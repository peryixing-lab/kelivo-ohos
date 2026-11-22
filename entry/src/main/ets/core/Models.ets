export type ApiFamily = 'openai' | 'openai-responses' | 'anthropic' | 'gemini' | 'vertex';

export type KeyRotationStrategy = 'round_robin' | 'priority' | 'least_used' | 'random';

export type ReasoningEffort = 'off' | 'low' | 'medium' | 'high' | 'max';

export type ResponseSpeedMode = 'standard' | 'fast' | 'ultrafast';

export type ToolPermissionMode = 'ask' | 'full';

export type AttachmentKind = 'text' | 'image' | 'pdf' | 'docx' | 'audio';

export type OAuthProviderKind = 'chatgpt' | 'grok' | 'kimi' | 'claude';

export interface ModelSpec {
  id: string;
  displayName: string;
  groupName?: string;
  vision: boolean;
  tools: boolean;
  reasoning: boolean;
  imageGen: boolean;
  contextWindow: number;
  maxOutputTokens: number;
  enabled: boolean;
}

export interface ApiKeyEntry {
  id: string;
  label: string;
  secretRef: string;
  priority: number;
  usageCount: number;
  errorCount: number;
  disabledUntil: number;
}

export interface ProxyConfig {
  enabled: boolean;
  host: string;
  port: number;
  username?: string;
  passwordRef?: string;
}

export interface HeaderEntry {
  key: string;
  value: string;
}

export interface OAuthAccountInfo {
  kind: OAuthProviderKind;
  accountEmail: string;
  accessTokenRef: string;
  refreshTokenRef: string;
  expiresAt: number;
  quotaSummary: string;
}

export interface GenerationParams {
  temperature?: number;
  topP?: number;
  maxTokens?: number;
  reasoningEffort?: ReasoningEffort;
  reasoningBudget?: number;
  responseSpeed?: ResponseSpeedMode;
  contextLimit?: number;
  autoRetryCount?: number;
  retryBaseMs?: number;
}

export interface ModelDefaults {
  chatProviderId: string;
  chatModelId: string;
  perChatModel?: boolean;
  titleProviderId: string;
  titleModelId: string;
  summaryProviderId?: string;
  summaryModelId?: string;
  suggestionsProviderId?: string;
  suggestionsModelId?: string;
  compressProviderId?: string;
  compressModelId?: string;
  translateProviderId: string;
  translateModelId: string;
  ocrProviderId: string;
  ocrModelId: string;
  memoryProviderId: string;
  memoryModelId: string;
}

export interface Provider {
  id: string;
  name: string;
  family: ApiFamily;
  baseUrl: string;
  chatPath?: string;
  model: string;
  secretRef: string;
  models?: ModelSpec[];
  apiKeys?: ApiKeyEntry[];
  keyStrategy?: KeyRotationStrategy;
  groupName?: string;
  proxy?: ProxyConfig;
  customHeaders?: HeaderEntry[];
  customBodyJson?: string;
  promptCaching?: boolean;
  sendConversationCacheKey?: boolean;
  balanceUrl?: string;
  lastBalance?: string;
  builtinSearch?: boolean;
  builtinUrlContext?: boolean;
  builtinCodeExec?: boolean;
  builtinImageGen?: boolean;
  oauth?: OAuthAccountInfo;
  enabled?: boolean;
}

export interface PresetMessage {
  id: string;
  role: 'user' | 'assistant' | 'system';
  content: string;
}

export interface QuickPhrase {
  id: string;
  title: string;
  content: string;
  scope?: 'global' | 'assistant';
}

export interface RegexRule {
  id: string;
  name: string;
  pattern: string;
  replacement: string;
  flags: string;
  scope: 'input' | 'output' | 'display';
  enabled: boolean;
}

export interface Persona {
  id: string;
  name: string;
  prompt: string;
  avatar?: string;
  tags?: string[];
  providerId?: string;
  modelId?: string;
  params?: GenerationParams;
  presetMessages?: PresetMessage[];
  customHeaders?: HeaderEntry[];
  customBodyJson?: string;
  mcpServerIds?: string[];
  skillIds?: string[];
  builtinTools?: string[];
  workspaceId?: string;
  quickPhrases?: QuickPhrase[];
  regexRules?: RegexRule[];
  chatBackground?: string;
  memoryEnabled?: boolean;
  autoOrganizeMemory?: boolean;
  memoryOrganizeEveryNTurns?: number;
  memoryFullInjectionTypes?: MemoryCategory[];
  memoryWriteScope?: MemoryWriteScope;
  memorySmartAddMode?: MemorySmartAddMode;
  allowPastConversationRecall?: boolean;
  generateConversationSummary?: boolean;
  recentChatsSummaryMessageCount?: number;
  worldBookIds?: string[];
  useAssistantAvatar?: boolean;
  useAssistantName?: boolean;
  streamOutput?: boolean;
  allowConversationSystemPrompt?: boolean;
  allowConversationPromptInjection?: boolean;
  appendCurrentTimeToUserMessage?: boolean;
  allowConversationMcp?: boolean;
  useGradientBackground?: boolean;
}

export interface Attachment {
  name: string;
  mime: string;
  data: string;
  id?: string;
  filePath?: string;
  sizeBytes?: number;
  kind?: AttachmentKind;
}

export interface SearchConfig {
  kind: string;
  endpoint: string;
  secretRef: string;
}

export interface SearchServiceConfig {
  id: string;
  kind: string;
  name: string;
  endpoint: string;
  apiKeys: ApiKeyEntry[];
  keyStrategy: KeyRotationStrategy;
  maxResults: number;
  enabled: boolean;
  mode: 'agent_tool' | 'pre_search';
  webFetchEnabled: boolean;
}

export interface SearchHit {
  title: string;
  url: string;
  excerpt: string;
}

export interface TokenUsage {
  promptTokens: number;
  completionTokens: number;
  cachedTokens: number;
  totalTokens: number;
  durationMs: number;
}

