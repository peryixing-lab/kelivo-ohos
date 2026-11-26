import { common } from '@kit.AbilityKit';
import {
  ChatMessage,
  Conversation,
  LocalWorkspace,
  McpServerConfig,
  Persona,
  Provider,
  SearchHit,
  SearchServiceConfig,
  UserProfileField,
  Workspace
} from './Models';
import { ToolSchemaCandidate } from '../components/DiagnosticsPanel';
import { RegisteredTool } from './ToolRegistry';
import { ToolCallGroup, ToolExecutionOutput } from './ToolLoop';
import { PromptTemplateContext } from './PromptEngine';
import { buildMemoryTools, executeMemoryToolCall } from './MemoryEngine';
import { buildWorkspaceTools, executeWorkspaceTool } from './WorkspaceTools';
import { buildSkillTools, executeSkillTool } from './SkillsManager';
import { defaultBuiltinSkills } from './SkillsParser';
import { BrowserAgentManager, buildBrowserTools } from './BrowserAgent';
import { AskUserPromptRequest, DeviceToolBridge, buildDeviceTools, executeDeviceTool } from './DeviceTools';
import { McpManager } from './RemoteTools';
import { WebSearch, fetchWebPage } from './WebSearch';
import { Narration } from './Narration';
import { ChatGenerationJob } from './GenerationSession';
import { readKey } from './Storage';
import { selectApiKey } from './KeyPool';
import { ChatStream, completeOnce } from './ChatClient';
import { RichFragment, makeAdvancedChatCall } from './Protocol';
import { buildCompressionPrompt } from './ContextUtils';

export interface ResolvedProviderAuth {
  key: string;
  keyEntryId: string;
  proxyPass: string;
}

export interface ResolvedRoleTarget {
  prov: Provider;
  model: string;
}

export type ChatRoleKind = 'title' | 'summary' | 'suggestions' | 'compress' | 'translate' | 'ocr' | 'memory';

export interface CompressionSummaryResult {
  summary: string;
  modelId: string;
}

export interface ChatToolExecutionEnv {
  workspace: Workspace;
  activeSearchService: () => SearchServiceConfig | undefined;
  workspaceForChat: (chat: Conversation, persona: Persona) => LocalWorkspace | undefined;
  onWorkspaceMutated: () => void;
  mcpManager: McpManager;
  browserManager: BrowserAgentManager;
  shouldOpenBrowserPanel: (chatId: string) => boolean;
  onOpenBrowserPanel: () => void;
  hostContext: common.UIAbilityContext;
  speaker: Narration;
  requestAskUserInput: (job: ChatGenerationJob, req: AskUserPromptRequest) => Promise<string>;
}

/** Resolve active API key (via key pool Strategy or secretRef) and proxy password for a provider. */
export async function resolveProviderKeyAndProxy(p: Provider): Promise<ResolvedProviderAuth> {
  let key = '';
  let keyEntryId = '';
  if (p.apiKeys && p.apiKeys.length > 0) {
    const chosen = selectApiKey(p.id, p.apiKeys, p.keyStrategy || 'round_robin');
    if (chosen) {
      keyEntryId = chosen.id;
      key = await readKey(chosen.secretRef);
    }
  }
  if (!key && p.secretRef) {
    key = await readKey(p.secretRef);
  }
  const proxyPass = p.proxy?.passwordRef ? await readKey(p.proxy.passwordRef) : '';
  return { key, keyEntryId, proxyPass };
}

