import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import {
  Attachment,
  ModelSpec,
  Provider,
  ProxyConfig,
  ReasoningEffort,
  RequestLogEntry,
  checkEndpoint,
  defaultModelSpec,
  findProviderModelSpec
} from './Models';
import {
  ChatCall,
  EventReader,
  Fragment,
  RichFragment,
  ThinkTagStreamParser,
  buildProviderHeaders,
  makeAdvancedChatCall,
  makeImageGenCall,
  parseImageGenResponse,
  parseRichReply
} from './Protocol';

interface ModelEntry { id?: string; name?: string; supportedGenerationMethods?: string[] }
interface ModelPage { data?: ModelEntry[]; models?: ModelEntry[]; nextPageToken?: string; has_more?: boolean; last_id?: string }
interface ApiErrorEnvelope { error?: ApiErrorDetail }
interface ApiErrorDetail { message?: string }

interface OllamaShowResp { capabilities?: string[] }
interface DeepSeekBalanceItem { currency?: string; total_balance?: string; is_available?: boolean }
interface DeepSeekBalanceResp { is_available?: boolean; balance_infos?: DeepSeekBalanceItem[] }
interface SiliconFlowData { balance?: string; totalBalance?: string; chargeBalance?: string }
interface SiliconFlowResp { data?: SiliconFlowData }
interface OpenRouterData { total_credits?: number; total_usage?: number }
interface OpenRouterResp { data?: OpenRouterData }

export interface StreamRunOptions {
  providerName?: string;
  modelId?: string;
  proxy?: ProxyConfig;
  proxyPassword?: string;
  maxRetries?: number;
  retryBaseMs?: number;
  onLog?: (log: RequestLogEntry) => void;
}

class HttpStatusError extends Error {
  status: number;
  rawBody: string;
  constructor(status: number, message: string, rawBody: string = '') {
    super(message);
    this.status = status;
    this.rawBody = rawBody;
  }
}

function statusError(status: number, body: string): HttpStatusError {
  let detail = '';
  try {
    detail = (JSON.parse(body) as ApiErrorEnvelope).error?.message?.slice(0, 400) || '';
  } catch (_) {}
  if (!detail && body.trim()) {
    detail = body.trim().slice(0, 240);
  }
  return new HttpStatusError(status, '服务商返回 HTTP ' + status + (detail ? ' · ' + detail : ''), body);
}

export function buildHttpProxy(proxy?: ProxyConfig, password?: string): http.HttpProxy | undefined {
  if (!proxy || !proxy.enabled || !proxy.host.trim() || proxy.port <= 0) return undefined;
  const cfg: http.HttpProxy = {
    host: proxy.host.trim(),
    port: proxy.port,
    exclusionList: []
  };
  if (proxy.username && proxy.username.trim()) {
    cfg.username = proxy.username.trim();
    if (password) cfg.password = password;
  }
  return cfg;
}

export function redactUrlSecrets(url: string): string {
  return url.replace(/([?&](?:key|api_key|token|access_token)=)[^&]+/gi, '$1***');
}

function isRetryableStatus(status: number): boolean {
  return status === 429 || status === 408 || status === 500 || status === 502 || status === 503 || status === 504;
}

function waitMs(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(() => resolve(), ms);
  });
}

export async function fetchModels(provider: Provider, key: string, proxyPassword?: string): Promise<string[]> {
  const base = checkEndpoint(provider.baseUrl) + '/models';
  const names: string[] = [];
  let next = base;
  const seen = new Set<string>();
  const proxyCfg = buildHttpProxy(provider.proxy, proxyPassword);
  while (next && !seen.has(next)) {
    seen.add(next);
    const req = http.createHttp();
    try {
      const opts: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: buildProviderHeaders(provider, key),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 25000,
        maxRedirects: 5,
        usingCache: false
      };
      if (proxyCfg) opts.usingProxy = proxyCfg;
      const response = await req.request(next, opts);
      const raw = response.result as string;
      if (response.responseCode < 200 || response.responseCode >= 300) throw statusError(response.responseCode, raw);
      const page = JSON.parse(raw) as ModelPage;
      const items = page.data ?? page.models;
      if (!Array.isArray(items)) throw new Error('服务商没有返回模型列表，可手动填写模型 ID。');
      items.forEach((entry: ModelEntry) => {
        if (entry.supportedGenerationMethods && !entry.supportedGenerationMethods.includes('generateContent')) return;
        const name = (entry.id || entry.name || '').replace(/^models\//, '');
        if (name) names.push(name);
      });
      next = '';
      if (provider.family === 'gemini' && page.nextPageToken) next = base + '?pageToken=' + encodeURIComponent(page.nextPageToken);
      if (provider.family === 'anthropic' && page.has_more && page.last_id) next = base + '?after_id=' + encodeURIComponent(page.last_id);
    } finally { req.destroy(); }
  }
  return Array.from(new Set(names)).sort();
}

