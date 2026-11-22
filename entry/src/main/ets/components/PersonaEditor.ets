import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { computeFloatingBottomInsetVp, hexWithAlpha } from '../core/ImmersiveUtils';
import { SystemMotion } from '../core/SystemMotion';
import {
  canReadMemory,
  MEMORY_CATEGORIES,
  normalizeMemoryTimestamp
} from '../core/MemoryLogic';
import {
  GenerationParams,
  HeaderEntry,
  LocalWorkspace,
  McpServerConfig,
  MemoryCategory,
  MemoryEntry,
  MemorySettings,
  MemorySmartAddMode,
  MemorySourceKind,
  MemoryTrace,
  MemoryWriteScope,
  ModelSpec,
  Persona,
  PresetMessage,
  Provider,
  QuickPhrase,
  ReasoningEffort,
  RegexRule,
  SkillRecord,
  WorldBook,
  providerEnabledModels
} from '../core/Models';
import { newId } from '../core/Storage';
import { KelivoAvatarBadge, KelivoNavTitleBar } from './KelivoChrome';

interface LocalToolSpec {
  id: string;
  name: string;
  desc: string;
}

const BUILTIN_LOCAL_TOOLS: LocalToolSpec[] = [
  { id: 'browser_action', name: '浏览器控制', desc: '浏览并操作内置浏览器中的网页。' },
  { id: 'get_time_info', name: '时间信息', desc: '读取设备日期、星期、时间、时区与时间戳。' },
  { id: 'clipboard_tool', name: '剪切板', desc: '在明确需要时读取或写入设备剪切板文本。' },
  { id: 'text_to_speech', name: '文字转语音', desc: '允许助手使用已配置的语音播放朗读文本。' },
  { id: 'ask_user_input', name: '询问用户', desc: '允许助手提出简短问题，并在你回答后继续生成。' },
  { id: 'calculate', name: '计算器', desc: '计算数学表达式，支持加减乘除与常用科学函数。' },
  { id: 'read_chat_context', name: '读取会话上下文', desc: '读取当前或历史会话列表与消息上下文。' },
  { id: 'calendar_query', name: '查询日历', desc: '读取本设备上的日历日程，需要日历权限。' },
  { id: 'calendar_create', name: '创建日程', desc: '在你确认后于本设备创建日历日程。' },
  { id: 'get_current_location', name: '当前位置', desc: '读取本设备的一次性定位，需要定位权限。' }
];

@Component
export struct PersonaEditor {
  @Prop personas: Persona[] = [];
  @Prop activeId: string = '';
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
  onDismissOverlay: () => boolean = () => false;
  onRouteShown: () => void = () => {};
  onRouteHidden: () => void = () => {};
  onClose: () => void = () => {};

  @State viewMode: 'list' | 'detail' = 'list';
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

  private readonly memoryPolicies: MemoryWriteScope[] =
    ['alwaysGlobal', 'alwaysAssistant', 'toolDefaultGlobal', 'toolDefaultAssistant'];
  private readonly smartAddModes: MemorySmartAddMode[] = ['batched', 'perItem'];
  private readonly emojiChoices: string[] = ['🤖', '💻', '✍️', '🔬', '🎓', '🌐', '🎨', '⚡', '🧭', '📚'];
  private readonly bgChoices: string[] = ['', '#F0F6FC', '#F3F7F2', '#FDF6EC', '#F6F0FC', '#F4F4F6'];
  private readonly reasoningOptions: string[] = ['', 'off', 'low', 'medium', 'high', 'max'];
  private readonly reasoningLabels: string[] = ['跟随模型默认', '关闭', '低 (low)', '中 (medium)', '高 (high)', '最大 (max)'];
  private readonly promptVars: string[] = [
    '{cur_date}', '{cur_time}', '{cur_datetime}', '{model_id}', '{model_name}',
    '{locale}', '{timezone}', '{nickname}', '{assistant_name}'
  ];

