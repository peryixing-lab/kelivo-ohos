import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { computeFloatingBottomInsetVp, hexWithAlpha } from '../core/ImmersiveUtils';
import { SystemMotion } from '../core/SystemMotion';
import { canReadMemory, normalizeMemoryTimestamp } from '../core/MemoryLogic';
import {
  GenerationParams,
  HeaderEntry,
  LocalWorkspace,
  McpServerConfig,
  MemoryCategory,
  MemoryEntry,
  MemorySettings,
  MemoryTrace,
  Persona,
  PresetMessage,
  Provider,
  QuickPhrase,
  ReasoningEffort,
  RegexRule,
  SkillRecord,
  WorldBook
} from '../core/Models';
import { newId } from '../core/Storage';
import { KelivoAvatarBadge, KelivoNavTitleBar } from './KelivoChrome';
import {
  PERSONA_BG_CHOICES,
  PERSONA_MEMORY_POLICIES,
  PERSONA_REASONING_LABELS,
  PERSONA_REASONING_OPTIONS,
  PERSONA_SMART_ADD_MODES,
  PersonaCustomRequestTab,
  PersonaLocalToolsTab,
  PersonaMcpTab,
  PersonaPromptTab,
  PersonaQuickPhrasesTab,
  PersonaRegexTab,
  PersonaSkillsTab
} from './PersonaAdvancedTabs';
import {
  PersonaAvatarSheet,
  PersonaMemoryEntrySheet,
  PersonaMemoryTab,
  PersonaModelSheet
} from './PersonaMemoryAndSheets';

@Component
export struct PersonaEditor {
  @Prop personas: Persona[] = [];
  @Prop activeId: string = '';
  pageMode: 'list' | 'detail' = 'list';
  @Prop initialEditId: string = '';
  @Prop providers: Provider[] = [];
  @Prop worldBooks: WorldBook[] = [];
  @Prop mcpServers: McpServerConfig[] = [];
  @Prop skills: SkillRecord[] = [];
  @Prop localWorkspaces: LocalWorkspace[] = [];
  @Prop memories: MemoryEntry[] = [];
  @Prop memorySettings: MemorySettings = { autoExtract: false, injectGlobal: true, maxInjectCount: 100 };
  @Prop organizingMemoryAssistantId: string = '';
  @Prop memoryTraces: MemoryTrace[] = [];

  onSavePersona: (persona: Persona, setActive: boolean) => Promise<void> = async () => {};
  onDeletePersona: (id: string) => Promise<void> = async () => {};
  onApply: (persona: Persona) => Promise<void> = async () => {};
  onSaveMemories: (entries: MemoryEntry[]) => Promise<void> = async () => {};
  onOrganizeMemory: (assistantId: string) => void = () => {};
  onOpenMemorySettings: () => void = () => {};
  onOpenDetail: (personaId: string) => void = () => {};
  onDismissOverlay: () => boolean = () => false;
  onRouteShown: () => void = () => {};
  onRouteHidden: () => void = () => {};
  onClose: () => void = () => {};

  @State selectedId: string = '';
  @State activeTab: number = 0; // 0:基础设置 1:提示词 2:记忆 3:本地工具 4:技能 5:MCP 6:快捷短语 7:自定义请求 8:正则替换
  @StorageProp('windowTopInsetVp') winTopInset: number = 0;
  @StorageProp('windowBottomInsetVp') winBottomInset: number = 0;
  @StorageProp('windowLeftInsetVp') winLeftInset: number = 0;
  @StorageProp('windowRightInsetVp') winRightInset: number = 0;
  @StorageProp('windowIsFloating') winIsFloating: boolean = false;
  @StorageProp('windowKeyboardHeightVp') winKeyboardHeight: number = 0;
  @StorageProp('immersiveLightEnabled') immersiveLightEnabled: boolean = true;
  @StorageProp('themeSurfaceHex') themeSurfaceHex: string = '#FFFFFF';
  @StorageProp('themeCanvasHex') themeCanvasHex: string = '#F7F7F7';
  @StorageProp('reduceMotionEnabled') reduceMotion: boolean = false;
  private listScroller: Scroller = new Scroller();
  private detailScroller: Scroller = new Scroller();
  @State activeSheetKind: '' | 'avatar' | 'model' | 'memory' = '';
  @State activeSheetOpen: boolean = false;

  // Basic tab states
  @State editName: string = '';
  @State editAvatar: string = '🤖';
  @State editUseAssistantAvatar: boolean = false;
  @State editUseAssistantName: boolean = false;
  @State editStreamOutput: boolean = true;
  @State editTagsText: string = '';
  @State editProviderId: string = '';
  @State editModelId: string = '';
  @State editBgTint: string = '';
  @State editUseGradientBg: boolean = false;
  @State editTemp: string = '';
  @State editTopP: string = '';
  @State editMaxTokens: string = '';
  @State editContextBudget: string = '';
  @State editReasoning: string = '';
  @State editingBasicField: string = ''; // '' | 'temp' | 'topP' | 'context' | 'maxTokens' | 'workspace'
  @State editWorkspaceId: string = '';

  // Prompt tab states
  @State editPrompt: string = '';
  @State editAllowConvSystemPrompt: boolean = false;
  @State editAllowConvPromptInjection: boolean = false;
  @State editAppendCurrentTime: boolean = false;
  @State editWorldBookIds: string[] = [];
  @State editPresets: PresetMessage[] = [];

  // Memory tab states
  @State editMemoryEnabled: boolean = true;
  @State editAutoOrganizeIndex: number = 0;
  @State editMemoryCadence: string = '1';
  @State editFullMemoryTypes: MemoryCategory[] = [];
  @State editSmartAddModeIndex: number = 0;
  @State editWriteScopeIndex: number = 0;
  @State editPastRecall: boolean = false;
  @State editGenSummary: boolean = false;
  @State editSummaryEveryN: string = '5';
  @State asstMemEditingId: string = '';
  @State asstMemCat: MemoryCategory = 'instruction';
  @State asstMemScopeGlobal: boolean = false;
  @State asstMemContent: string = '';
  @State asstMemLimit: number = 30;

