export interface S3RemoteObject {
  key: string;
  size: number;
  lastModified: string;
}

export interface S3CanonicalParts {
  canonicalUri: string;
  canonicalQuery: string;
  canonicalHeaders: string;
  signedHeaders: string;
  canonicalRequest: string;
}

export function encodeS3Segment(seg: string): string {
  return encodeURIComponent(seg).replace(/[!'()*]/g, (c: string): string => '%' + c.charCodeAt(0).toString(16).toUpperCase());
}

export function encodeS3Path(path: string): string {
  const clean = path.startsWith('/') ? path : '/' + path;
  return clean.split('/').map((seg: string): string => encodeS3Segment(seg)).join('/');
}

export function buildS3CanonicalRequest(
  method: string,
  path: string,
  queryParams: Record<string, string>,
  headers: Record<string, string>,
  payloadHashHex: string
): S3CanonicalParts {
  const canonicalUri = encodeS3Path(path);
  const qKeys = Object.keys(queryParams).sort();
  const canonicalQuery = qKeys.map((k: string): string =>
    encodeS3Segment(k) + '=' + encodeS3Segment(queryParams[k])
  ).join('&');

  const lowerHeaders = new Map<string, string>();
  Object.keys(headers).forEach((k: string) => {
    lowerHeaders.set(k.toLowerCase().trim(), headers[k].trim().replace(/\s+/g, ' '));
  });
  const sortedKeys = Array.from(lowerHeaders.keys()).sort();
  const canonicalHeaders = sortedKeys.map((k: string): string => k + ':' + (lowerHeaders.get(k) || '') + '\n').join('');
  const signedHeaders = sortedKeys.join(';');
  const canonicalRequest = [
    method.toUpperCase(),
    canonicalUri,
    canonicalQuery,
    canonicalHeaders,
    signedHeaders,
    payloadHashHex
  ].join('\n');

  return {
    canonicalUri,
    canonicalQuery,
    canonicalHeaders,
    signedHeaders,
    canonicalRequest
  };
}

export interface AmzDateStamp {
  amzDate: string;
  dateStamp: string;
}

export function formatAmzDate(date: Date): AmzDateStamp {
  const iso = date.toISOString().replace(/[-:]/g, '').replace(/\.\d{3}Z$/, 'Z');
  return { amzDate: iso, dateStamp: iso.slice(0, 8) };
}

function extractXmlTag(xml: string, tag: string): string {
  const m = xml.match(new RegExp('<' + tag + '>([\\s\\S]*?)</' + tag + '>', 'i'));
  return m ? m[1].trim() : '';
}

export function parseS3ListXml(xml: string): S3RemoteObject[] {
  const out: S3RemoteObject[] = [];
  const blockRegex = /<Contents>([\s\S]*?)<\/Contents>/gi;
  let m = blockRegex.exec(xml);
  while (m) {
    const inner = m[1];
    const key = extractXmlTag(inner, 'Key');
    const size = Number(extractXmlTag(inner, 'Size')) || 0;
    const lastModified = extractXmlTag(inner, 'LastModified');
    if (key) out.push({ key, size, lastModified });
    m = blockRegex.exec(xml);
  }
  return out;
}
