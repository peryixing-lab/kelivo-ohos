import { planAccessToken } from './ChatGptSession';
import { openCodeGoAccessToken } from './OpenCodeGoSession';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import {
  Attachment,
  CHATGPT_PLAN_API,
  planClientId,
  ModelSpec,
  OPEN_CODE_GO_API,
  openCodeGoSessionId,
  Provider,
  ProxyConfig,
  ReasoningEffort,
  RequestLogEntry,
  checkEndpoint,
  defaultModelSpec,
  extractUrlHost,
  findProviderModelSpec,
  isOpenCodeGoEndpoint,
  normalizeProxyConfig
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

interface ModelEntry { slug?: string; visibility?: string; display_name?: string; id?: string; name?: string; type?: string; supportedGenerationMethods?: string[] }
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

export interface ResolvedProxySelection {
  proxy: ProxyConfig;
  password: string;
  source: 'provider' | 'global';
}

export interface ProxyTestResult {
  ok: boolean;
  status: number;
  elapsedMs: number;
  error: string;
}

let globalHttpProxyConfig: ProxyConfig | undefined = undefined;
let globalHttpProxyPassword: string = '';

export function setGlobalHttpProxy(proxy?: ProxyConfig, password: string = ''): void {
  globalHttpProxyConfig = proxy ? normalizeProxyConfig(proxy, true) : undefined;
  globalHttpProxyPassword = password || '';
}

export function getGlobalHttpProxy(): ProxyConfig | undefined {
  return globalHttpProxyConfig;
}

function normalizeBypassHost(host: string): string {
  let h = host.trim().toLowerCase();
  if (h.startsWith('[') && h.endsWith(']') && h.length > 2) {
    h = h.slice(1, h.length - 1);
  }
  const zoneIdx = h.indexOf('%');
  if (zoneIdx > 0) {
    h = h.slice(0, zoneIdx);
  }
  if (h.endsWith('.')) {
    h = h.slice(0, h.length - 1);
  }
  return h;
}

function parseIpv4Uint32(ip: string): number | undefined {
  const parts = ip.split('.');
  if (parts.length !== 4) return undefined;
  let value = 0;
  for (let i = 0; i < 4; i++) {
    if (!/^\d{1,3}$/.test(parts[i])) return undefined;
    const oct = Number(parts[i]);
    if (!Number.isInteger(oct) || oct < 0 || oct > 255) return undefined;
    value = ((value * 256) + oct) >>> 0;
  }
  return value;
}

export function shouldBypassProxy(urlOrHost: string, bypassRules?: string): boolean {
  if (!bypassRules || bypassRules.trim().length === 0) return false;
  const rawHost = urlOrHost.includes('://') || urlOrHost.includes('/')
    ? extractUrlHost(urlOrHost)
    : urlOrHost;
  const h = normalizeBypassHost(rawHost);
  if (!h) return false;

  const rules = bypassRules.split(/[,;\s]+/);
  const hIpv4 = parseIpv4Uint32(h);
  for (let i = 0; i < rules.length; i++) {
    const r = rules[i].trim().toLowerCase();
    if (!r) continue;
    if (r === '*') return true;
    const slashIdx = r.indexOf('/');
    if (slashIdx > 0 && hIpv4 !== undefined) {
      const netStr = r.slice(0, slashIdx);
      const prefixStr = r.slice(slashIdx + 1);
      const netIp = parseIpv4Uint32(netStr);
      const prefix = /^\d+$/.test(prefixStr) ? Number(prefixStr) : -1;
      if (netIp !== undefined && prefix >= 0 && prefix <= 32) {
        const mask = prefix === 0 ? 0 : ((0xFFFFFFFF << (32 - prefix)) >>> 0);
        if (((hIpv4 & mask) >>> 0) === ((netIp & mask) >>> 0)) {
          return true;
        }
        continue;
      }
    }
    if (r.startsWith('*.') && r.length > 2) {
      const suffix = normalizeBypassHost(r.slice(2));
      if (suffix && (h === suffix || h.endsWith('.' + suffix))) {
        return true;
      }
      continue;
    }
    if (r.startsWith('.') && r.length > 1) {
      const suffix = normalizeBypassHost(r.slice(1));
      if (suffix && (h === suffix || h.endsWith('.' + suffix))) {
        return true;
      }
      continue;
    }
    if (normalizeBypassHost(r) === h) {
      return true;
    }
  }
  return false;
}

export function parseProxyExclusionList(bypassRules?: string): string[] {
  if (!bypassRules || bypassRules.trim().length === 0) return [];
  const out: string[] = [];
  const rules = bypassRules.split(/[,;\s]+/);
  for (let i = 0; i < rules.length; i++) {
    const r = rules[i].trim();
    if (!r || r === '*') continue;
    if (r.includes('/') || r.startsWith('*.')) continue;
    out.push(r.startsWith('.') ? r.slice(1) : r);
  }
  return out;
}

export function resolveEffectiveProxy(
  proxy?: ProxyConfig,
  password?: string,
  targetUrl?: string
): ResolvedProxySelection | undefined {
  if (proxy && proxy.enabled && proxy.host && proxy.host.trim().length > 0 && proxy.port > 0) {
    if (targetUrl && proxy.bypass && shouldBypassProxy(targetUrl, proxy.bypass)) {
      return undefined;
    }
    return {
      proxy: normalizeProxyConfig(proxy),
      password: password || '',
      source: 'provider'
    };
  }
  if (globalHttpProxyConfig && globalHttpProxyConfig.enabled &&
    globalHttpProxyConfig.host.trim().length > 0 && globalHttpProxyConfig.port > 0) {
    if (targetUrl && shouldBypassProxy(targetUrl, globalHttpProxyConfig.bypass)) {
      return undefined;
    }
    return {
      proxy: globalHttpProxyConfig,
      password: globalHttpProxyPassword,
      source: 'global'
    };
  }
  return undefined;
}

function buildDirectHttpProxyConfig(proxy: ProxyConfig, password?: string): http.HttpProxy {
  const cfg: http.HttpProxy = {
    host: proxy.host.trim(),
    port: proxy.port,
    exclusionList: parseProxyExclusionList(proxy.bypass)
  };
  if (proxy.username && proxy.username.trim().length > 0) {
    cfg.username = proxy.username.trim();
    cfg.password = password || '';
  }
  return cfg;
}

export function buildHttpProxy(proxy?: ProxyConfig, password?: string, targetUrl?: string): http.HttpProxy | undefined {
  const resolved = resolveEffectiveProxy(proxy, password, targetUrl);
  if (!resolved || resolved.proxy.type === 'socks5') return undefined;
  return buildDirectHttpProxyConfig(resolved.proxy, resolved.password);
}

export function applyProxyToHttpOptions(
  opts: http.HttpRequestOptions,
  targetUrl?: string,
  proxy?: ProxyConfig,
  password?: string
): void {
  const resolved = resolveEffectiveProxy(proxy, password, targetUrl);
  if (!resolved) return;
  if (resolved.proxy.type === 'socks5') {
    const sCfg: http.Socks5Proxy = {
      host: resolved.proxy.host.trim(),
      port: resolved.proxy.port,
      exclusionList: parseProxyExclusionList(resolved.proxy.bypass)
    };
    if (resolved.proxy.username && resolved.proxy.username.trim().length > 0) {
      sCfg.username = resolved.proxy.username.trim();
      sCfg.password = resolved.password || '';
    }
    opts.usingSocks5Proxy = sCfg;
    return;
  }
  opts.usingProxy = buildDirectHttpProxyConfig(resolved.proxy, resolved.password);
}

export async function testProxyConnection(
  proxy: ProxyConfig,
  password: string,
  testUrl: string
): Promise<ProxyTestResult> {
  const host = (proxy.host || '').trim();
  const port = Math.floor(proxy.port || 0);
  const url = (testUrl || '').trim();
  if (!host) {
    return { ok: false, status: 0, elapsedMs: 0, error: '请填写代理服务器地址' };
  }
  if (!Number.isFinite(port) || port <= 0 || port > 65535) {
    return { ok: false, status: 0, elapsedMs: 0, error: '请输入有效端口 (1-65535)' };
  }
  if (!/^https?:\/\/\S+$/i.test(url)) {
    return { ok: false, status: 0, elapsedMs: 0, error: '请输入以 http:// 或 https:// 开头的测试地址' };
  }
  const req = http.createHttp();
  const start = Date.now();
  try {
    const forcedProxy: ProxyConfig = normalizeProxyConfig(proxy, false);
    forcedProxy.enabled = true;
    const opts: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 8000,
      readTimeout: 10000,
      maxRedirects: 5,
      usingCache: false
    };
    if (forcedProxy.type === 'socks5') {
      const sCfg: http.Socks5Proxy = {
        host,
        port,
        exclusionList: []
      };
      if (forcedProxy.username && forcedProxy.username.length > 0) {
        sCfg.username = forcedProxy.username;
        sCfg.password = password || '';
      }
      opts.usingSocks5Proxy = sCfg;
    } else {
      const hCfg: http.HttpProxy = {
        host,
        port,
        exclusionList: []
      };
      if (forcedProxy.username && forcedProxy.username.length > 0) {
        hCfg.username = forcedProxy.username;
        hCfg.password = password || '';
      }
      opts.usingProxy = hCfg;
    }
    const resp = await req.request(url, opts);
    const elapsedMs = Math.max(1, Date.now() - start);
    const ok = resp.responseCode >= 200 && resp.responseCode < 400;
    return {
      ok,
      status: resp.responseCode,
      elapsedMs,
      error: ok ? '' : ('HTTP ' + resp.responseCode)
    };
  } catch (e) {
    return {
      ok: false,
      status: 0,
      elapsedMs: Math.max(1, Date.now() - start),
      error: (e as Error).message || String(e)
    };
  } finally {
    req.destroy();
  }
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
  const plan = planClientId(provider);
  if (plan) {
    const token = await planAccessToken(plan);
    const req = http.createHttp();
    try {
      const url = CHATGPT_PLAN_API + '/models';
      const opts: http.HttpRequestOptions = { method: http.RequestMethod.GET, header: { 'Authorization': 'Bearer ' + token },
        expectDataType: http.HttpDataType.STRING, usingCache: false, maxRedirects: 0, connectTimeout: 15000, readTimeout: 25000 };
      applyProxyToHttpOptions(opts, url, provider.proxy, proxyPassword);
      const response = await req.request(url, opts);
      if (response.responseCode !== 200) throw new Error('ChatGPT 模型列表请求失败（HTTP ' + response.responseCode + '）');
      const page = JSON.parse(response.result as string) as ModelPage;
      if (!Array.isArray(page.models)) throw new Error('ChatGPT 模型列表格式异常');
      return page.models.filter((m: ModelEntry): boolean => !!m.slug && m.visibility === 'list')
        .map((m: ModelEntry): string => m.slug!);
    } finally { req.destroy(); }
  }
  const goSession = openCodeGoSessionId(provider);
  const go = isOpenCodeGoEndpoint(provider.baseUrl);
  if (goSession && !go) {
    throw new Error('OpenCode Go 账号登录仅支持官方 OpenCode Go 接口地址');
  }
  const effectiveKey = goSession && !key.trim()
    ? await openCodeGoAccessToken(goSession, provider.proxy, proxyPassword)
    : key;
  const base = go ? OPEN_CODE_GO_API + '/v1/models' : checkEndpoint(provider.baseUrl) + '/models';
  const names: string[] = [];
  let next = base;
  const seen = new Set<string>();
  while (next && !seen.has(next)) {
    seen.add(next);
    const req = http.createHttp();
    try {
      const opts: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: buildProviderHeaders(provider, effectiveKey),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 25000,
        maxRedirects: 5,
        usingCache: false
      };
      applyProxyToHttpOptions(opts, next, provider.proxy, proxyPassword);
      const response = await req.request(next, opts);
      const raw = response.result as string;
      if (response.responseCode < 200 || response.responseCode >= 300) throw statusError(response.responseCode, raw);
      const page = JSON.parse(raw) as ModelPage;
      const items = page.data ?? page.models;
      if (!Array.isArray(items)) throw new Error('服务商没有返回模型列表，可手动填写模型 ID。');
      items.forEach((entry: ModelEntry) => {
        if (go && entry.type && entry.type !== 'chat') return;
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
    applyProxyToHttpOptions(opts, root + '/api/show', proxy);
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

interface GoUsageMeter { percent: number; resetsAt: string }
interface GoUsageWindows { rolling: GoUsageMeter; weekly: GoUsageMeter; monthly: GoUsageMeter }
interface GoUsageResponse { usage?: GoUsageWindows }

export interface GoQuotaRow {
  label: string;
  remaining: number;
  resetTime: number;
}

export function parseOpenCodeGoUsage(raw: string): GoQuotaRow[] {
  const error = 'OpenCode Go 返回的额度数据不完整或格式异常';
  let data: GoUsageResponse;
  try {
    data = JSON.parse(raw) as GoUsageResponse;
  } catch (_) {
    throw new Error(error);
  }
  const usage = data?.usage;
  if (!usage) throw new Error(error);
  const row = (label: string, meter: GoUsageMeter): GoQuotaRow => {
    if (!meter || !Number.isInteger(meter.percent) || meter.percent < 0 || meter.percent > 100 ||
      typeof meter.resetsAt !== 'string' || !Number.isFinite(Date.parse(meter.resetsAt))) {
      throw new Error(error);
    }
    return { label, remaining: 100 - meter.percent, resetTime: Date.parse(meter.resetsAt) };
  };
  return [row('5 小时额度', usage.rolling), row('周额度', usage.weekly), row('月额度', usage.monthly)];
}

export async function fetchOpenCodeGoUsage(key: string, proxy?: ProxyConfig, password?: string): Promise<GoQuotaRow[]> {
  if (!key.trim()) throw new Error('请先填写主 API 密钥');
  const url = OPEN_CODE_GO_API + '/v1/usage';
  const req = http.createHttp();
  try {
    const opts: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: { 'Authorization': 'Bearer ' + key.trim(), 'Accept': 'application/json' },
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 10000,
      readTimeout: 15000,
      maxRedirects: 0,
      usingCache: false
    };
    applyProxyToHttpOptions(opts, url, proxy, password);
    let response: http.HttpResponse;
    try {
      response = await req.request(url, opts);
    } catch (_) {
      throw new Error('无法连接 OpenCode Go，请检查网络或代理后刷新');
    }
    const status = response.responseCode;
    if (status === 401) throw new Error('API 密钥无效或已失效，请检查主 API 密钥');
    if (status === 403) throw new Error('此密钥无权查看额度，请检查 Go 订阅和工作区权限');
    if (status === 429) throw new Error('额度查询过于频繁，请稍后刷新');
    if (status !== 200) throw new Error('额度查询失败（HTTP ' + status + '）');
    return parseOpenCodeGoUsage(response.result as string);
  } finally {
    req.destroy();
  }
}

export function providerBalanceUrl(baseUrl: string, customUrl?: string): string {
  if (customUrl?.trim()) return customUrl.trim();
  const host = extractUrlHost(baseUrl);
  if (host === 'api.deepseek.com') return 'https://api.deepseek.com/user/balance';
  if (host === 'api.siliconflow.cn') return 'https://api.siliconflow.cn/v1/user/info';
  if (host === 'openrouter.ai') return 'https://openrouter.ai/api/v1/credits';
  return '';
}

export async function fetchProviderBalance(provider: Provider, key: string, proxyPassword?: string): Promise<string> {
  const url = providerBalanceUrl(checkEndpoint(provider.baseUrl), provider.balanceUrl);
  if (!url) throw new Error('该服务商未配置余额查询地址');
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
    applyProxyToHttpOptions(opts, url, provider.proxy, proxyPassword);
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
          if (frag.text || frag.reasoning || frag.toolCalls.length || frag.generatedImages.length ||
            Boolean(frag.citations && frag.citations.length > 0)) {
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
    let headers = call.headers;
    if (call.planClient) {
      if (call.address !== CHATGPT_PLAN_API + '/responses') throw new Error('ChatGPT 订阅请求地址无效');
      headers = { 'Authorization': 'Bearer ' + await planAccessToken(call.planClient), 'Content-Type': 'application/json' };
      if (this.cancelled) throw new Error('已停止生成');
    }
    if (call.openCodeGoSession) {
      if (!call.address.startsWith(OPEN_CODE_GO_API + '/') && !call.address.startsWith('https://opencode.ai/zen/go/')) {
        throw new Error('OpenCode Go 订阅请求地址无效');
      }
      const goToken = await openCodeGoAccessToken(call.openCodeGoSession, options?.proxy, options?.proxyPassword);
      if (this.cancelled) throw new Error('已停止生成');
      const nextHeaders: Record<string, string> = {};
      const headerKeys = Object.keys(headers);
      for (let i = 0; i < headerKeys.length; i++) {
        const hk = headerKeys[i];
        if (hk.toLowerCase() !== 'authorization') {
          nextHeaders[hk] = headers[hk];
        }
      }
      nextHeaders['Authorization'] = 'Bearer ' + goToken;
      headers = nextHeaders;
    }
    let planCompleted = false;
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
      if (call.planClient && data !== '[DONE]' && part.done) {
        const terminal = JSON.parse(data) as Record<string, Object>;
        if (terminal['type'] === 'response.completed') planCompleted = true;
      }
      if (part.text) {
        const split = thinkParser.push(part.text);
        part.text = split.text;
        part.reasoningPhase = part.reasoningPhase ?? split.reasoningPhase;
        part.reasoning = (part.reasoning || '') + split.reasoning;
      }
      if (part.text || part.reasoning || part.reasoningPhase || part.toolCalls.length ||
        part.generatedImages.length || Boolean(part.citations && part.citations.length > 0) ||
        part.usage || part.done) {
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
            if (call.planClient && !planCompleted) throw new Error('ChatGPT 回复连接提前结束，请重试');
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
          header: headers,
          extraData: call.body,
          connectTimeout: 20000,
          readTimeout: 120000,
          usingCache: false,
          maxRedirects: (call.planClient || call.openCodeGoSession) ? 0 : 5
        };
        applyProxyToHttpOptions(reqOpts, call.address, options?.proxy, options?.proxyPassword);
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
  const goSession = openCodeGoSessionId(provider);
  let effectiveKey = key;
  if (goSession && !effectiveKey.trim()) {
    if (!isOpenCodeGoEndpoint(provider.baseUrl)) {
      throw new Error('OpenCode Go 账号登录仅支持官方 OpenCode Go 接口地址');
    }
    effectiveKey = await openCodeGoAccessToken(goSession, provider.proxy, proxyPassword);
  }
  const call = makeImageGenCall(provider, effectiveKey, prompt, modelId, conversationId);
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
    applyProxyToHttpOptions(opts, call.address, provider.proxy, proxyPassword);
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
