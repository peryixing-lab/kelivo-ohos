import {
  MemoryTemplateKind,
  isStandardProfileKey,
  normalizeMemorySettings,
  normalizeMemoryTimestamp,
  normalizeUserProfileFields,
  profileFieldKey
} from '../core/MemoryLogic';
import {
  MemoryCategory,
  MemoryPromptTemplates,
  MemorySettings,
  MemorySourceKind,
  MemoryTrace,
  MemoryTraceStep,
  ModelDefaults,
  ModelSpec,
  Persona,
  Provider,
  UserProfileField,
  isProviderConfigured,
  providerEnabledModels
} from '../core/Models';

export type MemorySubPage = 'home' | 'list' | 'profile' | 'legacy' | 'traces' | 'about' | 'template' | 'modelPicker';

export interface MemoryTemplateRowSpec {
  kind: MemoryTemplateKind;
  title: string;
  subtitle: string;
}

export interface MemoryRoleModelChoice {
  key: string;
  providerId: string;
  providerName: string;
  modelId: string;
}

export const MEMORY_TEMPLATE_ROWS: MemoryTemplateRowSpec[] = [
  { kind: 'rules', title: '记忆规则', subtitle: '注入到主对话系统提示词中' },
  { kind: 'gate', title: '门控判断 (Gatekeeper)', subtitle: '判定一轮对话是否值得长期记忆' },
  { kind: 'extract', title: '候选提取 (Extract)', subtitle: '从对话中提取候选长期记忆条目' },
  { kind: 'smartAddBatch', title: '智能去重 · 批量 (Smart Add)', subtitle: '批量判定 NEW / MERGE / CONFLICT / SKIP' },
  { kind: 'smartAddSingle', title: '智能去重 · 逐条 (Smart Add)', subtitle: '逐条判定 NEW / MERGE / CONFLICT / SKIP' },
  { kind: 'profileDistill', title: '画像提炼 (Profile Distiller)', subtitle: '从身份记忆中提炼结构化用户画像字段' },
  { kind: 'legacyMigrate', title: '旧版记忆迁移', subtitle: '迁移改写旧版自由文本记忆时使用' }
];

export function cloneMemorySettings(raw: MemorySettings): MemorySettings {
  const s = normalizeMemorySettings(raw);
  const tpl: MemoryPromptTemplates = s.templates ? {
    rulesZh: s.templates.rulesZh,
    rulesEn: s.templates.rulesEn,
    gateZh: s.templates.gateZh,
    gateEn: s.templates.gateEn,
    extractZh: s.templates.extractZh,
    extractEn: s.templates.extractEn,
    smartAddSingleZh: s.templates.smartAddSingleZh,
    smartAddSingleEn: s.templates.smartAddSingleEn,
    smartAddBatchZh: s.templates.smartAddBatchZh,
    smartAddBatchEn: s.templates.smartAddBatchEn,
    profileDistillZh: s.templates.profileDistillZh,
    profileDistillEn: s.templates.profileDistillEn,
    legacyMigrateZh: s.templates.legacyMigrateZh,
    legacyMigrateEn: s.templates.legacyMigrateEn
  } : {};
  return {
    autoExtract: s.autoExtract,
    injectGlobal: s.injectGlobal,
    maxInjectCount: s.maxInjectCount,
    useLegacyMemory: s.useLegacyMemory,
    enableThinking: s.enableThinking,
    promptLanguage: s.promptLanguage,
    recordTraces: s.recordTraces,
    templates: tpl,
    legacyMemories: s.legacyMemories ? s.legacyMemories.slice() : []
  };
}