/** Resolve provider and model configured for a specialized role, falling back to the active chat target. */
export function resolveRoleProviderTarget(
  workspace: Workspace,
  fallbackProv: Provider,
  fallbackModelId: string,
  role: ChatRoleKind
): ResolvedRoleTarget {
  const defs = workspace.modelDefaults;
  let pid = '';
  let mid = '';
  if (defs) {
    if (role === 'title') { pid = defs.titleProviderId; mid = defs.titleModelId; }
    else if (role === 'summary') { pid = defs.summaryProviderId || ''; mid = defs.summaryModelId || ''; }
    else if (role === 'suggestions') { pid = defs.suggestionsProviderId || ''; mid = defs.suggestionsModelId || ''; }
    else if (role === 'compress') { pid = defs.compressProviderId || ''; mid = defs.compressModelId || ''; }
    else if (role === 'translate') { pid = defs.translateProviderId; mid = defs.translateModelId; }
    else if (role === 'ocr') { pid = defs.ocrProviderId; mid = defs.ocrModelId; }
    else { pid = defs.memoryProviderId; mid = defs.memoryModelId; }
  }
  const prov = workspace.providers.find((p: Provider): boolean => p.id === pid && p.enabled !== false) || fallbackProv;
  return { prov, model: mid || (prov.id === fallbackProv.id ? fallbackModelId : prov.model) };
}

/** Collect all built-in, module, and cached MCP tool schemas for diagnostics inspection. */
export function buildChatToolSchemaCandidates(
  mcpServers: McpServerConfig[],
  mcpManager: McpManager
): ToolSchemaCandidate[] {
  const out: ToolSchemaCandidate[] = [
    { name: 'web_search', defaultDescription: '使用联网搜索引擎检索最新公开网页信息', source: 'builtin' },
    { name: 'web_fetch', defaultDescription: '抓取指定网页正文转为纯文本', source: 'builtin' }
  ];
  const groups: RegisteredTool[][] = [
    buildMemoryTools(),
    buildWorkspaceTools(),
    buildSkillTools(),
    buildBrowserTools(),
    buildDeviceTools()
  ];
  for (let g = 0; g < groups.length; g++) {
    const list = groups[g];
    for (let i = 0; i < list.length; i++) {
      out.push({
        name: list[i].declaration.name,
        defaultDescription: list[i].declaration.description,
        source: list[i].source
      });
    }
  }
  for (let i = 0; i < mcpServers.length; i++) {
    const srv = mcpServers[i];
    const cached = mcpManager.getCachedTools(srv.id);
    for (let j = 0; j < cached.length; j++) {
      out.push({
        name: cached[j].name,
        defaultDescription: cached[j].description || cached[j].name,
        source: `mcp:${srv.name}`
      });
    }
  }
  return out;
}

/** Build prompt variable substitution context from user profile and active model/persona metadata. */
export function buildChatTemplateContext(
  userProfile: UserProfileField[],
  personaName: string,
  providerName: string,
  modelId: string,
  chatTitle: string
): PromptTemplateContext {
  let userName = '用户';
  for (let i = 0; i < userProfile.length; i++) {
    const k = userProfile[i].key.trim().toLowerCase();
    if (k === '称呼' || k === '名字' || k === '姓名' || k === 'name' || k === 'user') {
      userName = userProfile[i].value.trim();
      break;
    }
  }
  return {
    userName,
    assistantName: personaName,
    modelName: modelId,
    providerName,
    conversationTitle: chatTitle
  };
}

