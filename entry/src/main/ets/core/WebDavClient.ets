import { rcp } from '@kit.RemoteCommunicationKit';
import { util } from '@kit.ArkTS';
import { checkEndpoint } from './Models';

export interface WebDavRemoteItem {
  name: string;
  href: string;
  sizeBytes: number;
  lastModified: string;
  isDir: boolean;
}

export function parseWebDavPropfindXml(xml: string, baseDirUrl: string): WebDavRemoteItem[] {
  const out: WebDavRemoteItem[] = [];
  const respRegex = /<(?:[a-z0-9]+:)?response\b[^>]*>([\s\S]*?)<\/(?:[a-z0-9]+:)?response>/gi;
  const cleanBasePath = baseDirUrl.replace(/^https?:\/\/[^\/]+/i, '').replace(/\/+$/, '');
  let m = respRegex.exec(xml);
  while (m) {
    const block = m[1];
    const hrefMatch = block.match(/<(?:[a-z0-9]+:)?href\b[^>]*>([\s\S]*?)<\/(?:[a-z0-9]+:)?href>/i);
    const lenMatch = block.match(/<(?:[a-z0-9]+:)?getcontentlength\b[^>]*>(\d+)<\/(?:[a-z0-9]+:)?getcontentlength>/i);
    const modMatch = block.match(/<(?:[a-z0-9]+:)?getlastmodified\b[^>]*>([\s\S]*?)<\/(?:[a-z0-9]+:)?getlastmodified>/i);
    const isDir = /<(?:[a-z0-9]+:)?collection\b/i.test(block);
    if (hrefMatch) {
      let rawHref = hrefMatch[1].trim();
      try { rawHref = decodeURIComponent(rawHref); } catch (_) {}
      const relPath = rawHref.replace(/^https?:\/\/[^\/]+/i, '').replace(/\/+$/, '');
      if (relPath !== cleanBasePath && !isDir) {
        const name = relPath.split('/').pop() || rawHref;
        if (name && !name.startsWith('.')) {
          out.push({
            name,
            href: rawHref,
            sizeBytes: lenMatch ? Number(lenMatch[1]) || 0 : 0,
            lastModified: modMatch ? modMatch[1].trim() : '',
            isDir
          });
        }
      }
    }
    m = respRegex.exec(xml);
  }
  return out;
}

export function sortWebDavItems(items: WebDavRemoteItem[]): WebDavRemoteItem[] {
  return items.slice().sort((a: WebDavRemoteItem, b: WebDavRemoteItem): number => {
    const ta = a.lastModified ? Date.parse(a.lastModified) : 0;
    const tb = b.lastModified ? Date.parse(b.lastModified) : 0;
    if (ta && tb && ta !== tb) return tb - ta;
    if (ta && !tb) return -1;
    if (!ta && tb) return 1;
    return b.name.localeCompare(a.name);
  });
}

export function resolveWebDavDirUrl(serverUrl: string, remotePath: string = ''): string {
  const base = checkEndpoint(serverUrl).replace(/\/+$/, '');
  const cleanPath = remotePath.trim().replace(/^\/+|\/+$/g, '');
  if (!cleanPath) return base;
  if (base.endsWith('/' + cleanPath)) return base;
  return base + '/' + cleanPath;
}

export class WebDavClient {
  private serverBaseUrl: string;
  private remotePath: string;
  private dirUrl: string;
  private username: string;
  private password: string;
  private userAgent: string;

  constructor(dirUrlOrServer: string, username: string, password: string, remotePath: string = '', userAgent: string = '') {
    this.serverBaseUrl = checkEndpoint(dirUrlOrServer).replace(/\/+$/, '');
    this.remotePath = remotePath.trim().replace(/^\/+|\/+$/g, '');
    this.dirUrl = resolveWebDavDirUrl(this.serverBaseUrl, this.remotePath);
    this.username = username.trim();
    this.password = password;
    this.userAgent = userAgent.trim();
  }

  private authHeader(): string {
    if (!this.username) return '';
    const bytes = util.TextEncoder.create().encodeInto(this.username + ':' + this.password);
    return 'Basic ' + new util.Base64Helper().encodeToStringSync(bytes);
  }

  private buildHeaders(extra?: Record<string, string>): rcp.RequestHeaders {
    const headers: rcp.RequestHeaders = {};
    const auth = this.authHeader();
    if (auth) headers['authorization'] = auth;
    if (this.userAgent) headers['user-agent'] = this.userAgent;
    if (extra) {
      Object.keys(extra).forEach((k: string) => {
        headers[k.toLowerCase()] = extra[k];
      });
    }
    return headers;
  }

