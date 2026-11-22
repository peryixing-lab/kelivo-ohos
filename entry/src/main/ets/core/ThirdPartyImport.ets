import {
  ApiFamily,
  ApiKeyEntry,
  ChatMessage,
  Conversation,
  MessageVersion,
  ModelSpec,
  Persona,
  Provider,
  defaultModelSpec,
  preset
} from './Models';
import { ParsedBackupData, parseAndroidChatsJson } from './BackupCodec';

export interface ThirdPartyImportBundle {
  conversations: Conversation[];
  personas: Persona[];
  providers: Provider[];
  secretsToStore?: Record<string, string>;
  sourceName: string;
}

interface FlutterAssistantEntry {
  id?: string;
  name?: string;
  systemPrompt?: string;
  prompt?: string;
  avatar?: string;
}

interface FlutterProviderEntry {
  id?: string;
  name?: string;
  type?: string;
  baseUrl?: string;
  defaultModel?: string;
}

export function importFlutterFullArchive(
  chatsJson: string,
  assistantsJson?: string,
  providersJson?: string
): ThirdPartyImportBundle {
  const conversations = parseAndroidChatsJson(chatsJson);

  const personas: Persona[] = [];
  if (assistantsJson) {
    try {
      const list = JSON.parse(assistantsJson) as FlutterAssistantEntry[];
      if (Array.isArray(list)) {
        for (let i = 0; i < list.length; i++) {
          const a = list[i];
          if (a.id && a.name) {
            personas.push({
              id: a.id,
              name: a.name,
              prompt: a.systemPrompt || a.prompt || '',
              avatar: a.avatar
            });
          }
        }
      }
    } catch (_) {}
  }

  const providers: Provider[] = [];
  if (providersJson) {
    try {
      const pList = JSON.parse(providersJson) as FlutterProviderEntry[];
      if (Array.isArray(pList)) {
        for (let i = 0; i < pList.length; i++) {
          const p = pList[i];
          if (p.id && p.name && p.baseUrl) {
            const fam: ApiFamily = p.type === 'claude' ? 'anthropic' : p.type === 'google' ? 'gemini' : 'openai';
            providers.push(preset(p.id, p.name, fam, p.baseUrl, p.defaultModel || ''));
          }
        }
      }
    } catch (_) {}
  }

  return { conversations, personas, providers, secretsToStore: {}, sourceName: 'Kelivo (Flutter)' };
}

// ===== 2. Cherry Studio Importer (JSON + ZIP data.json) =====
interface CherryModelRef {
  id?: string;
  provider?: string;
  name?: string;
}

interface CherryAssistantSettings {
  temperature?: number;
  topP?: number;
  contextCount?: number;
  streamOutput?: boolean;
  enableMaxTokens?: boolean;
  maxTokens?: number;
}

interface CherryTopicMeta {
  id?: string;
  name?: string;
  title?: string;
  assistantId?: string;
  updatedAt?: string | number;
  createdAt?: string | number;
  messages?: CherryMessage[];
}

interface CherryAssistant {
  id?: string;
  name?: string;
  prompt?: string;
  settings?: CherryAssistantSettings;
  model?: CherryModelRef;
  topics?: CherryTopicMeta[];
}

interface CherryProviderEntry {
  id?: string;
  name?: string;
  type?: string;
  apiKey?: string;
  apiHost?: string;
  enabled?: boolean;
  models?: CherryModelRef[];
}

interface CherryBlock {
  type?: string;
  messageId?: string;
  content?: string;
  language?: string;
}

interface CherryMessage {
  id?: string;
  role?: string;
  content?: string;
  blocks?: (CherryBlock | string)[];
  modelId?: string;
  model?: CherryModelRef;
  createdAt?: string | number;
  updatedAt?: string | number;
}

interface CherryIndexedDb {
  topics?: CherryTopicMeta[];
  assistants?: CherryAssistant[];
  messages?: CherryMessage[];
  message_blocks?: CherryBlock[];
}

interface CherryPersistSlice {
  assistants?: string;
  llm?: string;
}

interface CherryAssistantsSlice {
  assistants?: CherryAssistant[];
}

interface CherryLlmSlice {
  providers?: CherryProviderEntry[];
}