  // Tools / Skills / MCP / QuickPhrases / CustomRequest / Regex states
  @State editBuiltinTools: string[] = [];
  @State editSkillIds: string[] = [];
  @State editAllowConvMcp: boolean = false;
  @State editMcpIds: string[] = [];
  @State editQuickPhrases: QuickPhrase[] = [];
  @State editHeaderRows: HeaderEntry[] = [];
  @State editBodyJson: string = '';
  @State editRegexRules: RegexRule[] = [];
  @State statusMsg: string = '';

  aboutToAppear(): void {
    if (this.pageMode === 'detail') {
      const target = (this.initialEditId ? this.findPersonaById(this.initialEditId) : undefined) ??
        this.findPersonaById(this.activeId) ??
        (this.personas.length > 0 ? this.personas[0] : undefined);
      if (target) {
        this.loadFromPersona(target);
      }
    }
  }

  private findPersonaById(id: string): Persona | undefined {
    for (let i = 0; i < this.personas.length; i++) {
      if (this.personas[i].id === id) return this.personas[i];
    }
    return undefined;
  }

  private loadFromPersona(p: Persona): void {
    this.selectedId = p.id;
    this.editName = p.name;
    this.editAvatar = p.avatar && p.avatar.length > 0 ? p.avatar : '';
    this.editUseAssistantAvatar = p.useAssistantAvatar === true;
    this.editUseAssistantName = p.useAssistantName === true;
    this.editStreamOutput = p.streamOutput !== false;
    this.editTagsText = p.tags ? p.tags.join(', ') : '';
    this.editProviderId = p.providerId ? p.providerId : '';
    this.editModelId = p.modelId ? p.modelId : '';
    this.editBgTint = p.chatBackground ? p.chatBackground : '';
    this.editUseGradientBg = p.useGradientBackground === true;
    const pm = p.params;
    this.editTemp = pm && pm.temperature !== undefined ? String(pm.temperature) : '';
    this.editTopP = pm && pm.topP !== undefined ? String(pm.topP) : '';
    this.editMaxTokens = pm && pm.maxTokens !== undefined ? String(pm.maxTokens) : '';
    this.editContextBudget = pm && pm.contextLimit !== undefined && pm.contextLimit > 0 ? String(pm.contextLimit) : '';
    this.editReasoning = pm && pm.reasoningEffort ? pm.reasoningEffort : '';
    this.editingBasicField = '';
    this.editWorkspaceId = p.workspaceId ? p.workspaceId : '';

    this.editPrompt = p.prompt || '';
    this.editAllowConvSystemPrompt = p.allowConversationSystemPrompt === true;
    this.editAllowConvPromptInjection = p.allowConversationPromptInjection === true;
    this.editAppendCurrentTime = p.appendCurrentTimeToUserMessage === true;
    this.editWorldBookIds = p.worldBookIds ? p.worldBookIds.slice() : [];
    this.editPresets = p.presetMessages
      ? p.presetMessages.map((m): PresetMessage => ({ id: m.id, role: m.role, content: m.content }))
      : [];

    this.editMemoryEnabled = p.memoryEnabled !== false;
    this.editAutoOrganizeIndex = p.autoOrganizeMemory === undefined ? 0 : (p.autoOrganizeMemory ? 1 : 2);
    this.editMemoryCadence = String(p.memoryOrganizeEveryNTurns || 1);
    this.editFullMemoryTypes = p.memoryFullInjectionTypes?.slice() || [];
    this.editSmartAddModeIndex = p.memorySmartAddMode === 'perItem' ? 1 : 0;
    this.editWriteScopeIndex = Math.max(0, PERSONA_MEMORY_POLICIES.indexOf(p.memoryWriteScope || 'alwaysGlobal'));
    this.editPastRecall = p.allowPastConversationRecall === true;
    this.editGenSummary = p.generateConversationSummary === true;
    this.editSummaryEveryN = String(p.recentChatsSummaryMessageCount || 5);
    this.closeSheet();
    this.asstMemEditingId = '';
    this.asstMemLimit = 30;

    this.editBuiltinTools = p.builtinTools ? p.builtinTools.slice() : [];
    this.editSkillIds = p.skillIds ? p.skillIds.slice() : [];
    this.editAllowConvMcp = p.allowConversationMcp === true;
    this.editMcpIds = p.mcpServerIds ? p.mcpServerIds.slice() : [];
    this.editQuickPhrases = p.quickPhrases
      ? p.quickPhrases.map((q): QuickPhrase => ({ id: q.id, title: q.title, content: q.content, scope: 'assistant' }))
      : [];
    this.editHeaderRows = p.customHeaders
      ? p.customHeaders.map((h: HeaderEntry): HeaderEntry => ({ key: h.key, value: h.value }))
      : [];
    this.editBodyJson = p.customBodyJson ? p.customBodyJson : '';
    this.editRegexRules = p.regexRules
      ? p.regexRules.map((r): RegexRule => ({
          id: r.id,
          name: r.name,
          pattern: r.pattern,
          replacement: r.replacement,
          flags: r.flags,
          scope: r.scope,
          enabled: r.enabled
        }))
      : [];
    this.statusMsg = '';
  }

  private normalizeReasoningEffort(raw: string): ReasoningEffort | undefined {
    const v = raw.trim().toLowerCase();
    if (v === 'off' || v === 'minimal' || v === 'xhigh' || v === 'low' || v === 'medium' || v === 'high' || v === 'max') {
      return v as ReasoningEffort;
    }
    return undefined;
  }

  private isOrganizingSelectedAssistant(): boolean {
    return this.organizingMemoryAssistantId.length > 0 && this.organizingMemoryAssistantId === this.selectedId;
  }

