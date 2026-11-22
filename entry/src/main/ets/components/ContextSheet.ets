import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { SystemMotion } from '../core/SystemMotion';
import { KelivoNavTitleBar } from './KelivoChrome';
import {
  ChatMessage,
  Conversation,
  GenerationParams,
  Provider,
  ReasoningEffort,
  ResponseSpeedMode,
  SystemSettings,
  defaultGenerationParams,
  estimateMessagesTokens,
  estimateTokens,
  findProviderModelSpec
} from '../core/Models';
import { sliceContextMessages } from '../core/ContextUtils';

@Component
export struct ContextSheet {
  @Prop chat?: Conversation = undefined;
  @Prop providers: Provider[] = [];
  @Prop activeProviderId: string = '';
  @Prop systemPrompt: string = '';
  @Prop params: GenerationParams = defaultGenerationParams();
  @Prop sysSettings: SystemSettings = {
    autoTitleEnabled: true,
    chatSuggestionsEnabled: true,
    autoCompactEnabled: false,
    autoCompactThreshold: 36,
    compressionTemplate: '',
    imageUploadQuality: 85,
    hapticsEnabled: true,
    keepScreenOn: true,
    backgroundNotifyEnabled: true,
    autoSnapshotEnabled: true,
    builtinFetchEnabled: true,
    maxToolSteps: 10,
    defaultToolPermission: 'ask',
    enabledDeviceTools: []
  };
  onSaveParams: (p: GenerationParams, autoCompact: boolean, threshold: number, template: string) => void = () => {};
  onSaveChatOverrides: (providerId: string, modelId: string, prompt: string, startIdx: number) => void = () => {};
  onCompressInPlace: (template: string) => Promise<void> = async () => {};
  onUndoCompress: () => void = () => {};
  onCompressToNewChat: (template: string) => Promise<void> = async () => {};
  onDismissOverlay: () => boolean = () => false;
  onClose: () => void = () => {};

  @StorageProp('immersiveLightEnabled') immersiveLightEnabled: boolean = true;
  @StorageProp('windowTopInsetVp') winTopInset: number = 0;
  @StorageProp('themeCanvasHex') themeCanvasHex: string = '#F7F7F7';
  @StorageProp('reduceMotionEnabled') reduceMotion: boolean = false;

  @State tempVal: number = 0.7;
  @State topPVal: number = 1.0;
  @State maxTokensVal: number = 4096;
  @State effortVal: ReasoningEffort = 'medium';
  @State budgetVal: number = 8192;
  @State speedVal: ResponseSpeedMode = 'standard';
  @State ctxLimitVal: number = 24;
  @State retryVal: number = 2;
  @State autoCompactVal: boolean = false;
  @State thresholdVal: number = 36;
  @State templateVal: string = '';
  @State chatProvId: string = '';
  @State chatModelVal: string = '';
  @State chatPromptVal: string = '';
  @State startIdxVal: number = 0;
  @State busy: boolean = false;
  @State noticeMsg: string = '';

  aboutToAppear(): void {
    this.tempVal = this.params.temperature ?? 0.7;
    this.topPVal = this.params.topP ?? 1.0;
    this.maxTokensVal = this.params.maxTokens ?? 4096;
    this.effortVal = this.params.reasoningEffort || 'medium';
    this.budgetVal = this.params.reasoningBudget ?? 8192;
    this.speedVal = this.params.responseSpeed || 'standard';
    this.ctxLimitVal = this.params.contextLimit ?? 24;
    this.retryVal = this.params.autoRetryCount ?? 2;
    this.autoCompactVal = this.sysSettings.autoCompactEnabled;
    this.thresholdVal = this.sysSettings.autoCompactThreshold;
    this.templateVal = this.sysSettings.compressionTemplate;
    this.chatProvId = this.chat?.overrideProviderId || '';
    this.chatModelVal = this.chat?.overrideModel || '';
    this.chatPromptVal = this.chat?.overridePrompt || '';
    this.startIdxVal = this.chat?.contextStartIndex || 0;
  }

  private effectiveProvider(): Provider {
    const id = this.chatProvId || this.activeProviderId;
    return this.providers.find((p: Provider): boolean => p.id === id) || this.providers[0];
  }

  private contextWindowLimit(): number {
    const p = this.effectiveProvider();
    const spec = findProviderModelSpec(p, this.chatModelVal || p.model);
    return spec.contextWindow > 0 ? spec.contextWindow : 128000;
  }