export interface ToolCallRecord {
  id: string;
  name: string;
  argsJson: string;
  status: 'pending' | 'running' | 'done' | 'error' | 'denied';
  resultText: string;
  diffText?: string;
  imageAttachments?: Attachment[];
  durationMs: number;
}

export interface QuoteRef {
  messageId: string;
  excerpt: string;
}

export interface MessageVersion {
  id: string;
  text: string;
  reasoning: string;
  model: string;
  createdAt: number;
  usage?: TokenUsage;
  toolCalls?: ToolCallRecord[];
  generatedImages?: Attachment[];
  sources?: SearchHit[];
  translation?: string;
}

export interface ChatMessage {
  id: string;
  role: 'user' | 'assistant';
  text: string;
  model: string;
  attachment?: Attachment;
  reasoning?: string;
  sources?: SearchHit[];
  attachments?: Attachment[];
  createdAt?: number;
  usage?: TokenUsage;
  toolCalls?: ToolCallRecord[];
  generatedImages?: Attachment[];
  quote?: QuoteRef;
  translation?: string;
  versions?: MessageVersion[];
  activeVersion?: number;
  isSummary?: boolean;
  compressedCount?: number;
  compressionSnapshot?: ChatMessage[];
}

export interface Conversation {
  id: string;
  title: string;
  updated: number;
  pinned?: boolean;
  messages: ChatMessage[];
  personaId: string;
  ephemeral?: boolean;
  contextStartIndex?: number;
  memoryOrganizedThrough?: string;
  overrideProviderId?: string;
  overrideModel?: string;
  overridePrompt?: string;
  enabledMcpIds?: string[];
  enabledSkillIds?: string[];
  workspaceId?: string;
  toolPermissionMode?: ToolPermissionMode;
  draftText?: string;
  imageGenMode?: boolean;
  suggestions?: string[];
}

export interface McpServerConfig {
  id: string;
  name: string;
  transport: 'streamable-http' | 'sse';
  endpoint: string;
  bearerSecretRef: string;
  customHeaders: HeaderEntry[];
  oauthAccessTokenRef?: string;
  enabled: boolean;
  disabledTools: string[];
  autoApproveTools: string[];
}

export type TtsEngineKind = 'system' | 'openai' | 'gemini' | 'azure' | 'elevenlabs' | 'minimax' | 'qwen' | 'groq' | 'xai' | 'mimo' | 'stepfun' | 'fishaudio';

export type AsrEngineKind = 'system' | 'openai' | 'groq' | 'dashscope' | 'volcengine' | 'mimo' | 'stepfun';

export interface TtsConfig {
  engine: TtsEngineKind;
  endpoint: string;
  secretRef: string;
  model: string;
  voice: string;
  speed: number;
  language: string;
  region?: string;
}

export interface AsrConfig {
  engine: AsrEngineKind;
  endpoint: string;
  secretRef: string;
  model: string;
  language: string;
}

export type MemoryWriteScope = 'alwaysGlobal' | 'alwaysAssistant' | 'toolDefaultGlobal' | 'toolDefaultAssistant';

export type MemorySmartAddMode = 'batched' | 'perItem';

export type MemoryPromptLanguage = 'auto' | 'zh' | 'en';

export type MemorySourceKind = 'manual' | 'extracted' | 'tool';

export type MemoryCategory = 'identity' | 'workflow' | 'tone' | 'instruction';

export interface MemoryEntry {
  id: string;
  category: MemoryCategory;
  content: string;
  assistantId?: string;
  archived: boolean;
  createdAt: number;
  updatedAt: number;
  sourceConversationId?: string;
  source?: MemorySourceKind;
  relatedIds?: string[];
}

export interface UserProfileField {
  id: string;
  key: string;
  value: string;
  updatedAt: number;
  source?: string;
}

export interface MemoryTraceStep {
  stage: string;
  prompt?: string;
  response?: string;
  summary: string;
  durationMs?: number;
  status?: 'success' | 'skipped' | 'failed';
  error?: string;
}

export interface MemoryTrace {
  id: string;
  ts: number;
  conversationId: string;
  assistantId?: string;
  modelId?: string;
  trigger?: 'auto' | 'manual';
  gatekeeperPassed: boolean;
  advanced?: boolean;
  error?: string;
  extractedCount: number;
  mergedCount: number;
  conflictCount?: number;
  skippedCount?: number;
  profileUpdatedCount?: number;
  summary: string;
  steps?: MemoryTraceStep[];
}

export interface MemoryPromptTemplates {
  rulesZh?: string;
  rulesEn?: string;
  gateZh?: string;
  gateEn?: string;
  extractZh?: string;
  extractEn?: string;
  smartAddSingleZh?: string;
  smartAddSingleEn?: string;
  smartAddBatchZh?: string;
  smartAddBatchEn?: string;
  profileDistillZh?: string;
  profileDistillEn?: string;
  legacyMigrateZh?: string;
  legacyMigrateEn?: string;
}

export interface MemorySettings {
  autoExtract: boolean;
  injectGlobal: boolean;
  maxInjectCount: number;
  useLegacyMemory?: boolean;
  enableThinking?: boolean;
  promptLanguage?: MemoryPromptLanguage;
  recordTraces?: boolean;
  templates?: MemoryPromptTemplates;
  legacyMemories?: string[];
}

export type WorldBookPosition = 'before_system' | 'after_system' | 'before_last_user' | 'at_depth';

export interface WorldBookEntry {
  id: string;
  name: string;
  keys: string[];
  useRegex: boolean;
  content: string;
  position: WorldBookPosition;
  role: 'system' | 'user' | 'assistant';
  depth: number;
  enabled: boolean;
  alwaysActive: boolean;
}

export interface WorldBook {
  id: string;
  name: string;
  description: string;
  enabled: boolean;
  entries: WorldBookEntry[];
}