export async function fetchOllamaCapabilities(baseUrl: string, modelId: string, proxy?: ProxyConfig): Promise<ModelSpec> {
  const spec = defaultModelSpec(modelId);
  const root = checkEndpoint(baseUrl).replace(/\/v1$/, '');
  const req = http.createHttp();
  try {
    const opts: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: { 'Content-Type': 'application/json' },
      extraData: JSON.stringify({ model: modelId }),
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 8000,
      readTimeout: 10000,
      usingCache: false
    };
    const pCfg = buildHttpProxy(proxy);
    if (pCfg) opts.usingProxy = pCfg;
    const resp = await req.request(root + '/api/show', opts);
    if (resp.responseCode >= 200 && resp.responseCode < 300) {
      const parsed = JSON.parse(resp.result as string) as OllamaShowResp;
      if (Array.isArray(parsed.capabilities)) {
        spec.vision = parsed.capabilities.includes('vision');
        spec.tools = parsed.capabilities.includes('tools');
        spec.reasoning = parsed.capabilities.includes('thinking') || spec.reasoning;
      }
    }
  } catch (_) {}
  finally { req.destroy(); }
  return spec;
}

export async function fetchProviderBalance(provider: Provider, key: string, proxyPassword?: string): Promise<string> {
  const base = checkEndpoint(provider.baseUrl);
  let url = provider.balanceUrl?.trim() || '';
  if (!url) {
    if (base.includes('api.deepseek.com')) url = 'https://api.deepseek.com/user/balance';
    else if (base.includes('api.siliconflow.cn')) url = 'https://api.siliconflow.cn/v1/user/info';
    else if (base.includes('openrouter.ai')) url = 'https://openrouter.ai/api/v1/credits';
    else throw new Error('该服务商未配置余额查询地址');
  }
  const req = http.createHttp();
  try {
    const headers = buildProviderHeaders(provider, key);
    headers['Accept'] = 'application/json';
    const opts: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: headers,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 10000,
      readTimeout: 15000,
      usingCache: false
    };
    const pCfg = buildHttpProxy(provider.proxy, proxyPassword);
    if (pCfg) opts.usingProxy = pCfg;
    const resp = await req.request(url, opts);
    const raw = resp.result as string;
    if (resp.responseCode < 200 || resp.responseCode >= 300) throw statusError(resp.responseCode, raw);
    if (url.includes('deepseek')) {
      const d = JSON.parse(raw) as DeepSeekBalanceResp;
      if (d.balance_infos?.length) {
        return d.balance_infos.map((b: DeepSeekBalanceItem): string => (b.total_balance || '0') + ' ' + (b.currency || '')).join(' / ');
      }
    }
    if (url.includes('siliconflow')) {
      const s = JSON.parse(raw) as SiliconFlowResp;
      if (s.data) return '余额: ' + (s.data.totalBalance || s.data.balance || s.data.chargeBalance || '0');
    }
    if (url.includes('openrouter')) {
      const o = JSON.parse(raw) as OpenRouterResp;
      if (o.data && o.data.total_credits !== undefined) {
        const remain = (o.data.total_credits - (o.data.total_usage || 0)).toFixed(4);
        return '$' + remain + ' (总额 $' + o.data.total_credits.toFixed(2) + ')';
      }
    }
    return raw.slice(0, 120);
  } finally {
    req.destroy();
  }
}

export class ChatStream {
  private abort?: () => void;
  private cancelled: boolean = false;

  stop(): void {
    this.cancelled = true;
    this.abort?.();
  }

  async run(call: ChatCall, onFragment: (fragment: Fragment) => void): Promise<void> {
    await this.runRich(call, (rich: RichFragment) => {
      if (rich.text || rich.reasoning) {
        onFragment({ text: rich.text, reasoning: rich.reasoning });
      }
    });
  }