interface CherryRoot {
  version?: number;
  localStorage?: Record<string, Object>;
  indexedDB?: CherryIndexedDb;
  topics?: CherryTopicMeta[];
  assistants?: CherryAssistant[];
}

function splitCherryApiKeys(raw: string): string[] {
  const parts = raw.split(/[,\n\r]/);
  const out: string[] = [];
  const seen = new Set<string>();
  for (let i = 0; i < parts.length; i++) {
    const t = parts[i].trim();
    if (t && !seen.has(t)) {
      seen.add(t);
      out.push(t);
    }
  }
  return out;
}

function normalizeCherryBaseUrl(rawHost: string, family: ApiFamily): string {
  let base = rawHost.trim();
  if (!base) {
    if (family === 'gemini') return 'https://generativelanguage.googleapis.com/v1beta';
    if (family === 'anthropic') return 'https://api.anthropic.com/v1';
    return 'https://api.openai.com/v1';
  }
  if (base.endsWith('/')) {
    return base.slice(0, base.length - 1);
  }
  const lower = base.toLowerCase();
  if (!/\/v\d([a-z0-9._-]+)?$/i.test(lower)) {
    return base + (family === 'gemini' ? '/v1beta' : '/v1');
  }
  return base;
}

export function parseCherryStudioData(rawJson: string): ParsedBackupData {
  const root = JSON.parse(rawJson) as CherryRoot;
  const secretsToStore: Record<string, string> = {};
  let secIdx = 0;
  const stageSecret = (val: string): string => {
    secIdx++;
    const ref = '__cherry_sec_' + secIdx;
    secretsToStore[ref] = val;
    return ref;
  };

  let cherryProviders: CherryProviderEntry[] = [];
  let persistAssistants: CherryAssistant[] = [];
  const persistRaw = root.localStorage ? root.localStorage['persist:cherry-studio'] : undefined;
  if (typeof persistRaw === 'string' && persistRaw.trim().length > 0) {
    try {
      const pObj = JSON.parse(persistRaw) as CherryPersistSlice;
      if (pObj.assistants) {
        const aSlice = JSON.parse(pObj.assistants) as CherryAssistantsSlice;
        if (Array.isArray(aSlice.assistants)) persistAssistants = aSlice.assistants;
      }
      if (pObj.llm) {
        const lSlice = JSON.parse(pObj.llm) as CherryLlmSlice;
        if (Array.isArray(lSlice.providers)) cherryProviders = lSlice.providers;
      }
    } catch (_) {}
  }

  // Parse Providers
  const providers: Provider[] = [];
  for (let i = 0; i < cherryProviders.length; i++) {
    const cp = cherryProviders[i];
    if (!cp || !cp.id) continue;
    const typeLower = (cp.type || '').toLowerCase();
    const family: ApiFamily = typeLower === 'anthropic' ? 'anthropic' : typeLower === 'gemini' ? 'gemini' : 'openai';
    const keys = splitCherryApiKeys(cp.apiKey || '');
    const primaryRef = keys.length > 0 ? stageSecret(keys[0]) : '';
    const pool: ApiKeyEntry[] = [];
    if (keys.length > 1) {
      for (let k = 0; k < keys.length; k++) {
        pool.push({
          id: cp.id + '-k-' + k,
          label: 'Key ' + (k + 1),
          secretRef: stageSecret(keys[k]),
          priority: k,
          usageCount: 0,
          errorCount: 0,
          disabledUntil: 0
        });
      }
    }
    const models: ModelSpec[] = [];
    if (Array.isArray(cp.models)) {
      for (let m = 0; m < cp.models.length; m++) {
        const mid = cp.models[m]?.id;
        if (mid) models.push(defaultModelSpec(mid));
      }
    }
    providers.push({
      id: cp.id,
      name: cp.name || cp.id,
      family,
      baseUrl: normalizeCherryBaseUrl(cp.apiHost || '', family),
      chatPath: family === 'openai' ? '/chat/completions' : '',
      model: models.length > 0 ? models[0].id : '',
      secretRef: primaryRef,
      models,
      apiKeys: pool,
      keyStrategy: 'round_robin',
      enabled: cp.enabled !== undefined ? cp.enabled : keys.length > 0
    });
  }

  // Parse Assistants & Topic Metadata
  const rawAssistants: CherryAssistant[] = persistAssistants.length > 0
    ? persistAssistants
    : (root.indexedDB?.assistants || root.assistants || []);
  const personas: Persona[] = [];
  const topicMetaMap = new Map<string, CherryTopicMeta>();
  const directTopics: CherryTopicMeta[] = [];

  for (let i = 0; i < rawAssistants.length; i++) {
    const a = rawAssistants[i];
    if (!a || !a.id) continue;
    personas.push({
      id: a.id,
      name: a.name || a.id,
      prompt: a.prompt || '',
      providerId: a.model?.provider,
      modelId: a.model?.id,
      streamOutput: a.settings?.streamOutput !== false,
      params: {
        temperature: typeof a.settings?.temperature === 'number' ? a.settings.temperature : undefined,
        topP: typeof a.settings?.topP === 'number' ? a.settings.topP : undefined,
        contextLimit: typeof a.settings?.contextCount === 'number' ? a.settings.contextCount : undefined,
        maxTokens: a.settings?.enableMaxTokens && typeof a.settings?.maxTokens === 'number' ? a.settings.maxTokens : undefined
      }
    });
    if (Array.isArray(a.topics)) {
      for (let j = 0; j < a.topics.length; j++) {
        const t = a.topics[j];
        if (!t || !t.id) continue;
        topicMetaMap.set(t.id, {
          id: t.id,
          name: t.name || t.title,
          assistantId: a.id,
          updatedAt: t.updatedAt,
          createdAt: t.createdAt
        });
        if (Array.isArray(t.messages)) {
          directTopics.push({
            id: t.id,
            name: t.name || t.title,
            assistantId: a.id,
            updatedAt: t.updatedAt,
            createdAt: t.createdAt,
            messages: t.messages
          });
        }
      }
    }
  }

  // Index Cherry Studio message_blocks by messageId
  const blockTextByMsgId = new Map<string, string>();
  const blockThinkByMsgId = new Map<string, string>();
  const msgBlocks = root.indexedDB?.message_blocks || [];
  for (let i = 0; i < msgBlocks.length; i++) {
    const b = msgBlocks[i];
    if (!b || !b.messageId) continue;
    const mid = b.messageId;
    const bType = (b.type || '').toLowerCase();
    const content = b.content || '';
    if (!content) continue;
    if (bType === 'thinking') {
      const prev = blockThinkByMsgId.get(mid) || '';
      blockThinkByMsgId.set(mid, prev ? prev + '\n' + content : content);
    } else if (bType === 'code') {
      const fenced = '```' + (b.language || '') + '\n' + content + '\n```';
      const prev = blockTextByMsgId.get(mid) || '';
      blockTextByMsgId.set(mid, prev ? prev + '\n' + fenced : fenced);
    } else if (bType === 'error') {
      const errBlock = '> Error\n> ' + content.replace(/\n/g, '\n> ');
      const prev = blockTextByMsgId.get(mid) || '';
      blockTextByMsgId.set(mid, prev ? prev + '\n' + errBlock : errBlock);
    } else if (bType === 'main_text') {
      const prev = blockTextByMsgId.get(mid) || '';
      blockTextByMsgId.set(mid, prev ? prev + '\n' + content : content);
    }
  }

  const dbTopics = root.indexedDB?.topics || root.topics || [];
  const topicList: CherryTopicMeta[] = dbTopics.length > 0 ? dbTopics : directTopics;
  const conversations: Conversation[] = [];

  for (let i = 0; i < topicList.length; i++) {
    const t = topicList[i];
    if (!t || !t.id || !Array.isArray(t.messages)) continue;
    const meta = topicMetaMap.get(t.id);
    const msgs: ChatMessage[] = [];
    for (let j = 0; j < t.messages.length; j++) {
      const m = t.messages[j];
      if (!m || (m.role !== 'user' && m.role !== 'assistant')) continue;
      const mid = m.id || (t.id + '-m-' + j);
      let text = m.content || '';
      let reasoning = blockThinkByMsgId.get(mid) || '';
      if (!text) {
        const fromBlock = blockTextByMsgId.get(mid);
        if (fromBlock) text = fromBlock;
      }
      if (!text && Array.isArray(m.blocks)) {
        const parts: string[] = [];
        const thParts: string[] = [];
        for (let b = 0; b < m.blocks.length; b++) {
          const blk = m.blocks[b];
          if (typeof blk === 'string') continue;
          if (blk.type === 'thinking' && blk.content) thParts.push(blk.content);
          else if (blk.content) parts.push(blk.content);
        }
        text = parts.join('\n');
        if (!reasoning && thParts.length > 0) reasoning = thParts.join('\n');
      }
      const createdMs = typeof m.createdAt === 'number' ? m.createdAt
        : (typeof m.createdAt === 'string' ? (Date.parse(m.createdAt) || Date.now()) : Date.now());
      msgs.push({
        id: mid,
        role: m.role === 'assistant' ? 'assistant' : 'user',
        text,
        model: m.modelId || m.model?.id || '',
        reasoning,
        createdAt: createdMs
      });
    }
    const updRaw = t.updatedAt || meta?.updatedAt;
    const updMs = typeof updRaw === 'number' ? updRaw : (updRaw ? (Date.parse(updRaw) || Date.now()) : Date.now());
    conversations.push({
      id: t.id,
      title: meta?.name || t.name || t.title || 'Cherry 导入对话',
      updated: updMs,
      messages: msgs,
      personaId: t.assistantId || meta?.assistantId || 'default'
    });
  }

  if (!conversations.length && !personas.length && !providers.length) {
    throw new Error('未识别到 Cherry Studio 对话、助手或供应商数据');
  }

  return {
    sourceName: 'Cherry Studio',
    conversations,
    personas,
    providers,
    secretsToStore
  };
}

