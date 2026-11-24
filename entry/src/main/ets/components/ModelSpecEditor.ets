import { pasteboard } from '@kit.BasicServicesKit';
import {
  HeaderEntry,
  ModelKindType,
  ModelModality,
  ModelOutputModality,
  ModelPricingSpec,
  ModelReasoningDialectOverride,
  ModelReasoningReplayField,
  ModelReasoningReplayPolicy,
  ModelSamplingPolicy,
  ModelSpec,
  Provider,
  ReasoningEffort,
  defaultModelSpec,
  preset
} from '../core/Models';
import {
  REASONING_NON_OFF_ORDER,
  ReasoningControl,
  inferReasoningControl,
  usesResponsesApi
} from '../core/Reasoning';
import { isDeepSeekProvider, isOpenRouterProvider } from '../core/BuiltinSearch';
import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { hexWithAlpha } from '../core/ImmersiveUtils';
import { SystemMotion } from '../core/SystemMotion';
import { KelivoNavTitleBar, KelivoSectionHeader } from './KelivoChrome';

@Component
export struct ModelSpecEditor {
  @Prop provider: Provider = preset('', '', 'openai', '', '');
  @Prop @Watch('onInitialSpecChange') initialSpec: ModelSpec = defaultModelSpec('');
  @Prop isNew: boolean = false;
  onSave: (spec: ModelSpec) => void = () => {};
  onCancel: () => void = () => {};
  onDismissOverlay: () => boolean = () => false;
  onRouteShown: () => void = () => {};
  onRouteHidden: () => void = () => {};

  @StorageProp('immersiveLightEnabled') immersiveLightEnabled: boolean = true;
  @StorageProp('effectiveDarkMode') isDark: boolean = false;
  @StorageProp('themeCanvasHex') themeCanvasHex: string = '#F7F7F7';
  @StorageProp('themeSurfaceHex') themeSurfaceHex: string = '#FFFFFF';
  @StorageProp('themeAccentHex') themeAccentHex: string = '#4D5C92';
  @StorageProp('themeTintHex') themeTintHex: string = '#DCE1FF';
  @StorageProp('windowTopInsetVp') winTopInset: number = 0;
  @StorageProp('windowBottomInsetVp') winBottomInset: number = 0;
  @StorageProp('windowLeftInsetVp') winLeftInset: number = 0;
  @StorageProp('windowRightInsetVp') winRightInset: number = 0;
  @StorageProp('reduceMotionEnabled') reduceMotion: boolean = false;

  private editorScroller: Scroller = new Scroller();

  @State editTab: number = 0;

  // 基本设置
  @State modelIdInput: string = '';
  @State displayNameInput: string = '';
  @State modelKindType: ModelKindType = 'chat';
  @State inputMods: ModelModality[] = ['text'];
  @State outputMods: ModelOutputModality[] = ['text'];
  @State toolsCap: boolean = true;
  @State reasoningCap: boolean = false;
  @State structuredCap: boolean = false;
  @State contextWindowText: string = '128000';
  @State maxOutputText: string = '8192';
  @State priceInputText: string = '';
  @State priceOutputText: string = '';
  @State priceCacheReadText: string = '';
  @State priceCacheWriteText: string = '';
  @State priceCurrency: string = 'USD';

  // 推理
  @State dialectOverride: ModelReasoningDialectOverride = 'auto';
  @State selectedLevels: ReasoningEffort[] = ['low', 'medium', 'high'];
  @State levelsCustomized: boolean = false;
  @State allowOffFlag: boolean = true;
  @State allowOffCustomized: boolean = false;
  @State defaultLevelChoice: 'auto' | ReasoningEffort = 'auto';
  @State samplingChoice: 'default' | ModelSamplingPolicy = 'default';
  @State replayChoice: 'default' | ModelReasoningReplayPolicy = 'default';
  @State replayFieldChoice: 'default' | ModelReasoningReplayField = 'default';

  // 高级设置
  @State customHeadersList: HeaderEntry[] = [];
  @State showHeaderAdd: boolean = false;
  @State headerKeyInput: string = '';
  @State headerValInput: string = '';

  @State customBodyList: HeaderEntry[] = [];
  @State showBodyAdd: boolean = false;
  @State bodyKeyInput: string = '';
  @State bodyValInput: string = '';

  @State allowRemoteImages: boolean = true;
  @State remoteImagesCustomized: boolean = false;

  @State toolCodeInterpreter: boolean = false;
  @State toolImageGen: boolean = false;
  @State toolUrlContext: boolean = false;
  @State toolCodeExec: boolean = false;
  @State toolYoutube: boolean = false;
  @State toolWebFetch: boolean = false;
  @State toolShell: boolean = false;

  @State errorTip: string = '';
  @State listRev: number = 0;

  aboutToAppear(): void {
    this.loadFromSpec(this.initialSpec);
  }

  private onInitialSpecChange(): void {
    this.loadFromSpec(this.initialSpec);
  }

  private effectiveModelId(): string {
    return (this.modelIdInput || this.initialSpec.id || '').trim();
  }

  private inferredControl(): ReasoningControl {
    return inferReasoningControl(this.provider, this.effectiveModelId(), true);
  }

  private formatOptionalNumber(val?: number): string {
    if (val === undefined || !Number.isFinite(val)) {
      return '';
    }
    return String(val);
  }

