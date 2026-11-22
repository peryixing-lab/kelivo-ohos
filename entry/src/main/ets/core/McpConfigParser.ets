import { HeaderEntry, McpServerConfig } from './Models';

interface RawMcpServerNode {
  url?: string;
  endpoint?: string;
  transport?: string;
  type?: string;
  headers?: Record<string, string>;
  bearer?: string;
}

interface RawMcpRoot {
  mcpServers?: Record<string, RawMcpServerNode>;
  servers?: Record<string, RawMcpServerNode>;
}

export interface ImportedMcpServer {
  config: McpServerConfig;
  bearerToken: string;
}

export function parseMcpConfigJson(raw: string, idFactory: () => string): ImportedMcpServer[] {
  const parsed = JSON.parse(raw) as RawMcpRoot;
  const mapObj = parsed.mcpServers || parsed.servers;
  if (!mapObj || typeof mapObj !== 'object') {
    throw new Error('未在 JSON 中找到 mcpServers 或 servers 字段');
  }
  const out: ImportedMcpServer[] = [];
  Object.keys(mapObj).forEach((name: string) => {
    const node = mapObj[name];
    const url = (node.url || node.endpoint || '').trim();
    if (!url || !/^https?:\/\//i.test(url)) return;
    const rawType = (node.transport || node.type || '').toLowerCase();
    const transport: 'streamable-http' | 'sse' = rawType === 'sse' || url.endsWith('/sse') ? 'sse' : 'streamable-http';
    const customHeaders: HeaderEntry[] = [];
    let bearer = node.bearer || '';
    if (node.headers && typeof node.headers === 'object') {
      Object.keys(node.headers).forEach((hk: string) => {
        const hv = String(node.headers![hk] || '');
        if (hk.toLowerCase() === 'authorization' && hv.toLowerCase().startsWith('bearer ')) {
          bearer = hv.slice(7).trim();
        } else {
          customHeaders.push({ key: hk, value: hv });
        }
      });
    }
    out.push({
      config: {
        id: idFactory(),
        name,
        transport,
        endpoint: url,
        bearerSecretRef: '',
        customHeaders,
        enabled: true,
        disabledTools: [],
        autoApproveTools: []
      },
      bearerToken: bearer
    });
  });
  if (!out.length) throw new Error('JSON 中没有包含有效的 HTTP/SSE MCP 服务器地址');
  return out;
}