export function importCherryStudioJson(rawJson: string): ThirdPartyImportBundle {
  const parsed = parseCherryStudioData(rawJson);
  return {
    conversations: parsed.conversations || [],
    personas: parsed.personas || [],
    providers: parsed.providers || [],
    secretsToStore: parsed.secretsToStore,
    sourceName: parsed.sourceName
  };
}

// ===== 3. Chatbox Importer (Legacy JSON, Session-* Export JSON, and v2 ZIP) =====
interface ChatboxContentPart {
  type?: string;
  text?: string;
}

interface ChatboxMsg {
  id?: string;
  role?: string;
  content?: string;
  contentParts?: ChatboxContentPart[];
  reasoningContent?: string;
  model?: string;
  aiProvider?: string;
  timestamp?: number | string;
  tokenCount?: number;
  tokensUsed?: number;
}

interface ChatboxThread {
  id?: string;
  name?: string;
  createdAt?: number;
  messages?: ChatboxMsg[];
}

interface ChatboxSessionSettings {
  provider?: string;
  modelId?: string;
  temperature?: number;
  topP?: number;
  maxTokens?: number;
  stream?: boolean;
  maxContextMessageCount?: number;
}

interface ChatboxSession {
  id?: string;
  name?: string;
  picUrl?: string;
  type?: string;
  messages?: ChatboxMsg[];
  threads?: ChatboxThread[];
  threadName?: string;
  starred?: boolean;
  settings?: ChatboxSessionSettings;
}