export interface InstructionCard {
  id: string;
  title: string;
  description: string;
  content: string;
  builtin: boolean;
}

export interface SkillRecord {
  id: string;
  name: string;
  description: string;
  markdown: string;
  source: 'builtin' | 'local' | 'github';
  sourceUrl?: string;
  enabled: boolean;
  updatedAt: number;
}

export interface LocalWorkspace {
  id: string;
  name: string;
  rootPath: string;
  createdAt: number;
}

export interface EnvVar {
  id: string;
  key: string;
  secretRef: string;
  masked: boolean;
}

export interface ScheduledTask {
  id: string;
  name: string;
  personaId: string;
  providerId: string;
  modelId: string;
  prompt: string;
  scheduleType: 'daily' | 'weekly' | 'interval' | 'once';
  timeHHMM: string;
  weekdays: number[];
  intervalMinutes: number;
  runAtMs: number;
  enabled: boolean;
  lastRunAt: number;
  lastStatus: string;
  lastConversationId: string;
}

export interface BrowserBookmark {
  id: string;
  title: string;
  url: string;
  createdAt: number;
}

export interface ChatItemDisplayConfig {
  showUserAvatar: boolean;
  showUserName: boolean;
  showUserTimestamp: boolean;
  showUserMessageActions: boolean;
  showModelIcon: boolean;
  showAssistantAvatarInTitleBar: boolean;
  showModelName: boolean;
  showModelTimestamp: boolean;
  showProviderAfterModelName: boolean;
  showTokenStats: boolean;
  showThinkingCards: boolean;
  showToolCards: boolean;
  showFilesBelowReplies: boolean;
  showReasoningLevelOnButton: boolean;
}

export interface AppearanceConfig {
  themeMode: 'system' | 'light' | 'dark';
  paletteId: string;
  customThemeJson?: string;
  bubbleStyle: 'default' | 'frosted' | 'solid';
  bubbleRadius: number;
  bubbleBlur: number;
  wallpaperKind: 'none' | 'gradient' | 'image';
  wallpaperValue: string;
  wallpaperOpacity: number;
  fontScale: number;
  codeFontSize: number;
  language: 'zh-Hans' | 'zh-Hant' | 'en' | 'ko' | 'ru' | 'tr';
  immersiveLightEnabled?: boolean;
  pureBackground?: boolean;
  fitAssistantBubble?: boolean;
  splitParagraphsIntoBubbles?: boolean;
  inputBoxOpacity?: number;
  chatItemDisplay?: ChatItemDisplayConfig;
  collapseLongUserChars?: number;
  enableAssistantMarkdown?: boolean;
  enableUserMarkdown?: boolean;
  enableReasoningMarkdown?: boolean;
  enableMathLatex?: boolean;
  autoFollowBottom?: boolean;
  insertSuggestionOnly?: boolean;
  enterToSend?: boolean;
}

export interface BackupScopeConfig {
  chats: boolean;
  attachments: boolean;
  assistants: boolean;
  providers: boolean;
  mcp: boolean;
  envVars: boolean;
  skills: boolean;
  worldBooks: boolean;
  memory: boolean;
  quickPhrases: boolean;
  instructions: boolean;
  workspaces: boolean;
  search: boolean;
  speech: boolean;
  settings: boolean;
}

export interface BackupPreferencesConfig {
  scope: BackupScopeConfig;
  encryptionEnabled: boolean;
  rememberPassword: boolean;
  passwordVerifier?: string;
  passwordSecretRef?: string;
  reminderEnabled: boolean;
  reminderIntervalDays: number;
  reminderMinutesOfDay: number;
  lastBackupAt?: number;
  localCopiesEnabled: boolean;
  localCopiesIntervalDays: number;
  localCopiesKeepRecent: number;
  localCopiesKeepWeekly: boolean;
  localCopiesKeepMonthly: boolean;
  localCopiesMaxBytes: number;
  localCopiesLastSuccessAt?: number;
  localCopiesLastError?: string;
}

export interface S3BackupConfig {
  endpoint: string;
  region: string;
  bucket: string;
  prefix: string;
  accessKeyId: string;
  secretAccessKeyRef: string;
  sessionTokenRef?: string;
  userAgent?: string;
  pathStyle: boolean;
}

export interface LocalSnapshotMeta {
  id: string;
  fileName: string;
  createdAt: number;
  sizeBytes: number;
  reason: 'auto' | 'manual' | 'pre_restore';
  encrypted: boolean;
  pinned?: boolean;
  conversationCount?: number;
  messageCount?: number;
}

export interface ToolSchemaOverride {
  toolName: string;
  customDescription: string;
  enabled: boolean;
}

export interface SystemSettings {
  autoTitleEnabled: boolean;
  chatSuggestionsEnabled: boolean;
  autoCompactEnabled: boolean;
  autoCompactThreshold: number;
  compressionTemplate: string;
  imageUploadQuality: number;
  hapticsEnabled: boolean;
  keepScreenOn: boolean;
  backgroundNotifyEnabled: boolean;
  autoSnapshotEnabled: boolean;
  builtinFetchEnabled: boolean;
  maxToolSteps: number;
  defaultToolPermission: ToolPermissionMode;
  enabledDeviceTools: string[];
  searchEnabled?: boolean;
}

export interface RequestLogEntry {
  id: string;
  ts: number;
  provider: string;
  model: string;
  url: string;
  status: number;
  durationMs: number;
  reqPreview: string;
  respPreview: string;
  error: string;
}

export interface ContextLogEntry {
  id: string;
  ts: number;
  conversationId: string;
  model: string;
  payloadJson: string;
  tokenEstimate: number;
}

export interface UsageStatRow {
  id: string;
  day: string;
  model: string;
  personaId: string;
  promptTokens: number;
  completionTokens: number;
  cachedTokens: number;
  msgCount: number;
}

