import { pasteboard } from '@kit.BasicServicesKit';
import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { computeFloatingBottomInsetVp } from '../core/ImmersiveUtils';
import { SystemMotion } from '../core/SystemMotion';
import {
  MEMORY_CATEGORIES,
  MemoryTemplateKind,
  findOrphanedMemories,
  getDefaultMemoryTemplate,
  getEffectiveMemoryTemplate,
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
  MemoryTrace,
  ModelDefaults,
  Persona,
  Provider,
  UserProfileField
} from '../core/Models';
import { newId } from '../core/Storage';
import { KelivoNavTitleBar } from './KelivoChrome';
import {
  MEMORY_TEMPLATE_ROWS,
  MemorySubPage,
  MemoryTemplateRowSpec,
  cloneMemoryModelDefaults,
  cloneMemorySettings,
  collectMemoryModelChoices,
  findMemoryTemplateSpec,
  isMemoryTemplateCustomized,
  memoryCategoryLabel,
  memoryPersonaName,
  setCustomMemoryTemplateValue
} from './MemoryPanelHelpers';
import {
  MemoryAboutSubView,
  MemoryLegacySubView,
  MemoryListSubView,
  MemoryModelPickerSubView,
  MemoryProfileSubView,
  MemoryTemplateEditorSubView,
  MemoryTracesSubView
} from './MemorySubPages';

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

  private processingModelLabel(): string {
    const pid = this.modelDefaults.memoryProviderId;
    const mid = this.modelDefaults.memoryModelId;
    if (!pid || !mid) return '跟随当前对话模型';
    const prov = this.providers.find((p: Provider): boolean => p.id === pid);
    return prov ? `${prov.name} / ${mid}` : mid;
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

  private async saveTemplateEdit(): Promise<void> {
    const next = cloneMemorySettings(this.memorySettings);
    const tpl: MemoryPromptTemplates = next.templates || {};
    const defText = getDefaultMemoryTemplate(this.editTemplateKind, this.editTemplateLang).trim();
    const clean = this.editTemplateText.trim();
    setCustomMemoryTemplateValue(tpl, this.editTemplateKind, this.editTemplateLang, clean === defText || clean.length === 0 ? undefined : clean);
    next.templates = tpl;
    await this.onSaveSettings(next);
    this.statusTip = '已保存提示词模板';
    this.showToastTip(this.statusTip);
    this.navigateSubPage('home');
  }

  private async resetTemplateToDefault(): Promise<void> {
    const defText = getDefaultMemoryTemplate(this.editTemplateKind, this.editTemplateLang);
    this.editTemplateText = defText;
    const next = cloneMemorySettings(this.memorySettings);
    const tpl: MemoryPromptTemplates = next.templates || {};
    setCustomMemoryTemplateValue(tpl, this.editTemplateKind, this.editTemplateLang, undefined);
    next.templates = tpl;
    await this.onSaveSettings(next);
    this.statusTip = '已恢复默认模板';
    this.showToastTip(this.statusTip);
  }

  private async updateSettingFlag(field: 'useLegacyMemory' | 'enableThinking' | 'injectGlobal' | 'autoExtract' | 'recordTraces', val: boolean): Promise<void> {
    const next = cloneMemorySettings(this.memorySettings);
    if (field === 'useLegacyMemory') next.useLegacyMemory = val;
    else if (field === 'enableThinking') next.enableThinking = val;
    else if (field === 'injectGlobal') next.injectGlobal = val;
    else if (field === 'autoExtract') next.autoExtract = val;
    else next.recordTraces = val;
    await this.onSaveSettings(next);
  }

  private async updateInjectCount(nextVal: number): Promise<void> {
    const clamped = Math.max(1, Math.min(500, Math.floor(nextVal)));
    const next = cloneMemorySettings(this.memorySettings);
    next.maxInjectCount = clamped;
    await this.onSaveSettings(next);
  }

  private async updatePromptLanguage(lang: MemoryPromptLanguage): Promise<void> {
    const next = cloneMemorySettings(this.memorySettings);
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
    return memoryPersonaName(this.personas, this.filterScope);
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
      lines.push(`- [${m.category}][${memoryPersonaName(this.personas, m.assistantId)}]${m.archived ? '[已归档]' : ''} ${m.content}`);
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

  private subPageTitle(): string {
    if (this.subPage === 'list') return '记忆列表';
    if (this.subPage === 'profile') return '用户画像';
    if (this.subPage === 'legacy') return '旧版记忆（只读）';
    if (this.subPage === 'traces') return '流水线追踪';
    if (this.subPage === 'about') return '关于记忆';
    if (this.subPage === 'template') return findMemoryTemplateSpec(this.editTemplateKind).title;
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
            Text('关闭可显著加快整理速度；开启时提取/去重按低强度推理（门控始终免思考）')
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
        ForEach(MEMORY_TEMPLATE_ROWS, (spec: MemoryTemplateRowSpec, idx: number) => {
          Column() {
            if (idx > 0) {
              Divider().color($r('app.color.line')).margin({ left: 14 })
            }
            this.navRow(
              spec.title,
              spec.subtitle,
              isMemoryTemplateCustomized(this.memorySettings, spec.kind) ? '已自定义' : '默认',
              false,
              () => { this.openTemplateEditor(spec.kind); }
            )
          }
        }, (spec: MemoryTemplateRowSpec) => `tpl_${spec.kind}`)
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
        titleText: findMemoryTemplateSpec(this.editTemplateKind).title,
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
          Button(memoryCategoryLabel(cat))
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
        Button(this.entryScopeId === '' ? '范围：全局' : `范围：${memoryPersonaName(this.personas, this.entryScopeId)}`)
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
              MemoryListSubView({
                personas: this.personas,
                orphanCount: this.orphanCount(),
                scopeLabel: this.scopeLabelText(),
                filteredTotal: this.filteredTotalCount(),
                remainingCount: this.remainingEntryCount(),
                pagedItems: this.pagedEntries(),
                searchQuery: this.searchQuery,
                filterScope: this.filterScope,
                filterCat: this.filterCat,
                filterStatus: this.filterStatus,
                pageLimit: this.pageLimit,
                multiSelect: this.multiSelect,
                selectedIds: this.selectedIds,
                onOpenAdd: () => { this.openAddEntryEditor(); },
                onOpenEdit: (item: MemoryEntry) => { this.openEditEntryEditor(item); },
                onToggleArchive: (id: string) => this.toggleArchive(id),
                onDeleteMemory: (id: string) => this.deleteMemory(id),
                onCleanupOrphaned: (convertToGlobal: boolean) => this.cleanupOrphaned(convertToGlobal),
                onBatchToggleArchive: () => this.batchToggleArchiveSelected(),
                onBatchDelete: () => this.batchDeleteSelected(),
                onToggleSelected: (id: string) => { this.toggleSelected(id); }
              })
            } else if (this.subPage === 'profile') {
              MemoryProfileSubView({
                userProfile: this.userProfile,
                editingProfileKey: this.editingProfileKey,
                editingProfileVal: this.editingProfileVal,
                onSaveProfileField: (key: string, val: string) => this.saveProfileFieldValue(key, val),
                onOpenCustomField: (key: string, val: string) => {
                  this.newProfileKey = key;
                  this.newProfileVal = val;
                  this.openSheet('profile');
                }
              })
            } else if (this.subPage === 'legacy') {
              MemoryLegacySubView({
                legacyItems: this.legacyList()
              })
            } else if (this.subPage === 'traces') {
              MemoryTracesSubView({
                memoryTraces: this.memoryTraces,
                recordTraces: this.memorySettings.recordTraces !== false,
                onToggleRecordTraces: (v: boolean) => this.updateSettingFlag('recordTraces', v),
                onClearTraces: async () => {
                  await this.onClearTraces();
                  this.statusTip = '已清空流水线追踪记录';
                }
              })
            } else if (this.subPage === 'template') {
              MemoryTemplateEditorSubView({
                specSubtitle: findMemoryTemplateSpec(this.editTemplateKind).subtitle,
                editLang: this.editTemplateLang,
                editText: this.editTemplateText,
                onSwitchLang: (lang: 'zh' | 'en') => { this.switchTemplateEditorLang(lang); },
                onReset: () => this.resetTemplateToDefault(),
                onSave: () => this.saveTemplateEdit()
              })
            } else if (this.subPage === 'modelPicker') {
              MemoryModelPickerSubView({
                selectedProviderId: this.modelDefaults.memoryProviderId,
                selectedModelId: this.modelDefaults.memoryModelId,
                choices: collectMemoryModelChoices(this.providers),
                onSelectFollowChat: async () => {
                  const next = cloneMemoryModelDefaults(this.modelDefaults);
                  next.memoryProviderId = '';
                  next.memoryModelId = '';
                  await this.onSaveModelDefaults(next);
                  this.statusTip = '记忆处理模型已设为跟随对话模型';
                  this.navigateSubPage('home');
                },
                onSelectChoice: async (choice) => {
                  const next = cloneMemoryModelDefaults(this.modelDefaults);
                  next.memoryProviderId = choice.providerId;
                  next.memoryModelId = choice.modelId;
                  await this.onSaveModelDefaults(next);
                  this.statusTip = `处理模型已设为 ${choice.providerName} / ${choice.modelId}`;
                  this.navigateSubPage('home');
                }
              })
            } else {
              MemoryAboutSubView()
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