  private loadFromSpec(raw: ModelSpec): void {
    this.editTab = 0;
    this.modelIdInput = raw.id || '';
    this.displayNameInput = raw.displayName || raw.id || '';
    this.modelKindType = raw.modelType || 'chat';

    if (raw.inputModalities && raw.inputModalities.length > 0) {
      this.inputMods = raw.inputModalities.slice();
    } else {
      this.inputMods = raw.vision ? ['text', 'image'] : ['text'];
    }

    if (raw.outputModalities && raw.outputModalities.length > 0) {
      this.outputMods = raw.outputModalities.slice();
    } else {
      this.outputMods = raw.imageGen ? ['text', 'image'] : ['text'];
    }

    this.toolsCap = raw.tools;
    this.reasoningCap = raw.reasoning;
    this.structuredCap = !!raw.structuredOutput;
    this.contextWindowText = raw.contextWindow > 0 ? String(raw.contextWindow) : '128000';
    this.maxOutputText = raw.maxOutputTokens > 0 ? String(raw.maxOutputTokens) : '8192';

    const pricing = raw.pricing;
    this.priceInputText = this.formatOptionalNumber(pricing?.inputPerMillion);
    this.priceOutputText = this.formatOptionalNumber(pricing?.outputPerMillion);
    this.priceCacheReadText = this.formatOptionalNumber(pricing?.cacheReadPerMillion);
    this.priceCacheWriteText = this.formatOptionalNumber(pricing?.cacheWritePerMillion);
    this.priceCurrency = (pricing?.currency && pricing.currency.trim()) ? pricing.currency.trim() : 'USD';

    const baseCtrl = inferReasoningControl(this.provider, raw.id || '', true);
    this.dialectOverride = raw.reasoningDialect || 'auto';

    if (raw.reasoningLevels !== undefined) {
      this.levelsCustomized = true;
      this.selectedLevels = REASONING_NON_OFF_ORDER.filter(
        (lv: ReasoningEffort): boolean => raw.reasoningLevels!.includes(lv)
      );
    } else {
      this.levelsCustomized = false;
      const inferredNonOff = baseCtrl.levels.filter((lv: ReasoningEffort): boolean => lv !== 'off');
      this.selectedLevels = inferredNonOff.length > 0 ? inferredNonOff : ['low', 'medium', 'high'];
    }

    if (raw.reasoningAllowOff !== undefined) {
      this.allowOffCustomized = true;
      this.allowOffFlag = raw.reasoningAllowOff;
    } else {
      this.allowOffCustomized = false;
      this.allowOffFlag = baseCtrl.levels.includes('off');
    }

    this.defaultLevelChoice = raw.reasoningDefaultLevel || 'auto';
    this.samplingChoice = raw.samplingPolicy || 'default';
    this.replayChoice = raw.reasoningReplay || 'default';
    this.replayFieldChoice = raw.reasoningReplayField || 'default';

    this.customHeadersList = raw.customHeaders
      ? raw.customHeaders.map((h: HeaderEntry): HeaderEntry => { return { key: h.key, value: h.value }; })
      : [];
    this.customBodyList = raw.customBodyEntries
      ? raw.customBodyEntries.map((h: HeaderEntry): HeaderEntry => { return { key: h.key, value: h.value }; })
      : [];
    this.showHeaderAdd = false;
    this.headerKeyInput = '';
    this.headerValInput = '';
    this.showBodyAdd = false;
    this.bodyKeyInput = '';
    this.bodyValInput = '';

    this.remoteImagesCustomized = raw.allowRemoteImageUrls !== undefined;
    this.allowRemoteImages = raw.allowRemoteImageUrls !== undefined ? raw.allowRemoteImageUrls : true;

    this.toolCodeInterpreter = !!raw.builtinCodeInterpreter;
    this.toolImageGen = !!raw.builtinImageGen;
    this.toolUrlContext = !!raw.builtinUrlContext;
    this.toolCodeExec = !!raw.builtinCodeExec;
    this.toolYoutube = !!raw.builtinYoutube;
    this.toolWebFetch = !!raw.builtinWebFetch;
    this.toolShell = !!raw.builtinShell;

    this.errorTip = '';
    this.listRev += 1;
  }

  private showToastTip(msg: string): void {
    try {
      this.getUIContext().getPromptAction().showToast(
        ImmersiveMaterialStyle.toastOptions(msg, this.immersiveLightEnabled)
      );
    } catch (_) {}
  }

  private copyModelId(): void {
    const text = this.effectiveModelId();
    if (!text) {
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      pasteboard.getSystemPasteboard().setDataSync(data);
      this.showToastTip('已复制模型 ID');
    } catch (_) {
      this.showToastTip('复制失败');
    }
  }

  private toggleInputModality(mod: ModelModality): void {
    if (this.inputMods.includes(mod)) {
      const next = this.inputMods.filter((m: ModelModality): boolean => m !== mod);
      this.inputMods = next.length > 0 ? next : ['text'];
    } else {
      const ordered: ModelModality[] = ['text', 'image', 'audio', 'video', 'pdf'];
      const merged = [...this.inputMods, mod];
      this.inputMods = ordered.filter((m: ModelModality): boolean => merged.includes(m));
    }
  }

  private toggleOutputModality(mod: ModelOutputModality): void {
    if (this.outputMods.includes(mod)) {
      const next = this.outputMods.filter((m: ModelOutputModality): boolean => m !== mod);
      this.outputMods = next.length > 0 ? next : ['text'];
    } else {
      const ordered: ModelOutputModality[] = ['text', 'image', 'audio'];
      const merged = [...this.outputMods, mod];
      this.outputMods = ordered.filter((m: ModelOutputModality): boolean => merged.includes(m));
    }
  }

  private toggleReasoningLevel(lv: ReasoningEffort): void {
    this.levelsCustomized = true;
    if (this.selectedLevels.includes(lv)) {
      this.selectedLevels = this.selectedLevels.filter((x: ReasoningEffort): boolean => x !== lv);
    } else {
      const merged = [...this.selectedLevels, lv];
      this.selectedLevels = REASONING_NON_OFF_ORDER.filter((x: ReasoningEffort): boolean => merged.includes(x));
    }
  }

  private resetReasoningDefaults(): void {
    const baseCtrl = this.inferredControl();
    this.dialectOverride = 'auto';
    this.levelsCustomized = false;
    const inferredNonOff = baseCtrl.levels.filter((lv: ReasoningEffort): boolean => lv !== 'off');
    this.selectedLevels = inferredNonOff.length > 0 ? inferredNonOff : ['low', 'medium', 'high'];
    this.allowOffCustomized = false;
    this.allowOffFlag = baseCtrl.levels.includes('off');
    this.defaultLevelChoice = 'auto';
    this.samplingChoice = 'default';
    this.replayChoice = 'default';
    this.replayFieldChoice = 'default';
  }

  private resetAllToInferred(): void {
    this.resetReasoningDefaults();
    this.customHeadersList = [];
    this.customBodyList = [];
    this.showHeaderAdd = false;
    this.showBodyAdd = false;
    this.headerKeyInput = '';
    this.headerValInput = '';
    this.bodyKeyInput = '';
    this.bodyValInput = '';
    this.remoteImagesCustomized = false;
    this.allowRemoteImages = true;
    this.toolCodeInterpreter = false;
    this.toolImageGen = false;
    this.toolUrlContext = false;
    this.toolCodeExec = false;
    this.toolYoutube = false;
    this.toolWebFetch = false;
    this.toolShell = false;
    this.listRev += 1;
    this.showToastTip('已恢复全部高级与推理默认设置');
  }

  private parseOptionalFloat(raw: string): number | undefined {
    const trimmed = raw.trim();
    if (!trimmed) {
      return undefined;
    }
    const n = Number(trimmed);
    return Number.isFinite(n) && n >= 0 ? n : undefined;
  }

  private parsePositiveInt(raw: string, fallback: number): number {
    const trimmed = raw.trim();
    if (!trimmed) {
      return fallback;
    }
    const n = Math.round(Number(trimmed));
    return Number.isFinite(n) && n > 0 ? n : fallback;
  }

  private buildPricingSpec(): ModelPricingSpec | undefined {
    const inputP = this.parseOptionalFloat(this.priceInputText);
    const outputP = this.parseOptionalFloat(this.priceOutputText);
    const cacheReadP = this.parseOptionalFloat(this.priceCacheReadText);
    const cacheWriteP = this.parseOptionalFloat(this.priceCacheWriteText);
    const cur = this.priceCurrency.trim() || 'USD';
    if (
      inputP === undefined &&
      outputP === undefined &&
      cacheReadP === undefined &&
      cacheWriteP === undefined &&
      cur === 'USD'
    ) {
      return undefined;
    }
    return {
      inputPerMillion: inputP,
      outputPerMillion: outputP,
      cacheReadPerMillion: cacheReadP,
      cacheWritePerMillion: cacheWriteP,
      currency: cur
    };
  }

