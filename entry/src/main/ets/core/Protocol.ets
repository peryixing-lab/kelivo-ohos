import {
  ApiFamily,
  Attachment,
  ChatMessage,
  GenerationParams,
  HeaderEntry,
  ModelSpec,
  PresetMessage,
  Provider,
  TokenUsage,
  checkEndpoint,
  extractUrlHost,
  findProviderModelSpec,
  getAllAttachments,
  isLocalOrCustomHost,
  messageText
} from './Models';

interface WireMessage {
  role: string;
  content: string | WirePart[] | null;
  reasoning_content?: string;
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
export interface ChatCall { address: string; headers: Record<string, string>; body: string }

interface ReplyToolFn { name?: string; arguments?: string }
interface ReplyToolCallItem { index?: number; id?: string; type?: string; function?: ReplyToolFn }
interface ReplyDelta {
  content?: string;
  text?: string;
  reasoning_content?: string;
  reasoning?: string;
  thinking?: string;
  partial_json?: string;
  type?: string;
  tool_calls?: ReplyToolCallItem[];
}
interface ReplyChoice { delta?: ReplyDelta; message?: ReplyDelta; finish_reason?: string }
interface Candidate { content?: GeminiContent; finishReason?: string }
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
}
interface ReplyResponseItem {
  id?: string;
  type?: string;
  call_id?: string;
  name?: string;
  arguments?: string;
}
interface ReplyResponseObj { usage?: ReplyUsage }
interface ReplyMessageStart { usage?: ReplyUsage }
interface ReplyEvent {
  type?: string;
  choices?: ReplyChoice[];
  delta?: ReplyDelta | string;
  content?: WirePart[];
  content_block?: ReplyContentBlock;
  item?: ReplyResponseItem;
  response?: ReplyResponseObj;
  message?: ReplyMessageStart;
  output_index?: number;
  call_id?: string;
  item_id?: string;
  index?: number;
  candidates?: Candidate[];
  usage?: ReplyUsage;
  usageMetadata?: ReplyUsage;
  error?: RemoteError;
}

export interface Fragment { text: string; reasoning: string }

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

