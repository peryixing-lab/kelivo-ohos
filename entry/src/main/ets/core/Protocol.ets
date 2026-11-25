import {
  ApiFamily,
  CHATGPT_PLAN_API,
  planClientId,
  Attachment,
  ChatMessage,
  GenerationParams,
  HeaderEntry,
  ModelReasoningReplayField,
  ModelSpec,
  PresetMessage,
  Provider,
  SearchHit,
  TokenUsage,
  checkEndpoint,
  extractUrlHost,
  findProviderModelSpec,
  getAllAttachments,
  isLocalOrCustomHost,
  isOpenCodeGoEndpoint,
  messageText,
  openCodeGoSessionId
} from './Models';
import {
  applyChatCompletionsBuiltInSearch,
  applyModelExtraChatCompletionsTools,
  buildModelExtraClaudeTools,
  buildModelExtraResponsesTools,
  buildResponsesBuiltInSearchTools,
  claudeSearchToolType,
  isBuiltInSearchEnabled,
  isClaudeDynamicSearchEnabled,
  mergeDeduplicatedCitations,
  supportsBuiltInSearch,
  supportsGeminiMixedBuiltInAndFunctionTools
} from './BuiltinSearch';
import { ReasoningControl, applyReasoning, effectiveEffort, reasoningControl, usesResponsesApi } from './Reasoning';

interface WireMessage {
  role: string;
  content: string | WirePart[] | null;
  reasoning_content?: string;
  reasoning?: string;
  reasoning_details?: Array<Record<string, Object>>;
  tool_calls?: WireOpenToolCall[];
  tool_call_id?: string;
  name?: string;
}
interface WireOpenToolCall {
  id: string;
  type: string;
  function: WireOpenToolFunction;
}
interface WireOpenToolFunction {
  name: string;
  arguments: string;
}
interface WireImage { url: string }
interface WireAudio { data: string; format: string }
interface ClaudeImage { type: string; media_type: string; data: string }
interface InlineImage { mimeType: string; data: string }
interface WireFunctionCall { name: string; args: Record<string, Object> }
interface WireFunctionResp { name: string; response: Record<string, Object> }
interface WirePart {
  type?: string;
  text?: string;
  thought?: boolean;
  image_url?: WireImage;
  input_audio?: WireAudio;
  source?: ClaudeImage;
  inlineData?: InlineImage;
  id?: string;
  name?: string;
  input?: Record<string, Object>;
  tool_use_id?: string;
  content?: string;
  cache_control?: WireCacheControl;
  functionCall?: WireFunctionCall;
  functionResponse?: WireFunctionResp;
}
interface WireCacheControl { type: string }
interface GeminiContent { role?: string; parts: WirePart[] }
interface OpenBody { model: string; messages: WireMessage[]; stream: boolean }
interface ClaudeBody { model: string; system?: string; messages: WireMessage[]; max_tokens: number; stream: boolean }
interface GeminiBody { contents: GeminiContent[]; systemInstruction?: GeminiContent }
export interface ChatCall {
  planClient?: string;
  openCodeGoSession?: string;
  address: string;
  headers: Record<string, string>;
  body: string;
}

function withOpenCodeGoSession(call: ChatCall, goSession: string): ChatCall {
  if (!goSession) {
    return call;
  }
  return {
    planClient: call.planClient,
    openCodeGoSession: goSession,
    address: call.address,
    headers: call.headers,
    body: call.body
  };
}

interface ReplyToolFn { name?: string; arguments?: string }
interface ReplyToolCallItem { index?: number; id?: string; type?: string; function?: ReplyToolFn }
interface ReplyUrlCitation { url?: string; title?: string }
interface ReplyClaudeCitation { url?: string; title?: string; cited_text?: string }
interface ReplyAnnotation { type?: string; url?: string; title?: string; url_citation?: ReplyUrlCitation }
interface ReplyGroundingWeb { uri?: string; title?: string }
interface ReplyGroundingChunk { web?: ReplyGroundingWeb; webSite?: ReplyGroundingWeb; webPage?: ReplyGroundingWeb }
interface ReplyGroundingMetadata { groundingChunks?: ReplyGroundingChunk[] }
interface ReplyZhipuSearchItem { title?: string; link?: string; url?: string; content?: string }
interface ReplyWebSearchResultItem { type?: string; url?: string; title?: string }
interface ReplyWebSearchToolError { type?: string; error_code?: string }
interface ReplyResponsesContentBlock { type?: string; text?: string; annotations?: ReplyAnnotation[] }

interface ReplyDelta {
  content?: string;
  text?: string;
  reasoning_content?: string;
  reasoning?: string;
  thinking?: string;
  partial_json?: string;
  type?: string;
  tool_calls?: ReplyToolCallItem[];
  annotations?: ReplyAnnotation[];
  citation?: ReplyClaudeCitation;
}
interface ReplyChoice { delta?: ReplyDelta; message?: ReplyDelta; finish_reason?: string }
interface Candidate { content?: GeminiContent; finishReason?: string; groundingMetadata?: ReplyGroundingMetadata }
interface RemoteError { message?: string }
interface ReplyUsage {
  prompt_tokens?: number;
  completion_tokens?: number;
  total_tokens?: number;
  input_tokens?: number;
  output_tokens?: number;
  cache_read_input_tokens?: number;
  promptTokenCount?: number;
  candidatesTokenCount?: number;
  totalTokenCount?: number;
  cachedContentTokenCount?: number;
  prompt_tokens_details?: ReplyTokenDetails;
  input_tokens_details?: ReplyTokenDetails;
}
interface ReplyTokenDetails { cached_tokens?: number }
interface ReplyContentBlock {
  type?: string;
  id?: string;
  name?: string;
  text?: string;
  thinking?: string;
  input?: Record<string, Object>;
  content?: ReplyWebSearchResultItem[] | ReplyWebSearchToolError;
  citations?: ReplyClaudeCitation[];
}
interface ReplyResponseItem {
  id?: string;
  type?: string;
  call_id?: string;
  name?: string;
  arguments?: string;
  content?: ReplyResponsesContentBlock[];
}
interface PlanResponseError { message?: string }
interface ReplyResponseObj { error?: PlanResponseError; usage?: ReplyUsage; output?: ReplyResponseItem[] }
interface ReplyMessageStart { usage?: ReplyUsage }
interface ReplyEvent {
  type?: string;
  choices?: ReplyChoice[];
  delta?: ReplyDelta | string;
  content?: ReplyContentBlock[];
  content_block?: ReplyContentBlock;
  item?: ReplyResponseItem;
  response?: ReplyResponseObj;
  message?: ReplyMessageStart;
  annotation?: ReplyAnnotation;
  annotations?: ReplyAnnotation[];
  citations?: Array<string | ReplyAnnotation>;
  groundingMetadata?: ReplyGroundingMetadata;
  web_search?: ReplyZhipuSearchItem[];
  output?: ReplyResponseItem[];
  output_index?: number;
  call_id?: string;
  item_id?: string;
  index?: number;
  candidates?: Candidate[];
  usage?: ReplyUsage;
  usageMetadata?: ReplyUsage;
  error?: RemoteError;
}

export interface Fragment {
  text: string;
  reasoning: string;
  reasoningPhase?: 'thinking' | 'finished';
}

export interface ToolDeclaration {
  name: string;
  description: string;
  parametersJson: string;
}

export interface ToolCallDelta {
  index: number;
  id: string;
  name: string;
  argsDelta: string;
  done: boolean;
}

export interface WireToolTurn {
  role: 'assistant' | 'tool';
  text?: string;
  reasoning?: string;
  toolCalls?: ToolCallDelta[];
  toolCallId?: string;
  toolName?: string;
  toolResult?: string;
}

export interface RichFragment extends Fragment {
  toolCalls: ToolCallDelta[];
  usage?: TokenUsage;
  generatedImages: Attachment[];
  citations?: SearchHit[];
  done: boolean;
}

// Some providers mark the reasoning boundary explicitly. Others first reveal it
// by sending answer text, a tool call or an image.
export class ReplyReasoningTimer {
  private startedAt: number = -1;
  elapsedMs: number = 0;