export interface Workspace {
  version: number;
  providers: Provider[];
  personas: Persona[];
  conversations: Conversation[];
  search?: SearchConfig;
  searchServices?: SearchServiceConfig[];
  activeSearchId?: string;
  mcpEndpoint?: string;
  mcpServers?: McpServerConfig[];
  davDirectory?: string;
  davPath?: string;
  davFilename?: string;
  davUsername?: string;
  davPasswordRef?: string;
  davUserAgent?: string;
  s3Config?: S3BackupConfig;
  backupConfig?: BackupPreferencesConfig;
  activeProvider: string;
  activeConversation: string;
  generationParams?: GenerationParams;
  modelDefaults?: ModelDefaults;
  tts?: TtsConfig;
  asr?: AsrConfig;
  memories?: MemoryEntry[];
  userProfile?: UserProfileField[];
  memoryTraces?: MemoryTrace[];
  memorySettings?: MemorySettings;
  worldBooks?: WorldBook[];
  instructionCards?: InstructionCard[];
  activeInstructionIds?: string[];
  quickPhrases?: QuickPhrase[];
  skills?: SkillRecord[];
  workspaces?: LocalWorkspace[];
  envVars?: EnvVar[];
  scheduledTasks?: ScheduledTask[];
  browserBookmarks?: BrowserBookmark[];
  appearance?: AppearanceConfig;
  systemSettings?: SystemSettings;
  toolOverrides?: ToolSchemaOverride[];
  snapshots?: LocalSnapshotMeta[];
  userName?: string;
  favoriteModels?: string[];
}

export function defaultModelSpec(id: string): ModelSpec {
  const lower = id.toLowerCase();
  const isVision = /(gpt-4o|gpt-4\.1|gpt-5|gpt-6|claude-3|claude-4|claude-5|claude-sonnet|claude-opus|claude-haiku|gemini|qwen-vl|qwen2\.5-vl|qwen3-vl|glm-4v|glm-4\.5v|grok-2-vision|grok-3|grok-4|vision|vl)/i.test(lower);
  const isReason = /(o1|o3|o4|r1|reasoner|thinking|gpt-5|gpt-6|deepseek-v4|claude-3-7|claude-sonnet-4|claude-opus-4|claude-haiku-4|claude-haiku-5|claude-4|claude-5|gemini-2\.5|gemini-3|gemini-4|qwen3|qwq|glm-z1|glm-5|omen)/i.test(lower);
  const isImageGen = /(dall-e|gpt-image|imagen|flux|stable-diffusion|image-generation|gemini-2\.0-flash-exp-image|gemini-2\.5-flash-image)/i.test(lower);
  const isTools = !/(reasoner|r1|image|tts|whisper|embedding)/i.test(lower);
  return {
    id,
    displayName: id,
    groupName: '',
    vision: isVision,
    tools: isTools,
    reasoning: isReason,
    imageGen: isImageGen,
    contextWindow: 128000,
    maxOutputTokens: 8192,
    enabled: true
  };
}

