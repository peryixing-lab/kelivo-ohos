import {
  ApiFamily,
  ApiKeyEntry,
  AppearanceConfig,
  AsrConfig,
  ChatMessage,
  Conversation,
  EnvVar,
  GenerationParams,
  InstructionCard,
  LocalWorkspace,
  McpServerConfig,
  MemoryEntry,
  MemoryPromptTemplates,
  MemorySettings,
  MemorySourceKind,
  MemoryWriteScope,
  MessageVersion,
  ModelDefaults,
  ModelSpec,
  Persona,
  Provider,
  ProxyConfig,
  QuickPhrase,
  ReasoningEffort,
  ScheduledTask,
  SearchServiceConfig,
  SkillRecord,
  SystemSettings,
  ToolSchemaOverride,
  TtsConfig,
  UserProfileField,
  Workspace,
  WorldBook,
  BackupScopeConfig,
  defaultBackupScope,
  defaultModelSpec,
  normalizeAppearanceConfig,
  normalizeBackupScope,
  normalizeInstructionCards,
  normalizeProxyConfig,
  normalizeProxyType,
  normalizeQuickPhrases,
  normalizeWorldBooks
} from './Models';
import {
  memoryTypeName,
  normalizeMemoryCategory,
  normalizeMemoryEntries,
  normalizeMemorySettings,
  normalizeMemoryTimestamp,
  normalizeUserProfileFields,
  profileWireKey
} from './MemoryLogic';

export interface ParsedBackupData {
  sourceName: string;
  sourceScope?: BackupScopeConfig;
  conversations?: Conversation[];
  providers?: Provider[];
  personas?: Persona[];
  mcpServers?: McpServerConfig[];
  mcpEndpoint?: string;
  searchServices?: SearchServiceConfig[];
  activeSearchId?: string;
  globalProxy?: ProxyConfig;
  memories?: MemoryEntry[];
  userProfile?: UserProfileField[];
  memorySettings?: MemorySettings;
  worldBooks?: WorldBook[];
  quickPhrases?: QuickPhrase[];
  instructionCards?: InstructionCard[];
  activeInstructionIds?: string[];
  skills?: SkillRecord[];
  workspaces?: LocalWorkspace[];
  envVars?: EnvVar[];
  scheduledTasks?: ScheduledTask[];
  tts?: TtsConfig;
  asr?: AsrConfig;
  generationParams?: GenerationParams;
  modelDefaults?: ModelDefaults;
  appearance?: AppearanceConfig;
  systemSettings?: SystemSettings;
  toolOverrides?: ToolSchemaOverride[];
  favoriteModels?: string[];
  userName?: string;
  activeProvider?: string;
  secretsToStore: Record<string, string>;
}

export interface RestoreStats {
  providers: number;
  assistants: number;
  conversations: number;
  messages: number;
  files: number;
}

export interface ApplyRestoreOutput {
  workspace: Workspace;
  stats: RestoreStats;
  secretsToStore: Record<string, string>;
  summary: string;
}

interface HarmonyBackupEnvelopeV2 {
  format: string;
  version: number;
  exportedAt: number;
  scope?: Partial<BackupScopeConfig>;
  secrets?: Record<string, string>;
  workspace?: Workspace;
  // Legacy v2 fields compatibility
  conversations?: Conversation[];
  providers?: Provider[];
  personas?: Persona[];
  workspaceMetaJson?: string;
}

interface AndroidConversationJson {
  id?: string;
  title?: string;
  createdAt?: string;
  updatedAt?: string;
  messageIds?: string[];
  isPinned?: boolean;
  mcpServerIds?: string[];
  assistantId?: string | null;
  truncateIndex?: number;
  versionSelections?: Record<string, number>;
  chatSuggestions?: string[];
  chatModelProvider?: string | null;
  chatModelId?: string | null;
}

interface AndroidMessagePartJson {
  kind?: string;
  payload?: string;
}

interface AndroidMessageJson {
  id?: string;
  conversationId?: string;
  role?: string;
  content?: string;
  parts?: AndroidMessagePartJson[];
  timestamp?: string;
  createdAt?: string;
  modelId?: string | null;
  providerId?: string | null;
  reasoningText?: string | null;
  translation?: string | null;
  groupId?: string | null;
  version?: number;
  totalTokens?: number | null;
  promptTokens?: number | null;
  completionTokens?: number | null;
  cachedTokens?: number | null;
  durationMs?: number | null;
}

interface AndroidChatsRoot {
  version?: number;
  conversations?: AndroidConversationJson[];
  messages?: AndroidMessageJson[];
}

interface AndroidApiKeyJson {
  id?: string;
  key?: string;
  name?: string;
  label?: string;
  priority?: number;
  isEnabled?: boolean;
  enabled?: boolean;
}

interface AndroidProviderJson {
  id?: string;
  enabled?: boolean;
  name?: string;
  apiKey?: string;
  baseUrl?: string;
  providerType?: string;
  chatPath?: string | null;
  useResponseApi?: boolean | null;
  vertexAI?: boolean | null;
  models?: Object[];
  proxyEnabled?: boolean;
  proxyType?: string;
  proxyHost?: string;
  proxyPort?: string;
  proxyUsername?: string;
  proxyPassword?: string;
  multiKeyEnabled?: boolean;
  apiKeys?: AndroidApiKeyJson[];
}

interface AndroidReasoningJson {
  level: string;
  budgetTokens?: number | null;
}

interface AndroidLegacyMemoryJson {
  id: number;
  assistantId: string;
  content: string;
}

interface AndroidAssistantJson {
  id?: string;
  name?: string;
  avatar?: string | null;
  useAssistantAvatar?: boolean;
  useAssistantName?: boolean;
  chatModelProvider?: string | null;
  chatModelId?: string | null;
  temperature?: number | null;
  topP?: number | null;
  contextMessageSize?: number;
  limitContextMessages?: boolean;
  streamOutput?: boolean;
  maxTokens?: number | null;
  reasoning?: AndroidReasoningJson | string | null;
  systemPrompt?: string;
  prompt?: string;
  allowConversationSystemPrompt?: boolean;
  allowConversationPromptInjection?: boolean;
  appendCurrentTimeToUserMessage?: boolean;
  useGradientBackground?: boolean;
  localToolIds?: string[];
  skillIds?: string[] | null;
  defaultWorkspaceId?: string | null;
  mcpServerIds?: string[];
  enableMemory?: boolean;
  autoOrganizeMemory?: boolean;
  memoryOrganizeEveryNTurns?: number;
  memoryFullInjectionTypes?: string[];
  memorySmartAddMode?: string;
  memoryWriteScope?: MemoryWriteScope;
  allowPastConversationRecall?: boolean;
  enableRecentChatsReference?: boolean;
  generateConversationSummary?: boolean;
  recentChatsSummaryMessageCount?: number;
}

interface AndroidMcpJson {
  id?: string;
  name?: string;
  type?: string;
  transport?: string;
  url?: string;
  endpoint?: string;
  enabled?: boolean;
  bearerToken?: string;
  disabledTools?: string[];
  autoApproveTools?: string[];
  headers?: Record<string, string>;
  customHeaders?: Record<string, string> | Object[];
}

interface AndroidEnvVarJson {
  id?: string;
  name?: string;
  value?: string;
  note?: string;
}

interface AndroidSearchJson {
  id?: string;
  kind?: string;
  type?: string;
  name?: string;
  endpoint?: string;
  url?: string;
  apiKey?: string;
  apiKeys?: AndroidApiKeyJson[];
  enabled?: boolean;
  maxResults?: number;
}

interface AndroidSpeechJson {
  id?: string;
  kind?: string;
  engine?: string;
  endpoint?: string;
  baseUrl?: string;
  apiKey?: string;
  model?: string;
  voice?: string;
  speed?: number;
  language?: string;
  region?: string;
}

interface AndroidMemoryJson {
  id?: string;
  scope?: string;
  assistantId?: string;
  type?: string;
  category?: string;
  status?: string;
  content?: string;
  source?: string;
  relatedIds?: string[];
  createdAt?: string | number;
  updatedAt?: string | number;
}

interface AndroidProfileJson {
  id?: string;
  key?: string;
  value?: string;
  source?: string;
  updatedAt?: string | number;
}

interface AndroidSelectedModel {
  providerId?: string;
  modelId?: string;
}

function addRef(set: Set<string>, ref?: string): void {
  if (ref && ref.trim().length > 0) set.add(ref.trim());
}

export function collectSecretRefsForScope(ws: Workspace, rawScope?: BackupScopeConfig): string[] {
  const scope = normalizeBackupScope(rawScope);
  const refs = new Set<string>();
  if (scope.providers) {
    for (let i = 0; i < ws.providers.length; i++) {
      const p = ws.providers[i];
      addRef(refs, p.secretRef);
      if (p.proxy) addRef(refs, p.proxy.passwordRef);
      if (p.oauth) {
        addRef(refs, p.oauth.accessTokenRef);
        addRef(refs, p.oauth.refreshTokenRef);
      }
      if (p.apiKeys) {
        for (let k = 0; k < p.apiKeys.length; k++) {
          addRef(refs, p.apiKeys[k].secretRef);
        }
      }
    }
  }
  if (scope.mcp && ws.mcpServers) {
    for (let i = 0; i < ws.mcpServers.length; i++) {
      addRef(refs, ws.mcpServers[i].bearerSecretRef);
      addRef(refs, ws.mcpServers[i].oauthAccessTokenRef);
    }
  }
  if (scope.search) {
    if (ws.search) addRef(refs, ws.search.secretRef);
    if (ws.searchServices) {
      for (let i = 0; i < ws.searchServices.length; i++) {
        const s = ws.searchServices[i];
        for (let k = 0; k < s.apiKeys.length; k++) {
          addRef(refs, s.apiKeys[k].secretRef);
        }
      }
    }
  }
  if (scope.speech) {
    if (ws.tts) addRef(refs, ws.tts.secretRef);
    if (ws.asr) addRef(refs, ws.asr.secretRef);
  }
  if (scope.envVars && ws.envVars) {
    for (let i = 0; i < ws.envVars.length; i++) {
      addRef(refs, ws.envVars[i].secretRef);
    }
  }
  if (scope.settings && ws.globalProxy) {
    addRef(refs, ws.globalProxy.passwordRef);
  }
  return Array.from(refs);
}

function stripConversationAttachments(chats: Conversation[], keepAttachments: boolean): Conversation[] {
  const out: Conversation[] = [];
  for (let i = 0; i < chats.length; i++) {
    const c = chats[i];
    if (c.ephemeral) continue;
    const msgs: ChatMessage[] = [];
    for (let j = 0; j < c.messages.length; j++) {
      const m = c.messages[j];
      msgs.push({
        id: m.id,
        role: m.role,
        text: m.text,
        model: m.model,
        attachment: keepAttachments ? m.attachment : undefined,
        attachments: keepAttachments ? m.attachments : undefined,
        reasoning: m.reasoning,
        sources: m.sources,
        createdAt: m.createdAt,
        usage: m.usage,
        reasoningDurationMs: m.reasoningDurationMs,
        toolCalls: m.toolCalls,
        generatedImages: keepAttachments ? m.generatedImages : undefined,
        quote: m.quote,
        translation: m.translation,
        versions: m.versions,
        activeVersion: m.activeVersion,
        isSummary: m.isSummary,
        compressedCount: m.compressedCount,
        compressionSnapshot: m.compressionSnapshot
      });
    }
    out.push({
      id: c.id,
      title: c.title,
      updated: c.updated,
      pinned: c.pinned,
      messages: msgs,
      personaId: c.personaId,
      contextStartIndex: c.contextStartIndex,
      memoryOrganizedThrough: c.memoryOrganizedThrough,
      overrideProviderId: c.overrideProviderId,
      overrideModel: c.overrideModel,
      overridePrompt: c.overridePrompt,
      enabledMcpIds: c.enabledMcpIds,
      enabledSkillIds: c.enabledSkillIds,
      workspaceId: c.workspaceId,
      toolPermissionMode: c.toolPermissionMode,
      suggestions: c.suggestions
    });
  }
  return out;
}

