import { completeOnce } from './ChatClient';
import {
  applySmartAddDecisions,
  buildExistingMemoryXmlBlock,
  buildProfileBlock,
  canReadMemory,
  EXTRACT_TOOL_DEFAULT_SCOPE_RULE_EN,
  EXTRACT_TOOL_DEFAULT_SCOPE_RULE_ZH,
  ExtractedMemoryCandidate,
  ExtractedProfileCandidate,
  findExactActiveMemory,
  findSmartAddCandidates,
  GatekeeperDecision,
  getEffectiveMemoryTemplate,
  memoryDate,
  MemoryExtractionResult,
  memoryTypeName,
  memoryWriteAssistantId,
  mergeMemoryCandidates,
  mergeProfileFields,
  normalizeMemoryCategory,
  parseExtractedMemoriesResult,
  parseGatekeeperResult,
  parseMemoryExtractionResponse,
  parseProfileDistillerResponse,
  parseSmartAddBatchResponse,
  parseSmartAddSingleResponse,
  resolveMemoryPromptLang,
  searchMemories,
  SmartAddDecision
} from './MemoryLogic';
import {
  ChatMessage,
  Conversation,
  MemoryEntry,
  MemorySettings,
  MemorySmartAddMode,
  MemoryTraceStep,
  MemoryWriteScope,
  messageText,
  Persona,
  Provider,
  ReasoningEffort,
  RequestLogEntry,
  UserProfileField
} from './Models';
import { RegisteredTool } from './ToolRegistry';

export interface MemoryToolOutcome {
  text: string;
  memories?: MemoryEntry[];
  profile?: UserProfileField[];
  isError?: boolean;
}

export interface MemoryBatchResult {
  snippet: string;
  endMessageId: string;
  windowSize: number;
}

export interface MemoryPipelineRunInput {
  provider: Provider;
  apiKey: string;
  modelId: string;
  proxyPassword?: string;
  conversationId: string;
  assistantId: string;
  snippet: string;
  existingMemories: MemoryEntry[];
  existingProfile: UserProfileField[];
  settings: MemorySettings;
  writeScope: MemoryWriteScope;
  smartAddMode: MemorySmartAddMode;
  assistantReasoning?: ReasoningEffort;
  uiLanguage?: string;
  onLog?: (entry: RequestLogEntry) => void;
}

export interface MemoryPipelineRunOutput {
  shouldSave: boolean;
  advanced: boolean;
  gateStatus: GatekeeperDecision;
  error?: string;
  summary: string;
  memories: MemoryEntry[];
  profile: UserProfileField[];
  addedCount: number;
  mergedCount: number;
  conflictCount: number;
  skippedCount: number;
  profileUpdatedCount: number;
  steps: MemoryTraceStep[];
}

const EXTRACTION_SYSTEM_PROMPT =
  '从这些对话中提炼用户明确表达且跨会话仍有效的信息。只根据用户的话判断，助手回复仅用于理解语境。\n' +
  '一次性任务、临时报错、密钥等敏感凭据不要保存。把不同事实拆成独立、简洁的第三人称陈述。\n' +
  '只输出 JSON：{"shouldSave":boolean,"summary":"简短原因",' +
  '"memories":[{"category":"identity|workflow|voice|instruction","content":"陈述"}],' +
  '"profile":[{"key":"preferred_name|gender|pronouns|preferred_language|timezone|occupation|location","value":"值"}]}';

const TYPE_SCHEMA = '{"type":"string","enum":["identity","workflow","voice","instruction"]}';

function memoryTool(name: string, description: string, properties: string, required: string = '[]'): RegisteredTool {
  return {
    declaration: {
      name,
      description,
      parametersJson: '{"type":"object","properties":{' + properties + '},"required":' + required + '}'
    },
    source: 'memory',
    requiresApproval: false
  };
}