  private hasCustomBuiltinTools(): boolean {
    return this.toolCodeInterpreter ||
      this.toolImageGen ||
      this.toolUrlContext ||
      this.toolCodeExec ||
      this.toolYoutube ||
      this.toolWebFetch ||
      this.toolShell;
  }

  public submitModel(): void {
    const cleanId = this.modelIdInput.trim();
    if (!cleanId) {
      this.editTab = 0;
      this.errorTip = '模型 ID 不能为空';
      return;
    }
    const baseSpec = defaultModelSpec(cleanId);
    const hasCustomBasic = !this.isNew &&
      this.initialSpec.id === cleanId &&
      this.initialSpec.contextWindow > 0;
    const defaultCtx = hasCustomBasic ? this.initialSpec.contextWindow : (baseSpec.contextWindow || 128000);
    const defaultOut = hasCustomBasic ? this.initialSpec.maxOutputTokens : (baseSpec.maxOutputTokens || 8192);

    const outSpec: ModelSpec = {
      id: cleanId,
      displayName: this.displayNameInput.trim() || cleanId,
      groupName: this.initialSpec.groupName,
      modelType: this.modelKindType,
      inputModalities: this.inputMods.slice(),
      outputModalities: this.outputMods.slice(),
      vision: this.inputMods.includes('image'),
      tools: this.toolsCap,
      reasoning: this.reasoningCap,
      imageGen: this.outputMods.includes('image'),
      structuredOutput: this.structuredCap,
      contextWindow: this.parsePositiveInt(this.contextWindowText, defaultCtx),
      maxOutputTokens: this.parsePositiveInt(this.maxOutputText, defaultOut),
      enabled: this.initialSpec.enabled !== undefined ? this.initialSpec.enabled : true,
      pricing: this.buildPricingSpec(),
      reasoningDialect: this.dialectOverride !== 'auto' ? this.dialectOverride : undefined,
      reasoningLevels: this.levelsCustomized ? this.selectedLevels.slice() : undefined,
      reasoningAllowOff: this.allowOffCustomized ? this.allowOffFlag : undefined,
      reasoningDefaultLevel: this.defaultLevelChoice !== 'auto' ? this.defaultLevelChoice : undefined,
      samplingPolicy: this.samplingChoice !== 'default' ? this.samplingChoice : undefined,
      reasoningReplay: this.replayChoice !== 'default' ? this.replayChoice : undefined,
      reasoningReplayField: this.replayFieldChoice !== 'default' ? this.replayFieldChoice : undefined,
      customHeaders: this.customHeadersList.length > 0
        ? this.customHeadersList.map((h: HeaderEntry): HeaderEntry => { return { key: h.key, value: h.value }; })
        : undefined,
      customBodyEntries: this.customBodyList.length > 0
        ? this.customBodyList.map((h: HeaderEntry): HeaderEntry => { return { key: h.key, value: h.value }; })
        : undefined,
      allowRemoteImageUrls: this.remoteImagesCustomized ? this.allowRemoteImages : undefined,
      builtinSearch: this.initialSpec.builtinSearch,
      claudeDynamicSearch: this.initialSpec.claudeDynamicSearch,
      builtinCodeInterpreter: this.toolCodeInterpreter ? true : undefined,
      builtinImageGen: this.toolImageGen ? true : undefined,
      builtinUrlContext: this.toolUrlContext ? true : undefined,
      builtinCodeExec: this.toolCodeExec ? true : undefined,
      builtinYoutube: this.toolYoutube ? true : undefined,
      builtinWebFetch: this.toolWebFetch ? true : undefined,
      builtinShell: this.toolShell ? true : undefined
    };

    this.errorTip = '';
    this.onSave(outSpec);
  }

  private dialectTitle(d: ModelReasoningDialectOverride): string {
    const resolved = d === 'auto' ? this.inferredControl().dialect : d;
    switch (resolved) {
      case 'effort':
        return 'Reasoning effort';
      case 'router':
        return 'OpenRouter reasoning';
      case 'budgetFlag':
        return 'Thinking budget';
      case 'thinkingType':
        return 'Thinking type';
      case 'kimi':
        return 'Kimi thinking';
      case 'intern':
        return 'Thinking mode';
      case 'claudeBudget':
        return 'Claude thinking';
      case 'adaptive':
        return 'Adaptive thinking';
      case 'geminiBudget':
        return 'Gemini thinking budget';
      case 'geminiLevel':
        return 'Gemini thinking level';
      case 'fixed':
        return '固定深度思考';
      default:
        return 'Reasoning effort';
    }
  }

  private dialectSubtitle(d: ModelReasoningDialectOverride): string {
    const resolved = d === 'auto' ? this.inferredControl().dialect : d;
    switch (resolved) {
      case 'effort':
        return 'reasoning_effort / reasoning.effort';
      case 'router':
        return 'reasoning.effort (OpenRouter)';
      case 'budgetFlag':
        return 'enable_thinking + thinking_budget';
      case 'thinkingType':
        return 'thinking.type';
      case 'kimi':
        return 'thinking.type (Moonshot/Kimi)';
      case 'intern':
        return 'thinking_mode';
      case 'claudeBudget':
        return 'thinking.budget_tokens';
      case 'adaptive':
        return 'thinking.type = adaptive';
      case 'geminiBudget':
        return 'thinkingConfig.thinkingBudget';
      case 'geminiLevel':
        return 'thinkingConfig.thinkingLevel';
      case 'fixed':
        return '模型不支持外部调节档位';
      default:
        return 'reasoning_effort';
    }
  }

  private effortLabel(lv: 'auto' | ReasoningEffort): string {
    switch (lv) {
      case 'auto':
        return '自动';
      case 'off':
        return '关闭';
      case 'minimal':
        return '最低';
      case 'low':
        return '低';
      case 'medium':
        return '中';
      case 'high':
        return '高';
      case 'xhigh':
        return '极高';
      case 'max':
        return '最大';
      default:
        return String(lv);
    }
  }

  private samplingTitle(choice: 'default' | ModelSamplingPolicy): string {
    switch (choice) {
      case 'always':
        return '始终保留';
      case 'only_when_reasoning_off':
        return '仅推理关闭时保留';
      case 'never':
        return '始终省略';
      default:
        return '遵循推断规则';
    }
  }

  private samplingSubtitle(choice: 'default' | ModelSamplingPolicy): string {
    switch (choice) {
      case 'always':
        return '保留 temperature 等采样字段';
      case 'only_when_reasoning_off':
        return '开启思考时省略 temperature / top_p';
      case 'never':
        return '不发送 temperature / top_p 字段';
      default:
        return '保留 temperature 等默认兼容策略';
    }
  }