export function buildHarmonyBackupJson(
  ws: Workspace,
  rawScope: BackupScopeConfig,
  secrets: Record<string, string>,
  hydratedConversations?: Conversation[]
): string {
  const scope = normalizeBackupScope(rawScope);
  const srcChats = hydratedConversations || ws.conversations;
  const scopedWs: Workspace = {
    version: ws.version,
    providers: scope.providers ? ws.providers : [],
    personas: scope.assistants ? ws.personas : [],
    conversations: scope.chats ? stripConversationAttachments(srcChats, scope.attachments) : [],
    activeProvider: scope.providers ? ws.activeProvider : '',
    activeConversation: scope.chats ? ws.activeConversation : '',
    search: scope.search ? ws.search : undefined,
    searchServices: scope.search ? ws.searchServices : undefined,
    activeSearchId: scope.search ? ws.activeSearchId : undefined,
    globalProxy: scope.settings ? ws.globalProxy : undefined,
    mcpEndpoint: scope.mcp ? ws.mcpEndpoint : undefined,
    mcpServers: scope.mcp ? ws.mcpServers : undefined,
    memories: scope.memory ? ws.memories : undefined,
    userProfile: scope.memory ? ws.userProfile : undefined,
    memoryTraces: scope.memory ? ws.memoryTraces : undefined,
    memorySettings: scope.memory ? ws.memorySettings : undefined,
    worldBooks: scope.worldBooks ? ws.worldBooks : undefined,
    instructionCards: scope.instructions ? ws.instructionCards : undefined,
    activeInstructionIds: scope.instructions ? ws.activeInstructionIds : undefined,
    quickPhrases: scope.quickPhrases ? ws.quickPhrases : undefined,
    skills: scope.skills ? ws.skills : undefined,
    workspaces: scope.workspaces ? ws.workspaces : undefined,
    envVars: scope.envVars ? ws.envVars : undefined,
    tts: scope.speech ? ws.tts : undefined,
    asr: scope.speech ? ws.asr : undefined,
    generationParams: scope.settings ? ws.generationParams : undefined,
    modelDefaults: scope.settings ? ws.modelDefaults : undefined,
    scheduledTasks: scope.settings ? ws.scheduledTasks : undefined,
    appearance: scope.settings ? ws.appearance : undefined,
    systemSettings: scope.settings ? ws.systemSettings : undefined,
    toolOverrides: scope.settings ? ws.toolOverrides : undefined,
    userName: scope.settings ? ws.userName : undefined,
    favoriteModels: scope.providers ? ws.favoriteModels : undefined
  };

  // Filter secrets strictly to refs belonging to enabled scope
  const allowedRefs = collectSecretRefsForScope(ws, scope);
  const exportedSecrets: Record<string, string> = {};
  for (let i = 0; i < allowedRefs.length; i++) {
    const r = allowedRefs[i];
    const v = secrets[r];
    if (v !== undefined && v.length > 0) exportedSecrets[r] = v;
  }

  const envelope: HarmonyBackupEnvelopeV2 = {
    format: 'kelivo-workspace-backup',
    version: 2,
    exportedAt: Date.now(),
    scope,
    secrets: exportedSecrets,
    workspace: scopedWs
  };
  return JSON.stringify(envelope);
}

export function parseHarmonyBackupJson(raw: string): ParsedBackupData {
  const env = JSON.parse(raw) as HarmonyBackupEnvelopeV2;
  if (env.format === 'kelivo-workspace-backup' && env.workspace) {
    const ws = env.workspace;
    const scope = env.scope ? normalizeBackupScope(env.scope) : defaultBackupScope();
    const secrets: Record<string, string> = env.secrets || {};
    return {
      sourceName: 'Kelivo (Harmony)',
      sourceScope: scope,
      conversations: scope.chats ? (ws.conversations || []) : undefined,
      providers: scope.providers ? (ws.providers || []) : undefined,
      personas: scope.assistants ? (ws.personas || []) : undefined,
      mcpServers: scope.mcp ? (ws.mcpServers || []) : undefined,
      mcpEndpoint: scope.mcp ? ws.mcpEndpoint : undefined,
      searchServices: scope.search ? (ws.searchServices || []) : undefined,
      activeSearchId: scope.search ? ws.activeSearchId : undefined,
      globalProxy: scope.settings && ws.globalProxy ? normalizeProxyConfig(ws.globalProxy, true) : undefined,
      memories: scope.memory ? (ws.memories || []) : undefined,
      userProfile: scope.memory ? (ws.userProfile || []) : undefined,
      memorySettings: scope.memory ? ws.memorySettings : undefined,
      worldBooks: scope.worldBooks && ws.worldBooks ? normalizeWorldBooks(ws.worldBooks) : undefined,
      quickPhrases: scope.quickPhrases && ws.quickPhrases ? normalizeQuickPhrases(ws.quickPhrases) : undefined,
      instructionCards: scope.instructions && ws.instructionCards ? normalizeInstructionCards(ws.instructionCards) : undefined,
      activeInstructionIds: scope.instructions ? ws.activeInstructionIds : undefined,
      skills: scope.skills ? (ws.skills || []) : undefined,
      workspaces: scope.workspaces ? (ws.workspaces || []) : undefined,
      envVars: scope.envVars ? (ws.envVars || []) : undefined,
      scheduledTasks: scope.settings ? ws.scheduledTasks : undefined,
      tts: scope.speech ? ws.tts : undefined,
      asr: scope.speech ? ws.asr : undefined,
      generationParams: scope.settings ? ws.generationParams : undefined,
      modelDefaults: scope.settings ? ws.modelDefaults : undefined,
      appearance: scope.settings ? ws.appearance : undefined,
      systemSettings: scope.settings ? ws.systemSettings : undefined,
      toolOverrides: scope.settings ? ws.toolOverrides : undefined,
      favoriteModels: scope.providers ? ws.favoriteModels : undefined,
      userName: scope.settings ? ws.userName : undefined,
      activeProvider: scope.providers ? ws.activeProvider : undefined,
      secretsToStore: secrets
    };
  }

  // Legacy kelivo-arkui-full v2 JSON format
  if (env.format === 'kelivo-arkui-full') {
    const scope = env.scope ? normalizeBackupScope(env.scope) : defaultBackupScope();
    const meta = env.workspaceMetaJson ? (JSON.parse(env.workspaceMetaJson) as Workspace) : undefined;
    return {
      sourceName: 'Kelivo (ArkUI v1)',
      sourceScope: scope,
      conversations: env.conversations,
      providers: env.providers,
      personas: env.personas,
      mcpServers: meta?.mcpServers,
      mcpEndpoint: meta?.mcpEndpoint,
      searchServices: meta?.searchServices,
      activeSearchId: meta?.activeSearchId,
      memories: meta?.memories,
      userProfile: meta?.userProfile,
      memorySettings: meta?.memorySettings,
      worldBooks: meta?.worldBooks,
      quickPhrases: meta?.quickPhrases,
      instructionCards: meta?.instructionCards,
      skills: meta?.skills,
      generationParams: meta?.generationParams,
      modelDefaults: meta?.modelDefaults,
      tts: meta?.tts,
      asr: meta?.asr,
      appearance: meta?.appearance,
      systemSettings: meta?.systemSettings,
      toolOverrides: meta?.toolOverrides,
      secretsToStore: {}
    };
  }

  throw new Error('不是有效的 Harmony Kelivo 备份 JSON');
}

function mapFamilyToAndroidProviderType(family: ApiFamily): string {
  if (family === 'anthropic') return 'claude';
  if (family === 'gemini' || family === 'vertex') return 'google';
  return 'openai';
}

function mapAndroidProviderTypeToFamily(providerType: string, useResponseApi: boolean, vertexAI: boolean): ApiFamily {
  if (providerType === 'claude') return 'anthropic';
  if (providerType === 'google') return vertexAI ? 'vertex' : 'gemini';
  return useResponseApi ? 'openai-responses' : 'openai';
}

function mapAndroidLocalToolToHarmony(id: string): string {
  if (id === 'ask_user_input_v0') return 'ask_user_input';
  if (id === 'time_info') return 'get_time_info';
  if (id === 'clipboard') return 'clipboard_tool';
  if (id === 'calculator') return 'calculate';
  if (id === 'tts') return 'text_to_speech';
  if (id === 'browser') return 'browser_action';
  if (id === 'location') return 'get_current_location';
  return id;
}

function mapHarmonyToolToAndroidLocal(id: string): string {
  if (id === 'ask_user_input') return 'ask_user_input_v0';
  if (id === 'get_time_info') return 'time_info';
  if (id === 'clipboard_tool') return 'clipboard';
  if (id === 'calculate') return 'calculator';
  if (id === 'text_to_speech') return 'tts';
  if (id === 'browser_action') return 'browser';
  if (id === 'get_current_location') return 'location';
  return id;
}

