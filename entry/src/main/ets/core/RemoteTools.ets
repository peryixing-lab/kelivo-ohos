import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { EventReader } from './Protocol';
import { Attachment, HeaderEntry, McpServerConfig, checkEndpoint } from './Models';
import { fetchWebPage } from './WebSearch';
import { readKey } from './Storage';

export interface McpTool {
  name: string;
  description?: string;
  inputSchema: Object;
  serverId?: string;
  serverName?: string;
}

export interface McpInvocationResult {
  text: string;
  images: Attachment[];
}

interface ToolContent {
  type: string;
  text?: string;
  uri?: string;
  data?: string;
  mimeType?: string;
}
interface RpcResult {
  protocolVersion?: string;
  tools?: McpTool[];
  nextCursor?: string;
  content?: ToolContent[];
  structuredContent?: Object;
  isError?: boolean;
}
interface RpcError { message: string }
interface RpcReply { jsonrpc: string; id?: number; result?: RpcResult; error?: RpcError }
interface RpcRequest { jsonrpc: string; method: string; params?: Object; id?: number }
interface ClientInfo { name: string; version: string }
interface InitializeParams { protocolVersion: string; capabilities: Record<string, Object>; clientInfo: ClientInfo }
interface ToolCallParams { name: string; arguments: Object }
interface ListParams { cursor: string }

export class RemoteTools {
  private endpoint: string;
  private bearer: string;
  private transport: 'streamable-http' | 'sse';
  private customHeaders: HeaderEntry[];
  private session: string = '';
  private protocol: string = '';
  private ssePostUrl: string = '';
  private seq: number = 0;
  private active?: http.HttpRequest;
  private sseStreamReq?: http.HttpRequest;
  private pendingSseReplies: Map<number, (reply: RpcReply) => void> = new Map<number, (reply: RpcReply) => void>();
  private closed: boolean = false;

  constructor(
    endpoint: string,
    bearer: string,
    transport: 'streamable-http' | 'sse' = 'streamable-http',
    customHeaders: HeaderEntry[] = []
  ) {
    this.endpoint = checkEndpoint(endpoint);
    this.bearer = bearer;
    this.transport = transport;
    this.customHeaders = customHeaders;
  }