  private activeHistory(): ChatMessage[] {
    const all = this.chat?.messages || [];
    return sliceContextMessages(all, this.startIdxVal, this.ctxLimitVal);
  }

  private usedTokens(): number {
    const prompt = this.chatPromptVal.trim() || this.systemPrompt;
    return estimateMessagesTokens(this.activeHistory(), prompt);
  }

  private hasCompressionSnapshot(): boolean {
    const all = this.chat?.messages || [];
    return all.some((m: ChatMessage): boolean => !!m.isSummary && !!(m.compressionSnapshot?.length));
  }

  private providerSelectOptions(): SelectOption[] {
    const opts: SelectOption[] = [{ value: '跟随默认/助手' }];
    for (let i = 0; i < this.providers.length; i++) {
      opts.push({ value: this.providers[i].name });
    }
    return opts;
  }

  private selectedProviderLabel(): string {
    if (!this.chatProvId) return '跟随默认/助手';
    const found = this.providers.find((p: Provider): boolean => p.id === this.chatProvId);
    return found ? found.name : '跟随默认/助手';
  }

  private startIndexLabel(): string {
    const total = this.chat?.messages.length || 0;
    if (total === 0) return '无消息';
    if (this.startIdxVal <= 0) return '第 1 条（全部）';
    return '第 ' + (this.startIdxVal + 1) + ' 条起（跳过前 ' + this.startIdxVal + ' 条）';
  }

  private startIndexOptions(): SelectOption[] {
    const msgs = this.chat?.messages || [];
    if (!msgs.length) return [{ value: '无消息' }];
    return msgs.map((m: ChatMessage, idx: number): SelectOption => {
      const snippet = m.text.replace(/\s+/g, ' ').slice(0, 18);
      return { value: '第 ' + (idx + 1) + ' 条: ' + snippet };
    });
  }

  private effortLabel(e: ReasoningEffort): string {
    if (e === 'off') return '关闭';
    if (e === 'low') return '低';
    if (e === 'medium') return '中';
    if (e === 'high') return '高';
    return '最高';
  }

  private speedLabel(s: ResponseSpeedMode): string {
    if (s === 'standard') return '标准';
    if (s === 'fast') return '快速';
    return '极速';
  }

  private saveAll(): void {
    this.onSaveParams({
      temperature: Number(this.tempVal.toFixed(2)),
      topP: Number(this.topPVal.toFixed(2)),
      maxTokens: this.maxTokensVal,
      reasoningEffort: this.effortVal,
      reasoningBudget: this.budgetVal,
      responseSpeed: this.speedVal,
      contextLimit: this.ctxLimitVal,
      autoRetryCount: this.retryVal,
      retryBaseMs: this.params.retryBaseMs ?? 800
    }, this.autoCompactVal, this.thresholdVal, this.templateVal);
    if (this.chat) {
      this.onSaveChatOverrides(this.chatProvId, this.chatModelVal.trim(), this.chatPromptVal.trim(), this.startIdxVal);
    }
    this.onClose();
  }

  private async runCompress(inPlace: boolean): Promise<void> {
    if (this.busy || !this.chat?.messages.length) return;
    this.busy = true;
    this.noticeMsg = '';
    try {
      if (inPlace) {
        await this.onCompressInPlace(this.templateVal);
        this.noticeMsg = '已压缩上下文，可随时点击撤销恢复原消息';
      } else {
        await this.onCompressToNewChat(this.templateVal);
        this.onClose();
      }
    } catch (e) {
      this.noticeMsg = (e as Error).message || '压缩失败';
    } finally {
      this.busy = false;
    }
  }

  @Builder
  private navTitleBar() {
    KelivoNavTitleBar({
      titleText: '上下文与生成参数',
      showBack: true,
      rightText: this.busy ? '处理中' : '保存',
      rightPrimary: true,
      onBack: () => { this.onClose(); },
      onRightAction: () => {
        if (!this.busy) {
          this.saveAll();
        }
      }
    })
  }

