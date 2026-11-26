import {
  BackupPreferencesConfig,
  BackupScopeConfig,
  normalizeBackupScope
} from '../core/Models';

export type BackupScopeKey = 'chats' | 'attachments' | 'assistants' | 'providers' | 'mcp' | 'envVars' | 'skills' | 'worldBooks' | 'memory' | 'quickPhrases' | 'instructions' | 'workspaces' | 'search' | 'speech' | 'settings';

export interface BackupScopeCategoryMeta {
  key: BackupScopeKey;
  label: string;
  symbol: Resource;
}

export interface RemoteBackupEntry {
  kind: 'webdav' | 's3';
  name: string;
  remoteKey: string;
  sizeBytes: number;
  lastModified: string;
}

export const BACKUP_SCOPE_GROUP_MEDIA: BackupScopeCategoryMeta[] = [
  { key: 'chats', label: '聊天记录', symbol: $r('sys.symbol.ellipsis_bubble') },
  { key: 'attachments', label: '文件与图片', symbol: $r('sys.symbol.doc_text') }
];

export const BACKUP_SCOPE_GROUP_DATA: BackupScopeCategoryMeta[] = [
  { key: 'assistants', label: '助手', symbol: $r('sys.symbol.person') },
  { key: 'providers', label: '供应商', symbol: $r('sys.symbol.square_grid_2x2') },
  { key: 'mcp', label: 'MCP 服务器', symbol: $r('sys.symbol.wrench_and_screwdriver') },
  { key: 'envVars', label: '环境变量', symbol: $r('sys.symbol.lightbulb') },
  { key: 'skills', label: '技能', symbol: $r('sys.symbol.bolt') },
  { key: 'worldBooks', label: '世界书', symbol: $r('sys.symbol.book') },
  { key: 'memory', label: '记忆', symbol: $r('sys.symbol.compass') },
  { key: 'quickPhrases', label: '快捷短语', symbol: $r('sys.symbol.message') },
  { key: 'instructions', label: '提示词注入', symbol: $r('sys.symbol.slider_horizontal_2') },
  { key: 'workspaces', label: '工作区', symbol: $r('sys.symbol.folder') },
  { key: 'search', label: '搜索服务', symbol: $r('sys.symbol.magnifyingglass') },
  { key: 'speech', label: '语音服务', symbol: $r('sys.symbol.speaker_wave_2') },
  { key: 'settings', label: '其他设置', symbol: $r('sys.symbol.gearshape') }
];

export const BACKUP_REMINDER_DAY_PRESETS: number[] = [1, 3, 7, 14, 30];
export const BACKUP_COPY_INTERVAL_PRESETS: number[] = [0, 1, 3, 7, 14, 30];
export const BACKUP_COPY_KEEP_PRESETS: number[] = [1, 2, 3, 5, 7, 10];
export const BACKUP_COPY_MAX_BYTES_PRESETS: number[] = [
  0,
  1024 * 1024 * 1024,
  2 * 1024 * 1024 * 1024,
  5 * 1024 * 1024 * 1024,
  10 * 1024 * 1024 * 1024
];

export function cloneBackupPreferences(cfg: BackupPreferencesConfig): BackupPreferencesConfig {
  return {
    scope: normalizeBackupScope(cfg.scope),
    encryptionEnabled: cfg.encryptionEnabled,
    rememberPassword: cfg.rememberPassword,
    passwordVerifier: cfg.passwordVerifier,
    passwordSecretRef: cfg.passwordSecretRef,
    reminderEnabled: cfg.reminderEnabled,
    reminderIntervalDays: cfg.reminderIntervalDays,
    reminderMinutesOfDay: cfg.reminderMinutesOfDay,
    lastBackupAt: cfg.lastBackupAt,
    localCopiesEnabled: cfg.localCopiesEnabled,
    localCopiesIntervalDays: cfg.localCopiesIntervalDays,
    localCopiesKeepRecent: cfg.localCopiesKeepRecent,
    localCopiesKeepWeekly: cfg.localCopiesKeepWeekly,
    localCopiesKeepMonthly: cfg.localCopiesKeepMonthly,
    localCopiesMaxBytes: cfg.localCopiesMaxBytes,
    localCopiesLastSuccessAt: cfg.localCopiesLastSuccessAt,
    localCopiesLastError: cfg.localCopiesLastError
  };
}