  private replayTitle(choice: 'default' | ModelReasoningReplayPolicy): string {
    switch (choice) {
      case 'none':
        return '不回放';
      case 'tool_turns':
        return '仅工具调用轮次';
      case 'all':
        return '全部';
      default:
        return '自动推断';
    }
  }

  private replaySubtitle(choice: 'default' | ModelReasoningReplayPolicy): string {
    switch (choice) {
      case 'none':
        return '后续请求不回放历史思考文本';
      case 'tool_turns':
        return '仅在多步工具调用间回放 reasoning';
      case 'all':
        return '每一轮后续请求都回放推理';
      default:
        return '按服务商及当前协议自动决定是否回放';
    }
  }

  private replayFieldTitle(choice: 'default' | ModelReasoningReplayField): string {
    return choice === 'default' ? 'reasoning_content (默认)' : choice;
  }

  private dialectMenuElements(): Array<MenuElement> {
    const items: Array<MenuElement> = [
      {
        value: '自动推断 (' + this.dialectTitle('auto') + ')',
        action: () => { this.dialectOverride = 'auto'; }
      }
    ];
    const dialects: ModelReasoningDialectOverride[] = [
      'effort',
      'router',
      'budgetFlag',
      'thinkingType',
      'kimi',
      'intern',
      'claudeBudget',
      'adaptive',
      'geminiBudget',
      'geminiLevel',
      'fixed'
    ];
    for (let i = 0; i < dialects.length; i++) {
      const d = dialects[i];
      items.push({
        value: this.dialectTitle(d) + ' · ' + this.dialectSubtitle(d),
        action: () => { this.dialectOverride = d; }
      });
    }
    return items;
  }

  private defaultLevelMenuElements(): Array<MenuElement> {
    const items: Array<MenuElement> = [
      { value: '自动 (跟随对话设置)', action: () => { this.defaultLevelChoice = 'auto'; } }
    ];
    if (this.allowOffFlag) {
      items.push({ value: '关闭', action: () => { this.defaultLevelChoice = 'off'; } });
    }
    for (let i = 0; i < REASONING_NON_OFF_ORDER.length; i++) {
      const lv = REASONING_NON_OFF_ORDER[i];
      items.push({
        value: this.effortLabel(lv),
        action: () => { this.defaultLevelChoice = lv; }
      });
    }
    return items;
  }

  private samplingMenuElements(): Array<MenuElement> {
    return [
      { value: '遵循推断规则 (默认)', action: () => { this.samplingChoice = 'default'; } },
      { value: '始终保留 (temperature/top_p)', action: () => { this.samplingChoice = 'always'; } },
      { value: '仅推理关闭时保留', action: () => { this.samplingChoice = 'only_when_reasoning_off'; } },
      { value: '始终省略', action: () => { this.samplingChoice = 'never'; } }
    ];
  }

  private replayMenuElements(): Array<MenuElement> {
    return [
      { value: '自动推断 (默认)', action: () => { this.replayChoice = 'default'; } },
      { value: '全部 (每一轮都回放推理)', action: () => { this.replayChoice = 'all'; } },
      { value: '仅工具调用轮次', action: () => { this.replayChoice = 'tool_turns'; } },
      { value: '不回放', action: () => { this.replayChoice = 'none'; } }
    ];
  }

  private replayFieldMenuElements(): Array<MenuElement> {
    return [
      { value: '默认 (reasoning_content)', action: () => { this.replayFieldChoice = 'default'; } },
      { value: 'reasoning_content', action: () => { this.replayFieldChoice = 'reasoning_content'; } },
      { value: 'reasoning', action: () => { this.replayFieldChoice = 'reasoning'; } },
      { value: 'reasoning_details', action: () => { this.replayFieldChoice = 'reasoning_details'; } }
    ];
  }

  private addCustomHeader(): void {
    const k = this.headerKeyInput.trim();
    if (!k) {
      return;
    }
    const next = this.customHeadersList.slice();
    const existIdx = next.findIndex((h: HeaderEntry): boolean => h.key.trim().toLowerCase() === k.toLowerCase());
    if (existIdx >= 0) {
      next[existIdx] = { key: k, value: this.headerValInput };
    } else {
      next.push({ key: k, value: this.headerValInput });
    }
    this.customHeadersList = next;
    this.headerKeyInput = '';
    this.headerValInput = '';
    this.showHeaderAdd = false;
    this.listRev += 1;
  }

  private removeCustomHeader(idx: number): void {
    this.customHeadersList = this.customHeadersList.filter((_h: HeaderEntry, i: number): boolean => i !== idx);
    this.listRev += 1;
  }

  private addCustomBodyEntry(): void {
    const k = this.bodyKeyInput.trim();
    if (!k) {
      return;
    }
    const next = this.customBodyList.slice();
    const existIdx = next.findIndex((h: HeaderEntry): boolean => h.key.trim().toLowerCase() === k.toLowerCase());
    if (existIdx >= 0) {
      next[existIdx] = { key: k, value: this.bodyValInput };
    } else {
      next.push({ key: k, value: this.bodyValInput });
    }
    this.customBodyList = next;
    this.bodyKeyInput = '';
    this.bodyValInput = '';
    this.showBodyAdd = false;
    this.listRev += 1;
  }

  private removeCustomBodyEntry(idx: number): void {
    this.customBodyList = this.customBodyList.filter((_h: HeaderEntry, i: number): boolean => i !== idx);
    this.listRev += 1;
  }

  private isGeminiProvider(): boolean {
    return this.provider.family === 'gemini' || this.provider.family === 'vertex';
  }

  private isAnthropicToolsProvider(): boolean {
    return this.provider.family === 'anthropic' && !isDeepSeekProvider(this.provider);
  }

  private isOpenRouterToolsProvider(): boolean {
    return isOpenRouterProvider(this.provider);
  }

  private isOpenAiToolsProvider(): boolean {
    return (this.provider.family === 'openai' || this.provider.family === 'openai-responses') &&
      !this.isOpenRouterToolsProvider();
  }

  @Builder
  private statusBadge(defaultLabel: string, customized: boolean) {
    Text(customized ? '自定义' : defaultLabel)
      .fontSize(11)
      .fontWeight(FontWeight.Medium)
      .fontColor(customized ? $r('app.color.accent') : $r('app.color.muted'))
      .backgroundColor(customized ? $r('app.color.tint') : $r('app.color.panel'))
      .padding({ left: 8, right: 8, top: 3, bottom: 3 })
      .borderRadius(999)
  }