  get active(): boolean { return this.startedAt >= 0; }

  update(part: RichFragment, now: number): void {
    if ((part.reasoning || part.reasoningPhase === 'thinking') && !this.active) this.startedAt = now;
    const answering = part.text.length > 0 && part.reasoningPhase !== 'thinking';
    if (part.reasoningPhase === 'finished' || part.done || answering || part.toolCalls.length || part.generatedImages.length) {
      this.finish(now);
    }
  }

  finish(now: number): void {
    if (!this.active) return;
    this.elapsedMs += Math.max(0, now - this.startedAt);
    this.startedAt = -1;
  }
}

export interface ChatCallOptions {
  modelId?: string;
  modelSpec?: ModelSpec;
  conversationId?: string;
  stream?: boolean;
  params?: GenerationParams;
  tools?: ToolDeclaration[];
  toolTurns?: WireToolTurn[];
  presetMessages?: PresetMessage[];
  customHeaders?: HeaderEntry[];
  customBodyJson?: string;
  promptCaching?: boolean;
  builtinSearch?: boolean;
  claudeDynamicSearch?: boolean;
  builtinUrlContext?: boolean;
  builtinCodeExec?: boolean;
}

export function generateFallbackSessionId(): string {
  const hex = '0123456789abcdef';
  let out = '';
  for (let i = 0; i < 36; i++) {
    if (i === 8 || i === 13 || i === 18 || i === 23) {
      out += '-';
    } else if (i === 14) {
      out += '4';
    } else if (i === 19) {
      const r = Math.floor(Math.random() * 16);
      out += hex.charAt((r & 0x3) | 0x8);
    } else {
      out += hex.charAt(Math.floor(Math.random() * 16));
    }
  }
  return out;
}

const OPEN_CODE_USER_AGENT = 'kelivo/1.0 (HarmonyOS)';

function usesOpenCodeSession(provider: Provider): boolean {
  const host = extractUrlHost(provider.baseUrl).replace(/\.$/, '');
  return host === 'opencode.ai' || host.endsWith('.opencode.ai');
}

export function providerDefaultHeaders(provider: Provider): Record<string, string> {
  const host = extractUrlHost(provider.baseUrl);
  const out: Record<string, string> = {};
  if (host.includes('openrouter.ai')) {
    out['HTTP-Referer'] = 'https://github.com/Chevey339/kelivo';
    out['X-OpenRouter-Title'] = 'Kelivo';
    out['X-OpenRouter-Categories'] = 'general-chat';
  }
  if (usesOpenCodeSession(provider)) {
    out['User-Agent'] = OPEN_CODE_USER_AGENT;
  }
  return out;
}

export function providerSessionHeaders(provider: Provider, conversationId?: string): Record<string, string> {
  const cleanId = (conversationId || '').trim();
  const out: Record<string, string> = {};
  if (provider.oauth) {
    const session = cleanId.length > 0 ? cleanId : generateFallbackSessionId();
    if (provider.oauth.kind === 'chatgpt') {
      out['session-id'] = session;
      out['thread-id'] = session;
      out['x-client-request-id'] = session;
    } else if (provider.oauth.kind === 'grok') {
      out['x-grok-conv-id'] = session;
    } else if (provider.oauth.kind === 'claude') {
      out['X-Claude-Code-Session-Id'] = session;
    }
  }
  if (usesOpenCodeSession(provider)) {
    out['x-opencode-session'] = cleanId.length > 0 ? cleanId : generateFallbackSessionId();
  }
  return out;
}

export function mergeHeaderMap(target: Record<string, string>, extra: Record<string, string>): void {
  const keys = Object.keys(extra);
  for (let i = 0; i < keys.length; i++) {
    const k = keys[i];
    if (k) {
      target[k] = extra[k];
    }
  }
}

export function resolveEndpointUrl(base: string, customPath: string | undefined, defaultPath: string): string {
  const trimmed = (customPath || '').trim();
  if (!trimmed) {
    return base + defaultPath;
  }
  const normalized = trimmed.startsWith('/') ? trimmed : '/' + trimmed;
  return base + normalized;
}

export function authHeaders(family: ApiFamily, key: string): Record<string, string> {
  const headers: Record<string, string> = { 'Content-Type': 'application/json' };
  if (family === 'anthropic') {
    headers['anthropic-version'] = '2023-06-01';
    if (key) headers['x-api-key'] = key;
  } else if (family === 'gemini') {
    if (key) headers['x-goog-api-key'] = key;
  } else if (key) {
    headers['Authorization'] = 'Bearer ' + key;
  }
  return headers;
}

function contentParts(msg: ChatMessage, family: ApiFamily, allowRemoteImageUrls: boolean = true): WirePart[] {
  const body = messageText(msg);
  const parts: WirePart[] = [];
  const files = getAllAttachments(msg);
  if (body) {
    if (family === 'gemini' || family === 'vertex') parts.push({ text: body });
    else parts.push({ type: 'text', text: body });
  }
  for (let i = 0; i < files.length; i++) {
    const f = files[i];
    if (f.mime.startsWith('image/') && f.data) {
      const trimmed = f.data.trim();
      const isRemote = /^https?:\/\//i.test(trimmed);
      if (isRemote) {
        if (allowRemoteImageUrls && (family === 'openai' || family === 'openai-responses')) {
          parts.push({ type: 'image_url', image_url: { url: trimmed } });
        }
      } else if (family === 'openai' || family === 'openai-responses') {
        parts.push({ type: 'image_url', image_url: { url: 'data:' + f.mime + ';base64,' + f.data } });
      } else if (family === 'anthropic') {
        parts.push({ type: 'image', source: { type: 'base64', media_type: f.mime, data: f.data } });
      } else {
        parts.push({ inlineData: { mimeType: f.mime, data: f.data } });
      }
    } else if (f.mime.startsWith('audio/') && f.data) {
      if (family === 'openai') {
        const fmt = f.mime.includes('wav') ? 'wav' : 'mp3';
        parts.push({ type: 'input_audio', input_audio: { data: f.data, format: fmt } });
      } else if (family === 'gemini' || family === 'vertex') {
        parts.push({ inlineData: { mimeType: f.mime, data: f.data } });
      }
    }
  }
  if (parts.length === 0) {
    if (family === 'gemini' || family === 'vertex') parts.push({ text: ' ' });
    else parts.push({ type: 'text', text: ' ' });
  }
  return parts;
}

