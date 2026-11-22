import { completeOnce } from './ChatClient';
import {
  applySmartAddDecisions,
  buildProfileBlock,
  canReadMemory,
  ExtractedMemoryCandidate,
  ExtractedProfileCandidate,
  findSimilarActiveMemories,
  getEffectiveMemoryTemplate,
  memoryDate,
   MemoryExtractionResult,
  memoryTypeName,
  memoryWriteAssistantId,
  mergeMemoryCandidates,
  mergeProfileFields,
  normalizeMemoryCategory,
  parseExtractedMemoriesXml,
  parseGatekeeperXml,
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
  MemoryTrace,
  MemoryTraceStep,
  MemoryWriteScope,
  Persona,
  Provider,
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
  uiLanguage?: string;
  onLog?: (entry: RequestLogEntry) => void;
}

export interface MemoryPipelineRunOutput {
  shouldSave: boolean;
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

export function memoryTurnBatch(messages: ChatMessage[], cadence: number, through?: string, manual: boolean = false): string {
  if (!messages.length || messages[messages.length - 1].role !== 'assistant') return '';
  const watermark = through ? messages.findIndex((message: ChatMessage): boolean => message.id === through) : -1;
  const pending = messages.slice(watermark + 1);
  const turns = pending.filter((message: ChatMessage): boolean => message.role === 'user');
  if (!turns.length || (!manual && turns.length < cadence)) return '';
  const count = manual || watermark >= 0 ? Math.min(turns.length, 20) : cadence;
  const start = pending.indexOf(turns[turns.length - count]);
  return pending.slice(start).map((message: ChatMessage): string =>
    (message.role === 'user' ? '用户：' : '助手：') + message.text.slice(0, 1500)).join('\n\n').slice(-12000);
}

export async function extractMemory(
  provider: Provider, key: string, modelId: string, snippet: string, conversationId: string, proxyPassword?: string
): Promise<MemoryExtractionResult> {
  const raw = await completeOnce(provider, key, EXTRACTION_SYSTEM_PROMPT, snippet, modelId, 1000, proxyPassword, conversationId);
  return parseMemoryExtractionResponse(raw);
}

function formatExistingMemoriesForExtract(entries: MemoryEntry[], assistantId?: string, includeGlobal: boolean = true): string {
  const visible = entries.filter((e: MemoryEntry): boolean => !e.archived && canReadMemory(e, assistantId, includeGlobal));
  if (visible.length === 0) return '(无)';
  const recent = visible.slice(0, 60);
  return recent.map((e: MemoryEntry): string => `- [${memoryTypeName(e.category)}] ${e.content}`).join('\n');
}

function formatSimilarEntriesForSmartAdd(entries: MemoryEntry[]): string {
  if (entries.length === 0) return '(none)';
  return entries.map((e: MemoryEntry): string =>
    `- id=${e.id} | type=${memoryTypeName(e.category)} | ${e.content}`
  ).join('\n');
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
  const enableThinking = input.settings.enableThinking !== false;
  const steps: MemoryTraceStep[] = [];

  // Stage 1: Gatekeeper
  const gateStart = Date.now();
  const gateTpl = getEffectiveMemoryTemplate(input.settings, 'gate', lang);
  const gatePrompt = gateTpl.replace(/\{\{\s*conversation\s*\}\}/g, input.snippet);
  const gateResp = await completeOnce(
    input.provider,
    input.apiKey,
    '',
    gatePrompt,
    input.modelId,
    256,
    input.proxyPassword,
    input.conversationId,
    enableThinking,
    input.onLog
  );
  const gatePassed = parseGatekeeperXml(gateResp);
  steps.push({
    stage: 'Gatekeeper',
    prompt: recordSteps ? gatePrompt : undefined,
    response: recordSteps ? gateResp : undefined,
    summary: gatePassed ? '门控判定：包含值得长期记忆的用户信息 (true)' : '门控判定：无需记录长期记忆 (false)',
    durationMs: Date.now() - gateStart
  });

  if (!gatePassed) {
    return {
      shouldSave: false,
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
  const extTpl = getEffectiveMemoryTemplate(input.settings, 'extract', lang);
  const existingMemStr = formatExistingMemoriesForExtract(input.existingMemories, input.assistantId, includeGlobal);
  const extPrompt = extTpl
    .replace(/\{\{\s*existingMemory\s*\}\}/g, existingMemStr)
    .replace(/\{\{\s*conversation\s*\}\}/g, input.snippet);
  const extResp = await completeOnce(
    input.provider,
    input.apiKey,
    '',
    extPrompt,
    input.modelId,
    1200,
    input.proxyPassword,
    input.conversationId,
    enableThinking,
    input.onLog
  );
  const candidates: ExtractedMemoryCandidate[] = parseExtractedMemoriesXml(extResp);
  steps.push({
    stage: 'Extract',
    prompt: recordSteps ? extPrompt : undefined,
    response: recordSteps ? extResp : undefined,
    summary: candidates.length > 0 ? `提取出 ${candidates.length} 条候选记忆` : '未提取到新候选记忆 (<extracted/>)',
    durationMs: Date.now() - extStart
  });

  if (candidates.length === 0) {
    return {
      shouldSave: false,
      summary: '门控通过，但未提取出新的独立记忆条目',
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
  if (input.smartAddMode === 'perItem') {
    const singleTpl = getEffectiveMemoryTemplate(input.settings, 'smartAddSingle', lang);
    for (let i = 0; i < candidates.length; i++) {
      const cand = candidates[i];
      const similar = findSimilarActiveMemories(input.existingMemories, cand.content, undefined, owner, 5);
      if (similar.length === 0) {
        decisions.set(i + 1, { action: 'NEW', relatedIds: [] });
        continue;
      }
      const singlePrompt = singleTpl
        .replace(/\{\{\s*type\s*\}\}/g, memoryTypeName(cand.category))
        .replace(/\{\{\s*newInfo\s*\}\}/g, cand.content)
        .replace(/\{\{\s*entriesText\s*\}\}/g, formatSimilarEntriesForSmartAdd(similar));
      try {
        const sResp = await completeOnce(
          input.provider,
          input.apiKey,
          '',
          singlePrompt,
          input.modelId,
          512,
          input.proxyPassword,
          input.conversationId,
          enableThinking,
          input.onLog
        );
        const dec = parseSmartAddSingleResponse(sResp);
        if (dec) decisions.set(i + 1, dec);
      } catch (_) {}
    }
    steps.push({
      stage: 'Smart Add (Per-item)',
      summary: `已完成 ${candidates.length} 条候选记忆的逐条去重判定`,
      durationMs: Date.now() - smartStart
    });
  } else {
    // Gather union of similar existing memories across all candidates
    const simMap = new Map<string, MemoryEntry>();
    for (let i = 0; i < candidates.length; i++) {
      const simList = findSimilarActiveMemories(input.existingMemories, candidates[i].content, undefined, owner, 5);
      for (let j = 0; j < simList.length; j++) {
        simMap.set(simList[j].id, simList[j]);
      }
    }
    const unionSimilar = Array.from(simMap.values()).slice(0, 15);
    if (unionSimilar.length === 0) {
      for (let i = 0; i < candidates.length; i++) {
        decisions.set(i + 1, { action: 'NEW', relatedIds: [] });
      }
      steps.push({
        stage: 'Smart Add (Batched)',
        summary: `库中无相似条目，直接新增 ${candidates.length} 条记忆`,
        durationMs: Date.now() - smartStart
      });
    } else {
      const batchTpl = getEffectiveMemoryTemplate(input.settings, 'smartAddBatch', lang);
      const itemsText = candidates.map((c: ExtractedMemoryCandidate, idx: number): string =>
        `${idx + 1}. [${memoryTypeName(c.category)}] ${c.content}`
      ).join('\n');
      const entriesText = formatSimilarEntriesForSmartAdd(unionSimilar);
      const batchPrompt = batchTpl
        .replace(/\{\{\s*itemsText\s*\}\}/g, itemsText)
        .replace(/\{\{\s*entriesText\s*\}\}/g, entriesText);
      try {
        const bResp = await completeOnce(
          input.provider,
          input.apiKey,
          '',
          batchPrompt,
          input.modelId,
          1024,
          input.proxyPassword,
          input.conversationId,
          enableThinking,
          input.onLog
        );
        const parsedMap = parseSmartAddBatchResponse(bResp);
        parsedMap.forEach((v: SmartAddDecision, k: number) => {
          decisions.set(k, v);
        });
        steps.push({
          stage: 'Smart Add (Batched)',
          prompt: recordSteps ? batchPrompt : undefined,
          response: recordSteps ? bResp : undefined,
          summary: `批量去重判定完成（匹配 ${unionSimilar.length} 条相似记忆）`,
          durationMs: Date.now() - smartStart
        });
      } catch (e) {
        steps.push({
          stage: 'Smart Add (Batched)',
          summary: `批量去重回退至本地相似度合并：${(e as Error).message || String(e)}`,
          durationMs: Date.now() - smartStart
        });
      }
    }
  }

  const mergedOut = applySmartAddDecisions(
    input.existingMemories,
    candidates,
    decisions,
    input.conversationId,
    owner,
    'extracted'
  );

  // Stage 4: Profile Distiller (when global profile is active and identity candidates were extracted)
  let nextProfile = input.existingProfile;
  let profileUpdatedCount = 0;
  const hasNewIdentity = candidates.some((c: ExtractedMemoryCandidate): boolean => c.category === 'identity');
  if (!owner && includeGlobal && hasNewIdentity) {
    const distStart = Date.now();
    const identityEntries = mergedOut.entries
      .filter((m: MemoryEntry): boolean => !m.archived && m.category === 'identity' && !m.assistantId)
      .slice(-25)
      .map((m: MemoryEntry): string => `- ${m.content}`)
      .join('\n');
    if (identityEntries.length > 0) {
      const distTpl = getEffectiveMemoryTemplate(input.settings, 'profileDistill', lang);
      const distPrompt = distTpl
        .replace(/\{\{\s*profileBlock\s*\}\}/g, buildProfileBlock(input.existingProfile))
        .replace(/\{\{\s*identityEntries\s*\}\}/g, identityEntries);
      try {
        const distResp = await completeOnce(
          input.provider,
          input.apiKey,
          '',
          distPrompt,
          input.modelId,
          512,
          input.proxyPassword,
          input.conversationId,
          enableThinking,
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
          prompt: recordSteps ? distPrompt : undefined,
          response: recordSteps ? distResp : undefined,
          summary: profileUpdatedCount > 0 ? `更新了 ${profileUpdatedCount} 个用户画像字段` : '画像字段无需变更',
          durationMs: Date.now() - distStart
        });
      } catch (_) {}
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