interface ChatboxModelInfo {
  modelId?: string;
}

interface ChatboxProviderCfg {
  apiKey?: string;
  apiHost?: string;
  apiPath?: string;
  endpoint?: string;
  models?: ChatboxModelInfo[];
}

interface ChatboxCopilot {
  id?: string;
  name?: string;
  prompt?: string;
  picUrl?: string;
}

interface ChatboxSettingsObj {
  providers?: Record<string, ChatboxProviderCfg>;
}

interface ChatboxRoot {
  settings?: ChatboxSettingsObj;
  myCopilots?: ChatboxCopilot[];
  chatSessions?: ChatboxSession[];
  sessions?: ChatboxSession[];
}

interface ChatboxExtractedParts {
  text: string;
  reasoning: string;
}

interface ChatGptAuthor {
  role?: string;
}

function classifyChatboxProviderFamily(key: string): ApiFamily {
  const k = key.toLowerCase();
  if (k.indexOf('claude') >= 0 || k.indexOf('anthropic') >= 0) return 'anthropic';
  if (k.indexOf('gemini') >= 0 || k.indexOf('google') >= 0) return 'gemini';
  return 'openai';
}

function defaultChatboxHost(family: ApiFamily): string {
  if (family === 'anthropic') return 'https://api.anthropic.com/v1';
  if (family === 'gemini') return 'https://generativelanguage.googleapis.com/v1beta';
  return 'https://api.openai.com/v1';
}