  private headers(): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'Accept': 'application/json, text/event-stream'
    };
    for (let i = 0; i < this.customHeaders.length; i++) {
      const k = this.customHeaders[i].key.trim();
      if (k) headers[k] = this.customHeaders[i].value;
    }
    if (this.bearer) headers['Authorization'] = 'Bearer ' + this.bearer;
    if (this.session) headers['Mcp-Session-Id'] = this.session;
    if (this.protocol) headers['MCP-Protocol-Version'] = this.protocol;
    return headers;
  }

  async close(): Promise<void> {
    this.closed = true;
    this.active?.destroy();
    this.active = undefined;
    this.sseStreamReq?.destroy();
    this.sseStreamReq = undefined;
    this.pendingSseReplies.clear();
    if (!this.session) return;
    const req = http.createHttp();
    try {
      await req.request(this.endpoint, {
        method: http.RequestMethod.DELETE,
        header: this.headers(),
        readTimeout: 4000,
        connectTimeout: 4000,
        maxRedirects: 0
      });
    } finally { req.destroy(); this.session = ''; this.bearer = ''; }
  }

  private resolveSsePostTarget(endpointPayload: string): string {
    const trimmed = endpointPayload.trim();
    if (/^https?:\/\//i.test(trimmed)) return trimmed;
    const match = this.endpoint.match(/^(https?:\/\/[^\/]+)/i);
    const origin = match ? match[1] : this.endpoint;
    if (trimmed.startsWith('/')) return origin + trimmed;
    const baseDir = this.endpoint.slice(0, this.endpoint.lastIndexOf('/') + 1);
    return baseDir + trimmed;
  }

  private async ensureSseConnected(): Promise<void> {
    if (this.ssePostUrl && this.sseStreamReq) return;
    const req = http.createHttp();
    this.sseStreamReq = req;
    const decoder = util.TextDecoder.create('utf-8');
    let buffer = '';
    let currentEvent = 'message';
    let dataLines: string[] = [];

    await new Promise<void>((resolve, reject) => {
      let resolved = false;
      const timer = setTimeout(() => {
        if (!resolved) {
          resolved = true;
          reject(new Error('SSE MCP 握手超时'));
        }
      }, 12000);

      const dispatchEvent = (evtName: string, data: string): void => {
        if (evtName === 'endpoint') {
          this.ssePostUrl = this.resolveSsePostTarget(data);
          if (!resolved) {
            resolved = true;
            clearTimeout(timer);
            resolve();
          }
          return;
        }
        try {
          const reply = JSON.parse(data) as RpcReply;
          if (reply.id !== undefined) {
            const waiter = this.pendingSseReplies.get(reply.id);
            if (waiter) {
              this.pendingSseReplies.delete(reply.id);
              waiter(reply);
            }
          }
        } catch (_) {}
      };

      const feedLine = (line: string): void => {
        if (line.startsWith('event:')) {
          currentEvent = line.slice(6).trim();
        } else if (line.startsWith('data:')) {
          dataLines.push(line.slice(5).replace(/^ /, ''));
        } else if (!line && dataLines.length > 0) {
          const payload = dataLines.join('\n');
          const evt = currentEvent;
          currentEvent = 'message';
          dataLines = [];
          dispatchEvent(evt, payload);
        }
      };

      req.on('dataReceive', (chunk: ArrayBuffer) => {
        buffer += decoder.decodeToString(new Uint8Array(chunk), { stream: true });
        let cut = buffer.indexOf('\n');
        while (cut >= 0) {
          feedLine(buffer.slice(0, cut).replace(/\r$/, ''));
          buffer = buffer.slice(cut + 1);
          cut = buffer.indexOf('\n');
        }
      });
      req.on('dataEnd', () => {
        if (!resolved) {
          resolved = true;
          clearTimeout(timer);
          reject(new Error('SSE 流提前结束'));
        }
      });
      const sseHeaders = this.headers();
      sseHeaders['Accept'] = 'text/event-stream';
      req.requestInStream(this.endpoint, {
        method: http.RequestMethod.GET,
        header: sseHeaders,
        connectTimeout: 12000,
        readTimeout: 300000,
        usingCache: false
      }).then((code: number) => {
        if ((code < 200 || code >= 300) && !resolved) {
          resolved = true;
          clearTimeout(timer);
          reject(new Error('SSE MCP 返回 HTTP ' + code));
        }
      }).catch((err: Error) => {
        if (!resolved) {
          resolved = true;
          clearTimeout(timer);
          reject(err);
        }
      });
    });
  }

  private async post(method: string, params?: Object, notify: boolean = false): Promise<RpcResult> {
    if (this.closed) throw new Error('连接已关闭');
    if (this.transport === 'sse') {
      await this.ensureSseConnected();
    }
    const targetUrl = this.transport === 'sse' && this.ssePostUrl ? this.ssePostUrl : this.endpoint;
    const req = http.createHttp();
    this.active = req;
    try {
      const id = ++this.seq;
      const message: RpcRequest = { jsonrpc: '2.0', method, params };
      if (!notify) message.id = id;

      let waitSse: Promise<RpcReply> | undefined = undefined;
      if (this.transport === 'sse' && !notify) {
        waitSse = new Promise<RpcReply>((resolve, reject) => {
          const timer = setTimeout(() => {
            this.pendingSseReplies.delete(id);
            reject(new Error('SSE 工具响应超时'));
          }, 45000);
          this.pendingSseReplies.set(id, (r: RpcReply) => {
            clearTimeout(timer);
            resolve(r);
          });
        });
      }

      const response = await req.request(targetUrl, {
        method: http.RequestMethod.POST,
        header: this.headers(),
        extraData: JSON.stringify(message),
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        maxRedirects: 0,
        connectTimeout: 12000,
        readTimeout: 45000
      });
      if (response.responseCode < 200 || response.responseCode > 299) {
        throw new Error('MCP 服务返回 HTTP ' + response.responseCode);
      }
      if (method === 'initialize') {
        const h = response.header as Record<string, string>;
        Object.keys(h).forEach((k: string) => { if (k.toLowerCase() === 'mcp-session-id') this.session = h[k]; });
      }
      if (notify) return {};
      const body = ((response.result as string) || '').trim();
      if (this.transport === 'sse' && !body.startsWith('{') && waitSse) {
        const sseReply = await waitSse;
        if (sseReply.error) throw new Error(sseReply.error.message || '工具调用失败');
        if (!sseReply.result) throw new Error('未收到对应的 SSE MCP 响应');
        return sseReply.result;
      }

      const replies: RpcReply[] = [];
      if (body.startsWith('{')) replies.push(JSON.parse(body) as RpcReply);
      else {
        const events = new EventReader((data: string) => { replies.push(JSON.parse(data) as RpcReply); });
        events.push(body);
        events.finish();
      }
      const reply = replies.find((r: RpcReply): boolean => r.id === id && r.jsonrpc === '2.0');
      if (reply?.error) throw new Error(reply.error.message || '工具调用失败');
      if (!reply?.result) throw new Error('未收到对应的 MCP 响应');
      return reply.result;
    } finally { if (this.active === req) { req.destroy(); this.active = undefined; } }
  }

  async discover(): Promise<McpTool[]> {
    const init: InitializeParams = {
      protocolVersion: '2025-06-18',
      capabilities: {},
      clientInfo: { name: 'kelivo', version: '1.0.0' }
    };
    const reply = await this.post('initialize', init);
    if (!reply.protocolVersion) {
      throw new Error('服务端未协商到有效的 MCP 协议版本');
    }
    this.protocol = reply.protocolVersion;
    await this.post('notifications/initialized', undefined, true);
    const list: McpTool[] = [];
    let cursor = '';
    const seen = new Set<string>();
    do {
      if (seen.has(cursor)) throw new Error('工具列表分页重复');
      seen.add(cursor);
      const params: ListParams = { cursor };
      const page = await this.post('tools/list', cursor ? params : undefined);
      if (!Array.isArray(page.tools)) throw new Error('服务端没有返回工具清单');
      list.push(...page.tools);
      cursor = page.nextCursor || '';
    } while (cursor);
    return list;
  }

  async callRich(name: string, json: string): Promise<McpInvocationResult> {
    const args = JSON.parse(json) as Object;
    if (args === null || typeof args !== 'object' || Array.isArray(args)) throw new Error('参数须为 JSON 对象');
    const params: ToolCallParams = { name, arguments: args };
    const reply = await this.post('tools/call', params);
    const textParts: string[] = [];
    const images: Attachment[] = [];
    if (reply.content) {
      for (let i = 0; i < reply.content.length; i++) {
        const part = reply.content[i];
        if (part.type === 'image' && part.data) {
          images.push({
            name: name + '-img-' + (i + 1) + '.png',
            mime: part.mimeType || 'image/png',
            data: part.data,
            kind: 'image'
          });
        } else if (part.text || part.uri) {
          textParts.push(part.text || part.uri || '');
        }
      }
    }
    const text = textParts.join('\n') ||
      (reply.structuredContent ? JSON.stringify(reply.structuredContent, null, 2) : '');
    if (reply.isError) throw new Error(text || '工具执行失败');
    if (!text && !images.length) throw new Error('该工具未返回可附加的内容');
    return { text: text || '[返回了 ' + images.length + ' 张图片]', images };
  }

  async call(name: string, json: string): Promise<string> {
    const res = await this.callRich(name, json);
    return res.text;
  }
}