export function buildMemoryTools(
  enabled: boolean = true,
  recall: boolean = true,
  allowWrites: boolean = true,
  scope: MemoryWriteScope = 'toolDefaultGlobal',
  includeGlobal: boolean = true,
  lang: 'zh' | 'en' = 'zh'
): RegisteredTool[] {
  const tools: RegisteredTool[] = [];
  const isEn = lang === 'en';
  if (enabled) {
    tools.push(memoryTool(
      'memory_read',
      isEn
        ? 'Read visible long-term memories with pagination when summary mode truncates items or IDs are needed.'
        : '分页读取可见的长期记忆，摘要被截断或需要条目 ID 时使用。',
      '"type":' + TYPE_SCHEMA + ',"include_archived":{"type":"boolean"},"limit":{"type":"integer"},"offset":{"type":"integer"}'
    ));
    tools.push(memoryTool(
      'memory_search_profile',
      isEn
        ? 'Search visible long-term memories by keyword query.'
        : '按关键词查找可见的长期记忆。',
      '"type":' + TYPE_SCHEMA + ',"query":{"type":"string"},"limit":{"type":"integer"}',
      '["query"]'
    ));
    if (allowWrites) {
      const scopeField = scope === 'toolDefaultGlobal' || scope === 'toolDefaultAssistant'
        ? ',"scope":{"type":"string","enum":["global","assistant"]}'
        : '';
      tools.push(memoryTool(
        'memory_update',
        isEn
          ? 'Save a durable user fact or preference across conversations with automatic deduplication.'
          : '保存跨会话有效的用户事实或偏好，自动去重。',
        '"type":' + TYPE_SCHEMA + ',"content":{"type":"string"}' + scopeField,
        '["type","content"]'
      ));
      tools.push(memoryTool(
        'memory_edit',
        isEn
          ? 'Correct a visible long-term memory entry by its ID.'
          : '按 ID 更正一条可见的长期记忆。',
        '"id":{"type":"string"},"content":{"type":"string"}',
        '["id","content"]'
      ));
      tools.push(memoryTool(
        'memory_delete',
        isEn
          ? 'Archive an outdated or wrong long-term memory entry by its ID.'
          : '按 ID 归档失效的长期记忆。',
        '"id":{"type":"string"}',
        '["id"]'
      ));
      if (includeGlobal) {
        tools.push(memoryTool(
          'update_user_profile',
          isEn
            ? 'Update stable user profile fields explicitly stated by the user.'
            : '更新用户明确表达的稳定画像字段，键名使用画像标记中的名称。',
          '"fields":{"type":"array","items":{"type":"object","properties":{"key":{"type":"string"},' +
          '"value":{"type":"string"}},"required":["key","value"]}}',
          '["fields"]'
        ));
      }
    }
  }
  if (recall) {
    tools.push(memoryTool(
      'chat_search',
      isEn
        ? 'Search saved past conversations of the current assistant by keyword query.'
        : '在当前助手的已保存对话中检索关键词。可指定对话 ID。',
      '"query":{"type":"string"},"conversation_id":{"type":"string"},"limit":{"type":"integer"}',
      '["query"]'
    ));
  }
  return tools;
}

function textArg(args: Record<string, Object>, key: string): string {
  const value = args[key];
  return typeof value === 'string' ? value.trim() : '';
}

function intArg(args: Record<string, Object>, key: string, fallback: number, min: number, max: number): number {
  const value = args[key];
  return typeof value === 'number' && Number.isFinite(value)
    ? Math.max(min, Math.min(max, Math.floor(value))) : fallback;
}

interface MemoryToolEntry {
  id: string;
  type: string;
  scope: string;
  status: string;
  content: string;
  updated_at: string;
}

function summarizeEntry(entry: MemoryEntry): MemoryToolEntry {
  return {
    id: entry.id,
    type: memoryTypeName(entry.category),
    scope: entry.assistantId ? 'assistant' : 'global',
    status: entry.archived ? 'archived' : 'active',
    content: entry.content,
    updated_at: memoryDate(entry.updatedAt)
  };
}

interface ConversationMatch {
  conversationId: string;
  title: string;
  role: string;
  date: string;
  snippet: string;
}

function searchPastChats(
  args: Record<string, Object>, chats: Conversation[], personaId: string, currentId: string
): MemoryToolOutcome {
  const query = textArg(args, 'query').toLowerCase();
  if (!query) return { text: 'query 不能为空', isError: true };
  const limit = intArg(args, 'limit', 10, 1, 20);
  const tokens = query.split(/\s+/);
  const filterId = textArg(args, 'conversation_id');
  const ordered = chats.filter((chat: Conversation): boolean =>
    !chat.ephemeral && chat.personaId === personaId && (filterId ? chat.id === filterId : chat.id !== currentId));
  ordered.sort((a: Conversation, b: Conversation): number => b.updated - a.updated);
  const results: ConversationMatch[] = [];
  for (const chat of ordered) {
    for (let i = chat.messages.length - 1; i >= 0; i--) {
      const message = chat.messages[i];
      const lower = message.text.toLowerCase();
      if (!tokens.every((token: string): boolean => lower.includes(token))) continue;
      const start = Math.max(0, lower.indexOf(tokens[0]) - 60);
      results.push({
        conversationId: chat.id,
        title: chat.title,
        role: message.role,
        date: memoryDate(message.createdAt || chat.updated),
        snippet: message.text.slice(start, start + 320)
      });
      if (results.length === limit) break;
    }
    if (results.length === limit) break;
  }
  return { text: JSON.stringify({ query, results }) };
}