function extractChatboxMessageParts(m: ChatboxMsg): ChatboxExtractedParts {
  let text = m.content || '';
  let reasoning = m.reasoningContent || '';
  if (Array.isArray(m.contentParts) && m.contentParts.length > 0) {
    const tParts: string[] = [];
    const rParts: string[] = [];
    for (let i = 0; i < m.contentParts.length; i++) {
      const p = m.contentParts[i];
      const partText = p.text || '';
      if (!partText) continue;
      if (p.type === 'reasoning') rParts.push(partText);
      else tParts.push(partText);
    }
    if (!text && tParts.length > 0) text = tParts.join('\n');
    if (!reasoning && rParts.length > 0) reasoning = rParts.join('\n');
  }
  return { text, reasoning };
}

function convertChatboxMessages(rawList: ChatboxMsg[], convId: string, fallbackBaseMs: number): ChatMessage[] {
  const out: ChatMessage[] = [];
  let consumedSystem = false;
  for (let i = 0; i < rawList.length; i++) {
    const m = rawList[i];
    if (!m) continue;
    const extracted = extractChatboxMessageParts(m);
    if (m.role === 'system') {
      if (!consumedSystem && extracted.text.trim().length > 0) {
        consumedSystem = true;
        continue;
      }
      continue;
    }
    if (m.role !== 'user' && m.role !== 'assistant') continue;
    const ts = typeof m.timestamp === 'number' ? m.timestamp
      : (typeof m.timestamp === 'string' ? (Date.parse(m.timestamp) || (fallbackBaseMs + i)) : (fallbackBaseMs + i));
    const totalTokens = typeof m.tokenCount === 'number' ? m.tokenCount
      : (typeof m.tokensUsed === 'number' ? m.tokensUsed : undefined);
    out.push({
      id: m.id || (convId + '-cb-' + i),
      role: m.role === 'assistant' ? 'assistant' : 'user',
      text: extracted.text,
      model: m.model || '',
      reasoning: extracted.reasoning,
      createdAt: ts,
      usage: totalTokens !== undefined ? {
        promptTokens: 0,
        completionTokens: totalTokens,
        cachedTokens: 0,
        totalTokens,
        durationMs: 0
      } : undefined
    });
  }
  return out;
}

export function assembleChatboxZipV2Json(filesMap: Record<string, string>): string {
  const manifestRaw = filesMap['manifest.json'];
  if (!manifestRaw) throw new Error('Chatbox ZIP 中缺少 manifest.json');
  const manifest = JSON.parse(manifestRaw) as Record<string, Object>;
  const root: Record<string, Object> = {};
  if (manifest['exportedAt']) root['__exported_at'] = manifest['exportedAt'];

  const data = (manifest['data'] || {}) as Record<string, Object>;
  const settingsDesc = data['settings'] as Record<string, Object> | undefined;
  const settingsPath = settingsDesc && typeof settingsDesc['path'] === 'string' ? (settingsDesc['path'] as string) : 'settings.json';
  if (filesMap[settingsPath]) {
    root['settings'] = JSON.parse(filesMap[settingsPath]) as Object;
  }

  const copilotsDesc = data['copilots'] as Record<string, Object> | undefined;
  const copilotsPath = copilotsDesc && typeof copilotsDesc['path'] === 'string' ? (copilotsDesc['path'] as string) : 'copilots.json';
  if (filesMap[copilotsPath]) {
    root['myCopilots'] = JSON.parse(filesMap[copilotsPath]) as Object;
  }

  const sessionsDescList = Array.isArray(manifest['sessions']) ? (manifest['sessions'] as Record<string, Object>[]) : [];
  const sessionList: Record<string, Object>[] = [];
  for (let i = 0; i < sessionsDescList.length; i++) {
    const desc = sessionsDescList[i];
    const sid = String(desc['id'] || '');
    const spath = String(desc['path'] || '');
    if (!sid || !spath || !filesMap[spath]) continue;
    const sess = JSON.parse(filesMap[spath]) as Record<string, Object>;
    root['session:' + sid] = sess;
    const listEntry: Record<string, Object> = {};
    listEntry['id'] = sid;
    listEntry['name'] = String(desc['name'] || sess['name'] || sid);
    listEntry['starred'] = desc['starred'] === true || sess['starred'] === true;
    sessionList.push(listEntry);
  }
  root['chat-sessions-list'] = sessionList;
  return JSON.stringify(root);
}