  async testConnection(): Promise<void> {
    const session = rcp.createSession();
    try {
      const propBody = '<?xml version="1.0" encoding="utf-8" ?>' +
        '<d:propfind xmlns:d="DAV:"><d:prop><d:displayname/></d:prop></d:propfind>';
      const extra: Record<string, string> = {};
      extra['depth'] = '1';
      extra['content-type'] = 'application/xml; charset=utf-8';
      const req = new rcp.Request(this.dirUrl + '/', 'PROPFIND', this.buildHeaders(extra), propBody);
      const resp = await session.fetch(req);
      if (resp.statusCode === 401) {
        throw new Error('WebDAV 认证失败：用户名或密码错误 (HTTP 401)');
      }
      if (resp.statusCode !== 207 && (resp.statusCode < 200 || resp.statusCode >= 300)) {
        throw new Error('WebDAV 连接测试失败 HTTP ' + resp.statusCode);
      }
    } finally {
      session.close();
    }
  }

  async ensureDirectory(): Promise<void> {
    const session = rcp.createSession();
    try {
      if (this.remotePath) {
        const segs = this.remotePath.split('/').filter((s: string): boolean => s.trim().length > 0);
        let acc = this.serverBaseUrl;
        for (let i = 0; i < segs.length; i++) {
          acc = acc + '/' + encodeURIComponent(segs[i]);
          const propBody = '<?xml version="1.0" encoding="utf-8" ?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/></d:prop></d:propfind>';
          const extra: Record<string, string> = {};
          extra['depth'] = '0';
          extra['content-type'] = 'application/xml; charset=utf-8';
          const checkResp = await session.fetch(new rcp.Request(acc + '/', 'PROPFIND', this.buildHeaders(extra), propBody));
          if (checkResp.statusCode === 404) {
            const mkResp = await session.fetch(new rcp.Request(acc + '/', 'MKCOL', this.buildHeaders()));
            if (mkResp.statusCode !== 200 && mkResp.statusCode !== 201 && mkResp.statusCode !== 405) {
              throw new Error('WebDAV MKCOL 失败 HTTP ' + mkResp.statusCode);
            }
          } else if (checkResp.statusCode === 401) {
            throw new Error('WebDAV 认证失败 (HTTP 401)');
          }
        }
      } else {
        const req = new rcp.Request(this.dirUrl + '/', 'MKCOL', this.buildHeaders());
        await session.fetch(req);
      }
    } finally {
      session.close();
    }
  }

  async listFiles(): Promise<WebDavRemoteItem[]> {
    const session = rcp.createSession();
    try {
      const propBody = '<?xml version="1.0" encoding="utf-8" ?>' +
        '<d:propfind xmlns:d="DAV:"><d:prop><d:getcontentlength/><d:getlastmodified/><d:resourcetype/></d:prop></d:propfind>';
      const extra: Record<string, string> = {};
      extra['depth'] = '1';
      extra['content-type'] = 'application/xml';
      const hdrs = this.buildHeaders(extra);
      const req = new rcp.Request(this.dirUrl + '/', 'PROPFIND', hdrs, propBody);
      const resp = await session.fetch(req);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw new Error('WebDAV PROPFIND 返回 HTTP ' + resp.statusCode);
      }
      const xml = resp.toString() || '';
      return sortWebDavItems(parseWebDavPropfindXml(xml, this.dirUrl));
    } finally {
      session.close();
    }
  }

  async putFile(fileName: string, content: string): Promise<void> {
    await this.putBytes(fileName, util.TextEncoder.create('utf-8').encodeInto(content), 'application/json');
  }

  async putBytes(fileName: string, bytes: Uint8Array, contentType: string = 'application/octet-stream'): Promise<void> {
    await this.ensureDirectory();
    const session = rcp.createSession();
    try {
      const extra: Record<string, string> = {};
      extra['content-type'] = contentType;
      const hdrs = this.buildHeaders(extra);
      const bodyBuf = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
      const req = new rcp.Request(this.dirUrl + '/' + encodeURIComponent(fileName), 'PUT', hdrs, bodyBuf);
      const resp = await session.fetch(req);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw new Error('WebDAV 上传失败 HTTP ' + resp.statusCode);
      }
    } finally {
      session.close();
    }
  }

  async getFile(fileName: string): Promise<string> {
    const bytes = await this.getBytes(fileName);
    return util.TextDecoder.create('utf-8').decodeToString(bytes);
  }

  async getBytes(fileName: string): Promise<Uint8Array> {
    const session = rcp.createSession();
    try {
      const req = new rcp.Request(this.dirUrl + '/' + encodeURIComponent(fileName), 'GET', this.buildHeaders());
      const resp = await session.fetch(req);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw new Error('WebDAV 下载失败 HTTP ' + resp.statusCode);
      }
      if (resp.body && resp.body.byteLength > 0) {
        return new Uint8Array(resp.body);
      }
      return util.TextEncoder.create('utf-8').encodeInto(resp.toString() || '');
    } finally {
      session.close();
    }
  }

  async deleteFile(fileName: string): Promise<void> {
    const session = rcp.createSession();
    try {
      const req = new rcp.Request(this.dirUrl + '/' + encodeURIComponent(fileName), 'DELETE', this.buildHeaders());
      const resp = await session.fetch(req);
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw new Error('WebDAV 删除失败 HTTP ' + resp.statusCode);
      }
    } finally {
      session.close();
    }
  }
}
