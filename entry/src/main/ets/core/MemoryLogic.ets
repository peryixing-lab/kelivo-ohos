import {
  MemoryCategory,
  MemoryEntry,
  MemoryPromptLanguage,
  MemoryPromptTemplates,
  MemorySettings,
  MemorySourceKind,
  MemoryWriteScope,
  Persona,
  UserProfileField
} from './Models';

export interface ExtractedMemoryCandidate {
  category: MemoryCategory;
  content: string;
}

export interface ExtractedProfileCandidate {
  key: string;
  value: string;
}

export interface MemoryExtractionResult {
  shouldSave: boolean;
  summary: string;
  memories: ExtractedMemoryCandidate[];
  profile: ExtractedProfileCandidate[];
}

export interface MemoryMergeResult {
  entries: MemoryEntry[];
  addedCount: number;
  mergedCount: number;
  conflictCount?: number;
  skippedCount?: number;
}

export interface ProfileMergeResult {
  fields: UserProfileField[];
  updatedCount: number;
}

export interface StandardProfileFieldSpec {
  key: string;
  labelZh: string;
  labelEn: string;
  placeholderZh: string;
}

export interface SmartAddDecision {
  action: 'NEW' | 'MERGE' | 'CONFLICT' | 'SKIP';
  targetId?: string;
  mergedContent?: string;
  relatedIds: string[];
}

let memSeq: number = 0;

export function nextMemId(prefix: string = 'mem'): string {
  memSeq += 1;
  return `${prefix}_${Date.now()}_${memSeq}`;
}