  build() {
    NavDestination() {
      Column() {
        Scroll() {
        Column({ space: 14 }) {
          // Context Usage Card
          Row({ space: 14 }) {
            Progress({
              value: Math.min(this.usedTokens(), this.contextWindowLimit()),
              total: this.contextWindowLimit(),
              type: ProgressType.Ring
            }).width(58).height(58).color($r('app.color.accent')).backgroundColor($r('app.color.panel'))
            Column({ space: 4 }) {
              Text('估算上下文占用：' + this.usedTokens() + ' / ' + this.contextWindowLimit() + ' tokens')
                .fontSize(14).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink'))
              Text('系统提示词约 ' + estimateTokens(this.chatPromptVal.trim() || this.systemPrompt) +
                ' tokens · 有效消息 ' + this.activeHistory().length + ' / ' + (this.chat?.messages.length || 0) + ' 条')
                .fontSize(12).fontColor($r('app.color.muted'))
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          }.width('100%').padding(12).borderRadius(12).backgroundColor($r('app.color.surface'))
            .border({ width: 1, color: $r('app.color.line') })

          // Reasoning & Speed
          Column({ space: 8 }) {
            Text('思维链与响应控制').fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink'))
            Row({ space: 6 }) {
              ForEach(['off', 'low', 'medium', 'high', 'max'] as ReasoningEffort[], (eff: ReasoningEffort) => {
                Button(this.effortLabel(eff)).height(30).fontSize(12).layoutWeight(1)
                  .backgroundColor(this.effortVal === eff ? $r('app.color.accent') : $r('app.color.panel'))
                  .fontColor(this.effortVal === eff ? $r('app.color.on_accent') : $r('app.color.ink'))
                  .onClick(() => { this.effortVal = eff; })
              }, (eff: ReasoningEffort) => eff)
            }.width('100%')

            Row({ space: 6 }) {
              Text('响应速度').fontSize(13).fontColor($r('app.color.muted')).layoutWeight(1)
              ForEach(['standard', 'fast', 'ultrafast'] as ResponseSpeedMode[], (sp: ResponseSpeedMode) => {
                Button(this.speedLabel(sp)).height(28).fontSize(12)
                  .backgroundColor(this.speedVal === sp ? $r('app.color.tint') : $r('app.color.panel'))
                  .fontColor(this.speedVal === sp ? $r('app.color.accent') : $r('app.color.ink'))
                  .onClick(() => { this.speedVal = sp; })
              }, (sp: ResponseSpeedMode) => sp)
            }.width('100%')

            Row() {
              Text('思考 Token 预算: ' + this.budgetVal).fontSize(13).fontColor($r('app.color.ink')).layoutWeight(1)
            }.width('100%')
            Slider({ value: this.budgetVal, min: 1024, max: 32768, step: 1024 })
              .selectedColor($r('app.color.accent'))
              .onChange((v: number) => { this.budgetVal = Math.round(v); })
              .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))

            Row() {
              Text('温度 (Temperature): ' + this.tempVal.toFixed(2)).fontSize(13).fontColor($r('app.color.ink')).layoutWeight(1)
            }.width('100%')
            Slider({ value: Math.round(this.tempVal * 20), min: 0, max: 40, step: 1 })
              .selectedColor($r('app.color.accent'))
              .onChange((v: number) => { this.tempVal = v / 20; })
              .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))

            Row() {
              Text('Top-P: ' + this.topPVal.toFixed(2)).fontSize(13).fontColor($r('app.color.ink')).layoutWeight(1)
            }.width('100%')
            Slider({ value: Math.round(this.topPVal * 20), min: 1, max: 20, step: 1 })
              .selectedColor($r('app.color.accent'))
              .onChange((v: number) => { this.topPVal = v / 20; })
              .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))

            Row({ space: 10 }) {
              Text('最大输出 Token').fontSize(13).fontColor($r('app.color.ink')).layoutWeight(1)
              TextInput({ text: String(this.maxTokensVal) }).width(100).type(InputType.Number)
                .onChange((v: string) => { const n = Number(v); if (n > 0) this.maxTokensVal = Math.min(131072, n); })
            }.width('100%')

            Row({ space: 10 }) {
              Text('上下文保留条数（0 不限）').fontSize(13).fontColor($r('app.color.ink')).layoutWeight(1)
              TextInput({ text: String(this.ctxLimitVal) }).width(80).type(InputType.Number)
                .onChange((v: string) => { const n = Number(v); if (n >= 0) this.ctxLimitVal = Math.min(200, n); })
            }.width('100%')

            Row({ space: 10 }) {
              Text('失败自动重试次数').fontSize(13).fontColor($r('app.color.ink')).layoutWeight(1)
              TextInput({ text: String(this.retryVal) }).width(80).type(InputType.Number)
                .onChange((v: string) => { const n = Number(v); if (n >= 0) this.retryVal = Math.min(5, n); })
            }.width('100%')
          }.width('100%').padding(12).borderRadius(12).backgroundColor($r('app.color.surface'))
            .border({ width: 1, color: $r('app.color.line') }).alignItems(HorizontalAlign.Start)