  @Builder
  private labelWithBadge(title: string, defaultLabel: string, customized: boolean) {
    Row() {
      Text(title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ink'))
        .layoutWeight(1)
      this.statusBadge(defaultLabel, customized)
    }
    .width('100%')
  }

  @Builder
  private checkCircleRow(label: string, checked: boolean, onTap: () => void) {
    Row({ space: 12 }) {
      if (checked) {
        SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
          .fontSize(20)
          .fontColor([$r('app.color.accent')])
      } else {
        Column()
          .width(18)
          .height(18)
          .margin({ left: 1, right: 1 })
          .borderRadius(9)
          .border({ width: 1.5, color: $r('app.color.muted') })
          .backgroundColor(Color.Transparent)
      }
      Text(label)
        .fontSize(14)
        .fontColor($r('app.color.ink'))
        .layoutWeight(1)
    }
    .width('100%')
    .height(34)
    .padding({ left: 4, right: 4 })
    .borderRadius(8)
    .onClick(() => { onTap(); })
  }

  @Builder
  private segmentedTabButton(label: string, idx: number) {
    Button(label, { buttonStyle: ButtonStyleMode.TEXTUAL })
      .layoutWeight(1)
      .height(34)
      .fontSize(13)
      .fontWeight(this.editTab === idx ? FontWeight.Medium : FontWeight.Normal)
      .borderRadius(13)
      .backgroundColor(
        ImmersiveMaterialStyle.isActive(this.immersiveLightEnabled)
          ? (this.editTab === idx ? hexWithAlpha(this.themeAccentHex, this.isDark ? '48' : '24') : Color.Transparent)
          : (this.editTab === idx ? $r('app.color.tint') : Color.Transparent)
      )
      .fontColor(
        ImmersiveMaterialStyle.isActive(this.immersiveLightEnabled)
          ? (this.editTab === idx ? $r('sys.color.font_primary') : $r('sys.color.font_secondary'))
          : (this.editTab === idx ? $r('app.color.accent') : $r('app.color.muted'))
      )
      .onClick(() => {
        this.editTab = idx;
        try {
          this.editorScroller.scrollTo({ xOffset: 0, yOffset: 0 });
        } catch (_) {}
      })
  }

  @Builder
  private modelTitleBar() {
    Column({ space: 0 }) {
      Row() {
        KelivoNavTitleBar({
          titleText: this.isNew ? '添加模型' : '编辑模型',
          subtitleText: this.provider.name || '',
          showBack: true,
          rightPrimary: true,
          rightSymbol: $r('sys.symbol.checkmark'),
          onBack: () => { this.onCancel(); },
          onRightAction: () => { this.submitModel(); }
        })
      }
      .width('100%')
      .height(56 + this.winTopInset)
      .clip(false)

      Row() {
        Row({ space: 4 }) {
          this.segmentedTabButton('基本设置', 0)
          this.segmentedTabButton('推理', 1)
          this.segmentedTabButton('高级设置', 2)
        }
        .width('100%')
        .height(40)
        .padding(3)
        .borderRadius(16)
        .backgroundColor(ImmersiveMaterialStyle.headerActionBackground(
          this.themeSurfaceHex, this.themeTintHex, this.immersiveLightEnabled, false
        ))
        .systemMaterial(ImmersiveMaterialStyle.titleCapsuleMaterial(
          this.themeSurfaceHex, this.themeAccentHex, this.isDark, this.immersiveLightEnabled
        ))
      }
      .width('100%')
      .height(48)
      .padding({
        left: 16 + this.winLeftInset,
        right: 16 + this.winRightInset,
        top: 2,
        bottom: 6
      })
      .clip(false)
    }
    .width('100%')
    .height('100%')
    .clip(false)
  }

  @Builder
  private kindSegmentButton(label: string, kind: ModelKindType) {
    Button(label)
      .layoutWeight(1)
      .height(34)
      .fontSize(13)
      .fontWeight(this.modelKindType === kind ? FontWeight.Medium : FontWeight.Normal)
      .borderRadius(12)
      .backgroundColor(this.modelKindType === kind ? $r('app.color.tint') : Color.Transparent)
      .fontColor(this.modelKindType === kind ? $r('app.color.accent') : $r('app.color.muted'))
      .onClick(() => { this.modelKindType = kind; })
  }

  @Builder
  private numericFieldRow(label: string, fieldText: string, placeholder: string, onEdit: (v: string) => void) {
    Row({ space: 12 }) {
      Text(label)
        .fontSize(14)
        .fontColor($r('app.color.ink'))
        .width(104)
      TextInput({ text: fieldText, placeholder: placeholder })
        .layoutWeight(1)
        .height(40)
        .fontSize(14)
        .textAlign(TextAlign.End)
        .borderRadius(12)
        .backgroundColor($r('app.color.panel'))
        .onChange((v: string) => { onEdit(v); })
    }
    .width('100%')
  }

  @Builder
  private pickerRow(
    title: string,
    defaultBadge: string,
    customized: boolean,
    selectedTitle: string,
    selectedSub: string,
    menuItems: Array<MenuElement>
  ) {
    Column({ space: 8 }) {
      this.labelWithBadge(title, defaultBadge, customized)
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text(selectedTitle)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
          if (selectedSub.length > 0) {
            Text(selectedSub)
              .fontSize(12)
              .fontColor($r('app.color.muted'))
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('app.color.muted')])
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .borderRadius(12)
      .backgroundColor($r('app.color.panel'))
      .bindMenu(menuItems, ImmersiveMaterialStyle.menuOptions(this.immersiveLightEnabled))
    }
    .width('100%')
  }