  async runRich(
    call: ChatCall,
    onFragment: (fragment: RichFragment) => void,
    options?: StreamRunOptions
  ): Promise<void> {
    this.cancelled = false;
    const maxRetries = Math.max(0, options?.maxRetries ?? 0);
    const retryBase = Math.max(200, options?.retryBaseMs ?? 800);
    let attempt = 0;

    while (true) {
      let emittedAny = false;
      const startTs = Date.now();
      let capturedStatus = 0;
      let respPreview = '';
      let reasoningPreview = '';
      try {
        await this.runOnce(call, (frag: RichFragment) => {
          if (frag.text || frag.reasoning || frag.toolCalls.length || frag.generatedImages.length) {
            emittedAny = true;
            if (respPreview.length < 2000 && frag.text) respPreview += frag.text;
            if (reasoningPreview.length < 1800 && frag.reasoning) reasoningPreview += frag.reasoning;
          }
          onFragment(frag);
        }, (status: number) => {
          capturedStatus = status;
        }, options);

        const loggedResp = respPreview.length > 0
          ? respPreview.slice(0, 2000)
          : (reasoningPreview.length > 0 ? '[thinking_only] ' + reasoningPreview.slice(0, 1800) : '');
        options?.onLog?.({
          id: util.generateRandomUUID(true),
          ts: startTs,
          provider: options.providerName || '',
          model: options.modelId || '',
          url: redactUrlSecrets(call.address),
          status: capturedStatus || 200,
          durationMs: Date.now() - startTs,
          reqPreview: call.body.slice(0, 2000),
          respPreview: loggedResp,
          error: ''
        });
        return;
      } catch (err) {
        const errObj = err as Error;
        const status = err instanceof HttpStatusError ? err.status : capturedStatus;
        const errBody = err instanceof HttpStatusError && err.rawBody
          ? err.rawBody
          : (respPreview.length > 0 ? respPreview : (reasoningPreview.length > 0 ? '[thinking_only] ' + reasoningPreview : ''));
        options?.onLog?.({
          id: util.generateRandomUUID(true),
          ts: startTs,
          provider: options.providerName || '',
          model: options.modelId || '',
          url: redactUrlSecrets(call.address),
          status,
          durationMs: Date.now() - startTs,
          reqPreview: call.body.slice(0, 2000),
          respPreview: errBody.slice(0, 2000),
          error: errObj.message || '请求失败'
        });

        const canRetry = !this.cancelled && !emittedAny && attempt < maxRetries &&
          (status === 0 || isRetryableStatus(status));
        if (!canRetry) throw errObj;
        const delay = retryBase * Math.pow(2, attempt);
        attempt++;
        await waitMs(delay);
        if (this.cancelled) throw new Error('已停止生成');
      }
    }
  }

  private async runOnce(
    call: ChatCall,
    onFragment: (fragment: RichFragment) => void,
    onStatus: (status: number) => void,
    options?: StreamRunOptions
  ): Promise<void> {
    const req = http.createHttp();
    const decoder = util.TextDecoder.create('utf-8');
    const thinkParser = new ThinkTagStreamParser();
    let raw = '';
    let sawEvent = false;
    let bodyEnded = false;
    let status = 0;
    let closed = false;
    let streamParseErr: Error | undefined = undefined;

    const emitParsed = (data: string): void => {
      const part = parseRichReply(data);
      if (part.text) {
        const split = thinkParser.push(part.text);
        part.text = split.text;
        part.reasoning = (part.reasoning || '') + split.reasoning;
      }
      if (part.text || part.reasoning || part.toolCalls.length || part.generatedImages.length || part.usage || part.done) {
        onFragment(part);
      }
    };

    const reader = new EventReader((data: string) => {
      sawEvent = true;
      if (status > 0 && (status < 200 || status >= 300)) {
        return;
      }
      emitParsed(data);
    });

    try {
      await new Promise<void>((resolve, reject) => {
        const fail = (err: Error): void => { if (!closed) { closed = true; reject(err); } };
        this.abort = () => fail(new Error('已停止生成'));
        const complete = (): void => {
          if (closed || !bodyEnded || !status) return;
          try {
            onStatus(status);
            if (status < 200 || status >= 300) throw statusError(status, raw);
            if (streamParseErr) throw streamParseErr;
            reader.finish();
            if (!sawEvent && raw.trim()) {
              emitParsed(raw);
            }
            const flushed = thinkParser.flush();
            if (flushed.text || flushed.reasoning) {
              onFragment({
                text: flushed.text,
                reasoning: flushed.reasoning,
                toolCalls: [],
                generatedImages: [],
                done: true
              });
            }
            closed = true;
            resolve();
          } catch (e) { fail(e as Error); }
        };
        req.on('dataReceive', (data: ArrayBuffer) => {
          if (closed) return;
          try {
            const text = decoder.decodeToString(new Uint8Array(data), { stream: true });
            if (raw.length < 2 * 1024 * 1024) raw += text;
            reader.push(text);
          } catch (e) {
            if (!streamParseErr) streamParseErr = e as Error;
          }
        });
        req.on('dataEnd', () => {
          if (closed) return;
          try {
            const tail = decoder.decodeToString(new Uint8Array(0));
            if (raw.length < 2 * 1024 * 1024) raw += tail;
            reader.push(tail);
            bodyEnded = true;
            complete();
          } catch (e) {
            if (!streamParseErr) streamParseErr = e as Error;
            bodyEnded = true;
            complete();
          }
        });
        const reqOpts: http.HttpRequestOptions = {
          method: http.RequestMethod.POST,
          header: call.headers,
          extraData: call.body,
          connectTimeout: 20000,
          readTimeout: 120000,
          usingCache: false,
          maxRedirects: 5
        };
        const proxyCfg = buildHttpProxy(options?.proxy, options?.proxyPassword);
        if (proxyCfg) reqOpts.usingProxy = proxyCfg;
        req.requestInStream(call.address, reqOpts)
          .then((code: number) => { status = code; complete(); })
          .catch((e: Error) => fail(e));
      });
    } finally {
      closed = true;
      this.abort = undefined;
      req.destroy();
    }
  }
}