export function extractUrlHost(url: string): string {
  const stripped = url.trim().replace(/^https?:\/\//i, '');
  const cutSlash = stripped.indexOf('/');
  const cutQuery = stripped.indexOf('?');
  const cutHash = stripped.indexOf('#');
  let end = stripped.length;
  if (cutSlash >= 0 && cutSlash < end) end = cutSlash;
  if (cutQuery >= 0 && cutQuery < end) end = cutQuery;
  if (cutHash >= 0 && cutHash < end) end = cutHash;
  const hostPort = stripped.slice(0, end);
  if (hostPort.startsWith('[')) {
    const closeBracket = hostPort.indexOf(']');
    if (closeBracket >= 0) {
      return hostPort.slice(1, closeBracket).toLowerCase();
    }
  }
  const colonIdx = hostPort.indexOf(':');
  const host = colonIdx >= 0 ? hostPort.slice(0, colonIdx) : hostPort;
  return host.toLowerCase();
}

export function isLocalOrCustomHost(baseUrl: string): boolean {
  const host = extractUrlHost(baseUrl);
  if (!host) return false;
  if (host === 'localhost' || host === '127.0.0.1' || host === '0.0.0.0' || host === '::1') {
    return true;
  }
  if (host.startsWith('10.') || host.startsWith('192.168.')) {
    return true;
  }
  if (/^172\.(1[6-9]|2\d|3[0-1])\./.test(host)) {
    return true;
  }
  return false;
}

export function providerEnabledModels(p: Provider): ModelSpec[] {
  if (p.models && p.models.length > 0) {
    return p.models.filter((m: ModelSpec): boolean => m.enabled);
  }
  if (p.model.trim()) {
    return [defaultModelSpec(p.model.trim())];
  }
  return [];
}

export function isProviderConfigured(p: Provider): boolean {
  if (p.secretRef || p.oauth || (p.apiKeys && p.apiKeys.length > 0)) {
    return true;
  }
  if (isLocalOrCustomHost(p.baseUrl)) {
    return Boolean(p.model.trim()) || Boolean(p.models && p.models.some((m: ModelSpec): boolean => m.enabled));
  }
  return false;
}

export function preset(id: string, name: string, family: ApiFamily, baseUrl: string, model: string): Provider {
  return {
    id,
    name,
    family,
    baseUrl,
    chatPath: '',
    model,
    secretRef: '',
    models: model ? [defaultModelSpec(model)] : [],
    apiKeys: [],
    keyStrategy: 'round_robin',
    enabled: true
  };
}

export function defaultGenerationParams(): GenerationParams {
  return {
    temperature: 0.7,
    topP: 1.0,
    maxTokens: 4096,
    reasoningEffort: 'off',
    reasoningBudget: 8192,
    responseSpeed: 'standard',
    contextLimit: 24,
    autoRetryCount: 2,
    retryBaseMs: 800
  };
}

export function defaultChatItemDisplay(): ChatItemDisplayConfig {
  return {
    showUserAvatar: true,
    showUserName: true,
    showUserTimestamp: true,
    showUserMessageActions: true,
    showModelIcon: true,
    showAssistantAvatarInTitleBar: false,
    showModelName: true,
    showModelTimestamp: true,
    showProviderAfterModelName: false,
    showTokenStats: true,
    showThinkingCards: true,
    showToolCards: true,
    showFilesBelowReplies: true,
    showReasoningLevelOnButton: false
  };
}

export function defaultAppearance(): AppearanceConfig {
  return {
    themeMode: 'system',
    paletteId: 'default',
    bubbleStyle: 'default',
    bubbleRadius: 18,
    bubbleBlur: 12,
    wallpaperKind: 'none',
    wallpaperValue: '',
    wallpaperOpacity: 0.16,
    fontScale: 1.0,
    codeFontSize: 13,
    language: 'zh-Hans',
    immersiveLightEnabled: true,
    pureBackground: false,
    fitAssistantBubble: false,
    splitParagraphsIntoBubbles: false,
    inputBoxOpacity: 0.88,
    chatItemDisplay: defaultChatItemDisplay(),
    collapseLongUserChars: 0,
    enableAssistantMarkdown: true,
    enableUserMarkdown: true,
    enableReasoningMarkdown: true,
    enableMathLatex: true,
    autoFollowBottom: true,
    insertSuggestionOnly: false,
    enterToSend: false
  };
}

export function normalizeChatItemDisplay(raw?: ChatItemDisplayConfig): ChatItemDisplayConfig {
  const def = defaultChatItemDisplay();
  if (!raw) return def;
  return {
    showUserAvatar: raw.showUserAvatar !== false,
    showUserName: raw.showUserName !== false,
    showUserTimestamp: raw.showUserTimestamp !== false,
    showUserMessageActions: raw.showUserMessageActions !== false,
    showModelIcon: raw.showModelIcon !== false,
    showAssistantAvatarInTitleBar: raw.showAssistantAvatarInTitleBar === true,
    showModelName: raw.showModelName !== false,
    showModelTimestamp: raw.showModelTimestamp !== false,
    showProviderAfterModelName: raw.showProviderAfterModelName === true,
    showTokenStats: raw.showTokenStats !== false,
    showThinkingCards: raw.showThinkingCards !== false,
    showToolCards: raw.showToolCards !== false,
    showFilesBelowReplies: raw.showFilesBelowReplies !== false,
    showReasoningLevelOnButton: raw.showReasoningLevelOnButton === true
  };
}

export function normalizeAppearanceConfig(raw?: AppearanceConfig): AppearanceConfig {
  const def = defaultAppearance();
  if (!raw) return def;
  return {
    themeMode: raw.themeMode || def.themeMode,
    paletteId: raw.paletteId || def.paletteId,
    customThemeJson: raw.customThemeJson,
    bubbleStyle: raw.bubbleStyle || def.bubbleStyle,
    bubbleRadius: typeof raw.bubbleRadius === 'number' ? raw.bubbleRadius : def.bubbleRadius,
    bubbleBlur: typeof raw.bubbleBlur === 'number' ? raw.bubbleBlur : def.bubbleBlur,
    wallpaperKind: raw.wallpaperKind || def.wallpaperKind,
    wallpaperValue: raw.wallpaperValue || def.wallpaperValue,
    wallpaperOpacity: typeof raw.wallpaperOpacity === 'number' ? raw.wallpaperOpacity : def.wallpaperOpacity,
    fontScale: typeof raw.fontScale === 'number' ? raw.fontScale : def.fontScale,
    codeFontSize: typeof raw.codeFontSize === 'number' ? raw.codeFontSize : def.codeFontSize,
    language: raw.language || def.language,
    immersiveLightEnabled: raw.immersiveLightEnabled !== false,
    pureBackground: raw.pureBackground === true,
    fitAssistantBubble: raw.fitAssistantBubble === true,
    splitParagraphsIntoBubbles: raw.splitParagraphsIntoBubbles === true,
    inputBoxOpacity: typeof raw.inputBoxOpacity === 'number' ? raw.inputBoxOpacity : def.inputBoxOpacity,
    chatItemDisplay: normalizeChatItemDisplay(raw.chatItemDisplay),
    collapseLongUserChars: typeof raw.collapseLongUserChars === 'number' ? raw.collapseLongUserChars : 0,
    enableAssistantMarkdown: raw.enableAssistantMarkdown !== false,
    enableUserMarkdown: raw.enableUserMarkdown !== false,
    enableReasoningMarkdown: raw.enableReasoningMarkdown !== false,
    enableMathLatex: raw.enableMathLatex !== false,
    autoFollowBottom: raw.autoFollowBottom !== false,
    insertSuggestionOnly: raw.insertSuggestionOnly === true,
    enterToSend: raw.enterToSend === true
  };
}

export function defaultBackupScope(): BackupScopeConfig {
  return {
    chats: true,
    attachments: true,
    assistants: true,
    providers: true,
    mcp: true,
    envVars: true,
    skills: true,
    worldBooks: true,
    memory: true,
    quickPhrases: true,
    instructions: true,
    workspaces: true,
    search: true,
    speech: true,
    settings: true
  };
}

export function normalizeBackupScope(raw?: Partial<BackupScopeConfig>): BackupScopeConfig {
  if (!raw) return defaultBackupScope();
  return {
    chats: raw.chats !== false,
    attachments: raw.attachments !== false,
    assistants: raw.assistants !== false,
    providers: raw.providers !== false,
    mcp: raw.mcp !== false,
    envVars: raw.envVars !== false,
    skills: raw.skills !== false,
    worldBooks: raw.worldBooks !== false,
    memory: raw.memory !== false,
    quickPhrases: raw.quickPhrases !== false,
    instructions: raw.instructions !== false,
    workspaces: raw.workspaces !== false,
    search: raw.search !== false,
    speech: raw.speech !== false,
    settings: raw.settings !== false
  };
}

export function countSelectedBackupScope(scope: BackupScopeConfig): number {
  let n = 0;
  if (scope.chats) n++;
  if (scope.attachments) n++;
  if (scope.assistants) n++;
  if (scope.providers) n++;
  if (scope.mcp) n++;
  if (scope.envVars) n++;
  if (scope.skills) n++;
  if (scope.worldBooks) n++;
  if (scope.memory) n++;
  if (scope.quickPhrases) n++;
  if (scope.instructions) n++;
  if (scope.workspaces) n++;
  if (scope.search) n++;
  if (scope.speech) n++;
  if (scope.settings) n++;
  return n;
}

export function defaultBackupConfig(): BackupPreferencesConfig {
  return {
    scope: defaultBackupScope(),
    encryptionEnabled: false,
    rememberPassword: false,
    reminderEnabled: false,
    reminderIntervalDays: 7,
    reminderMinutesOfDay: 20 * 60,
    localCopiesEnabled: true,
    localCopiesIntervalDays: 0,
    localCopiesKeepRecent: 3,
    localCopiesKeepWeekly: true,
    localCopiesKeepMonthly: true,
    localCopiesMaxBytes: 0
  };
}

export function normalizeBackupConfig(raw?: Partial<BackupPreferencesConfig>): BackupPreferencesConfig {
  const def = defaultBackupConfig();
  if (!raw) return def;
  const keepRecent = typeof raw.localCopiesKeepRecent === 'number'
    ? Math.max(1, Math.min(10, Math.round(raw.localCopiesKeepRecent)))
    : def.localCopiesKeepRecent;
  const intervalDays = typeof raw.reminderIntervalDays === 'number'
    ? Math.max(1, Math.min(365, Math.round(raw.reminderIntervalDays)))
    : def.reminderIntervalDays;
  const minutes = typeof raw.reminderMinutesOfDay === 'number'
    ? Math.max(0, Math.min(24 * 60 - 1, Math.round(raw.reminderMinutesOfDay)))
    : def.reminderMinutesOfDay;
  const localInterval = typeof raw.localCopiesIntervalDays === 'number'
    ? Math.max(0, Math.min(365, Math.round(raw.localCopiesIntervalDays)))
    : def.localCopiesIntervalDays;
  const maxBytes = typeof raw.localCopiesMaxBytes === 'number' && raw.localCopiesMaxBytes > 0
    ? raw.localCopiesMaxBytes
    : 0;
  return {
    scope: normalizeBackupScope(raw.scope),
    encryptionEnabled: raw.encryptionEnabled === true,
    rememberPassword: raw.rememberPassword === true,
    passwordVerifier: raw.passwordVerifier,
    passwordSecretRef: raw.passwordSecretRef,
    reminderEnabled: raw.reminderEnabled === true,
    reminderIntervalDays: intervalDays,
    reminderMinutesOfDay: minutes,
    lastBackupAt: typeof raw.lastBackupAt === 'number' ? raw.lastBackupAt : undefined,
    localCopiesEnabled: raw.localCopiesEnabled !== false,
    localCopiesIntervalDays: localInterval,
    localCopiesKeepRecent: keepRecent,
    localCopiesKeepWeekly: raw.localCopiesKeepWeekly !== false,
    localCopiesKeepMonthly: raw.localCopiesKeepMonthly !== false,
    localCopiesMaxBytes: maxBytes,
    localCopiesLastSuccessAt: typeof raw.localCopiesLastSuccessAt === 'number' ? raw.localCopiesLastSuccessAt : undefined,
    localCopiesLastError: raw.localCopiesLastError
  };
}

export function defaultSystemSettings(): SystemSettings {
  return {
    autoTitleEnabled: true,
    chatSuggestionsEnabled: false,
    autoCompactEnabled: false,
    autoCompactThreshold: 36,
    compressionTemplate: '请将上述对话浓缩为结构化上下文摘要，保留：1) 用户目标与约束；2) 已确认的事实、代码路径或数据；3) 未解决的问题和下一步计划。',
    imageUploadQuality: 85,
    hapticsEnabled: true,
    keepScreenOn: true,
    backgroundNotifyEnabled: true,
    autoSnapshotEnabled: true,
    builtinFetchEnabled: true,
    maxToolSteps: 10,
    defaultToolPermission: 'ask',
    enabledDeviceTools: [],
    searchEnabled: false
  };
}

export function defaultInstructionCards(): InstructionCard[] {
  return [
    {
      id: 'learning-mode',
      title: '苏格拉底学习模式',
      description: '不直接给出最终答案，而是分步引导思考并提问检验理解。',
      content: '【学习模式指令】请扮演循循善诱的导师：先判断我当前的理解程度，每次只推进一个关键概念，通过提问引导我自己推导结论，在我主动要求或确实卡住时再揭示完整答案。',
      builtin: true
    },
    {
      id: 'concise-mode',
      title: '极简直答',
      description: '省去客套和重复背景，直接给出结论、代码或步骤。',
      content: '【输出约束】请省略寒暄与铺垫，直接给出核心结论、可执行步骤或代码，必要时用项目符号列出关键要点。',
      builtin: true
    },
    {
      id: 'critical-review',
      title: '批判性审阅',
      description: '主动挑出逻辑漏洞、边界条件、隐藏风险和替代方案。',
      content: '【审阅要求】不要盲目附和。请重点检查方案中的假设前提、边界异常、性能瓶颈、安全隐患以及更稳健的替代思路。',
      builtin: true
    }
  ];
}

export function defaultQuickPhrases(): QuickPhrase[] {
  return [
    { id: 'qp-explain', title: '通俗解释', content: '请用通俗易懂的语言和生活类比再解释一遍：', scope: 'global' },
    { id: 'qp-summarize', title: '总结要点', content: '请将以上内容提炼为 5 条以内的核心要点：', scope: 'global' },
    { id: 'qp-review', title: '检查问题', content: '请逐项审查上面的内容，指出潜在错误和改进建议：', scope: 'global' }
  ];
}

export function defaultSearchServices(): SearchServiceConfig[] {
  return [
    {
      id: 'search-duckduckgo',
      kind: 'duckduckgo',
      name: 'DuckDuckGo（免密钥）',
      endpoint: 'https://html.duckduckgo.com',
      apiKeys: [],
      keyStrategy: 'round_robin',
      maxResults: 5,
      enabled: true,
      mode: 'agent_tool',
      webFetchEnabled: true
    },
    {
      id: 'search-bing',
      kind: 'bing',
      name: 'Bing 网页搜索（免密钥）',
      endpoint: 'https://www.bing.com',
      apiKeys: [],
      keyStrategy: 'round_robin',
      maxResults: 5,
      enabled: true,
      mode: 'agent_tool',
      webFetchEnabled: true
    },
    {
      id: 'search-searxng',
      kind: 'searxng',
      name: 'SearXNG 自建实例',
      endpoint: '',
      apiKeys: [],
      keyStrategy: 'round_robin',
      maxResults: 5,
      enabled: true,
      mode: 'pre_search',
      webFetchEnabled: true
    },
    {
      id: 'search-tavily',
      kind: 'tavily',
      name: 'Tavily Search',
      endpoint: 'https://api.tavily.com/search',
      apiKeys: [],
      keyStrategy: 'round_robin',
      maxResults: 5,
      enabled: true,
      mode: 'agent_tool',
      webFetchEnabled: true
    }
  ];
}

export function initialWorkspace(): Workspace {
  return {
    version: 2,
    providers: [
      preset('openai', 'OpenAI', 'openai', 'https://api.openai.com/v1', ''),
      preset('deepseek', 'DeepSeek', 'openai', 'https://api.deepseek.com/v1', ''),
      preset('gemini', 'Google Gemini', 'gemini', 'https://generativelanguage.googleapis.com/v1beta', ''),
      preset('claude', 'Anthropic', 'anthropic', 'https://api.anthropic.com/v1', ''),
      preset('siliconflow', '硅基流动', 'openai', 'https://api.siliconflow.cn/v1', ''),
      preset('openrouter', 'OpenRouter', 'openai', 'https://openrouter.ai/api/v1', ''),
      preset('qwen', '阿里云百炼', 'openai', 'https://dashscope.aliyuncs.com/compatible-mode/v1', ''),
      preset('zhipu', '智谱 GLM', 'openai', 'https://open.bigmodel.cn/api/paas/v4', ''),
      preset('xai', 'xAI Grok', 'openai', 'https://api.x.ai/v1', ''),
      preset('volcengine', '火山引擎 Ark', 'openai', 'https://ark.cn-beijing.volces.com/api/v3', ''),
      preset('ollama', 'Ollama 本地', 'openai', 'http://127.0.0.1:11434/v1', '')
    ],
    personas: [
      { id: 'default', name: '通用助手', prompt: '', avatar: '🤖', tags: ['通用'], memoryEnabled: true },
      {
        id: 'translator',
        name: '翻译助手',
        prompt: '请将用户输入的文字译成中文。如果原文是中文，请译成英文。保留原文结构，只输出译文。',
        avatar: '🌐',
        tags: ['语言'],
        memoryEnabled: false
      },
      {
        id: 'coder',
        name: '研发工程师',
        prompt: '你是一名资深全栈与鸿蒙架构师。回答需直接、严谨、注重边界条件和可运行性；优先输出清晰代码示例和差量改动说明。',
        avatar: '💻',
        tags: ['编程'],
        memoryEnabled: true
      }
    ],
    conversations: [],
    searchServices: defaultSearchServices(),
    activeSearchId: 'search-duckduckgo',
    mcpServers: [],
    activeProvider: 'openai',
    activeConversation: '',
    generationParams: defaultGenerationParams(),
    modelDefaults: {
      chatProviderId: '',
      chatModelId: '',
      perChatModel: false,
      titleProviderId: '',
      titleModelId: '',
      summaryProviderId: '',
      summaryModelId: '',
      suggestionsProviderId: '',
      suggestionsModelId: '',
      compressProviderId: '',
      compressModelId: '',
      translateProviderId: '',
      translateModelId: '',
      ocrProviderId: '',
      ocrModelId: '',
      memoryProviderId: '',
      memoryModelId: ''
    },
    tts: {
      engine: 'system',
      endpoint: '',
      secretRef: '',
      model: 'tts-1',
      voice: 'alloy',
      speed: 1.0,
      language: 'zh-CN'
    },
    asr: {
      engine: 'system',
      endpoint: '',
      secretRef: '',
      model: 'whisper-1',
      language: 'zh-CN'
    },
    memories: [],
    userProfile: [],
    memoryTraces: [],
    memorySettings: {
      autoExtract: false,
      injectGlobal: true,
      maxInjectCount: 10
    },
    worldBooks: [],
    instructionCards: defaultInstructionCards(),
    activeInstructionIds: [],
    quickPhrases: defaultQuickPhrases(),
    skills: [],
    workspaces: [],
    envVars: [],
    scheduledTasks: [],
    browserBookmarks: [
      { id: 'bm-kelivo', title: 'Kelivo 文档', url: 'https://kelivo.psycheas.top/guide', createdAt: 1700000000000 }
    ],
    appearance: defaultAppearance(),
    systemSettings: defaultSystemSettings(),
    toolOverrides: [],
    snapshots: [],
    backupConfig: defaultBackupConfig(),
    userName: '用户',
    favoriteModels: []
  };
}

export function getAllAttachments(message: ChatMessage): Attachment[] {
  const list: Attachment[] = [];
  if (message.attachment) list.push(message.attachment);
  if (message.attachments && message.attachments.length > 0) {
    for (let i = 0; i < message.attachments.length; i++) {
      const item = message.attachments[i];
      if (!message.attachment || item.name !== message.attachment.name || item.data !== message.attachment.data) {
        list.push(item);
      }
    }
  }
  return list;
}

export function messageText(message: ChatMessage): string {
  let body = message.text;
  if (message.quote && message.quote.excerpt) {
    body = '> 引用前文：' + message.quote.excerpt.replace(/\n/g, '\n> ') + '\n\n' + body;
  }
  const files = getAllAttachments(message);
  for (let i = 0; i < files.length; i++) {
    const file = files[i];
    if (file.mime === 'text/plain' || file.kind === 'text' || file.kind === 'pdf' || file.kind === 'docx') {
      body += '\n\n[附件: ' + file.name + ']\n' + file.data;
    }
  }
  if (message.sources?.length) {
    body += '\n\n以下为网页检索资料。请根据相关资料回答，引用时标注来源编号。\n' +
      message.sources.map((hit: SearchHit, i: number): string =>
        '[' + (i + 1) + '] ' + hit.title + '\n' + hit.url + '\n' + hit.excerpt).join('\n\n');
  }
  return body;
}

export function checkEndpoint(value: string): string {
  const base = value.trim().replace(/\/+$/, '');
  if (!/^https?:\/\/[^\s\/?#@]+(?:\/[^\s?#]*)?$/i.test(base)) {
    throw new Error('请输入完整的 API 基础地址，地址中不能包含密钥、查询参数或片段。');
  }
  return base;
}

export function estimateTokens(text: string): number {
  if (!text) return 0;
  let cjk = 0;
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    if (code >= 0x4E00 && code <= 0x9FFF) cjk++;
  }
  const ascii = text.length - cjk;
  return Math.max(1, Math.ceil(cjk * 1.5 + ascii / 3.8));
}

export function estimateMessagesTokens(messages: ChatMessage[], systemPrompt: string): number {
  let total = estimateTokens(systemPrompt);
  for (let i = 0; i < messages.length; i++) {
    const msg = messages[i];
    total += 6 + estimateTokens(messageText(msg));
    if (msg.reasoning) total += estimateTokens(msg.reasoning);
    const files = getAllAttachments(msg);
    for (let j = 0; j < files.length; j++) {
      if (files[j].mime.startsWith('image/')) total += 512;
    }
  }
  return total;
}

export function findProviderModelSpec(provider: Provider, modelId: string): ModelSpec {
  const found = provider.models?.find((m: ModelSpec): boolean => m.id === modelId);
  if (found) return found;
  return defaultModelSpec(modelId || provider.model);
}

export interface ActiveModelResolution {
  provider: Provider;
  modelId: string;
}

export function resolveActiveModel(workspace: Workspace, chat?: Conversation, persona?: Persona): ActiveModelResolution {
  const findEnabled = (id?: string): Provider | undefined => {
    if (!id) return undefined;
    return workspace.providers.find((p: Provider): boolean => p.id === id && p.enabled !== false);
  };
  let prov: Provider | undefined = findEnabled(chat?.overrideProviderId);
  let targetModel = prov ? (chat?.overrideModel || '') : '';
  if (!prov) {
    prov = findEnabled(persona?.providerId);
    targetModel = prov ? (persona?.modelId || '') : '';
  }
  if (!prov && workspace.modelDefaults?.chatProviderId) {
    prov = findEnabled(workspace.modelDefaults.chatProviderId);
    if (prov) {
      targetModel = workspace.modelDefaults.chatModelId || '';
    }
  }
  if (!prov && workspace.activeProvider) {
    prov = findEnabled(workspace.activeProvider);
  }
  if (!prov) {
    prov = workspace.providers.find((p: Provider): boolean => p.enabled !== false && isProviderConfigured(p));
  }
  if (!prov) {
    prov = workspace.providers.find((p: Provider): boolean => p.id === workspace.activeProvider) || workspace.providers[0];
  }
  if (!targetModel) {
    if (chat?.overrideProviderId === prov.id && chat.overrideModel) {
      targetModel = chat.overrideModel;
    } else if (persona?.providerId === prov.id && persona.modelId) {
      targetModel = persona.modelId;
    } else if (workspace.modelDefaults?.chatProviderId === prov.id && workspace.modelDefaults.chatModelId) {
      targetModel = workspace.modelDefaults.chatModelId;
    } else if (prov.model.trim()) {
      targetModel = prov.model.trim();
    } else {
      const enabledModels = providerEnabledModels(prov);
      targetModel = enabledModels.length > 0 ? enabledModels[0].id : '';
    }
  }
  return { provider: prov, modelId: targetModel };
}

export function cloneProvider(p: Provider): Provider {
  return {
    id: p.id,
    name: p.name,
    family: p.family,
    baseUrl: p.baseUrl,
    chatPath: p.chatPath || '',
    model: p.model,
    secretRef: p.secretRef,
    models: p.models ? p.models.slice() : [],
    apiKeys: p.apiKeys ? p.apiKeys.slice() : [],
    keyStrategy: p.keyStrategy || 'round_robin',
    groupName: p.groupName || '',
    proxy: p.proxy ? {
      enabled: p.proxy.enabled,
      host: p.proxy.host,
      port: p.proxy.port,
      username: p.proxy.username,
      passwordRef: p.proxy.passwordRef
    } : undefined,
    customHeaders: p.customHeaders ? p.customHeaders.slice() : [],
    customBodyJson: p.customBodyJson,
    promptCaching: p.promptCaching,
    sendConversationCacheKey: p.sendConversationCacheKey,
    balanceUrl: p.balanceUrl,
    lastBalance: p.lastBalance,
    builtinSearch: p.builtinSearch,
    builtinUrlContext: p.builtinUrlContext,
    builtinCodeExec: p.builtinCodeExec,
    builtinImageGen: p.builtinImageGen,
    oauth: p.oauth,
    enabled: p.enabled !== false
  };
}