export function makeChatCall(provider: Provider, key: string, prompt: string, history: ChatMessage[],
  conversationId?: string): ChatCall {
  if (planClientId(provider)) return makeAdvancedChatCall(provider, key, prompt, history, { conversationId });
  const goSession = openCodeGoSessionId(provider);
  if (goSession && !isOpenCodeGoEndpoint(provider.baseUrl)) {
    throw new Error('OpenCode Go 账号登录仅支持官方 OpenCode Go 接口地址');
  }
  const base = checkEndpoint(provider.baseUrl);
  const headers = buildProviderHeaders(provider, key, conversationId);
  if (!provider.model.trim()) throw new Error('请在模型设置中填写模型 ID。');
  if (provider.family === 'gemini' || provider.family === 'vertex') {
    const contents = history.map((msg: ChatMessage): GeminiContent => {
      return { role: msg.role === 'assistant' ? 'model' : 'user', parts: contentParts(msg, provider.family) };
    });
    const payload: GeminiBody = { contents };
    if (prompt) payload.systemInstruction = { parts: [{ text: prompt }] };
    const modelId = encodeURIComponent(provider.model.replace(/^models\//, ''));
    return withOpenCodeGoSession({
      address: base + '/models/' + modelId + ':streamGenerateContent?alt=sse',
      headers,
      body: JSON.stringify(payload)
    }, goSession);
  }
  const messages: WireMessage[] = [];
  if (prompt && provider.family === 'openai') messages.push({ role: 'system', content: prompt });
  history.forEach((msg: ChatMessage) => {
    const files = getAllAttachments(msg);
    const hasBinary = files.some((f: Attachment): boolean => (f.mime.startsWith('image/') || f.mime.startsWith('audio/')) && !!f.data);
    messages.push({
      role: msg.role,
      content: hasBinary ? contentParts(msg, provider.family) : messageText(msg)
    });
  });
  if (provider.family === 'anthropic') {
    const claude: ClaudeBody = { model: provider.model, messages, max_tokens: 4096, stream: true };
    if (prompt) claude.system = prompt;
    return withOpenCodeGoSession(
      { address: resolveEndpointUrl(base, provider.chatPath, '/messages'), headers, body: JSON.stringify(claude) },
      goSession
    );
  }
  const body: OpenBody = { model: provider.model, messages, stream: true };
  return withOpenCodeGoSession(
    { address: resolveEndpointUrl(base, provider.chatPath, '/chat/completions'), headers, body: JSON.stringify(body) },
    goSession
  );
}

function mergeCustomBody(target: Record<string, Object>, rawJson?: string): void {
  if (!rawJson || !rawJson.trim()) return;
  try {
    const extra = JSON.parse(rawJson) as Record<string, Object>;
    if (extra && typeof extra === 'object') {
      Object.keys(extra).forEach((k: string) => {
        if (k === 'generationConfig' && target[k] && extra[k] && typeof extra[k] === 'object' && !Array.isArray(extra[k])) {
          const config = target[k] as Record<string, Object>;
          const additions = extra[k] as Record<string, Object>;
          Object.keys(additions).forEach((field: string) => { config[field] = additions[field]; });
        } else {
          target[k] = extra[k];
        }
      });
    }
  } catch (_) {}
}

function applyCustomHeaders(headers: Record<string, string>, entries?: HeaderEntry[]): void {
  if (!entries) return;
  for (let i = 0; i < entries.length; i++) {
    const k = entries[i].key.trim();
    if (k) headers[k] = entries[i].value;
  }
}

function parseCustomBodyValue(raw: string): Object {
  const trimmed = raw.trim();
  if (trimmed === 'true') return true;
  if (trimmed === 'false') return false;
  if (/^-?\d+(?:\.\d+)?$/.test(trimmed)) {
    const n = Number(trimmed);
    if (Number.isFinite(n)) return n;
  }
  if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
    (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
    try {
      const parsed = JSON.parse(trimmed) as Object;
      if (parsed !== null && parsed !== undefined) {
        return parsed;
      }
    } catch (_) {}
  }
  return raw;
}

function mergeCustomBodyEntries(target: Record<string, Object>, entries?: HeaderEntry[]): void {
  if (!entries || !entries.length) {
    return;
  }
  for (let i = 0; i < entries.length; i++) {
    const k = entries[i].key.trim();
    if (!k) {
      continue;
    }
    target[k] = parseCustomBodyValue(entries[i].value);
  }
}

function shouldIncludeSampling(
  spec: ModelSpec,
  control: ReasoningControl,
  params: GenerationParams | undefined,
  defaultAllow: boolean
): boolean {
  if (spec.samplingPolicy === 'always') {
    return true;
  }
  if (spec.samplingPolicy === 'never') {
    return false;
  }
  if (spec.samplingPolicy === 'only_when_reasoning_off') {
    if (!spec.reasoning || !control.levels.length) {
      return true;
    }
    const effort = params?.reasoningEffort ? effectiveEffort(control, params.reasoningEffort) : 'off';
    return effort === 'off';
  }
  return defaultAllow;
}

function setWireMessageReasoning(
  msg: WireMessage,
  text: string,
  field?: ModelReasoningReplayField
): void {
  if (!text) {
    return;
  }
  if (field === 'reasoning') {
    msg.reasoning = text;
    return;
  }
  if (field === 'reasoning_details') {
    const detail: Record<string, Object> = {};
    detail['type'] = 'reasoning.text';
    detail['text'] = text;
    msg.reasoning_details = [detail];
    return;
  }
  msg.reasoning_content = text;
}

export function buildProviderHeaders(
  provider: Provider,
  key: string,
  conversationId?: string,
  customHeaders?: HeaderEntry[],
  anthropicCaching: boolean = false
): Record<string, string> {
  const headers = authHeaders(provider.family, key);
  if (anthropicCaching && provider.family === 'anthropic') {
    headers['anthropic-beta'] = 'prompt-caching-2024-07-31';
  }
  const sessionHeaders = providerSessionHeaders(provider, conversationId);
  mergeHeaderMap(headers, providerDefaultHeaders(provider));
  mergeHeaderMap(headers, sessionHeaders);
  applyCustomHeaders(headers, provider.customHeaders);
  applyCustomHeaders(headers, customHeaders);

  const openCodeSession = sessionHeaders['x-opencode-session'];
  if (!openCodeSession) return headers;

  // HarmonyOS may collapse differently cased keys. Keep one routing header.
  const routed: Record<string, string> = {};
  let userAgent = OPEN_CODE_USER_AGENT;
  for (const name of Object.keys(headers)) {
    const lower = name.toLowerCase();
    if (lower === 'user-agent') {
      userAgent = headers[name].trim() || userAgent;
    } else if (lower !== 'x-opencode-session') {
      routed[name] = headers[name];
    }
  }
  routed['User-Agent'] = userAgent;
  routed['x-opencode-session'] = openCodeSession;
  return routed;
}

function parseJsonObjectSafe(raw: string): Record<string, Object> {
  try {
    const obj = JSON.parse(raw) as Record<string, Object>;
    if (obj && typeof obj === 'object') return obj;
  } catch (_) {}
  const empty: Record<string, Object> = {};
  return empty;
}

function normalizeObjectToolSchema(raw: string): Record<string, Object> {
  const obj = parseJsonObjectSafe(raw);
  if (!obj['type']) {
    obj['type'] = 'object';
  }
  if (obj['type'] === 'object' && (!obj['properties'] || typeof obj['properties'] !== 'object')) {
    const emptyProps: Record<string, Object> = {};
    obj['properties'] = emptyProps;
  }
  return obj;
}

function sanitizeGeminiParameters(raw: string): Record<string, Object> | undefined {
  const obj = parseJsonObjectSafe(raw);
  const props = obj['properties'] as Record<string, Object> | undefined;
  if (!props || typeof props !== 'object' || Object.keys(props).length === 0) {
    return undefined;
  }
  const clean: Record<string, Object> = {};
  clean['type'] = (obj['type'] as string) || 'object';
  clean['properties'] = props;
  if (Array.isArray(obj['required']) && (obj['required'] as Object[]).length > 0) {
    clean['required'] = obj['required'];
  }
  return clean;
}

function pushAnthropicMessage(list: WireMessage[], role: string, content: string | WirePart[]): void {
  if (typeof content === 'string') {
    if (!content.trim()) return;
  } else if (content.length === 0) {
    return;
  }
  if (list.length > 0 && list[list.length - 1].role === role) {
    const prev = list[list.length - 1];
    if (typeof prev.content === 'string' && typeof content === 'string') {
      prev.content = prev.content + '\n\n' + content;
      return;
    }
    const prevParts: WirePart[] = typeof prev.content === 'string'
      ? [{ type: 'text', text: prev.content }]
      : (prev.content || []);
    const nextParts: WirePart[] = typeof content === 'string'
      ? [{ type: 'text', text: content }]
      : content;
    prev.content = prevParts.concat(nextParts);
    return;
  }
  list.push({ role, content });
}

export function makeAdvancedChatCall(
  provider: Provider,
  key: string,
  prompt: string,
  history: ChatMessage[],
  options?: ChatCallOptions
): ChatCall {
  const opts: ChatCallOptions = options || {};
  const modelName = (opts.modelId || provider.model).trim();
  if (!modelName) throw new Error('请在模型设置中填写模型 ID。');
  const planClient = planClientId(provider);
  if (planClient && (provider.baseUrl !== CHATGPT_PLAN_API || provider.family !== 'openai-responses' || provider.chatPath)) {
    throw new Error('ChatGPT 订阅仅支持官方 Responses 接口');
  }
  const goSession = openCodeGoSessionId(provider);
  if (goSession && !isOpenCodeGoEndpoint(provider.baseUrl)) {
    throw new Error('OpenCode Go 账号登录仅支持官方 OpenCode Go 接口地址');
  }
  const base = checkEndpoint(provider.baseUrl);
  const host = extractUrlHost(provider.baseUrl);
  const params = opts.params;
  const spec = opts.modelSpec || findProviderModelSpec(provider, modelName);
  const combinedCustomHeaders: HeaderEntry[] = [
    ...(spec.customHeaders || []),
    ...(opts.customHeaders || [])
  ];
  const headers = buildProviderHeaders(
    provider,
    key,
    opts.conversationId,
    combinedCustomHeaders.length > 0 ? combinedCustomHeaders : undefined,
    opts.promptCaching
  );
  const useStream = opts.stream !== false;
  const control = reasoningControl(provider, modelName, spec);

  const tools = opts.tools || [];
  const toolTurns = opts.toolTurns || [];
  const presets = opts.presetMessages || [];
  const enableBuiltinSearch = opts.builtinSearch !== undefined
    ? (opts.builtinSearch && supportsBuiltInSearch(provider, modelName, spec))
    : isBuiltInSearchEnabled(provider, modelName);
  const enableClaudeDynamic = opts.claudeDynamicSearch !== undefined
    ? opts.claudeDynamicSearch
    : isClaudeDynamicSearchEnabled(provider, modelName);

  if (provider.family === 'gemini' || provider.family === 'vertex') {
    const contents: GeminiContent[] = [];
    for (let i = 0; i < presets.length; i++) {
      const pm = presets[i];
      if (!pm.content.trim()) continue;
      contents.push({ role: pm.role === 'assistant' ? 'model' : 'user', parts: [{ text: pm.content }] });
    }
    for (let i = 0; i < history.length; i++) {
      const msg = history[i];
      const parts = contentParts(msg, provider.family, spec.allowRemoteImageUrls !== false);
      if (parts.length === 0) continue;
      contents.push({ role: msg.role === 'assistant' ? 'model' : 'user', parts });
    }
    for (let i = 0; i < toolTurns.length; i++) {
      const turn = toolTurns[i];
      if (turn.role === 'assistant') {
        const parts: WirePart[] = [];
        if (turn.text) parts.push({ text: turn.text });
        if (turn.toolCalls) {
          for (let j = 0; j < turn.toolCalls.length; j++) {
            const tc = turn.toolCalls[j];
            parts.push({ functionCall: { name: tc.name, args: parseJsonObjectSafe(tc.argsDelta) } });
          }
        }
        if (parts.length > 0) contents.push({ role: 'model', parts });
      } else {
        const respObj: Record<string, Object> = {};
        respObj['result'] = turn.toolResult || '';
        contents.push({
          role: 'user',
          parts: [{ functionResponse: { name: turn.toolName || 'tool', response: respObj } }]
        });
      }
    }

    const body: Record<string, Object> = {};
    body['contents'] = contents;
    if (prompt) {
      const sysInst: GeminiContent = { parts: [{ text: prompt }] };
      body['systemInstruction'] = sysInst;
    }

    const genCfg: Record<string, Object> = {};
    if (shouldIncludeSampling(spec, control, params, true)) {
      if (params?.temperature !== undefined) genCfg['temperature'] = params.temperature;
      if (params?.topP !== undefined) genCfg['topP'] = params.topP;
    }
    if (params?.maxTokens !== undefined && params.maxTokens > 0) genCfg['maxOutputTokens'] = params.maxTokens;
    if (Object.keys(genCfg).length > 0) body['generationConfig'] = genCfg;
    applyReasoning(body, provider, modelName, control, params);

    const decls: Array<Record<string, Object>> = [];
    for (let i = 0; i < tools.length; i++) {
      const td = tools[i];
      const decl: Record<string, Object> = {};
      decl['name'] = td.name;
      decl['description'] = td.description;
      const gParams = sanitizeGeminiParameters(td.parametersJson);
      if (gParams) {
        decl['parameters'] = gParams;
      }
      decls.push(decl);
    }

    const gTools: Array<Record<string, Object>> = [];
    const allowCoexistence = supportsGeminiMixedBuiltInAndFunctionTools(modelName);
    const hasBuiltinUrl = opts.builtinUrlContext !== undefined
      ? opts.builtinUrlContext
      : (spec.builtinUrlContext !== undefined ? spec.builtinUrlContext : Boolean(provider.builtinUrlContext));
    const hasBuiltinCode = opts.builtinCodeExec !== undefined
      ? opts.builtinCodeExec
      : (spec.builtinCodeExec !== undefined ? spec.builtinCodeExec : Boolean(provider.builtinCodeExec));

    if (allowCoexistence) {
      if (hasBuiltinCode) {
        const ce: Record<string, Object> = {};
        ce['codeExecution'] = new Object();
        gTools.push(ce);
      }
      if (enableBuiltinSearch) {
        const gs: Record<string, Object> = {};
        gs['googleSearch'] = new Object();
        gTools.push(gs);
      }
      if (hasBuiltinUrl) {
        const uc: Record<string, Object> = {};
        uc['urlContext'] = new Object();
        gTools.push(uc);
      }
      if (decls.length > 0) {
        const fnGroup: Record<string, Object> = {};
        fnGroup['functionDeclarations'] = decls;
        gTools.push(fnGroup);
      }
      if ((hasBuiltinCode || enableBuiltinSearch || hasBuiltinUrl) && decls.length > 0 && provider.family !== 'vertex') {
        const fnCallCfg: Record<string, Object> = {};
        fnCallCfg['mode'] = 'VALIDATED';
        const toolCfg: Record<string, Object> = {};
        toolCfg['functionCallingConfig'] = fnCallCfg;
        toolCfg['includeServerSideToolInvocations'] = true;
        body['toolConfig'] = toolCfg;
      }
    } else {
      if (hasBuiltinCode) {
        const ce: Record<string, Object> = {};
        ce['codeExecution'] = new Object();
        gTools.push(ce);
      } else if (enableBuiltinSearch || hasBuiltinUrl) {
        if (enableBuiltinSearch) {
          const gs: Record<string, Object> = {};
          gs['googleSearch'] = new Object();
          gTools.push(gs);
        }
        if (hasBuiltinUrl) {
          const uc: Record<string, Object> = {};
          uc['urlContext'] = new Object();
          gTools.push(uc);
        }
      } else if (decls.length > 0) {
        const fnGroup: Record<string, Object> = {};
        fnGroup['functionDeclarations'] = decls;
        gTools.push(fnGroup);
      }
    }
    if (gTools.length > 0) body['tools'] = gTools;

    mergeCustomBody(body, provider.customBodyJson);
    mergeCustomBodyEntries(body, spec.customBodyEntries);
    mergeCustomBody(body, opts.customBodyJson);
    const cleanModel = encodeURIComponent(modelName.replace(/^models\//, ''));
    const suffix = useStream ? ':streamGenerateContent?alt=sse' : ':generateContent';
    return withOpenCodeGoSession({
      address: base + '/models/' + cleanModel + suffix,
      headers,
      body: JSON.stringify(body)
    }, goSession);
  }

  if (usesResponsesApi(provider)) {
    const inputItems: Array<Record<string, Object>> = [];
    for (let i = 0; i < presets.length; i++) {
      if (!presets[i].content.trim()) continue;
      const item: Record<string, Object> = {};
      item['role'] = presets[i].role;
      item['content'] = presets[i].content;
      inputItems.push(item);
    }
    for (let i = 0; i < history.length; i++) {
      const msg = history[i];
      const files = getAllAttachments(msg);
      const hasImg = files.some((f: Attachment): boolean => f.mime.startsWith('image/') && !!f.data);
      const txt = messageText(msg);
      if (!hasImg && !txt.trim()) continue;
      const item: Record<string, Object> = {};
      item['role'] = msg.role;
      if (hasImg) {
        const respParts: Array<Record<string, Object>> = [];
        if (txt) {
          const tp: Record<string, Object> = {};
          tp['type'] = msg.role === 'assistant' ? 'output_text' : 'input_text';
          tp['text'] = txt;
          respParts.push(tp);
        }
        for (let k = 0; k < files.length; k++) {
          if (files[k].mime.startsWith('image/') && files[k].data) {
            const trimmed = files[k].data.trim();
            const isRemote = /^https?:\/\//i.test(trimmed);
            if (isRemote && spec.allowRemoteImageUrls === false) {
              continue;
            }
            const ip: Record<string, Object> = {};
            ip['type'] = 'input_image';
            ip['image_url'] = isRemote ? trimmed : ('data:' + files[k].mime + ';base64,' + files[k].data);
            respParts.push(ip);
          }
        }
        if (respParts.length === 0) {
          const emptyTxt: Record<string, Object> = {};
          emptyTxt['type'] = msg.role === 'assistant' ? 'output_text' : 'input_text';
          emptyTxt['text'] = ' ';
          respParts.push(emptyTxt);
        }
        item['content'] = respParts;
      } else {
        item['content'] = txt;
      }
      inputItems.push(item);
    }
    for (let i = 0; i < toolTurns.length; i++) {
      const turn = toolTurns[i];
      if (turn.role === 'assistant') {
        if (turn.text && turn.text.trim()) {
          const txtItem: Record<string, Object> = {};
          txtItem['role'] = 'assistant';
          txtItem['content'] = turn.text;
          inputItems.push(txtItem);
        }
        if (turn.toolCalls) {
          for (let j = 0; j < turn.toolCalls.length; j++) {
            const tc = turn.toolCalls[j];
            const fc: Record<string, Object> = {};
            fc['type'] = 'function_call';
            if (planClient) fc['namespace'] = 'kelivo';
            fc['call_id'] = tc.id;
            fc['name'] = tc.name;
            fc['arguments'] = tc.argsDelta || '{}';
            inputItems.push(fc);
          }
        }
      } else if (turn.role === 'tool') {
        const out: Record<string, Object> = {};
        out['type'] = 'function_call_output';
        out['call_id'] = turn.toolCallId || '';
        out['output'] = turn.toolResult || '';
        inputItems.push(out);
      }
    }

    const body: Record<string, Object> = {};
    body['model'] = modelName;
    body['input'] = inputItems;
    body['stream'] = useStream;
    if (prompt) body['instructions'] = prompt;
    if (host.includes('chatgpt.com')) {
      body['store'] = false;
      if (!body['instructions']) body['instructions'] = 'You are a helpful assistant.';
    }
    if (!host.includes('chatgpt.com') && shouldIncludeSampling(spec, control, params, !spec.reasoning)) {
      if (params?.temperature !== undefined) body['temperature'] = params.temperature;
      if (params?.topP !== undefined) body['top_p'] = params.topP;
    }
    if (params?.maxTokens !== undefined && params.maxTokens > 0 && !host.includes('chatgpt.com')) {
      body['max_output_tokens'] = params.maxTokens;
    }
    applyReasoning(body, provider, modelName, control, params);
    if (provider.sendConversationCacheKey && opts.conversationId) {
      body['prompt_cache_key'] = opts.conversationId;
    }
    if (params?.responseSpeed === 'ultrafast' && (host === 'api.openai.com' || provider.oauth?.kind === 'chatgpt')) {
      body['service_tier'] = 'priority';
    }
    const rTools: Array<Record<string, Object>> = [];
    for (let i = 0; i < tools.length; i++) {
      const td = tools[i];
      const rt: Record<string, Object> = {};
      rt['type'] = 'function';
      rt['name'] = td.name;
      rt['description'] = td.description;
      rt['parameters'] = normalizeObjectToolSchema(td.parametersJson);
      rTools.push(rt);
    }
    if (planClient) {
      const planBody: Record<string, Object> = { 'model': modelName, 'input': inputItems, 'store': false, 'stream': true };
      inputItems.forEach((item: Record<string, Object>) => {
        if (item['role'] === 'system') item['role'] = 'developer';
      });
      if (prompt) planBody['instructions'] = prompt;
      if (body['reasoning']) planBody['reasoning'] = body['reasoning'];
      const planTools: Array<Record<string, Object>> = [];
      if (rTools.length) planTools.push({ 'type': 'namespace', 'name': 'kelivo', 'description': 'Kelivo tools', 'tools': rTools });
      if (enableBuiltinSearch) planTools.push({ 'type': 'web_search' });
      if (planTools.length) planBody['tools'] = planTools;
      return { planClient, address: CHATGPT_PLAN_API + '/responses', headers: {}, body: JSON.stringify(planBody) };
    }
    if (enableBuiltinSearch) {
      const builtinTools = buildResponsesBuiltInSearchTools(provider, modelName);
      for (let i = 0; i < builtinTools.length; i++) {
        const bt = builtinTools[i];
        const bType = bt['type'];
        if (!rTools.some((existing: Record<string, Object>): boolean => existing['type'] === bType)) {
          rTools.push(bt);
        }
      }
    }
    const extraRespTools = buildModelExtraResponsesTools(provider, spec);
    for (let i = 0; i < extraRespTools.length; i++) {
      const et = extraRespTools[i];
      const eType = et['type'];
      if (!rTools.some((existing: Record<string, Object>): boolean => existing['type'] === eType)) {
        rTools.push(et);
      }
    }
    if (rTools.length > 0) body['tools'] = rTools;

    mergeCustomBody(body, provider.customBodyJson);
    mergeCustomBodyEntries(body, spec.customBodyEntries);
    mergeCustomBody(body, opts.customBodyJson);
    return withOpenCodeGoSession(
      { address: resolveEndpointUrl(base, provider.chatPath, '/responses'), headers, body: JSON.stringify(body) },
      goSession
    );
  }

  if (provider.family === 'anthropic') {
    const messages: WireMessage[] = [];
    for (let i = 0; i < presets.length; i++) {
      if (presets[i].role !== 'system' && presets[i].content.trim()) {
        pushAnthropicMessage(messages, presets[i].role, presets[i].content);
      }
    }
    for (let i = 0; i < history.length; i++) {
      const msg = history[i];
      const files = getAllAttachments(msg);
      const hasImg = files.some((f: Attachment): boolean => f.mime.startsWith('image/') && !!f.data);
      const txt = messageText(msg);
      if (!hasImg && !txt.trim()) continue;
      pushAnthropicMessage(
        messages,
        msg.role,
        hasImg ? contentParts(msg, 'anthropic', spec.allowRemoteImageUrls !== false) : txt
      );
    }
    for (let i = 0; i < toolTurns.length; i++) {
      const turn = toolTurns[i];
      if (turn.role === 'assistant') {
        const blocks: WirePart[] = [];
        if (turn.text) blocks.push({ type: 'text', text: turn.text });
        if (turn.toolCalls) {
          for (let j = 0; j < turn.toolCalls.length; j++) {
            const tc = turn.toolCalls[j];
            blocks.push({ type: 'tool_use', id: tc.id, name: tc.name, input: parseJsonObjectSafe(tc.argsDelta) });
          }
        }
        if (blocks.length > 0) pushAnthropicMessage(messages, 'assistant', blocks);
      } else {
        pushAnthropicMessage(
          messages,
          'user',
          [{ type: 'tool_result', tool_use_id: turn.toolCallId || '', content: turn.toolResult || '' }]
        );
      }
    }
    const body: Record<string, Object> = {};
    body['model'] = modelName;
    body['messages'] = messages;
    body['max_tokens'] = params?.maxTokens && params.maxTokens > 0 ? params.maxTokens : 4096;
    body['stream'] = useStream;
    if (prompt) {
      if (opts.promptCaching || provider.promptCaching) {
        const sysArr: WirePart[] = [{ type: 'text', text: prompt, cache_control: { type: 'ephemeral' } }];
        body['system'] = sysArr;
      } else {
        body['system'] = prompt;
      }
    }
    applyReasoning(body, provider, modelName, control, params);
    const defaultAnthropicSampling = !spec.reasoning || !params?.reasoningEffort || params.reasoningEffort === 'off';
    if (control.dialect !== 'adaptive' && shouldIncludeSampling(spec, control, params, defaultAnthropicSampling)) {
      if (params?.temperature !== undefined) {
        body['temperature'] = params.temperature;
      } else if (params?.topP !== undefined) {
        body['top_p'] = params.topP;
      }
    }
    const cTools: Array<Record<string, Object>> = [];
    const claimedToolNames = new Set<string>();
    for (let i = 0; i < tools.length; i++) {
      const td = tools[i];
      const ct: Record<string, Object> = {};
      ct['name'] = td.name;
      ct['description'] = td.description;
      ct['input_schema'] = normalizeObjectToolSchema(td.parametersJson);
      cTools.push(ct);
      claimedToolNames.add(td.name);
    }
    if (enableBuiltinSearch && !claimedToolNames.has('web_search')) {
      const wsTool: Record<string, Object> = {};
      wsTool['type'] = claudeSearchToolType(provider, modelName, enableClaudeDynamic);
      wsTool['name'] = 'web_search';
      cTools.push(wsTool);
      claimedToolNames.add('web_search');
    }
    const extraClaudeTools = buildModelExtraClaudeTools(
      provider,
      modelName,
      spec,
      enableClaudeDynamic,
      claimedToolNames
    );
    for (let i = 0; i < extraClaudeTools.length; i++) {
      cTools.push(extraClaudeTools[i]);
    }
    if (cTools.length > 0) {
      body['tools'] = cTools;
    }
    mergeCustomBody(body, provider.customBodyJson);
    mergeCustomBodyEntries(body, spec.customBodyEntries);
    mergeCustomBody(body, opts.customBodyJson);
    return withOpenCodeGoSession(
      { address: resolveEndpointUrl(base, provider.chatPath, '/messages'), headers, body: JSON.stringify(body) },
      goSession
    );
  }

  // OpenAI Chat Completions
  const messages: WireMessage[] = [];
  if (prompt) messages.push({ role: 'system', content: prompt });
  for (let i = 0; i < presets.length; i++) {
    if (!presets[i].content.trim()) continue;
    messages.push({ role: presets[i].role, content: presets[i].content });
  }
  for (let i = 0; i < history.length; i++) {
    const msg = history[i];
    const files = getAllAttachments(msg);
    const hasMedia = files.some((f: Attachment): boolean => (f.mime.startsWith('image/') || f.mime.startsWith('audio/')) && !!f.data);
    const txt = messageText(msg);
    if (!hasMedia && !txt.trim() && i < history.length - 1) continue;
    const wireHist: WireMessage = {
      role: msg.role,
      content: hasMedia ? contentParts(msg, 'openai', spec.allowRemoteImageUrls !== false) : txt
    };
    if (msg.role === 'assistant' && msg.reasoning && spec.reasoningReplay === 'all') {
      setWireMessageReasoning(wireHist, msg.reasoning, spec.reasoningReplayField);
    }
    messages.push(wireHist);
  }
  for (let i = 0; i < toolTurns.length; i++) {
    const turn = toolTurns[i];
    if (turn.role === 'assistant') {
      const openCalls: WireOpenToolCall[] = [];
      if (turn.toolCalls) {
        for (let j = 0; j < turn.toolCalls.length; j++) {
          const tc = turn.toolCalls[j];
          openCalls.push({ id: tc.id, type: 'function', function: { name: tc.name, arguments: tc.argsDelta || '{}' } });
        }
      }
      const wireTurn: WireMessage = {
        role: 'assistant',
        content: turn.text ? turn.text : (openCalls.length ? '' : null),
        tool_calls: openCalls.length ? openCalls : undefined
      };
      if (turn.reasoning && spec.reasoningReplay !== 'none') {
        setWireMessageReasoning(wireTurn, turn.reasoning, spec.reasoningReplayField);
      }
      messages.push(wireTurn);
    } else {
      messages.push({
        role: 'tool',
        tool_call_id: turn.toolCallId || '',
        name: turn.toolName,
        content: turn.toolResult || ''
      });
    }
  }

  const body: Record<string, Object> = {};
  body['model'] = modelName;
  body['messages'] = messages;
  body['stream'] = useStream;
  if (useStream && !isLocalOrCustomHost(provider.baseUrl)) {
    const streamOpts: Record<string, Object> = {};
    streamOpts['include_usage'] = true;
    body['stream_options'] = streamOpts;
  }
  const openAIReasoner = spec.reasoning && /(?:gpt-[56]|\bo[134]\b)/i.test(modelName);
  const defaultOpenAISampling = !openAIReasoner || (params?.reasoningEffort === 'off' && control.levels.includes('off'));
  if (shouldIncludeSampling(spec, control, params, defaultOpenAISampling)) {
    if (params?.temperature !== undefined) body['temperature'] = params.temperature;
    if (params?.topP !== undefined) body['top_p'] = params.topP;
  }
  if (params?.maxTokens !== undefined && params.maxTokens > 0) {
    body[openAIReasoner ? 'max_completion_tokens' : 'max_tokens'] = params.maxTokens;
  }
  applyReasoning(body, provider, modelName, control, params);
  if (provider.sendConversationCacheKey && opts.conversationId) {
    body['prompt_cache_key'] = opts.conversationId;
  }
  if (params?.responseSpeed === 'ultrafast' && (host === 'api.openai.com' || provider.oauth?.kind === 'chatgpt')) {
    body['service_tier'] = 'priority';
  }
  if (tools.length > 0) {
    const oTools: Array<Record<string, Object>> = [];
    for (let i = 0; i < tools.length; i++) {
      const td = tools[i];
      const fnObj: Record<string, Object> = {};
      fnObj['name'] = td.name;
      fnObj['description'] = td.description;
      fnObj['parameters'] = normalizeObjectToolSchema(td.parametersJson);
      const wrap: Record<string, Object> = {};
      wrap['type'] = 'function';
      wrap['function'] = fnObj;
      oTools.push(wrap);
    }
    body['tools'] = oTools;
  }
  mergeCustomBody(body, provider.customBodyJson);
  mergeCustomBodyEntries(body, spec.customBodyEntries);
  mergeCustomBody(body, opts.customBodyJson);
  const finalBody = enableBuiltinSearch
    ? applyChatCompletionsBuiltInSearch(body, provider, modelName)
    : body;
  applyModelExtraChatCompletionsTools(finalBody, provider, spec);
  return withOpenCodeGoSession(
    { address: resolveEndpointUrl(base, provider.chatPath, '/chat/completions'), headers, body: JSON.stringify(finalBody) },
    goSession
  );
}

function usageFromWire(u?: ReplyUsage): TokenUsage | undefined {
  if (!u) return undefined;
  const prompt = u.prompt_tokens ?? u.input_tokens ?? u.promptTokenCount ?? 0;
  const completion = u.completion_tokens ?? u.output_tokens ?? u.candidatesTokenCount ?? 0;
  const cached = u.cache_read_input_tokens ?? u.cachedContentTokenCount ??
    u.prompt_tokens_details?.cached_tokens ?? u.input_tokens_details?.cached_tokens ?? 0;
  const total = u.total_tokens ?? u.totalTokenCount ?? (prompt + completion);
  if (prompt === 0 && completion === 0 && total === 0) return undefined;
  return {
    promptTokens: prompt,
    completionTokens: completion,
    cachedTokens: cached,
    totalTokens: total,
    durationMs: 0
  };
}

function pushAnnotationHit(target: SearchHit[], ann?: ReplyAnnotation): void {
  if (!ann || (ann.type && ann.type !== 'url_citation')) {
    return;
  }
  const url = (ann.url_citation?.url || ann.url || '').trim();
  if (!url) {
    return;
  }
  const title = (ann.url_citation?.title || ann.title || '').trim() || url;
  target.push({ title, url, excerpt: '' });
}

function collectResponsesOutputCitations(target: SearchHit[], output?: ReplyResponseItem[]): void {
  if (!output) {
    return;
  }
  for (let i = 0; i < output.length; i++) {
    const blocks = output[i].content;
    if (!blocks) {
      continue;
    }
    for (let j = 0; j < blocks.length; j++) {
      const anns = blocks[j].annotations;
      if (!anns) {
        continue;
      }
      for (let k = 0; k < anns.length; k++) {
        pushAnnotationHit(target, anns[k]);
      }
    }
  }
}

function collectClaudeBlockCitations(target: SearchHit[], block?: ReplyContentBlock): void {
  if (!block) {
    return;
  }
  if (block.type === 'web_search_tool_result' && Array.isArray(block.content)) {
    const items = block.content;
    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      if (item.type && item.type !== 'web_search_result') {
        continue;
      }
      const url = (item.url || '').trim();
      if (!url) {
        continue;
      }
      const title = (item.title || '').trim() || url;
      target.push({ title, url, excerpt: '' });
    }
  }
  if (block.citations) {
    for (let i = 0; i < block.citations.length; i++) {
      const cite = block.citations[i];
      const url = (cite.url || '').trim();
      if (!url) {
        continue;
      }
      const title = (cite.title || '').trim() || url;
      const excerpt = (cite.cited_text || '').trim();
      target.push({ title, url, excerpt });
    }
  }
}

function collectGeminiGroundingCitations(target: SearchHit[], gm?: ReplyGroundingMetadata): void {
  const chunks = gm?.groundingChunks;
  if (!chunks) {
    return;
  }
  for (let i = 0; i < chunks.length; i++) {
    const ch = chunks[i];
    const web = ch.web ?? ch.webSite ?? ch.webPage;
    if (!web) {
      continue;
    }
    const url = (web.uri || '').trim();
    if (!url) {
      continue;
    }
    const title = (web.title || '').trim() || url;
    target.push({ title, url, excerpt: '' });
  }
}

export function parseRichReply(data: string): RichFragment {
  const result: RichFragment = {
    text: '',
    reasoning: '',
    toolCalls: [],
    generatedImages: [],
    done: false
  };
  if (data === '[DONE]') {
    result.done = true;
    return result;
  }
  const event = JSON.parse(data) as ReplyEvent;
  if (event.type === 'response.failed' || event.type === 'response.incomplete') {
    throw new Error(event.response?.error?.message || '模型响应未完成，请重试或检查套餐用量');
  }
  if (event.error || event.type === 'error') {
    throw new Error(event.error?.message || '模型服务返回错误');
  }

  if ((event.type === 'content_block_start' && event.content_block?.type === 'thinking') ||
    (event.type === 'response.output_item.added' && event.item?.type === 'reasoning')) {
    result.reasoningPhase = 'thinking';
  } else if (event.type === 'content_block_stop' || event.type === 'response.reasoning_summary_text.done' ||
    event.type === 'response.reasoning_text.done' || (event.type === 'response.output_item.done' && event.item?.type === 'reasoning') ||
    event.choices?.[0]?.finish_reason || event.candidates?.[0]?.finishReason) {
    result.reasoningPhase = 'finished';
  }

  // OpenAI Responses API events
  if (event.type === 'response.output_text.delta') {
    if (typeof event.delta === 'string') result.text = event.delta;
    else if (event.delta) result.text = event.delta.text || '';
    return result;
  }
  if (event.type === 'response.reasoning_summary_text.delta' || event.type === 'response.reasoning_text.delta') {
    if (typeof event.delta === 'string') result.reasoning = event.delta;
    else if (event.delta) result.reasoning = event.delta.text || '';
    return result;
  }
  if (event.type === 'response.output_text.annotation.added') {
    const hits: SearchHit[] = [];
    pushAnnotationHit(hits, event.annotation);
    const deduped = mergeDeduplicatedCitations([], hits);
    if (deduped.length > 0) {
      result.citations = deduped;
    }
    return result;
  }
  if (event.type === 'response.output_item.added' && event.item?.type === 'function_call') {
    result.toolCalls.push({
      index: event.output_index ?? 0,
      id: event.item.call_id || event.item.id || '',
      name: event.item.name || '',
      argsDelta: event.item.arguments || '',
      done: false
    });
    return result;
  }
  if (event.type === 'response.function_call_arguments.delta') {
    result.toolCalls.push({
      index: event.output_index ?? 0,
      id: event.call_id || '',
      name: '',
      argsDelta: typeof event.delta === 'string' ? event.delta : (event.delta?.partial_json || ''),
      done: false
    });
    return result;
  }
  if (event.type === 'response.completed') {
    result.done = true;
    result.usage = usageFromWire(event.response?.usage);
    const hits: SearchHit[] = [];
    collectResponsesOutputCitations(hits, event.response?.output);
    const deduped = mergeDeduplicatedCitations([], hits);
    if (deduped.length > 0) {
      result.citations = deduped;
    }
    return result;
  }

  const rawHits: SearchHit[] = [];
  const objDelta: ReplyDelta | undefined = (typeof event.delta === 'object' && event.delta !== null) ? event.delta : undefined;

  // Anthropic tool_use start & delta, plus built-in search result / citation blocks
  if (event.type === 'content_block_start' && event.content_block?.type === 'tool_use') {
    result.toolCalls.push({
      index: event.index ?? 0,
      id: event.content_block.id || '',
      name: event.content_block.name || '',
      argsDelta: '',
      done: false
    });
  }
  if (event.type === 'content_block_start' && event.content_block) {
    collectClaudeBlockCitations(rawHits, event.content_block);
  }
  if (event.type === 'content_block_delta' && objDelta?.type === 'input_json_delta') {
    result.toolCalls.push({
      index: event.index ?? 0,
      id: '',
      name: '',
      argsDelta: objDelta.partial_json || '',
      done: false
    });
  }
  if (event.type === 'content_block_delta' && objDelta?.type === 'citations_delta' && objDelta.citation?.url) {
    const url = objDelta.citation.url.trim();
    if (url) {
      rawHits.push({
        title: (objDelta.citation.title || '').trim() || url,
        url,
        excerpt: (objDelta.citation.cited_text || '').trim()
      });
    }
  }

  // OpenAI Chat Completions & Anthropic deltas
  const choice = event.choices?.[0];
  const delta = choice?.delta ?? choice?.message ?? objDelta;
  if (delta) {
    result.text = delta.content || delta.text || '';
    result.reasoning = delta.reasoning_content || delta.reasoning || delta.thinking || '';
    if (delta.tool_calls) {
      for (let i = 0; i < delta.tool_calls.length; i++) {
        const tc = delta.tool_calls[i];
        result.toolCalls.push({
          index: tc.index ?? i,
          id: tc.id || '',
          name: tc.function?.name || '',
          argsDelta: tc.function?.arguments || '',
          done: false
        });
      }
    }
    if (delta.annotations) {
      for (let i = 0; i < delta.annotations.length; i++) {
        pushAnnotationHit(rawHits, delta.annotations[i]);
      }
    }
  }
  if (choice?.message?.annotations && delta !== choice.message) {
    for (let i = 0; i < choice.message.annotations.length; i++) {
      pushAnnotationHit(rawHits, choice.message.annotations[i]);
    }
  }
  if (event.annotations) {
    for (let i = 0; i < event.annotations.length; i++) {
      pushAnnotationHit(rawHits, event.annotations[i]);
    }
  }
  if (event.citations) {
    for (let i = 0; i < event.citations.length; i++) {
      const cItem = event.citations[i];
      if (typeof cItem === 'string') {
        const cUrl = cItem.trim();
        if (cUrl) {
          rawHits.push({ title: cUrl, url: cUrl, excerpt: '' });
        }
      } else {
        pushAnnotationHit(rawHits, cItem);
      }
    }
  }
  if (event.web_search) {
    for (let i = 0; i < event.web_search.length; i++) {
      const ws = event.web_search[i];
      const url = (ws.link || ws.url || '').trim();
      if (!url) {
        continue;
      }
      rawHits.push({
        title: (ws.title || '').trim() || url,
        url,
        excerpt: (ws.content || '').trim()
      });
    }
  }
  if (event.output) {
    collectResponsesOutputCitations(rawHits, event.output);
  }

  // Gemini / Vertex parts & groundingMetadata
  const gemParts = event.candidates?.[0]?.content?.parts;
  if (gemParts) {
    for (let i = 0; i < gemParts.length; i++) {
      const part = gemParts[i];
      if (part.thought) {
        result.reasoning += part.text || '';
      } else if (part.functionCall) {
        result.toolCalls.push({
          index: i,
          id: 'gem-' + i + '-' + Date.now(),
          name: part.functionCall.name,
          argsDelta: JSON.stringify(part.functionCall.args || {}),
          done: true
        });
      } else if (part.inlineData && part.inlineData.data) {
        result.generatedImages.push({
          name: 'generated-' + Date.now() + '.png',
          mime: part.inlineData.mimeType || 'image/png',
          data: part.inlineData.data,
          kind: 'image'
        });
      } else {
        result.text += part.text || '';
      }
    }
  }
  collectGeminiGroundingCitations(rawHits, event.candidates?.[0]?.groundingMetadata ?? event.groundingMetadata);

  // Anthropic non-stream content blocks
  if (event.content) {
    for (let i = 0; i < event.content.length; i++) {
      const block = event.content[i];
      if (block.type === 'thinking') {
        result.reasoning += block.thinking || '';
      } else if (block.type === 'web_search_tool_result') {
        collectClaudeBlockCitations(rawHits, block);
      } else {
        result.text += block.text || '';
        collectClaudeBlockCitations(rawHits, block);
      }
    }
  }

  const dedupedHits = mergeDeduplicatedCitations([], rawHits);
  if (dedupedHits.length > 0) {
    result.citations = dedupedHits;
  }

  result.usage = usageFromWire(event.usage ?? event.usageMetadata ?? event.message?.usage);
  return result;
}

export function parseReply(data: string): Fragment {
  const rich = parseRichReply(data);
  return { text: rich.text, reasoning: rich.reasoning };
}

export class ThinkTagStreamParser {
  private inThink: boolean = false;
  private carry: string = '';

  push(chunk: string): Fragment {
    let textOut = '';
    let reasonOut = '';
    let closedReasoning = false;
    const buf = this.carry + chunk;
    this.carry = '';
    let i = 0;
    while (i < buf.length) {
      if (!this.inThink) {
        const openThink = buf.indexOf('<think>', i);
        const openThought = buf.indexOf('<thought>', i);
        let idx = -1;
        let tagLen = 0;
        if (openThink >= 0 && (openThought < 0 || openThink < openThought)) {
          idx = openThink;
          tagLen = 7;
        } else if (openThought >= 0) {
          idx = openThought;
          tagLen = 9;
        }
        if (idx >= 0) {
          textOut += buf.slice(i, idx);
          this.inThink = true;
          i = idx + tagLen;
          continue;
        }
        const tailIdx = buf.lastIndexOf('<');
        if (tailIdx >= i && buf.length - tailIdx < 10) {
          const tail = buf.slice(tailIdx);
          if ('<think>'.startsWith(tail) || '<thought>'.startsWith(tail)) {
            textOut += buf.slice(i, tailIdx);
            this.carry = tail;
            break;
          }
        }
        textOut += buf.slice(i);
        break;
      } else {
        const closeThink = buf.indexOf('</think>', i);
        const closeThought = buf.indexOf('</thought>', i);
        let idx = -1;
        let tagLen = 0;
        if (closeThink >= 0 && (closeThought < 0 || closeThink < closeThought)) {
          idx = closeThink;
          tagLen = 8;
        } else if (closeThought >= 0) {
          idx = closeThought;
          tagLen = 10;
        }
        if (idx >= 0) {
          reasonOut += buf.slice(i, idx);
          this.inThink = false;
          closedReasoning = true;
          i = idx + tagLen;
          continue;
        }
        const tailIdx = buf.lastIndexOf('<');
        if (tailIdx >= i && buf.length - tailIdx < 11) {
          const tail = buf.slice(tailIdx);
          if ('</think>'.startsWith(tail) || '</thought>'.startsWith(tail)) {
            reasonOut += buf.slice(i, tailIdx);
            this.carry = tail;
            break;
          }
        }
        reasonOut += buf.slice(i);
        break;
      }
    }
    const fragment: Fragment = { text: textOut, reasoning: reasonOut };
    if (this.inThink) fragment.reasoningPhase = 'thinking';
    else if (closedReasoning) fragment.reasoningPhase = 'finished';
    return fragment;
  }

  flush(): Fragment {
    const rest = this.carry;
    this.carry = '';
    if (!rest) return { text: '', reasoning: '' };
    return this.inThink ? { text: '', reasoning: rest } : { text: rest, reasoning: '' };
  }
}

export function makeImageGenCall(provider: Provider, key: string, prompt: string, modelId?: string,
  conversationId?: string): ChatCall {
  if (planClientId(provider)) throw new Error('ChatGPT 订阅连接暂不支持图片生成');
  const base = checkEndpoint(provider.baseUrl);
  const headers = buildProviderHeaders(provider, key, conversationId);
  const model = (modelId || provider.model || 'dall-e-3').trim();
  if (provider.family === 'gemini' || provider.family === 'vertex') {
    const cleanModel = encodeURIComponent(model.replace(/^models\//, ''));
    const body: Record<string, Object> = {};
    const imgContents: GeminiContent[] = [{ role: 'user', parts: [{ text: prompt }] }];
    body['contents'] = imgContents;
    const genCfg: Record<string, Object> = {};
    genCfg['responseModalities'] = ['TEXT', 'IMAGE'];
    body['generationConfig'] = genCfg;
    return {
      address: base + '/models/' + cleanModel + ':generateContent',
      headers,
      body: JSON.stringify(body)
    };
  }
  const body: Record<string, Object> = {};
  body['model'] = model;
  body['prompt'] = prompt;
  body['n'] = 1;
  body['response_format'] = 'b64_json';
  return {
    address: base + '/images/generations',
    headers,
    body: JSON.stringify(body)
  };
}

interface ImageGenOpenItem { b64_json?: string; url?: string; revised_prompt?: string }
interface ImageGenOpenResp { data?: ImageGenOpenItem[]; error?: RemoteError }

export function parseImageGenResponse(raw: string, family: ApiFamily): Attachment[] {
  if (family === 'gemini' || family === 'vertex') {
    const parsed = parseRichReply(raw);
    return parsed.generatedImages;
  }
  const resp = JSON.parse(raw) as ImageGenOpenResp;
  if (resp.error?.message) throw new Error(resp.error.message);
  const out: Attachment[] = [];
  if (resp.data) {
    for (let i = 0; i < resp.data.length; i++) {
      const item = resp.data[i];
      if (item.b64_json) {
        out.push({
          name: 'image-' + (i + 1) + '.png',
          mime: 'image/png',
          data: item.b64_json,
          kind: 'image'
        });
      }
    }
  }
  return out;
}

// Network chunks can end anywhere in a UTF-8 character, a line, or an SSE event.
// The transport decodes UTF-8 incrementally before passing text here.
export class EventReader {
  private buffer: string = '';
  private lines: string[] = [];
  private emit: (data: string) => void;
  constructor(emit: (data: string) => void) { this.emit = emit; }

  push(chunk: string): void {
    this.buffer += chunk;
    let cut = this.buffer.indexOf('\n');
    while (cut >= 0) {
      this.line(this.buffer.slice(0, cut).replace(/\r$/, ''));
      this.buffer = this.buffer.slice(cut + 1);
      cut = this.buffer.indexOf('\n');
    }
  }
  finish(): void {
    if (this.buffer) this.line(this.buffer.replace(/\r$/, ''));
    this.buffer = '';
    this.line('');
  }
  private line(value: string): void {
    if (value.startsWith('data:')) this.lines.push(value.slice(5).replace(/^ /, ''));
    if (!value && this.lines.length) {
      const data = this.lines.join('\n');
      this.lines = [];
      if (data.trim()) this.emit(data);
    }
  }
}