  private latestAssistantOrganizeStatus(): string {
    if (this.isOrganizingSelectedAssistant()) {
      return '正在整理记忆…';
    }
    let latest: MemoryTrace | undefined = undefined;
    for (let i = 0; i < this.memoryTraces.length; i++) {
      const tr = this.memoryTraces[i];
      if (tr.assistantId === this.selectedId) {
        latest = tr;
        break;
      }
    }
    if (!latest) return '';
    const diffMs = Math.max(0, Date.now() - (latest.ts || 0));
    const mins = Math.floor(diffMs / 60000);
    const when = mins < 1
      ? '刚刚'
      : (mins < 60 ? `${mins} 分钟前` : (mins < 1440 ? `${Math.floor(mins / 60)} 小时前` : `${Math.floor(mins / 1440)} 天前`));
    if (latest.error && latest.error.length > 0) {
      return `上次整理：${when} · 失败`;
    }
    if (!latest.gatekeeperPassed || (latest.extractedCount === 0 && latest.mergedCount === 0)) {
      return `上次整理：${when} · 无新增记忆`;
    }
    return `上次整理：${when} · ${latest.summary || `新增 ${latest.extractedCount} 条`}`;
  }

  private parseTags(): string[] {
    const parts = this.editTagsText.split(',');
    const out: string[] = [];
    for (let i = 0; i < parts.length; i++) {
      const s = parts[i].trim();
      if (s.length > 0 && out.indexOf(s) < 0) out.push(s);
    }
    return out;
  }

  private cleanedCustomHeaders(): HeaderEntry[] | undefined {
    const out: HeaderEntry[] = [];
    for (let i = 0; i < this.editHeaderRows.length; i++) {
      const k = this.editHeaderRows[i].key.trim();
      if (k.length > 0) {
        out.push({ key: k, value: this.editHeaderRows[i].value });
      }
    }
    return out.length > 0 ? out : undefined;
  }

  private buildPersonaObject(newIdOverride?: string, nameOverride?: string): Persona {
    const params: GenerationParams = {};
    const t = parseFloat(this.editTemp);
    if (!Number.isNaN(t)) params.temperature = t;
    const tp = parseFloat(this.editTopP);
    if (!Number.isNaN(tp)) params.topP = tp;
    const mt = parseInt(this.editMaxTokens, 10);
    if (!Number.isNaN(mt) && mt > 0) params.maxTokens = mt;
    const cb = parseInt(this.editContextBudget, 10);
    if (!Number.isNaN(cb) && cb > 0) params.contextLimit = cb;
    const effort = this.normalizeReasoningEffort(this.editReasoning);
    if (effort) {
      params.reasoningEffort = effort;
      const previous = this.findPersonaById(this.selectedId)?.params;
      if (previous?.reasoningEffort === effort) params.reasoningBudget = previous.reasoningBudget;
    }

    const baseName = nameOverride ? nameOverride : (this.editName.trim().length > 0 ? this.editName.trim() : '未命名助手');
    return {
      id: newIdOverride ? newIdOverride : (this.selectedId.length > 0 ? this.selectedId : 'p_' + newId()),
      name: baseName,
      prompt: this.editPrompt,
      avatar: this.editAvatar.length > 0 ? this.editAvatar : undefined,
      tags: this.parseTags(),
      providerId: this.editProviderId.length > 0 ? this.editProviderId : undefined,
      modelId: this.editModelId.length > 0 ? this.editModelId : undefined,
      params,
      presetMessages: this.editPresets,
      customHeaders: this.cleanedCustomHeaders(),
      customBodyJson: this.editBodyJson.trim().length > 0 ? this.editBodyJson.trim() : undefined,
      mcpServerIds: this.editMcpIds.slice(),
      skillIds: this.editSkillIds.slice(),
      builtinTools: this.editBuiltinTools.slice(),
      workspaceId: this.editWorkspaceId.length > 0 ? this.editWorkspaceId : undefined,
      quickPhrases: this.editQuickPhrases,
      regexRules: this.editRegexRules,
      chatBackground: this.editBgTint.length > 0 ? this.editBgTint : undefined,
      memoryEnabled: this.editMemoryEnabled,
      autoOrganizeMemory: this.editAutoOrganizeIndex === 0 ? undefined : this.editAutoOrganizeIndex === 1,
      memoryOrganizeEveryNTurns: Math.max(1, Math.min(20, Number.parseInt(this.editMemoryCadence, 10) || 1)),
      memoryFullInjectionTypes: this.editFullMemoryTypes.slice(),
      memorySmartAddMode: PERSONA_SMART_ADD_MODES[this.editSmartAddModeIndex],
      memoryWriteScope: PERSONA_MEMORY_POLICIES[this.editWriteScopeIndex],
      allowPastConversationRecall: this.editPastRecall,
      generateConversationSummary: this.editGenSummary,
      recentChatsSummaryMessageCount: Math.max(1, Math.min(50, Number.parseInt(this.editSummaryEveryN, 10) || 5)),
      worldBookIds: this.editWorldBookIds.slice(),
      useAssistantAvatar: this.editUseAssistantAvatar,
      useAssistantName: this.editUseAssistantName,
      streamOutput: this.editStreamOutput,
      allowConversationSystemPrompt: this.editAllowConvSystemPrompt,
      allowConversationPromptInjection: this.editAllowConvPromptInjection,
      appendCurrentTimeToUserMessage: this.editAppendCurrentTime,
      allowConversationMcp: this.editAllowConvMcp,
      useGradientBackground: this.editUseGradientBg
    };
  }

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

  private openSheet(kind: 'avatar' | 'model' | 'memory'): void {
    this.activeSheetKind = kind;
    this.activeSheetOpen = true;
  }

  private closeSheet(): void {
    this.activeSheetOpen = false;
    this.activeSheetKind = '';
  }