export function executeMemoryToolCall(
  name: string,
  args: Record<string, Object>,
  memories: MemoryEntry[],
  profile: UserProfileField[],
  chats: Conversation[],
  chat: Conversation,
  persona: Persona,
  includeGlobal: boolean
): MemoryToolOutcome {
  if (name === 'chat_search' && persona.allowPastConversationRecall) {
    return searchPastChats(args, chats, persona.id, chat.id);
  }
  const read = name === 'memory_read' || name === 'memory_search_profile';
  if (persona.memoryEnabled === false || name === 'chat_search' || (chat.ephemeral && !read)) {
    return { text: '当前对话未启用此记忆操作。', isError: true };
  }

  const visible = memories.filter((entry: MemoryEntry): boolean => canReadMemory(entry, persona.id, includeGlobal));
  const type = textArg(args, 'type');
  if (type && !['identity', 'workflow', 'voice', 'instruction'].includes(type)) {
    return { text: 'type 必须是 identity、workflow、voice 或 instruction。', isError: true };
  }
  const category = normalizeMemoryCategory(type);
  if (read) {
    const filtered = type ? visible.filter((entry: MemoryEntry): boolean => entry.category === category) : visible;
    if (name === 'memory_read') {
      const hits = searchMemories(filtered, '', persona.id, args['include_archived'] === true);
      const offset = intArg(args, 'offset', 0, 0, Number.MAX_SAFE_INTEGER);
      const limit = intArg(args, 'limit', 50, 1, 100);
      const entries = hits.slice(offset, offset + limit).map(summarizeEntry);
      const hasMore = offset + entries.length < hits.length;
      return { text: JSON.stringify({
        total: hits.length, offset, limit, has_more: hasMore, next_offset: hasMore ? offset + entries.length : null, entries
      }) };
    }
    const query = textArg(args, 'query');
    if (!query) return { text: 'query 不能为空', isError: true };
    const limit = intArg(args, 'limit', 10, 1, 20);
    const matched = searchMemories(filtered, query, persona.id).slice(0, limit).map(summarizeEntry);
    return { text: JSON.stringify({ query, matched }) };
  }

  const content = textArg(args, 'content');
  const id = textArg(args, 'id');
  if (name === 'memory_update') {
    if (!content || !type) return { text: 'type 和 content 不能为空', isError: true };
    const policy = persona.memoryWriteScope || 'alwaysGlobal';
    const owner = includeGlobal ? memoryWriteAssistantId(policy, persona.id, textArg(args, 'scope')) : persona.id;
    const merged = mergeMemoryCandidates(memories, [{ category, content }], chat.id, owner, 'tool');
    return { text: merged.addedCount > 0 ? '已保存长期记忆。' : '已合并相似长期记忆。', memories: merged.entries };
  }
  if (name === 'memory_edit' || name === 'memory_delete') {
    const target = visible.find((entry: MemoryEntry): boolean => entry.id === id && !entry.archived);
    if (!target) return { text: '未找到可操作的记忆条目。', isError: true };
    const archive = name === 'memory_delete';
    if (!archive && !content) return { text: 'content 不能为空', isError: true };
    const updated = memories.map((entry: MemoryEntry): MemoryEntry => {
      if (entry.id !== target.id) return entry;
      return {
        id: entry.id,
        category: entry.category,
        assistantId: entry.assistantId,
        createdAt: entry.createdAt,
        content: archive ? entry.content : content,
        archived: archive,
        updatedAt: Date.now(),
        sourceConversationId: entry.sourceConversationId,
        source: entry.source || 'tool',
        relatedIds: entry.relatedIds
      };
    });
    return { text: archive ? '已归档记忆。' : '已更新记忆。', memories: updated };
  }
  if (name === 'update_user_profile' && includeGlobal && Array.isArray(args['fields'])) {
    const raw = args['fields'] as Record<string, Object>[];
    const fields: ExtractedProfileCandidate[] = [];
    for (const field of raw) {
      if (!field || typeof field !== 'object') continue;
      const key = textArg(field, 'key');
      const value = textArg(field, 'value');
      if (key && value) fields.push({ key, value });
    }
    if (!fields.length) return { text: '请提供有效的画像字段。', isError: true };
    return { text: '已更新用户画像。', profile: mergeProfileFields(profile, fields, 'tool').fields };
  }
  return { text: '未知或未启用的记忆工具。', isError: true };
}

function replaceTemplatePlaceholder(template: string, key: string, value: string): string {
  const re = new RegExp('\\{\\{\\s*' + key + '\\s*\\}\\}', 'g');
  return template.replace(re, (): string => value);
}