export function buildAndroidSettingsJson(
  ws: Workspace,
  rawScope: BackupScopeConfig,
  secrets: Record<string, string>
): string {
  const scope = normalizeBackupScope(rawScope);
  const out: Record<string, Object> = {};

  if (scope.providers) {
    const providerConfigs: Record<string, Object> = {};
    const order: string[] = [];
    for (let i = 0; i < ws.providers.length; i++) {
      const p = ws.providers[i];
      order.push(p.id);
      const primaryKey = p.secretRef ? (secrets[p.secretRef] || '') : '';
      const poolEntries: Object[] = [];
      if (p.apiKeys && p.apiKeys.length > 0) {
        for (let k = 0; k < p.apiKeys.length; k++) {
          const entry = p.apiKeys[k];
          const val = entry.secretRef ? (secrets[entry.secretRef] || '') : '';
          if (!val) continue;
          const item: Record<string, Object> = {};
          item['id'] = entry.id;
          item['key'] = val;
          item['label'] = entry.label;
          item['priority'] = entry.priority;
          item['enabled'] = entry.disabledUntil === 0;
          poolEntries.push(item);
        }
      }
      const pType = mapFamilyToAndroidProviderType(p.family);
      const modelIds: string[] = [];
      if (p.models && p.models.length > 0) {
        for (let m = 0; m < p.models.length; m++) {
          modelIds.push(p.models[m].id);
        }
      } else if (p.model) {
        modelIds.push(p.model);
      }
      const pObj: Record<string, Object | null> = {};
      pObj['id'] = p.id;
      pObj['enabled'] = p.enabled !== false;
      pObj['name'] = p.name;
      pObj['apiKey'] = primaryKey;
      pObj['baseUrl'] = p.baseUrl;
      pObj['providerType'] = pType;
      pObj['chatPath'] = pType === 'openai' ? (p.chatPath || '/chat/completions') : null;
      pObj['useResponseApi'] = pType === 'openai' ? (p.family === 'openai-responses') : null;
      pObj['vertexAI'] = pType === 'google' ? (p.family === 'vertex') : null;
      pObj['models'] = modelIds;
      pObj['proxyEnabled'] = p.proxy?.enabled === true;
      pObj['proxyType'] = normalizeProxyType(p.proxy?.type);
      pObj['proxyHost'] = p.proxy?.host || '';
      pObj['proxyPort'] = String(p.proxy?.port || 8080);
      pObj['proxyUsername'] = p.proxy?.username || '';
      pObj['proxyPassword'] = p.proxy?.passwordRef ? (secrets[p.proxy.passwordRef] || '') : '';
      pObj['multiKeyEnabled'] = poolEntries.length > 0;
      pObj['apiKeys'] = poolEntries;
      providerConfigs[p.id] = pObj;
    }
    out['provider_configs_v1'] = JSON.stringify(providerConfigs);
    out['providers_order_v1'] = order;
    if (ws.modelDefaults?.chatProviderId && ws.modelDefaults?.chatModelId) {
      const selModel: AndroidSelectedModel = {
        providerId: ws.modelDefaults.chatProviderId,
        modelId: ws.modelDefaults.chatModelId
      };
      out['selected_model_v1'] = JSON.stringify(selModel);
    }
  }

  if (scope.assistants) {
    const assts: Object[] = [];
    for (let i = 0; i < ws.personas.length; i++) {
      const a = ws.personas[i];
      const item: Record<string, Object | null> = {};
      item['id'] = a.id;
      item['name'] = a.name;
      item['avatar'] = a.avatar || null;
      item['useAssistantAvatar'] = a.useAssistantAvatar === true;
      item['useAssistantName'] = a.useAssistantName === true;
      item['chatModelProvider'] = a.providerId || null;
      item['chatModelId'] = a.modelId || null;
      item['temperature'] = a.params?.temperature ?? null;
      item['topP'] = a.params?.topP ?? null;
      item['contextMessageSize'] = a.params?.contextLimit ?? 64;
      item['limitContextMessages'] = (a.params?.contextLimit ?? 0) > 0;
      item['streamOutput'] = a.streamOutput !== false;
      item['maxTokens'] = a.params?.maxTokens ?? null;
      const reasoning: AndroidReasoningJson | null = a.params?.reasoningEffort
        ? { level: a.params.reasoningEffort, budgetTokens: a.params.reasoningBudget ?? null }
        : null;
      item['reasoning'] = reasoning;
      item['systemPrompt'] = a.prompt || '';
      item['allowConversationSystemPrompt'] = a.allowConversationSystemPrompt === true;
      item['allowConversationPromptInjection'] = a.allowConversationPromptInjection === true;
      item['appendCurrentTimeToUserMessage'] = a.appendCurrentTimeToUserMessage === true;
      item['useGradientBackground'] = a.useGradientBackground === true;
      item['localToolIds'] = (a.builtinTools || []).map(mapHarmonyToolToAndroidLocal);
      item['skillIds'] = a.skillIds || null;
      item['defaultWorkspaceId'] = a.workspaceId || null;
      item['messageTemplate'] = '{{ message }}';
      item['mcpServerIds'] = a.mcpServerIds || [];
      item['enableMemory'] = a.memoryEnabled !== false;
      item['autoOrganizeMemory'] = a.autoOrganizeMemory ?? (ws.memorySettings?.autoExtract === true);
      item['memoryOrganizeEveryNTurns'] = a.memoryOrganizeEveryNTurns || 1;
      item['memoryFullInjectionTypes'] = (a.memoryFullInjectionTypes || []).map(memoryTypeName);
      item['memorySmartAddMode'] = a.memorySmartAddMode || 'batched';
      item['memoryWriteScope'] = a.memoryWriteScope || 'alwaysGlobal';
      item['allowPastConversationRecall'] = a.allowPastConversationRecall === true;
      item['enableRecentChatsReference'] = a.allowPastConversationRecall === true;
      item['generateConversationSummary'] = a.generateConversationSummary === true;
      item['recentChatsSummaryMessageCount'] = a.recentChatsSummaryMessageCount || 5;
      assts.push(item);
    }
    out['assistants_v1'] = JSON.stringify(assts);
  }

  if (scope.mcp && ws.mcpServers) {
    const mcps: Object[] = [];
    for (let i = 0; i < ws.mcpServers.length; i++) {
      const m = ws.mcpServers[i];
      const obj: Record<string, Object> = {};
      obj['id'] = m.id;
      obj['name'] = m.name;
      obj['type'] = m.transport === 'sse' ? 'sse' : 'http';
      obj['url'] = m.endpoint;
      obj['enabled'] = m.enabled;
      obj['bearerToken'] = m.bearerSecretRef ? (secrets[m.bearerSecretRef] || '') : '';
      obj['disabledTools'] = m.disabledTools || [];
      obj['autoApproveTools'] = m.autoApproveTools || [];
      mcps.push(obj);
    }
    out['mcp_servers_v1'] = JSON.stringify(mcps);
  }

  if (scope.worldBooks && ws.worldBooks) {
    out['world_books_v1'] = JSON.stringify(ws.worldBooks);
  }
  if (scope.quickPhrases && ws.quickPhrases) {
    out['quick_phrases_v1'] = JSON.stringify(ws.quickPhrases);
  }
  if (scope.instructions && ws.instructionCards) {
    const cards: Object[] = [];
    for (let i = 0; i < ws.instructionCards.length; i++) {
      const c = ws.instructionCards[i];
      const text = typeof c.content === 'string' && c.content.length > 0 ? c.content : (c.prompt || '');
      const obj: Record<string, Object> = {};
      obj['id'] = c.id;
      obj['title'] = c.title;
      obj['prompt'] = text;
      obj['group'] = c.group || '';
      obj['description'] = c.description || '';
      obj['content'] = text;
      obj['builtin'] = c.builtin === true;
      cards.push(obj);
    }
    out['instruction_injections_v1'] = JSON.stringify(cards);
  }

  if (scope.search && ws.searchServices) {
    const list: Object[] = [];
    for (let i = 0; i < ws.searchServices.length; i++) {
      const s = ws.searchServices[i];
      const key = s.apiKeys.length > 0 && s.apiKeys[0].secretRef ? (secrets[s.apiKeys[0].secretRef] || '') : '';
      const obj: Record<string, Object> = {};
      obj['id'] = s.id;
      obj['type'] = s.kind === 'bing' ? 'bing_local' : s.kind === 'fourget' ? '4get' : s.kind;
      obj['name'] = s.name;
      obj['url'] = s.endpoint;
      obj['apiKey'] = key;
      obj['enabled'] = s.enabled;
      obj['maxResults'] = s.maxResults;
      list.push(obj);
    }
    out['search_services_v1'] = JSON.stringify(list);
  }

  if (scope.memory) {
    if (ws.memorySettings) {
      out['memory_injection_max_items_v1'] = ws.memorySettings.maxInjectCount;
      out['memory_legacy_mode_v1'] = ws.memorySettings.useLegacyMemory === true;
      out['memory_model_thinking_enabled_v1'] = ws.memorySettings.enableThinking === true;
      if (ws.memorySettings.legacyMemories?.length) {
        // Harmony shares legacy memories across assistants. Android stores them per assistant.
        const legacyMemories: AndroidLegacyMemoryJson[] = [];
        for (const assistant of ws.personas) {
          for (const content of ws.memorySettings.legacyMemories) {
            if (content.trim()) {
              legacyMemories.push({ id: legacyMemories.length + 1, assistantId: assistant.id, content });
            }
          }
        }
        out['assistant_memories_v1'] = JSON.stringify(legacyMemories);
      }
      const tpl = ws.memorySettings.templates;
      if (tpl) {
        if (tpl.rulesZh) out['memory_rules_prompt_zh_v1'] = tpl.rulesZh;
        if (tpl.rulesEn) out['memory_rules_prompt_en_v1'] = tpl.rulesEn;
        if (tpl.gateZh) out['memory_gate_prompt_zh_v1'] = tpl.gateZh;
        if (tpl.gateEn) out['memory_gate_prompt_en_v1'] = tpl.gateEn;
        if (tpl.extractZh) out['memory_extract_prompt_zh_v1'] = tpl.extractZh;
        if (tpl.extractEn) out['memory_extract_prompt_en_v1'] = tpl.extractEn;
        if (tpl.smartAddSingleZh) out['memory_smart_add_single_prompt_zh_v1'] = tpl.smartAddSingleZh;
        if (tpl.smartAddSingleEn) out['memory_smart_add_single_prompt_en_v1'] = tpl.smartAddSingleEn;
        if (tpl.smartAddBatchZh) out['memory_smart_add_batch_prompt_zh_v1'] = tpl.smartAddBatchZh;
        if (tpl.smartAddBatchEn) out['memory_smart_add_batch_prompt_en_v1'] = tpl.smartAddBatchEn;
        if (tpl.profileDistillZh) out['memory_profile_distill_prompt_zh_v1'] = tpl.profileDistillZh;
        if (tpl.profileDistillEn) out['memory_profile_distill_prompt_en_v1'] = tpl.profileDistillEn;
        if (tpl.legacyMigrateZh) out['memory_legacy_migrate_prompt_zh_v1'] = tpl.legacyMigrateZh;
        if (tpl.legacyMigrateEn) out['memory_legacy_migrate_prompt_en_v1'] = tpl.legacyMigrateEn;
      }
    }
    if (ws.modelDefaults?.memoryProviderId && ws.modelDefaults?.memoryModelId) {
      out['memory_model_v1'] = ws.modelDefaults.memoryProviderId + '::' + ws.modelDefaults.memoryModelId;
    }
    if (ws.memories) {
      const mems: Object[] = [];
      for (let i = 0; i < ws.memories.length; i++) {
        const m = ws.memories[i];
        const obj: Record<string, Object | null> = {};
        obj['id'] = m.id;
        obj['scope'] = m.assistantId ? 'assistant' : 'global';
        obj['assistantId'] = m.assistantId || null;
        obj['type'] = m.category === 'tone' ? 'voice' : m.category;
        obj['status'] = m.archived ? 'archived' : 'active';
        obj['content'] = m.content;
        obj['source'] = m.source || 'manual';
        obj['relatedIds'] = m.relatedIds || [];
        obj['createdAt'] = Math.round(normalizeMemoryTimestamp(m.createdAt) * 1000);
        obj['updatedAt'] = Math.round(normalizeMemoryTimestamp(m.updatedAt) * 1000);
        mems.push(obj);
      }
      out['memory_entries_v1'] = JSON.stringify(mems);
    }
    if (ws.userProfile) {
      const profile: AndroidProfileJson[] = ws.userProfile.map((field: UserProfileField): AndroidProfileJson => ({
        id: profileWireKey(field.key || field.id),
        key: field.key || field.id,
        value: field.value,
        source: field.source || 'manual',
        updatedAt: Math.round(normalizeMemoryTimestamp(field.updatedAt) * 1000)
      }));
      out['user_profile_fields_v1'] = JSON.stringify(profile);
    }
  }

  if (scope.envVars && ws.envVars) {
    const envs: AndroidEnvVarJson[] = [];
    const nameRe = /^[A-Za-z_][A-Za-z0-9_]*$/;
    for (let i = 0; i < ws.envVars.length; i++) {
      const e = ws.envVars[i];
      const val = e.secretRef ? (secrets[e.secretRef] || '') : '';
      if (!nameRe.test(e.key) || !val) continue;
      envs.push({ name: e.key, value: val });
    }
    out['environment_variables_v1'] = JSON.stringify(envs);
  }

  if (scope.speech) {
    if (ws.tts && ws.tts.engine !== 'system') {
      const t = ws.tts;
      const tObj: Record<string, Object> = {};
      tObj['id'] = 'tts-main';
      tObj['engine'] = t.engine;
      tObj['endpoint'] = t.endpoint;
      tObj['apiKey'] = t.secretRef ? (secrets[t.secretRef] || '') : '';
      tObj['model'] = t.model;
      tObj['voice'] = t.voice;
      tObj['speed'] = t.speed;
      tObj['language'] = t.language;
      out['tts_services_v1'] = JSON.stringify([tObj]);
    }
  }

  if (scope.settings) {
    if (ws.userName) out['user_name'] = ws.userName;
    if (ws.appearance) {
      out['theme_mode_v1'] = ws.appearance.themeMode;
      out['theme_palette_v1'] = ws.appearance.paletteId;
    }
    if (ws.globalProxy) {
      const gp = normalizeProxyConfig(ws.globalProxy, true);
      out['global_proxy_enabled_v1'] = gp.enabled === true;
      out['global_proxy_type_v1'] = normalizeProxyType(gp.type);
      out['global_proxy_host_v1'] = gp.host || '';
      out['global_proxy_port_v1'] = String(gp.port || 8080);
      out['global_proxy_username_v1'] = gp.username || '';
      out['global_proxy_password_v1'] = gp.passwordRef ? (secrets[gp.passwordRef] || '') : '';
      if (gp.bypass !== undefined) {
        out['global_proxy_bypass_v1'] = gp.bypass;
      }
    }
  }

  return JSON.stringify(out);
}