  private personaSheetTitle(): string {
    if (this.activeSheetKind === 'avatar') {
      return '选择助手头像';
    }
    if (this.activeSheetKind === 'model') {
      return '选择聊天模型';
    }
    return this.asstMemEditingId.length > 0 ? '编辑记忆' : '添加记忆';
  }

  private async deleteCurrentPersonaAndReturn(): Promise<void> {
    if (this.personas.length <= 1) {
      return;
    }
    const delId = this.selectedId;
    await this.onDeletePersona(delId);
    this.showToastTip('已删除助手');
    this.onClose();
  }

  private async saveCurrent(setActive: boolean): Promise<void> {
    if (this.editBodyJson.trim().length > 0) {
      try {
        JSON.parse(this.editBodyJson);
      } catch (_) {
        this.statusMsg = '自定义 Body JSON 格式有误';
        this.showToastTip(this.statusMsg);
        return;
      }
    }
    const built = this.buildPersonaObject();
    this.selectedId = built.id;
    await this.onSavePersona(built, setActive);
    this.statusMsg = setActive ? '已保存并切换至此助手' : '已保存助手配置';
    this.showToastTip(this.statusMsg);
  }

  private async createNewPersona(): Promise<string> {
    const fresh: Persona = {
      id: 'p_' + newId(),
      name: '新助手',
      avatar: '✨',
      prompt: '你是一个乐于助人、回答严谨清晰的 AI 助手。',
      tags: [],
      memoryEnabled: false,
      autoOrganizeMemory: false
    };
    await this.onSavePersona(fresh, false);
    this.loadFromPersona(fresh);
    this.statusMsg = '已新建助手';
    this.showToastTip(this.statusMsg);
    return fresh.id;
  }

  private async cloneCurrentPersona(): Promise<void> {
    const cloned = this.buildPersonaObject('p_' + newId(), `${this.editName.trim() || '助手'} 副本`);
    await this.onSavePersona(cloned, false);
    this.loadFromPersona(cloned);
    this.statusMsg = '已克隆助手';
    this.showToastTip(this.statusMsg);
  }

  private currentModelSummary(): string {
    if (!this.editProviderId || !this.editModelId) return '跟随全局默认';
    const prov = this.providers.find((p: Provider): boolean => p.id === this.editProviderId);
    return prov ? `${prov.name} / ${this.editModelId}` : this.editModelId;
  }

  private reasoningDisplayText(): string {
    const idx = PERSONA_REASONING_OPTIONS.indexOf(this.editReasoning);
    return idx >= 0 ? PERSONA_REASONING_LABELS[idx] : '跟随全局设置';
  }

  private workspaceDisplayText(): string {
    if (!this.editWorkspaceId) return '未设置';
    const ws = this.localWorkspaces.find((w: LocalWorkspace): boolean => w.id === this.editWorkspaceId);
    return ws ? ws.name : '未设置';
  }

  private visibleAssistantMemories(): MemoryEntry[] {
    const includeGlobal = this.memorySettings.injectGlobal !== false;
    const list = this.memories.filter((m: MemoryEntry): boolean =>
      !m.archived && canReadMemory(m, this.selectedId, includeGlobal)
    );
    list.sort((a: MemoryEntry, b: MemoryEntry): number =>
      normalizeMemoryTimestamp(b.updatedAt) - normalizeMemoryTimestamp(a.updatedAt)
    );
    return list;
  }

  private pagedAssistantMemories(): MemoryEntry[] {
    return this.visibleAssistantMemories().slice(0, this.asstMemLimit);
  }

  private visibleAssistantMemoryCount(): number {
    return this.visibleAssistantMemories().length;
  }

  private remainingAssistantMemoryCount(): number {
    const total = this.visibleAssistantMemoryCount();
    return total > this.asstMemLimit ? total - this.asstMemLimit : 0;
  }

  private openAddAsstMemory(): void {
    this.asstMemEditingId = '';
    this.asstMemCat = 'instruction';
    const policy = PERSONA_MEMORY_POLICIES[this.editWriteScopeIndex];
    this.asstMemScopeGlobal = policy === 'alwaysGlobal' || policy === 'toolDefaultGlobal';
    this.asstMemContent = '';
    this.openSheet('memory');
  }

  private openEditAsstMemory(item: MemoryEntry): void {
    this.asstMemEditingId = item.id;
    this.asstMemCat = item.category;
    this.asstMemScopeGlobal = !(item.assistantId && item.assistantId.length > 0);
    this.asstMemContent = item.content;
    this.openSheet('memory');
  }