export class McpManager {
  private clients: Map<string, RemoteTools> = new Map<string, RemoteTools>();
  private discovered: Map<string, McpTool[]> = new Map<string, McpTool[]>();

  static builtinFetchTool(): McpTool {
    const schema: Record<string, Object> = {};
    schema['type'] = 'object';
    const props: Record<string, Object> = {};
    const urlProp: Record<string, Object> = {};
    urlProp['type'] = 'string';
    urlProp['description'] = '要抓取的网页 HTTP/HTTPS URL';
    props['url'] = urlProp;
    const maxProp: Record<string, Object> = {};
    maxProp['type'] = 'integer';
    maxProp['description'] = '最多返回字符数，默认 8000';
    props['max_chars'] = maxProp;
    const offProp: Record<string, Object> = {};
    offProp['type'] = 'integer';
    offProp['description'] = '分页偏移量，默认 0';
    props['offset'] = offProp;
    schema['properties'] = props;
    schema['required'] = ['url'];
    return {
      name: 'kelivo_fetch_url',
      description: '内置网页抓取器：读取指定 URL 的正文并转为可读纯文本，支持分页读取。',
      inputSchema: schema,
      serverId: 'builtin-kelivo-fetch',
      serverName: 'kelivo-fetch（内置）'
    };
  }