export function parseChatboxData(rawJson: string): ParsedBackupData {
  const rawRecord = JSON.parse(rawJson) as Record<string, Object>;
  const root = JSON.parse(rawJson.replace(/"chat-sessions"/g, '"chatSessions"')) as ChatboxRoot;
  const secretsToStore: Record<string, string> = {};
  let secIdx = 0;
  const stageSecret = (val: string): string => {
    secIdx++;
    const ref = '__cb_sec_' + secIdx;
    secretsToStore[ref] = val;
    return ref;
  };

  // 1. Providers
  const providers: Provider[] = [];
  const rawProviders = root.settings?.providers;
  if (rawProviders) {
    const keys = Object.keys(rawProviders);
    for (let i = 0; i < keys.length; i++) {
      const k = keys[i].trim();
      if (!k || k === 'chatbox-ai') continue;
      const cfg = rawProviders[keys[i]];
      if (!cfg) continue;
      const family = classifyChatboxProviderFamily(k);
      const apiKey = (cfg.apiKey || '').trim();
      const baseRaw = (cfg.apiHost || cfg.endpoint || '').trim().replace(/\/+$/, '');
      const models: ModelSpec[] = [];
      if (Array.isArray(cfg.models)) {
        for (let m = 0; m < cfg.models.length; m++) {
          const mid = (cfg.models[m]?.modelId || '').trim();
          if (mid) models.push(defaultModelSpec(mid));
        }
      }
      providers.push({
        id: k,
        name: k,
        family,
        baseUrl: baseRaw || defaultChatboxHost(family),
        chatPath: family === 'openai' ? (cfg.apiPath || '') : '',
        model: models.length > 0 ? models[0].id : '',
        secretRef: apiKey ? stageSecret(apiKey) : '',
        models,
        apiKeys: [],
        keyStrategy: 'round_robin',
        enabled: apiKey.length > 0
      });
    }
  }

  const rawExported = rawRecord['__exported_at'];
  const exportedMs = typeof rawExported === 'string' && rawExported ? (Date.parse(rawExported) || Date.now()) : Date.now();
  const personas: Persona[] = [];
  const personaSeen = new Set<string>();
  const conversations: Conversation[] = [];

  // 2A. Modern Chatbox format: chat-sessions-list + session:<id>
  const metaListRaw = rawRecord['chat-sessions-list'];
  const metaList = Array.isArray(metaListRaw) ? (metaListRaw as ChatboxSession[]) : undefined;
  if (Array.isArray(metaList) && metaList.length > 0) {
    for (let i = 0; i < metaList.length; i++) {
      const meta = metaList[i];
      const sid = (meta.id || '').trim();
      if (!sid) continue;
      const sessObj = rawRecord['session:' + sid] as ChatboxSession | undefined;
      const name = meta.name || sessObj?.name || sid;
      const starred = meta.starred === true || sessObj?.starred === true;

      let sysPrompt = '';
      const sessMsgs = sessObj?.messages || [];
      for (let m = 0; m < sessMsgs.length; m++) {
        if (sessMsgs[m]?.role === 'system') {
          sysPrompt = extractChatboxMessageParts(sessMsgs[m]).text;
          break;
        }
      }

      if (!personaSeen.has(sid)) {
        personaSeen.add(sid);
        const st = sessObj?.settings;
        const provId = st?.provider && st.provider !== 'chatbox-ai' ? st.provider : undefined;
        personas.push({
          id: sid,
          name,
          prompt: sysPrompt,
          providerId: provId,
          modelId: provId && st?.modelId ? st.modelId : undefined,
          streamOutput: st?.stream !== false,
          params: {
            temperature: typeof st?.temperature === 'number' ? st.temperature : undefined,
            topP: typeof st?.topP === 'number' ? st.topP : undefined,
            maxTokens: typeof st?.maxTokens === 'number' ? st.maxTokens : undefined,
            contextLimit: typeof st?.maxContextMessageCount === 'number' ? st.maxContextMessageCount : undefined
          }
        });
      }

      const threads = sessObj?.threads || [];
      const effectiveThreads: ChatboxThread[] = [];
      if (threads.length === 0) {
        effectiveThreads.push({
          id: 'chatbox_default_' + sid,
          name,
          messages: sessMsgs
        });
      } else {
        for (let t = 0; t < threads.length; t++) effectiveThreads.push(threads[t]);
        // Include current session messages if not already duplicated in threads
        const currIds: string[] = [];
        for (let m = 0; m < sessMsgs.length; m++) {
          if (sessMsgs[m]?.id) currIds.push(sessMsgs[m].id!);
        }
        if (currIds.length > 0) {
          let dup = false;
          for (let t = 0; t < threads.length; t++) {
            const tm = threads[t].messages || [];
            if (tm.length === sessMsgs.length && tm.length > 0 && tm[0].id === sessMsgs[0].id) {
              dup = true;
              break;
            }
          }
          if (!dup) {
            effectiveThreads.push({
              id: 'chatbox_current_' + sid,
              name: sessObj?.threadName || name,
              messages: sessMsgs
            });
          }
        }
      }

      for (let t = 0; t < effectiveThreads.length; t++) {
        const th = effectiveThreads[t];
        const tid = (th.id || (sid + '-t-' + t)).trim();
        const msgs = convertChatboxMessages(th.messages || [], tid, exportedMs);
        const updated = msgs.length > 0 && msgs[msgs.length - 1].createdAt
          ? (msgs[msgs.length - 1].createdAt!)
          : (th.createdAt || (exportedMs - i * 1000));
        conversations.push({
          id: tid,
          title: th.name || name,
          updated,
          pinned: starred,
          messages: msgs,
          personaId: sid
        });
      }
    }
  } else {
    // 2B. Legacy Chatbox format: chat-sessions / sessions array
    const sessions = root.chatSessions || root.sessions || [];
    if (!Array.isArray(sessions) || (!sessions.length && !providers.length)) {
      throw new Error('未识别到 Chatbox 备份数据（缺少 chat-sessions-list 或 settings.providers）');
    }
    for (let i = 0; i < sessions.length; i++) {
      const s = sessions[i];
      if (!s.id || !Array.isArray(s.messages)) continue;
      const msgs = convertChatboxMessages(s.messages, s.id, exportedMs);
      conversations.push({
        id: s.id,
        title: s.name || 'Chatbox 导入对话',
        updated: Date.now() - i * 1000,
        pinned: s.starred === true,
        messages: msgs,
        personaId: 'default'
      });
    }
  }

  // 3. Copilots -> Assistants
  if (Array.isArray(root.myCopilots)) {
    for (let i = 0; i < root.myCopilots.length; i++) {
      const cp = root.myCopilots[i];
      if (!cp || !cp.id || personaSeen.has(cp.id)) continue;
      personaSeen.add(cp.id);
      personas.push({
        id: cp.id,
        name: cp.name || cp.id,
        prompt: cp.prompt || '',
        avatar: cp.picUrl
      });
    }
  }

  return {
    sourceName: 'Chatbox',
    conversations,
    personas,
    providers,
    secretsToStore
  };
}