export function cloneMemoryModelDefaults(raw: ModelDefaults): ModelDefaults {
  return {
    chatProviderId: raw.chatProviderId || '',
    chatModelId: raw.chatModelId || '',
    perChatModel: raw.perChatModel === true,
    titleProviderId: raw.titleProviderId || '',
    titleModelId: raw.titleModelId || '',
    summaryProviderId: raw.summaryProviderId || '',
    summaryModelId: raw.summaryModelId || '',
    suggestionsProviderId: raw.suggestionsProviderId || '',
    suggestionsModelId: raw.suggestionsModelId || '',
    compressProviderId: raw.compressProviderId || '',
    compressModelId: raw.compressModelId || '',
    translateProviderId: raw.translateProviderId || '',
    translateModelId: raw.translateModelId || '',
    ocrProviderId: raw.ocrProviderId || '',
    ocrModelId: raw.ocrModelId || '',
    memoryProviderId: raw.memoryProviderId || '',
    memoryModelId: raw.memoryModelId || ''
  };
}

export function memoryCategoryLabel(cat: MemoryCategory): string {
  if (cat === 'identity') return '身份';
  if (cat === 'workflow') return '工作方式';
  if (cat === 'tone') return '表达风格';
  return '用户指令';
}

export function memorySourceLabel(src?: MemorySourceKind): string {
  if (src === 'tool') return '工具写入';
  if (src === 'manual') return '手动';
  return '自动提取';
}

export function memoryPersonaName(personas: Persona[], id?: string): string {
  if (!id || id.length === 0) return '全局';
  for (let i = 0; i < personas.length; i++) {
    if (personas[i].id === id) return personas[i].name;
  }
  return `已删除助手 (${id.slice(0, 6)})`;
}