export interface RichFragment {
  text: string;
  reasoning: string;
  toolCalls: ToolCallDelta[];
  usage?: TokenUsage;
  generatedImages: Attachment[];
  done: boolean;
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

const OPEN_CODE_USER_AGENT = 'LexiKelivo/1.0 (HarmonyOS)';

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

function contentParts(msg: ChatMessage, family: ApiFamily): WirePart[] {
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
      if (family === 'openai' || family === 'openai-responses') {
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
    return {
      address: base + '/models/' + modelId + ':streamGenerateContent?alt=sse',
      headers,
      body: JSON.stringify(payload)
    };
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
    return { address: resolveEndpointUrl(base, provider.chatPath, '/messages'), headers, body: JSON.stringify(claude) };
  }
  const body: OpenBody = { model: provider.model, messages, stream: true };
  return { address: resolveEndpointUrl(base, provider.chatPath, '/chat/completions'), headers, body: JSON.stringify(body) };
}

function mergeCustomBody(target: Record<string, Object>, rawJson?: string): void {
  if (!rawJson || !rawJson.trim()) return;
  try {
    const extra = JSON.parse(rawJson) as Record<string, Object>;
    if (extra && typeof extra === 'object') {
      Object.keys(extra).forEach((k: string) => {
        target[k] = extra[k];
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

export function canDisableModelThinking(modelName: string): boolean {
  return !/(deepseek-r1|deepseek-reasoner|\bqwq\b|qwen3[^\s]*thinking|\bo1\b|\bo3\b|\bo4\b|gemini-2\.5-pro)/i.test(modelName);
}

export function applyOpenAIChatReasoning(
  body: Record<string, Object>,
  provider: Provider,
  modelName: string,
  spec: ModelSpec,
  params?: GenerationParams
): void {
  if (!spec.reasoning || !params || !params.reasoningEffort) return;
  const effort = params.reasoningEffort;
  const isOff = effort === 'off';
  const canDisable = canDisableModelThinking(modelName);
  const host = (provider.baseUrl || '').toLowerCase();
  const lower = modelName.toLowerCase();

  if (host.includes('openrouter.ai')) {
    if (isOff && canDisable) {
      const r: Record<string, Object> = {};
      r['enabled'] = false;
      body['reasoning'] = r;
    } else if (!isOff) {
      const r: Record<string, Object> = {};
      r['effort'] = effort === 'max' ? 'high' : effort;
      body['reasoning'] = r;
    }
    return;
  }

  if (host.includes('siliconflow')) {
    if (isOff && canDisable) {
      body['enable_thinking'] = false;
    } else if (!isOff) {
      body['enable_thinking'] = true;
      if (params.reasoningBudget && params.reasoningBudget > 0) {
        body['thinking_budget'] = params.reasoningBudget;
      }
    }
    return;
  }

  if (host.includes('dashscope') || /(qwen3|qwq)/i.test(lower)) {
    if (!canDisable) {
      if (!isOff && params.reasoningBudget && params.reasoningBudget > 0) {
        body['thinking_budget'] = params.reasoningBudget;
      }
    } else if (isOff) {
      body['enable_thinking'] = false;
    } else {
      body['enable_thinking'] = true;
      if (params.reasoningBudget && params.reasoningBudget > 0) {
        body['thinking_budget'] = params.reasoningBudget;
      }
    }
    return;
  }

  if (
    /(deepseek|glm-4\.[5-9]|glm-5|glm-z1|doubao.*thinking|seed-1)/i.test(lower) ||
    host.includes('deepseek.com') ||
    host.includes('bigmodel.cn') ||
    host.includes('volces.com')
  ) {
    if (isOff) {
      if (canDisable) {
        const t: Record<string, Object> = {};
        t['type'] = 'disabled';
        body['thinking'] = t;
      }
    } else {
      const t: Record<string, Object> = {};
      t['type'] = 'enabled';
      body['thinking'] = t;
      if (lower.includes('deepseek')) {
        body['reasoning_effort'] = effort === 'medium' ? 'low' : effort;
      }
    }
    return;
  }

  if (/(kimi-k2|moonshot)/i.test(lower) || host.includes('moonshot')) {
    if (isOff && canDisable) {
      const t: Record<string, Object> = {};
      t['type'] = 'disabled';
      body['thinking'] = t;
    } else if (!isOff) {
      const t: Record<string, Object> = {};
      t['type'] = 'enabled';
      t['effort'] = effort === 'max' ? 'high' : effort;
      body['thinking'] = t;
    }
    return;
  }

  if (/(internlm|intern-s1)/i.test(lower)) {
    body['thinking_mode'] = !isOff;
    return;
  }

  if (/(o1|o3|o4|gpt-5|gpt-6|gpt-oss|grok-3-mini)/i.test(lower)) {
    if (isOff) {
      if (canDisable) {
        body['reasoning_effort'] = 'none';
      }
    } else {
      body['reasoning_effort'] = effort === 'max' ? 'high' : effort;
    }
  }
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
  const base = checkEndpoint(provider.baseUrl);
  const host = extractUrlHost(provider.baseUrl);
  const headers = buildProviderHeaders(provider, key, opts.conversationId, opts.customHeaders, opts.promptCaching);
  const params = opts.params;
  const spec = opts.modelSpec || findProviderModelSpec(provider, modelName);
  const useStream = opts.stream !== false;
  const wantReason = Boolean(params?.reasoningEffort && params.reasoningEffort !== 'off');

  const tools = opts.tools || [];
  const toolTurns = opts.toolTurns || [];
  const presets = opts.presetMessages || [];

  if (provider.family === 'gemini' || provider.family === 'vertex') {
    const contents: GeminiContent[] = [];
    for (let i = 0; i < presets.length; i++) {
      const pm = presets[i];
      if (!pm.content.trim()) continue;
      contents.push({ role: pm.role === 'assistant' ? 'model' : 'user', parts: [{ text: pm.content }] });
    }
    for (let i = 0; i < history.length; i++) {
      const msg = history[i];
      const parts = contentParts(msg, provider.family);
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
    if (params?.temperature !== undefined) genCfg['temperature'] = params.temperature;
    if (params?.topP !== undefined) genCfg['topP'] = params.topP;
    if (params?.maxTokens !== undefined && params.maxTokens > 0) genCfg['maxOutputTokens'] = params.maxTokens;
    if (wantReason && spec.reasoning) {
      const thinkCfg: Record<string, Object> = {};
      const budget = params!.reasoningBudget && params!.reasoningBudget > 0 ? params!.reasoningBudget :
        (params!.reasoningEffort === 'low' ? 1024 : params!.reasoningEffort === 'high' ? 16384 : params!.reasoningEffort === 'max' ? 24576 : 4096);
      thinkCfg['thinkingBudget'] = budget;
      thinkCfg['includeThoughts'] = true;
      genCfg['thinkingConfig'] = thinkCfg;
    } else if (spec.reasoning && params?.reasoningEffort === 'off' && canDisableModelThinking(modelName)) {
      const thinkCfg: Record<string, Object> = {};
      thinkCfg['thinkingBudget'] = 0;
      thinkCfg['includeThoughts'] = false;
      genCfg['thinkingConfig'] = thinkCfg;
    }
    if (Object.keys(genCfg).length > 0) body['generationConfig'] = genCfg;

    const gTools: Array<Record<string, Object>> = [];
    if (tools.length > 0) {
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
      const fnGroup: Record<string, Object> = {};
      fnGroup['functionDeclarations'] = decls;
      gTools.push(fnGroup);
    } else {
      if (opts.builtinSearch || provider.builtinSearch) {
        const gs: Record<string, Object> = {};
        gs['googleSearch'] = new Object();
        gTools.push(gs);
      }
      if (opts.builtinUrlContext || provider.builtinUrlContext) {
        const uc: Record<string, Object> = {};
        uc['urlContext'] = new Object();
        gTools.push(uc);
      }
      if (opts.builtinCodeExec || provider.builtinCodeExec) {
        const ce: Record<string, Object> = {};
        ce['codeExecution'] = new Object();
        gTools.push(ce);
      }
    }
    if (gTools.length > 0) body['tools'] = gTools;

    mergeCustomBody(body, provider.customBodyJson);
    mergeCustomBody(body, opts.customBodyJson);
    const cleanModel = encodeURIComponent(modelName.replace(/^models\//, ''));
    const suffix = useStream ? ':streamGenerateContent?alt=sse' : ':generateContent';
    return {
      address: base + '/models/' + cleanModel + suffix,
      headers,
      body: JSON.stringify(body)
    };
  }

  const chatPath = (provider.chatPath || '').trim().replace(/^\/+|\/+$/g, '');
  const forcesChatCompletionsPath = /^(?:v1\/)?chat\/completions$/i.test(chatPath);
  // Any provider pointing explicitly to /chat/completions must use Chat Completions wire format.
  if (provider.family === 'openai-responses' && !forcesChatCompletionsPath) {
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
            const ip: Record<string, Object> = {};
            ip['type'] = 'input_image';
            ip['image_url'] = 'data:' + files[k].mime + ';base64,' + files[k].data;
            respParts.push(ip);
          }
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
    if (!spec.reasoning && !host.includes('chatgpt.com')) {
      if (params?.temperature !== undefined) body['temperature'] = params.temperature;
      if (params?.topP !== undefined) body['top_p'] = params.topP;
    }
    if (params?.maxTokens !== undefined && params.maxTokens > 0 && !host.includes('chatgpt.com')) {
      body['max_output_tokens'] = params.maxTokens;
    }
    if (wantReason && spec.reasoning && params) {
      const reas: Record<string, Object> = {};
      reas['effort'] = params.reasoningEffort === 'max' ? 'high' : (params.reasoningEffort || 'medium');
      body['reasoning'] = reas;
    } else if (spec.reasoning && params?.reasoningEffort === 'off' && canDisableModelThinking(modelName)) {
      const reas: Record<string, Object> = {};
      reas['effort'] = 'none';
      body['reasoning'] = reas;
    }
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
    if (opts.builtinSearch || provider.builtinSearch) {
      const ws: Record<string, Object> = {};
      ws['type'] = 'web_search_preview';
      rTools.push(ws);
    }
    if (rTools.length > 0) body['tools'] = rTools;

    mergeCustomBody(body, provider.customBodyJson);
    mergeCustomBody(body, opts.customBodyJson);
    return { address: resolveEndpointUrl(base, provider.chatPath, '/responses'), headers, body: JSON.stringify(body) };
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
      pushAnthropicMessage(messages, msg.role, hasImg ? contentParts(msg, 'anthropic') : txt);
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
    const enableThinking = wantReason && spec.reasoning;
    if (enableThinking && params) {
      const budget = params.reasoningBudget && params.reasoningBudget > 1024 ? params.reasoningBudget :
        (params.reasoningEffort === 'low' ? 2048 : params.reasoningEffort === 'high' ? 12000 : params.reasoningEffort === 'max' ? 20000 : 4096);
      const thinkObj: Record<string, Object> = {};
      thinkObj['type'] = 'enabled';
      thinkObj['budget_tokens'] = budget;
      body['thinking'] = thinkObj;
      if ((body['max_tokens'] as number) <= budget) body['max_tokens'] = budget + 4096;
    } else {
      if (params?.temperature !== undefined) {
        body['temperature'] = params.temperature;
      } else if (params?.topP !== undefined) {
        body['top_p'] = params.topP;
      }
    }
    if (tools.length > 0) {
      const cTools: Array<Record<string, Object>> = [];
      for (let i = 0; i < tools.length; i++) {
        const td = tools[i];
        const ct: Record<string, Object> = {};
        ct['name'] = td.name;
        ct['description'] = td.description;
        ct['input_schema'] = normalizeObjectToolSchema(td.parametersJson);
        cTools.push(ct);
      }
      body['tools'] = cTools;
    }
    mergeCustomBody(body, provider.customBodyJson);
    mergeCustomBody(body, opts.customBodyJson);
    return { address: resolveEndpointUrl(base, provider.chatPath, '/messages'), headers, body: JSON.stringify(body) };
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
    messages.push({ role: msg.role, content: hasMedia ? contentParts(msg, 'openai') : txt });
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
      if (turn.reasoning) {
        wireTurn.reasoning_content = turn.reasoning;
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
  if (params?.temperature !== undefined) body['temperature'] = params.temperature;
  if (params?.topP !== undefined) body['top_p'] = params.topP;
  if (params?.maxTokens !== undefined && params.maxTokens > 0) body['max_tokens'] = params.maxTokens;
  applyOpenAIChatReasoning(body, provider, modelName, spec, params);
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
  mergeCustomBody(body, opts.customBodyJson);
  return { address: resolveEndpointUrl(base, provider.chatPath, '/chat/completions'), headers, body: JSON.stringify(body) };
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
  if (event.error || event.type === 'error') {
    throw new Error(event.error?.message || '模型服务返回错误');
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
    return result;
  }

  const objDelta: ReplyDelta | undefined = (typeof event.delta === 'object' && event.delta !== null) ? event.delta : undefined;

  // Anthropic tool_use start & delta
  if (event.type === 'content_block_start' && event.content_block?.type === 'tool_use') {
    result.toolCalls.push({
      index: event.index ?? 0,
      id: event.content_block.id || '',
      name: event.content_block.name || '',
      argsDelta: '',
      done: false
    });
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
  }

  // Gemini / Vertex / Anthropic non-stream parts
  const parts = event.candidates?.[0]?.content?.parts ?? event.content;
  if (parts) {
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i];
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
    return { text: textOut, reasoning: reasonOut };
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
