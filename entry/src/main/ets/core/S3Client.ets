import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { S3BackupConfig, checkEndpoint } from './Models';
import { bytesToHex, hmacSha256, sha256Hex } from './BackupCrypto';
import {
  S3RemoteObject,
  buildS3CanonicalRequest,
  encodeS3Path,
  formatAmzDate,
  parseS3ListXml
} from './S3SigV4';

interface S3TargetLocation {
  url: string;
  host: string;
  canonicalPath: string;
}

export class S3Client {
  private cfg: S3BackupConfig;
  private secretAccessKey: string;
  private sessionToken: string;

  constructor(cfg: S3BackupConfig, secretAccessKey: string, sessionToken: string = '') {
    this.cfg = cfg;
    this.secretAccessKey = secretAccessKey;
    this.sessionToken = sessionToken.trim();
  }

  private resolveTarget(objectKey: string, queryParams: Record<string, string>): S3TargetLocation {
    const cleanEndpoint = checkEndpoint(this.cfg.endpoint);
    const m = cleanEndpoint.match(/^(https?:)\/\/([^\/]+)(.*)$/i);
    if (!m) throw new Error('S3 Endpoint 格式无效');
    const scheme = m[1];
    const baseHost = m[2];
    const basePath = m[3].replace(/\/+$/, '');
    const bucket = this.cfg.bucket.trim();
    if (!bucket) throw new Error('请填写 S3 Bucket 名称');

    const cleanKey = objectKey.replace(/^\/+/, '');
    let host = baseHost;
    let rawPath = basePath;
    if (this.cfg.pathStyle) {
      rawPath = basePath + '/' + bucket + (cleanKey ? '/' + cleanKey : '');
    } else {
      host = bucket + '.' + baseHost;
      rawPath = basePath + (cleanKey ? '/' + cleanKey : '/');
    }
    if (!rawPath) rawPath = '/';

    const qKeys = Object.keys(queryParams).sort();
    const qs = qKeys.map((k: string): string => encodeURIComponent(k) + '=' + encodeURIComponent(queryParams[k])).join('&');
    const url = scheme + '//' + host + encodeS3Path(rawPath) + (qs ? '?' + qs : '');
    return { url, host, canonicalPath: rawPath };
  }

  private async signedHeaders(
    method: string,
    loc: S3TargetLocation,
    queryParams: Record<string, string>,
    body: string | Uint8Array,
    extraHeaders?: Record<string, string>
  ): Promise<Record<string, string>> {
    const stamps = formatAmzDate(new Date());
    const payloadHash = await sha256Hex(body);
    const region = this.cfg.region.trim() || 'us-east-1';
    const hdrs: Record<string, string> = {
      'host': loc.host,
      'x-amz-date': stamps.amzDate,
      'x-amz-content-sha256': payloadHash
    };
    if (this.sessionToken) {
      hdrs['x-amz-security-token'] = this.sessionToken;
    }
    if (this.cfg.userAgent && this.cfg.userAgent.trim()) {
      hdrs['user-agent'] = this.cfg.userAgent.trim();
    }
    if (extraHeaders) {
      Object.keys(extraHeaders).forEach((k: string) => {
        hdrs[k.toLowerCase()] = extraHeaders[k];
      });
    }
    const canonical = buildS3CanonicalRequest(method, loc.canonicalPath, queryParams, hdrs, payloadHash);
    const scope = stamps.dateStamp + '/' + region + '/s3/aws4_request';
    const canonicalHash = await sha256Hex(canonical.canonicalRequest);
    const stringToSign = ['AWS4-HMAC-SHA256', stamps.amzDate, scope, canonicalHash].join('\n');

    const enc = util.TextEncoder.create();
    const kDate = await hmacSha256(enc.encodeInto('AWS4' + this.secretAccessKey), stamps.dateStamp);
    const kRegion = await hmacSha256(kDate, region);
    const kService = await hmacSha256(kRegion, 's3');
    const kSigning = await hmacSha256(kService, 'aws4_request');
    const signature = bytesToHex(await hmacSha256(kSigning, stringToSign));

    hdrs['Authorization'] = 'AWS4-HMAC-SHA256 Credential=' + this.cfg.accessKeyId.trim() + '/' + scope +
      ', SignedHeaders=' + canonical.signedHeaders + ', Signature=' + signature;
    return hdrs;
  }