/** Generate a short conversation title from the first user/assistant exchange. */
export async function generateAutoChatTitle(
  workspace: Workspace,
  fallbackProv: Provider,
  fallbackModelId: string,
  chatId: string,
  firstQuestion: string,
  firstAnswer: string
): Promise<string> {
  if (!workspace.systemSettings?.autoTitleEnabled) return '';
  try {
    const target = resolveRoleProviderTarget(workspace, fallbackProv, fallbackModelId, 'title');
    const auth = await resolveProviderKeyAndProxy(target.prov);
    if (!target.model) return '';
    const title = await completeOnce(
      target.prov, auth.key,
      '请根据下面这轮对话生成一个简短准确的中文或原文标题（不超过16个字，不加引号和标点）。',
      '用户：' + firstQuestion.slice(0, 400) + '\n助手：' + firstAnswer.slice(0, 400),
      target.model, 64, auth.proxyPass, chatId
    );
    return title.replace(/["'《》「」]/g, '').trim().slice(0, 28);
  } catch (_) {
    return '';
  }
}

/** Generate up to 3 short follow-up question suggestions for the latest exchange. */
export async function generateChatSuggestions(
  workspace: Workspace,
  fallbackProv: Provider,
  fallbackModelId: string,
  chatId: string,
  lastQuestion: string,
  lastAnswer: string
): Promise<string[]> {
  if (!workspace.systemSettings?.chatSuggestionsEnabled) return [];
  try {
    const roleTarget = resolveRoleProviderTarget(workspace, fallbackProv, fallbackModelId, 'suggestions');
    const auth = await resolveProviderKeyAndProxy(roleTarget.prov);
    const model = roleTarget.model;
    if (!model) return [];
    const raw = await completeOnce(
      roleTarget.prov, auth.key,
      '根据对话末尾内容，用一行一个的格式给出 3 个简短的后续追问建议（每条不超过18字，不要序号）。',
      '问：' + lastQuestion.slice(0, 300) + '\n答：' + lastAnswer.slice(0, 500),
      model, 120, auth.proxyPass, chatId
    );
    return raw.split('\n').map((s: string): string => s.replace(/^[-*•\d.]+\s*/, '').trim())
      .filter((s: string): boolean => s.length > 1 && s.length <= 36).slice(0, 3);
  } catch (_) {
    return [];
  }
}

/** Translate a message between Chinese and English using the configured translation role model. */
export async function translateChatMessageText(
  workspace: Workspace,
  fallbackProv: Provider,
  fallbackModelId: string,
  chatId: string,
  text: string
): Promise<string> {
  const role = resolveRoleProviderTarget(workspace, fallbackProv, fallbackModelId, 'translate');
  const auth = await resolveProviderKeyAndProxy(role.prov);
  return completeOnce(
    role.prov, auth.key,
    '若输入主要为中文请译为地道英文，否则译为地道简体中文，保留格式，只输出译文。',
    text, role.model, 2048, auth.proxyPass, chatId
  );
}

/** Extract plain text from a data-URI image using the configured OCR role model. */
export async function runChatOcrOnImage(
  workspace: Workspace,
  fallbackProv: Provider,
  fallbackModelId: string,
  chatId: string | undefined,
  dataUri: string
): Promise<string> {
  const comma = dataUri.indexOf(',');
  if (comma < 0) throw new Error('仅支持对本地/Base64 图片执行 OCR');
  const meta = dataUri.slice(5, comma);
  const mime = meta.split(';')[0] || 'image/png';
  const b64 = dataUri.slice(comma + 1);
  const role = resolveRoleProviderTarget(workspace, fallbackProv, fallbackModelId, 'ocr');
  const auth = await resolveProviderKeyAndProxy(role.prov);
  const ocrMsg: ChatMessage = {
    id: 'ocr',
    role: 'user',
    text: '请准确提取图片中的所有文字内容并保持原有排版，不添加额外解释。',
    model: '',
    attachment: { name: 'ocr.png', mime, data: b64, kind: 'image' }
  };
  const call = makeAdvancedChatCall(role.prov, auth.key, '', [ocrMsg], { modelId: role.model, conversationId: chatId });
  const s = new ChatStream();
  let out = '';
  await s.runRich(call, (frag: RichFragment) => { out += frag.text; });
  return out.trim();
}

/** Generate a compressed context summary string for context window compaction. */
export async function generateChatCompressionSummary(
  workspace: Workspace,
  fallbackProv: Provider,
  fallbackModelId: string,
  messages: ChatMessage[],
  template: string,
  chatId: string
): Promise<CompressionSummaryResult> {
  const roleTarget = resolveRoleProviderTarget(workspace, fallbackProv, fallbackModelId, 'compress');
  const auth = await resolveProviderKeyAndProxy(roleTarget.prov);
  const modelId = roleTarget.model || fallbackModelId;
  const summary = await completeOnce(
    roleTarget.prov, auth.key, '你是精准的上下文压缩助手。',
    buildCompressionPrompt(messages, template), modelId, 1200, auth.proxyPass, chatId
  );
  return { summary, modelId };
}

/** Dispatch a registered tool invocation to web search/fetch, memory, workspace, skill, browser, device, or MCP. */
export async function executeChatRegisteredTool(
  tool: RegisteredTool,
  argsJson: string,
  chat: Conversation,
  persona: Persona,
  job: ChatGenerationJob,
  env: ChatToolExecutionEnv
): Promise<ToolExecutionOutput> {
  let parsed: Record<string, Object> = {};
  try {
    const obj = JSON.parse(argsJson || '{}') as Record<string, Object>;
    if (obj && typeof obj === 'object') {
      parsed = obj;
    }
  } catch (_) {
    return { text: '工具参数 JSON 解析失败', isError: true };
  }
  if (tool.declaration.name === 'web_search') {
    const query = String(parsed['query'] || '');
    const svc = env.activeSearchService();
    if (!svc) return { text: '未配置搜索服务', isError: true };
    const searcher = new WebSearch();
    job.searcher = searcher;
    const fallbackKey = env.workspace.search?.secretRef ? await readKey(env.workspace.search.secretRef) : '';
    const hits = await searcher.findWithService(svc, fallbackKey, query);
    if (!hits.length) return { text: '未找到相关网页结果' };
    const out = hits.map((h: SearchHit, idx: number): string =>
      '[' + (idx + 1) + '] ' + h.title + '\nURL: ' + h.url + '\n摘要: ' + h.excerpt
    ).join('\n\n');
    return { text: out };
  }
  if (tool.declaration.name === 'web_fetch') {
    const url = String(parsed['url'] || '');
    const maxChars = Number(parsed['max_chars'] || 8000);
    const offset = Number(parsed['offset'] || 0);
    const txt = await fetchWebPage(url, maxChars, offset);
    return { text: txt };
  }
  if (tool.source === 'memory') {
    const current = env.workspace.personas.find((item: Persona): boolean => item.id === persona.id) || persona;
    const outcome = executeMemoryToolCall(
      tool.declaration.name, parsed, env.workspace.memories || [], env.workspace.userProfile || [],
      env.workspace.conversations, chat, current, env.workspace.memorySettings?.injectGlobal !== false
    );
    if (outcome.memories || outcome.profile) {
      if (outcome.memories) env.workspace.memories = outcome.memories;
      if (outcome.profile) env.workspace.userProfile = outcome.profile;
      env.onWorkspaceMutated();
    }
    return { text: outcome.text, isError: outcome.isError };
  }
  if (tool.source === 'workspace') {
    return executeWorkspaceTool(
      tool.declaration.name,
      argsJson,
      env.workspaceForChat(chat, persona),
      env.workspace.envVars || []
    );
  }
  if (tool.source === 'skill') {
    return executeSkillTool(argsJson, env.workspace.skills || defaultBuiltinSkills());
  }
  if (tool.source === 'browser') {
    if (env.shouldOpenBrowserPanel(chat.id)) {
      env.onOpenBrowserPanel();
    }
    return env.browserManager.executeAction(argsJson, env.workspace.workspaces || []);
  }
  if (tool.source === 'device') {
    const bridge: DeviceToolBridge = {
      hostContext: env.hostContext,
      speakText: async (text: string): Promise<void> => {
        const ttsCfg = env.workspace.tts;
        if (ttsCfg && ttsCfg.engine !== 'system') {
          const key = ttsCfg.secretRef ? await readKey(ttsCfg.secretRef) : '';
          await env.speaker.playWithConfig(text, ttsCfg, key, env.hostContext.cacheDir, () => {});
        } else {
          await env.speaker.play(text, () => {});
        }
      },
      askUserInput: (req: AskUserPromptRequest): Promise<string> => env.requestAskUserInput(job, req),
      getConversations: (): Conversation[] => env.workspace.conversations,
      getActiveConversation: (): Conversation | undefined =>
        env.workspace.conversations.find((item: Conversation): boolean => item.id === chat.id) || chat
    };
    return executeDeviceTool(tool.declaration.name, argsJson, bridge);
  }
  if (tool.source === 'mcp' && tool.serverId) {
    const res = await env.mcpManager.invokeMcpTool(tool.serverId, tool.declaration.name, argsJson);
    return { text: res.text, images: res.images };
  }
  return { text: '未实现的工具: ' + tool.declaration.name, isError: true };
}

/** Classify a conversation into drawer section headers ('置顶', '今天', '昨天', '近 7 天', '更早'). */
export function formatChatDateGroupLabel(c: Conversation): string {
  if (c.pinned) return '置顶';
  const d = new Date(c.updated || Date.now());
  const now = new Date();
  const startToday = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
  const dayStart = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
  const diffDays = Math.round((startToday - dayStart) / 86400000);
  if (diffDays <= 0) return '今天';
  if (diffDays === 1) return '昨天';
  if (diffDays <= 7) return '近 7 天';
  return '更早';
}

/** Return true if conversation `idx` starts a new date group in `rows`. */
export function isChatDrawerGroupStart(rows: Conversation[], idx: number): boolean {
  if (idx <= 0) return true;
  return formatChatDateGroupLabel(rows[idx]) !== formatChatDateGroupLabel(rows[idx - 1]);
}

/** Format epoch timestamp in milliseconds as HH:MM for message timestamps. */
export function formatChatMessageTime(ts?: number): string {
  if (!ts) return '';
  const d = new Date(ts);
  const hh = String(d.getHours()).padStart(2, '0');
  const mm = String(d.getMinutes()).padStart(2, '0');
  return `${hh}:${mm}`;
}

/** Format full usage badge text including prompt, completion, cached tokens, and duration. */
export function formatChatUsageBadge(msg: ChatMessage): string {
  if (!msg.usage) return '';
  return '↑' + msg.usage.promptTokens + ' ↓' + msg.usage.completionTokens +
    (msg.usage.cachedTokens ? ' ⚡' + msg.usage.cachedTokens : '') +
    (msg.usage.durationMs ? ' · ' + (msg.usage.durationMs / 1000).toFixed(1) + 's' : '');
}

/** Format compact total token counter shown in the assistant action row. */
export function formatChatCompactTokens(msg: ChatMessage): string {
  if (!msg.usage) return '';
  const total = msg.usage.totalTokens > 0
    ? msg.usage.totalTokens
    : (msg.usage.promptTokens + msg.usage.completionTokens);
  return total > 0 ? `${total} tokens` : '';
}

/** Map internal tool identifier to user-facing Chinese label in chat activity cards. */
export function chatToolRowLabel(name: string): string {
  switch (name) {
    case 'memory_update': return '更新记忆';
    case 'memory_read': return '读取记忆';
    case 'memory_search_profile': return '查找记忆';
    case 'memory_edit': return '编辑记忆';
    case 'memory_delete': return '归档记忆';
    case 'update_user_profile': return '更新用户画像';
    case 'web_search': return '搜索网页';
    case 'web_fetch': return '读取网页';
    case '$web_search':
    case 'builtin_search': return '模型内置搜索';
    default: return name;
  }
}

/** Map tool call record execution status to localized badge text. */
export function chatToolRecordStatusLabel(status: string): string {
  if (status === 'pending') return '待授权';
  if (status === 'running') return '执行中';
  if (status === 'denied') return '已拒绝';
  if (status === 'error') return '失败';
  return '完成';
}

/** Map grouped tool call status to summary badge text. */
export function chatToolGroupBadgeText(grp: ToolCallGroup): string {
  if (grp.status === 'pending') return '待授权';
  if (grp.status === 'running') return '执行中';
  if (grp.status === 'denied') return '已拒绝';
  if (grp.status === 'error') return '失败';
  if (grp.failedCount > 0) return `${grp.failedCount} 次失败`;
  return '';
}

/** Format byte size into B / KB / MB for settings display. */
export function formatStorageSizeLabel(totalBytes: number): string {
  if (totalBytes < 1024) {
    return `${totalBytes} B`;
  }
  if (totalBytes < 1024 * 1024) {
    return `${(totalBytes / 1024).toFixed(1)} KB`;
  }
  return `${(totalBytes / (1024 * 1024)).toFixed(1)} MB`;
}