export async function completeOnce(
  provider: Provider,
  key: string,
  systemPrompt: string,
  userPrompt: string,
  modelId?: string,
  maxTokens?: number,
  proxyPassword?: string,
  conversationId?: string,
  thinking: boolean | ReasoningEffort = false,
  onLog?: (log: RequestLogEntry) => void
): Promise<string> {
  const chosenModel = (modelId || provider.model).trim();
  const spec = findProviderModelSpec(provider, chosenModel);
  const cappedTokens = maxTokens !== undefined && maxTokens > 0 ? maxTokens : undefined;
  const resolvedEffort: ReasoningEffort = !spec.reasoning
    ? 'off'
    : (typeof thinking === 'string' ? thinking : (thinking ? 'low' : 'off'));
  const call = makeAdvancedChatCall(
    provider,
    key,
    systemPrompt,
    [{ id: 'oneshot', role: 'user', text: userPrompt, model: '' }],
    {
      modelId: chosenModel,
      modelSpec: spec,
      conversationId,
      params: {
        temperature: (cappedTokens === undefined || spec.reasoning) ? undefined : 0.3,
        maxTokens: cappedTokens,
        reasoningEffort: resolvedEffort
      }
    }
  );
  const stream = new ChatStream();
  let output = '';
  await stream.runRich(call, (frag: RichFragment) => {
    output += frag.text;
  }, {
    providerName: provider.name,
    modelId: chosenModel,
    proxy: provider.proxy,
    proxyPassword,
    maxRetries: 1,
    onLog
  });
  return output.trim();
}

export async function checkProviderHealth(
  provider: Provider,
  key: string,
  modelId?: string,
  proxyPassword?: string
): Promise<number> {
  const start = Date.now();
  const targetModel = (modelId || provider.model).trim();
  if (targetModel.length > 0) {
    await completeOnce(provider, key, '', 'ping', targetModel, 64, proxyPassword);
  } else {
    await fetchModels(provider, key, proxyPassword);
  }
  return Math.max(1, Date.now() - start);
}

export async function generateImages(
  provider: Provider,
  key: string,
  prompt: string,
  modelId?: string,
  proxyPassword?: string,
  conversationId?: string
): Promise<Attachment[]> {
  const call = makeImageGenCall(provider, key, prompt, modelId, conversationId);
  const req = http.createHttp();
  try {
    const opts: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: call.headers,
      extraData: call.body,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 20000,
      readTimeout: 90000,
      usingCache: false
    };
    const proxyCfg = buildHttpProxy(provider.proxy, proxyPassword);
    if (proxyCfg) opts.usingProxy = proxyCfg;
    const resp = await req.request(call.address, opts);
    const raw = resp.result as string;
    if (resp.responseCode < 200 || resp.responseCode >= 300) throw statusError(resp.responseCode, raw);
    const images = parseImageGenResponse(raw, provider.family);
    if (!images.length) throw new Error('模型未返回图片数据');
    return images;
  } finally {
    req.destroy();
  }
}