export function importChatboxJson(rawJson: string): ThirdPartyImportBundle {
  const parsed = parseChatboxData(rawJson);
  return {
    conversations: parsed.conversations || [],
    personas: parsed.personas || [],
    providers: parsed.providers || [],
    secretsToStore: parsed.secretsToStore,
    sourceName: parsed.sourceName
  };
}

// ===== 4. Generic ChatGPT / Claude / Universal Detector =====
interface ChatGptContent {
  parts?: Object[];
}
interface ChatGptMsg {
  author?: ChatGptAuthor;
  content?: ChatGptContent;
  create_time?: number;
}
interface ChatGptNode {
  id?: string;
  message?: ChatGptMsg;
  parent?: string;
  children?: string[];
}
interface ChatGptConv {
  id?: string;
  title?: string;
  create_time?: number;
  update_time?: number;
  mapping?: Record<string, ChatGptNode>;
  current_node?: string;
}

function tryImportChatGptJson(rawJson: string): ParsedBackupData | undefined {
  try {
    const arr = JSON.parse(rawJson) as ChatGptConv[];
    if (!Array.isArray(arr) || !arr.length || !arr[0].mapping) return undefined;
    const conversations: Conversation[] = [];
    for (let i = 0; i < arr.length; i++) {
      const item = arr[i];
      if (!item.mapping) continue;
      const chain: ChatGptNode[] = [];
      let cursor = item.current_node;
      const guard = new Set<string>();
      while (cursor && !guard.has(cursor)) {
        guard.add(cursor);
        const node = item.mapping[cursor];
        if (!node) break;
        chain.push(node);
        cursor = node.parent;
      }
      chain.reverse();
      const msgs: ChatMessage[] = [];
      for (let j = 0; j < chain.length; j++) {
        const msg = chain[j].message;
        const role = msg?.author?.role;
        if (role !== 'user' && role !== 'assistant') continue;
        const parts = msg?.content?.parts || [];
        const textParts: string[] = [];
        for (let k = 0; k < parts.length; k++) {
          if (typeof parts[k] === 'string') textParts.push(parts[k] as string);
        }
        const txt = textParts.join('\n').trim();
        if (!txt) continue;
        msgs.push({
          id: (item.id || ('gpt-' + i)) + '-m-' + j,
          role: role === 'assistant' ? 'assistant' : 'user',
          text: txt,
          model: '',
          createdAt: msg?.create_time ? Math.round(msg.create_time * 1000) : Date.now()
        });
      }
      if (msgs.length > 0) {
        conversations.push({
          id: item.id || ('chatgpt-' + i),
          title: item.title || 'ChatGPT 导入对话',
          updated: item.update_time ? Math.round(item.update_time * 1000) : Date.now(),
          messages: msgs,
          personaId: 'default'
        });
      }
    }
    return { sourceName: 'ChatGPT', conversations, secretsToStore: {} };
  } catch (_) {
    return undefined;
  }
}