  private fullKey(fileName: string): string {
    const p = this.cfg.prefix.trim().replace(/^\/+|\/+$/g, '');
    return p ? p + '/' + fileName : fileName;
  }

  async testConnection(): Promise<void> {
    await this.listObjects('1');
  }

  async listObjects(maxKeys: string = ''): Promise<S3RemoteObject[]> {
    const query: Record<string, string> = { 'list-type': '2' };
    const p = this.cfg.prefix.trim().replace(/^\/+|\/+$/g, '');
    if (p) query['prefix'] = p + '/';
    if (maxKeys) query['max-keys'] = maxKeys;
    const loc = this.resolveTarget('', query);
    const hdrs = await this.signedHeaders('GET', loc, query, '');
    const req = http.createHttp();
    try {
      const resp = await req.request(loc.url, {
        method: http.RequestMethod.GET,
        header: hdrs,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 30000,
        usingCache: false
      });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new Error('S3 列表失败 HTTP ' + resp.responseCode);
      }
      const list = parseS3ListXml(resp.result as string);
      return list.sort((a: S3RemoteObject, b: S3RemoteObject): number => {
        const ta = a.lastModified ? Date.parse(a.lastModified) : 0;
        const tb = b.lastModified ? Date.parse(b.lastModified) : 0;
        if (ta && tb && ta !== tb) return tb - ta;
        return b.key.localeCompare(a.key);
      });
    } finally {
      req.destroy();
    }
  }

  async putObject(fileName: string, content: string): Promise<void> {
    await this.putBytes(fileName, util.TextEncoder.create('utf-8').encodeInto(content), 'application/json');
  }

  async putBytes(fileName: string, bytes: Uint8Array, contentType: string = 'application/octet-stream'): Promise<void> {
    const key = this.fullKey(fileName);
    const emptyQ: Record<string, string> = {};
    const loc = this.resolveTarget(key, emptyQ);
    const extra: Record<string, string> = { 'content-type': contentType };
    const hdrs = await this.signedHeaders('PUT', loc, emptyQ, bytes, extra);
    const req = http.createHttp();
    try {
      const bodyBuf = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
      const resp = await req.request(loc.url, {
        method: http.RequestMethod.PUT,
        header: hdrs,
        extraData: bodyBuf,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 60000,
        usingCache: false
      });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new Error('S3 上传失败 HTTP ' + resp.responseCode);
      }
    } finally {
      req.destroy();
    }
  }

  async getObject(objectKey: string): Promise<string> {
    const bytes = await this.getBytes(objectKey);
    return util.TextDecoder.create('utf-8').decodeToString(bytes);
  }

  async getBytes(objectKey: string): Promise<Uint8Array> {
    const emptyQ: Record<string, string> = {};
    const loc = this.resolveTarget(objectKey, emptyQ);
    const hdrs = await this.signedHeaders('GET', loc, emptyQ, '');
    const req = http.createHttp();
    try {
      const resp = await req.request(loc.url, {
        method: http.RequestMethod.GET,
        header: hdrs,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        maxLimit: 128 * 1024 * 1024,
        connectTimeout: 15000,
        readTimeout: 60000,
        usingCache: false
      });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new Error('S3 下载失败 HTTP ' + resp.responseCode);
      }
      if (resp.result instanceof ArrayBuffer) {
        return new Uint8Array(resp.result);
      }
      return util.TextEncoder.create('utf-8').encodeInto(String(resp.result || ''));
    } finally {
      req.destroy();
    }
  }

  async deleteObject(objectKey: string): Promise<void> {
    const emptyQ: Record<string, string> = {};
    const loc = this.resolveTarget(objectKey, emptyQ);
    const hdrs = await this.signedHeaders('DELETE', loc, emptyQ, '');
    const req = http.createHttp();
    try {
      const resp = await req.request(loc.url, {
        method: http.RequestMethod.DELETE,
        header: hdrs,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 30000,
        usingCache: false
      });
      if (resp.responseCode < 200 || resp.responseCode >= 300) {
        throw new Error('S3 删除失败 HTTP ' + resp.responseCode);
      }
    } finally {
      req.destroy();
    }
  }
}