function clipTraceText(text: string, maxChars: number): string {
  return text.length <= maxChars ? text : `${text.slice(0, maxChars)}\n…[truncated]`;
}

export function buildMemoryOrganizeBatch(
  messages: ChatMessage[],
  cadence: number,
  through?: string,
  manual: boolean = false,
  lang: 'zh' | 'en' = 'zh'
): MemoryBatchResult {
  const empty: MemoryBatchResult = { snippet: '', endMessageId: '', windowSize: 0 };
  if (!messages.length) return empty;
  const watermark = through ? messages.findIndex((message: ChatMessage): boolean => message.id === through) : -1;
  const pending = messages.slice(watermark + 1);
  let windowMsgs: ChatMessage[] = [];
  let isManualFallback = false;

  if (!manual) {
    let lastAsstIdx = -1;
    for (let i = pending.length - 1; i >= 0; i--) {
      if (pending[i].role === 'assistant' && messageText(pending[i]).trim().length > 0) {
        lastAsstIdx = i;
        break;
      }
    }
    if (lastAsstIdx < 0) return empty;
    const eligible = pending.slice(0, lastAsstIdx + 1);
    let assistantTurns = 0;
    for (let i = 0; i < eligible.length; i++) {
      if (eligible[i].role === 'assistant' && messageText(eligible[i]).trim().length > 0) {
        assistantTurns += 1;
      }
    }
    const minTurns = Math.max(1, cadence);
    if (assistantTurns < minTurns) return empty;
    windowMsgs = watermark < 0 && eligible.length > 10 ? eligible.slice(-10) : eligible;
  } else {
    const nonEmptyPending = pending.filter((m: ChatMessage): boolean =>
      (m.role === 'user' || m.role === 'assistant') && messageText(m).trim().length > 0
    );
    if (nonEmptyPending.length > 0) {
      windowMsgs = watermark < 0 && nonEmptyPending.length > 10 ? nonEmptyPending.slice(-10) : nonEmptyPending;
    } else {
      isManualFallback = true;
      const recent = messages.filter((m: ChatMessage): boolean =>
        (m.role === 'user' || m.role === 'assistant') && messageText(m).trim().length > 0
      );
      if (!recent.length) return empty;
      windowMsgs = recent.length > 4 ? recent.slice(-4) : recent;
    }
  }

  if (!windowMsgs.length) return empty;
  const maxMessageChars = 2000;
  const maxTotalChars = isManualFallback ? 4000 : 6000;
  const reversedLines: string[] = [];
  let totalLen = 0;

  for (let i = windowMsgs.length - 1; i >= 0; i--) {
    const msg = windowMsgs[i];
    const body = messageText(msg).trim();
    if (!body) continue;
    const prefix = msg.role === 'user'
      ? (lang === 'en' ? 'User: ' : '用户：')
      : (lang === 'en' ? 'Assistant: ' : '助手：');
    const clipped = body.length > maxMessageChars ? `${body.slice(0, maxMessageChars)}…` : body;
    const line = `${prefix}${clipped}`;
    totalLen += (reversedLines.length === 0 ? 0 : 2) + line.length;
    reversedLines.push(line);
    if (totalLen > maxTotalChars) break;
  }

  if (!reversedLines.length) return empty;
  const joined = reversedLines.reverse().join('\n\n');
  const snippet = joined.length > maxTotalChars ? `…${joined.slice(joined.length - maxTotalChars)}` : joined;
  return {
    snippet,
    endMessageId: windowMsgs[windowMsgs.length - 1].id,
    windowSize: windowMsgs.length
  };
}

export function memoryTurnBatch(messages: ChatMessage[], cadence: number, through?: string, manual: boolean = false): string {
  return buildMemoryOrganizeBatch(messages, cadence, through, manual, 'zh').snippet;
}

export async function extractMemory(
  provider: Provider, key: string, modelId: string, snippet: string, conversationId: string, proxyPassword?: string
): Promise<MemoryExtractionResult> {
  const raw = await completeOnce(provider, key, EXTRACTION_SYSTEM_PROMPT, snippet, modelId, 0, proxyPassword, conversationId);
  return parseMemoryExtractionResponse(raw);
}

function formatSmartAddEntriesPerItem(entries: MemoryEntry[]): string {
  if (entries.length === 0) return '';
  return entries.map((e: MemoryEntry): string => `${e.id} ${e.content}`).join('\n');
}

function formatSmartAddEntriesBatched(entries: MemoryEntry[]): string {
  if (entries.length === 0) return '';
  return entries.map((e: MemoryEntry): string => `${e.id} (${memoryTypeName(e.category)}) ${e.content}`).join('\n');
}