export function buildAndroidChatsJson(conversations: Conversation[]): string {
  const chats: AndroidConversationJson[] = [];
  const messages: AndroidMessageJson[] = [];

  for (let i = 0; i < conversations.length; i++) {
    const c = conversations[i];
    if (c.ephemeral) continue;
    const msgIds: string[] = [];
    const versionSelections: Record<string, number> = {};
    const createdMs = c.messages.length > 0 && c.messages[0].createdAt ? c.messages[0].createdAt : c.updated;

    for (let j = 0; j < c.messages.length; j++) {
      const m = c.messages[j];
      const tsIso = new Date(m.createdAt || c.updated || Date.now()).toISOString();
      if (m.versions && m.versions.length > 1) {
        const gid = m.id + '-grp';
        const sel = m.activeVersion ?? (m.versions.length - 1);
        versionSelections[gid] = sel;
        for (let v = 0; v < m.versions.length; v++) {
          const ver = m.versions[v];
          const vid = v === sel ? m.id : ver.id;
          msgIds.push(vid);
          messages.push({
            id: vid,
            conversationId: c.id,
            role: m.role,
            content: ver.text,
            parts: [{ kind: 'text', payload: ver.text }],
            timestamp: new Date(ver.createdAt || m.createdAt || c.updated).toISOString(),
            modelId: ver.model || m.model || null,
            reasoningText: ver.reasoning || null,
            translation: ver.translation || null,
            groupId: gid,
            version: v,
            totalTokens: ver.usage?.totalTokens ?? null,
            promptTokens: ver.usage?.promptTokens ?? null,
            completionTokens: ver.usage?.completionTokens ?? null,
            cachedTokens: ver.usage?.cachedTokens ?? null,
            durationMs: ver.usage?.durationMs ?? null
          });
        }
      } else {
        msgIds.push(m.id);
        messages.push({
          id: m.id,
          conversationId: c.id,
          role: m.role,
          content: m.text,
          parts: [{ kind: 'text', payload: m.text }],
          timestamp: tsIso,
          modelId: m.model || null,
          reasoningText: m.reasoning || null,
          translation: m.translation || null,
          totalTokens: m.usage?.totalTokens ?? null,
          promptTokens: m.usage?.promptTokens ?? null,
          completionTokens: m.usage?.completionTokens ?? null,
          cachedTokens: m.usage?.cachedTokens ?? null,
          durationMs: m.usage?.durationMs ?? null
        });
      }
    }

    chats.push({
      id: c.id,
      title: c.title,
      createdAt: new Date(createdMs || Date.now()).toISOString(),
      updatedAt: new Date(c.updated || Date.now()).toISOString(),
      messageIds: msgIds,
      isPinned: c.pinned === true,
      mcpServerIds: c.enabledMcpIds || [],
      assistantId: c.personaId || null,
      truncateIndex: c.contextStartIndex ?? -1,
      versionSelections,
      chatSuggestions: c.suggestions || [],
      chatModelProvider: c.overrideProviderId || null,
      chatModelId: c.overrideModel || null
    });
  }

  const rootOut: AndroidChatsRoot = {
    version: 1,
    conversations: chats,
    messages
  };
  return JSON.stringify(rootOut);
}

function parseJsonValue<T>(raw: Object | undefined | null): T | undefined {
  if (raw === undefined || raw === null) return undefined;
  if (typeof raw === 'string') {
    const trimmed = raw.trim();
    if (!trimmed) return undefined;
    return JSON.parse(trimmed) as T;
  }
  return raw as T;
}

function parseTimestampMs(raw?: string | number): number {
  if (typeof raw === 'number' && Number.isFinite(raw)) return raw;
  if (typeof raw === 'string' && raw.length > 0) {
    const ms = Date.parse(raw);
    if (Number.isFinite(ms)) return ms;
  }
  return Date.now();
}

function parseMemoryTimestamp(raw?: string | number): number {
  if (typeof raw === 'number' && raw >= 100000000000000) return Math.floor(raw / 1000);
  return parseTimestampMs(raw);
}

function parseAndroidReasoningEffort(level?: string): ReasoningEffort | undefined {
  switch (level) {
    case 'off':
    case 'low':
    case 'medium':
    case 'high':
    case 'max':
      return level;
    default:
      return undefined;
  }
}

export function parseAndroidChatsJson(rawJson: string): Conversation[] {
  const archive = JSON.parse(rawJson) as AndroidChatsRoot;
  if (!Array.isArray(archive.conversations) || !Array.isArray(archive.messages)) {
    throw new Error('不是有效的 Kelivo chats.json 格式');
  }
  const msgLookup = new Map<string, AndroidMessageJson>();
  for (let i = 0; i < archive.messages.length; i++) {
    const m = archive.messages[i];
    if (m && m.id) msgLookup.set(m.id, m);
  }

  const out: Conversation[] = [];
  for (let i = 0; i < archive.conversations.length; i++) {
    const c = archive.conversations[i];
    if (!c || !c.id || !Array.isArray(c.messageIds)) continue;
    const groups = new Map<string, AndroidMessageJson[]>();
    for (let j = 0; j < c.messageIds.length; j++) {
      const m = msgLookup.get(c.messageIds[j]);
      if (!m || m.conversationId !== c.id) continue;
      if (m.role !== 'user' && m.role !== 'assistant') continue;
      const gid = m.groupId || m.id || String(j);
      const arr = groups.get(gid) || [];
      arr.push(m);
      groups.set(gid, arr);
    }

    const messages: ChatMessage[] = [];
    groups.forEach((items: AndroidMessageJson[], gid: string) => {
      items.sort((a: AndroidMessageJson, b: AndroidMessageJson): number => (a.version || 0) - (b.version || 0));
      const selVer = c.versionSelections ? c.versionSelections[gid] : undefined;
      let activeIdx = items.length - 1;
      if (selVer !== undefined) {
        const idx = items.findIndex((it: AndroidMessageJson): boolean => it.version === selVer);
        if (idx >= 0) activeIdx = idx;
      }
      const selected = items[activeIdx];
      const versions: MessageVersion[] = [];
      for (let v = 0; v < items.length; v++) {
        const it = items[v];
        const txt = extractAndroidMessageText(it);
        const rsn = extractAndroidMessageReasoning(it);
        versions.push({
          id: it.id || (gid + '-v-' + v),
          text: txt,
          reasoning: rsn,
          model: it.modelId || '',
          createdAt: parseTimestampMs(it.timestamp || it.createdAt),
          translation: it.translation || undefined
        });
      }
      messages.push({
        id: selected.id || gid,
        role: selected.role === 'assistant' ? 'assistant' : 'user',
        text: versions[activeIdx].text,
        model: selected.modelId || '',
        reasoning: versions[activeIdx].reasoning,
        createdAt: versions[activeIdx].createdAt,
        translation: selected.translation || undefined,
        usage: typeof selected.totalTokens === 'number' ? {
          promptTokens: selected.promptTokens || 0,
          completionTokens: selected.completionTokens || 0,
          cachedTokens: selected.cachedTokens || 0,
          totalTokens: selected.totalTokens,
          durationMs: selected.durationMs || 0
        } : undefined,
        versions: versions.length > 1 ? versions : undefined,
        activeVersion: versions.length > 1 ? activeIdx : undefined
      });
    });

    out.push({
      id: c.id,
      title: c.title || '导入对话',
      updated: parseTimestampMs(c.updatedAt || c.createdAt),
      pinned: c.isPinned === true,
      messages,
      personaId: c.assistantId || 'default',
      contextStartIndex: typeof c.truncateIndex === 'number' ? c.truncateIndex : undefined,
      overrideProviderId: c.chatModelProvider || undefined,
      overrideModel: c.chatModelId || undefined,
      enabledMcpIds: Array.isArray(c.mcpServerIds) ? c.mcpServerIds : undefined,
      suggestions: Array.isArray(c.chatSuggestions) ? c.chatSuggestions : undefined
    });
  }
  return out;
}

function extractAndroidMessageText(m: AndroidMessageJson): string {
  if (Array.isArray(m.parts) && m.parts.length > 0) {
    let out = '';
    for (let i = 0; i < m.parts.length; i++) {
      const part = m.parts[i];
      if (part.kind === 'text' && typeof part.payload === 'string') {
        out += part.payload;
      }
    }
    if (out.length > 0 || typeof m.content !== 'string') return out;
  }
  return typeof m.content === 'string' ? m.content : '';
}

function extractAndroidMessageReasoning(m: AndroidMessageJson): string {
  if (typeof m.reasoningText === 'string' && m.reasoningText.length > 0) return m.reasoningText;
  if (Array.isArray(m.parts)) {
    const parts: string[] = [];
    for (let i = 0; i < m.parts.length; i++) {
      if (m.parts[i].kind === 'reasoning' && typeof m.parts[i].payload === 'string' && m.parts[i].payload) {
        parts.push(m.parts[i].payload || '');
      }
    }
    if (parts.length > 0) return parts.join('\n');
  }
  return '';
}