  async connectServer(cfg: McpServerConfig): Promise<McpTool[]> {
    await this.disconnectServer(cfg.id);
    let token = '';
    if (cfg.oauthAccessTokenRef) token = await readKey(cfg.oauthAccessTokenRef);
    if (!token && cfg.bearerSecretRef) token = await readKey(cfg.bearerSecretRef);
    const client = new RemoteTools(cfg.endpoint, token, cfg.transport, cfg.customHeaders);
    const tools = await client.discover();
    const tagged = tools.map((t: McpTool): McpTool => {
      return {
        name: t.name,
        description: t.description,
        inputSchema: t.inputSchema,
        serverId: cfg.id,
        serverName: cfg.name
      };
    });
    this.clients.set(cfg.id, client);
    this.discovered.set(cfg.id, tagged);
    return tagged;
  }

  async disconnectServer(serverId: string): Promise<void> {
    const old = this.clients.get(serverId);
    this.clients.delete(serverId);
    if (old) await old.close().catch(() => {});
  }

  getCachedTools(serverId: string): McpTool[] {
    return this.discovered.get(serverId) || [];
  }

  async discoverEnabledServers(servers: McpServerConfig[]): Promise<McpTool[]> {
    const all: McpTool[] = [];
    for (let i = 0; i < servers.length; i++) {
      const s = servers[i];
      if (!s.enabled) continue;
      let tools = this.discovered.get(s.id);
      if (!tools) {
        try { tools = await this.connectServer(s); } catch (_) { tools = []; }
      }
      const disabled = new Set<string>(s.disabledTools || []);
      for (let j = 0; j < tools.length; j++) {
        if (!disabled.has(tools[j].name)) all.push(tools[j]);
      }
    }
    return all;
  }

  async invokeMcpTool(serverId: string, toolName: string, argsJson: string): Promise<McpInvocationResult> {
    if (serverId === 'builtin-kelivo-fetch' || toolName === 'kelivo_fetch_url') {
      const parsed = JSON.parse(argsJson) as Record<string, Object>;
      const url = String(parsed['url'] || '');
      const maxChars = Number(parsed['max_chars'] || 8000);
      const offset = Number(parsed['offset'] || 0);
      const text = await fetchWebPage(url, maxChars, offset);
      return { text, images: [] };
    }
    const client = this.clients.get(serverId);
    if (!client) throw new Error('MCP 服务器未连接: ' + serverId);
    return client.callRich(toolName, argsJson);
  }
}
