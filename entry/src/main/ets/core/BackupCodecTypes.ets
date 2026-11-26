import {
  AppearanceConfig,
  AsrConfig,
  BackupScopeConfig,
  Conversation,
  EnvVar,
  GenerationParams,
  InstructionCard,
  LocalWorkspace,
  McpServerConfig,
  MemoryEntry,
  MemorySettings,
  ModelDefaults,
  Persona,
  Provider,
  ProxyConfig,
  QuickPhrase,
  ScheduledTask,
  SearchServiceConfig,
  SkillRecord,
  SystemSettings,
  ToolSchemaOverride,
  TtsConfig,
  UserProfileField,
  Workspace,
  WorldBook
} from './Models';

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