function formatIdentityEntriesForDistill(entries: MemoryEntry[]): string {
  if (entries.length === 0) return '';
  return entries.map((e: MemoryEntry): string => `${e.id} ${e.content}`).join('\n');
}

/**
 * Full 4-stage Android-aligned Memory Pipeline:
 * 1. Gatekeeper (<gate><user_memory>true/false</user_memory></gate>)
 * 2. Extract (<extracted><item type="...">...</item></extracted>)
 * 3. Smart Add (NEW / MERGE / CONFLICT / SKIP + relatedIds, batched or perItem)
 * 4. Profile Distiller ({"fields":[{"key":"...","value":"..."}]})
 */
export async function runMemoryPipeline(input: MemoryPipelineRunInput): Promise<MemoryPipelineRunOutput> {
  const lang = resolveMemoryPromptLang(input.settings, input.uiLanguage || 'zh-Hans');
  const includeGlobal = input.settings.injectGlobal !== false;
  const owner = includeGlobal
    ? memoryWriteAssistantId(input.writeScope, input.assistantId)
    : input.assistantId;
  const recordSteps = input.settings.recordTraces !== false;
  const thinkingEnabled = input.settings.enableThinking !== false;
  const stageEffort: ReasoningEffort = thinkingEnabled ? (input.assistantReasoning || 'low') : 'off';
  const gateEffort: ReasoningEffort = 'off';
  const steps: MemoryTraceStep[] = [];

  // Stage 1: Gatekeeper
  const gateStart = Date.now();
  const gateTpl = getEffectiveMemoryTemplate(input.settings, 'gate', lang);
  const gatePrompt = replaceTemplatePlaceholder(gateTpl, 'conversation', input.snippet);
  let gateResp = '';
  try {
    gateResp = await completeOnce(
      input.provider,
      input.apiKey,
      '',
      gatePrompt,
      input.modelId,
      0,
      input.proxyPassword,
      input.conversationId,
      gateEffort,
      input.onLog
    );
  } catch (e) {
    const errText = (e as Error).message || String(e);
    steps.push({
      stage: 'Gatekeeper',
      status: 'failed',
      error: `gate_request_failed: ${errText}`,
      prompt: recordSteps ? clipTraceText(gatePrompt, 3000) : undefined,
      response: recordSteps ? '' : undefined,
      summary: `门控请求失败：${errText}`,
      durationMs: Date.now() - gateStart
    });
    return {
      shouldSave: false,
      advanced: false,
      gateStatus: 'malformed',
      error: `gate_request_failed:${errText}`,
      summary: `门控请求失败：${errText}`,
      memories: input.existingMemories,
      profile: input.existingProfile,
      addedCount: 0,
      mergedCount: 0,
      conflictCount: 0,
      skippedCount: 0,
      profileUpdatedCount: 0,
      steps
    };
  }

  const gateDecision = parseGatekeeperResult(gateResp);
  if (gateDecision === 'malformed') {
    const reason = gateResp.trim().length === 0 ? '门控返回空响应（将保留未整理进度以便重试）' : '门控输出格式无效（将保留未整理进度以便重试）';
    steps.push({
      stage: 'Gatekeeper',
      status: 'failed',
      error: 'gate_parse_failed',
      prompt: recordSteps ? clipTraceText(gatePrompt, 3000) : undefined,
      response: recordSteps ? clipTraceText(gateResp, 2000) : undefined,
      summary: reason,
      durationMs: Date.now() - gateStart
    });
    return {
      shouldSave: false,
      advanced: false,
      gateStatus: 'malformed',
      error: 'gate_parse_failed',
      summary: reason,
      memories: input.existingMemories,
      profile: input.existingProfile,
      addedCount: 0,
      mergedCount: 0,
      conflictCount: 0,
      skippedCount: 0,
      profileUpdatedCount: 0,
      steps
    };
  }

  const gatePassed = gateDecision === 'worthRemembering';
  steps.push({
    stage: 'Gatekeeper',
    status: 'success',
    prompt: recordSteps ? clipTraceText(gatePrompt, 3000) : undefined,
    response: recordSteps ? clipTraceText(gateResp, 2000) : undefined,
    summary: gatePassed ? '门控判定：包含值得长期记忆的用户信息 (true)' : '门控判定：无需记录长期记忆 (false)',
    durationMs: Date.now() - gateStart
  });

  if (!gatePassed) {
    return {
      shouldSave: false,
      advanced: true,
      gateStatus: 'skip',
      summary: '门控跳过：未发现需要长期记忆的用户信息',
      memories: input.existingMemories,
      profile: input.existingProfile,
      addedCount: 0,
      mergedCount: 0,
      conflictCount: 0,
      skippedCount: 0,
      profileUpdatedCount: 0,
      steps
    };
  }

  // Stage 2: Extract
  const extStart = Date.now();
  let extTpl = getEffectiveMemoryTemplate(input.settings, 'extract', lang);
  if (includeGlobal && (input.writeScope === 'toolDefaultGlobal' || input.writeScope === 'toolDefaultAssistant')) {
    const rule = lang === 'en' ? EXTRACT_TOOL_DEFAULT_SCOPE_RULE_EN : EXTRACT_TOOL_DEFAULT_SCOPE_RULE_ZH;
    const marker = lang === 'en' ? '## Existing memory' : '## 已有记忆';
    extTpl = extTpl.includes(marker)
      ? extTpl.replace(marker, (): string => `${rule}\n\n${marker}`)
      : `${extTpl}\n\n${rule}`;
  }
  const existingMemStr = buildExistingMemoryXmlBlock(input.existingMemories, input.settings, input.assistantId, lang, [], 25);
  const extPrompt = replaceTemplatePlaceholder(
    replaceTemplatePlaceholder(extTpl, 'existingMemory', existingMemStr),
    'conversation',
    input.snippet
  );
  let extResp = '';
  try {
    extResp = await completeOnce(
      input.provider,
      input.apiKey,
      '',
      extPrompt,
      input.modelId,
      0,
      input.proxyPassword,
      input.conversationId,
      stageEffort,
      input.onLog
    );
  } catch (e) {
    const errText = (e as Error).message || String(e);
    steps.push({
      stage: 'Extract',
      status: 'failed',
      error: `extract_request_failed: ${errText}`,
      prompt: recordSteps ? clipTraceText(extPrompt, 3000) : undefined,
      response: recordSteps ? '' : undefined,
      summary: `提取请求失败：${errText}`,
      durationMs: Date.now() - extStart
    });
    return {
      shouldSave: false,
      advanced: false,
      gateStatus: 'worthRemembering',
      error: `extract_request_failed:${errText}`,
      summary: `提取请求失败：${errText}`,
      memories: input.existingMemories,
      profile: input.existingProfile,
      addedCount: 0,
      mergedCount: 0,
      conflictCount: 0,
      skippedCount: 0,
      profileUpdatedCount: 0,
      steps
    };
  }

  const extParsed = parseExtractedMemoriesResult(extResp);
  if (!extParsed.ok) {
    const extReason = extResp.trim().length === 0 ? '提取阶段返回空响应（将重试）' : '提取阶段输出格式无效（将重试）';
    steps.push({
      stage: 'Extract',
      status: 'failed',
      error: 'extract_parse_failed',
      prompt: recordSteps ? clipTraceText(extPrompt, 3000) : undefined,
      response: recordSteps ? clipTraceText(extResp, 2000) : undefined,
      summary: extReason,
      durationMs: Date.now() - extStart
    });
    return {
      shouldSave: false,
      advanced: false,
      gateStatus: 'worthRemembering',
      error: 'extract_parse_failed',
      summary: extReason,
      memories: input.existingMemories,
      profile: input.existingProfile,
      addedCount: 0,
      mergedCount: 0,
      conflictCount: 0,
      skippedCount: 0,
      profileUpdatedCount: 0,
      steps
    };
  }

  const candidates: ExtractedMemoryCandidate[] = extParsed.items;
  steps.push({
    stage: 'Extract',
    status: 'success',
    prompt: recordSteps ? clipTraceText(extPrompt, 3000) : undefined,
    response: recordSteps ? clipTraceText(extResp, 2000) : undefined,
    summary: candidates.length > 0 ? `提取出 ${candidates.length} 条候选记忆` : '未提取到新候选记忆 (<extracted/>)',
    durationMs: Date.now() - extStart
  });

  if (candidates.length === 0) {
    return {
      shouldSave: false,
      advanced: true,
      gateStatus: 'worthRemembering',
      summary: '无新增记忆条目',
      memories: input.existingMemories,
      profile: input.existingProfile,
      addedCount: 0,
      mergedCount: 0,
      conflictCount: 0,
      skippedCount: 0,
      profileUpdatedCount: 0,
      steps
    };
  }

  // Stage 3: Smart Add (Batched or Per-item)
  const smartStart = Date.now();
  const decisions = new Map<number, SmartAddDecision>();
  const itemOwners: Array<string | undefined> = [];
  const pendingIndexes: number[] = [];
  const perItemCandidates: MemoryEntry[][] = [];
  const unionMap = new Map<string, MemoryEntry>();

  for (let i = 0; i < candidates.length; i++) {
    const cand = candidates[i];
    const itemOwner = includeGlobal
      ? memoryWriteAssistantId(input.writeScope, input.assistantId, cand.scope)
      : input.assistantId;
    itemOwners.push(itemOwner);

    const exact = findExactActiveMemory(input.existingMemories, cand.category, cand.content, input.assistantId, includeGlobal);
    if (exact) {
      perItemCandidates.push([]);
      decisions.set(i + 1, { action: 'SKIP', targetId: exact.id, relatedIds: [] });
      continue;
    }

    const cands = findSmartAddCandidates(input.existingMemories, cand.content, cand.category, input.assistantId, includeGlobal, 5);
    perItemCandidates.push(cands);
    if (cands.length === 0) {
      decisions.set(i + 1, { action: 'NEW', relatedIds: [] });
      continue;
    }
    for (let j = 0; j < cands.length; j++) {
      unionMap.set(cands[j].id, cands[j]);
    }
    pendingIndexes.push(i);
  }

  if (pendingIndexes.length === 0) {
    steps.push({
      stage: input.smartAddMode === 'perItem' ? 'Smart Add (Per-item)' : 'Smart Add (Batched)',
      status: 'success',
      summary: input.existingMemories.length === 0
        ? `库中无已有条目，直接新增 ${candidates.length} 条记忆`
        : `完成 ${candidates.length} 条候选记忆的快速去重判定`,
      durationMs: Date.now() - smartStart
    });
  } else if (input.smartAddMode === 'perItem') {
    const singleTpl = getEffectiveMemoryTemplate(input.settings, 'smartAddSingle', lang);
    const promptParts: string[] = [];
    const respParts: string[] = [];
    for (let k = 0; k < pendingIndexes.length; k++) {
      promptParts.push('');
      respParts.push('');
    }
    let cursor = 0;
    const workerCount = Math.min(3, pendingIndexes.length);
    const workers: Array<Promise<void>> = [];
    const runWorker = async (): Promise<void> => {
      while (true) {
        const pIdx = cursor;
        if (pIdx >= pendingIndexes.length) break;
        cursor += 1;
        const idx = pendingIndexes[pIdx];
        const cand = candidates[idx];
        const similar = perItemCandidates[idx];
        const singlePrompt = replaceTemplatePlaceholder(
          replaceTemplatePlaceholder(
            replaceTemplatePlaceholder(singleTpl, 'type', memoryTypeName(cand.category)),
            'newInfo',
            cand.content
          ),
          'entriesText',
          formatSmartAddEntriesPerItem(similar)
        );
        if (recordSteps) promptParts[pIdx] = singlePrompt;
        try {
          const sResp = await completeOnce(
            input.provider,
            input.apiKey,
            '',
            singlePrompt,
            input.modelId,
            0,
            input.proxyPassword,
            input.conversationId,
            stageEffort,
            input.onLog
          );
          if (recordSteps) respParts[pIdx] = sResp;
          const dec = parseSmartAddSingleResponse(sResp);
          if (dec) decisions.set(idx + 1, dec);
        } catch (e) {
          if (recordSteps) respParts[pIdx] = `<request failed> ${(e as Error).message || String(e)}`;
        }
      }
    };
    for (let w = 0; w < workerCount; w++) {
      workers.push(runWorker());
    }
    await Promise.all(workers);
    steps.push({
      stage: 'Smart Add (Per-item)',
      status: 'success',
      prompt: recordSteps && promptParts.length > 0 ? clipTraceText(promptParts.join('\n\n─── ───\n\n'), 3000) : undefined,
      response: recordSteps && respParts.length > 0 ? clipTraceText(respParts.join('\n\n─── ───\n\n'), 2000) : undefined,
      summary: `已完成 ${candidates.length} 条候选记忆的逐条去重判定`,
      durationMs: Date.now() - smartStart
    });
  } else {
    const unionSimilar = Array.from(unionMap.values()).slice(0, 12);
    const batchTpl = getEffectiveMemoryTemplate(input.settings, 'smartAddBatch', lang);
    const itemsText = pendingIndexes.map((origIdx: number, k: number): string =>
      `[${k + 1}] ${memoryTypeName(candidates[origIdx].category)} ${candidates[origIdx].content}`
    ).join('\n');
    const entriesText = formatSmartAddEntriesBatched(unionSimilar);
    const batchPrompt = replaceTemplatePlaceholder(
      replaceTemplatePlaceholder(batchTpl, 'itemsText', itemsText),
      'entriesText',
      entriesText
    );
    try {
      const bResp = await completeOnce(
        input.provider,
        input.apiKey,
        '',
        batchPrompt,
        input.modelId,
        0,
        input.proxyPassword,
        input.conversationId,
        stageEffort,
        input.onLog
      );
      const parsedMap = parseSmartAddBatchResponse(bResp);
      for (let k = 0; k < pendingIndexes.length; k++) {
        const dec = parsedMap.get(k + 1);
        if (dec) {
          decisions.set(pendingIndexes[k] + 1, dec);
        }
      }
      steps.push({
        stage: 'Smart Add (Batched)',
        status: 'success',
        prompt: recordSteps ? clipTraceText(batchPrompt, 3000) : undefined,
        response: recordSteps ? clipTraceText(bResp, 2000) : undefined,
        summary: `批量去重判定完成（比对 ${unionSimilar.length} 条同类已有记忆）`,
        durationMs: Date.now() - smartStart
      });
    } catch (e) {
      steps.push({
        stage: 'Smart Add (Batched)',
        status: 'failed',
        error: (e as Error).message || String(e),
        prompt: recordSteps ? clipTraceText(batchPrompt, 3000) : undefined,
        summary: `批量去重请求失败，已降级为本地去重合并：${(e as Error).message || String(e)}`,
        durationMs: Date.now() - smartStart
      });
    }
  }

  const mergedOut = applySmartAddDecisions(
    input.existingMemories,
    candidates,
    decisions,
    input.conversationId,
    owner,
    'extracted',
    itemOwners
  );

  // Stage 4: Profile Distiller (when global profile is active and identity entries changed)
  let nextProfile = input.existingProfile;
  let profileUpdatedCount = 0;
  if (includeGlobal && mergedOut.identityChanged) {
    const distStart = Date.now();
    const identityEntries = mergedOut.entries
      .filter((m: MemoryEntry): boolean => !m.archived && m.category === 'identity' && canReadMemory(m, input.assistantId, includeGlobal))
      .slice(-30);
    if (identityEntries.length > 0) {
      const distTpl = getEffectiveMemoryTemplate(input.settings, 'profileDistill', lang);
      const distPrompt = replaceTemplatePlaceholder(
        replaceTemplatePlaceholder(distTpl, 'profileBlock', buildProfileBlock(input.existingProfile)),
        'identityEntries',
        formatIdentityEntriesForDistill(identityEntries)
      );
      try {
        const distResp = await completeOnce(
          input.provider,
          input.apiKey,
          '',
          distPrompt,
          input.modelId,
          0,
          input.proxyPassword,
          input.conversationId,
          stageEffort,
          input.onLog
        );
        const distilledFields = parseProfileDistillerResponse(distResp);
        if (distilledFields.length > 0) {
          const profMerged = mergeProfileFields(input.existingProfile, distilledFields, 'distilled');
          nextProfile = profMerged.fields;
          profileUpdatedCount = profMerged.updatedCount;
        }
        steps.push({
          stage: 'Profile Distiller',
          status: 'success',
          prompt: recordSteps ? clipTraceText(distPrompt, 3000) : undefined,
          response: recordSteps ? clipTraceText(distResp, 2000) : undefined,
          summary: profileUpdatedCount > 0 ? `更新了 ${profileUpdatedCount} 个用户画像字段` : '画像字段无需变更',
          durationMs: Date.now() - distStart
        });
      } catch (e) {
        steps.push({
          stage: 'Profile Distiller',
          status: 'failed',
          error: (e as Error).message || String(e),
          prompt: recordSteps ? clipTraceText(distPrompt, 3000) : undefined,
          summary: `画像提炼失败：${(e as Error).message || String(e)}`,
          durationMs: Date.now() - distStart
        });
      }
    }
  }

  const conflictCnt = mergedOut.conflictCount || 0;
  const skippedCnt = mergedOut.skippedCount || 0;
  const summaryParts: string[] = [];
  if (mergedOut.addedCount > 0) summaryParts.push(`新增 ${mergedOut.addedCount}`);
  if (mergedOut.mergedCount > 0) summaryParts.push(`合并 ${mergedOut.mergedCount}`);
  if (conflictCnt > 0) summaryParts.push(`冲突替换 ${conflictCnt}`);
  if (skippedCnt > 0) summaryParts.push(`跳过重复 ${skippedCnt}`);
  if (profileUpdatedCount > 0) summaryParts.push(`画像更新 ${profileUpdatedCount}`);

  return {
    shouldSave: mergedOut.addedCount > 0 || mergedOut.mergedCount > 0 || profileUpdatedCount > 0,
    advanced: true,
    gateStatus: 'worthRemembering',
    summary: summaryParts.length > 0 ? summaryParts.join(' · ') : '已判重，无新增记忆变更',
    memories: mergedOut.entries,
    profile: nextProfile,
    addedCount: mergedOut.addedCount,
    mergedCount: mergedOut.mergedCount,
    conflictCount: conflictCnt,
    skippedCount: skippedCnt,
    profileUpdatedCount,
    steps
  };
}