  @Builder
  private builtinToolSwitchCard(title: string, desc: string, isOn: boolean, onToggle: (v: boolean) => void) {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
        Text(desc)
          .fontSize(12)
          .fontColor($r('app.color.muted'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor($r('app.color.accent'))
        .onChange((v: boolean) => {
          if (v !== isOn) {
            onToggle(v);
          }
        })
        .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
    }
    .width('100%')
    .padding(12)
    .borderRadius(14)
    .backgroundColor($r('app.color.panel'))
  }

  @Builder
  private basicTab() {
    Column({ space: 12 }) {
      KelivoSectionHeader({ titleText: '基本设置', topSpacing: 4 })

      Column({ space: 14 }) {
        Column({ space: 8 }) {
          this.labelWithBadge('模型 ID', '默认', this.isNew && this.modelIdInput.trim().length > 0)
          Row({ space: 8 }) {
            if (this.isNew) {
              TextInput({ text: this.modelIdInput, placeholder: '输入模型 ID，如 gpt-4.1 / deepseek-chat' })
                .layoutWeight(1)
                .height(42)
                .borderRadius(12)
                .backgroundColor($r('app.color.panel'))
                .onChange((v: string) => {
                  this.modelIdInput = v;
                  this.errorTip = '';
                })
            } else {
              Text(this.modelIdInput)
                .layoutWeight(1)
                .fontSize(14)
                .fontColor($r('app.color.muted'))
                .padding({ left: 14, right: 14, top: 11, bottom: 11 })
                .borderRadius(12)
                .backgroundColor($r('app.color.panel'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
              SymbolGlyph($r('sys.symbol.rectangle_on_rectangle'))
                .fontSize(17)
                .fontColor([$r('app.color.ink')])
            }
            .width(38)
            .height(38)
            .backgroundColor(Color.Transparent)
            .accessibilityText('复制模型 ID')
            .onClick(() => { this.copyModelId(); })
          }
          .width('100%')
        }
        .width('100%')

        Column({ space: 8 }) {
          this.labelWithBadge(
            '模型名称',
            '默认',
            this.displayNameInput.trim().length > 0 && this.displayNameInput.trim() !== this.modelIdInput.trim()
          )
          TextInput({ text: this.displayNameInput, placeholder: '显示名称（留空默认使用模型 ID）' })
            .width('100%')
            .height(42)
            .borderRadius(12)
            .backgroundColor($r('app.color.panel'))
            .onChange((v: string) => { this.displayNameInput = v; })
        }
        .width('100%')

        Column({ space: 8 }) {
          this.labelWithBadge('模型类型', '目录', this.modelKindType !== 'chat')
          Row({ space: 4 }) {
            this.kindSegmentButton('聊天', 'chat')
            this.kindSegmentButton('嵌入', 'embedding')
            this.kindSegmentButton('图像', 'image')
          }
          .width('100%')
          .padding(4)
          .borderRadius(14)
          .backgroundColor($r('app.color.panel'))
        }
        .width('100%')
      }
      .width('100%')
      .padding(14)
      .borderRadius(18)
      .backgroundColor($r('app.color.surface'))

      KelivoSectionHeader({ titleText: '输入模式', topSpacing: 4 })

      Column({ space: 14 }) {
        Column({ space: 6 }) {
          this.labelWithBadge('输入模式', '目录', this.inputMods.length > 1 || this.inputMods[0] !== 'text')
          this.checkCircleRow('文本', this.inputMods.includes('text'), () => { this.toggleInputModality('text'); })
          this.checkCircleRow('图片', this.inputMods.includes('image'), () => { this.toggleInputModality('image'); })
          this.checkCircleRow('音频', this.inputMods.includes('audio'), () => { this.toggleInputModality('audio'); })
          this.checkCircleRow('视频', this.inputMods.includes('video'), () => { this.toggleInputModality('video'); })
          this.checkCircleRow('PDF', this.inputMods.includes('pdf'), () => { this.toggleInputModality('pdf'); })
        }
        .width('100%')

        Divider().color($r('app.color.line'))

        Column({ space: 6 }) {
          this.labelWithBadge('输出模式', '目录', this.outputMods.length > 1 || this.outputMods[0] !== 'text')
          this.checkCircleRow('文本', this.outputMods.includes('text'), () => { this.toggleOutputModality('text'); })
          this.checkCircleRow('图片', this.outputMods.includes('image'), () => { this.toggleOutputModality('image'); })
          this.checkCircleRow('音频', this.outputMods.includes('audio'), () => { this.toggleOutputModality('audio'); })
        }
        .width('100%')

        Divider().color($r('app.color.line'))

        Column({ space: 6 }) {
          this.labelWithBadge('能力', '目录', this.structuredCap)
          this.checkCircleRow('工具', this.toolsCap, () => { this.toolsCap = !this.toolsCap; })
          this.checkCircleRow('推理', this.reasoningCap, () => { this.reasoningCap = !this.reasoningCap; })
          this.checkCircleRow('结构化输出', this.structuredCap, () => { this.structuredCap = !this.structuredCap; })
        }
        .width('100%')
      }
      .width('100%')
      .padding(14)
      .borderRadius(18)
      .backgroundColor($r('app.color.surface'))

      KelivoSectionHeader({ titleText: '限额', topSpacing: 4 })

      Column({ space: 12 }) {
        this.labelWithBadge('限额', '目录', false)
        this.numericFieldRow('上下文窗口', this.contextWindowText, '128000', (v: string) => { this.contextWindowText = v; })
        this.numericFieldRow('最大输出', this.maxOutputText, '8192', (v: string) => { this.maxOutputText = v; })

        Divider().color($r('app.color.line'))

        this.labelWithBadge(
          '定价 / 1M',
          '目录',
          !!(this.priceInputText.trim() || this.priceOutputText.trim() || this.priceCacheReadText.trim() || this.priceCacheWriteText.trim())
        )
        this.numericFieldRow('输入', this.priceInputText, '0.00', (v: string) => { this.priceInputText = v; })
        this.numericFieldRow('输出', this.priceOutputText, '0.00', (v: string) => { this.priceOutputText = v; })
        this.numericFieldRow('缓存读取', this.priceCacheReadText, '可选', (v: string) => { this.priceCacheReadText = v; })
        this.numericFieldRow('缓存写入', this.priceCacheWriteText, '可选', (v: string) => { this.priceCacheWriteText = v; })
        this.numericFieldRow('货币', this.priceCurrency, 'USD', (v: string) => { this.priceCurrency = v; })
      }
      .width('100%')
      .padding(14)
      .borderRadius(18)
      .backgroundColor($r('app.color.surface'))
    }
    .width('100%')
  }

  @Builder
  private reasoningTab() {
    Column({ space: 12 }) {
      KelivoSectionHeader({ titleText: '推理', topSpacing: 4 })

      Column({ space: 14 }) {
        this.pickerRow(
          '推理方言',
          '推断',
          this.dialectOverride !== 'auto',
          this.dialectTitle(this.dialectOverride),
          this.dialectSubtitle(this.dialectOverride),
          this.dialectMenuElements()
        )

        Divider().color($r('app.color.line'))

        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Text('支持的级别')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))
              .layoutWeight(1)
            if (this.levelsCustomized) {
              Button('恢复默认')
                .height(24)
                .fontSize(11)
                .backgroundColor(Color.Transparent)
                .fontColor($r('app.color.accent'))
                .onClick(() => {
                  const baseLevels = this.inferredControl().levels.filter((lv: ReasoningEffort): boolean => lv !== 'off');
                  this.selectedLevels = baseLevels.length > 0 ? baseLevels : ['low', 'medium', 'high'];
                  this.levelsCustomized = false;
                })
            }
            this.statusBadge('目录', this.levelsCustomized)
          }
          .width('100%')

          this.checkCircleRow('最低', this.selectedLevels.includes('minimal'), () => { this.toggleReasoningLevel('minimal'); })
          this.checkCircleRow('低', this.selectedLevels.includes('low'), () => { this.toggleReasoningLevel('low'); })
          this.checkCircleRow('中', this.selectedLevels.includes('medium'), () => { this.toggleReasoningLevel('medium'); })
          this.checkCircleRow('高', this.selectedLevels.includes('high'), () => { this.toggleReasoningLevel('high'); })
          this.checkCircleRow('极高', this.selectedLevels.includes('xhigh'), () => { this.toggleReasoningLevel('xhigh'); })
          this.checkCircleRow('最大', this.selectedLevels.includes('max'), () => { this.toggleReasoningLevel('max'); })
        }
        .width('100%')

        Divider().color($r('app.color.line'))

        Row({ space: 8 }) {
          Text('允许关闭')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
            .layoutWeight(1)
          this.statusBadge('目录', this.allowOffCustomized)
          Toggle({ type: ToggleType.Switch, isOn: this.allowOffFlag })
            .selectedColor($r('app.color.accent'))
            .onChange((v: boolean) => {
              if (v !== this.allowOffFlag) {
                this.allowOffFlag = v;
                this.allowOffCustomized = true;
              }
            })
            .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
        }
        .width('100%')

        Divider().color($r('app.color.line'))

        this.pickerRow(
          '默认级别',
          '推断',
          this.defaultLevelChoice !== 'auto',
          this.effortLabel(this.defaultLevelChoice),
          this.defaultLevelChoice === 'auto' ? '跟随当前对话思考开关与默认档位' : '未单独调整思考强度时默认使用该级别',
          this.defaultLevelMenuElements()
        )
      }
      .width('100%')
      .padding(14)
      .borderRadius(18)
      .backgroundColor($r('app.color.surface'))

      KelivoSectionHeader({ titleText: '策略', topSpacing: 4 })

      Column({ space: 14 }) {
        this.pickerRow(
          '采样',
          '默认',
          this.samplingChoice !== 'default',
          this.samplingTitle(this.samplingChoice),
          this.samplingSubtitle(this.samplingChoice),
          this.samplingMenuElements()
        )

        Divider().color($r('app.color.line'))

        this.pickerRow(
          '推理回放',
          '推断',
          this.replayChoice !== 'default',
          this.replayTitle(this.replayChoice),
          this.replaySubtitle(this.replayChoice),
          this.replayMenuElements()
        )

        Divider().color($r('app.color.line'))

        this.pickerRow(
          '回放字段',
          '推断',
          this.replayFieldChoice !== 'default',
          this.replayFieldTitle(this.replayFieldChoice),
          '',
          this.replayFieldMenuElements()
        )
      }
      .width('100%')
      .padding(14)
      .borderRadius(18)
      .backgroundColor($r('app.color.surface'))
    }
    .width('100%')
  }

  @Builder
  private advancedTab() {
    Column({ space: 12 }) {
      KelivoSectionHeader({ titleText: '请求', topSpacing: 4 })

      Column({ space: 14 }) {
        Column({ space: 8 }) {
          this.labelWithBadge('自定义 Headers', '默认', this.customHeadersList.length > 0)

          ForEach(this.customHeadersList, (hd: HeaderEntry, idx: number) => {
            Row({ space: 8 }) {
              Text(hd.key + ': ' + hd.value)
                .fontSize(13)
                .fontColor($r('app.color.ink'))
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(15)
                  .fontColor([$r('app.color.warning')])
              }
              .width(30)
              .height(30)
              .backgroundColor(Color.Transparent)
              .accessibilityText('删除 Header')
              .onClick(() => { this.removeCustomHeader(idx); })
            }
            .width('100%')
            .padding({ left: 12, right: 8, top: 8, bottom: 8 })
            .borderRadius(12)
            .backgroundColor($r('app.color.panel'))
          }, (hd: HeaderEntry, idx: number) => this.listRev + '-hd-' + idx + '-' + hd.key + '-' + hd.value)

          if (this.showHeaderAdd) {
            Column({ space: 8 }) {
              Row({ space: 8 }) {
                TextInput({ text: this.headerKeyInput, placeholder: 'Header 名称，如 X-Custom' })
                  .layoutWeight(1)
                  .height(38)
                  .borderRadius(10)
                  .backgroundColor($r('app.color.surface'))
                  .onChange((v: string) => { this.headerKeyInput = v; })
                TextInput({ text: this.headerValInput, placeholder: 'Header 值' })
                  .layoutWeight(1)
                  .height(38)
                  .borderRadius(10)
                  .backgroundColor($r('app.color.surface'))
                  .onChange((v: string) => { this.headerValInput = v; })
              }
              .width('100%')
              Row({ space: 8 }) {
                Button('取消')
                  .layoutWeight(1)
                  .height(34)
                  .fontSize(13)
                  .backgroundColor($r('app.color.surface'))
                  .fontColor($r('app.color.muted'))
                  .onClick(() => {
                    this.showHeaderAdd = false;
                    this.headerKeyInput = '';
                    this.headerValInput = '';
                  })
                Button('确认添加')
                  .layoutWeight(1)
                  .height(34)
                  .fontSize(13)
                  .backgroundColor($r('app.color.tint'))
                  .fontColor($r('app.color.accent'))
                  .onClick(() => { this.addCustomHeader(); })
              }
              .width('100%')
            }
            .width('100%')
            .padding(10)
            .borderRadius(12)
            .backgroundColor($r('app.color.panel'))
          } else {
            Button() {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.plus'))
                  .fontSize(15)
                  .fontColor([$r('app.color.ink')])
                Text('添加 Header')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.ink'))
              }
            }
            .width('100%')
            .height(42)
            .borderRadius(14)
            .backgroundColor($r('app.color.panel'))
            .onClick(() => { this.showHeaderAdd = true; })
          }
        }
        .width('100%')

        Divider().color($r('app.color.line'))

        Column({ space: 8 }) {
          this.labelWithBadge('自定义 Body', '默认', this.customBodyList.length > 0)

          ForEach(this.customBodyList, (bd: HeaderEntry, idx: number) => {
            Row({ space: 8 }) {
              Text(bd.key + ' = ' + bd.value)
                .fontSize(13)
                .fontColor($r('app.color.ink'))
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
                SymbolGlyph($r('sys.symbol.trash'))
                  .fontSize(15)
                  .fontColor([$r('app.color.warning')])
              }
              .width(30)
              .height(30)
              .backgroundColor(Color.Transparent)
              .accessibilityText('删除 Body 字段')
              .onClick(() => { this.removeCustomBodyEntry(idx); })
            }
            .width('100%')
            .padding({ left: 12, right: 8, top: 8, bottom: 8 })
            .borderRadius(12)
            .backgroundColor($r('app.color.panel'))
          }, (bd: HeaderEntry, idx: number) => this.listRev + '-bd-' + idx + '-' + bd.key + '-' + bd.value)

          if (this.showBodyAdd) {
            Column({ space: 8 }) {
              Row({ space: 8 }) {
                TextInput({ text: this.bodyKeyInput, placeholder: '字段名，如 seed / top_k' })
                  .layoutWeight(1)
                  .height(38)
                  .borderRadius(10)
                  .backgroundColor($r('app.color.surface'))
                  .onChange((v: string) => { this.bodyKeyInput = v; })
                TextInput({ text: this.bodyValInput, placeholder: 'JSON 值或文本' })
                  .layoutWeight(1)
                  .height(38)
                  .borderRadius(10)
                  .backgroundColor($r('app.color.surface'))
                  .onChange((v: string) => { this.bodyValInput = v; })
              }
              .width('100%')
              Row({ space: 8 }) {
                Button('取消')
                  .layoutWeight(1)
                  .height(34)
                  .fontSize(13)
                  .backgroundColor($r('app.color.surface'))
                  .fontColor($r('app.color.muted'))
                  .onClick(() => {
                    this.showBodyAdd = false;
                    this.bodyKeyInput = '';
                    this.bodyValInput = '';
                  })
                Button('确认添加')
                  .layoutWeight(1)
                  .height(34)
                  .fontSize(13)
                  .backgroundColor($r('app.color.tint'))
                  .fontColor($r('app.color.accent'))
                  .onClick(() => { this.addCustomBodyEntry(); })
              }
              .width('100%')
            }
            .width('100%')
            .padding(10)
            .borderRadius(12)
            .backgroundColor($r('app.color.panel'))
          } else {
            Button() {
              Row({ space: 6 }) {
                SymbolGlyph($r('sys.symbol.plus'))
                  .fontSize(15)
                  .fontColor([$r('app.color.ink')])
                Text('添加 Body')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.ink'))
              }
            }
            .width('100%')
            .height(42)
            .borderRadius(14)
            .backgroundColor($r('app.color.panel'))
            .onClick(() => { this.showBodyAdd = true; })
          }
        }
        .width('100%')

        Divider().color($r('app.color.line'))

        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Text('远程图片链接')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))
              .layoutWeight(1)
            this.statusBadge('推断', this.remoteImagesCustomized)
            Toggle({ type: ToggleType.Switch, isOn: this.allowRemoteImages })
              .selectedColor($r('app.color.accent'))
              .onChange((v: boolean) => {
                if (v !== this.allowRemoteImages) {
                  this.allowRemoteImages = v;
                  this.remoteImagesCustomized = true;
                }
              })
              .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
          }
          .width('100%')
          Text('直接发送 http(s) 图片链接；关闭后丢弃远程链接，只发送本地图片')
            .fontSize(12)
            .fontColor($r('app.color.muted'))
            .width('100%')
        }
        .width('100%')
      }
      .width('100%')
      .padding(14)
      .borderRadius(18)
      .backgroundColor($r('app.color.surface'))

      KelivoSectionHeader({ titleText: '内置工具', topSpacing: 4 })

      Column({ space: 10 }) {
        this.labelWithBadge('内置工具', '默认', this.hasCustomBuiltinTools())
        Text('内置工具取决于供应商和 API 模式。')
          .fontSize(12)
          .fontColor($r('app.color.muted'))
          .width('100%')

        if (this.isGeminiProvider()) {
          this.builtinToolSwitchCard('URL 上下文', '允许模型直接读取并分析网页链接内容', this.toolUrlContext, (v: boolean) => {
            this.toolUrlContext = v;
          })
          this.builtinToolSwitchCard('代码执行', '启用 Gemini 原生 Python 代码执行沙盒', this.toolCodeExec, (v: boolean) => {
            this.toolCodeExec = v;
          })
          this.builtinToolSwitchCard('YouTube', '允许直接分析提问中的 YouTube 视频内容', this.toolYoutube, (v: boolean) => {
            this.toolYoutube = v;
          })
        } else if (this.isAnthropicToolsProvider()) {
          this.builtinToolSwitchCard('网页抓取', '允许 Claude 抓取并读取网页正文', this.toolWebFetch, (v: boolean) => {
            this.toolWebFetch = v;
          })
          this.builtinToolSwitchCard('代码执行', '启用 Claude 官方代码执行沙盒工具', this.toolCodeExec, (v: boolean) => {
            this.toolCodeExec = v;
          })
        } else if (this.isOpenRouterToolsProvider()) {
          this.builtinToolSwitchCard('网页抓取', '启用 OpenRouter 网页内容抓取插件', this.toolWebFetch, (v: boolean) => {
            this.toolWebFetch = v;
          })
          this.builtinToolSwitchCard('图像生成', '启用 OpenRouter 原生图像生成工具', this.toolImageGen, (v: boolean) => {
            this.toolImageGen = v;
          })
          this.builtinToolSwitchCard('代码解释器', '启用代码解释器工具（容器自动，内存上限 4g）', this.toolCodeInterpreter, (v: boolean) => {
            this.toolCodeInterpreter = v;
          })
          this.builtinToolSwitchCard('Shell', '启用 OpenRouter Shell 执行工具（Responses 模式）', this.toolShell, (v: boolean) => {
            this.toolShell = v;
          })
        } else if (this.isOpenAiToolsProvider()) {
          this.builtinToolSwitchCard('代码解释器', '启用代码解释器工具（容器自动，内存上限 4g）', this.toolCodeInterpreter, (v: boolean) => {
            this.toolCodeInterpreter = v;
          })
          this.builtinToolSwitchCard('图像生成', '启用图像生成工具', this.toolImageGen, (v: boolean) => {
            this.toolImageGen = v;
          })
          if (!usesResponsesApi(this.provider)) {
            Text('提示：OpenAI 原生代码解释器与图像生成仅在使用 Responses API 时生效。')
              .fontSize(11)
              .fontColor($r('app.color.muted'))
              .width('100%')
          }
        } else {
          Text('当前服务商暂未声明额外的模型级内置工具开关。')
            .fontSize(12)
            .fontColor($r('app.color.muted'))
            .width('100%')
        }
      }
      .width('100%')
      .padding(14)
      .borderRadius(18)
      .backgroundColor($r('app.color.surface'))

      Button('恢复全部为默认推断')
        .width('100%')
        .height(42)
        .fontSize(14)
        .borderRadius(14)
        .backgroundColor($r('app.color.surface'))
        .fontColor($r('app.color.warning'))
        .onClick(() => { this.resetAllToInferred(); })
    }
    .width('100%')
  }

  build() {
    NavDestination() {
      Scroll(this.editorScroller) {
        Column({ space: 12 }) {
          if (this.errorTip.length > 0) {
            Text(this.errorTip)
              .fontSize(13)
              .fontColor($r('app.color.warning'))
              .width('100%')
              .padding({ left: 4, right: 4, bottom: 2 })
          }

          if (this.editTab === 0) {
            this.basicTab()
          } else if (this.editTab === 1) {
            this.reasoningTab()
          } else {
            this.advancedTab()
          }
        }
        .width('100%')
        .padding({
          left: 16 + this.winLeftInset,
          right: 16 + this.winRightInset,
          top: 104 + this.winTopInset + 8,
          bottom: Math.max(36, this.winBottomInset + 24)
        })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .hideBackButton(true)
    .backgroundColor(this.themeCanvasHex)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .title(
      { builder: () => { this.modelTitleBar(); }, height: 104 + this.winTopInset },
      ImmersiveMaterialStyle.titleBarOptions(this.immersiveLightEnabled, true)
    )
    .systemTransition(SystemMotion.navTransition(this.reduceMotion))
    .onShown(() => { this.onRouteShown(); })
    .onHidden(() => { this.onRouteHidden(); })
    .onBackPressed(() => this.onDismissOverlay())
  }
}
