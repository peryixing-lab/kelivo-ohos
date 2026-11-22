import { pasteboard } from '@kit.BasicServicesKit';
import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { computeFloatingBottomInsetVp } from '../core/ImmersiveUtils';
import { SystemMotion } from '../core/SystemMotion';
import {
  MEMORY_CATEGORIES,
  MemoryTemplateKind,
  STANDARD_PROFILE_FIELDS,
  StandardProfileFieldSpec,
  findOrphanedMemories,
  getDefaultMemoryTemplate,
  getEffectiveMemoryTemplate,
  isStandardProfileKey,
  normalizeMemoryCategory,
  normalizeMemorySettings,
  normalizeMemoryTimestamp,
  normalizeUserProfileFields,
  profileFieldKey,
  profileKeyDisplayLabel,
  searchMemories
} from '../core/MemoryLogic';
import {
  MemoryCategory,
  MemoryEntry,
  MemoryPromptLanguage,
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
import { newId } from '../core/Storage';
import { KelivoNavTitleBar } from './KelivoChrome';

type MemorySubPage = 'home' | 'list' | 'profile' | 'legacy' | 'traces' | 'about' | 'template' | 'modelPicker';

interface TemplateRowSpec {
  kind: MemoryTemplateKind;
  title: string;
  subtitle: string;
}

interface RoleModelChoice {
  key: string;
  providerId: string;
  providerName: string;
  modelId: string;
}

const TEMPLATE_ROWS: TemplateRowSpec[] = [
  { kind: 'rules', title: '记忆规则', subtitle: '注入到主对话系统提示词中' },
  { kind: 'gate', title: '门控判断 (Gatekeeper)', subtitle: '判定一轮对话是否值得长期记忆' },
  { kind: 'extract', title: '候选提取 (Extract)', subtitle: '从对话中提取候选长期记忆条目' },
  { kind: 'smartAddBatch', title: '智能去重 · 批量 (Smart Add)', subtitle: '批量判定 NEW / MERGE / CONFLICT / SKIP' },
  { kind: 'smartAddSingle', title: '智能去重 · 逐条 (Smart Add)', subtitle: '逐条判定 NEW / MERGE / CONFLICT / SKIP' },
  { kind: 'profileDistill', title: '画像提炼 (Profile Distiller)', subtitle: '从身份记忆中提炼结构化用户画像字段' },
  { kind: 'legacyMigrate', title: '旧版记忆迁移', subtitle: '迁移改写旧版自由文本记忆时使用' }
];

@Component
export struct MemoryPanel {
  @Prop memories: MemoryEntry[] = [];
  @Prop userProfile: UserProfileField[] = [];
  @Prop memoryTraces: MemoryTrace[] = [];
  @Prop memorySettings: MemorySettings = {
    autoExtract: false,
    injectGlobal: true,
    maxInjectCount: 100,
    useLegacyMemory: false,
    enableThinking: true,
    promptLanguage: 'auto',
    recordTraces: true,
    templates: {},
    legacyMemories: []
  };
  @Prop personas: Persona[] = [];
  @Prop providers: Provider[] = [];
  @Prop modelDefaults: ModelDefaults = {
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
  };
  @Prop embeddedInNav: boolean = false;

  onSaveMemories: (entries: MemoryEntry[]) => Promise<void> = async () => {};
  onSaveProfile: (fields: UserProfileField[]) => Promise<void> = async () => {};
  onSaveSettings: (cfg: MemorySettings) => Promise<void> = async () => {};
  onSaveModelDefaults: (next: ModelDefaults) => Promise<void> = async () => {};
  onClearTraces: () => Promise<void> = async () => {};
  onDismissOverlay: () => boolean = () => false;
  onRouteShown: () => void = () => {};
  onRouteHidden: () => void = () => {};
  onClose: () => void = () => {};

  @StorageProp('immersiveLightEnabled') immersiveLightEnabled: boolean = true;
  @StorageProp('windowTopInsetVp') winTopInset: number = 0;
  @StorageProp('windowBottomInsetVp') winBottomInset: number = 0;
  @StorageProp('windowLeftInsetVp') winLeftInset: number = 0;
  @StorageProp('windowRightInsetVp') winRightInset: number = 0;
  @StorageProp('windowIsFloating') winIsFloating: boolean = false;
  @StorageProp('themeCanvasHex') themeCanvasHex: string = '#F7F7F7';
  @StorageProp('themeSurfaceHex') themeSurfaceHex: string = '#FFFFFF';
  @StorageProp('reduceMotionEnabled') reduceMotion: boolean = false;

  @State subPage: MemorySubPage = 'home';
  @State statusTip: string = '';
  @State activeSheetKind: '' | 'entry' | 'profile' = '';
  @State activeSheetOpen: boolean = false;
  private contentScroller: Scroller = new Scroller();

  private effectiveBottomInset(): number {
    return computeFloatingBottomInsetVp(this.winBottomInset, this.winIsFloating, false);
  }

  private showToastTip(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast(
        ImmersiveMaterialStyle.toastOptions(msg, this.immersiveLightEnabled)
      );
    } catch (_) {}
  }

  private openSheet(kind: 'entry' | 'profile'): void {
    this.activeSheetKind = kind;
    this.activeSheetOpen = true;
  }

  private closeSheet(): void {
    this.activeSheetOpen = false;
    this.activeSheetKind = '';
  }

  private memorySheetTitle(): string {
    if (this.activeSheetKind === 'profile') {
      return '自定义画像字段';
    }
    return this.editingEntryId.length > 0 ? '编辑记忆' : '新增长期记忆';
  }

  private returnToHome(): void {
    this.closeSheet();
    this.editingProfileKey = '';
    this.multiSelect = false;
    this.selectedIds = [];
    this.navigateSubPage('home');
  }

  private navigateSubPage(next: MemorySubPage): void {
    SystemMotion.springAnimate(this.getUIContext(), this.reduceMotion, () => {
      this.subPage = next;
    });
    try {
      this.contentScroller.scrollTo({ xOffset: 0, yOffset: 0 });
    } catch (_) {}
  }

  // Memory list state
  @State searchQuery: string = '';
  @State filterScope: string = 'all'; // 'all' | 'global' | 'orphan' | personaId
  @State filterCat: string = 'all';
  @State filterStatus: string = 'active'; // 'active' | 'archived' | 'all'
  @State pageLimit: number = 40;
  @State multiSelect: boolean = false;
  @State selectedIds: string[] = [];
  @State editingEntryId: string = '';
  @State entryCat: MemoryCategory = 'instruction';
  @State entryContent: string = '';
  @State entryScopeId: string = '';

  // Profile editor state
  @State editingProfileKey: string = '';
  @State editingProfileVal: string = '';
  @State newProfileKey: string = '';
  @State newProfileVal: string = '';

  // Template editor state
  @State editTemplateKind: MemoryTemplateKind = 'rules';
  @State editTemplateLang: 'zh' | 'en' = 'zh';
  @State editTemplateText: string = '';

  // Trace detail state
  @State expandedTraceId: string = '';

  private cloneSettings(): MemorySettings {
    const s = normalizeMemorySettings(this.memorySettings);
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

  private cloneModelDefaults(): ModelDefaults {
    return {
      chatProviderId: this.modelDefaults.chatProviderId || '',
      chatModelId: this.modelDefaults.chatModelId || '',
      perChatModel: this.modelDefaults.perChatModel === true,
      titleProviderId: this.modelDefaults.titleProviderId || '',
      titleModelId: this.modelDefaults.titleModelId || '',
      summaryProviderId: this.modelDefaults.summaryProviderId || '',
      summaryModelId: this.modelDefaults.summaryModelId || '',
      suggestionsProviderId: this.modelDefaults.suggestionsProviderId || '',
      suggestionsModelId: this.modelDefaults.suggestionsModelId || '',
      compressProviderId: this.modelDefaults.compressProviderId || '',
      compressModelId: this.modelDefaults.compressModelId || '',
      translateProviderId: this.modelDefaults.translateProviderId || '',
      translateModelId: this.modelDefaults.translateModelId || '',
      ocrProviderId: this.modelDefaults.ocrProviderId || '',
      ocrModelId: this.modelDefaults.ocrModelId || '',
      memoryProviderId: this.modelDefaults.memoryProviderId || '',
      memoryModelId: this.modelDefaults.memoryModelId || ''
    };
  }

  private categoryLabel(cat: MemoryCategory): string {
    if (cat === 'identity') return '身份';
    if (cat === 'workflow') return '工作方式';
    if (cat === 'tone') return '表达风格';
    return '用户指令';
  }

  private sourceLabel(src?: MemorySourceKind): string {
    if (src === 'tool') return '工具写入';
    if (src === 'manual') return '手动';
    return '自动提取';
  }

  private personaName(id?: string): string {
    if (!id || id.length === 0) return '全局';
    for (let i = 0; i < this.personas.length; i++) {
      if (this.personas[i].id === id) return this.personas[i].name;
    }
    return `已删除助手 (${id.slice(0, 6)})`;
  }

  private formatTs(ts?: number | string): string {
    const ms = normalizeMemoryTimestamp(ts);
    const d = new Date(ms);
    if (!Number.isFinite(d.getTime())) return '';
    const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
  }

  private formatDateOnly(ts?: number | string): string {
    const ms = normalizeMemoryTimestamp(ts);
    const d = new Date(ms);
    if (!Number.isFinite(d.getTime())) return '';
    const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  }

  private processingModelLabel(): string {
    const pid = this.modelDefaults.memoryProviderId;
    const mid = this.modelDefaults.memoryModelId;
    if (!pid || !mid) return '跟随当前对话模型';
    const prov = this.providers.find((p: Provider): boolean => p.id === pid);
    return prov ? `${prov.name} / ${mid}` : mid;
  }

  private availableModelChoices(): RoleModelChoice[] {
    const enabled = this.providers.filter((p: Provider): boolean =>
      p.enabled !== false && providerEnabledModels(p).length > 0);
    const configured = enabled.filter((p: Provider): boolean => isProviderConfigured(p));
    const source = configured.length > 0 ? configured : enabled;
    const out: RoleModelChoice[] = [];
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

  private isTemplateCustomized(kind: MemoryTemplateKind): boolean {
    const tpl = this.memorySettings.templates;
    if (!tpl) return false;
    if (kind === 'rules') return Boolean(tpl.rulesZh?.trim() || tpl.rulesEn?.trim());
    if (kind === 'gate') return Boolean(tpl.gateZh?.trim() || tpl.gateEn?.trim());
    if (kind === 'extract') return Boolean(tpl.extractZh?.trim() || tpl.extractEn?.trim());
    if (kind === 'smartAddSingle') return Boolean(tpl.smartAddSingleZh?.trim() || tpl.smartAddSingleEn?.trim());
    if (kind === 'smartAddBatch') return Boolean(tpl.smartAddBatchZh?.trim() || tpl.smartAddBatchEn?.trim());
    if (kind === 'profileDistill') return Boolean(tpl.profileDistillZh?.trim() || tpl.profileDistillEn?.trim());
    return Boolean(tpl.legacyMigrateZh?.trim() || tpl.legacyMigrateEn?.trim());
  }

  private getCustomTemplateValue(tpl: MemoryPromptTemplates | undefined, kind: MemoryTemplateKind, lang: 'zh' | 'en'): string {
    if (!tpl) return '';
    if (kind === 'rules') return (lang === 'zh' ? tpl.rulesZh : tpl.rulesEn) || '';
    if (kind === 'gate') return (lang === 'zh' ? tpl.gateZh : tpl.gateEn) || '';
    if (kind === 'extract') return (lang === 'zh' ? tpl.extractZh : tpl.extractEn) || '';
    if (kind === 'smartAddSingle') return (lang === 'zh' ? tpl.smartAddSingleZh : tpl.smartAddSingleEn) || '';
    if (kind === 'smartAddBatch') return (lang === 'zh' ? tpl.smartAddBatchZh : tpl.smartAddBatchEn) || '';
    if (kind === 'profileDistill') return (lang === 'zh' ? tpl.profileDistillZh : tpl.profileDistillEn) || '';
    return (lang === 'zh' ? tpl.legacyMigrateZh : tpl.legacyMigrateEn) || '';
  }

  private setCustomTemplateValue(tpl: MemoryPromptTemplates, kind: MemoryTemplateKind, lang: 'zh' | 'en', val: string | undefined): void {
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

  private openTemplateEditor(kind: MemoryTemplateKind): void {
    const lang: 'zh' | 'en' = this.memorySettings.promptLanguage === 'en' ? 'en' : 'zh';
    this.editTemplateKind = kind;
    this.editTemplateLang = lang;
    this.editTemplateText = getEffectiveMemoryTemplate(this.memorySettings, kind, lang);
    this.navigateSubPage('template');
  }

  private switchTemplateEditorLang(lang: 'zh' | 'en'): void {
    this.editTemplateLang = lang;
    this.editTemplateText = getEffectiveMemoryTemplate(this.memorySettings, this.editTemplateKind, lang);
  }

  private currentTemplateSpec(): TemplateRowSpec {
    for (let i = 0; i < TEMPLATE_ROWS.length; i++) {
      if (TEMPLATE_ROWS[i].kind === this.editTemplateKind) return TEMPLATE_ROWS[i];
    }
    return TEMPLATE_ROWS[0];
  }

  private async saveTemplateEdit(): Promise<void> {
    const next = this.cloneSettings();
    const tpl: MemoryPromptTemplates = next.templates || {};
    const defText = getDefaultMemoryTemplate(this.editTemplateKind, this.editTemplateLang).trim();
    const clean = this.editTemplateText.trim();
    this.setCustomTemplateValue(tpl, this.editTemplateKind, this.editTemplateLang, clean === defText || clean.length === 0 ? undefined : clean);
    next.templates = tpl;
    await this.onSaveSettings(next);
    this.statusTip = '已保存提示词模板';
    this.showToastTip(this.statusTip);
    this.navigateSubPage('home');
  }

  private async resetTemplateToDefault(): Promise<void> {
    const defText = getDefaultMemoryTemplate(this.editTemplateKind, this.editTemplateLang);
    this.editTemplateText = defText;
    const next = this.cloneSettings();
    const tpl: MemoryPromptTemplates = next.templates || {};
    this.setCustomTemplateValue(tpl, this.editTemplateKind, this.editTemplateLang, undefined);
    next.templates = tpl;
    await this.onSaveSettings(next);
    this.statusTip = '已恢复默认模板';
    this.showToastTip(this.statusTip);
  }

  private async updateSettingFlag(field: 'useLegacyMemory' | 'enableThinking' | 'injectGlobal' | 'autoExtract' | 'recordTraces', val: boolean): Promise<void> {
    const next = this.cloneSettings();
    if (field === 'useLegacyMemory') next.useLegacyMemory = val;
    else if (field === 'enableThinking') next.enableThinking = val;
    else if (field === 'injectGlobal') next.injectGlobal = val;
    else if (field === 'autoExtract') next.autoExtract = val;
    else next.recordTraces = val;
    await this.onSaveSettings(next);
  }

  private async updateInjectCount(nextVal: number): Promise<void> {
    const clamped = Math.max(1, Math.min(500, Math.floor(nextVal)));
    const next = this.cloneSettings();
    next.maxInjectCount = clamped;
    await this.onSaveSettings(next);
  }

  private async updatePromptLanguage(lang: MemoryPromptLanguage): Promise<void> {
    const next = this.cloneSettings();
    next.promptLanguage = lang;
    await this.onSaveSettings(next);
  }

  private activeMemoryCount(): number {
    let n = 0;
    for (let i = 0; i < this.memories.length; i++) {
      if (!this.memories[i].archived) n++;
    }
    return n;
  }

  private orphanedList(): MemoryEntry[] {
    return findOrphanedMemories(this.memories, this.personas);
  }

  private orphanCount(): number {
    return this.orphanedList().length;
  }

  private legacyList(): string[] {
    return this.memorySettings.legacyMemories || [];
  }

  private filledProfileCount(): number {
    const norm = normalizeUserProfileFields(this.userProfile);
    let c = 0;
    for (let i = 0; i < norm.length; i++) {
      if (norm[i].value.trim().length > 0) c++;
    }
    return c;
  }

  private standardProfileValue(key: string): string {
    const norm = normalizeUserProfileFields(this.userProfile);
    const target = key.trim().toLowerCase();
    for (let i = 0; i < norm.length; i++) {
      if (profileFieldKey(norm[i]).toLowerCase() === target) {
        return norm[i].value;
      }
    }
    return '';
  }

  private customProfileFields(): UserProfileField[] {
    const norm = normalizeUserProfileFields(this.userProfile);
    return norm.filter((f: UserProfileField): boolean => !isStandardProfileKey(profileFieldKey(f)));
  }

  private async saveProfileFieldValue(key: string, val: string): Promise<void> {
    const cleanKey = key.trim();
    const cleanVal = val.trim();
    const norm = normalizeUserProfileFields(this.userProfile);
    const filtered = norm.filter((f: UserProfileField): boolean =>
      profileFieldKey(f).toLowerCase() !== cleanKey.toLowerCase()
    );
    if (cleanVal.length > 0) {
      filtered.push({
        id: cleanKey,
        key: cleanKey,
        value: cleanVal,
        updatedAt: Date.now(),
        source: 'manual'
      });
    }
    this.editingProfileKey = '';
    this.editingProfileVal = '';
    await this.onSaveProfile(filtered);
    this.statusTip = cleanVal.length > 0 ? `已更新画像字段：${profileKeyDisplayLabel(cleanKey)}` : '已清除该画像字段';
  }

  private async addCustomProfileField(): Promise<void> {
    const k = this.newProfileKey.trim();
    const v = this.newProfileVal.trim();
    if (k.length === 0 || v.length === 0) {
      this.statusTip = '请填写字段名称和内容';
      this.showToastTip(this.statusTip);
      return;
    }
    await this.saveProfileFieldValue(k, v);
    this.newProfileKey = '';
    this.newProfileVal = '';
    this.closeSheet();
    this.showToastTip('已保存自定义画像字段');
  }

  private isValidPersonaId(id: string): boolean {
    for (let i = 0; i < this.personas.length; i++) {
      if (this.personas[i].id === id) return true;
    }
    return false;
  }

  private filteredEntries(): MemoryEntry[] {
    const includeArchived = this.filterStatus !== 'active';
    const base = searchMemories(this.memories, this.searchQuery, undefined, includeArchived);
    const out: MemoryEntry[] = [];
    for (let i = 0; i < base.length; i++) {
      const m = base[i];
      if (this.filterStatus === 'active' && m.archived) continue;
      if (this.filterStatus === 'archived' && !m.archived) continue;
      if (this.filterCat !== 'all' && m.category !== this.filterCat) continue;
      if (this.filterScope === 'global') {
        if (m.assistantId && m.assistantId.trim().length > 0) continue;
      } else if (this.filterScope === 'orphan') {
        if (!m.assistantId || this.isValidPersonaId(m.assistantId)) continue;
      } else if (this.filterScope !== 'all') {
        if (m.assistantId !== this.filterScope) continue;
      }
      out.push(m);
    }
    return out;
  }

  private pagedEntries(): MemoryEntry[] {
    return this.filteredEntries().slice(0, this.pageLimit);
  }

  private filteredTotalCount(): number {
    return this.filteredEntries().length;
  }

  private remainingEntryCount(): number {
    const total = this.filteredTotalCount();
    return total > this.pageLimit ? total - this.pageLimit : 0;
  }

  private scopeLabelText(): string {
    if (this.filterScope === 'all') return '全部范围';
    if (this.filterScope === 'global') return '全局';
    if (this.filterScope === 'orphan') return '孤立助手';
    return this.personaName(this.filterScope);
  }

  private openAddEntryEditor(): void {
    this.editingEntryId = '';
    this.entryCat = 'instruction';
    this.entryContent = '';
    this.entryScopeId = (this.filterScope !== 'all' && this.filterScope !== 'global' && this.filterScope !== 'orphan')
      ? this.filterScope
      : '';
    this.openSheet('entry');
  }

  private openEditEntryEditor(item: MemoryEntry): void {
    this.editingEntryId = item.id;
    this.entryCat = item.category;
    this.entryContent = item.content;
    this.entryScopeId = item.assistantId || '';
    this.openSheet('entry');
  }

  private async saveEntryEditor(): Promise<void> {
    const clean = this.entryContent.trim();
    if (clean.length === 0) {
      this.statusTip = '请输入记忆内容';
      this.showToastTip(this.statusTip);
      return;
    }
    const now = Date.now();
    const scopeId = this.entryScopeId.trim().length > 0 ? this.entryScopeId.trim() : undefined;
    if (this.editingEntryId.length > 0) {
      const next: MemoryEntry[] = [];
      for (let i = 0; i < this.memories.length; i++) {
        const m = this.memories[i];
        if (m.id === this.editingEntryId) {
          next.push({
            id: m.id,
            category: this.entryCat,
            content: clean,
            assistantId: scopeId,
            archived: m.archived,
            createdAt: normalizeMemoryTimestamp(m.createdAt),
            updatedAt: now,
            sourceConversationId: m.sourceConversationId,
            source: m.source || 'manual',
            relatedIds: m.relatedIds
          });
        } else {
          next.push(m);
        }
      }
      await this.onSaveMemories(next);
      this.statusTip = '已更新记忆条目';
    } else {
      const next = this.memories.slice();
      next.unshift({
        id: 'mem_' + newId(),
        category: this.entryCat,
        content: clean,
        assistantId: scopeId,
        archived: false,
        createdAt: now,
        updatedAt: now,
        source: 'manual'
      });
      await this.onSaveMemories(next);
      this.statusTip = '已添加长期记忆';
    }
    this.closeSheet();
    this.editingEntryId = '';
    this.entryContent = '';
    this.showToastTip(this.statusTip);
  }

  private async toggleArchive(id: string): Promise<void> {
    const next: MemoryEntry[] = [];
    for (let i = 0; i < this.memories.length; i++) {
      const m = this.memories[i];
      if (m.id === id) {
        next.push({
          id: m.id,
          category: m.category,
          content: m.content,
          assistantId: m.assistantId,
          archived: !m.archived,
          createdAt: normalizeMemoryTimestamp(m.createdAt),
          updatedAt: Date.now(),
          sourceConversationId: m.sourceConversationId,
          source: m.source,
          relatedIds: m.relatedIds
        });
      } else {
        next.push(m);
      }
    }
    await this.onSaveMemories(next);
  }

  private async deleteMemory(id: string): Promise<void> {
    await this.onSaveMemories(this.memories.filter((m: MemoryEntry): boolean => m.id !== id));
  }

  private async cleanupOrphaned(convertToGlobal: boolean): Promise<void> {
    const orphans = this.orphanedList();
    if (orphans.length === 0) return;
    const orphanIds = new Set<string>(orphans.map((m: MemoryEntry): string => m.id));
    if (convertToGlobal) {
      const next: MemoryEntry[] = [];
      for (let i = 0; i < this.memories.length; i++) {
        const m = this.memories[i];
        if (orphanIds.has(m.id)) {
          next.push({
            id: m.id,
            category: m.category,
            content: m.content,
            assistantId: undefined,
            archived: m.archived,
            createdAt: normalizeMemoryTimestamp(m.createdAt),
            updatedAt: Date.now(),
            sourceConversationId: m.sourceConversationId,
            source: m.source,
            relatedIds: m.relatedIds
          });
        } else {
          next.push(m);
        }
      }
      await this.onSaveMemories(next);
      this.statusTip = `已将 ${orphans.length} 条孤立记忆转为全局`;
    } else {
      await this.onSaveMemories(this.memories.filter((m: MemoryEntry): boolean => !orphanIds.has(m.id)));
      if (this.filterScope === 'orphan') this.filterScope = 'all';
      this.statusTip = `已清理 ${orphans.length} 条孤立助手记忆`;
    }
  }

  private toggleSelected(id: string): void {
    const idx = this.selectedIds.indexOf(id);
    const next = this.selectedIds.slice();
    if (idx >= 0) next.splice(idx, 1);
    else next.push(id);
    this.selectedIds = next;
  }

  private async batchDeleteSelected(): Promise<void> {
    if (this.selectedIds.length === 0) return;
    const sel = new Set<string>(this.selectedIds);
    await this.onSaveMemories(this.memories.filter((m: MemoryEntry): boolean => !sel.has(m.id)));
    this.statusTip = `已删除 ${sel.size} 条记忆`;
    this.selectedIds = [];
    this.multiSelect = false;
  }

  private async batchToggleArchiveSelected(): Promise<void> {
    if (this.selectedIds.length === 0) return;
    const sel = new Set<string>(this.selectedIds);
    const archiveMode = this.filterStatus !== 'archived';
    const next: MemoryEntry[] = [];
    for (let i = 0; i < this.memories.length; i++) {
      const m = this.memories[i];
      if (sel.has(m.id)) {
        next.push({
          id: m.id,
          category: m.category,
          content: m.content,
          assistantId: m.assistantId,
          archived: archiveMode,
          createdAt: normalizeMemoryTimestamp(m.createdAt),
          updatedAt: Date.now(),
          sourceConversationId: m.sourceConversationId,
          source: m.source,
          relatedIds: m.relatedIds
        });
      } else {
        next.push(m);
      }
    }
    await this.onSaveMemories(next);
    this.statusTip = archiveMode ? `已归档 ${sel.size} 条记忆` : `已恢复 ${sel.size} 条记忆`;
    this.selectedIds = [];
    this.multiSelect = false;
  }

  private async copyAllMemoriesMarkdown(): Promise<void> {
    const lines: string[] = ['# Kelivo 长期记忆导出', ''];
    const profile = normalizeUserProfileFields(this.userProfile);
    if (profile.length > 0) {
      lines.push('## 用户画像');
      for (let i = 0; i < profile.length; i++) {
        lines.push(`- **${profileKeyDisplayLabel(profile[i].key)}**: ${profile[i].value}`);
      }
      lines.push('');
    }
    lines.push('## 记忆条目');
    for (let i = 0; i < this.memories.length; i++) {
      const m = this.memories[i];
      lines.push(`- [${m.category}][${this.personaName(m.assistantId)}]${m.archived ? '[已归档]' : ''} ${m.content}`);
    }
    try {
      await pasteboard.getSystemPasteboard().setData(
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, lines.join('\n'))
      );
      this.statusTip = '已复制全部记忆与画像 (Markdown) 到剪贴板';
      this.showToastTip('已复制到剪贴板');
    } catch (e) {
      this.statusTip = `复制失败: ${String(e)}`;
    }
  }

  private traceStepsFor(tr: MemoryTrace): MemoryTraceStep[] {
    return tr.steps || [];
  }

  private subPageTitle(): string {
    if (this.subPage === 'list') return '记忆列表';
    if (this.subPage === 'profile') return '用户画像';
    if (this.subPage === 'legacy') return '旧版记忆（只读）';
    if (this.subPage === 'traces') return '流水线追踪';
    if (this.subPage === 'about') return '关于记忆';
    if (this.subPage === 'template') return this.currentTemplateSpec().title;
    if (this.subPage === 'modelPicker') return '选择记忆处理模型';
    return '记忆';
  }

  @Builder
  private sectionLabel(text: string) {
    Text(text)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.muted'))
      .padding({ left: 4, top: 4 })
      .width('100%')
  }

  @Builder
  private navRow(title: string, subtitle: string, trailing: string, showWarnDot: boolean, onTap: () => void) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
        if (subtitle.length > 0) {
          Text(subtitle)
            .fontSize(12)
            .fontColor($r('app.color.muted'))
            .maxLines(2)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (trailing.length > 0) {
        Text(trailing)
          .fontSize(12)
          .fontColor(showWarnDot ? $r('app.color.warning') : $r('app.color.muted'))
      }
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(15)
        .fontColor([$r('app.color.muted')])
    }
    .width('100%')
    .padding({ left: 14, right: 12, top: 12, bottom: 12 })
    .onClick(() => { onTap(); })
  }

  @Builder
  private renderHomeSubPage() {
    Column({ space: 12 }) {
      this.sectionLabel('记忆模式')
      Column() {
        Row({ space: 12 }) {
          Column({ space: 2 }) {
            Text('使用旧版记忆')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))
            Text('全局设置，对所有助手生效')
              .fontSize(12)
              .fontColor($r('app.color.muted'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.memorySettings.useLegacyMemory === true })
            .onChange(async (v: boolean) => {
              await this.updateSettingFlag('useLegacyMemory', v);
            })
            .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
        }
        .width('100%')
        .padding({ left: 14, right: 12, top: 12, bottom: 12 })
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)

      this.sectionLabel('记忆模型')
      Column() {
        this.navRow(
          '处理模型',
          this.processingModelLabel(),
          '',
          false,
          () => { this.navigateSubPage('modelPicker'); }
        )
        Divider().color($r('app.color.line')).margin({ left: 14 })
        Row({ space: 12 }) {
          Column({ space: 2 }) {
            Text('启用思考')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))
            Text('支持时允许记忆模型在整理阶段使用推理')
              .fontSize(12)
              .fontColor($r('app.color.muted'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.memorySettings.enableThinking !== false })
            .onChange(async (v: boolean) => {
              await this.updateSettingFlag('enableThinking', v);
            })
            .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
        }
        .width('100%')
        .padding({ left: 14, right: 12, top: 12, bottom: 12 })
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)

      this.sectionLabel('记忆注入')
      Column() {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            Column({ space: 2 }) {
              Text('每类注入条数')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.ink'))
              Text('各类记忆默认注入上下文的最新条目上限')
                .fontSize(12)
                .fontColor($r('app.color.muted'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Button('-')
              .type(ButtonType.Normal)
              .width(30)
              .height(30)
              .padding(0)
              .fontSize(16)
              .borderRadius(8)
              .fontColor($r('app.color.ink'))
              .backgroundColor($r('app.color.canvas'))
              .onClick(async () => {
                await this.updateInjectCount(this.memorySettings.maxInjectCount - 5);
              })
            Text(`${this.memorySettings.maxInjectCount}`)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.accent'))
              .constraintSize({ minWidth: 32 })
              .textAlign(TextAlign.Center)
            Button('+')
              .type(ButtonType.Normal)
              .width(30)
              .height(30)
              .padding(0)
              .fontSize(16)
              .borderRadius(8)
              .fontColor($r('app.color.ink'))
              .backgroundColor($r('app.color.canvas'))
              .onClick(async () => {
                await this.updateInjectCount(this.memorySettings.maxInjectCount + 5);
              })
          }
          .width('100%')

          Row({ space: 6 }) {
            ForEach([10, 30, 100, 200], (presetVal: number) => {
              Button(`${presetVal}`)
                .type(ButtonType.Normal)
                .height(26)
                .fontSize(11)
                .borderRadius(8)
                .padding({ left: 10, right: 10 })
                .fontColor(this.memorySettings.maxInjectCount === presetVal ? $r('app.color.on_accent') : $r('app.color.ink'))
                .backgroundColor(this.memorySettings.maxInjectCount === presetVal ? $r('app.color.accent') : $r('app.color.canvas'))
                .onClick(async () => {
                  await this.updateInjectCount(presetVal);
                })
            }, (presetVal: number) => `inj_${presetVal}`)
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 14, right: 12, top: 12, bottom: 12 })

        Divider().color($r('app.color.line')).margin({ left: 14 })

        Row({ space: 12 }) {
          Column({ space: 2 }) {
            Text('注入全局记忆与用户画像')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))
            Text('开启后所有启用记忆的助手都可读取全局画像与记忆')
              .fontSize(12)
              .fontColor($r('app.color.muted'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.memorySettings.injectGlobal !== false })
            .onChange(async (v: boolean) => {
              await this.updateSettingFlag('injectGlobal', v);
            })
            .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
        }
        .width('100%')
        .padding({ left: 14, right: 12, top: 12, bottom: 12 })

        Divider().color($r('app.color.line')).margin({ left: 14 })

        Row({ space: 12 }) {
          Column({ space: 2 }) {
            Text('默认自动整理记忆')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))
            Text('适用于自动整理设为「跟随全局」的助手')
              .fontSize(12)
              .fontColor($r('app.color.muted'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.memorySettings.autoExtract === true })
            .onChange(async (v: boolean) => {
              await this.updateSettingFlag('autoExtract', v);
            })
            .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
        }
        .width('100%')
        .padding({ left: 14, right: 12, top: 12, bottom: 12 })
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)

      this.sectionLabel('提示词语言')
      Column() {
        Row({ space: 10 }) {
          Column({ space: 2 }) {
            Text('自动').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink'))
            Text('跟随界面语言（中文 → zh，否则 en）').fontSize(12).fontColor($r('app.color.muted'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          if ((this.memorySettings.promptLanguage || 'auto') === 'auto') {
            SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16).fontColor([$r('app.color.accent')])
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .onClick(async () => { await this.updatePromptLanguage('auto'); })

        Divider().color($r('app.color.line')).margin({ left: 14 })

        Row({ space: 10 }) {
          Column({ space: 2 }) {
            Text('中文').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink'))
            Text('始终使用中文记忆提示词与工具描述').fontSize(12).fontColor($r('app.color.muted'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          if (this.memorySettings.promptLanguage === 'zh') {
            SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16).fontColor([$r('app.color.accent')])
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .onClick(async () => { await this.updatePromptLanguage('zh'); })

        Divider().color($r('app.color.line')).margin({ left: 14 })

        Row({ space: 10 }) {
          Column({ space: 2 }) {
            Text('English').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink'))
            Text('Always use English memory prompts and tool descriptions').fontSize(12).fontColor($r('app.color.muted'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          if (this.memorySettings.promptLanguage === 'en') {
            SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16).fontColor([$r('app.color.accent')])
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .onClick(async () => { await this.updatePromptLanguage('en'); })
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)

      this.sectionLabel('提示词模板')
      Column() {
        ForEach(TEMPLATE_ROWS, (spec: TemplateRowSpec, idx: number) => {
          Column() {
            if (idx > 0) {
              Divider().color($r('app.color.line')).margin({ left: 14 })
            }
            this.navRow(
              spec.title,
              spec.subtitle,
              this.isTemplateCustomized(spec.kind) ? '已自定义' : '默认',
              false,
              () => { this.openTemplateEditor(spec.kind); }
            )
          }
        }, (spec: TemplateRowSpec) => `tpl_${spec.kind}`)
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)

      this.sectionLabel('全部记忆')
      Column() {
        this.navRow(
          '记忆列表',
          '浏览、筛选、编辑、归档与清理记忆',
          this.orphanCount() > 0 ? `${this.activeMemoryCount()} 条 · ${this.orphanCount()} 孤立` : `${this.activeMemoryCount()} 条`,
          this.orphanCount() > 0,
          () => {
            this.pageLimit = 40;
            this.navigateSubPage('list');
          }
        )
        Divider().color($r('app.color.line')).margin({ left: 14 })
        this.navRow(
          '用户画像',
          '7 个标准字段与自定义结构化属性',
          `${this.filledProfileCount()} 项`,
          false,
          () => { this.navigateSubPage('profile'); }
        )
        Divider().color($r('app.color.line')).margin({ left: 14 })
        this.navRow(
          '旧版记忆（只读）',
          '来自旧版或导入的自由文本记忆',
          `${this.legacyList().length} 条`,
          false,
          () => { this.navigateSubPage('legacy'); }
        )
        Divider().color($r('app.color.line')).margin({ left: 14 })
        this.navRow(
          '流水线追踪',
          '逐步检查 Gatekeeper / Extract / Smart Add / 画像提炼',
          `${this.memoryTraces.length} 条`,
          false,
          () => { this.navigateSubPage('traces'); }
        )
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)

      Column() {
        this.navRow(
          '关于记忆',
          '了解记忆类型、全局与助手范围及注入机制',
          '',
          false,
          () => { this.navigateSubPage('about'); }
        )
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)

      Row({ space: 8 }) {
        Button('复制导出 Markdown')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(40)
          .fontSize(13)
          .borderRadius(10)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor($r('app.color.accent'))
          .onClick(async () => {
            await this.copyAllMemoriesMarkdown();
          })
        Button('清理已归档')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(40)
          .fontSize(13)
          .borderRadius(10)
          .fontColor($r('app.color.warning'))
          .backgroundColor($r('app.color.surface'))
          .onClick(async () => {
            await this.onSaveMemories(this.memories.filter((m: MemoryEntry): boolean => !m.archived));
            this.statusTip = '已清理所有已归档记忆';
          })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private renderModelPickerSubPage() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text('跟随当前对话模型')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
          Text('不指定独立记忆模型，直接使用对话所选模型')
            .fontSize(12)
            .fontColor($r('app.color.muted'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (!this.modelDefaults.memoryProviderId || !this.modelDefaults.memoryModelId) {
          SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16).fontColor([$r('app.color.accent')])
        }
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)
      .onClick(async () => {
        const next = this.cloneModelDefaults();
        next.memoryProviderId = '';
        next.memoryModelId = '';
        await this.onSaveModelDefaults(next);
        this.statusTip = '记忆处理模型已设为跟随对话模型';
        this.navigateSubPage('home');
      })

      ForEach(this.availableModelChoices(), (choice: RoleModelChoice) => {
        Row({ space: 10 }) {
          Column({ space: 2 }) {
            Text(choice.modelId)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))
            Text(choice.providerName)
              .fontSize(12)
              .fontColor($r('app.color.muted'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          if (this.modelDefaults.memoryProviderId === choice.providerId &&
            this.modelDefaults.memoryModelId === choice.modelId) {
            SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16).fontColor([$r('app.color.accent')])
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor($r('app.color.surface'))
        .borderRadius(12)
        .onClick(async () => {
          const next = this.cloneModelDefaults();
          next.memoryProviderId = choice.providerId;
          next.memoryModelId = choice.modelId;
          await this.onSaveModelDefaults(next);
          this.statusTip = `处理模型已设为 ${choice.providerName} / ${choice.modelId}`;
          this.navigateSubPage('home');
        })
      }, (choice: RoleModelChoice) => `mp_${choice.key}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private renderTemplateSubPage() {
    Column({ space: 12 }) {
      Text(this.currentTemplateSpec().subtitle)
        .fontSize(12)
        .fontColor($r('app.color.muted'))

      Row({ space: 8 }) {
        Button('中文模板')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(34)
          .fontSize(12)
          .borderRadius(10)
          .fontColor(this.editTemplateLang === 'zh' ? $r('app.color.on_accent') : $r('app.color.ink'))
          .backgroundColor(this.editTemplateLang === 'zh' ? $r('app.color.accent') : $r('app.color.surface'))
          .onClick(() => { this.switchTemplateEditorLang('zh'); })
        Button('English 模板')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(34)
          .fontSize(12)
          .borderRadius(10)
          .fontColor(this.editTemplateLang === 'en' ? $r('app.color.on_accent') : $r('app.color.ink'))
          .backgroundColor(this.editTemplateLang === 'en' ? $r('app.color.accent') : $r('app.color.surface'))
          .onClick(() => { this.switchTemplateEditorLang('en'); })
      }
      .width('100%')

      TextArea({ text: this.editTemplateText, placeholder: '输入提示词模板内容...' })
        .width('100%')
        .height(360)
        .fontSize(13)
        .borderRadius(12)
        .backgroundColor($r('app.color.surface'))
        .onChange((v: string) => {
          this.editTemplateText = v;
        })

      Row({ space: 8 }) {
        Button('恢复默认')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(40)
          .fontSize(13)
          .borderRadius(10)
          .fontColor($r('app.color.warning'))
          .backgroundColor($r('app.color.surface'))
          .onClick(async () => { await this.resetTemplateToDefault(); })

        Button('保存模板')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(40)
          .fontSize(13)
          .borderRadius(10)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor($r('app.color.accent'))
          .onClick(async () => { await this.saveTemplateEdit(); })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private renderListSubPage() {
    Column({ space: 10 }) {
      Row({ space: 6 }) {
        TextInput({ text: this.searchQuery, placeholder: '搜索记忆关键词...' })
          .layoutWeight(1)
          .height(38)
          .borderRadius(12)
          .backgroundColor($r('app.color.surface'))
          .onChange((v: string) => {
            this.searchQuery = v;
            this.pageLimit = 40;
          })
        Button(this.multiSelect ? '取消多选' : '多选')
          .type(ButtonType.Normal)
          .height(38)
          .fontSize(12)
          .borderRadius(10)
          .fontColor(this.multiSelect ? $r('app.color.on_accent') : $r('app.color.ink'))
          .backgroundColor(this.multiSelect ? $r('app.color.accent') : $r('app.color.surface'))
          .onClick(() => {
            this.multiSelect = !this.multiSelect;
            this.selectedIds = [];
          })
        Button('+ 添加')
          .type(ButtonType.Normal)
          .height(38)
          .fontSize(12)
          .borderRadius(10)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor($r('app.color.accent'))
          .onClick(() => { this.openAddEntryEditor(); })
      }
      .width('100%')

      // Scope filter strip
      Scroll() {
        Row({ space: 6 }) {
          Button('全部范围')
            .type(ButtonType.Normal).height(28).fontSize(11).borderRadius(14).padding({ left: 12, right: 12 })
            .fontColor(this.filterScope === 'all' ? $r('app.color.on_accent') : $r('app.color.ink'))
            .backgroundColor(this.filterScope === 'all' ? $r('app.color.accent') : $r('app.color.surface'))
            .onClick(() => { this.filterScope = 'all'; this.pageLimit = 40; })
          Button('全局')
            .type(ButtonType.Normal).height(28).fontSize(11).borderRadius(14).padding({ left: 12, right: 12 })
            .fontColor(this.filterScope === 'global' ? $r('app.color.on_accent') : $r('app.color.ink'))
            .backgroundColor(this.filterScope === 'global' ? $r('app.color.accent') : $r('app.color.surface'))
            .onClick(() => { this.filterScope = 'global'; this.pageLimit = 40; })
          if (this.orphanCount() > 0) {
            Button(`孤立 (${this.orphanCount()})`)
              .type(ButtonType.Normal).height(28).fontSize(11).borderRadius(14).padding({ left: 12, right: 12 })
              .fontColor(this.filterScope === 'orphan' ? $r('app.color.on_accent') : $r('app.color.warning'))
              .backgroundColor(this.filterScope === 'orphan' ? $r('app.color.warning') : $r('app.color.surface'))
              .onClick(() => { this.filterScope = 'orphan'; this.pageLimit = 40; })
          }
          ForEach(this.personas, (p: Persona) => {
            Button(p.name)
              .type(ButtonType.Normal).height(28).fontSize(11).borderRadius(14).padding({ left: 12, right: 12 })
              .fontColor(this.filterScope === p.id ? $r('app.color.on_accent') : $r('app.color.ink'))
              .backgroundColor(this.filterScope === p.id ? $r('app.color.accent') : $r('app.color.surface'))
              .onClick(() => { this.filterScope = p.id; this.pageLimit = 40; })
          }, (p: Persona) => `fs_${p.id}`)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      // Type + Status filter strip
      Scroll() {
        Row({ space: 6 }) {
          ForEach(['all', 'identity', 'workflow', 'tone', 'instruction'], (cat: string) => {
            Button(cat === 'all' ? '全部类型' : this.categoryLabel(cat as MemoryCategory))
              .type(ButtonType.Normal).height(26).fontSize(11).borderRadius(8).padding({ left: 10, right: 10 })
              .fontColor(this.filterCat === cat ? $r('app.color.accent') : $r('app.color.muted'))
              .backgroundColor(this.filterCat === cat ? $r('app.color.tint') : $r('app.color.surface'))
              .onClick(() => { this.filterCat = cat; this.pageLimit = 40; })
          }, (cat: string) => `fc_${cat}`)

          Button(this.filterStatus === 'active' ? '状态：生效中' : (this.filterStatus === 'archived' ? '状态：已归档' : '状态：全部'))
            .type(ButtonType.Normal).height(26).fontSize(11).borderRadius(8).padding({ left: 10, right: 10 })
            .fontColor($r('app.color.ink'))
            .backgroundColor($r('app.color.surface'))
            .onClick(() => {
              this.filterStatus = this.filterStatus === 'active' ? 'archived' : (this.filterStatus === 'archived' ? 'all' : 'active');
              this.pageLimit = 40;
            })
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      // Orphaned assistant memories banner
      if (this.orphanCount() > 0) {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
              .fontSize(18)
              .fontColor([$r('app.color.warning')])
            Text(`${this.orphanCount()} 条孤立助手记忆（原助手已删除）`)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))
              .layoutWeight(1)
          }
          .width('100%')

          Row({ space: 8 }) {
            Button('转为全局')
              .type(ButtonType.Normal)
              .layoutWeight(1)
              .height(30)
              .fontSize(12)
              .borderRadius(8)
              .fontColor($r('app.color.accent'))
              .backgroundColor($r('app.color.surface'))
              .onClick(async () => { await this.cleanupOrphaned(true); })

            Button('一键清理')
              .type(ButtonType.Normal)
              .layoutWeight(1)
              .height(30)
              .fontSize(12)
              .borderRadius(8)
              .fontColor($r('app.color.on_accent'))
              .backgroundColor($r('app.color.warning'))
              .onClick(async () => { await this.cleanupOrphaned(false); })
          }
          .width('100%')
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#14BB0947')
        .borderRadius(12)
      }

      if (this.multiSelect) {
        Row({ space: 8 }) {
          Text(`已选 ${this.selectedIds.length} 条`)
            .fontSize(12)
            .fontColor($r('app.color.ink'))
          Blank()
          Button(this.filterStatus === 'archived' ? '批量恢复' : '批量归档')
            .type(ButtonType.Normal)
            .height(28)
            .fontSize(11)
            .borderRadius(8)
            .fontColor($r('app.color.accent'))
            .backgroundColor($r('app.color.tint'))
            .enabled(this.selectedIds.length > 0)
            .onClick(async () => { await this.batchToggleArchiveSelected(); })
          Button('批量删除')
            .type(ButtonType.Normal)
            .height(28)
            .fontSize(11)
            .borderRadius(8)
            .fontColor($r('app.color.on_accent'))
            .backgroundColor($r('app.color.warning'))
            .enabled(this.selectedIds.length > 0)
            .onClick(async () => { await this.batchDeleteSelected(); })
        }
        .width('100%')
        .padding(10)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(10)
      }

      Text(`当前筛选（${this.scopeLabelText()}）：共 ${this.filteredTotalCount()} 条`)
        .fontSize(11)
        .fontColor($r('app.color.muted'))
        .padding({ left: 2 })

      if (this.filteredTotalCount() === 0) {
        Text('暂无匹配的记忆条目')
          .fontSize(13)
          .fontColor($r('app.color.muted'))
          .padding(24)
      } else {
        ForEach(this.pagedEntries(), (item: MemoryEntry) => {
          Column({ space: 8 }) {
            Row({ space: 6 }) {
              if (this.multiSelect) {
                Button(this.selectedIds.indexOf(item.id) >= 0 ? '☑' : '☐')
                  .type(ButtonType.Normal)
                  .width(28)
                  .height(26)
                  .padding(0)
                  .fontSize(13)
                  .borderRadius(6)
                  .fontColor(this.selectedIds.indexOf(item.id) >= 0 ? $r('app.color.accent') : $r('app.color.muted'))
                  .backgroundColor(Color.Transparent)
                  .onClick(() => { this.toggleSelected(item.id); })
              }
              Text(this.categoryLabel(item.category))
                .fontSize(11)
                .fontColor($r('app.color.accent'))
                .backgroundColor($r('app.color.tint'))
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .borderRadius(10)

              Text(this.personaName(item.assistantId))
                .fontSize(11)
                .fontColor($r('app.color.muted'))
                .backgroundColor($r('app.color.canvas'))
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .borderRadius(10)
                .maxLines(1)

              Blank()

              Button('编辑')
                .type(ButtonType.Normal)
                .height(26)
                .fontSize(11)
                .padding({ left: 8, right: 8 })
                .borderRadius(6)
                .fontColor($r('app.color.accent'))
                .backgroundColor($r('app.color.canvas'))
                .onClick(() => { this.openEditEntryEditor(item); })

              Button(item.archived ? '恢复' : '归档')
                .type(ButtonType.Normal)
                .height(26)
                .fontSize(11)
                .padding({ left: 8, right: 8 })
                .borderRadius(6)
                .fontColor($r('app.color.ink'))
                .backgroundColor($r('app.color.canvas'))
                .onClick(async () => { await this.toggleArchive(item.id); })

              Button('删除')
                .type(ButtonType.Normal)
                .height(26)
                .fontSize(11)
                .padding({ left: 8, right: 8 })
                .borderRadius(6)
                .fontColor($r('app.color.warning'))
                .backgroundColor($r('app.color.canvas'))
                .onClick(async () => { await this.deleteMemory(item.id); })
            }
            .width('100%')

            Text(item.content)
              .fontSize(14)
              .lineHeight(20)
              .fontColor($r('app.color.ink'))
              .copyOption(CopyOptions.LocalDevice)

            Text(`更新于 ${this.formatDateOnly(item.updatedAt)} · ${this.sourceLabel(item.source)}${item.archived ? ' · 已归档' : ''}`)
              .fontSize(11)
              .fontColor($r('app.color.muted'))
          }
          .alignItems(HorizontalAlign.Start)
          .padding(12)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .width('100%')
        }, (item: MemoryEntry) => `${item.id}_${item.updatedAt}_${item.archived}_${this.selectedIds.indexOf(item.id) >= 0}`)

        if (this.remainingEntryCount() > 0) {
          Button(`加载更多（剩余 ${this.remainingEntryCount()} 条）`)
            .type(ButtonType.Normal)
            .width('100%')
            .height(40)
            .fontSize(13)
            .borderRadius(12)
            .fontColor($r('app.color.accent'))
            .backgroundColor($r('app.color.surface'))
            .onClick(() => {
              this.pageLimit += 50;
            })
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private renderProfileSubPage() {
    Column({ space: 12 }) {
      this.sectionLabel('标准画像字段')
      Column() {
        ForEach(STANDARD_PROFILE_FIELDS, (spec: StandardProfileFieldSpec, idx: number) => {
          Column() {
            if (idx > 0) {
              Divider().color($r('app.color.line')).margin({ left: 14 })
            }
            if (this.editingProfileKey === spec.key) {
              Column({ space: 8 }) {
                Text(spec.labelZh)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.ink'))
                TextInput({ text: this.editingProfileVal, placeholder: spec.placeholderZh })
                  .height(38)
                  .borderRadius(8)
                  .backgroundColor($r('app.color.canvas'))
                  .onChange((v: string) => { this.editingProfileVal = v; })
                Row({ space: 8 }) {
                  Button('清空')
                    .type(ButtonType.Normal)
                    .height(30)
                    .fontSize(12)
                    .borderRadius(8)
                    .fontColor($r('app.color.warning'))
                    .backgroundColor($r('app.color.canvas'))
                    .onClick(async () => { await this.saveProfileFieldValue(spec.key, ''); })
                  Blank()
                  Button('取消')
                    .type(ButtonType.Normal)
                    .height(30)
                    .fontSize(12)
                    .borderRadius(8)
                    .fontColor($r('app.color.muted'))
                    .backgroundColor($r('app.color.canvas'))
                    .onClick(() => { this.editingProfileKey = ''; })
                  Button('保存')
                    .type(ButtonType.Normal)
                    .height(30)
                    .fontSize(12)
                    .borderRadius(8)
                    .fontColor($r('app.color.on_accent'))
                    .backgroundColor($r('app.color.accent'))
                    .onClick(async () => { await this.saveProfileFieldValue(spec.key, this.editingProfileVal); })
                }
                .width('100%')
              }
              .width('100%')
              .padding(14)
              .alignItems(HorizontalAlign.Start)
            } else {
              Row({ space: 10 }) {
                Column({ space: 2 }) {
                  Text(spec.labelZh)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.ink'))
                  Text(this.standardProfileValue(spec.key).length > 0 ? this.standardProfileValue(spec.key) : '未设置')
                    .fontSize(13)
                    .fontColor(this.standardProfileValue(spec.key).length > 0 ? $r('app.color.ink') : $r('app.color.muted'))
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(15)
                  .fontColor([$r('app.color.muted')])
              }
              .width('100%')
              .padding({ left: 14, right: 12, top: 12, bottom: 12 })
              .onClick(() => {
                this.editingProfileKey = spec.key;
                this.editingProfileVal = this.standardProfileValue(spec.key);
              })
            }
          }
        }, (spec: StandardProfileFieldSpec) => `stdprof_${spec.key}`)
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)

      this.sectionLabel('自定义字段')
      ForEach(this.customProfileFields(), (f: UserProfileField) => {
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text(profileKeyDisplayLabel(profileFieldKey(f)))
              .fontSize(13)
              .fontColor($r('app.color.accent'))
            Text(f.value)
              .fontSize(14)
              .fontColor($r('app.color.ink'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button('编辑')
            .type(ButtonType.Normal)
            .height(28)
            .fontSize(11)
            .borderRadius(6)
            .fontColor($r('app.color.accent'))
            .backgroundColor($r('app.color.canvas'))
            .onClick(() => {
              this.newProfileKey = profileFieldKey(f);
              this.newProfileVal = f.value;
              this.openSheet('profile');
            })
          Button('删除')
            .type(ButtonType.Normal)
            .height(28)
            .fontSize(11)
            .borderRadius(6)
            .fontColor($r('app.color.warning'))
            .backgroundColor($r('app.color.canvas'))
            .onClick(async () => {
              await this.saveProfileFieldValue(profileFieldKey(f), '');
            })
        }
        .width('100%')
        .padding(12)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(12)
      }, (f: UserProfileField) => `cust_${f.id}_${f.key}_${f.value}`)

      Button('+ 添加自定义字段')
        .type(ButtonType.Normal)
        .width('100%')
        .height(42)
        .fontSize(14)
        .borderRadius(12)
        .fontColor($r('app.color.accent'))
        .backgroundColor($r('app.color.surface'))
        .onClick(() => {
          this.newProfileKey = '';
          this.newProfileVal = '';
          this.openSheet('profile');
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private renderLegacySubPage() {
    Column({ space: 10 }) {
      if (this.legacyList().length === 0) {
        Text('暂无旧版只读记忆')
          .fontSize(13)
          .fontColor($r('app.color.muted'))
          .padding(20)
      } else {
        ForEach(this.legacyList(), (item: string, idx: number) => {
          Row({ space: 8 }) {
            Text(`${idx + 1}.`)
              .fontSize(12)
              .fontColor($r('app.color.accent'))
            Text(item)
              .fontSize(13)
              .lineHeight(19)
              .fontColor($r('app.color.ink'))
              .layoutWeight(1)
              .copyOption(CopyOptions.LocalDevice)
          }
          .width('100%')
          .padding(12)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .alignItems(VerticalAlign.Top)
        }, (item: string, idx: number) => `leg_${idx}_${item.slice(0, 16)}`)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private renderTracesSubPage() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text('记录流水线追踪')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
          Text('保存每轮记忆整理的步骤耗时与提示词详情')
            .fontSize(12)
            .fontColor($r('app.color.muted'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.memorySettings.recordTraces !== false })
          .onChange(async (v: boolean) => {
            await this.updateSettingFlag('recordTraces', v);
          })
          .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
      }
      .width('100%')
      .padding(12)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(12)

      Row() {
        Text(`共 ${this.memoryTraces.length} 条流水线记录`)
          .fontSize(12)
          .fontColor($r('app.color.muted'))
        Blank()
        if (this.memoryTraces.length > 0) {
          Button('清空流水')
            .type(ButtonType.Normal)
            .height(28)
            .fontSize(11)
            .borderRadius(8)
            .fontColor($r('app.color.warning'))
            .backgroundColor($r('app.color.surface'))
            .onClick(async () => {
              await this.onClearTraces();
              this.statusTip = '已清空流水线追踪记录';
            })
        }
      }
      .width('100%')

      if (this.memoryTraces.length === 0) {
        Text('尚无后台记忆流水线运行记录')
          .fontSize(13)
          .fontColor($r('app.color.muted'))
          .padding(20)
      } else {
        ForEach(this.memoryTraces, (tr: MemoryTrace) => {
          Column({ space: 6 }) {
            Row({ space: 6 }) {
              Text(tr.gatekeeperPassed ? '✓ 门控通过' : '○ 门控跳过')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(tr.gatekeeperPassed ? $r('app.color.accent') : $r('app.color.muted'))
              Text(`新增 ${tr.extractedCount} · 合并 ${tr.mergedCount}${tr.conflictCount ? ' · 冲突 ' + tr.conflictCount : ''}${tr.skippedCount ? ' · 跳过 ' + tr.skippedCount : ''}`)
                .fontSize(11)
                .fontColor($r('app.color.muted'))
              Blank()
              Text(this.formatTs(tr.ts))
                .fontSize(10)
                .fontColor($r('app.color.muted'))
            }
            .width('100%')

            if (tr.modelId) {
              Text(`模型：${tr.modelId}`)
                .fontSize(11)
                .fontColor($r('app.color.muted'))
            }
            Text(tr.summary)
              .fontSize(13)
              .fontColor($r('app.color.ink'))

            if (this.traceStepsFor(tr).length > 0) {
              Button(this.expandedTraceId === tr.id ? '收起阶段详情' : `查看 ${this.traceStepsFor(tr).length} 个阶段详情`)
                .type(ButtonType.Normal)
                .height(26)
                .fontSize(11)
                .borderRadius(6)
                .fontColor($r('app.color.accent'))
                .backgroundColor($r('app.color.tint'))
                .onClick(() => {
                  this.expandedTraceId = this.expandedTraceId === tr.id ? '' : tr.id;
                })
            }

            if (this.expandedTraceId === tr.id && this.traceStepsFor(tr).length > 0) {
              ForEach(this.traceStepsFor(tr), (st: MemoryTraceStep, si: number) => {
                Column({ space: 4 }) {
                  Row() {
                    Text(st.stage)
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.accent'))
                    Blank()
                    if (st.durationMs !== undefined) {
                      Text(`${st.durationMs}ms`)
                        .fontSize(10)
                        .fontColor($r('app.color.muted'))
                    }
                  }
                  .width('100%')
                  Text(st.summary)
                    .fontSize(12)
                    .fontColor($r('app.color.ink'))
                  if (st.response) {
                    Text(st.response.slice(0, 600))
                      .fontSize(11)
                      .fontColor($r('app.color.muted'))
                      .copyOption(CopyOptions.LocalDevice)
                  }
                }
                .width('100%')
                .padding(8)
                .backgroundColor($r('app.color.canvas'))
                .borderRadius(8)
                .alignItems(HorizontalAlign.Start)
              }, (st: MemoryTraceStep, si: number) => `${tr.id}_st_${si}`)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .padding(12)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .width('100%')
        }, (tr: MemoryTrace) => `${tr.id}_${this.expandedTraceId === tr.id}`)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private renderAboutSubPage() {
    Column({ space: 12 }) {
      Column({ space: 6 }) {
        Text('快速开始')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ink'))
        Text('1. 在「设置 → 记忆」中选择处理模型。\n2. 在助手的「记忆」标签页开启长期记忆与自动整理。\n3. 进行几轮对话或点击「整理」，然后在记忆列表中查看提取结果。')
          .fontSize(13)
          .lineHeight(20)
          .fontColor($r('app.color.ink'))
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 6 }) {
        Text('四种记忆类型')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ink'))
        Text('• 身份 (identity)：用户背景、称呼、职业与长期偏好等稳定事实，用完整第三人称陈述。\n• 工作方式 (workflow)：偏好的工具链、流程与复盘习惯。\n• 表达风格 (voice)：偏好的语气、篇幅、句式与语言风格。\n• 用户指令 (instruction)：助手需长期遵守的固定规则，而非一次性任务。')
          .fontSize(13)
          .lineHeight(20)
          .fontColor($r('app.color.ink'))
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 6 }) {
        Text('全局与助手范围')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ink'))
        Text('全局记忆对所有启用长期记忆的助手可见；助手范围记忆仅对该助手可见。适合全局的是应跨助手跟随的个人事实，适合助手范围的是特定角色的创作设定或规则。')
          .fontSize(13)
          .lineHeight(20)
          .fontColor($r('app.color.ink'))
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 6 }) {
        Text('记忆如何注入与工具协作')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ink'))
        Text('新对话开始时，每个分类最新的条目会按注入上限注入上下文。超出上限的分类会标记 mode="summary" 与总数，助手可通过 memory_search_profile / memory_read 按需检索，并通过 memory_update / memory_edit / memory_delete 实时维护。')
          .fontSize(13)
          .lineHeight(20)
          .fontColor($r('app.color.ink'))
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private navTitleBar() {
    if (this.subPage === 'home') {
      KelivoNavTitleBar({
        titleText: '记忆',
        subtitleText: `有效 ${this.activeMemoryCount()} 条 · 画像 ${this.filledProfileCount()} 项`,
        showBack: true,
        onBack: () => { this.onClose(); }
      })
    } else if (this.subPage === 'list') {
      KelivoNavTitleBar({
        titleText: '记忆列表',
        subtitleText: `${this.scopeLabelText()} · 共 ${this.filteredTotalCount()} 条`,
        showBack: true,
        secondSymbol: this.multiSelect ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.checkmark_circle'),
        rightSymbol: $r('sys.symbol.plus'),
        onBack: () => { this.returnToHome(); },
        onSecondAction: () => {
          this.multiSelect = !this.multiSelect;
          this.selectedIds = [];
        },
        onRightAction: () => { this.openAddEntryEditor(); }
      })
    } else if (this.subPage === 'profile') {
      KelivoNavTitleBar({
        titleText: '用户画像',
        subtitleText: `已填写 ${this.filledProfileCount()} 项`,
        showBack: true,
        rightSymbol: $r('sys.symbol.plus'),
        onBack: () => { this.returnToHome(); },
        onRightAction: () => {
          this.newProfileKey = '';
          this.newProfileVal = '';
          this.openSheet('profile');
        }
      })
    } else if (this.subPage === 'template') {
      KelivoNavTitleBar({
        titleText: this.currentTemplateSpec().title,
        subtitleText: this.editTemplateLang === 'zh' ? '中文模板' : 'English 模板',
        showBack: true,
        rightText: '保存',
        rightPrimary: true,
        onBack: () => { this.returnToHome(); },
        onRightAction: () => { this.saveTemplateEdit().catch(() => {}); }
      })
    } else if (this.subPage === 'traces') {
      KelivoNavTitleBar({
        titleText: '流水线追踪',
        subtitleText: `共 ${this.memoryTraces.length} 条记录`,
        showBack: true,
        rightSymbol: this.memoryTraces.length > 0 ? $r('sys.symbol.trash') : undefined,
        onBack: () => { this.returnToHome(); },
        onRightAction: () => {
          this.onClearTraces().then(() => {
            this.statusTip = '已清空流水线追踪记录';
            this.showToastTip('已清空流水线追踪记录');
          }).catch(() => {});
        }
      })
    } else {
      KelivoNavTitleBar({
        titleText: this.subPageTitle(),
        subtitleText: '记忆设置',
        showBack: true,
        onBack: () => { this.returnToHome(); }
      })
    }
  }

  @Builder
  private entryEditorSheetBody() {
    Column({ space: 10 }) {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(MEMORY_CATEGORIES, (cat: MemoryCategory) => {
          Button(this.categoryLabel(cat))
            .type(ButtonType.Normal)
            .height(28)
            .fontSize(11)
            .margin({ right: 6, bottom: 6 })
            .borderRadius(8)
            .fontColor(this.entryCat === cat ? $r('app.color.on_accent') : $r('app.color.ink'))
            .backgroundColor(this.entryCat === cat ? $r('app.color.accent') : $r('app.color.panel'))
            .onClick(() => { this.entryCat = cat; })
        }, (cat: MemoryCategory) => `edcat_${cat}`)
      }
      .width('100%')

      TextArea({ text: this.entryContent, placeholder: '用完整第三人称句描述用户事实或偏好...' })
        .height(96)
        .borderRadius(10)
        .backgroundColor($r('app.color.panel'))
        .onChange((v: string) => { this.entryContent = v; })

      Row({ space: 8 }) {
        Button(this.entryScopeId === '' ? '范围：全局' : `范围：${this.personaName(this.entryScopeId)}`)
          .type(ButtonType.Normal)
          .height(34)
          .fontSize(12)
          .borderRadius(10)
          .fontColor($r('app.color.ink'))
          .backgroundColor($r('app.color.panel'))
          .onClick(() => {
            if (this.personas.length === 0) return;
            if (this.entryScopeId === '') {
              this.entryScopeId = this.personas[0].id;
            } else {
              const idx = this.personas.findIndex((p: Persona): boolean => p.id === this.entryScopeId);
              this.entryScopeId = idx + 1 < this.personas.length ? this.personas[idx + 1].id : '';
            }
          })
        Blank()
        Button('取消')
          .type(ButtonType.Normal)
          .height(34)
          .fontSize(12)
          .borderRadius(10)
          .fontColor($r('app.color.muted'))
          .backgroundColor($r('app.color.panel'))
          .onClick(() => { this.closeSheet(); })
        Button('保存')
          .type(ButtonType.Normal)
          .height(34)
          .fontSize(12)
          .borderRadius(10)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor($r('app.color.accent'))
          .onClick(async () => { await this.saveEntryEditor(); })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 4, bottom: Math.max(24, this.effectiveBottomInset() + 12) })
  }

  @Builder
  private profileFieldSheetBody() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        TextInput({ text: this.newProfileKey, placeholder: '字段名' })
          .layoutWeight(1)
          .height(40)
          .borderRadius(10)
          .backgroundColor($r('app.color.panel'))
          .onChange((v: string) => { this.newProfileKey = v; })
        TextInput({ text: this.newProfileVal, placeholder: '字段值' })
          .layoutWeight(2)
          .height(40)
          .borderRadius(10)
          .backgroundColor($r('app.color.panel'))
          .onChange((v: string) => { this.newProfileVal = v; })
      }
      .width('100%')

      Row({ space: 8 }) {
        Blank()
        Button('取消')
          .type(ButtonType.Normal)
          .height(34)
          .fontSize(12)
          .borderRadius(10)
          .fontColor($r('app.color.muted'))
          .backgroundColor($r('app.color.panel'))
          .onClick(() => { this.closeSheet(); })
        Button('保存')
          .type(ButtonType.Normal)
          .height(34)
          .fontSize(12)
          .borderRadius(10)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor($r('app.color.accent'))
          .onClick(async () => { await this.addCustomProfileField(); })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 4, bottom: Math.max(24, this.effectiveBottomInset() + 12) })
  }

  @Builder
  private memorySheetContent() {
    if (this.activeSheetKind === 'entry') {
      this.entryEditorSheetBody()
    } else if (this.activeSheetKind === 'profile') {
      this.profileFieldSheetBody()
    } else {
      Column() {}
    }
  }

  build() {
    NavDestination() {
      Column() {
        Scroll(this.contentScroller) {
          Column({ space: 10 }) {
            if (this.statusTip.length > 0) {
              Row({ space: 8 }) {
                Text(this.statusTip)
                  .fontSize(12)
                  .fontColor($r('app.color.accent'))
                  .layoutWeight(1)
                Text('×')
                  .fontSize(14)
                  .fontColor($r('app.color.muted'))
                  .padding({ left: 6, right: 4 })
                  .onClick(() => { this.statusTip = ''; })
              }
              .width('100%')
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .backgroundColor($r('app.color.tint'))
              .borderRadius(8)
            }

            if (this.subPage === 'home') {
              this.renderHomeSubPage()
            } else if (this.subPage === 'list') {
              this.renderListSubPage()
            } else if (this.subPage === 'profile') {
              this.renderProfileSubPage()
            } else if (this.subPage === 'legacy') {
              this.renderLegacySubPage()
            } else if (this.subPage === 'traces') {
              this.renderTracesSubPage()
            } else if (this.subPage === 'template') {
              this.renderTemplateSubPage()
            } else if (this.subPage === 'modelPicker') {
              this.renderModelPickerSubPage()
            } else {
              this.renderAboutSubPage()
            }
          }
          .width('100%')
          .padding({
            left: 16,
            right: 16,
            top: 56 + this.winTopInset + 4,
            bottom: Math.max(36, this.effectiveBottomInset() + 24)
          })
        }
        .layoutWeight(1)
        .width('100%')
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')
      .padding({ left: this.winLeftInset, right: this.winRightInset })
      .backgroundColor(Color.Transparent)
      .bindSheet(
        $$this.activeSheetOpen,
        this.memorySheetContent(),
        ImmersiveMaterialStyle.sheetOptions(
          this.immersiveLightEnabled,
          this.themeSurfaceHex,
          this.memorySheetTitle(),
          () => { this.closeSheet(); },
          true
        )
      )
    }
    .hideBackButton(true)
    .backgroundColor(this.themeCanvasHex)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .title(
      { builder: () => { this.navTitleBar(); }, height: 56 + this.winTopInset },
      ImmersiveMaterialStyle.titleBarOptions(this.immersiveLightEnabled, true)
    )
    .systemTransition(SystemMotion.navTransition(this.reduceMotion))
    .onShown(() => { this.onRouteShown(); })
    .onHidden(() => { this.onRouteHidden(); })
    .onBackPressed(() => {
      if (this.activeSheetOpen) {
        this.closeSheet();
        return true;
      }
      if (this.onDismissOverlay()) {
        return true;
      }
      if (this.subPage !== 'home') {
        this.returnToHome();
        return true;
      }
      return false;
    })
  }
}
