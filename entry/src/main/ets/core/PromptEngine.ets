import {
  ChatMessage,
  InstructionCard,
  PresetMessage,
  QuickPhrase,
  RegexRule,
  WorldBook,
  WorldBookEntry
} from './Models';

export interface PromptTemplateContext {
  userName?: string;
  assistantName?: string;
  modelName?: string;
  providerName?: string;
  conversationTitle?: string;
  now?: Date;
}

export interface ActivatedWorldBookEntries {
  beforeSystem: WorldBookEntry[];
  afterSystem: WorldBookEntry[];
  beforeLastUser: WorldBookEntry[];
  atDepth: WorldBookEntry[];
  matchedNames: string[];
}

export interface AssembledPromptInput {
  systemPrompt: string;
  messages: ChatMessage[];
  matchedWorldBookNames: string[];
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

export function formatPromptDate(d: Date): string {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`;
}

export function formatPromptTime(d: Date): string {
  return `${pad2(d.getHours())}:${pad2(d.getMinutes())}:${pad2(d.getSeconds())}`;
}

function formatWeekday(d: Date): string {
  const names = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
  const idx = d.getDay();
  return idx >= 0 && idx < names.length ? names[idx] : '';
}

/**
 * Expands {{var}} template placeholders in system prompts, preset messages, and quick phrases.
 */
export function expandPromptTemplates(text: string, ctx: PromptTemplateContext): string {
  if (!text || text.indexOf('{') < 0) {
    return text;
  }
  const now = ctx.now ? ctx.now : new Date();
  const dateStr = formatPromptDate(now);
  const timeStr = formatPromptTime(now);
  const dtStr = `${dateStr} ${pad2(now.getHours())}:${pad2(now.getMinutes())}`;
  const dtFullStr = `${dateStr} ${timeStr}`;
  const weekdayStr = formatWeekday(now);
  const userName = (ctx.userName && ctx.userName.trim().length > 0) ? ctx.userName.trim() : 'User';
  const charName = (ctx.assistantName && ctx.assistantName.trim().length > 0) ? ctx.assistantName.trim() : 'Assistant';
  const modelName = ctx.modelName ? ctx.modelName : '';
  const providerName = ctx.providerName ? ctx.providerName : '';
  const title = ctx.conversationTitle ? ctx.conversationTitle : '';
  let timezoneStr = 'Asia/Shanghai';
  try {
    const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
    if (tz) timezoneStr = tz;
  } catch (_) {}

  const lookupSingle = (k: string): string | undefined => {
    if (k === 'cur_date') return dateStr;
    if (k === 'cur_time') return timeStr;
    if (k === 'cur_datetime') return dtFullStr;
    if (k === 'model_id' || k === 'model_name') return modelName;
    if (k === 'locale') return 'zh-CN';
    if (k === 'timezone') return timezoneStr;
    if (k === 'nickname') return userName;
    if (k === 'assistant_name') return charName;
    if (k === 'system_version') return 'HarmonyOS';
    if (k === 'device_info') return 'HarmonyOS Device';
    if (k === 'battery_level') return '100%';
    return undefined;
  };

  let out = '';
  let cursor = 0;
  while (cursor < text.length) {
    const start = text.indexOf('{', cursor);
    if (start < 0) {
      out += text.slice(cursor);
      break;
    }
    if (text.startsWith('{{', start)) {
      const end = text.indexOf('}}', start + 2);
      if (end < 0) {
        out += text.slice(cursor);
        break;
      }
      out += text.slice(cursor, start);
      const key = text.slice(start + 2, end).trim().toLowerCase();
      if (key === 'date') {
        out += dateStr;
      } else if (key === 'time') {
        out += timeStr;
      } else if (key === 'datetime') {
        out += dtStr;
      } else if (key === 'weekday') {
        out += weekdayStr;
      } else if (key === 'user' || key === 'user_name' || key === 'username') {
        out += userName;
      } else if (key === 'char' || key === 'assistant' || key === 'assistant_name') {
        out += charName;
      } else if (key === 'model') {
        out += modelName;
      } else if (key === 'provider') {
        out += providerName;
      } else if (key === 'title' || key === 'conversation_title') {
        out += title;
      } else {
        out += text.slice(start, end + 2);
      }
      cursor = end + 2;
      continue;
    }
    const endSingle = text.indexOf('}', start + 1);
    const nextOpen = text.indexOf('{', start + 1);
    if (endSingle < 0 || (nextOpen >= 0 && nextOpen < endSingle)) {
      out += text.slice(cursor, start + 1);
      cursor = start + 1;
      continue;
    }
    out += text.slice(cursor, start);
    const sKey = text.slice(start + 1, endSingle).trim().toLowerCase();
    const sVal = lookupSingle(sKey);
    out += sVal !== undefined ? sVal : text.slice(start, endSingle + 1);
    cursor = endSingle + 1;
  }
  return out;
}

function sanitizeRegexFlags(flags: string): string {
  const allowed = ['g', 'i', 'm', 's', 'u'];
  let res = '';
  for (let i = 0; i < flags.length; i++) {
    const ch = flags.charAt(i);
    if (allowed.indexOf(ch) >= 0 && res.indexOf(ch) < 0) {
      res += ch;
    }
  }
  if (res.indexOf('g') < 0) {
    res = 'g' + res;
  }
  return res;
}

/**
 * Applies enabled regex replacement rules matching the target scope.
 */
export function applyRegexRules(
  text: string,
  rules: RegexRule[],
  scope: 'input' | 'output' | 'display'
): string {
  if (!text || !rules || rules.length === 0) {
    return text;
  }
  let current = text;
  for (let i = 0; i < rules.length; i++) {
    const rule = rules[i];
    if (!rule.enabled || rule.scope !== scope) {
      continue;
    }
    const pattern = rule.pattern ? rule.pattern : '';
    if (pattern.length === 0) {
      continue;
    }
    try {
      const re = new RegExp(pattern, sanitizeRegexFlags(rule.flags ? rule.flags : 'g'));
      const rep = (rule.replacement ? rule.replacement : '').replace(/\\n/g, '\n');
      current = current.replace(re, rep);
    } catch (_) {
      // Ignore malformed user regexes rather than breaking message rendering/sending.
    }
  }
  return current;
}

function entryMatchesText(entry: WorldBookEntry, scanText: string, scanLower: string): boolean {
  if (entry.alwaysActive) {
    return true;
  }
  if (!entry.keys || entry.keys.length === 0) {
    return false;
  }
  for (let i = 0; i < entry.keys.length; i++) {
    const rawKey = entry.keys[i].trim();
    if (rawKey.length === 0) {
      continue;
    }
    if (entry.useRegex) {
      try {
        const re = new RegExp(rawKey, 'i');
        if (re.test(scanText)) {
          return true;
        }
      } catch (_) {
        // Fallback to plain substring match if regex syntax is invalid.
        if (scanLower.indexOf(rawKey.toLowerCase()) >= 0) {
          return true;
        }
      }
    } else if (scanLower.indexOf(rawKey.toLowerCase()) >= 0) {
      return true;
    }
  }
  return false;
}

/**
 * Evaluates active world books against recent conversation messages and returns matched entries grouped by slot.
 */
export function activateWorldBooks(
  books: WorldBook[],
  enabledBookIds: string[] | undefined,
  conversationMessages: ChatMessage[],
  extraScanText: string = ''
): ActivatedWorldBookEntries {
  const result: ActivatedWorldBookEntries = {
    beforeSystem: [],
    afterSystem: [],
    beforeLastUser: [],
    atDepth: [],
    matchedNames: []
  };
  if (!books || books.length === 0) {
    return result;
  }

  const recentStart = conversationMessages.length > 8 ? conversationMessages.length - 8 : 0;
  const scanParts: string[] = [];
  for (let i = recentStart; i < conversationMessages.length; i++) {
    if (conversationMessages[i].text) {
      scanParts.push(conversationMessages[i].text);
    }
  }
  if (extraScanText.trim().length > 0) {
    scanParts.push(extraScanText);
  }
  const scanText = scanParts.join('\n');
  const scanLower = scanText.toLowerCase();
  const hasExplicitIds = Boolean(enabledBookIds && enabledBookIds.length > 0);

  for (let i = 0; i < books.length; i++) {
    const book = books[i];
    if (!book.enabled) {
      continue;
    }
    if (hasExplicitIds && enabledBookIds && enabledBookIds.indexOf(book.id) < 0) {
      continue;
    }
    for (let j = 0; j < book.entries.length; j++) {
      const entry = book.entries[j];
      if (!entry.enabled || entry.content.trim().length === 0) {
        continue;
      }
      if (!entryMatchesText(entry, scanText, scanLower)) {
        continue;
      }
      result.matchedNames.push(entry.name || book.name);
      if (entry.position === 'before_system') {
        result.beforeSystem.push(entry);
      } else if (entry.position === 'before_last_user') {
        result.beforeLastUser.push(entry);
      } else if (entry.position === 'at_depth') {
        result.atDepth.push(entry);
      } else {
        result.afterSystem.push(entry);
      }
    }
  }
  return result;
}

export function assembleInstructionCards(cards: InstructionCard[], activeIds: string[]): string {
  if (!cards || !activeIds || activeIds.length === 0) {
    return '';
  }
  const parts: string[] = [];
  for (let i = 0; i < cards.length; i++) {
    const c = cards[i];
    if (!c) continue;
    const rawBody = typeof c.content === 'string'
      ? c.content
      : (typeof c.prompt === 'string' ? c.prompt : '');
    const body = rawBody.trim();
    if (activeIds.indexOf(c.id) >= 0 && body.length > 0) {
      const title = typeof c.title === 'string' ? c.title.trim() : '';
      parts.push(title.length > 0 ? `[${title}]\n${body}` : body);
    }
  }
  return parts.join('\n\n');
}

function formatWorldBookGroup(entries: WorldBookEntry[]): string {
  const parts: string[] = [];
  for (let i = 0; i < entries.length; i++) {
    const e = entries[i];
    if (e.name && e.name.trim().length > 0) {
      parts.push(`[${e.name.trim()}]\n${e.content.trim()}`);
    } else {
      parts.push(e.content.trim());
    }
  }
  return parts.join('\n\n');
}

export interface BuildPromptParams {
  baseSystemPrompt: string;
  presetMessages?: PresetMessage[];
  historyMessages: ChatMessage[];
  worldBooks?: WorldBook[];
  enabledWorldBookIds?: string[];
  instructionCards?: InstructionCard[];
  activeInstructionIds?: string[];
  memoryBlock?: string;
  templateContext: PromptTemplateContext;
}

function makeInjectedMessage(id: string, role: 'user' | 'assistant' | 'system', content: string): ChatMessage {
  return {
    id,
    role: role === 'assistant' ? 'assistant' : 'user',
    text: role === 'system' ? `[Directive]\n${content}` : content,
    model: '',
    createdAt: Date.now()
  };
}

/**
 * Combines base system prompt, preset few-shot messages, world book injections, and instruction cards.
 */
export function buildAssembledPrompt(params: BuildPromptParams): AssembledPromptInput {
  const baseExpanded = expandPromptTemplates(params.baseSystemPrompt, params.templateContext);
  const activated = activateWorldBooks(
    params.worldBooks ? params.worldBooks : [],
    params.enabledWorldBookIds,
    params.historyMessages
  );

  const sysSections: string[] = [];
  if (activated.beforeSystem.length > 0) {
    sysSections.push(expandPromptTemplates(formatWorldBookGroup(activated.beforeSystem), params.templateContext));
  }
  if (baseExpanded.trim().length > 0) {
    sysSections.push(baseExpanded.trim());
  }
  if (activated.afterSystem.length > 0) {
    sysSections.push(expandPromptTemplates(formatWorldBookGroup(activated.afterSystem), params.templateContext));
  }
  const instructionsText = assembleInstructionCards(
    params.instructionCards ? params.instructionCards : [],
    params.activeInstructionIds ? params.activeInstructionIds : []
  );
  if (instructionsText.length > 0) {
    sysSections.push(expandPromptTemplates(instructionsText, params.templateContext));
  }

  const outMessages: ChatMessage[] = [];
  if (params.presetMessages && params.presetMessages.length > 0) {
    for (let i = 0; i < params.presetMessages.length; i++) {
      const pm = params.presetMessages[i];
      if (pm.content.trim().length === 0) {
        continue;
      }
      const expanded = expandPromptTemplates(pm.content, params.templateContext);
      if (pm.role === 'system') {
        sysSections.push(expanded);
      } else {
        outMessages.push(makeInjectedMessage(`preset_${pm.id}`, pm.role, expanded));
      }
    }
  }

  const histCopy: ChatMessage[] = [];
  for (let i = 0; i < params.historyMessages.length; i++) {
    histCopy.push(params.historyMessages[i]);
  }

  const firstUserIdx = histCopy.findIndex((item: ChatMessage): boolean => item.role === 'user');
  let lastUserIdx = -1;
  for (let i = histCopy.length - 1; i >= 0; i--) {
    if (histCopy[i].role === 'user') {
      lastUserIdx = i;
      break;
    }
  }

  // Insert at_depth entries counting backwards from the end of history.
  const depthInsertions: Map<number, WorldBookEntry[]> = new Map<number, WorldBookEntry[]>();
  for (let i = 0; i < activated.atDepth.length; i++) {
    const entry = activated.atDepth[i];
    const depth = entry.depth >= 0 ? entry.depth : 0;
    const insertIdx = Math.max(0, histCopy.length - depth);
    const bucket = depthInsertions.get(insertIdx);
    if (bucket) {
      bucket.push(entry);
    } else {
      depthInsertions.set(insertIdx, [entry]);
    }
  }

  for (let i = 0; i < histCopy.length; i++) {
    const atThisIdx = depthInsertions.get(i);
    if (atThisIdx) {
      for (let k = 0; k < atThisIdx.length; k++) {
        const entry = atThisIdx[k];
        outMessages.push(
          makeInjectedMessage(
            `wb_d_${entry.id}`,
            entry.role,
            expandPromptTemplates(entry.content, params.templateContext)
          )
        );
      }
    }
    if (i === lastUserIdx && activated.beforeLastUser.length > 0) {
      for (let k = 0; k < activated.beforeLastUser.length; k++) {
        const entry = activated.beforeLastUser[k];
        outMessages.push(
          makeInjectedMessage(
            `wb_u_${entry.id}`,
            entry.role,
            expandPromptTemplates(entry.content, params.templateContext)
          )
        );
      }
    }
    const item = histCopy[i];
    const memory = params.memoryBlock;
    if (i === firstUserIdx && memory) {
      outMessages.push({
        id: item.id, role: item.role, text: memory + '\n\n' + item.text, model: item.model,
        attachment: item.attachment, attachments: item.attachments, quote: item.quote, sources: item.sources,
        createdAt: item.createdAt
      });
    } else {
      outMessages.push(item);
    }
  }

  const tailInsertions = depthInsertions.get(histCopy.length);
  if (tailInsertions) {
    for (let k = 0; k < tailInsertions.length; k++) {
      const entry = tailInsertions[k];
      outMessages.push(
        makeInjectedMessage(
          `wb_t_${entry.id}`,
          entry.role,
          expandPromptTemplates(entry.content, params.templateContext)
        )
      );
    }
  }

  return {
    systemPrompt: sysSections.join('\n\n'),
    messages: outMessages,
    matchedWorldBookNames: activated.matchedNames
  };
}

/**
 * Parses SillyTavern WorldInfo or Kelivo WorldBook JSON exports.
 */
export function parseWorldBookImportJson(rawJson: string, fallbackName: string = '导入世界书'): WorldBook {
  const parsed = JSON.parse(rawJson) as Record<string, Object>;
  const nowId = `wb_${Date.now()}`;
  const entries: WorldBookEntry[] = [];

  if (Array.isArray(parsed['entries'])) {
    const arr = parsed['entries'] as Record<string, Object>[];
    for (let i = 0; i < arr.length; i++) {
      entries.push(parseSingleWorldBookEntry(arr[i], `${nowId}_e${i}`));
    }
  } else if (parsed['entries'] && typeof parsed['entries'] === 'object') {
    const obj = parsed['entries'] as Record<string, Object>;
    const objKeys = Object.keys(obj);
    for (let i = 0; i < objKeys.length; i++) {
      const item = obj[objKeys[i]] as Record<string, Object>;
      if (item && typeof item === 'object') {
        entries.push(parseSingleWorldBookEntry(item, `${nowId}_e${i}`));
      }
    }
  }

  const name = typeof parsed['name'] === 'string' && parsed['name'].trim().length > 0
    ? parsed['name'].trim()
    : fallbackName;
  const description = typeof parsed['description'] === 'string' ? parsed['description'] : '';
  return {
    id: nowId,
    name,
    description,
    enabled: true,
    entries
  };
}

function parseSingleWorldBookEntry(raw: Record<string, Object>, fallbackId: string): WorldBookEntry {
  const keysRaw = raw['keys'] ?? raw['key'];
  const keys: string[] = [];
  if (Array.isArray(keysRaw)) {
    for (let i = 0; i < keysRaw.length; i++) {
      const s = String(keysRaw[i]).trim();
      if (s.length > 0) {
        keys.push(s);
      }
    }
  } else if (typeof keysRaw === 'string') {
    const parts = keysRaw.split(',');
    for (let i = 0; i < parts.length; i++) {
      const s = parts[i].trim();
      if (s.length > 0) {
        keys.push(s);
      }
    }
  }

  const nameRaw = raw['name'] ?? raw['comment'];
  const name = typeof nameRaw === 'string' && nameRaw.trim().length > 0 ? nameRaw.trim() : (keys[0] ?? '条目');
  const content = typeof raw['content'] === 'string' ? raw['content'] : '';
  const posRaw = typeof raw['position'] === 'string' ? raw['position'] : '';
  let position: 'before_system' | 'after_system' | 'before_last_user' | 'at_depth' = 'after_system';
  if (posRaw === 'before_system' || posRaw === 'before_char') {
    position = 'before_system';
  } else if (posRaw === 'before_last_user') {
    position = 'before_last_user';
  } else if (posRaw === 'at_depth') {
    position = 'at_depth';
  }

  const roleRaw = typeof raw['role'] === 'string' ? raw['role'] : 'system';
  const role: 'system' | 'user' | 'assistant' =
    roleRaw === 'user' || roleRaw === 'assistant' ? roleRaw : 'system';
  const depth = typeof raw['depth'] === 'number' ? raw['depth'] : 1;
  const enabled = typeof raw['enabled'] === 'boolean'
    ? raw['enabled']
    : (typeof raw['disable'] === 'boolean' ? !raw['disable'] : true);
  const alwaysActive = Boolean(raw['alwaysActive'] ?? raw['constant']);
  const useRegex = Boolean(raw['useRegex']);

  return {
    id: typeof raw['id'] === 'string' ? raw['id'] : fallbackId,
    name,
    keys,
    useRegex,
    content,
    position,
    role,
    depth,
    enabled,
    alwaysActive
  };
}

export function defaultInstructionCards(): InstructionCard[] {
  return [
    {
      id: 'inst_learning_mode',
      title: '苏格拉底学习模式',
      description: '引导式提问，不直接给出完整答案，帮助深入理解原理',
      content: '当前处于学习模式。请先评估用户已掌握的部分，用启发式问题和循序渐进的提示引导用户自己推导答案；只有在用户明确要求查看完整解答时才直接揭示最终答案。',
      builtin: true
    },
    {
      id: 'inst_concise_code',
      title: '简洁代码模式',
      description: '仅输出关键代码与必要解释，减少冗长寒暄',
      content: '请直接切入核心问题，优先给出准确可运行的代码片段和关键修改点，省略开场白和重复性总结。',
      builtin: true
    },
    {
      id: 'inst_strict_cite',
      title: '严谨考证模式',
      description: '严格区分已知事实、推断与未知项，不编造结论',
      content: '请对结论保持严谨克制：明确区分已确认事实与推理假设；如果缺少依据或存在不确定性，请直接指出缺失条件，切勿猜测或编造引用。',
      builtin: true
    }
  ];
}

export function defaultQuickPhrases(): QuickPhrase[] {
  return [
    {
      id: 'qp_summarize',
      title: '总结要点',
      content: '请把以上内容提炼成 3-5 条清晰的核心要点，并列出下一步行动建议。',
      scope: 'global'
    },
    {
      id: 'qp_review',
      title: '审查问题',
      content: '请从边界条件、错误处理、性能和可维护性四个维度帮我逐条审查：',
      scope: 'global'
    },
    {
      id: 'qp_translate_zh',
      title: '译为地道中文',
      content: '请将以下内容翻译为自然流畅、术语准确的简体中文：',
      scope: 'global'
    },
    {
      id: 'qp_explain_simple',
      title: '通俗解释',
      content: '请用类比和清晰示例，向初学者通俗地解释以下概念：',
      scope: 'global'
    }
  ];
}