export function formatBackupTimeFull(ms?: number): string {
  if (!ms) return '从未';
  const d = new Date(ms);
  const pad = (n: number): string => n < 10 ? ('0' + n) : String(n);
  return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) +
    ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
}

export function formatReminderFreqText(days: number): string {
  if (days === 1) return '每天';
  if (days === 3) return '每 3 天';
  if (days === 7) return '每周';
  if (days === 14) return '每 14 天';
  if (days === 30) return '每月';
  return '每 ' + days + ' 天';
}

export function formatReminderTimeText(minutes: number): string {
  const h = Math.floor(minutes / 60) % 24;
  const m = minutes % 60;
  return (h < 10 ? '0' : '') + h + ':' + (m < 10 ? '0' : '') + m;
}

export function formatNextReminderText(cfg: BackupPreferencesConfig): string {
  if (!cfg.reminderEnabled) return '未开启';
  const baseMs = cfg.lastBackupAt || Date.now();
  const intervalMs = Math.max(1, cfg.reminderIntervalDays) * 24 * 3600 * 1000;
  const target = new Date(baseMs + intervalMs);
  const h = Math.floor(cfg.reminderMinutesOfDay / 60) % 24;
  const m = cfg.reminderMinutesOfDay % 60;
  target.setHours(h, m, 0, 0);
  if (target.getTime() <= Date.now()) return '已到期，建议尽快备份';
  return formatBackupTimeFull(target.getTime());
}

export function formatCopyIntervalText(days: number): string {
  if (days <= 0) return '自动';
  return formatReminderFreqText(days);
}

export function getBackupScopeCategory(scope: BackupScopeConfig, key: BackupScopeKey): boolean {
  if (key === 'chats') return scope.chats;
  if (key === 'attachments') return scope.attachments;
  if (key === 'assistants') return scope.assistants;
  if (key === 'providers') return scope.providers;
  if (key === 'mcp') return scope.mcp;
  if (key === 'envVars') return scope.envVars;
  if (key === 'skills') return scope.skills;
  if (key === 'worldBooks') return scope.worldBooks;
  if (key === 'memory') return scope.memory;
  if (key === 'quickPhrases') return scope.quickPhrases;
  if (key === 'instructions') return scope.instructions;
  if (key === 'workspaces') return scope.workspaces;
  if (key === 'search') return scope.search;
  if (key === 'speech') return scope.speech;
  return scope.settings;
}

export function withBackupScopeCategory(
  scope: BackupScopeConfig,
  key: BackupScopeKey,
  val: boolean
): BackupScopeConfig {
  const s = normalizeBackupScope(scope);
  if (key === 'chats') s.chats = val;
  else if (key === 'attachments') s.attachments = val;
  else if (key === 'assistants') s.assistants = val;
  else if (key === 'providers') s.providers = val;
  else if (key === 'mcp') s.mcp = val;
  else if (key === 'envVars') s.envVars = val;
  else if (key === 'skills') s.skills = val;
  else if (key === 'worldBooks') s.worldBooks = val;
  else if (key === 'memory') s.memory = val;
  else if (key === 'quickPhrases') s.quickPhrases = val;
  else if (key === 'instructions') s.instructions = val;
  else if (key === 'workspaces') s.workspaces = val;
  else if (key === 'search') s.search = val;
  else if (key === 'speech') s.speech = val;
  else if (key === 'settings') s.settings = val;
  return s;
}

export function makeAllBackupScope(enabled: boolean): BackupScopeConfig {
  return {
    chats: enabled,
    attachments: enabled,
    assistants: enabled,
    providers: enabled,
    mcp: enabled,
    envVars: enabled,
    skills: enabled,
    worldBooks: enabled,
    memory: enabled,
    quickPhrases: enabled,
    instructions: enabled,
    workspaces: enabled,
    search: enabled,
    speech: enabled,
    settings: enabled
  };
}