export function parseAndroidSettingsJson(rawJson: string): ParsedBackupData {
  const settings = JSON.parse(rawJson) as Record<string, Object>;
  const secretsToStore: Record<string, string> = {};
  let secSeq = 0;
  const stageSecret = (val?: string | null): string => {
    const clean = (val || '').trim();
    if (!clean) return '';
    secSeq++;
    const tmp = '__android_sec_' + secSeq;
    secretsToStore[tmp] = clean;
    return tmp;
  };

  // 1. Providers + order
  let providers: Provider[] | undefined = undefined;
  const rawProvMap = parseJsonValue<Record<string, AndroidProviderJson>>(settings['provider_configs_v1']);
  if (rawProvMap) {
    const order = parseJsonValue<string[]>(settings['providers_order_v1']) || [];
    const seen = new Set<string>();
    const orderedIds: string[] = [];
    for (let i = 0; i < order.length; i++) {
      const k = order[i];
      if (k && rawProvMap[k] && !seen.has(k)) {
        seen.add(k);
        orderedIds.push(k);
      }
    }
    const mapKeys = Object.keys(rawProvMap);
    for (let i = 0; i < mapKeys.length; i++) {
      const k = mapKeys[i];
      if (!seen.has(k)) {
        seen.add(k);
        orderedIds.push(k);
      }
    }
    providers = [];
    for (let i = 0; i < orderedIds.length; i++) {
      const k = orderedIds[i];
      const ap = rawProvMap[k];
      if (!ap || !ap.name) continue;
      const pType = (ap.providerType || 'openai').toLowerCase();
      const family = mapAndroidProviderTypeToFamily(pType, ap.useResponseApi === true, ap.vertexAI === true);
      const modelSpecs: ModelSpec[] = [];
      if (Array.isArray(ap.models)) {
        for (let m = 0; m < ap.models.length; m++) {
          const item = ap.models[m];
          const mid = typeof item === 'string' ? item : String((item as Record<string, Object>)['id'] || '');
          if (mid.trim()) modelSpecs.push(defaultModelSpec(mid.trim()));
        }
      }
      const primaryRef = stageSecret(ap.apiKey);
      const pool: ApiKeyEntry[] = [];
      if (Array.isArray(ap.apiKeys)) {
        for (let a = 0; a < ap.apiKeys.length; a++) {
          const ak = ap.apiKeys[a];
          const r = stageSecret(ak.key);
          if (!r) continue;
          pool.push({
            id: ak.id || ('ak-' + i + '-' + a),
            label: ak.name || ak.label || ('Key ' + (a + 1)),
            secretRef: r,
            priority: typeof ak.priority === 'number' ? ak.priority : a,
            usageCount: 0,
            errorCount: 0,
            disabledUntil: (ak.isEnabled === false || ak.enabled === false) ? Date.now() + 86400000 : 0
          });
        }
      }
      const proxyPassRef = stageSecret(ap.proxyPassword);
      const hasProxyConfig = ap.proxyEnabled === true || (typeof ap.proxyHost === 'string' && ap.proxyHost.trim().length > 0);
      providers.push({
        id: ap.id || k,
        name: ap.name,
        family,
        baseUrl: (ap.baseUrl || '').trim(),
        chatPath: ap.chatPath || '',
        model: modelSpecs.length > 0 ? modelSpecs[0].id : '',
        secretRef: primaryRef,
        models: modelSpecs,
        apiKeys: pool,
        keyStrategy: 'round_robin',
        proxy: hasProxyConfig ? {
          enabled: ap.proxyEnabled === true,
          type: normalizeProxyType(ap.proxyType),
          host: ap.proxyHost || '',
          port: Number(ap.proxyPort) || 8080,
          username: ap.proxyUsername || '',
          passwordRef: proxyPassRef || undefined
        } : undefined,
        enabled: ap.enabled !== false
      });
    }
  }

  // 2. Assistants -> Personas
  let personas: Persona[] | undefined = undefined;
  const rawAssts = parseJsonValue<AndroidAssistantJson[]>(settings['assistants_v1']);
  if (Array.isArray(rawAssts)) {
    personas = [];
    for (let i = 0; i < rawAssts.length; i++) {
      const a = rawAssts[i];
      if (!a || !a.id || !a.name) continue;
      const reasoningLevel = typeof a.reasoning === 'string' ? a.reasoning : a.reasoning?.level;
      const reasoningBudget = typeof a.reasoning === 'object' ? a.reasoning?.budgetTokens : undefined;
      personas.push({
        id: a.id,
        name: a.name,
        prompt: a.systemPrompt || a.prompt || '',
        avatar: a.avatar || undefined,
        providerId: a.chatModelProvider || undefined,
        modelId: a.chatModelId || undefined,
        useAssistantAvatar: a.useAssistantAvatar === true,
        useAssistantName: a.useAssistantName === true,
        streamOutput: a.streamOutput !== false,
        memoryEnabled: a.enableMemory === true,
        autoOrganizeMemory: a.autoOrganizeMemory === true,
        memoryOrganizeEveryNTurns: Math.max(1, Math.min(20, Math.floor(a.memoryOrganizeEveryNTurns || 1))),
        memoryFullInjectionTypes: Array.isArray(a.memoryFullInjectionTypes)
          ? a.memoryFullInjectionTypes.filter((type: string): boolean =>
              ['identity', 'workflow', 'voice', 'tone', 'instruction'].includes(type)).map(normalizeMemoryCategory)
          : undefined,
        memorySmartAddMode: (a.memorySmartAddMode === 'perItem' || a.memorySmartAddMode === 'single') ? 'perItem' : 'batched',
        memoryWriteScope: a.memoryWriteScope,
        allowPastConversationRecall: (a.allowPastConversationRecall ?? a.enableRecentChatsReference) === true,
        generateConversationSummary: a.generateConversationSummary === true,
        recentChatsSummaryMessageCount: typeof a.recentChatsSummaryMessageCount === 'number'
          ? Math.max(1, Math.min(50, Math.floor(a.recentChatsSummaryMessageCount)))
          : 5,
        allowConversationSystemPrompt: a.allowConversationSystemPrompt === true,
        allowConversationPromptInjection: a.allowConversationPromptInjection === true,
        appendCurrentTimeToUserMessage: a.appendCurrentTimeToUserMessage === true,
        useGradientBackground: a.useGradientBackground === true,
        builtinTools: Array.isArray(a.localToolIds) ? a.localToolIds.map(mapAndroidLocalToolToHarmony) : undefined,
        skillIds: Array.isArray(a.skillIds) ? a.skillIds : undefined,
        workspaceId: a.defaultWorkspaceId || undefined,
        mcpServerIds: Array.isArray(a.mcpServerIds) ? a.mcpServerIds : undefined,
        params: {
          temperature: typeof a.temperature === 'number' ? a.temperature : undefined,
          topP: typeof a.topP === 'number' ? a.topP : undefined,
          maxTokens: typeof a.maxTokens === 'number' ? a.maxTokens : undefined,
          reasoningEffort: parseAndroidReasoningEffort(reasoningLevel),
          reasoningBudget: typeof reasoningBudget === 'number' ? reasoningBudget : undefined,
          contextLimit: (a.limitContextMessages !== false && typeof a.contextMessageSize === 'number')
            ? a.contextMessageSize
            : undefined
        }
      });
    }
  }

  // 3. MCP
  let mcpServers: McpServerConfig[] | undefined = undefined;
  const rawMcps = parseJsonValue<AndroidMcpJson[]>(settings['mcp_servers_v1']);
  if (Array.isArray(rawMcps)) {
    mcpServers = [];
    for (let i = 0; i < rawMcps.length; i++) {
      const m = rawMcps[i];
      if (!m || !m.id) continue;
      const endpoint = (m.url || m.endpoint || '').trim();
      if (!endpoint) continue;
      const transport = (m.type || m.transport || '').toLowerCase() === 'sse' ? 'sse' : 'streamable-http';
      let bearerRaw = (m.bearerToken || '').trim();
      if (!bearerRaw && m.headers) {
        const authHdr = m.headers['Authorization'] || m.headers['authorization'] || '';
        if (authHdr.trim()) {
          bearerRaw = authHdr.trim().replace(/^Bearer\s+/i, '');
        }
      }
      mcpServers.push({
        id: m.id,
        name: m.name || m.id,
        transport,
        endpoint,
        bearerSecretRef: stageSecret(bearerRaw),
        customHeaders: [],
        enabled: m.enabled !== false,
        disabledTools: Array.isArray(m.disabledTools) ? m.disabledTools : [],
        autoApproveTools: Array.isArray(m.autoApproveTools) ? m.autoApproveTools : []
      });
    }
  }

  // 4. WorldBooks, QuickPhrases, InstructionCards
  const rawWorldBooks = parseJsonValue<WorldBook[]>(settings['world_books_v1']);
  const worldBooks = Array.isArray(rawWorldBooks) ? normalizeWorldBooks(rawWorldBooks) : undefined;
  const rawQuickPhrases = parseJsonValue<QuickPhrase[]>(settings['quick_phrases_v1']);
  const quickPhrases = Array.isArray(rawQuickPhrases) ? normalizeQuickPhrases(rawQuickPhrases) : undefined;
  const rawInstructionCards = parseJsonValue<InstructionCard[]>(settings['instruction_injections_v1']);
  const instructionCards = Array.isArray(rawInstructionCards)
    ? normalizeInstructionCards(rawInstructionCards)
    : undefined;

  // 5. Env Vars
  let envVars: EnvVar[] | undefined = undefined;
  const rawEnvs = parseJsonValue<AndroidEnvVarJson[]>(settings['environment_variables_v1']);
  if (Array.isArray(rawEnvs)) {
    envVars = [];
    for (let i = 0; i < rawEnvs.length; i++) {
      const ev = rawEnvs[i];
      if (!ev || !ev.name || !ev.value) continue;
      envVars.push({
        id: ev.id || ('env-' + i + '-' + ev.name),
        key: ev.name,
        secretRef: stageSecret(ev.value),
        masked: true
      });
    }
  }

  // 6. Search services
  let searchServices: SearchServiceConfig[] | undefined = undefined;
  const rawSearch = parseJsonValue<AndroidSearchJson[]>(settings['search_services_v1']);
  if (Array.isArray(rawSearch)) {
    searchServices = [];
    for (let i = 0; i < rawSearch.length; i++) {
      const s = rawSearch[i];
      if (!s || !s.id) continue;
      const keys: ApiKeyEntry[] = [];
      const kRef = stageSecret(s.apiKey);
      if (kRef) {
        keys.push({
          id: 'sk-' + i,
          label: 'Key 1',
          secretRef: kRef,
          priority: 0,
          usageCount: 0,
          errorCount: 0,
          disabledUntil: 0
        });
      }
      if (Array.isArray(s.apiKeys)) {
        for (let k = 0; k < s.apiKeys.length; k++) {
          const kr = stageSecret(s.apiKeys[k].key);
          if (!kr) continue;
          keys.push({
            id: s.apiKeys[k].id || ('sk-' + i + '-' + k),
            label: s.apiKeys[k].label || ('Key ' + (keys.length + 1)),
            secretRef: kr,
            priority: k,
            usageCount: 0,
            errorCount: 0,
            disabledUntil: 0
          });
        }
      }
      const kind = (s.type || s.kind || 'tavily').toLowerCase();
      searchServices.push({
        id: s.id,
        kind: kind === 'bing_local' ? 'bing' : kind === '4get' ? 'fourget' : kind,
        name: s.name || s.id,
        endpoint: s.endpoint || s.url || '',
        apiKeys: keys,
        keyStrategy: 'round_robin',
        maxResults: typeof s.maxResults === 'number' ? s.maxResults : 5,
        enabled: s.enabled !== false,
        mode: 'agent_tool',
        webFetchEnabled: true
      });
    }
  }

  // 7. Memories & User Profile
  let memories: MemoryEntry[] | undefined = undefined;
  const rawMems = parseJsonValue<AndroidMemoryJson[]>(settings['memory_entries_v1']);
  if (Array.isArray(rawMems)) {
    memories = [];
    for (let i = 0; i < rawMems.length; i++) {
      const m = rawMems[i];
      if (!m || !m.content || (m.scope === 'assistant' && !m.assistantId)) continue;
      const t = (m.type || m.category || 'identity').toLowerCase();
      const category = t === 'voice' || t === 'tone' ? 'tone'
        : t === 'workflow' ? 'workflow'
        : t === 'instruction' ? 'instruction'
        : 'identity';
      const src: MemorySourceKind = (m.source === 'extracted' || m.source === 'tool')
        ? m.source
        : 'manual';
      memories.push({
        id: m.id || ('mem-' + i),
        category,
        content: m.content,
        assistantId: m.scope === 'assistant' ? m.assistantId : undefined,
        archived: m.status === 'archived',
        source: src,
        relatedIds: Array.isArray(m.relatedIds) ? m.relatedIds : [],
        createdAt: parseMemoryTimestamp(m.createdAt),
        updatedAt: parseMemoryTimestamp(m.updatedAt || m.createdAt)
      });
    }
  }
  const rawProfile = parseJsonValue<AndroidProfileJson[]>(settings['user_profile_fields_v1']);
  let userProfile: UserProfileField[] | undefined = undefined;
  if (Array.isArray(rawProfile)) {
    userProfile = [];
    for (const field of rawProfile) {
      const key = (field?.key || field?.id || '').trim();
      if (!key || typeof field.value !== 'string' || !field.value.trim()) continue;
      userProfile.push({
        id: field.id || key,
        key,
        value: field.value,
        source: field.source === 'distilled' ? 'distilled' : 'manual',
        updatedAt: parseMemoryTimestamp(field.updatedAt)
      });
    }
    userProfile = normalizeUserProfileFields(userProfile);
  }
  const maxItems = Number(settings['memory_injection_max_items_v1']);
  const legacyModeRaw = settings['memory_legacy_mode_v1'];
  const thinkingRaw = settings['memory_model_thinking_enabled_v1'];
  const rawLegacyMems = parseJsonValue<Object[]>(settings['assistant_memories_v1']);
  const legacyMemories = new Set<string>();
  if (Array.isArray(rawLegacyMems)) {
    for (let i = 0; i < rawLegacyMems.length; i++) {
      const it: Object = rawLegacyMems[i];
      if (typeof it === 'string' && it.trim().length > 0) {
        legacyMemories.add(it.trim());
      } else if (it && typeof it === 'object') {
        const content = (it as Record<string, Object>)['content'];
        if (typeof content === 'string' && content.trim().length > 0) {
          legacyMemories.add(content.trim());
        }
      }
    }
  }
  const legacyList = Array.from(legacyMemories);
  const readStr = (k: string): string | undefined => {
    const v = settings[k];
    return typeof v === 'string' && v.trim().length > 0 ? v : undefined;
  };
  const parsedTemplates: MemoryPromptTemplates = {
    rulesZh: readStr('memory_rules_prompt_zh_v1'),
    rulesEn: readStr('memory_rules_prompt_en_v1'),
    gateZh: readStr('memory_gate_prompt_zh_v1'),
    gateEn: readStr('memory_gate_prompt_en_v1'),
    extractZh: readStr('memory_extract_prompt_zh_v1'),
    extractEn: readStr('memory_extract_prompt_en_v1'),
    smartAddSingleZh: readStr('memory_smart_add_single_prompt_zh_v1'),
    smartAddSingleEn: readStr('memory_smart_add_single_prompt_en_v1'),
    smartAddBatchZh: readStr('memory_smart_add_batch_prompt_zh_v1'),
    smartAddBatchEn: readStr('memory_smart_add_batch_prompt_en_v1'),
    profileDistillZh: readStr('memory_profile_distill_prompt_zh_v1'),
    profileDistillEn: readStr('memory_profile_distill_prompt_en_v1'),
    legacyMigrateZh: readStr('memory_legacy_migrate_prompt_zh_v1'),
    legacyMigrateEn: readStr('memory_legacy_migrate_prompt_en_v1')
  };
  const hasAnyTemplate = Boolean(
    parsedTemplates.rulesZh || parsedTemplates.rulesEn || parsedTemplates.gateZh || parsedTemplates.gateEn ||
    parsedTemplates.extractZh || parsedTemplates.extractEn || parsedTemplates.smartAddSingleZh ||
    parsedTemplates.smartAddSingleEn || parsedTemplates.smartAddBatchZh || parsedTemplates.smartAddBatchEn ||
    parsedTemplates.profileDistillZh || parsedTemplates.profileDistillEn ||
    parsedTemplates.legacyMigrateZh || parsedTemplates.legacyMigrateEn
  );
  const hasAnyMemorySetting = Number.isFinite(maxItems) || legacyModeRaw !== undefined || thinkingRaw !== undefined ||
    legacyList.length > 0 || hasAnyTemplate;
  const memorySettings: MemorySettings | undefined = hasAnyMemorySetting
    ? normalizeMemorySettings({
        autoExtract: false,
        injectGlobal: true,
        maxInjectCount: Number.isFinite(maxItems) && maxItems >= 1 ? Math.min(200, Math.floor(maxItems)) : 100,
        useLegacyMemory: legacyModeRaw === true,
        enableThinking: thinkingRaw !== false,
        promptLanguage: 'auto',
        recordTraces: true,
        templates: parsedTemplates,
        legacyMemories: legacyList
      })
    : undefined;

  // 8. Speech (TTS)
  let tts: TtsConfig | undefined = undefined;
  const rawTts = parseJsonValue<AndroidSpeechJson[]>(settings['tts_services_v1']);
  if (Array.isArray(rawTts) && rawTts.length > 0) {
    const t = rawTts[0];
    tts = {
      engine: 'openai',
      endpoint: t.endpoint || t.baseUrl || '',
      secretRef: stageSecret(t.apiKey),
      model: t.model || 'tts-1',
      voice: t.voice || 'alloy',
      speed: typeof t.speed === 'number' ? t.speed : 1.0,
      language: t.language || 'zh-CN',
      region: t.region
    };
  }

  // 9. Preferences (userName, appearance, selected model, memory model)
  const userName = typeof settings['user_name'] === 'string' ? (settings['user_name'] as string) : undefined;
  const selectedModel = parseJsonValue<AndroidSelectedModel>(settings['selected_model_v1']);
  let memProviderId = '';
  let memModelId = '';
  const rawMemModel = settings['memory_model_v1'];
  if (typeof rawMemModel === 'string' && rawMemModel.trim()) {
    const trimmed = rawMemModel.trim();
    if (trimmed.includes('::')) {
      const parts = trimmed.split('::');
      memProviderId = parts[0] || '';
      memModelId = parts.slice(1).join('::') || '';
    } else if (trimmed.startsWith('{')) {
      const parsedMem = parseJsonValue<AndroidSelectedModel>(trimmed);
      if (parsedMem) {
        memProviderId = parsedMem.providerId || '';
        memModelId = parsedMem.modelId || '';
      }
    }
  }
  let modelDefaults: ModelDefaults | undefined = undefined;
  if ((selectedModel && selectedModel.providerId && selectedModel.modelId) || (memProviderId && memModelId)) {
    modelDefaults = {
      chatProviderId: selectedModel?.providerId || '',
      chatModelId: selectedModel?.modelId || '',
      perChatModel: false,
      titleProviderId: '',
      titleModelId: '',
      translateProviderId: '',
      translateModelId: '',
      ocrProviderId: '',
      ocrModelId: '',
      memoryProviderId: memProviderId,
      memoryModelId: memModelId
    };
  }
  const themeMode = typeof settings['theme_mode_v1'] === 'string' ? (settings['theme_mode_v1'] as string) : '';
  let appearance: AppearanceConfig | undefined = undefined;
  if (themeMode === 'system' || themeMode === 'light' || themeMode === 'dark') {
    appearance = normalizeAppearanceConfig();
    appearance.themeMode = themeMode;
  }

  let globalProxy: ProxyConfig | undefined = undefined;
  const hasGlobalProxyKeys =
    settings['global_proxy_enabled_v1'] !== undefined ||
    settings['global_proxy_host_v1'] !== undefined ||
    settings['global_proxy_port_v1'] !== undefined ||
    settings['global_proxy_type_v1'] !== undefined ||
    settings['global_proxy_bypass_v1'] !== undefined;
  if (hasGlobalProxyKeys) {
    const rawEn = settings['global_proxy_enabled_v1'];
    const rawHost = settings['global_proxy_host_v1'];
    const rawPort = settings['global_proxy_port_v1'];
    const rawType = settings['global_proxy_type_v1'];
    const rawUser = settings['global_proxy_username_v1'];
    const rawPass = settings['global_proxy_password_v1'];
    const rawBypass = settings['global_proxy_bypass_v1'];
    const passRef = typeof rawPass === 'string' ? stageSecret(rawPass) : '';
    const parsedPort = typeof rawPort === 'number'
      ? rawPort
      : Number(typeof rawPort === 'string' ? rawPort.trim() : '8080');
    globalProxy = normalizeProxyConfig({
      enabled: rawEn === true || rawEn === 'true',
      type: normalizeProxyType(typeof rawType === 'string' ? rawType : undefined),
      host: typeof rawHost === 'string' ? rawHost : '',
      port: Number.isFinite(parsedPort) && parsedPort > 0 ? parsedPort : 8080,
      username: typeof rawUser === 'string' ? rawUser : '',
      passwordRef: passRef || undefined,
      bypass: typeof rawBypass === 'string' ? rawBypass : undefined
    }, true);
  }

  return {
    sourceName: 'Kelivo (Android)',
    providers,
    personas,
    mcpServers,
    globalProxy,
    worldBooks: Array.isArray(worldBooks) ? worldBooks : undefined,
    quickPhrases: Array.isArray(quickPhrases) ? quickPhrases : undefined,
    instructionCards: Array.isArray(instructionCards) ? instructionCards : undefined,
    envVars,
    searchServices,
    memories,
    userProfile,
    memorySettings,
    tts,
    modelDefaults,
    appearance,
    userName,
    secretsToStore
  };
}