export function detectAndParseThirdPartyJson(rawJson: string): ParsedBackupData {
  const trimmed = rawJson.trim();
  if (trimmed.includes('"chat-sessions-list"') || trimmed.includes('"chat-sessions"') || trimmed.includes('"sessions"')) {
    return parseChatboxData(trimmed);
  }
  if (trimmed.includes('"indexedDB"') || trimmed.includes('"persist:cherry-studio"') || trimmed.includes('"topics"')) {
    return parseCherryStudioData(trimmed);
  }
  if (trimmed.startsWith('[')) {
    const gpt = tryImportChatGptJson(trimmed);
    if (gpt) return gpt;
  }
  const bundle = importFlutterFullArchive(trimmed);
  return {
    sourceName: bundle.sourceName,
    conversations: bundle.conversations,
    personas: bundle.personas,
    providers: bundle.providers,
    secretsToStore: {}
  };
}

export function detectAndImportThirdPartyJson(rawJson: string): ThirdPartyImportBundle {
  const parsed = detectAndParseThirdPartyJson(rawJson);
  return {
    conversations: parsed.conversations || [],
    personas: parsed.personas || [],
    providers: parsed.providers || [],
    secretsToStore: parsed.secretsToStore,
    sourceName: parsed.sourceName
  };
}

export function mergeImportedProviders(existing: Provider[], incoming: Provider[]): Provider[] {
  const seen = new Set<string>(existing.map((p: Provider): string => p.id));
  const merged = existing.slice();
  for (let i = 0; i < incoming.length; i++) {
    const p = incoming[i];
    if (!seen.has(p.id)) {
      if (p.model && (!p.models || !p.models.length)) p.models = [defaultModelSpec(p.model)];
      merged.push(p);
      seen.add(p.id);
    }
  }
  return merged;
}