  private async saveAsstMemory(): Promise<void> {
    const clean = this.asstMemContent.trim();
    if (clean.length === 0) {
      this.statusMsg = '请输入记忆内容';
      this.showToastTip(this.statusMsg);
      return;
    }
    const now = Date.now();
    const targetOwner: string | undefined = this.asstMemScopeGlobal ? undefined : this.selectedId;
    if (this.asstMemEditingId.length > 0) {
      const next: MemoryEntry[] = [];
      for (let i = 0; i < this.memories.length; i++) {
        const m = this.memories[i];
        if (m.id === this.asstMemEditingId) {
          next.push({
            id: m.id,
            category: this.asstMemCat,
            content: clean,
            assistantId: targetOwner,
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
      this.statusMsg = '已更新记忆条目';
    } else {
      const next = this.memories.slice();
      next.unshift({
        id: 'mem_' + newId(),
        category: this.asstMemCat,
        content: clean,
        assistantId: targetOwner,
        archived: false,
        createdAt: now,
        updatedAt: now,
        source: 'manual'
      });
      await this.onSaveMemories(next);
      this.statusMsg = '已添加记忆条目';
    }
    this.closeSheet();
    this.asstMemEditingId = '';
    this.asstMemContent = '';
    this.showToastTip(this.statusMsg);
  }

  @Builder
  private tabPill(title: string, idx: number) {
    Button(title)
      .type(ButtonType.Normal)
      .height(34)
      .fontSize(13)
      .fontWeight(this.activeTab === idx ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.activeTab === idx ? $r('app.color.accent') : $r('app.color.muted'))
      .backgroundColor(this.activeTab === idx ? $r('app.color.tint') : Color.Transparent)
      .borderRadius(17)
      .padding({ left: 14, right: 14 })
      .onClick(() => {
        SystemMotion.quickAnimate(this.getUIContext(), this.reduceMotion, () => {
          this.activeTab = idx;
        });
        try {
          this.detailScroller.scrollTo({ xOffset: 0, yOffset: 0 });
        } catch (_) {}
      })
  }

  @Builder
  private valueRow(label: string, valText: string, fieldKey: string) {
    Row({ space: 8 }) {
      Text(label)
        .fontSize(15)
        .fontColor($r('app.color.ink'))
        .layoutWeight(1)
      Text(valText)
        .fontSize(13)
        .fontColor($r('app.color.muted'))
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(14)
        .fontColor([$r('app.color.muted')])
    }
    .width('100%')
    .padding({ left: 14, right: 12, top: 13, bottom: 13 })
    .onClick(() => {
      this.editingBasicField = this.editingBasicField === fieldKey ? '' : fieldKey;
    })
  }

  @Builder
  private switchRow(title: string, subtitle: string, checked: boolean, onChangeVal: (v: boolean) => void) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(15)
          .fontColor($r('app.color.ink'))
        if (subtitle.length > 0) {
          Text(subtitle)
            .fontSize(12)
            .fontColor($r('app.color.muted'))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: checked })
        .onChange((v: boolean) => { onChangeVal(v); })
        .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
    }
    .width('100%')
    .padding({ left: 14, right: 12, top: 11, bottom: 11 })
  }

  @Builder
  private renderBasicTab() {
    Column({ space: 12 }) {
      // Avatar & Assistant Name Card (aligned with Android)
      Row({ space: 12 }) {
        KelivoAvatarBadge({
          brandId: '',
          avatarText: this.editAvatar,
          fallbackLetter: this.editName || '助',
          badgeSize: 48
        })
        .onClick(() => { this.openSheet('avatar'); })

        Column({ space: 4 }) {
          Text('助手名称')
            .fontSize(12)
            .fontColor($r('app.color.muted'))
          TextInput({ text: this.editName, placeholder: '输入助手名称' })
            .height(40)
            .borderRadius(10)
            .backgroundColor($r('app.color.canvas'))
            .onChange((v: string) => { this.editName = v; })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)

      // Grouped Model Parameters & Appearance Switches Card
      Column() {
        this.valueRow(
          'Temperature',
          this.editTemp.trim().length > 0 ? this.editTemp.trim() : '已关闭（使用服务商默认）',
          'temp'
        )
        if (this.editingBasicField === 'temp') {
          Row({ space: 8 }) {
            TextInput({ text: this.editTemp, placeholder: '0.0 - 2.0，如 0.80' })
              .layoutWeight(1).height(36).borderRadius(8).backgroundColor($r('app.color.canvas'))
              .onChange((v: string) => { this.editTemp = v; })
            Button('关闭')
              .type(ButtonType.Normal).height(36).fontSize(12).borderRadius(8)
              .fontColor($r('app.color.muted')).backgroundColor($r('app.color.canvas'))
              .onClick(() => { this.editTemp = ''; this.editingBasicField = ''; })
          }
          .padding({ left: 14, right: 12, bottom: 10 })
        }
        Divider().color($r('app.color.line')).margin({ left: 14 })

        this.valueRow(
          'Top P',
          this.editTopP.trim().length > 0 ? this.editTopP.trim() : '已关闭（使用服务商默认）',
          'topP'
        )
        if (this.editingBasicField === 'topP') {
          Row({ space: 8 }) {
            TextInput({ text: this.editTopP, placeholder: '0.0 - 1.0，如 0.95' })
              .layoutWeight(1).height(36).borderRadius(8).backgroundColor($r('app.color.canvas'))
              .onChange((v: string) => { this.editTopP = v; })
            Button('关闭')
              .type(ButtonType.Normal).height(36).fontSize(12).borderRadius(8)
              .fontColor($r('app.color.muted')).backgroundColor($r('app.color.canvas'))
              .onClick(() => { this.editTopP = ''; this.editingBasicField = ''; })
          }
          .padding({ left: 14, right: 12, bottom: 10 })
        }
        Divider().color($r('app.color.line')).margin({ left: 14 })

        this.valueRow(
          '上下文消息数量',
          this.editContextBudget.trim().length > 0 ? `${this.editContextBudget.trim()} 条` : '已关闭（无限制）',
          'context'
        )
        if (this.editingBasicField === 'context') {
          Row({ space: 8 }) {
            TextInput({ text: this.editContextBudget, placeholder: '正整数，留空为无限制' })
              .type(InputType.Number)
              .layoutWeight(1).height(36).borderRadius(8).backgroundColor($r('app.color.canvas'))
              .onChange((v: string) => { this.editContextBudget = v; })
            Button('无限制')
              .type(ButtonType.Normal).height(36).fontSize(12).borderRadius(8)
              .fontColor($r('app.color.muted')).backgroundColor($r('app.color.canvas'))
              .onClick(() => { this.editContextBudget = ''; this.editingBasicField = ''; })
          }
          .padding({ left: 14, right: 12, bottom: 10 })
        }
        Divider().color($r('app.color.line')).margin({ left: 14 })

        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text('思考').fontSize(15).fontColor($r('app.color.ink'))
            Text('实际档位会按各模型的能力收敛').fontSize(11).fontColor($r('app.color.muted'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Select(PERSONA_REASONING_LABELS.map((label: string): SelectOption => { return { value: label }; }))
            .selected(Math.max(0, PERSONA_REASONING_OPTIONS.indexOf(this.editReasoning)))
            .value(this.reasoningDisplayText())
            .onSelect((idx: number) => {
              this.editReasoning = PERSONA_REASONING_OPTIONS[idx] || '';
            })
            .menuSystemMaterial(ImmersiveMaterialStyle.selectMenuMaterial(this.immersiveLightEnabled))
            .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
        }
        .width('100%')
        .padding({ left: 14, right: 12, top: 10, bottom: 10 })
        Divider().color($r('app.color.line')).margin({ left: 14 })

        this.valueRow(
          '最大 Token 数',
          this.editMaxTokens.trim().length > 0 ? this.editMaxTokens.trim() : '无限制',
          'maxTokens'
        )
        if (this.editingBasicField === 'maxTokens') {
          Row({ space: 8 }) {
            TextInput({ text: this.editMaxTokens, placeholder: '正整数，留空为无限制' })
              .type(InputType.Number)
              .layoutWeight(1).height(36).borderRadius(8).backgroundColor($r('app.color.canvas'))
              .onChange((v: string) => { this.editMaxTokens = v; })
            Button('无限制')
              .type(ButtonType.Normal).height(36).fontSize(12).borderRadius(8)
              .fontColor($r('app.color.muted')).backgroundColor($r('app.color.canvas'))
              .onClick(() => { this.editMaxTokens = ''; this.editingBasicField = ''; })
          }
          .padding({ left: 14, right: 12, bottom: 10 })
        }
        Divider().color($r('app.color.line')).margin({ left: 14 })

        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text('默认工作区').fontSize(15).fontColor($r('app.color.ink'))
            Text(this.workspaceDisplayText()).fontSize(12).fontColor($r('app.color.muted'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([$r('app.color.muted')])
        }
        .width('100%')
        .padding({ left: 14, right: 12, top: 12, bottom: 12 })
        .onClick(() => {
          this.editingBasicField = this.editingBasicField === 'workspace' ? '' : 'workspace';
        })

        if (this.editingBasicField === 'workspace') {
          Flex({ wrap: FlexWrap.Wrap }) {
            Button('未设置')
              .type(ButtonType.Normal).height(28).fontSize(11).margin({ right: 6, bottom: 6 }).borderRadius(8)
              .fontColor(this.editWorkspaceId === '' ? $r('app.color.on_accent') : $r('app.color.ink'))
              .backgroundColor(this.editWorkspaceId === '' ? $r('app.color.accent') : $r('app.color.canvas'))
              .onClick(() => { this.editWorkspaceId = ''; this.editingBasicField = ''; })
            ForEach(this.localWorkspaces, (ws: LocalWorkspace) => {
              Button(ws.name)
                .type(ButtonType.Normal).height(28).fontSize(11).margin({ right: 6, bottom: 6 }).borderRadius(8)
                .fontColor(this.editWorkspaceId === ws.id ? $r('app.color.on_accent') : $r('app.color.ink'))
                .backgroundColor(this.editWorkspaceId === ws.id ? $r('app.color.accent') : $r('app.color.canvas'))
                .onClick(() => { this.editWorkspaceId = ws.id; this.editingBasicField = ''; })
            }, (ws: LocalWorkspace) => ws.id)
          }
          .padding({ left: 14, right: 12, bottom: 10 })
        }

        Divider().color($r('app.color.line')).margin({ left: 14 })
        this.switchRow('使用助手头像', '消息气泡显示助手头像而非模型图标', this.editUseAssistantAvatar,
          (v: boolean) => { this.editUseAssistantAvatar = v; })
        Divider().color($r('app.color.line')).margin({ left: 14 })
        this.switchRow('使用助手名字', '消息头部显示助手名而非模型 ID', this.editUseAssistantName,
          (v: boolean) => { this.editUseAssistantName = v; })
        Divider().color($r('app.color.line')).margin({ left: 14 })
        this.switchRow('流式输出', '逐字实时显示模型生成内容', this.editStreamOutput,
          (v: boolean) => { this.editStreamOutput = v; })
      }
      .width('100%')
      .borderRadius(14)
      .backgroundColor($r('app.color.surface'))

      // Chat Model Card (aligned with Android)
      Column({ space: 8 }) {
        Row() {
          Text('聊天模型')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
          Blank()
          Button('重置为默认')
            .type(ButtonType.Normal)
            .height(26)
            .fontSize(11)
            .borderRadius(8)
            .fontColor($r('app.color.accent'))
            .backgroundColor($r('app.color.canvas'))
            .onClick(() => {
              this.editProviderId = '';
              this.editModelId = '';
              this.closeSheet();
            })
        }
        .width('100%')

        Text('为该助手设置默认聊天模型（未设置时使用全局默认）')
          .fontSize(12)
          .fontColor($r('app.color.muted'))

        Row({ space: 8 }) {
          Text(this.currentModelSummary())
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
            .layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(14)
            .fontColor([$r('app.color.muted')])
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor($r('app.color.canvas'))
        .borderRadius(10)
        .onClick(() => { this.openSheet('model'); })
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)
      .alignItems(HorizontalAlign.Start)

      // Chat Background Card
      Column({ space: 10 }) {
        Text('聊天背景')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
        Row() {
          Text('渐变背景').fontSize(14).fontColor($r('app.color.ink')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.editUseGradientBg })
            .onChange((v: boolean) => { this.editUseGradientBg = v; })
            .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
        }
        .width('100%')
        Row({ space: 8 }) {
          ForEach(PERSONA_BG_CHOICES, (bg: string, idx: number) => {
            Button(bg === '' ? '默认' : ' ')
              .type(ButtonType.Normal)
              .width(34)
              .height(30)
              .padding(0)
              .fontSize(10)
              .fontColor($r('app.color.ink'))
              .backgroundColor(bg === '' ? $r('app.color.canvas') : bg)
              .borderRadius(8)
              .borderWidth(this.editBgTint === bg ? 2 : 1)
              .borderColor(this.editBgTint === bg ? $r('app.color.accent') : $r('app.color.line'))
              .onClick(() => { this.editBgTint = bg; })
          }, (bg: string, idx: number) => `bg_${idx}`)
        }
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)
      .alignItems(HorizontalAlign.Start)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private personaSheetContent() {
    if (this.activeSheetKind === 'avatar') {
      PersonaAvatarSheet({
        editAvatar: this.editAvatar,
        bottomInsetVp: this.effectiveBottomInset(),
        onClose: () => { this.closeSheet(); }
      })
    } else if (this.activeSheetKind === 'model') {
      PersonaModelSheet({
        providers: this.providers,
        editProviderId: this.editProviderId,
        editModelId: this.editModelId,
        modelSummary: this.currentModelSummary(),
        bottomInsetVp: this.effectiveBottomInset(),
        onClose: () => { this.closeSheet(); }
      })
    } else if (this.activeSheetKind === 'memory') {
      PersonaMemoryEntrySheet({
        asstMemCat: this.asstMemCat,
        asstMemScopeGlobal: this.asstMemScopeGlobal,
        asstMemContent: this.asstMemContent,
        bottomInsetVp: this.effectiveBottomInset(),
        onCancel: () => { this.closeSheet(); },
        onSave: () => this.saveAsstMemory()
      })
    } else {
      Column() {}
    }
  }

  @Builder
  private navTitleBar() {
    if (this.pageMode === 'detail') {
      KelivoNavTitleBar({
        titleText: this.editName || '编辑助手',
        subtitleText: this.selectedId === this.activeId ? '当前启用助手' : '助手配置',
        showBack: true,
        thirdSymbol: $r('sys.symbol.rectangle_on_rectangle'),
        secondSymbol: this.personas.length > 1 ? $r('sys.symbol.trash') : undefined,
        rightText: '保存',
        rightPrimary: true,
        onBack: () => { this.onClose(); },
        onThirdAction: () => { this.cloneCurrentPersona().catch(() => {}); },
        onSecondAction: () => { this.deleteCurrentPersonaAndReturn().catch(() => {}); },
        onRightAction: () => { this.saveCurrent(false).catch(() => {}); }
      })
    } else {
      KelivoNavTitleBar({
        titleText: '助手设置',
        subtitleText: `共 ${this.personas.length} 个助手角色`,
        showBack: true,
        rightSymbol: $r('sys.symbol.plus'),
        onBack: () => { this.onClose(); },
        onRightAction: () => {
          this.createNewPersona().then((id: string) => {
            this.onOpenDetail(id);
          });
        }
      })
    }
  }

  @Builder
  private personaListView() {
    Scroll(this.listScroller) {
      Column({ space: 10 }) {
        ForEach(this.personas, (p: Persona) => {
          Column({ space: 8 }) {
            Row({ space: 12 }) {
              KelivoAvatarBadge({
                brandId: '',
                avatarText: p.avatar || '',
                fallbackLetter: p.name,
                badgeSize: 42
              })
              Column({ space: 3 }) {
                Row({ space: 6 }) {
                  Text(p.name)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.ink'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (p.id === this.activeId) {
                    Text('当前')
                      .fontSize(10)
                      .fontColor($r('app.color.accent'))
                      .backgroundColor($r('app.color.tint'))
                      .padding({ left: 7, right: 7, top: 2, bottom: 2 })
                      .borderRadius(8)
                  }
                }
                Text(p.prompt || (p.modelId || '点击配置助手详情'))
                  .fontSize(12)
                  .fontColor($r('app.color.muted'))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              if (p.id !== this.activeId) {
                Button('启用')
                  .type(ButtonType.Normal)
                  .height(28)
                  .fontSize(11)
                  .padding({ left: 10, right: 10 })
                  .borderRadius(14)
                  .backgroundColor($r('app.color.tint'))
                  .fontColor($r('app.color.accent'))
                  .onClick(() => {
                    this.onApply(p).then(() => {
                      this.showToastTip(`已启用助手：${p.name}`);
                    }).catch(() => {});
                  })
              }

              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(15)
                .fontColor([$r('app.color.muted')])
            }
            .width('100%')
          }
          .width('100%')
          .padding({ left: 14, right: 12, top: 12, bottom: 12 })
          .borderRadius(16)
          .backgroundColor($r('app.color.surface'))
          .border({ width: p.id === this.activeId ? 1.5 : 0, color: $r('app.color.accent') })
          .onClick(() => {
            this.onOpenDetail(p.id);
          })
        }, (p: Persona) => `${p.id}-${p.name}-${p.avatar || ''}-${this.activeId === p.id}`)
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 56 + this.winTopInset + 4,
        bottom: Math.max(36, this.effectiveBottomInset() + 20)
      })
    }
    .layoutWeight(1)
    .width('100%')
    .edgeEffect(EdgeEffect.Spring)
    .align(Alignment.Top)
  }

  @Builder
  private personaDetailView() {
    Stack({ alignContent: Alignment.Bottom }) {
      Scroll(this.detailScroller) {
        Column({ space: 12 }) {
          Scroll() {
            Row({ space: 4 }) {
              this.tabPill('基础设置', 0)
              this.tabPill('提示词', 1)
              this.tabPill('记忆', 2)
              this.tabPill('本地工具', 3)
              this.tabPill('技能', 4)
              this.tabPill('MCP', 5)
              this.tabPill('快捷短语', 6)
              this.tabPill('自定义请求', 7)
              this.tabPill('正则替换', 8)
            }
            .padding({ left: 16, right: 16 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')

          Column({ space: 12 }) {
            if (this.activeTab === 0) {
              this.renderBasicTab()
            } else if (this.activeTab === 1) {
              PersonaPromptTab({
                editPrompt: this.editPrompt,
                editAllowConvSystemPrompt: this.editAllowConvSystemPrompt,
                editAllowConvPromptInjection: this.editAllowConvPromptInjection,
                editAppendCurrentTime: this.editAppendCurrentTime,
                editWorldBookIds: this.editWorldBookIds,
                editPresets: this.editPresets,
                worldBooks: this.worldBooks
              })
            } else if (this.activeTab === 2) {
              PersonaMemoryTab({
                editMemoryEnabled: this.editMemoryEnabled,
                editAutoOrganizeIndex: this.editAutoOrganizeIndex,
                editMemoryCadence: this.editMemoryCadence,
                editFullMemoryTypes: this.editFullMemoryTypes,
                editSmartAddModeIndex: this.editSmartAddModeIndex,
                editWriteScopeIndex: this.editWriteScopeIndex,
                editPastRecall: this.editPastRecall,
                editGenSummary: this.editGenSummary,
                editSummaryEveryN: this.editSummaryEveryN,
                asstMemLimit: this.asstMemLimit,
                pagedMemories: this.pagedAssistantMemories(),
                totalVisibleCount: this.visibleAssistantMemoryCount(),
                remainingCount: this.remainingAssistantMemoryCount(),
                latestOrganizeStatus: this.latestAssistantOrganizeStatus(),
                isOrganizing: this.isOrganizingSelectedAssistant(),
                onOpenMemorySettings: () => { this.onOpenMemorySettings(); },
                onOrganizeMemory: () => { this.onOrganizeMemory(this.selectedId); },
                onAddMemory: () => { this.openAddAsstMemory(); },
                onEditMemory: (item: MemoryEntry) => { this.openEditAsstMemory(item); },
                onDeleteMemory: (id: string) => this.onSaveMemories(this.memories.filter((m: MemoryEntry): boolean => m.id !== id))
              })
            } else if (this.activeTab === 3) {
              PersonaLocalToolsTab({
                editBuiltinTools: this.editBuiltinTools
              })
            } else if (this.activeTab === 4) {
              PersonaSkillsTab({
                skills: this.skills,
                editSkillIds: this.editSkillIds
              })
            } else if (this.activeTab === 5) {
              PersonaMcpTab({
                mcpServers: this.mcpServers,
                editAllowConvMcp: this.editAllowConvMcp,
                editMcpIds: this.editMcpIds
              })
            } else if (this.activeTab === 6) {
              PersonaQuickPhrasesTab({
                editQuickPhrases: this.editQuickPhrases
              })
            } else if (this.activeTab === 7) {
              PersonaCustomRequestTab({
                editHeaderRows: this.editHeaderRows,
                editBodyJson: this.editBodyJson
              })
            } else {
              PersonaRegexTab({
                editRegexRules: this.editRegexRules
              })
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
        }
        .width('100%')
        .padding({
          top: 56 + this.winTopInset + 4,
          bottom: this.winKeyboardHeight > 0 ? 78 : Math.max(92, this.effectiveBottomInset() + 78)
        })
      }
      .width('100%')
      .height('100%')
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.Top)

      Column({ space: 6 }) {
        if (this.statusMsg.length > 0) {
          Text(this.statusMsg)
            .fontSize(12)
            .fontColor($r('app.color.accent'))
            .width('100%')
        }

        Row({ space: 8 }) {
          if (this.personas.length > 1) {
            Button('删除')
              .type(ButtonType.Normal)
              .height(42)
              .fontSize(13)
              .fontColor($r('app.color.warning'))
              .backgroundColor($r('app.color.surface'))
              .borderRadius(12)
              .onClick(async () => { await this.deleteCurrentPersonaAndReturn(); })
          }
          Button('克隆')
            .type(ButtonType.Normal)
            .height(42)
            .fontSize(13)
            .fontColor($r('app.color.ink'))
            .backgroundColor($r('app.color.surface'))
            .borderRadius(12)
            .onClick(() => { this.cloneCurrentPersona().catch(() => {}); })
          Button('仅保存')
            .type(ButtonType.Normal)
            .layoutWeight(1)
            .height(42)
            .fontSize(13)
            .fontColor($r('app.color.ink'))
            .backgroundColor($r('app.color.surface'))
            .borderRadius(12)
            .onClick(async () => { await this.saveCurrent(false); })
          Button('保存并启用')
            .type(ButtonType.Normal)
            .layoutWeight(1)
            .height(42)
            .fontSize(13)
            .fontColor($r('app.color.on_accent'))
            .backgroundColor($r('app.color.accent'))
            .borderRadius(12)
            .onClick(async () => {
              await this.saveCurrent(true);
              this.onClose();
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding({
        left: 16,
        right: 16,
        top: 18,
        bottom: this.winKeyboardHeight > 0 ? 8 : Math.max(12, this.effectiveBottomInset() + 6)
      })
      .linearGradient({
        direction: GradientDirection.Top,
        colors: [
          [hexWithAlpha(this.themeCanvasHex, 'F0'), 0.0],
          [hexWithAlpha(this.themeCanvasHex, 'CC'), 0.65],
          [hexWithAlpha(this.themeCanvasHex, '00'), 1.0]
        ]
      })
    }
    .width('100%')
    .layoutWeight(1)
  }

  build() {
    NavDestination() {
      Column() {
        if (this.pageMode === 'detail') {
          this.personaDetailView()
        } else {
          this.personaListView()
        }
      }
      .width('100%')
      .height('100%')
      .padding({ left: this.winLeftInset, right: this.winRightInset })
      .backgroundColor(Color.Transparent)
      .bindSheet(
        $$this.activeSheetOpen,
        this.personaSheetContent(),
        ImmersiveMaterialStyle.sheetOptions(
          this.immersiveLightEnabled,
          this.themeSurfaceHex,
          this.personaSheetTitle(),
          () => { this.closeSheet(); },
          this.activeSheetKind !== 'model'
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
      return false;
    })
  }
}