  aboutToAppear(): void {
    const editTarget = this.initialEditId ? this.findPersonaById(this.initialEditId) : undefined;
    if (editTarget) {
      this.loadFromPersona(editTarget);
      this.viewMode = 'detail';
      return;
    }
    const initial = this.findPersonaById(this.activeId) ?? (this.personas.length > 0 ? this.personas[0] : undefined);
    if (initial) {
      this.loadFromPersona(initial);
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
    this.editWriteScopeIndex = Math.max(0, this.memoryPolicies.indexOf(p.memoryWriteScope || 'alwaysGlobal'));
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
    if (v === 'off' || v === 'low' || v === 'medium' || v === 'high' || v === 'max') {
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
    if (effort) params.reasoningEffort = effort;

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
      memorySmartAddMode: this.smartAddModes[this.editSmartAddModeIndex],
      memoryWriteScope: this.memoryPolicies[this.editWriteScopeIndex],
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
    const fallback = this.personas.find((item: Persona): boolean => item.id !== delId);
    if (fallback) {
      this.loadFromPersona(fallback);
    }
    this.setViewMode('list');
    this.showToastTip('已删除助手');
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

  private async createNewPersona(): Promise<void> {
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
  }

  private async cloneCurrentPersona(): Promise<void> {
    const cloned = this.buildPersonaObject('p_' + newId(), `${this.editName.trim() || '助手'} 副本`);
    await this.onSavePersona(cloned, false);
    this.loadFromPersona(cloned);
    this.statusMsg = '已克隆助手';
    this.showToastTip(this.statusMsg);
  }

  private toggleIdInArray(list: string[], id: string): string[] {
    const idx = list.indexOf(id);
    const next = list.slice();
    if (idx >= 0) next.splice(idx, 1);
    else next.push(id);
    return next;
  }

  private modelsForSelectedProvider(): string[] {
    for (let i = 0; i < this.providers.length; i++) {
      const p = this.providers[i];
      if (p.id === this.editProviderId) {
        const enabled = providerEnabledModels(p);
        if (enabled.length > 0) return enabled.map((m: ModelSpec): string => m.id);
        return p.model ? [p.model] : [];
      }
    }
    return [];
  }

  private currentModelSummary(): string {
    if (!this.editProviderId || !this.editModelId) return '跟随全局默认';
    const prov = this.providers.find((p: Provider): boolean => p.id === this.editProviderId);
    return prov ? `${prov.name} / ${this.editModelId}` : this.editModelId;
  }

  private reasoningDisplayText(): string {
    const idx = this.reasoningOptions.indexOf(this.editReasoning);
    return idx >= 0 ? this.reasoningLabels[idx] : '跟随模型默认';
  }

  private workspaceDisplayText(): string {
    if (!this.editWorkspaceId) return '未设置';
    const ws = this.localWorkspaces.find((w: LocalWorkspace): boolean => w.id === this.editWorkspaceId);
    return ws ? ws.name : '未设置';
  }

  private appendTemplateVar(tag: string): void {
    this.editPrompt = this.editPrompt.length > 0 ? `${this.editPrompt}${tag}` : tag;
  }

  private setViewMode(mode: 'list' | 'detail'): void {
    this.closeSheet();
    SystemMotion.springAnimate(this.getUIContext(), this.reduceMotion, () => {
      this.viewMode = mode;
    });
    try {
      if (mode === 'list') {
        this.listScroller.scrollTo({ xOffset: 0, yOffset: 0 });
      } else {
        this.detailScroller.scrollTo({ xOffset: 0, yOffset: 0 });
      }
    } catch (_) {}
  }

  private memCategoryLabel(cat: MemoryCategory): string {
    if (cat === 'identity') return '身份';
    if (cat === 'workflow') return '工作方式';
    if (cat === 'tone') return '表达风格';
    return '用户指令';
  }

  private memSourceLabel(src?: MemorySourceKind): string {
    if (src === 'tool') return '工具写入';
    if (src === 'manual') return '手动';
    return '自动提取';
  }

  private formatMemDate(ts?: number): string {
    const ms = normalizeMemoryTimestamp(ts);
    const d = new Date(ms);
    if (!Number.isFinite(d.getTime())) return '';
    const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
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
    const policy = this.memoryPolicies[this.editWriteScopeIndex];
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

          Select([
            { value: '跟随模型默认' }, { value: '关闭' }, { value: '低 (low)' },
            { value: '中 (medium)' }, { value: '高 (high)' }, { value: '最大 (max)' }
          ])
            .selected(Math.max(0, this.reasoningOptions.indexOf(this.editReasoning)))
            .value(this.reasoningDisplayText())
            .onSelect((idx: number) => {
              this.editReasoning = this.reasoningOptions[idx] || '';
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
          ForEach(this.bgChoices, (bg: string, idx: number) => {
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
  private renderPromptTab() {
    Column({ space: 12 }) {
      // System Prompt Card
      Column({ space: 10 }) {
        Text('系统提示词')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))

        TextArea({ text: this.editPrompt, placeholder: '输入系统提示词...' })
          .height(210)
          .fontSize(13)
          .borderRadius(10)
          .backgroundColor($r('app.color.canvas'))
          .onChange((v: string) => { this.editPrompt = v; })

        Text('可用变量（点击插入）：')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.muted'))

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.promptVars, (tpl: string) => {
            Button(tpl)
              .type(ButtonType.Normal)
              .height(26)
              .fontSize(11)
              .padding({ left: 8, right: 8 })
              .margin({ right: 6, bottom: 6 })
              .borderRadius(6)
              .fontColor($r('app.color.accent'))
              .backgroundColor($r('app.color.tint'))
              .onClick(() => { this.appendTemplateVar(tpl); })
          }, (tpl: string) => tpl)
        }
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)
      .alignItems(HorizontalAlign.Start)

      // Per-conversation Prompt Toggles Card
      Column() {
        this.switchRow(
          '独立对话系统提示',
          '允许每个对话设置自己的系统提示词。',
          this.editAllowConvSystemPrompt,
          (v: boolean) => { this.editAllowConvSystemPrompt = v; }
        )
        Divider().color($r('app.color.line')).margin({ left: 14 })
        this.switchRow(
          '独立对话指令注入',
          '每个对话单独选择指令注入和世界书，默认不选中。',
          this.editAllowConvPromptInjection,
          (v: boolean) => { this.editAllowConvPromptInjection = v; }
        )
        Divider().color($r('app.color.line')).margin({ left: 14 })
        this.switchRow(
          '追加当前时间',
          '在每条用户消息末尾追加发送时刻，不影响缓存。',
          this.editAppendCurrentTime,
          (v: boolean) => { this.editAppendCurrentTime = v; }
        )
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)

      if (this.worldBooks.length > 0) {
        Column({ space: 8 }) {
          Text('绑定世界书 (不选则跟随全部已启用世界书)')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.worldBooks, (wb: WorldBook) => {
              Button(wb.name)
                .type(ButtonType.Normal).height(28).fontSize(11).margin({ right: 6, bottom: 6 }).borderRadius(8)
                .fontColor(this.editWorldBookIds.indexOf(wb.id) >= 0 ? $r('app.color.on_accent') : $r('app.color.ink'))
                .backgroundColor(this.editWorldBookIds.indexOf(wb.id) >= 0 ? $r('app.color.accent') : $r('app.color.canvas'))
                .onClick(() => { this.editWorldBookIds = this.toggleIdInArray(this.editWorldBookIds, wb.id); })
            }, (wb: WorldBook) => wb.id)
          }
        }
        .width('100%')
        .padding(14)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(14)
        .alignItems(HorizontalAlign.Start)
      }

      // Preset Messages Card
      Row() {
        Text('预设对话消息 (Few-shot / 开场前置)')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
        Blank()
        Button('+ 添加')
          .type(ButtonType.Normal)
          .height(28)
          .fontSize(11)
          .borderRadius(8)
          .fontColor($r('app.color.accent'))
          .backgroundColor($r('app.color.tint'))
          .onClick(() => {
            const next = this.editPresets.slice();
            next.push({ id: 'pm_' + newId(), role: 'user', content: '' });
            this.editPresets = next;
          })
      }
      .width('100%')

      ForEach(this.editPresets, (pm: PresetMessage, idx: number) => {
        Column({ space: 6 }) {
          Row({ space: 6 }) {
            Button(pm.role)
              .type(ButtonType.Normal).height(26).fontSize(11).borderRadius(6)
              .fontColor($r('app.color.accent')).backgroundColor($r('app.color.tint'))
              .onClick(() => {
                const next = this.editPresets.slice();
                const nextRole: 'user' | 'assistant' | 'system' =
                  pm.role === 'user' ? 'assistant' : (pm.role === 'assistant' ? 'system' : 'user');
                next[idx] = { id: pm.id, role: nextRole, content: pm.content };
                this.editPresets = next;
              })
            Blank()
            Button('删除')
              .type(ButtonType.Normal).height(26).fontSize(11).borderRadius(6)
              .fontColor($r('app.color.warning')).backgroundColor($r('app.color.canvas'))
              .onClick(() => {
                const next = this.editPresets.slice();
                next.splice(idx, 1);
                this.editPresets = next;
              })
          }
          .width('100%')

          TextArea({ text: pm.content, placeholder: '消息内容...' })
            .height(64).borderRadius(8).backgroundColor($r('app.color.canvas'))
            .onChange((v: string) => {
              const next = this.editPresets.slice();
              next[idx] = { id: pm.id, role: pm.role, content: v };
              this.editPresets = next;
            })
        }
        .padding(10)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(12)
        .width('100%')
      }, (pm: PresetMessage) => pm.id)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private renderMemoryCategory(title: string, category: MemoryCategory) {
    Row() {
      Text(title).fontSize(13).fontColor($r('app.color.ink'))
      Blank()
      Toggle({ type: ToggleType.Switch, isOn: this.editFullMemoryTypes.includes(category) })
        .onChange((enabled: boolean) => {
          const remaining = this.editFullMemoryTypes.filter((item: MemoryCategory): boolean => item !== category);
          this.editFullMemoryTypes = enabled ? remaining.concat([category]) : remaining;
        })
        .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
    }
    .width('100%')
  }

  @Builder
  private renderMemoryTab() {
    Column({ space: 12 }) {
      Column({ space: 10 }) {
        Row() {
          Column({ space: 2 }) {
            Text('使用长期记忆').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink'))
            Text('把已保存的记忆注入对话，并允许此助手写入新记忆').fontSize(11).fontColor($r('app.color.muted'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.editMemoryEnabled })
            .onChange((value: boolean) => { this.editMemoryEnabled = value; })
            .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
        }
        .width('100%')

        if (this.editMemoryEnabled) {
          Divider().color($r('app.color.line'))

          Column({ space: 6 }) {
            Text('全量注入类型').fontSize(14).fontColor($r('app.color.ink'))
            Text('选中类型会注入全部有效记忆，不受条数限制').fontSize(11).fontColor($r('app.color.muted'))
            this.renderMemoryCategory('身份信息 (identity)', 'identity')
            this.renderMemoryCategory('工作方式 (workflow)', 'workflow')
            this.renderMemoryCategory('表达风格 (voice)', 'tone')
            this.renderMemoryCategory('用户指令 (instruction)', 'instruction')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Divider().color($r('app.color.line'))

          Row() {
            Text('自动整理记忆').fontSize(14).fontColor($r('app.color.ink'))
            Blank()
            Select([{ value: '跟随全局' }, { value: '开启' }, { value: '关闭' }])
              .selected(this.editAutoOrganizeIndex)
              .value(['跟随全局', '开启', '关闭'][this.editAutoOrganizeIndex])
              .onSelect((index: number) => { this.editAutoOrganizeIndex = index; })
              .menuSystemMaterial(ImmersiveMaterialStyle.selectMenuMaterial(this.immersiveLightEnabled))
              .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
          }
          .width('100%')

          if (this.editAutoOrganizeIndex !== 2) {
            Row({ space: 8 }) {
              Text('整理频率（每 N 轮）').fontSize(14).fontColor($r('app.color.ink'))
              Blank()
              TextInput({ text: this.editMemoryCadence })
                .type(InputType.Number)
                .maxLength(2)
                .width(64)
                .height(34)
                .textAlign(TextAlign.Center)
                .backgroundColor($r('app.color.canvas'))
                .borderRadius(8)
                .onChange((value: string) => { this.editMemoryCadence = value; })
            }
            .width('100%')
          }

          Row() {
            Text('去重方式').fontSize(14).fontColor($r('app.color.ink'))
            Blank()
            Select([{ value: '批量 (Batched)' }, { value: '逐条 (Per item)' }])
              .selected(this.editSmartAddModeIndex)
              .value(['批量 (Batched)', '逐条 (Per item)'][this.editSmartAddModeIndex])
              .onSelect((index: number) => { this.editSmartAddModeIndex = index; })
              .menuSystemMaterial(ImmersiveMaterialStyle.selectMenuMaterial(this.immersiveLightEnabled))
              .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
          }
          .width('100%')

          Row() {
            Text('记忆写入范围').fontSize(14).fontColor($r('app.color.ink'))
            Blank()
            Select([{ value: '始终全局' }, { value: '一律本助手' }, { value: '由工具决定 · 默认全局' },
              { value: '由工具决定 · 默认本助手' }])
              .selected(this.editWriteScopeIndex)
              .value(['始终全局', '一律本助手', '由工具决定 · 默认全局', '由工具决定 · 默认本助手'][this.editWriteScopeIndex])
              .onSelect((index: number) => { this.editWriteScopeIndex = index; })
              .menuSystemMaterial(ImmersiveMaterialStyle.selectMenuMaterial(this.immersiveLightEnabled))
              .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
          }
          .width('100%')
        }

        Divider().color($r('app.color.line'))

        Row() {
          Column({ space: 2 }) {
            Text('允许回忆过去对话').fontSize(14).fontColor($r('app.color.ink'))
            Text('启用跨会话的对话搜索').fontSize(11).fontColor($r('app.color.muted'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.editPastRecall })
            .onChange((value: boolean) => { this.editPastRecall = value; })
            .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
        }
        .width('100%')

        Row() {
          Column({ space: 2 }) {
            Text('生成会话摘要').fontSize(14).fontColor($r('app.color.ink'))
            Text('摘要仅供对话搜索使用').fontSize(11).fontColor($r('app.color.muted'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.editGenSummary })
            .onChange((value: boolean) => { this.editGenSummary = value; })
            .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
        }
        .width('100%')

        if (this.editGenSummary) {
          Row({ space: 8 }) {
            Text('摘要更新频率（每 N 条）').fontSize(14).fontColor($r('app.color.ink'))
            Blank()
            TextInput({ text: this.editSummaryEveryN })
              .type(InputType.Number)
              .maxLength(2)
              .width(64)
              .height(34)
              .textAlign(TextAlign.Center)
              .backgroundColor($r('app.color.canvas'))
              .borderRadius(8)
              .onChange((value: string) => { this.editSummaryEveryN = value; })
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding(14)
      .alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)

      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text('记忆')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
          Text('记忆模式、模型与提示词')
            .fontSize(12)
            .fontColor($r('app.color.muted'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(15)
          .fontColor([$r('app.color.muted')])
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)
      .onClick(() => { this.onOpenMemorySettings(); })

      Column({ space: 10 }) {
        Row({ space: 6 }) {
          Column({ space: 2 }) {
            Text('本助手可见的记忆')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))
            Text(`共 ${this.visibleAssistantMemoryCount()} 条有效记忆`)
              .fontSize(11)
              .fontColor($r('app.color.muted'))
            if (this.latestAssistantOrganizeStatus().length > 0) {
              Text(this.latestAssistantOrganizeStatus())
                .fontSize(11)
                .fontColor($r('app.color.muted'))
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button(this.isOrganizingSelectedAssistant() ? '整理中…' : '整理记忆')
            .type(ButtonType.Normal)
            .height(30)
            .fontSize(12)
            .padding({ left: 10, right: 10 })
            .borderRadius(10)
            .fontColor($r('app.color.accent'))
            .backgroundColor($r('app.color.tint'))
            .enabled(!this.isOrganizingSelectedAssistant())
            .opacity(this.isOrganizingSelectedAssistant() ? 0.55 : 1)
            .onClick(() => { this.onOrganizeMemory(this.selectedId); })

          Button('+ 添加')
            .type(ButtonType.Normal)
            .height(30)
            .fontSize(12)
            .padding({ left: 10, right: 10 })
            .borderRadius(10)
            .fontColor($r('app.color.on_accent'))
            .backgroundColor($r('app.color.accent'))
            .onClick(() => { this.openAddAsstMemory(); })
        }
        .width('100%')

        if (this.visibleAssistantMemoryCount() === 0) {
          Text('当前助手暂无可见的长期记忆')
            .fontSize(12)
            .fontColor($r('app.color.muted'))
            .padding(14)
        } else {
          ForEach(this.pagedAssistantMemories(), (item: MemoryEntry) => {
            Column({ space: 6 }) {
              Row({ space: 6 }) {
                Text(this.memCategoryLabel(item.category))
                  .fontSize(11)
                  .fontColor($r('app.color.accent'))
                  .backgroundColor($r('app.color.tint'))
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .borderRadius(10)

                Text(item.assistantId ? '仅本助手' : '全局')
                  .fontSize(11)
                  .fontColor($r('app.color.muted'))
                  .backgroundColor($r('app.color.canvas'))
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .borderRadius(10)

                Blank()

                Button('编辑')
                  .type(ButtonType.Normal)
                  .height(26)
                  .fontSize(11)
                  .padding({ left: 8, right: 8 })
                  .borderRadius(6)
                  .fontColor($r('app.color.accent'))
                  .backgroundColor($r('app.color.canvas'))
                  .onClick(() => { this.openEditAsstMemory(item); })

                Button('删除')
                  .type(ButtonType.Normal)
                  .height(26)
                  .fontSize(11)
                  .padding({ left: 8, right: 8 })
                  .borderRadius(6)
                  .fontColor($r('app.color.warning'))
                  .backgroundColor($r('app.color.canvas'))
                  .onClick(async () => {
                    await this.onSaveMemories(this.memories.filter((m: MemoryEntry): boolean => m.id !== item.id));
                  })
              }
              .width('100%')

              Text(item.content)
                .fontSize(13)
                .lineHeight(19)
                .fontColor($r('app.color.ink'))

              Text(`更新于 ${this.formatMemDate(item.updatedAt)} · ${this.memSourceLabel(item.source)}`)
                .fontSize(11)
                .fontColor($r('app.color.muted'))
            }
            .width('100%')
            .padding(12)
            .backgroundColor($r('app.color.surface'))
            .borderRadius(12)
            .alignItems(HorizontalAlign.Start)
          }, (item: MemoryEntry) => `am_${item.id}_${item.updatedAt}`)

          if (this.remainingAssistantMemoryCount() > 0) {
            Button(`加载更多（剩余 ${this.remainingAssistantMemoryCount()} 条）`)
              .type(ButtonType.Normal)
              .width('100%')
              .height(38)
              .fontSize(12)
              .borderRadius(10)
              .fontColor($r('app.color.accent'))
              .backgroundColor($r('app.color.surface'))
              .onClick(() => { this.asstMemLimit += 30; })
          }
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private renderLocalToolsTab() {
    Column({ space: 10 }) {
      Text('为该助手启用的设备本地工具')
        .fontSize(12)
        .fontColor($r('app.color.muted'))
        .padding({ left: 4 })

      Column() {
        ForEach(BUILTIN_LOCAL_TOOLS, (tool: LocalToolSpec, idx: number) => {
          Column() {
            if (idx > 0) {
              Divider().color($r('app.color.line')).margin({ left: 14 })
            }
            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text(tool.name).fontSize(15).fontColor($r('app.color.ink'))
                Text(tool.desc).fontSize(12).fontColor($r('app.color.muted'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.editBuiltinTools.indexOf(tool.id) >= 0 })
                .onChange((enabled: boolean) => {
                  const has = this.editBuiltinTools.indexOf(tool.id) >= 0;
                  if (enabled !== has) {
                    this.editBuiltinTools = this.toggleIdInArray(this.editBuiltinTools, tool.id);
                  }
                })
                .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
            }
            .width('100%')
            .padding({ left: 14, right: 12, top: 12, bottom: 12 })
          }
        }, (tool: LocalToolSpec) => `lt_${tool.id}`)
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private renderSkillsTab() {
    Column({ space: 10 }) {
      Text('为该助手启用的 Agent Skills 技能包')
        .fontSize(12)
        .fontColor($r('app.color.muted'))
        .padding({ left: 4 })

      if (this.skills.length === 0) {
        Text('暂无可用技能，可在「设置 → 技能」中添加或导入')
          .fontSize(13)
          .fontColor($r('app.color.muted'))
          .padding(16)
      } else {
        Column() {
          ForEach(this.skills, (sk: SkillRecord, idx: number) => {
            Column() {
              if (idx > 0) {
                Divider().color($r('app.color.line')).margin({ left: 14 })
              }
              Row({ space: 12 }) {
                Column({ space: 2 }) {
                  Text(sk.name).fontSize(15).fontColor($r('app.color.ink'))
                  Text(sk.description).fontSize(12).fontColor($r('app.color.muted')).maxLines(2)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: this.editSkillIds.indexOf(sk.id) >= 0 })
                  .onChange((enabled: boolean) => {
                    const has = this.editSkillIds.indexOf(sk.id) >= 0;
                    if (enabled !== has) {
                      this.editSkillIds = this.toggleIdInArray(this.editSkillIds, sk.id);
                    }
                  })
                  .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
              }
              .width('100%')
              .padding({ left: 14, right: 12, top: 12, bottom: 12 })
            }
          }, (sk: SkillRecord) => `sk_${sk.id}`)
        }
        .width('100%')
        .backgroundColor($r('app.color.surface'))
        .borderRadius(14)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private renderMcpTab() {
    Column({ space: 12 }) {
      Column() {
        this.switchRow(
          '允许对话自定义 MCP',
          '开启后，对话可单独选择 MCP 服务器；未自定义时跟随助手设置。',
          this.editAllowConvMcp,
          (v: boolean) => { this.editAllowConvMcp = v; }
        )
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)

      Text('MCP 服务器（为该助手启用的服务）')
        .fontSize(12)
        .fontColor($r('app.color.muted'))
        .padding({ left: 4 })

      if (this.mcpServers.length === 0) {
        Text('尚未添加 MCP 服务器，可在「设置 → MCP」中配置')
          .fontSize(13)
          .fontColor($r('app.color.muted'))
          .padding(16)
      } else {
        Column() {
          ForEach(this.mcpServers, (srv: McpServerConfig, idx: number) => {
            Column() {
              if (idx > 0) {
                Divider().color($r('app.color.line')).margin({ left: 14 })
              }
              Row({ space: 12 }) {
                Column({ space: 2 }) {
                  Text(srv.name).fontSize(15).fontColor($r('app.color.ink'))
                  Text(srv.endpoint).fontSize(11).fontColor($r('app.color.muted')).maxLines(1)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: this.editMcpIds.indexOf(srv.id) >= 0 })
                  .onChange((enabled: boolean) => {
                    const has = this.editMcpIds.indexOf(srv.id) >= 0;
                    if (enabled !== has) {
                      this.editMcpIds = this.toggleIdInArray(this.editMcpIds, srv.id);
                    }
                  })
                  .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
              }
              .width('100%')
              .padding({ left: 14, right: 12, top: 12, bottom: 12 })
            }
          }, (srv: McpServerConfig) => `mcp_${srv.id}`)
        }
        .width('100%')
        .backgroundColor($r('app.color.surface'))
        .borderRadius(14)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private renderQuickPhrasesTab() {
    Column({ space: 10 }) {
      Row() {
        Text('管理该助手的专属快捷短语')
          .fontSize(13)
          .fontColor($r('app.color.muted'))
        Blank()
        Button('+ 添加快捷短语')
          .type(ButtonType.Normal)
          .height(30)
          .fontSize(12)
          .borderRadius(10)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor($r('app.color.accent'))
          .onClick(() => {
            const next = this.editQuickPhrases.slice();
            next.push({ id: 'qp_' + newId(), title: '快捷短语', content: '', scope: 'assistant' });
            this.editQuickPhrases = next;
          })
      }
      .width('100%')

      if (this.editQuickPhrases.length === 0) {
        Text('尚未添加快捷短语，点击右上角按钮添加。')
          .fontSize(13)
          .fontColor($r('app.color.muted'))
          .padding(16)
      } else {
        ForEach(this.editQuickPhrases, (qp: QuickPhrase, idx: number) => {
          Column({ space: 6 }) {
            Row({ space: 6 }) {
              TextInput({ text: qp.title, placeholder: '短语标题' })
                .layoutWeight(1).height(36).borderRadius(8).backgroundColor($r('app.color.canvas'))
                .onChange((v: string) => {
                  const next = this.editQuickPhrases.slice();
                  next[idx] = { id: qp.id, title: v, content: qp.content, scope: 'assistant' };
                  this.editQuickPhrases = next;
                })
              Button('删除')
                .type(ButtonType.Normal).height(32).fontSize(11).borderRadius(8)
                .fontColor($r('app.color.warning')).backgroundColor($r('app.color.canvas'))
                .onClick(() => {
                  const next = this.editQuickPhrases.slice();
                  next.splice(idx, 1);
                  this.editQuickPhrases = next;
                })
            }
            TextArea({ text: qp.content, placeholder: '短语内容...' })
              .height(64).borderRadius(8).backgroundColor($r('app.color.canvas'))
              .onChange((v: string) => {
                const next = this.editQuickPhrases.slice();
                next[idx] = { id: qp.id, title: qp.title, content: v, scope: 'assistant' };
                this.editQuickPhrases = next;
              })
          }
          .padding(12)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .width('100%')
        }, (qp: QuickPhrase) => qp.id)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private renderCustomRequestTab() {
    Column({ space: 12 }) {
      Column({ space: 8 }) {
        Row() {
          Text('自定义 Header')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
          Blank()
          Button('+ 添加 Header')
            .type(ButtonType.Normal)
            .height(28)
            .fontSize(11)
            .borderRadius(8)
            .fontColor($r('app.color.accent'))
            .backgroundColor($r('app.color.tint'))
            .onClick(() => {
              const next = this.editHeaderRows.slice();
              next.push({ key: '', value: '' });
              this.editHeaderRows = next;
            })
        }
        .width('100%')

        if (this.editHeaderRows.length === 0) {
          Text('未添加 Header')
            .fontSize(12)
            .fontColor($r('app.color.muted'))
        } else {
          ForEach(this.editHeaderRows, (hdr: HeaderEntry, idx: number) => {
            Row({ space: 6 }) {
              TextInput({ text: hdr.key, placeholder: 'Header 名' })
                .layoutWeight(1).height(36).borderRadius(8).backgroundColor($r('app.color.canvas'))
                .onChange((v: string) => {
                  const next = this.editHeaderRows.slice();
                  next[idx] = { key: v, value: hdr.value };
                  this.editHeaderRows = next;
                })
              TextInput({ text: hdr.value, placeholder: 'Header 值' })
                .layoutWeight(1).height(36).borderRadius(8).backgroundColor($r('app.color.canvas'))
                .onChange((v: string) => {
                  const next = this.editHeaderRows.slice();
                  next[idx] = { key: hdr.key, value: v };
                  this.editHeaderRows = next;
                })
              Button('删除')
                .type(ButtonType.Normal).height(32).fontSize(11).borderRadius(8)
                .fontColor($r('app.color.warning')).backgroundColor($r('app.color.canvas'))
                .onClick(() => {
                  const next = this.editHeaderRows.slice();
                  next.splice(idx, 1);
                  this.editHeaderRows = next;
                })
            }
            .width('100%')
          }, (hdr: HeaderEntry, idx: number) => `hdr_${idx}`)
        }
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 8 }) {
        Text('自定义 Body (JSON 对象)')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
        TextArea({ text: this.editBodyJson, placeholder: '{"presence_penalty": 0.2}' })
          .height(100)
          .fontSize(12)
          .borderRadius(8)
          .backgroundColor($r('app.color.canvas'))
          .onChange((v: string) => { this.editBodyJson = v; })
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
  private renderRegexTab() {
    Column({ space: 10 }) {
      Row() {
        Text('为用户/助手消息配置正则替换规则')
          .fontSize(13)
          .fontColor($r('app.color.muted'))
        Blank()
        Button('+ 添加正则规则')
          .type(ButtonType.Normal)
          .height(30)
          .fontSize(12)
          .borderRadius(10)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor($r('app.color.accent'))
          .onClick(() => {
            const next = this.editRegexRules.slice();
            next.push({
              id: 'rx_' + newId(),
              name: '新正则',
              pattern: '',
              replacement: '',
              flags: 'g',
              scope: 'output',
              enabled: true
            });
            this.editRegexRules = next;
          })
      }
      .width('100%')

      if (this.editRegexRules.length === 0) {
        Text('未配置正则规则，点击右上角按钮添加。')
          .fontSize(13)
          .fontColor($r('app.color.muted'))
          .padding(16)
      } else {
        ForEach(this.editRegexRules, (rule: RegexRule, idx: number) => {
          Column({ space: 6 }) {
            Row({ space: 6 }) {
              TextInput({ text: rule.name, placeholder: '规则名' })
                .layoutWeight(1).height(34).borderRadius(8).backgroundColor($r('app.color.canvas'))
                .onChange((v: string) => {
                  const next = this.editRegexRules.slice();
                  next[idx] = {
                    id: rule.id, name: v, pattern: rule.pattern, replacement: rule.replacement,
                    flags: rule.flags, scope: rule.scope, enabled: rule.enabled
                  };
                  this.editRegexRules = next;
                })
              Button(rule.scope)
                .type(ButtonType.Normal).height(30).fontSize(11).borderRadius(6)
                .fontColor($r('app.color.accent')).backgroundColor($r('app.color.tint'))
                .onClick(() => {
                  const next = this.editRegexRules.slice();
                  const nextScope: 'input' | 'output' | 'display' =
                    rule.scope === 'output' ? 'display' : (rule.scope === 'display' ? 'input' : 'output');
                  next[idx] = {
                    id: rule.id, name: rule.name, pattern: rule.pattern, replacement: rule.replacement,
                    flags: rule.flags, scope: nextScope, enabled: rule.enabled
                  };
                  this.editRegexRules = next;
                })
              Button('删除')
                .type(ButtonType.Normal).height(30).fontSize(11).borderRadius(6)
                .fontColor($r('app.color.warning')).backgroundColor($r('app.color.canvas'))
                .onClick(() => {
                  const next = this.editRegexRules.slice();
                  next.splice(idx, 1);
                  this.editRegexRules = next;
                })
            }
            Row({ space: 6 }) {
              TextInput({ text: rule.pattern, placeholder: '正则表达式 (Pattern)' })
                .layoutWeight(2).height(34).borderRadius(8).backgroundColor($r('app.color.canvas'))
                .onChange((v: string) => {
                  const next = this.editRegexRules.slice();
                  next[idx] = {
                    id: rule.id, name: rule.name, pattern: v, replacement: rule.replacement,
                    flags: rule.flags, scope: rule.scope, enabled: rule.enabled
                  };
                  this.editRegexRules = next;
                })
              TextInput({ text: rule.flags, placeholder: 'flags' })
                .width(56).height(34).borderRadius(8).backgroundColor($r('app.color.canvas'))
                .onChange((v: string) => {
                  const next = this.editRegexRules.slice();
                  next[idx] = {
                    id: rule.id, name: rule.name, pattern: rule.pattern, replacement: rule.replacement,
                    flags: v, scope: rule.scope, enabled: rule.enabled
                  };
                  this.editRegexRules = next;
                })
            }
            TextInput({ text: rule.replacement, placeholder: '替换为...' })
              .height(34).borderRadius(8).backgroundColor($r('app.color.canvas'))
              .onChange((v: string) => {
                const next = this.editRegexRules.slice();
                next[idx] = {
                  id: rule.id, name: rule.name, pattern: rule.pattern, replacement: v,
                  flags: rule.flags, scope: rule.scope, enabled: rule.enabled
                };
                this.editRegexRules = next;
              })
          }
          .padding(10)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .width('100%')
        }, (rule: RegexRule) => rule.id)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private avatarSheetBody() {
    Column({ space: 12 }) {
      Text('选择预设图标，或使用助手名称首字作为头像')
        .fontSize(12)
        .fontColor($r('app.color.muted'))

      Flex({ wrap: FlexWrap.Wrap }) {
        Button('首字')
          .type(ButtonType.Normal)
          .height(38)
          .fontSize(12)
          .margin({ right: 8, bottom: 8 })
          .borderRadius(10)
          .fontColor(this.editAvatar === '' ? $r('app.color.on_accent') : $r('app.color.ink'))
          .backgroundColor(this.editAvatar === '' ? $r('app.color.accent') : $r('app.color.panel'))
          .onClick(() => {
            this.editAvatar = '';
            this.closeSheet();
          })

        ForEach(this.emojiChoices, (em: string) => {
          Button(em)
            .type(ButtonType.Normal)
            .width(42)
            .height(42)
            .padding(0)
            .fontSize(21)
            .margin({ right: 8, bottom: 8 })
            .backgroundColor(this.editAvatar === em ? $r('app.color.tint') : $r('app.color.panel'))
            .borderRadius(12)
            .onClick(() => {
              this.editAvatar = em;
              this.closeSheet();
            })
        }, (em: string) => em)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 4, bottom: Math.max(24, this.effectiveBottomInset() + 12) })
  }

  @Builder
  private modelSheetBody() {
    Column() {
      Scroll() {
        Column({ space: 12 }) {
          Text(`当前选择：${this.currentModelSummary()}`)
            .fontSize(12)
            .fontColor($r('app.color.muted'))

          Text('服务商')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))

          Flex({ wrap: FlexWrap.Wrap }) {
            Button('跟随全局')
              .type(ButtonType.Normal)
              .height(32)
              .fontSize(12)
              .margin({ right: 6, bottom: 6 })
              .borderRadius(10)
              .fontColor(this.editProviderId === '' ? $r('app.color.on_accent') : $r('app.color.ink'))
              .backgroundColor(this.editProviderId === '' ? $r('app.color.accent') : $r('app.color.panel'))
              .onClick(() => {
                this.editProviderId = '';
                this.editModelId = '';
                this.closeSheet();
              })

            ForEach(this.providers, (prov: Provider) => {
              Button(prov.name)
                .type(ButtonType.Normal)
                .height(32)
                .fontSize(12)
                .margin({ right: 6, bottom: 6 })
                .borderRadius(10)
                .fontColor(this.editProviderId === prov.id ? $r('app.color.on_accent') : $r('app.color.ink'))
                .backgroundColor(this.editProviderId === prov.id ? $r('app.color.accent') : $r('app.color.panel'))
                .onClick(() => {
                  this.editProviderId = prov.id;
                  this.editModelId = prov.model;
                })
            }, (prov: Provider) => prov.id)
          }
          .width('100%')

          if (this.editProviderId.length > 0 && this.modelsForSelectedProvider().length > 0) {
            Text('模型列表')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.modelsForSelectedProvider(), (mId: string) => {
                Button(mId)
                  .type(ButtonType.Normal)
                  .height(30)
                  .fontSize(12)
                  .margin({ right: 6, bottom: 6 })
                  .borderRadius(10)
                  .fontColor(this.editModelId === mId ? $r('app.color.accent') : $r('app.color.ink'))
                  .backgroundColor(this.editModelId === mId ? $r('app.color.tint') : $r('app.color.panel'))
                  .onClick(() => {
                    this.editModelId = mId;
                    this.closeSheet();
                  })
              }, (mId: string) => mId)
            }
            .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 4, bottom: Math.max(24, this.effectiveBottomInset() + 12) })
      }
      .width('100%')
      .layoutWeight(1)
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private memorySheetBody() {
    Column({ space: 10 }) {
      Row({ space: 6 }) {
        ForEach(MEMORY_CATEGORIES, (cat: MemoryCategory) => {
          Button(this.memCategoryLabel(cat))
            .type(ButtonType.Normal)
            .height(28)
            .fontSize(11)
            .borderRadius(8)
            .fontColor(this.asstMemCat === cat ? $r('app.color.on_accent') : $r('app.color.ink'))
            .backgroundColor(this.asstMemCat === cat ? $r('app.color.accent') : $r('app.color.panel'))
            .onClick(() => { this.asstMemCat = cat; })
        }, (cat: MemoryCategory) => `acat_${cat}`)
      }
      .width('100%')

      TextArea({ text: this.asstMemContent, placeholder: '输入记忆内容...' })
        .height(92)
        .borderRadius(10)
        .backgroundColor($r('app.color.panel'))
        .onChange((v: string) => { this.asstMemContent = v; })

      Row({ space: 8 }) {
        Button(this.asstMemScopeGlobal ? '范围：全局' : '范围：仅本助手')
          .type(ButtonType.Normal)
          .height(34)
          .fontSize(12)
          .borderRadius(10)
          .fontColor($r('app.color.ink'))
          .backgroundColor($r('app.color.panel'))
          .onClick(() => { this.asstMemScopeGlobal = !this.asstMemScopeGlobal; })
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
          .onClick(async () => { await this.saveAsstMemory(); })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 4, bottom: Math.max(24, this.effectiveBottomInset() + 12) })
  }

  @Builder
  private personaSheetContent() {
    if (this.activeSheetKind === 'avatar') {
      this.avatarSheetBody()
    } else if (this.activeSheetKind === 'model') {
      this.modelSheetBody()
    } else if (this.activeSheetKind === 'memory') {
      this.memorySheetBody()
    } else {
      Column() {}
    }
  }

  @Builder
  private navTitleBar() {
    if (this.viewMode === 'detail') {
      KelivoNavTitleBar({
        titleText: this.editName || '编辑助手',
        subtitleText: this.selectedId === this.activeId ? '当前启用助手' : '助手配置',
        showBack: true,
        thirdSymbol: $r('sys.symbol.rectangle_on_rectangle'),
        secondSymbol: this.personas.length > 1 ? $r('sys.symbol.trash') : undefined,
        rightText: '保存',
        rightPrimary: true,
        onBack: () => { this.setViewMode('list'); },
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
          this.createNewPersona().then(() => {
            this.setViewMode('detail');
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
            this.loadFromPersona(p);
            this.setViewMode('detail');
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
    .transition(SystemMotion.subViewTransition(this.reduceMotion))
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
              this.renderPromptTab()
            } else if (this.activeTab === 2) {
              this.renderMemoryTab()
            } else if (this.activeTab === 3) {
              this.renderLocalToolsTab()
            } else if (this.activeTab === 4) {
              this.renderSkillsTab()
            } else if (this.activeTab === 5) {
              this.renderMcpTab()
            } else if (this.activeTab === 6) {
              this.renderQuickPhrasesTab()
            } else if (this.activeTab === 7) {
              this.renderCustomRequestTab()
            } else {
              this.renderRegexTab()
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
              this.setViewMode('list');
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
    .transition(SystemMotion.subViewTransition(this.reduceMotion))
  }

  build() {
    NavDestination() {
      Column() {
        if (this.viewMode === 'detail') {
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
      if (this.viewMode === 'detail') {
        this.setViewMode('list');
        return true;
      }
      return false;
    })
  }
}