export function normalizeMemoryTimestamp(raw?: number | string): number {
  if (typeof raw === 'number' && Number.isFinite(raw)) {
    if (raw >= 100000000000000) {
      return Math.floor(raw / 1000);
    }
    if (raw > 0 && raw < 10000000000) {
      return Math.floor(raw * 1000);
    }
    return Math.floor(raw);
  }
  if (typeof raw === 'string') {
    const trimmed = raw.trim();
    if (trimmed.length === 0) {
      return Date.now();
    }
    if (/^\d+$/.test(trimmed)) {
      return normalizeMemoryTimestamp(Number(trimmed));
    }
    const parsed = Date.parse(trimmed);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return Date.now();
}

export function profileFieldKey(field: UserProfileField): string {
  const rawKey = typeof field.key === 'string' && field.key.trim().length > 0
    ? field.key.trim()
    : (typeof field.id === 'string' ? field.id.trim() : '');
  return rawKey;
}

export function normalizeMemorySource(raw?: string): MemorySourceKind {
  if (raw === 'extracted' || raw === 'tool' || raw === 'manual') {
    return raw;
  }
  return 'manual';
}

export function normalizeMemoryEntries(entries?: MemoryEntry[]): MemoryEntry[] {
  if (!Array.isArray(entries)) {
    return [];
  }
  const out: MemoryEntry[] = [];
  for (let i = 0; i < entries.length; i++) {
    const item = entries[i];
    if (!item || typeof item.content !== 'string' || item.content.trim().length === 0) {
      continue;
    }
    const createdAt = normalizeMemoryTimestamp(item.createdAt);
    const updatedAt = normalizeMemoryTimestamp(item.updatedAt || item.createdAt);
    out.push({
      id: typeof item.id === 'string' && item.id.trim().length > 0 ? item.id.trim() : nextMemId('mem'),
      category: normalizeMemoryCategory(typeof item.category === 'string' ? item.category : 'instruction'),
      content: item.content.trim(),
      assistantId: typeof item.assistantId === 'string' && item.assistantId.trim().length > 0
        ? item.assistantId.trim()
        : undefined,
      archived: item.archived === true,
      createdAt,
      updatedAt,
      sourceConversationId: item.sourceConversationId,
      source: item.source ? normalizeMemorySource(item.source) : 'extracted',
      relatedIds: Array.isArray(item.relatedIds)
        ? item.relatedIds.filter((r: string): boolean => typeof r === 'string' && r.trim().length > 0)
        : undefined
    });
  }
  return out;
}

export function normalizeUserProfileFields(fields?: UserProfileField[]): UserProfileField[] {
  if (!Array.isArray(fields)) {
    return [];
  }
  const out: UserProfileField[] = [];
  const seen = new Map<string, number>();
  for (let i = 0; i < fields.length; i++) {
    const f = fields[i];
    if (!f || typeof f.value !== 'string' || f.value.trim().length === 0) {
      continue;
    }
    const rawKey = profileFieldKey(f);
    if (!rawKey) {
      continue;
    }
    const cleanKey = rawKey.replace(/^custom\./i, '');
    const lower = cleanKey.toLowerCase();
    const entry: UserProfileField = {
      id: typeof f.id === 'string' && f.id.trim().length > 0 ? f.id.trim() : profileWireKey(cleanKey),
      key: cleanKey,
      value: f.value.trim(),
      updatedAt: normalizeMemoryTimestamp(f.updatedAt),
      source: f.source || 'manual'
    };
    const prevIdx = seen.get(lower);
    if (prevIdx !== undefined) {
      out[prevIdx] = entry;
    } else {
      seen.set(lower, out.length);
      out.push(entry);
    }
  }
  return out;
}

export function normalizeMemorySettings(raw?: Partial<MemorySettings>): MemorySettings {
  const maxRaw = typeof raw?.maxInjectCount === 'number' && Number.isFinite(raw.maxInjectCount)
    ? Math.max(1, Math.min(500, Math.floor(raw.maxInjectCount)))
    : 100;
  const lang: MemoryPromptLanguage =
    raw?.promptLanguage === 'zh' || raw?.promptLanguage === 'en' || raw?.promptLanguage === 'auto'
      ? raw.promptLanguage
      : 'auto';
  return {
    autoExtract: raw?.autoExtract === true,
    injectGlobal: raw?.injectGlobal !== false,
    maxInjectCount: maxRaw,
    useLegacyMemory: raw?.useLegacyMemory === true,
    enableThinking: raw?.enableThinking !== false,
    promptLanguage: lang,
    recordTraces: raw?.recordTraces !== false,
    templates: raw?.templates ? {
      rulesZh: raw.templates.rulesZh,
      rulesEn: raw.templates.rulesEn,
      gateZh: raw.templates.gateZh,
      gateEn: raw.templates.gateEn,
      extractZh: raw.templates.extractZh,
      extractEn: raw.templates.extractEn,
      smartAddSingleZh: raw.templates.smartAddSingleZh,
      smartAddSingleEn: raw.templates.smartAddSingleEn,
      smartAddBatchZh: raw.templates.smartAddBatchZh,
      smartAddBatchEn: raw.templates.smartAddBatchEn,
      profileDistillZh: raw.templates.profileDistillZh,
      profileDistillEn: raw.templates.profileDistillEn,
      legacyMigrateZh: raw.templates.legacyMigrateZh,
      legacyMigrateEn: raw.templates.legacyMigrateEn
    } : {},
    legacyMemories: Array.isArray(raw?.legacyMemories) ? raw!.legacyMemories!.slice() : []
  };
}

export function normalizeMemoryCategory(raw: string): MemoryCategory {
  const s = (raw || '').trim().toLowerCase();
  if (s === 'identity' || s === 'profile' || s === '身份' || s === '身份信息') {
    return 'identity';
  }
  if (s === 'workflow' || s === 'habit' || s === '工作流' || s === '工作方式') {
    return 'workflow';
  }
  if (s === 'tone' || s === 'voice' || s === 'style' || s === '语气' || s === '风格' || s === '表达风格') {
    return 'tone';
  }
  return 'instruction';
}

function tokenizeForSimilarity(text: string): Set<string> {
  const tokens = new Set<string>();
  const lower = text.toLowerCase().trim();
  const words = lower.split(/[\s,.;:!?()[\]{}"'`~，。；：！？（）【】、/]+/);
  for (let i = 0; i < words.length; i++) {
    const w = words[i].trim();
    if (w.length === 0) {
      continue;
    }
    if (/[\u4e00-\u9fff]/.test(w) && w.length > 2) {
      for (let j = 0; j < w.length - 1; j++) {
        tokens.add(w.slice(j, j + 2));
      }
    } else {
      tokens.add(w);
    }
  }
  return tokens;
}

export function computeTextSimilarity(a: string, b: string): number {
  const na = a.toLowerCase().trim();
  const nb = b.toLowerCase().trim();
  if (na.length === 0 || nb.length === 0) {
    return 0;
  }
  if (na === nb) {
    return 1;
  }
  if (na.indexOf(nb) >= 0 || nb.indexOf(na) >= 0) {
    const minLen = Math.min(na.length, nb.length);
    const maxLen = Math.max(na.length, nb.length);
    if (minLen / maxLen >= 0.72) {
      return minLen / maxLen;
    }
  }
  const setA = tokenizeForSimilarity(na);
  const setB = tokenizeForSimilarity(nb);
  if (setA.size === 0 || setB.size === 0) {
    return 0;
  }
  let intersection = 0;
  setA.forEach((tok: string) => {
    if (setB.has(tok)) {
      intersection += 1;
    }
  });
  const union = setA.size + setB.size - intersection;
  return union > 0 ? intersection / union : 0;
}

export const MEMORY_CATEGORIES: MemoryCategory[] = ['identity', 'workflow', 'tone', 'instruction'];

export const STANDARD_PROFILE_FIELDS: StandardProfileFieldSpec[] = [
  { key: 'preferred_name', labelZh: '称呼偏好', labelEn: 'Preferred name', placeholderZh: '希望助手如何称呼你' },
  { key: 'gender', labelZh: '性别', labelEn: 'Gender', placeholderZh: '如：男 / 女' },
  { key: 'pronouns', labelZh: '代词', labelEn: 'Pronouns', placeholderZh: '如：他 / 她 / they' },
  { key: 'preferred_language', labelZh: '常用语言', labelEn: 'Preferred language', placeholderZh: '如：中文 / English' },
  { key: 'timezone', labelZh: '时区', labelEn: 'Timezone', placeholderZh: '如：Asia/Shanghai (UTC+8)' },
  { key: 'occupation', labelZh: '职业', labelEn: 'Occupation', placeholderZh: '如：软件工程师' },
  { key: 'location', labelZh: '所在地', labelEn: 'Location', placeholderZh: '如：北京' }
];

export const PROFILE_KEYS: string[] = [
  'preferred_name', 'gender', 'pronouns', 'preferred_language', 'timezone', 'occupation', 'location'
];

export function isStandardProfileKey(key: string): boolean {
  return PROFILE_KEYS.includes(key.trim().toLowerCase());
}

export function profileKeyDisplayLabel(key: string): string {
  const clean = key.replace(/^custom\./i, '').trim();
  const lower = clean.toLowerCase();
  for (let i = 0; i < STANDARD_PROFILE_FIELDS.length; i++) {
    if (STANDARD_PROFILE_FIELDS[i].key === lower) {
      return STANDARD_PROFILE_FIELDS[i].labelZh;
    }
  }
  return clean;
}

export function profileWireKey(key: string): string {
  const clean = (key || '').trim();
  if (!clean) return 'custom.field';
  return PROFILE_KEYS.includes(clean) || clean.startsWith('custom.') ? clean : 'custom.' + clean;
}

export function memoryTypeName(category: MemoryCategory): string {
  return category === 'tone' ? 'voice' : category;
}

export function canReadMemory(entry: MemoryEntry, assistantId?: string, includeGlobal: boolean = true): boolean {
  return entry.assistantId ? entry.assistantId === assistantId : includeGlobal;
}

export function findOrphanedMemories(memories: MemoryEntry[], personas: Persona[]): MemoryEntry[] {
  const validIds = new Set<string>(personas.map((p: Persona): string => p.id));
  return memories.filter((m: MemoryEntry): boolean =>
    Boolean(m.assistantId && m.assistantId.trim().length > 0 && !validIds.has(m.assistantId))
  );
}

export function memoryWriteAssistantId(policy: MemoryWriteScope, assistantId: string, requested?: string): string | undefined {
  if (policy === 'alwaysGlobal') return undefined;
  if (policy === 'alwaysAssistant') return assistantId;
  if (requested === 'global') return undefined;
  if (requested === 'assistant' || policy === 'toolDefaultAssistant') return assistantId;
  return undefined;
}

function escapeXml(text: string): string {
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&apos;');
}

function compareMemoryId(a: MemoryEntry, b: MemoryEntry): number {
  return a.id.localeCompare(b.id);
}

export function memoryDate(timestamp: number): string {
  const ms = normalizeMemoryTimestamp(timestamp);
  const date = new Date(ms);
  return Number.isFinite(date.getTime()) ? date.toISOString().slice(0, 10) : '';
}

export function buildProfileBlock(profile: UserProfileField[]): string {
  const normalized = normalizeUserProfileFields(profile);
  const fields = normalized.filter((field: UserProfileField): boolean =>
    Boolean(profileFieldKey(field) && field.value && field.value.trim())
  );
  if (fields.length === 0) return '<user_profile/>';
  const lines = ['<user_profile>'];
  for (const key of PROFILE_KEYS) {
    const field = fields.find((item: UserProfileField): boolean => profileFieldKey(item).toLowerCase() === key);
    if (field) lines.push(`<${key}>${escapeXml(field.value.trim())}</${key}>`);
  }
  const custom = fields.filter((field: UserProfileField): boolean =>
    !PROFILE_KEYS.includes(profileFieldKey(field).toLowerCase())
  );
  custom.sort((a: UserProfileField, b: UserProfileField): number =>
    profileFieldKey(a).localeCompare(profileFieldKey(b))
  );
  for (const field of custom) {
    const name = profileFieldKey(field).replace(/^custom\./, '').trim();
    lines.push(`<custom name="${escapeXml(name)}">${escapeXml(field.value.trim())}</custom>`);
  }
  lines.push('</user_profile>');
  return lines.join('\n');
}

export function buildMemoryInjectionBlock(
  memories: MemoryEntry[],
  profile: UserProfileField[],
  settings: MemorySettings,
  assistantId?: string,
  fullTypes: MemoryCategory[] = []
): string {
  if (settings.useLegacyMemory && Array.isArray(settings.legacyMemories) && settings.legacyMemories.length > 0) {
    const legacyLines = settings.legacyMemories
      .map((s: string): string => s.trim())
      .filter((s: string): boolean => s.length > 0)
      .map((s: string): string => `- ${s}`);
    if (legacyLines.length === 0) return '';
    return ['以下是长期记忆，请在与当前请求相关时参考。', '<legacy_memory>', ...legacyLines, '</legacy_memory>'].join('\n');
  }

  const maxCount = settings.maxInjectCount > 0 ? Math.max(1, Math.min(500, Math.floor(settings.maxInjectCount))) : 100;
  const includeGlobal = settings.injectGlobal !== false;
  const active = memories.filter((entry: MemoryEntry): boolean =>
    !entry.archived && typeof entry.content === 'string' && entry.content.trim().length > 0 &&
      canReadMemory(entry, assistantId, includeGlobal));
  const visibleProfile = includeGlobal ? normalizeUserProfileFields(profile) : [];
  if (active.length === 0 && !visibleProfile.some((field: UserProfileField): boolean => Boolean(field.value.trim()))) {
    return '';
  }

  const sections = ['以下是用户画像与长期记忆，请在与当前请求相关时参考。', buildProfileBlock(visibleProfile)];
  for (const category of MEMORY_CATEGORIES) {
    const entries = active.filter((entry: MemoryEntry): boolean => entry.category === category);
    const tag = `<user_memory type="${memoryTypeName(category)}"`;
    if (!entries.length) {
      sections.push(tag + '/>');
      continue;
    }
    const truncated = !fullTypes.includes(category) && entries.length > maxCount;
    if (truncated) {
      entries.sort((a: MemoryEntry, b: MemoryEntry): number =>
        normalizeMemoryTimestamp(b.updatedAt) - normalizeMemoryTimestamp(a.updatedAt) || compareMemoryId(a, b));
    }
    const selected = truncated ? entries.slice(0, maxCount) : entries;
    selected.sort((a: MemoryEntry, b: MemoryEntry): number =>
      Number(Boolean(a.assistantId)) - Number(Boolean(b.assistantId)) ||
        normalizeMemoryTimestamp(a.createdAt) - normalizeMemoryTimestamp(b.createdAt) || compareMemoryId(a, b));
    const lines = [truncated ? tag + ` mode="summary" total="${entries.length}" shown="${selected.length}">` : tag + '>'];
    for (const entry of selected) {
      const scope = entry.assistantId ? '(assistant) ' : '';
      lines.push(`- [${memoryDate(entry.updatedAt)}] ${scope}${escapeXml(entry.content.trim().replace(/\s+/g, ' '))}`);
    }
    if (truncated) lines.push('此分类还有更多条目，可通过记忆工具查阅。');
    lines.push('</user_memory>');
    sections.push(lines.join('\n'));
  }
  return sections.join('\n');
}

// ===== Aligned Default Prompt Templates (Chinese & English, verbatim from Android Kelivo) =====

export const DEFAULT_MEMORY_RULES_ZH: string =
  '## 长期记忆\n\n' +
  '对话中可能包含系统提供的记忆信息，这不是用户在当前轮说的话：\n\n' +
  '- <user_profile> 保存关于用户的稳定事实，例如希望如何被称呼、语言偏好与时区。\n' +
  '- <user_memory type="..."> 按四个分类保存长期记忆。每行格式为 `- [2026-08-07] 内容`，方括号内是该条目最近更新日期。带有 `(assistant) ` 前缀的条目仅属于当前助手，其余对所有助手可见。\n' +
  '- 带有 `mode="summary"` 标记的块表示该分类共有 `total` 条记忆，当前仅列出最新的 `shown` 条。需要更多时请调用 `memory_search_profile`（或 `memory_read`）。\n' +
  '- 空标签（如 `<user_memory type="voice"/>`）表示该分类当前没有条目。\n' +
  '- 对话中途出现的 `<user_memory_update>` 是最新的完整快照，请用它替换此前看到的记忆。\n\n' +
  '称呼用户时，如 `<user_profile>` 中有 `preferred_name` 请使用它；否则不要猜测，也绝不要把记忆中出现的其他人名当作用户名。\n\n' +
  '当用户透露在另一个新对话中仍然成立的信息时，调用 `memory_update` 写入一条记忆。判断标准：如果开启一段全新对话，不知道这件事是否会让你的回答变差？\n\n' +
  '不要写入：当前对话的临时背景、你自行推断但用户未确认的结论、用户随口提及的话题，或可以直接从聊天记录中查到的事实。\n\n' +
  '用完整的第三人称陈述描述用户，不要使用「这个」「刚才」等指回当前对话的词。系统会自动去重与合并，无需先读取再重写整条。\n\n' +
  '当用户指出某条记忆有误时，使用 `memory_edit` 更正或 `memory_delete` 归档。';

export const DEFAULT_MEMORY_RULES_EN: string =
  '## Long-term memory\n\n' +
  'The conversation may contain memory information provided by the system. It is not what the user said in the current turn:\n\n' +
  '- <user_profile> holds stable facts about the user, such as how they want to be addressed, language preference and timezone.\n' +
  '- <user_memory type="..."> holds long-term memory in four categories. Each line looks like `- [2026-08-07] content`, where the bracket is the date this entry was last updated. Entries prefixed with `(assistant) ` belong only to the current assistant; the rest are visible to all assistants.\n' +
  '- A block marked mode="summary" means the category has the number of entries given by the total attribute, and only the most recent ones indicated by the shown attribute are listed. Use memory_search_profile when you need more.\n' +
  '- An empty tag such as <user_memory type="voice"/> means the category currently has no entries.\n' +
  '- A <user_memory_update> appearing mid-conversation is the latest complete snapshot. Replace the memory you saw earlier with it.\n\n' +
  'When addressing the user, use preferred_name from <user_profile> if present. Otherwise do not guess, and never use the name of another person that appears in memory.\n\n' +
  'When the user reveals something that will still be true in a different conversation, write one entry with memory_update. The test is: if you started a fresh conversation, would not knowing this make your answer worse?\n\n' +
  'Do not write: temporary context from this conversation, conclusions you inferred but the user did not confirm, topics the user merely mentioned in passing, or facts that can be looked up directly in the chat history.\n\n' +
  'Write complete third-person statements about the user. Do not use words like "this" or "just now" that point back to the current conversation. The system deduplicates and merges automatically, so you do not need to read first and rewrite the whole entry.\n\n' +
  'When the user says an entry is wrong, use memory_edit to fix it or memory_delete to archive it.';

export const DEFAULT_MEMORY_GATE_ZH: string =
  '分析以下对话，判断其中是否包含值得长期记忆的用户信息。\n\n' +
  '值得记忆：用户透露了个人信息、做事偏好、表达风格特征、对助手的明确要求\n' +
  '不值得：纯技术问答、项目细节、一次性操作指令\n\n' +
  '输出格式（严格按此 XML，不要输出多余文字）：\n' +
  '<gate>\n' +
  '  <user_memory>true 或 false</user_memory>\n' +
  '</gate>\n\n' +
  '## 对话\n' +
  '{{conversation}}';

export const DEFAULT_MEMORY_GATE_EN: string =
  'Analyse the conversation below and decide whether it contains user information worth remembering long term.\n\n' +
  'Worth remembering: the user revealed personal information, a way of working, a characteristic of how they express themselves, or an explicit requirement for the assistant.\n' +
  'Not worth remembering: pure technical Q&A, project details, one-off operational instructions.\n\n' +
  'Output format (follow this XML exactly, no extra text):\n' +
  '<gate>\n' +
  '  <user_memory>true or false</user_memory>\n' +
  '</gate>\n\n' +
  '## Conversation\n' +
  '{{conversation}}';

export const DEFAULT_MEMORY_EXTRACT_ZH: string =
  '从对话中提取用户画像的新信息。每条信息独立、简洁、完整。\n\n' +
  '四类画像：\n' +
  '- identity（身份）：姓名、性别、代词偏好、职业、公司、身边的人、背景\n' +
  '- workflow（工作方式）：做事流程、工具偏好、调试习惯\n' +
  '- voice（表达风格）：行文风格、句式节奏、用词习惯\n' +
  '- instruction（用户指令）：用户对助手的明确要求——回复风格、禁止项、交互偏好\n\n' +
  '规则：\n' +
  '- 只从用户说的话里提取\n' +
  '- 不提取助手的角色设定\n' +
  '- 不提取可以直接从对话记录或代码里查到的事实\n' +
  '- 每条一句话，独立自包含，用第三人称描述用户\n' +
  '- 不使用「这个」「刚才」等指回本次对话的词\n' +
  '- 「已有记忆」里已经出现过的信息不要重复提取\n\n' +
  '## 已有记忆\n' +
  '{{existingMemory}}\n\n' +
  '输出格式：\n' +
  '<extracted>\n' +
  '<item type="identity|workflow|voice|instruction">一句话描述</item>\n' +
  '</extracted>\n\n' +
  '如果没有值得提取的信息：\n' +
  '<extracted/>\n\n' +
  '## 对话\n' +
  '{{conversation}}';

export const DEFAULT_MEMORY_EXTRACT_EN: string =
  'Extract new information about the user from the conversation. Each item must be independent, concise and complete.\n\n' +
  'Four categories:\n' +
  '- identity: name, gender, pronoun preference, occupation, company, people around them, background\n' +
  '- workflow: how they work, tool preferences, debugging habits\n' +
  '- voice: writing style, sentence rhythm, word choice\n' +
  '- instruction: explicit requirements the user has for the assistant — reply style, prohibitions, interaction preferences\n\n' +
  'Rules:\n' +
  '- Extract only from what the user said\n' +
  '- Do not extract the assistant\'s persona\n' +
  '- Do not extract facts that can be looked up directly in the chat history or in code\n' +
  '- One sentence per item, self-contained, third person about the user\n' +
  '- Do not use words like "this" or "just now" that point back to the current conversation\n' +
  '- Do not re-extract anything already present in "Existing memory"\n\n' +
  '## Existing memory\n' +
  '{{existingMemory}}\n\n' +
  'Output format:\n' +
  '<extracted>\n' +
  '<item type="identity|workflow|voice|instruction">one sentence</item>\n' +
  '</extracted>\n\n' +
  'If there is nothing worth extracting:\n' +
  '<extracted/>\n\n' +
  '## Conversation\n' +
  '{{conversation}}';

export const DEFAULT_MEMORY_SMART_ADD_SINGLE_ZH: string =
  '你是记忆去重裁判。判断新信息与已有记忆的关系。\n\n' +
  '## 新信息\n' +
  '类型：{{type}}\n' +
  '内容：{{newInfo}}\n\n' +
  '## 相似的已有记忆（最多 5 条）\n' +
  '{{entriesText}}\n\n' +
  '判断：\n' +
  '- NEW：没有相关记忆；新增一条\n' +
  '- MERGE：合并到某条已有记忆；输出完整合并后的内容\n' +
  '- CONFLICT：与某条已有记忆矛盾（用户改变了偏好）；归档旧条目并写入新条目\n' +
  '- SKIP：已有记忆已包含该信息；无需操作\n\n' +
  '同时判断：列出的已有记忆中哪些与新信息在语义上相关（即使既不重复也不冲突）？\n\n' +
  '只输出 JSON，不要解释：\n' +
  '{ "action": "NEW" | "MERGE" | "CONFLICT" | "SKIP", "targetId": "...", "mergedContent": "...", "relatedIds": ["mem_xxxxxxxx"] }';

export const DEFAULT_MEMORY_SMART_ADD_SINGLE_EN: string =
  'You are a memory deduplication judge. Decide how the new information relates to existing memory.\n\n' +
  '## New information\n' +
  'Type: {{type}}\n' +
  'Content: {{newInfo}}\n\n' +
  '## Similar existing memories (up to 5)\n' +
  '{{entriesText}}\n\n' +
  'Decide:\n' +
  '- NEW: nothing related exists; create a new entry\n' +
  '- MERGE: merge into an existing entry; output the full merged content\n' +
  '- CONFLICT: contradicts an existing entry (the user changed a preference); archive the old one and write the new one\n' +
  '- SKIP: existing memory already contains this information; do nothing\n\n' +
  'Also decide: which of the listed existing memories are semantically related to the new information (even if not duplicate and not conflicting)?\n\n' +
  'Output JSON only, no explanation:\n' +
  '{ "action": "NEW" | "MERGE" | "CONFLICT" | "SKIP", "targetId": "...", "mergedContent": "...", "relatedIds": ["mem_xxxxxxxx"] }';

export const DEFAULT_MEMORY_SMART_ADD_BATCH_ZH: string =
  '你是记忆去重裁判。判断每条新信息与已有记忆的关系。\n\n' +
  '## 新信息\n' +
  '{{itemsText}}\n\n' +
  '## 相似的已有记忆\n' +
  '{{entriesText}}\n\n' +
  '对每条新信息判断：\n' +
  '- NEW：没有相关记忆；新增一条\n' +
  '- MERGE：合并到某条已有记忆；输出完整合并后的内容\n' +
  '- CONFLICT：与某条已有记忆矛盾（用户改变了偏好）；归档旧条目并写入新条目\n' +
  '- SKIP：已有记忆已包含该信息；无需操作\n\n' +
  '同时对每条新信息判断：列出的已有记忆中哪些与它在语义上相关（即使既不重复也不冲突）。\n\n' +
  '只输出 JSON，不要解释：\n' +
  '{"results":[{"index":1,"action":"NEW","targetId":null,"mergedContent":null,"relatedIds":[]}]}';

export const DEFAULT_MEMORY_SMART_ADD_BATCH_EN: string =
  'You are a memory deduplication judge. Decide how each piece of new information relates to existing memory.\n\n' +
  '## New information\n' +
  '{{itemsText}}\n\n' +
  '## Similar existing memories\n' +
  '{{entriesText}}\n\n' +
  'For each piece of new information, decide:\n' +
  '- NEW: nothing related exists; create a new entry\n' +
  '- MERGE: merge into an existing entry; output the full merged content\n' +
  '- CONFLICT: contradicts an existing entry (the user changed a preference); archive the old one and write the new one\n' +
  '- SKIP: existing memory already contains this information; do nothing\n\n' +
  'Also, for each piece of new information, decide which of the listed existing memories are semantically related to it (even if not duplicate and not conflicting).\n\n' +
  'Output JSON only, no explanation:\n' +
  '{"results":[{"index":1,"action":"NEW","targetId":null,"mergedContent":null,"relatedIds":[]}]}';

export const DEFAULT_MEMORY_PROFILE_DISTILL_ZH: string =
  '从用户的身份记忆中提炼稳定的用户画像字段。\n\n' +
  '## 当前画像\n' +
  '{{profileBlock}}\n\n' +
  '## 身份记忆\n' +
  '{{identityEntries}}\n\n' +
  '可用字段：preferred_name（用户希望如何被称呼）、gender、pronouns、preferred_language、timezone、occupation、location\n\n' +
  '规则：\n' +
  '- 记忆中没有明确证据的字段不要输出\n' +
  '- 当前画像中已有值的字段除非被新记忆推翻，否则不要重复输出\n' +
  '- 仅在用户明确表达希望如何被称呼时才输出 preferred_name；绝不要把记忆中出现的其他人名当作用户名\n' +
  '- 不确定则不输出\n\n' +
  '只输出 JSON，不要解释：\n' +
  '{"fields":[{"key":"preferred_name","value":"..."}]}';

export const DEFAULT_MEMORY_PROFILE_DISTILL_EN: string =
  'Distill stable profile fields from the user\'s identity memories.\n\n' +
  '## Current profile\n' +
  '{{profileBlock}}\n\n' +
  '## Identity memories\n' +
  '{{identityEntries}}\n\n' +
  'Available fields: preferred_name (how the user wants to be addressed), gender, pronouns, preferred_language, timezone, occupation, location\n\n' +
  'Rules:\n' +
  '- Do not output a field without clear evidence in the memories\n' +
  '- Do not output a field that already has a value in the current profile unless the memories overturn it\n' +
  '- Only output preferred_name when the user has explicitly said how they want to be addressed; never use the name of another person that appears in memory\n' +
  '- If uncertain, do not output\n\n' +
  'Output JSON only, no explanation:\n' +
  '{"fields":[{"key":"preferred_name","value":"..."}]}';

export const DEFAULT_MEMORY_LEGACY_MIGRATE_ZH: string =
  '你正在将旧版长期记忆迁移到分类记忆系统。\n\n' +
  '对每条输入项，返回具有相同整数 id 的唯一输出项。保留所有事实、偏好、否定、限定与不确定性，保持原语言。仅在必要时改写以使记忆简洁、独立且无需对话上下文即可理解。适当时用第三人称陈述描述用户。\n\n' +
  '只选择一个分类：\n' +
  '- identity：稳定事实、偏好、背景、关系、兴趣或个人情境\n' +
  '- workflow：用户工作、决策、规划或使用工具的固定方式\n' +
  '- voice：偏好的语气、用词、语言、格式或沟通风格\n' +
  '- instruction：助手应遵循的长期规则\n\n' +
  '不要编造、翻译、合并、拆分、遗漏、去重、解释或添加建议。\n\n' +
  '仅返回如下格式的 JSON 数组：\n' +
  '[{"id":1,"type":"identity","content":"..."}]\n\n' +
  '输入：\n' +
  '{{items}}';

export const DEFAULT_MEMORY_LEGACY_MIGRATE_EN: string =
  'You are migrating legacy long-term memories into a typed memory system.\n\n' +
  'For every input item, return exactly one output item with the same integer id. Preserve every fact, preference, negation, qualification, and uncertainty. Keep the original language. Rewrite only enough to make the memory concise, self-contained, and understandable without conversation context. When appropriate, phrase it as a third-person statement about the user.\n\n' +
  'Choose exactly one type:\n' +
  '- identity: stable facts, preferences, background, relationships, interests, or personal context\n' +
  '- workflow: recurring ways the user works, decides, plans, or uses tools\n' +
  '- voice: preferred tone, wording, language, formatting, or communication style\n' +
  '- instruction: durable rules for how an assistant should behave or respond\n\n' +
  'Do not invent, translate, merge, split, omit, deduplicate, explain, or add advice.\n\n' +
  'Return only a JSON array in this exact shape:\n' +
  '[{"id":1,"type":"identity","content":"..."}]\n\n' +
  'Input:\n' +
  '{{items}}';

export type MemoryTemplateKind =
  'rules' | 'gate' | 'extract' | 'smartAddSingle' | 'smartAddBatch' | 'profileDistill' | 'legacyMigrate';

export function resolveMemoryPromptLang(settings?: MemorySettings, uiLanguage: string = 'zh-Hans'): 'zh' | 'en' {
  const pref = settings?.promptLanguage || 'auto';
  if (pref === 'zh') return 'zh';
  if (pref === 'en') return 'en';
  return uiLanguage.startsWith('zh') ? 'zh' : 'en';
}

export function getDefaultMemoryTemplate(kind: MemoryTemplateKind, lang: 'zh' | 'en'): string {
  if (kind === 'rules') return lang === 'zh' ? DEFAULT_MEMORY_RULES_ZH : DEFAULT_MEMORY_RULES_EN;
  if (kind === 'gate') return lang === 'zh' ? DEFAULT_MEMORY_GATE_ZH : DEFAULT_MEMORY_GATE_EN;
  if (kind === 'extract') return lang === 'zh' ? DEFAULT_MEMORY_EXTRACT_ZH : DEFAULT_MEMORY_EXTRACT_EN;
  if (kind === 'smartAddSingle') return lang === 'zh' ? DEFAULT_MEMORY_SMART_ADD_SINGLE_ZH : DEFAULT_MEMORY_SMART_ADD_SINGLE_EN;
  if (kind === 'smartAddBatch') return lang === 'zh' ? DEFAULT_MEMORY_SMART_ADD_BATCH_ZH : DEFAULT_MEMORY_SMART_ADD_BATCH_EN;
  if (kind === 'profileDistill') return lang === 'zh' ? DEFAULT_MEMORY_PROFILE_DISTILL_ZH : DEFAULT_MEMORY_PROFILE_DISTILL_EN;
  return lang === 'zh' ? DEFAULT_MEMORY_LEGACY_MIGRATE_ZH : DEFAULT_MEMORY_LEGACY_MIGRATE_EN;
}

export function getEffectiveMemoryTemplate(
  settings: MemorySettings | undefined,
  kind: MemoryTemplateKind,
  lang: 'zh' | 'en'
): string {
  const tpl: MemoryPromptTemplates | undefined = settings?.templates;
  let custom: string | undefined = undefined;
  if (tpl) {
    if (kind === 'rules') custom = lang === 'zh' ? tpl.rulesZh : tpl.rulesEn;
    else if (kind === 'gate') custom = lang === 'zh' ? tpl.gateZh : tpl.gateEn;
    else if (kind === 'extract') custom = lang === 'zh' ? tpl.extractZh : tpl.extractEn;
    else if (kind === 'smartAddSingle') custom = lang === 'zh' ? tpl.smartAddSingleZh : tpl.smartAddSingleEn;
    else if (kind === 'smartAddBatch') custom = lang === 'zh' ? tpl.smartAddBatchZh : tpl.smartAddBatchEn;
    else if (kind === 'profileDistill') custom = lang === 'zh' ? tpl.profileDistillZh : tpl.profileDistillEn;
    else if (kind === 'legacyMigrate') custom = lang === 'zh' ? tpl.legacyMigrateZh : tpl.legacyMigrateEn;
  }
  if (custom && custom.trim().length > 0) {
    return custom.trim();
  }
  return getDefaultMemoryTemplate(kind, lang);
}

export function buildMemoryRulesSystemPrompt(settings?: MemorySettings, uiLanguage: string = 'zh-Hans'): string {
  if (settings?.useLegacyMemory) {
    return '';
  }
  const lang = resolveMemoryPromptLang(settings, uiLanguage);
  return getEffectiveMemoryTemplate(settings, 'rules', lang);
}

interface ScoredMemory {
  entry: MemoryEntry;
  score: number;
}

export function searchMemories(
  memories: MemoryEntry[],
  query: string,
  assistantId?: string,
  includeArchived: boolean = false
): MemoryEntry[] {
  const q = query.trim().toLowerCase();
  const tokens = Array.from(tokenizeForSimilarity(q));
  const scored: ScoredMemory[] = [];

  for (let i = 0; i < memories.length; i++) {
    const m = memories[i];
    if (!includeArchived && m.archived) {
      continue;
    }
    if (assistantId !== undefined && !canReadMemory(m, assistantId)) {
      continue;
    }
    if (q.length === 0) {
      scored.push({ entry: m, score: normalizeMemoryTimestamp(m.updatedAt) });
      continue;
    }
    const lower = m.content.toLowerCase();
    let score = 0;
    if (lower.indexOf(q) >= 0) {
      score += 10;
    }
    for (let t = 0; t < tokens.length; t++) {
      if (lower.indexOf(tokens[t]) >= 0) {
        score += 2;
      }
    }
    if (m.category.toLowerCase().indexOf(q) >= 0) {
      score += 1;
    }
    if (score > 0) {
      scored.push({ entry: m, score });
    }
  }

  scored.sort((a: ScoredMemory, b: ScoredMemory): number => {
    if (b.score !== a.score) {
      return b.score - a.score;
    }
    return normalizeMemoryTimestamp(b.entry.updatedAt) - normalizeMemoryTimestamp(a.entry.updatedAt);
  });

  return scored.map((item: ScoredMemory): MemoryEntry => item.entry);
}

export function findSimilarActiveMemories(
  existing: MemoryEntry[],
  candidateContent: string,
  category: MemoryCategory | undefined,
  assistantId: string | undefined,
  limit: number = 5
): MemoryEntry[] {
  const scored: ScoredMemory[] = [];
  for (let i = 0; i < existing.length; i++) {
    const m = existing[i];
    if (m.archived) continue;
    if ((m.assistantId || '') !== (assistantId || '')) continue;
    if (category && m.category !== category) continue;
    const sim = computeTextSimilarity(m.content, candidateContent);
    if (sim > 0.12) {
      scored.push({ entry: m, score: sim });
    }
  }
  scored.sort((a: ScoredMemory, b: ScoredMemory): number =>
    b.score - a.score || normalizeMemoryTimestamp(b.entry.updatedAt) - normalizeMemoryTimestamp(a.entry.updatedAt)
  );
  return scored.slice(0, limit).map((s: ScoredMemory): MemoryEntry => s.entry);
}

export function parseGatekeeperXml(rawText: string): boolean {
  const m = rawText.match(/<user_memory>\s*(true|false)\s*<\/user_memory>/i);
  if (m && m[1]) {
    return m[1].toLowerCase() === 'true';
  }
  const parsed = parseMemoryExtractionResponse(rawText);
  if (parsed.shouldSave || parsed.memories.length > 0) {
    return true;
  }
  return false;
}

export function parseExtractedMemoriesXml(rawText: string): ExtractedMemoryCandidate[] {
  const out: ExtractedMemoryCandidate[] = [];
  if (/<extracted\s*\/>/i.test(rawText)) {
    return out;
  }
  const itemRe = /<item\s+type=["']([^"']+)["'][^>]*>([\s\S]*?)<\/item>/gi;
  let match = itemRe.exec(rawText);
  while (match !== null) {
    const rawType = match[1] || 'instruction';
    const rawContent = (match[2] || '').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&').trim();
    if (rawContent.length > 0) {
      out.push({
        category: normalizeMemoryCategory(rawType),
        content: rawContent
      });
    }
    match = itemRe.exec(rawText);
  }
  if (out.length > 0) {
    return out;
  }
  const fallback = parseMemoryExtractionResponse(rawText);
  return fallback.memories;
}

function extractFirstJsonObject(rawText: string): Record<string, Object> | undefined {
  const start = rawText.indexOf('{');
  const end = rawText.lastIndexOf('}');
  if (start < 0 || end <= start) return undefined;
  try {
    const parsed = JSON.parse(rawText.slice(start, end + 1)) as Record<string, Object>;
    if (parsed && typeof parsed === 'object') return parsed;
  } catch (_) {}
  return undefined;
}

function normalizeSmartAddAction(raw: Object | undefined): 'NEW' | 'MERGE' | 'CONFLICT' | 'SKIP' {
  const s = typeof raw === 'string' ? raw.trim().toUpperCase() : '';
  if (s === 'MERGE' || s === 'CONFLICT' || s === 'SKIP') {
    return s;
  }
  return 'NEW';
}

export function parseSmartAddSingleResponse(rawText: string): SmartAddDecision | undefined {
  const obj = extractFirstJsonObject(rawText);
  if (!obj) return undefined;
  const action = normalizeSmartAddAction(obj['action']);
  const targetId = typeof obj['targetId'] === 'string' && obj['targetId'].trim().length > 0
    ? obj['targetId'].trim()
    : undefined;
  const mergedContent = typeof obj['mergedContent'] === 'string' && obj['mergedContent'].trim().length > 0
    ? obj['mergedContent'].trim()
    : undefined;
  const relatedIds: string[] = [];
  if (Array.isArray(obj['relatedIds'])) {
    const arr = obj['relatedIds'] as Object[];
    for (let i = 0; i < arr.length; i++) {
      if (typeof arr[i] === 'string' && (arr[i] as string).trim().length > 0) {
        relatedIds.push((arr[i] as string).trim());
      }
    }
  }
  return { action, targetId, mergedContent, relatedIds };
}

export function parseSmartAddBatchResponse(rawText: string): Map<number, SmartAddDecision> {
  const map = new Map<number, SmartAddDecision>();
  const obj = extractFirstJsonObject(rawText);
  if (!obj || !Array.isArray(obj['results'])) return map;
  const arr = obj['results'] as Record<string, Object>[];
  for (let i = 0; i < arr.length; i++) {
    const item = arr[i];
    if (!item || typeof item !== 'object') continue;
    const idx = typeof item['index'] === 'number' ? Math.floor(item['index'] as number) : (i + 1);
    const action = normalizeSmartAddAction(item['action']);
    const targetId = typeof item['targetId'] === 'string' && (item['targetId'] as string).trim().length > 0
      ? (item['targetId'] as string).trim()
      : undefined;
    const mergedContent = typeof item['mergedContent'] === 'string' && (item['mergedContent'] as string).trim().length > 0
      ? (item['mergedContent'] as string).trim()
      : undefined;
    const relatedIds: string[] = [];
    if (Array.isArray(item['relatedIds'])) {
      const rels = item['relatedIds'] as Object[];
      for (let r = 0; r < rels.length; r++) {
        if (typeof rels[r] === 'string' && (rels[r] as string).trim().length > 0) {
          relatedIds.push((rels[r] as string).trim());
        }
      }
    }
    map.set(idx, { action, targetId, mergedContent, relatedIds });
  }
  return map;
}

export function applySmartAddDecisions(
  existing: MemoryEntry[],
  candidates: ExtractedMemoryCandidate[],
  decisions: Map<number, SmartAddDecision>,
  conversationId?: string,
  assistantId?: string,
  source: MemorySourceKind = 'extracted'
): MemoryMergeResult {
  let next: MemoryEntry[] = existing.map((m: MemoryEntry): MemoryEntry => ({
    id: m.id,
    category: m.category,
    content: m.content,
    assistantId: m.assistantId,
    archived: m.archived,
    createdAt: normalizeMemoryTimestamp(m.createdAt),
    updatedAt: normalizeMemoryTimestamp(m.updatedAt),
    sourceConversationId: m.sourceConversationId,
    source: m.source,
    relatedIds: m.relatedIds ? m.relatedIds.slice() : undefined
  }));
  let addedCount = 0;
  let mergedCount = 0;
  let conflictCount = 0;
  let skippedCount = 0;
  const now = Date.now();

  for (let i = 0; i < candidates.length; i++) {
    const cand = candidates[i];
    const clean = cand.content.trim();
    if (!clean) continue;
    const dec = decisions.get(i + 1);
    if (!dec) {
      const fallback = mergeMemoryCandidates(next, [cand], conversationId, assistantId, source);
      next = fallback.entries;
      addedCount += fallback.addedCount;
      mergedCount += fallback.mergedCount;
      continue;
    }

    if (dec.action === 'SKIP') {
      skippedCount += 1;
      continue;
    }

    const targetIdx = dec.targetId
      ? next.findIndex((m: MemoryEntry): boolean => m.id === dec.targetId && !m.archived && (m.assistantId || '') === (assistantId || ''))
      : -1;

    if (dec.action === 'MERGE' && targetIdx >= 0) {
      const target = next[targetIdx];
      const mergedText = dec.mergedContent && dec.mergedContent.trim().length > 0 ? dec.mergedContent.trim() : clean;
      const relSet = new Set<string>(target.relatedIds || []);
      for (let r = 0; r < dec.relatedIds.length; r++) {
        if (dec.relatedIds[r] !== target.id) relSet.add(dec.relatedIds[r]);
      }
      next[targetIdx] = {
        id: target.id,
        category: target.category,
        content: mergedText,
        assistantId: target.assistantId,
        archived: false,
        createdAt: target.createdAt,
        updatedAt: now + i,
        sourceConversationId: conversationId ?? target.sourceConversationId,
        source: target.source || source,
        relatedIds: Array.from(relSet)
      };
      mergedCount += 1;
      continue;
    }

    if (dec.action === 'CONFLICT' && targetIdx >= 0) {
      const oldEntry = next[targetIdx];
      next[targetIdx] = {
        id: oldEntry.id,
        category: oldEntry.category,
        content: oldEntry.content,
        assistantId: oldEntry.assistantId,
        archived: true,
        createdAt: oldEntry.createdAt,
        updatedAt: now + i,
        sourceConversationId: oldEntry.sourceConversationId,
        source: oldEntry.source,
        relatedIds: oldEntry.relatedIds
      };
      const relSet = new Set<string>(dec.relatedIds);
      relSet.add(oldEntry.id);
      next.push({
        id: nextMemId('mem'),
        category: cand.category,
        content: clean,
        assistantId,
        archived: false,
        createdAt: now + i,
        updatedAt: now + i,
        sourceConversationId: conversationId,
        source,
        relatedIds: Array.from(relSet)
      });
      conflictCount += 1;
      addedCount += 1;
      continue;
    }

    // NEW (or MERGE/CONFLICT without valid targetId: run similarity check to avoid exact duplicates)
    const simResult = mergeMemoryCandidates(next, [cand], conversationId, assistantId, source, dec.relatedIds);
    next = simResult.entries;
    addedCount += simResult.addedCount;
    mergedCount += simResult.mergedCount;
  }

  return { entries: next, addedCount, mergedCount, conflictCount, skippedCount };
}

export function parseProfileDistillerResponse(rawText: string): ExtractedProfileCandidate[] {
  const out: ExtractedProfileCandidate[] = [];
  const obj = extractFirstJsonObject(rawText);
  if (!obj) return out;
  const listRaw = obj['fields'] ?? obj['profile'];
  if (!Array.isArray(listRaw)) return out;
  const arr = listRaw as Record<string, Object>[];
  for (let i = 0; i < arr.length; i++) {
    const item = arr[i];
    if (!item || typeof item !== 'object') continue;
    const key = typeof item['key'] === 'string' ? (item['key'] as string).trim() : '';
    const value = typeof item['value'] === 'string' ? (item['value'] as string).trim() : '';
    if (key.length > 0 && value.length > 0) {
      out.push({ key, value });
    }
  }
  return out;
}

/**
 * Parses the JSON response from the memory gatekeeper + extraction model (also supports XML fallback).
 */
export function parseMemoryExtractionResponse(rawText: string): MemoryExtractionResult {
  const fallback: MemoryExtractionResult = {
    shouldSave: false,
    summary: '未提取到需要长期记忆的稳定事实',
    memories: [],
    profile: []
  };
  let jsonStr = rawText.trim();
  const fenceStart = jsonStr.indexOf('{');
  const fenceEnd = jsonStr.lastIndexOf('}');
  if (fenceStart < 0 || fenceEnd <= fenceStart) {
    const xmlItems = parseExtractedMemoriesXmlFromTagsOnly(rawText);
    if (xmlItems.length > 0) {
      return {
        shouldSave: true,
        summary: `提取 ${xmlItems.length} 条记忆`,
        memories: xmlItems,
        profile: []
      };
    }
    return fallback;
  }
  jsonStr = jsonStr.slice(fenceStart, fenceEnd + 1);

  try {
    const parsed = JSON.parse(jsonStr) as Record<string, Object>;
    const shouldSave = parsed['shouldSave'] === true;
    const summary = typeof parsed['summary'] === 'string' && parsed['summary'].trim().length > 0
      ? parsed['summary'].trim()
      : (shouldSave ? '提取成功' : '无需记录');
    const memories: ExtractedMemoryCandidate[] = [];
    if (Array.isArray(parsed['memories'])) {
      const arr = parsed['memories'] as Record<string, Object>[];
      for (let i = 0; i < arr.length; i++) {
        const item = arr[i];
        const content = typeof item['content'] === 'string' ? item['content'].trim() : '';
        if (content.length > 0) {
          const catStr = typeof item['category'] === 'string'
            ? (item['category'] as string)
            : (typeof item['type'] === 'string' ? (item['type'] as string) : 'instruction');
          memories.push({
            category: normalizeMemoryCategory(catStr),
            content
          });
        }
      }
    }
    const profile: ExtractedProfileCandidate[] = [];
    if (Array.isArray(parsed['profile'])) {
      const arr = parsed['profile'] as Record<string, Object>[];
      for (let i = 0; i < arr.length; i++) {
        const item = arr[i];
        const key = typeof item['key'] === 'string' ? item['key'].trim() : '';
        const value = typeof item['value'] === 'string' ? item['value'].trim() : '';
        if (key.length > 0 && value.length > 0) {
          profile.push({ key, value });
        }
      }
    }
    return { shouldSave, summary, memories, profile };
  } catch (_) {
    return fallback;
  }
}

function parseExtractedMemoriesXmlFromTagsOnly(rawText: string): ExtractedMemoryCandidate[] {
  const out: ExtractedMemoryCandidate[] = [];
  const itemRe = /<item\s+type=["']([^"']+)["'][^>]*>([\s\S]*?)<\/item>/gi;
  let match = itemRe.exec(rawText);
  while (match !== null) {
    const rawType = match[1] || 'instruction';
    const rawContent = (match[2] || '').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&').trim();
    if (rawContent.length > 0) {
      out.push({
        category: normalizeMemoryCategory(rawType),
        content: rawContent
      });
    }
    match = itemRe.exec(rawText);
  }
  return out;
}

export function mergeMemoryCandidates(
  existing: MemoryEntry[],
  candidates: ExtractedMemoryCandidate[],
  conversationId?: string,
  assistantId?: string,
  source: MemorySourceKind = 'extracted',
  relatedIds?: string[]
): MemoryMergeResult {
  const next: MemoryEntry[] = existing.map((m: MemoryEntry): MemoryEntry => ({
    id: m.id,
    category: m.category,
    content: m.content,
    assistantId: m.assistantId,
    archived: m.archived,
    createdAt: normalizeMemoryTimestamp(m.createdAt),
    updatedAt: normalizeMemoryTimestamp(m.updatedAt),
    sourceConversationId: m.sourceConversationId,
    source: m.source,
    relatedIds: m.relatedIds ? m.relatedIds.slice() : undefined
  }));
  let addedCount = 0;
  let mergedCount = 0;
  const now = Date.now();

  for (let i = 0; i < candidates.length; i++) {
    const c = candidates[i];
    const clean = c.content.trim();
    if (clean.length === 0) {
      continue;
    }
    let matchedIdx = -1;
    let bestSim = 0;
    for (let j = 0; j < next.length; j++) {
      const m = next[j];
      if (m.archived || m.category !== c.category) {
        continue;
      }
      if ((m.assistantId || '') !== (assistantId || '')) {
        continue;
      }
      const sim = computeTextSimilarity(m.content, clean);
      if (sim >= 0.72 && sim > bestSim) {
        bestSim = sim;
        matchedIdx = j;
      }
    }

    if (matchedIdx >= 0) {
      const target = next[matchedIdx];
      const mergedRel = relatedIds && relatedIds.length > 0
        ? Array.from(new Set<string>([...(target.relatedIds || []), ...relatedIds]))
        : target.relatedIds;
      if (clean.length >= target.content.length && clean !== target.content) {
        next[matchedIdx] = {
          id: target.id,
          category: target.category,
          content: clean,
          assistantId: target.assistantId,
          archived: target.archived,
          createdAt: target.createdAt,
          updatedAt: now,
          sourceConversationId: conversationId ?? target.sourceConversationId,
          source: target.source || source,
          relatedIds: mergedRel
        };
      } else {
        next[matchedIdx] = {
          id: target.id,
          category: target.category,
          content: target.content,
          assistantId: target.assistantId,
          archived: target.archived,
          createdAt: target.createdAt,
          updatedAt: now,
          sourceConversationId: target.sourceConversationId,
          source: target.source || source,
          relatedIds: mergedRel
        };
      }
      mergedCount += 1;
    } else {
      next.push({
        id: nextMemId('mem'),
        category: c.category,
        content: clean,
        assistantId,
        archived: false,
        createdAt: now + i,
        updatedAt: now + i,
        sourceConversationId: conversationId,
        source,
        relatedIds: relatedIds && relatedIds.length > 0 ? relatedIds.slice() : undefined
      });
      addedCount += 1;
    }
  }

  return { entries: next, addedCount, mergedCount };
}

export function mergeProfileFields(
  existing: UserProfileField[],
  candidates: ExtractedProfileCandidate[],
  source: string = 'distilled'
): ProfileMergeResult {
  const normalizedExisting = normalizeUserProfileFields(existing);
  const next: UserProfileField[] = normalizedExisting.map((f: UserProfileField): UserProfileField => ({
    id: f.id,
    key: profileFieldKey(f),
    value: f.value,
    updatedAt: normalizeMemoryTimestamp(f.updatedAt),
    source: f.source
  }));
  let updatedCount = 0;
  const now = Date.now();

  for (let i = 0; i < candidates.length; i++) {
    const c = candidates[i];
    const cleanKey = (c.key || '').replace(/^custom\./i, '').trim();
    const cleanVal = (c.value || '').trim();
    if (!cleanKey || !cleanVal) continue;
    const kLower = cleanKey.toLowerCase();
    let idx = -1;
    for (let j = 0; j < next.length; j++) {
      if (profileFieldKey(next[j]).toLowerCase() === kLower) {
        idx = j;
        break;
      }
    }
    if (idx >= 0) {
      if (next[idx].value !== cleanVal) {
        next[idx] = {
          id: next[idx].id || profileWireKey(cleanKey),
          key: cleanKey,
          value: cleanVal,
          updatedAt: now,
          source
        };
        updatedCount += 1;
      }
    } else {
      next.push({
        id: profileWireKey(cleanKey),
        key: cleanKey,
        value: cleanVal,
        updatedAt: now,
        source
      });
      updatedCount += 1;
    }
  }

  return { fields: next, updatedCount };
}