export function applyScopedRestore(
  current: Workspace,
  incoming: ParsedBackupData,
  rawScope: BackupScopeConfig,
  mode: 'overwrite' | 'merge',
  makeRefId: () => string
): ApplyRestoreOutput {
  const scope = normalizeBackupScope(rawScope);
  const srcScope = incoming.sourceScope ? normalizeBackupScope(incoming.sourceScope) : undefined;
  const allowCategory = (selected: boolean, hasPayload: boolean, srcEnabled?: boolean): boolean => {
    if (!selected || !hasPayload) return false;
    if (srcEnabled === false) return false;
    return true;
  };

  const outSecrets: Record<string, string> = {};
  const remapRef = (oldRef: string | undefined, sameDeviceFallback: boolean): string => {
    if (!oldRef) return '';
    const secretVal = incoming.secretsToStore[oldRef];
    if (secretVal !== undefined && secretVal.length > 0) {
      const fresh = makeRefId();
      outSecrets[fresh] = secretVal;
      return fresh;
    }
    return sameDeviceFallback ? oldRef : '';
  };
  const isHarmonySource = incoming.sourceName.indexOf('Harmony') >= 0 || incoming.sourceName.indexOf('ArkUI') >= 0;

  // Clone base workspace keeping all existing data & local-only security config untouched by default
  const next: Workspace = {
    version: current.version,
    providers: current.providers.slice(),
    personas: current.personas.slice(),
    conversations: current.conversations.slice(),
    search: current.search,
    searchServices: current.searchServices ? current.searchServices.slice() : [],
    activeSearchId: current.activeSearchId,
    globalProxy: current.globalProxy,
    mcpEndpoint: current.mcpEndpoint,
    mcpServers: current.mcpServers ? current.mcpServers.slice() : [],
    davDirectory: current.davDirectory,
    davPath: current.davPath,
    davFilename: current.davFilename,
    davUsername: current.davUsername,
    davPasswordRef: current.davPasswordRef,
    davUserAgent: current.davUserAgent,
    s3Config: current.s3Config,
    backupConfig: current.backupConfig,
    activeProvider: current.activeProvider,
    activeConversation: current.activeConversation,
    generationParams: current.generationParams,
    modelDefaults: current.modelDefaults,
    tts: current.tts,
    asr: current.asr,
    memories: current.memories ? current.memories.slice() : [],
    userProfile: current.userProfile ? current.userProfile.slice() : [],
    memoryTraces: current.memoryTraces ? current.memoryTraces.slice() : [],
    memorySettings: current.memorySettings,
    worldBooks: current.worldBooks ? current.worldBooks.slice() : [],
    instructionCards: current.instructionCards ? current.instructionCards.slice() : [],
    activeInstructionIds: current.activeInstructionIds ? current.activeInstructionIds.slice() : [],
    quickPhrases: current.quickPhrases ? current.quickPhrases.slice() : [],
    skills: current.skills ? current.skills.slice() : [],
    workspaces: current.workspaces ? current.workspaces.slice() : [],
    envVars: current.envVars ? current.envVars.slice() : [],
    scheduledTasks: current.scheduledTasks ? current.scheduledTasks.slice() : [],
    browserBookmarks: current.browserBookmarks ? current.browserBookmarks.slice() : [],
    appearance: current.appearance,
    systemSettings: current.systemSettings,
    toolOverrides: current.toolOverrides ? current.toolOverrides.slice() : [],
    snapshots: current.snapshots ? current.snapshots.slice() : [],
    userName: current.userName,
    favoriteModels: current.favoriteModels ? current.favoriteModels.slice() : []
  };

  let importedChats = 0;
  let importedMsgs = 0;
  let importedProviders = 0;
  let importedAssistants = 0;

  // 1. Chats
  if (allowCategory(scope.chats, Array.isArray(incoming.conversations), srcScope?.chats)) {
    const incChats = incoming.conversations || [];
    if (mode === 'overwrite') {
      next.conversations = incChats.slice();
      importedChats = incChats.length;
      for (let i = 0; i < incChats.length; i++) importedMsgs += incChats[i].messages.length;
    } else {
      const byId = new Map<string, Conversation>();
      for (let i = 0; i < next.conversations.length; i++) byId.set(next.conversations[i].id, next.conversations[i]);
      const list = next.conversations.slice();
      for (let i = 0; i < incChats.length; i++) {
        const inc = incChats[i];
        const existing = byId.get(inc.id);
        if (!existing) {
          byId.set(inc.id, inc);
          list.push(inc);
          importedChats++;
          importedMsgs += inc.messages.length;
        } else {
          const sameLen = existing.messages.length === inc.messages.length;
          const sameLast = !sameLen || existing.messages.length === 0 ||
            existing.messages[existing.messages.length - 1].text === inc.messages[inc.messages.length - 1].text;
          if (sameLen && sameLast) continue;
          const remappedId = 'conv-' + makeRefId();
          const cloned: Conversation = {
            id: remappedId,
            title: inc.title,
            updated: inc.updated,
            pinned: inc.pinned,
            messages: inc.messages,
            personaId: inc.personaId,
            contextStartIndex: inc.contextStartIndex,
            memoryOrganizedThrough: inc.memoryOrganizedThrough,
            overrideProviderId: inc.overrideProviderId,
            overrideModel: inc.overrideModel,
            overridePrompt: inc.overridePrompt,
            enabledMcpIds: inc.enabledMcpIds,
            enabledSkillIds: inc.enabledSkillIds,
            workspaceId: inc.workspaceId,
            toolPermissionMode: inc.toolPermissionMode,
            suggestions: inc.suggestions
          };
          byId.set(remappedId, cloned);
          list.push(cloned);
          importedChats++;
          importedMsgs += inc.messages.length;
        }
      }
      next.conversations = list;
    }
  }

  // 2. Providers + Secrets
  const cloneIncomingProvider = (p: Provider): Provider => {
    const newPool: ApiKeyEntry[] = [];
    if (p.apiKeys) {
      for (let k = 0; k < p.apiKeys.length; k++) {
        const ak = p.apiKeys[k];
        const nr = remapRef(ak.secretRef, isHarmonySource);
        if (nr || isHarmonySource) {
          newPool.push({
            id: ak.id,
            label: ak.label,
            secretRef: nr,
            priority: ak.priority,
            usageCount: ak.usageCount,
            errorCount: ak.errorCount,
            disabledUntil: ak.disabledUntil
          });
        }
      }
    }
    return {
      id: p.id,
      name: p.name,
      family: p.family,
      baseUrl: p.baseUrl,
      chatPath: p.chatPath,
      model: p.model,
      secretRef: remapRef(p.secretRef, isHarmonySource),
      models: p.models ? p.models.slice() : [],
      apiKeys: newPool,
      keyStrategy: p.keyStrategy,
      groupName: p.groupName,
      proxy: p.proxy ? {
        enabled: p.proxy.enabled,
        type: normalizeProxyType(p.proxy.type),
        host: p.proxy.host,
        port: p.proxy.port,
        username: p.proxy.username,
        passwordRef: remapRef(p.proxy.passwordRef, isHarmonySource) || undefined,
        bypass: p.proxy.bypass
      } : undefined,
      customHeaders: p.customHeaders ? p.customHeaders.slice() : undefined,
      customBodyJson: p.customBodyJson,
      promptCaching: p.promptCaching,
      sendConversationCacheKey: p.sendConversationCacheKey,
      balanceUrl: p.balanceUrl,
      lastBalance: p.lastBalance,
      builtinSearch: p.builtinSearch,
      builtinUrlContext: p.builtinUrlContext,
      builtinCodeExec: p.builtinCodeExec,
      builtinImageGen: p.builtinImageGen,
      oauth: p.oauth ? {
        kind: p.oauth.kind,
        accountEmail: p.oauth.accountEmail,
        accessTokenRef: remapRef(p.oauth.accessTokenRef, isHarmonySource),
        refreshTokenRef: remapRef(p.oauth.refreshTokenRef, isHarmonySource),
        expiresAt: p.oauth.expiresAt,
        quotaSummary: p.oauth.quotaSummary
      } : undefined,
      enabled: p.enabled !== false
    };
  };

  if (allowCategory(scope.providers, Array.isArray(incoming.providers), srcScope?.providers)) {
    const incProvs = incoming.providers || [];
    const prepared: Provider[] = [];
    for (let i = 0; i < incProvs.length; i++) {
      prepared.push(cloneIncomingProvider(incProvs[i]));
    }
    if (mode === 'overwrite') {
      if (prepared.length > 0) {
        next.providers = prepared;
        importedProviders = prepared.length;
        if (incoming.activeProvider) next.activeProvider = incoming.activeProvider;
      }
      if (incoming.favoriteModels) next.favoriteModels = incoming.favoriteModels.slice();
    } else {
      const byId = new Map<string, number>();
      for (let i = 0; i < next.providers.length; i++) byId.set(next.providers[i].id, i);
      for (let i = 0; i < prepared.length; i++) {
        const inc = prepared[i];
        const idx = byId.get(inc.id);
        if (idx === undefined) {
          byId.set(inc.id, next.providers.length);
          next.providers.push(inc);
          importedProviders++;
        } else {
          // If existing provider had no key at all and incoming brings a configured key, enrich it cleanly
          const cur = next.providers[idx];
          if (!cur.secretRef && (!cur.apiKeys || cur.apiKeys.length === 0) && (inc.secretRef || (inc.apiKeys && inc.apiKeys.length > 0))) {
            next.providers[idx] = inc;
            importedProviders++;
          }
        }
      }
      if (incoming.favoriteModels && incoming.favoriteModels.length > 0) {
        const favSet = new Set<string>(next.favoriteModels || []);
        for (let i = 0; i < incoming.favoriteModels.length; i++) favSet.add(incoming.favoriteModels[i]);
        next.favoriteModels = Array.from(favSet);
      }
    }
  }

  // 3. Assistants
  if (allowCategory(scope.assistants, Array.isArray(incoming.personas), srcScope?.assistants)) {
    const incAssts = incoming.personas || [];
    if (mode === 'overwrite' && incAssts.length > 0) {
      next.personas = incAssts.slice();
      importedAssistants = incAssts.length;
    } else {
      const seen = new Set<string>(next.personas.map((p: Persona): string => p.id));
      for (let i = 0; i < incAssts.length; i++) {
        if (!seen.has(incAssts[i].id)) {
          seen.add(incAssts[i].id);
          next.personas.push(incAssts[i]);
          importedAssistants++;
        }
      }
    }
  }

  // 4. MCP Servers
  if (allowCategory(scope.mcp, Array.isArray(incoming.mcpServers), srcScope?.mcp)) {
    const incMcp = incoming.mcpServers || [];
    const preparedMcp: McpServerConfig[] = [];
    for (let i = 0; i < incMcp.length; i++) {
      const m = incMcp[i];
      preparedMcp.push({
        id: m.id,
        name: m.name,
        transport: m.transport,
        endpoint: m.endpoint,
        bearerSecretRef: remapRef(m.bearerSecretRef, isHarmonySource),
        customHeaders: m.customHeaders ? m.customHeaders.slice() : [],
        oauthAccessTokenRef: remapRef(m.oauthAccessTokenRef, isHarmonySource) || undefined,
        enabled: m.enabled,
        disabledTools: m.disabledTools ? m.disabledTools.slice() : [],
        autoApproveTools: m.autoApproveTools ? m.autoApproveTools.slice() : []
      });
    }
    if (mode === 'overwrite') {
      next.mcpServers = preparedMcp;
      if (incoming.mcpEndpoint !== undefined) next.mcpEndpoint = incoming.mcpEndpoint;
    } else {
      const seen = new Set<string>((next.mcpServers || []).map((m: McpServerConfig): string => m.id));
      for (let i = 0; i < preparedMcp.length; i++) {
        if (!seen.has(preparedMcp[i].id)) {
          seen.add(preparedMcp[i].id);
          next.mcpServers!.push(preparedMcp[i]);
        }
      }
    }
  }

  // 5. Env Vars
  if (allowCategory(scope.envVars, Array.isArray(incoming.envVars), srcScope?.envVars)) {
    const incEnv = incoming.envVars || [];
    const preparedEnv: EnvVar[] = [];
    for (let i = 0; i < incEnv.length; i++) {
      const e = incEnv[i];
      const nr = remapRef(e.secretRef, isHarmonySource);
      if (!nr) continue;
      preparedEnv.push({ id: e.id, key: e.key, secretRef: nr, masked: e.masked });
    }
    if (mode === 'overwrite') {
      next.envVars = preparedEnv;
    } else {
      const seenKeys = new Set<string>((next.envVars || []).map((e: EnvVar): string => e.key));
      for (let i = 0; i < preparedEnv.length; i++) {
        if (!seenKeys.has(preparedEnv[i].key)) {
          seenKeys.add(preparedEnv[i].key);
          next.envVars!.push(preparedEnv[i]);
        }
      }
    }
  }

  // 6. Skills
  if (allowCategory(scope.skills, Array.isArray(incoming.skills), srcScope?.skills)) {
    const incSkills = incoming.skills || [];
    if (mode === 'overwrite') {
      next.skills = incSkills.slice();
    } else {
      const seen = new Set<string>((next.skills || []).map((s: SkillRecord): string => s.id));
      for (let i = 0; i < incSkills.length; i++) {
        if (!seen.has(incSkills[i].id)) {
          seen.add(incSkills[i].id);
          next.skills!.push(incSkills[i]);
        }
      }
    }
  }

  // 7. WorldBooks
  if (allowCategory(scope.worldBooks, Array.isArray(incoming.worldBooks), srcScope?.worldBooks)) {
    const incWb = normalizeWorldBooks(incoming.worldBooks || []);
    if (mode === 'overwrite') {
      next.worldBooks = incWb.slice();
    } else {
      next.worldBooks = normalizeWorldBooks(next.worldBooks);
      const seen = new Set<string>((next.worldBooks || []).map((w: WorldBook): string => w.id));
      for (let i = 0; i < incWb.length; i++) {
        if (!seen.has(incWb[i].id)) {
          seen.add(incWb[i].id);
          next.worldBooks!.push(incWb[i]);
        }
      }
    }
  }

  // 8. Memory + UserProfile + Settings
  if (allowCategory(scope.memory, Array.isArray(incoming.memories) || Array.isArray(incoming.userProfile) || Boolean(incoming.memorySettings),
    srcScope?.memory)) {
    if (Array.isArray(incoming.memories)) {
      const normIncMems = normalizeMemoryEntries(incoming.memories);
      if (mode === 'overwrite') {
        next.memories = normIncMems;
      } else {
        const seen = new Set<string>((next.memories || []).map((m: MemoryEntry): string => m.id));
        for (let i = 0; i < normIncMems.length; i++) {
          if (!seen.has(normIncMems[i].id)) {
            seen.add(normIncMems[i].id);
            next.memories!.push(normIncMems[i]);
          }
        }
      }
    }
    if (Array.isArray(incoming.userProfile)) {
      const normIncProf = normalizeUserProfileFields(incoming.userProfile);
      if (mode === 'overwrite') {
        next.userProfile = normIncProf;
      } else {
        next.userProfile = normalizeUserProfileFields((next.userProfile || []).concat(normIncProf));
      }
    }
    if (incoming.memorySettings) {
      if (mode === 'overwrite' || !next.memorySettings) {
        next.memorySettings = normalizeMemorySettings(incoming.memorySettings);
      } else {
        const cur = normalizeMemorySettings(next.memorySettings);
        const inc = normalizeMemorySettings(incoming.memorySettings);
        next.memorySettings = {
          autoExtract: cur.autoExtract,
          injectGlobal: cur.injectGlobal,
          maxInjectCount: inc.maxInjectCount || cur.maxInjectCount,
          useLegacyMemory: inc.useLegacyMemory ?? cur.useLegacyMemory,
          enableThinking: inc.enableThinking ?? cur.enableThinking,
          promptLanguage: inc.promptLanguage || cur.promptLanguage,
          recordTraces: inc.recordTraces ?? cur.recordTraces,
          templates: inc.templates || cur.templates,
          legacyMemories: inc.legacyMemories || cur.legacyMemories
        };
      }
    }
    if (incoming.modelDefaults?.memoryProviderId && incoming.modelDefaults?.memoryModelId) {
      const curMd = next.modelDefaults;
      if (curMd) {
        if (mode === 'overwrite' || !curMd.memoryProviderId) {
          next.modelDefaults = {
            chatProviderId: curMd.chatProviderId,
            chatModelId: curMd.chatModelId,
            perChatModel: curMd.perChatModel,
            titleProviderId: curMd.titleProviderId,
            titleModelId: curMd.titleModelId,
            summaryProviderId: curMd.summaryProviderId,
            summaryModelId: curMd.summaryModelId,
            suggestionsProviderId: curMd.suggestionsProviderId,
            suggestionsModelId: curMd.suggestionsModelId,
            compressProviderId: curMd.compressProviderId,
            compressModelId: curMd.compressModelId,
            translateProviderId: curMd.translateProviderId,
            translateModelId: curMd.translateModelId,
            ocrProviderId: curMd.ocrProviderId,
            ocrModelId: curMd.ocrModelId,
            memoryProviderId: incoming.modelDefaults.memoryProviderId,
            memoryModelId: incoming.modelDefaults.memoryModelId
          };
        }
      } else {
        next.modelDefaults = {
          chatProviderId: '',
          chatModelId: '',
          titleProviderId: '',
          titleModelId: '',
          translateProviderId: '',
          translateModelId: '',
          ocrProviderId: '',
          ocrModelId: '',
          memoryProviderId: incoming.modelDefaults.memoryProviderId,
          memoryModelId: incoming.modelDefaults.memoryModelId
        };
      }
    }
  }

  // 9. Quick Phrases
  if (allowCategory(scope.quickPhrases, Array.isArray(incoming.quickPhrases), srcScope?.quickPhrases)) {
    const incQp = normalizeQuickPhrases(incoming.quickPhrases || []);
    if (mode === 'overwrite') {
      next.quickPhrases = incQp.slice();
    } else {
      next.quickPhrases = normalizeQuickPhrases(next.quickPhrases);
      const seen = new Set<string>((next.quickPhrases || []).map((q: QuickPhrase): string => q.id));
      for (let i = 0; i < incQp.length; i++) {
        if (!seen.has(incQp[i].id)) {
          seen.add(incQp[i].id);
          next.quickPhrases!.push(incQp[i]);
        }
      }
    }
  }

  // 10. Instruction Cards
  if (allowCategory(scope.instructions, Array.isArray(incoming.instructionCards), srcScope?.instructions)) {
    const incCards = normalizeInstructionCards(incoming.instructionCards || []);
    if (mode === 'overwrite') {
      next.instructionCards = incCards.slice();
      if (incoming.activeInstructionIds) next.activeInstructionIds = incoming.activeInstructionIds.slice();
    } else {
      next.instructionCards = normalizeInstructionCards(next.instructionCards);
      const seen = new Set<string>((next.instructionCards || []).map((c: InstructionCard): string => c.id));
      for (let i = 0; i < incCards.length; i++) {
        if (!seen.has(incCards[i].id)) {
          seen.add(incCards[i].id);
          next.instructionCards!.push(incCards[i]);
        }
      }
    }
  }

  // 11. Workspaces
  if (allowCategory(scope.workspaces, Array.isArray(incoming.workspaces), srcScope?.workspaces)) {
    const incWs = incoming.workspaces || [];
    if (mode === 'overwrite') {
      next.workspaces = incWs.slice();
    } else {
      const seen = new Set<string>((next.workspaces || []).map((w: LocalWorkspace): string => w.id));
      for (let i = 0; i < incWs.length; i++) {
        if (!seen.has(incWs[i].id)) {
          seen.add(incWs[i].id);
          next.workspaces!.push(incWs[i]);
        }
      }
    }
  }

  // 12. Search Services
  if (allowCategory(scope.search, Array.isArray(incoming.searchServices), srcScope?.search)) {
    const incSearch = incoming.searchServices || [];
    const preparedSearch: SearchServiceConfig[] = [];
    for (let i = 0; i < incSearch.length; i++) {
      const s = incSearch[i];
      const newKeys: ApiKeyEntry[] = [];
      for (let k = 0; k < s.apiKeys.length; k++) {
        const nr = remapRef(s.apiKeys[k].secretRef, isHarmonySource);
        if (nr || isHarmonySource) {
          newKeys.push({
            id: s.apiKeys[k].id,
            label: s.apiKeys[k].label,
            secretRef: nr,
            priority: s.apiKeys[k].priority,
            usageCount: s.apiKeys[k].usageCount,
            errorCount: s.apiKeys[k].errorCount,
            disabledUntil: s.apiKeys[k].disabledUntil
          });
        }
      }
      preparedSearch.push({
        id: s.id,
        kind: s.kind,
        name: s.name,
        endpoint: s.endpoint,
        apiKeys: newKeys,
        keyStrategy: s.keyStrategy,
        maxResults: s.maxResults,
        enabled: s.enabled,
        mode: s.mode,
        webFetchEnabled: s.webFetchEnabled
      });
    }
    if (mode === 'overwrite') {
      next.searchServices = preparedSearch;
      if (incoming.activeSearchId) next.activeSearchId = incoming.activeSearchId;
    } else {
      const seen = new Set<string>((next.searchServices || []).map((s: SearchServiceConfig): string => s.id));
      for (let i = 0; i < preparedSearch.length; i++) {
        if (!seen.has(preparedSearch[i].id)) {
          seen.add(preparedSearch[i].id);
          next.searchServices!.push(preparedSearch[i]);
        }
      }
    }
  }

  // 13. Speech Services (TTS / ASR)
  if (allowCategory(scope.speech, Boolean(incoming.tts || incoming.asr), srcScope?.speech)) {
    if (incoming.tts && (mode === 'overwrite' || !next.tts || next.tts.engine === 'system')) {
      next.tts = {
        engine: incoming.tts.engine,
        endpoint: incoming.tts.endpoint,
        secretRef: remapRef(incoming.tts.secretRef, isHarmonySource),
        model: incoming.tts.model,
        voice: incoming.tts.voice,
        speed: incoming.tts.speed,
        language: incoming.tts.language,
        region: incoming.tts.region
      };
    }
    if (incoming.asr && (mode === 'overwrite' || !next.asr || next.asr.engine === 'system')) {
      next.asr = {
        engine: incoming.asr.engine,
        endpoint: incoming.asr.endpoint,
        secretRef: remapRef(incoming.asr.secretRef, isHarmonySource),
        model: incoming.asr.model,
        language: incoming.asr.language
      };
    }
  }

  // 14. Settings
  if (scope.settings && (srcScope === undefined || srcScope.settings)) {
    if (incoming.generationParams && (mode === 'overwrite' || !next.generationParams)) {
      next.generationParams = incoming.generationParams;
    }
    if (incoming.modelDefaults) {
      if (mode === 'overwrite' || !next.modelDefaults?.chatProviderId) {
        const preservedMemProv = next.modelDefaults?.memoryProviderId || '';
        const preservedMemModel = next.modelDefaults?.memoryModelId || '';
        const incMd = incoming.modelDefaults;
        next.modelDefaults = {
          chatProviderId: incMd.chatProviderId || (next.modelDefaults?.chatProviderId || ''),
          chatModelId: incMd.chatModelId || (next.modelDefaults?.chatModelId || ''),
          perChatModel: incMd.perChatModel,
          titleProviderId: incMd.titleProviderId,
          titleModelId: incMd.titleModelId,
          summaryProviderId: incMd.summaryProviderId,
          summaryModelId: incMd.summaryModelId,
          suggestionsProviderId: incMd.suggestionsProviderId,
          suggestionsModelId: incMd.suggestionsModelId,
          compressProviderId: incMd.compressProviderId,
          compressModelId: incMd.compressModelId,
          translateProviderId: incMd.translateProviderId,
          translateModelId: incMd.translateModelId,
          ocrProviderId: incMd.ocrProviderId,
          ocrModelId: incMd.ocrModelId,
          memoryProviderId: incMd.memoryProviderId || preservedMemProv,
          memoryModelId: incMd.memoryModelId || preservedMemModel
        };
      }
    }
    if (incoming.appearance && mode === 'overwrite') {
      next.appearance = incoming.appearance;
    }
    if (incoming.systemSettings && mode === 'overwrite') {
      next.systemSettings = incoming.systemSettings;
    }
    if (incoming.toolOverrides && mode === 'overwrite') {
      next.toolOverrides = incoming.toolOverrides;
    }
    if (incoming.scheduledTasks && mode === 'overwrite') {
      next.scheduledTasks = incoming.scheduledTasks;
    }
    if (incoming.userName && (mode === 'overwrite' || !next.userName || next.userName === '用户')) {
      next.userName = incoming.userName;
    }
    if (incoming.globalProxy && (mode === 'overwrite' || !next.globalProxy?.host)) {
      const normGp = normalizeProxyConfig(incoming.globalProxy, true);
      normGp.passwordRef = remapRef(normGp.passwordRef, isHarmonySource) || undefined;
      next.globalProxy = normGp;
    }
  }

  const summary = mode === 'overwrite'
    ? ('已覆盖恢复（' + importedChats + ' 段对话 · ' + importedProviders + ' 个供应商）')
    : ('已合并导入 ' + importedChats + ' 段对话、' + importedProviders + ' 个供应商、' + importedAssistants + ' 个助手');

  return {
    workspace: next,
    stats: {
      providers: importedProviders,
      assistants: importedAssistants,
      conversations: importedChats,
      messages: importedMsgs,
      files: 0
    },
    secretsToStore: outSecrets,
    summary
  };
}