export function formatMemoryTs(ts?: number | string): string {
  const ms = normalizeMemoryTimestamp(ts);
  const d = new Date(ms);
  if (!Number.isFinite(d.getTime())) return '';
  const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function formatMemoryDateOnly(ts?: number | string): string {
  const ms = normalizeMemoryTimestamp(ts);
  const d = new Date(ms);
  if (!Number.isFinite(d.getTime())) return '';
  const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

export function collectMemoryModelChoices(providers: Provider[]): MemoryRoleModelChoice[] {
  const enabled = providers.filter((p: Provider): boolean =>
    p.enabled !== false && providerEnabledModels(p).length > 0);
  const configured = enabled.filter((p: Provider): boolean => isProviderConfigured(p));
  const source = configured.length > 0 ? configured : enabled;
  const out: MemoryRoleModelChoice[] = [];
  for (let i = 0; i < source.length; i++) {
    const p = source[i];
    const specs: ModelSpec[] = providerEnabledModels(p);
    for (let j = 0; j < specs.length; j++) {
      out.push({
        key: `${p.id}::${specs[j].id}`,
        providerId: p.id,
        providerName: p.name,
        modelId: specs[j].id
      });
    }
  }
  return out;
}

export function isMemoryTemplateCustomized(settings: MemorySettings, kind: MemoryTemplateKind): boolean {
  const tpl = settings.templates;
  if (!tpl) return false;
  if (kind === 'rules') return Boolean(tpl.rulesZh?.trim() || tpl.rulesEn?.trim());
  if (kind === 'gate') return Boolean(tpl.gateZh?.trim() || tpl.gateEn?.trim());
  if (kind === 'extract') return Boolean(tpl.extractZh?.trim() || tpl.extractEn?.trim());
  if (kind === 'smartAddSingle') return Boolean(tpl.smartAddSingleZh?.trim() || tpl.smartAddSingleEn?.trim());
  if (kind === 'smartAddBatch') return Boolean(tpl.smartAddBatchZh?.trim() || tpl.smartAddBatchEn?.trim());
  if (kind === 'profileDistill') return Boolean(tpl.profileDistillZh?.trim() || tpl.profileDistillEn?.trim());
  return Boolean(tpl.legacyMigrateZh?.trim() || tpl.legacyMigrateEn?.trim());
}

export function getCustomMemoryTemplateValue(
  tpl: MemoryPromptTemplates | undefined,
  kind: MemoryTemplateKind,
  lang: 'zh' | 'en'
): string {
  if (!tpl) return '';
  if (kind === 'rules') return (lang === 'zh' ? tpl.rulesZh : tpl.rulesEn) || '';
  if (kind === 'gate') return (lang === 'zh' ? tpl.gateZh : tpl.gateEn) || '';
  if (kind === 'extract') return (lang === 'zh' ? tpl.extractZh : tpl.extractEn) || '';
  if (kind === 'smartAddSingle') return (lang === 'zh' ? tpl.smartAddSingleZh : tpl.smartAddSingleEn) || '';
  if (kind === 'smartAddBatch') return (lang === 'zh' ? tpl.smartAddBatchZh : tpl.smartAddBatchEn) || '';
  if (kind === 'profileDistill') return (lang === 'zh' ? tpl.profileDistillZh : tpl.profileDistillEn) || '';
  return (lang === 'zh' ? tpl.legacyMigrateZh : tpl.legacyMigrateEn) || '';
}

export function setCustomMemoryTemplateValue(
  tpl: MemoryPromptTemplates,
  kind: MemoryTemplateKind,
  lang: 'zh' | 'en',
  val: string | undefined
): void {
  if (kind === 'rules') {
    if (lang === 'zh') tpl.rulesZh = val;
    else tpl.rulesEn = val;
  } else if (kind === 'gate') {
    if (lang === 'zh') tpl.gateZh = val;
    else tpl.gateEn = val;
  } else if (kind === 'extract') {
    if (lang === 'zh') tpl.extractZh = val;
    else tpl.extractEn = val;
  } else if (kind === 'smartAddSingle') {
    if (lang === 'zh') tpl.smartAddSingleZh = val;
    else tpl.smartAddSingleEn = val;
  } else if (kind === 'smartAddBatch') {
    if (lang === 'zh') tpl.smartAddBatchZh = val;
    else tpl.smartAddBatchEn = val;
  } else if (kind === 'profileDistill') {
    if (lang === 'zh') tpl.profileDistillZh = val;
    else tpl.profileDistillEn = val;
  } else {
    if (lang === 'zh') tpl.legacyMigrateZh = val;
    else tpl.legacyMigrateEn = val;
  }
}

export function findMemoryTemplateSpec(kind: MemoryTemplateKind): MemoryTemplateRowSpec {
  for (let i = 0; i < MEMORY_TEMPLATE_ROWS.length; i++) {
    if (MEMORY_TEMPLATE_ROWS[i].kind === kind) return MEMORY_TEMPLATE_ROWS[i];
  }
  return MEMORY_TEMPLATE_ROWS[0];
}

export function standardMemoryProfileValue(userProfile: UserProfileField[], key: string): string {
  const norm = normalizeUserProfileFields(userProfile);
  const target = key.trim().toLowerCase();
  for (let i = 0; i < norm.length; i++) {
    if (profileFieldKey(norm[i]).toLowerCase() === target) {
      return norm[i].value;
    }
  }
  return '';
}

export function customMemoryProfileFields(userProfile: UserProfileField[]): UserProfileField[] {
  const norm = normalizeUserProfileFields(userProfile);
  return norm.filter((f: UserProfileField): boolean => !isStandardProfileKey(profileFieldKey(f)));
}

export function memoryTraceStatusLabel(tr: MemoryTrace): string {
  if (tr.error) return '✕ 失败';
  if (tr.gatekeeperPassed) return '✓ 门控通过';
  return '○ 门控跳过';
}

export function memoryTraceStepStatusLabel(st: MemoryTraceStep): string {
  if (st.status === 'failed' || st.error) return '失败';
  if (st.status === 'skipped') return '跳过';
  return '成功';
}

export function memoryTraceStepResponseText(st: MemoryTraceStep): string {
  if (st.response && st.response.trim().length > 0) {
    return st.response.slice(0, 600);
  }
  if (st.status === 'failed' || st.error) {
    return st.error ? `错误：${st.error}` : '(模型返回空响应)';
  }
  return '';
}