          // Per-Conversation Overrides & Context Start
          if (this.chat) {
            Column({ space: 8 }) {
              Text('当前对话独立设置').fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink'))
              Select(this.providerSelectOptions()).value(this.selectedProviderLabel())
                .onSelect((idx: number) => {
                  this.chatProvId = idx === 0 ? '' : this.providers[idx - 1].id;
                })
                .menuSystemMaterial(ImmersiveMaterialStyle.selectMenuMaterial(this.immersiveLightEnabled))
                .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
              TextInput({ text: this.chatModelVal, placeholder: '覆盖模型 ID（留空则跟随当前配置）' })
                .onChange((v: string) => { this.chatModelVal = v; })
              TextArea({ text: this.chatPromptVal, placeholder: '覆盖本对话系统提示词（留空则使用助手设置）' })
                .height(80).onChange((v: string) => { this.chatPromptVal = v; })
              Text('固定上下文起点').fontSize(13).fontColor($r('app.color.muted'))
              Select(this.startIndexOptions()).value(this.startIndexLabel())
                .onSelect((idx: number) => { this.startIdxVal = idx; })
                .menuSystemMaterial(ImmersiveMaterialStyle.selectMenuMaterial(this.immersiveLightEnabled))
                .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
            }.width('100%').padding(12).borderRadius(12).backgroundColor($r('app.color.surface'))
              .border({ width: 1, color: $r('app.color.line') }).alignItems(HorizontalAlign.Start)
          }

          // Context Compression
          Column({ space: 8 }) {
            Text('上下文压缩').fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink'))
            Row() {
              Text('超过阈值自动压缩上下文').fontSize(13).fontColor($r('app.color.ink')).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.autoCompactVal })
                .selectedColor($r('app.color.accent'))
                .onChange((v: boolean) => { this.autoCompactVal = v; })
                .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
            }.width('100%')
            if (this.autoCompactVal) {
              Row({ space: 10 }) {
                Text('触发消息数阈值').fontSize(13).fontColor($r('app.color.muted')).layoutWeight(1)
                TextInput({ text: String(this.thresholdVal) }).width(80).type(InputType.Number)
                  .onChange((v: string) => { const n = Number(v); if (n >= 8) this.thresholdVal = n; })
              }.width('100%')
            }
            Text('压缩摘要模板').fontSize(13).fontColor($r('app.color.muted'))
            TextArea({ text: this.templateVal }).height(84).onChange((v: string) => { this.templateVal = v; })
            Row({ space: 8 }) {
              Button('原地压缩').layoutWeight(1).height(36).fontSize(13)
                .backgroundColor($r('app.color.tint')).fontColor($r('app.color.accent'))
                .enabled(!this.busy && !!(this.chat?.messages.length))
                .onClick(() => { this.runCompress(true); })
              Button('压缩并开新对话').layoutWeight(1).height(36).fontSize(13)
                .backgroundColor($r('app.color.panel')).fontColor($r('app.color.ink'))
                .enabled(!this.busy && !!(this.chat?.messages.length))
                .onClick(() => { this.runCompress(false); })
            }.width('100%')
            if (this.hasCompressionSnapshot()) {
              Button('撤销最近一次压缩（恢复全部消息）').width('100%').height(34).fontSize(13)
                .backgroundColor($r('app.color.panel')).fontColor($r('app.color.warning'))
                .onClick(() => {
                  this.onUndoCompress();
                  this.noticeMsg = '已撤销压缩，原消息已恢复';
                })
            }
          }.width('100%').padding(12).borderRadius(12).backgroundColor($r('app.color.surface'))
            .border({ width: 1, color: $r('app.color.line') }).alignItems(HorizontalAlign.Start)

          if (this.busy) {
            LoadingProgress().width(28).height(28)
          }
          if (this.noticeMsg) {
            Text(this.noticeMsg).fontSize(13).fontColor($r('app.color.accent'))
          }
        }.padding({ left: 16, right: 16, top: 56 + this.winTopInset + 6, bottom: 48 }).width('100%').constraintSize({ maxWidth: 620 }).alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').align(Alignment.Top)
    }.width('100%').height('100%').backgroundColor(Color.Transparent)
    }
    .hideBackButton(true)
    .backgroundColor(this.themeCanvasHex)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .title(
      { builder: () => this.navTitleBar(), height: 56 + this.winTopInset },
      ImmersiveMaterialStyle.titleBarOptions(this.immersiveLightEnabled, true)
    )
    .systemTransition(SystemMotion.navTransition(this.reduceMotion))
    .onBackPressed(() => this.onDismissOverlay())
  }
}
