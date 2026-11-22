import { pasteboard } from '@kit.BasicServicesKit';
import { AppLanguageCode, LanguageOption, SUPPORTED_LANGUAGES } from '../core/I18n';
import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import {
  AppearanceConfig,
  ChatItemDisplayConfig,
  GenerationParams,
  SystemSettings,
  defaultAppearance,
  defaultChatItemDisplay,
  defaultGenerationParams,
  defaultSystemSettings,
  normalizeAppearanceConfig,
  normalizeChatItemDisplay
} from '../core/Models';
import {
  BUILTIN_PALETTES,
  ThemePalette,
  WALLPAPER_PRESETS,
  WallpaperPreset,
  findPalette,
  parseCustomThemeJson
} from '../core/ThemeManager';
import { KelivoAvatarBadge, KelivoPageHeader, KelivoSectionHeader, KelivoSwitchRow } from './KelivoChrome';

@Component
export struct AppearancePanel {
  @Prop appearance: AppearanceConfig = defaultAppearance();
  @Prop systemSettings: SystemSettings = defaultSystemSettings();
  @Prop generationParams: GenerationParams = defaultGenerationParams();
  @Prop embeddedInNav: boolean = false;
  initialSubView: string = '';

  onChangeAppearance: (cfg: AppearanceConfig) => Promise<void> = async () => {};
  onUpdateSettings: (next: SystemSettings) => Promise<void> = async () => {};
  onUpdateGenerationParams: (next: GenerationParams) => Promise<void> = async () => {};
  onRequestNotifyPermission: () => Promise<void> = async () => {};
  onOpenSubView: (sub: string) => void = () => {};
  onClose: () => void = () => {};

  @State cfg: AppearanceConfig = defaultAppearance();
  @State subView: string = '';
  @State customJsonInput: string = '';
  @State statusTip: string = '';
  @State capSummary: string = '';
  @StorageProp('windowTopInsetVp') winTopInset: number = 0;
  @StorageProp('windowBottomInsetVp') winBottomInset: number = 0;

  aboutToAppear(): void {
    this.cfg = normalizeAppearanceConfig(this.appearance);
    this.subView = this.initialSubView || '';
    this.customJsonInput = this.cfg.customThemeJson ? this.cfg.customThemeJson : '';
    this.capSummary = ImmersiveMaterialStyle.capabilitySummary();
  }

  private async commitAppearance(next: AppearanceConfig): Promise<void> {
    this.cfg = next;
    await this.onChangeAppearance(next);
  }

  private isImmersiveOn(): boolean {
    return this.cfg.immersiveLightEnabled !== false;
  }

  private displayCfg(): ChatItemDisplayConfig {
    return normalizeChatItemDisplay(this.cfg.chatItemDisplay);
  }

  private cloneCfg(): AppearanceConfig {
    const rawDisplay = this.displayCfg();
    return {
      themeMode: this.cfg.themeMode,
      paletteId: this.cfg.paletteId,
      customThemeJson: this.cfg.customThemeJson,
      bubbleStyle: this.cfg.bubbleStyle,
      bubbleRadius: this.cfg.bubbleRadius,
      bubbleBlur: this.cfg.bubbleBlur,
      wallpaperKind: this.cfg.wallpaperKind,
      wallpaperValue: this.cfg.wallpaperValue,
      wallpaperOpacity: this.cfg.wallpaperOpacity,
      fontScale: this.cfg.fontScale,
      codeFontSize: this.cfg.codeFontSize,
      language: this.cfg.language,
      immersiveLightEnabled: this.cfg.immersiveLightEnabled !== false,
      pureBackground: this.cfg.pureBackground === true,
      fitAssistantBubble: this.cfg.fitAssistantBubble === true,
      splitParagraphsIntoBubbles: this.cfg.splitParagraphsIntoBubbles === true,
      inputBoxOpacity: this.cfg.inputBoxOpacity ?? 0.88,
      chatItemDisplay: rawDisplay,
      collapseLongUserChars: this.cfg.collapseLongUserChars ?? 0,
      enableAssistantMarkdown: this.cfg.enableAssistantMarkdown !== false,
      enableUserMarkdown: this.cfg.enableUserMarkdown === true,
      enableReasoningMarkdown: this.cfg.enableReasoningMarkdown !== false,
      enableMathLatex: this.cfg.enableMathLatex !== false,
      autoFollowBottom: this.cfg.autoFollowBottom !== false,
      insertSuggestionOnly: this.cfg.insertSuggestionOnly !== false,
      enterToSend: this.cfg.enterToSend === true
    };
  }

  private cloneSettings(): SystemSettings {
    return {
      autoTitleEnabled: this.systemSettings.autoTitleEnabled,
      chatSuggestionsEnabled: this.systemSettings.chatSuggestionsEnabled,
      autoCompactEnabled: this.systemSettings.autoCompactEnabled,
      autoCompactThreshold: this.systemSettings.autoCompactThreshold,
      compressionTemplate: this.systemSettings.compressionTemplate,
      imageUploadQuality: this.systemSettings.imageUploadQuality,
      hapticsEnabled: this.systemSettings.hapticsEnabled,
      keepScreenOn: this.systemSettings.keepScreenOn,
      backgroundNotifyEnabled: this.systemSettings.backgroundNotifyEnabled,
      autoSnapshotEnabled: this.systemSettings.autoSnapshotEnabled,
      builtinFetchEnabled: this.systemSettings.builtinFetchEnabled,
      maxToolSteps: this.systemSettings.maxToolSteps,
      defaultToolPermission: this.systemSettings.defaultToolPermission,
      enabledDeviceTools: this.systemSettings.enabledDeviceTools.slice()
    };
  }

  private cloneParams(): GenerationParams {
    return {
      temperature: this.generationParams.temperature,
      topP: this.generationParams.topP,
      maxTokens: this.generationParams.maxTokens,
      reasoningEffort: this.generationParams.reasoningEffort,
      reasoningBudget: this.generationParams.reasoningBudget,
      responseSpeed: this.generationParams.responseSpeed,
      contextLimit: this.generationParams.contextLimit,
      autoRetryCount: this.generationParams.autoRetryCount ?? 2,
      retryBaseMs: this.generationParams.retryBaseMs ?? 600
    };
  }

  private headerTitle(): string {
    if (this.subView === 'theme') return '主题与配色';
    if (this.subView === 'messageStyle') return '消息样式';
    if (this.subView === 'display') return '显示项定制';
    if (this.subView === 'language') return '界面语言';
    return '外观与偏好设置';
  }

  private handleBack(): void {
    if (this.subView.length > 0 && this.subView !== this.initialSubView) {
      this.subView = '';
    } else {
      this.onClose();
    }
  }

  private async setThemeMode(mode: 'system' | 'light' | 'dark'): Promise<void> {
    const next = this.cloneCfg();
    next.themeMode = mode;
    await this.commitAppearance(next);
  }

  private async setPalette(id: string): Promise<void> {
    const next = this.cloneCfg();
    next.paletteId = id;
    next.customThemeJson = undefined;
    this.customJsonInput = '';
    await this.commitAppearance(next);
  }

  private async setBubbleStyle(style: 'default' | 'frosted' | 'solid'): Promise<void> {
    const next = this.cloneCfg();
    next.bubbleStyle = style;
    await this.commitAppearance(next);
  }

  private async setWallpaper(presetId: string): Promise<void> {
    const next = this.cloneCfg();
    next.wallpaperKind = presetId === 'none' ? 'none' : 'gradient';
    next.wallpaperValue = presetId;
    await this.commitAppearance(next);
  }

  private async setLanguage(code: AppLanguageCode): Promise<void> {
    const next = this.cloneCfg();
    next.language = code;
    await this.commitAppearance(next);
    this.statusTip = `界面语言已切换为 ${code}`;
  }

  private async updateDisplayFlag(key: string, val: boolean): Promise<void> {
    const next = this.cloneCfg();
    const d = this.displayCfg();
    if (key === 'showUserAvatar') d.showUserAvatar = val;
    else if (key === 'showUserName') d.showUserName = val;
    else if (key === 'showUserTimestamp') d.showUserTimestamp = val;
    else if (key === 'showUserMessageActions') d.showUserMessageActions = val;
    else if (key === 'showModelIcon') d.showModelIcon = val;
    else if (key === 'showAssistantAvatarInTitleBar') d.showAssistantAvatarInTitleBar = val;
    else if (key === 'showModelName') d.showModelName = val;
    else if (key === 'showModelTimestamp') d.showModelTimestamp = val;
    else if (key === 'showProviderAfterModelName') d.showProviderAfterModelName = val;
    else if (key === 'showTokenStats') d.showTokenStats = val;
    else if (key === 'showThinkingCards') d.showThinkingCards = val;
    else if (key === 'showToolCards') d.showToolCards = val;
    else if (key === 'showFilesBelowReplies') d.showFilesBelowReplies = val;
    else if (key === 'showReasoningLevelOnButton') d.showReasoningLevelOnButton = val;
    next.chatItemDisplay = d;
    await this.commitAppearance(next);
  }

  private async applyCustomJson(): Promise<void> {
    const raw = this.customJsonInput.trim();
    if (raw.length === 0) {
      const next = this.cloneCfg();
      next.customThemeJson = undefined;
      await this.commitAppearance(next);
      this.statusTip = '已恢复内置配色';
      return;
    }
    const base = findPalette(this.cfg.paletteId).light;
    const parsed = parseCustomThemeJson(raw, base);
    if (!parsed) {
      this.statusTip = '自定义主题 JSON 格式无效';
      return;
    }
    const next = this.cloneCfg();
    next.customThemeJson = raw;
    await this.commitAppearance(next);
    this.statusTip = '已应用自定义主题 JSON';
  }

  private async copyCurrentThemeJson(): Promise<void> {
    const pal = findPalette(this.cfg.paletteId);
    const tokens = this.cfg.themeMode === 'dark' ? pal.dark : pal.light;
    try {
      await pasteboard.getSystemPasteboard().setData(
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, JSON.stringify(tokens, null, 2))
      );
      this.statusTip = '已复制当前主题 JSON 到剪贴板';
    } catch (e) {
      this.statusTip = `复制失败: ${String(e)}`;
    }
  }

  @Builder
  private navRow(
    symbolRes: Resource,
    title: string,
    trailing: string,
    showDivider: boolean,
    onTap: () => void
  ) {
    Column() {
      Row({ space: 12 }) {
        SymbolGlyph(symbolRes)
          .fontSize(19)
          .fontColor([$r('app.color.ink')])
        Text(title)
          .fontSize(15)
          .fontColor($r('app.color.ink'))
          .layoutWeight(1)
        if (trailing.length > 0) {
          Text(trailing)
            .fontSize(12)
            .fontColor($r('app.color.muted'))
        }
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(15)
          .fontColor([$r('app.color.muted')])
      }
      .width('100%')
      .padding({ left: 16, right: 14, top: 14, bottom: 14 })
      .onClick(() => { onTap(); })

      if (showDivider) {
        Divider().color($r('app.color.line')).margin({ left: 48 })
      }
    }
    .width('100%')
  }

  private openSub(sub: string): void {
    if (this.embeddedInNav) {
      this.onOpenSubView(sub);
    } else {
      this.subView = sub;
    }
  }

  @Builder
  private renderHub() {
    Column({ space: 4 }) {
      KelivoSectionHeader({ titleText: '视觉与显示', topSpacing: 6 })
      Column() {
        this.navRow(
          $r('sys.symbol.paintbrush'),
          '主题与配色盘',
          findPalette(this.cfg.paletteId).name,
          true,
          () => { this.openSub('theme'); }
        )
        this.navRow(
          $r('sys.symbol.message'),
          '消息样式与气泡',
          this.cfg.bubbleStyle === 'frosted' ? '磨砂' : this.cfg.bubbleStyle === 'solid' ? '纯色' : '默认',
          true,
          () => { this.openSub('messageStyle'); }
        )
        this.navRow(
          $r('sys.symbol.display'),
          '对话显示项定制',
          '14 项开关',
          true,
          () => { this.openSub('display'); }
        )
        this.navRow(
          $r('sys.symbol.translate'),
          '界面语言',
          this.cfg.language,
          false,
          () => { this.openSub('language'); }
        )
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor($r('app.color.surface'))

      KelivoSectionHeader({ titleText: '文本渲染与 Markdown', topSpacing: 12 })
      Column() {
        KelivoSwitchRow({
          rowTitle: '助手消息 Markdown 渲染',
          desc: '关闭后将以纯文本形式展示回复',
          isOn: this.cfg.enableAssistantMarkdown !== false,
          showDivider: true,
          onToggle: async (v: boolean) => {
            const next = this.cloneCfg();
            next.enableAssistantMarkdown = v;
            await this.commitAppearance(next);
          }
        })
        KelivoSwitchRow({
          rowTitle: '用户消息 Markdown 渲染',
          desc: '为发送的内容应用基础 Markdown 格式',
          isOn: this.cfg.enableUserMarkdown === true,
          showDivider: true,
          onToggle: async (v: boolean) => {
            const next = this.cloneCfg();
            next.enableUserMarkdown = v;
            await this.commitAppearance(next);
          }
        })
        KelivoSwitchRow({
          rowTitle: '思考过程 Markdown 渲染',
          desc: '美化推理模型输出的思考链文本',
          isOn: this.cfg.enableReasoningMarkdown !== false,
          showDivider: true,
          onToggle: async (v: boolean) => {
            const next = this.cloneCfg();
            next.enableReasoningMarkdown = v;
            await this.commitAppearance(next);
          }
        })
        KelivoSwitchRow({
          rowTitle: 'LaTeX 数学公式解析',
          desc: '识别行内与块级数学公式表达式',
          isOn: this.cfg.enableMathLatex !== false,
          showDivider: true,
          onToggle: async (v: boolean) => {
            const next = this.cloneCfg();
            next.enableMathLatex = v;
            await this.commitAppearance(next);
          }
        })

        Row({ space: 10 }) {
          Column({ space: 2 }) {
            Text('长用户消息自动折叠阈值')
              .fontSize(14)
              .fontColor($r('app.color.ink'))
            Text((this.cfg.collapseLongUserChars ?? 0) === 0
              ? '已关闭自动折叠'
              : `超过 ${this.cfg.collapseLongUserChars} 字符自动折叠`)
              .fontSize(11)
              .fontColor($r('app.color.muted'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Row({ space: 6 }) {
            Button('−')
              .type(ButtonType.Normal)
              .width(30)
              .height(30)
              .padding(0)
              .borderRadius(8)
              .backgroundColor($r('app.color.panel'))
              .fontColor($r('app.color.ink'))
              .onClick(async () => {
                const next = this.cloneCfg();
                next.collapseLongUserChars = Math.max(0, (next.collapseLongUserChars ?? 0) - 200);
                await this.commitAppearance(next);
              })
            Text(`${this.cfg.collapseLongUserChars ?? 0}`)
              .fontSize(12)
              .fontColor($r('app.color.ink'))
              .width(36)
              .textAlign(TextAlign.Center)
            Button('+')
              .type(ButtonType.Normal)
              .width(30)
              .height(30)
              .padding(0)
              .borderRadius(8)
              .backgroundColor($r('app.color.panel'))
              .fontColor($r('app.color.ink'))
              .onClick(async () => {
                const next = this.cloneCfg();
                next.collapseLongUserChars = Math.min(2000, (next.collapseLongUserChars ?? 0) + 200);
                await this.commitAppearance(next);
              })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 14, top: 11, bottom: 11 })
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor($r('app.color.surface'))

      KelivoSectionHeader({ titleText: '对话与输入行为', topSpacing: 12 })
      Column() {
        KelivoSwitchRow({
          rowTitle: '流式输出自动跟随底部',
          desc: '未手动上滑时自动滚动显示最新生成内容',
          isOn: this.cfg.autoFollowBottom !== false,
          showDivider: true,
          onToggle: async (v: boolean) => {
            const next = this.cloneCfg();
            next.autoFollowBottom = v;
            await this.commitAppearance(next);
          }
        })
        KelivoSwitchRow({
          rowTitle: '点击追问建议仅填入输入框',
          desc: '开启后点击建议气泡不立即发送，方便继续补充编辑',
          isOn: this.cfg.insertSuggestionOnly !== false,
          showDivider: true,
          onToggle: async (v: boolean) => {
            const next = this.cloneCfg();
            next.insertSuggestionOnly = v;
            await this.commitAppearance(next);
          }
        })
        KelivoSwitchRow({
          rowTitle: '回车键直接发送消息',
          desc: '外接键盘或软键盘按 Enter 立即触发发送',
          isOn: this.cfg.enterToSend === true,
          showDivider: true,
          onToggle: async (v: boolean) => {
            const next = this.cloneCfg();
            next.enterToSend = v;
            await this.commitAppearance(next);
          }
        })
        KelivoSwitchRow({
          rowTitle: 'AI 自动命名对话',
          desc: '首轮回答完成后自动归纳生成简短会话标题',
          isOn: this.systemSettings.autoTitleEnabled,
          showDivider: true,
          onToggle: async (v: boolean) => {
            const next = this.cloneSettings();
            next.autoTitleEnabled = v;
            await this.onUpdateSettings(next);
          }
        })
        KelivoSwitchRow({
          rowTitle: '生成后续提问建议',
          desc: '在助手回复末尾提供相关追问气泡',
          isOn: this.systemSettings.chatSuggestionsEnabled,
          showDivider: true,
          onToggle: async (v: boolean) => {
            const next = this.cloneSettings();
            next.chatSuggestionsEnabled = v;
            await this.onUpdateSettings(next);
          }
        })
        KelivoSwitchRow({
          rowTitle: '触觉震动反馈',
          desc: '点击、发送与切换状态时提供轻触震动反馈',
          isOn: this.systemSettings.hapticsEnabled,
          showDivider: true,
          onToggle: async (v: boolean) => {
            const next = this.cloneSettings();
            next.hapticsEnabled = v;
            await this.onUpdateSettings(next);
          }
        })
        KelivoSwitchRow({
          rowTitle: '生成时屏幕常亮',
          desc: '避免长时间工具执行或推理期间屏幕自动熄灭',
          isOn: this.systemSettings.keepScreenOn,
          showDivider: true,
          onToggle: async (v: boolean) => {
            const next = this.cloneSettings();
            next.keepScreenOn = v;
            await this.onUpdateSettings(next);
          }
        })
        KelivoSwitchRow({
          rowTitle: '超长上下文自动压缩',
          desc: `消息数超过 ${this.systemSettings.autoCompactThreshold} 条时自动压缩早期消息`,
          isOn: this.systemSettings.autoCompactEnabled,
          showDivider: true,
          onToggle: async (v: boolean) => {
            const next = this.cloneSettings();
            next.autoCompactEnabled = v;
            await this.onUpdateSettings(next);
          }
        })
        KelivoSwitchRow({
          rowTitle: '生成完成系统通知',
          desc: '后台完成长任务或回复时推送系统通知',
          isOn: this.systemSettings.backgroundNotifyEnabled,
          showDivider: true,
          onToggle: async (v: boolean) => {
            if (v) {
              await this.onRequestNotifyPermission();
            }
            const next = this.cloneSettings();
            next.backgroundNotifyEnabled = v;
            await this.onUpdateSettings(next);
          }
        })
        KelivoSwitchRow({
          rowTitle: '工具自动审批（完全访问）',
          desc: '开启后非高风险工具默认免审批直接执行',
          isOn: this.systemSettings.defaultToolPermission === 'full',
          showDivider: false,
          onToggle: async (v: boolean) => {
            const next = this.cloneSettings();
            next.defaultToolPermission = v ? 'full' : 'ask';
            await this.onUpdateSettings(next);
          }
        })
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor($r('app.color.surface'))

      KelivoSectionHeader({ titleText: '图片与网络重连', topSpacing: 12 })
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          Text(`图片压缩上传质量 ${this.systemSettings.imageUploadQuality}%`)
            .fontSize(13)
            .fontColor($r('app.color.ink'))
            .layoutWeight(1)
        }
        .width('100%')

        Slider({ value: this.systemSettings.imageUploadQuality, min: 40, max: 100, step: 5 })
          .onChange(async (val: number) => {
            const next = this.cloneSettings();
            next.imageUploadQuality = Math.round(val);
            await this.onUpdateSettings(next);
          })
          .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.isImmersiveOn()))

        Divider().color($r('app.color.line'))

        Row({ space: 10 }) {
          Column({ space: 2 }) {
            Text('请求失败自动重试次数')
              .fontSize(14)
              .fontColor($r('app.color.ink'))
            Text('遇到网络抖动或 429 限流时自动指数退避重试')
              .fontSize(11)
              .fontColor($r('app.color.muted'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Row({ space: 6 }) {
            Button('−')
              .type(ButtonType.Normal)
              .width(30)
              .height(30)
              .padding(0)
              .borderRadius(8)
              .backgroundColor($r('app.color.panel'))
              .fontColor($r('app.color.ink'))
              .onClick(async () => {
                const next = this.cloneParams();
                next.autoRetryCount = Math.max(0, (next.autoRetryCount ?? 2) - 1);
                await this.onUpdateGenerationParams(next);
              })
            Text(`${this.generationParams.autoRetryCount ?? 2}`)
              .fontSize(13)
              .fontColor($r('app.color.ink'))
              .width(24)
              .textAlign(TextAlign.Center)
            Button('+')
              .type(ButtonType.Normal)
              .width(30)
              .height(30)
              .padding(0)
              .borderRadius(8)
              .backgroundColor($r('app.color.panel'))
              .fontColor($r('app.color.ink'))
              .onClick(async () => {
                const next = this.cloneParams();
                next.autoRetryCount = Math.min(5, (next.autoRetryCount ?? 2) + 1);
                await this.onUpdateGenerationParams(next);
              })
          }
        }
        .width('100%')
      }
      .width('100%')
      .padding(16)
      .borderRadius(16)
      .backgroundColor($r('app.color.surface'))
    }
    .width('100%')
  }

  @Builder
  private renderThemeSubView() {
    Column({ space: 10 }) {
      Column() {
        KelivoSwitchRow({
          rowTitle: 'HarmonyOS 沉浸光感材质',
          desc: this.capSummary || '自动探测设备光感与系统材质能力',
          isOn: this.isImmersiveOn(),
          showDivider: true,
          onToggle: async (v: boolean) => {
            if (v === this.isImmersiveOn()) {
              return;
            }
            const next = this.cloneCfg();
            next.immersiveLightEnabled = v;
            await this.commitAppearance(next);
            this.statusTip = v ? '已开启 HarmonyOS 沉浸光感' : '已切换为标准清晰材质';
          }
        })
        KelivoSwitchRow({
          rowTitle: '纯净背景画布',
          desc: '浅色使用纯白 #FFFFFF，深色使用 OLED 纯黑 #000000',
          isOn: this.cfg.pureBackground === true,
          showDivider: false,
          onToggle: async (v: boolean) => {
            if (v === (this.cfg.pureBackground === true)) {
              return;
            }
            const next = this.cloneCfg();
            next.pureBackground = v;
            await this.commitAppearance(next);
          }
        })
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor($r('app.color.surface'))

      Column({ space: 8 }) {
        Text('色彩模式')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
        Row({ space: 8 }) {
          Button('跟随系统')
            .type(ButtonType.Normal)
            .layoutWeight(1)
            .height(36)
            .fontSize(12)
            .borderRadius(10)
            .fontColor(this.cfg.themeMode === 'system' ? $r('app.color.on_accent') : $r('app.color.ink'))
            .backgroundColor(this.cfg.themeMode === 'system' ? $r('app.color.accent') : $r('app.color.panel'))
            .onClick(async () => { await this.setThemeMode('system'); })
          Button('浅色')
            .type(ButtonType.Normal)
            .layoutWeight(1)
            .height(36)
            .fontSize(12)
            .borderRadius(10)
            .fontColor(this.cfg.themeMode === 'light' ? $r('app.color.on_accent') : $r('app.color.ink'))
            .backgroundColor(this.cfg.themeMode === 'light' ? $r('app.color.accent') : $r('app.color.panel'))
            .onClick(async () => { await this.setThemeMode('light'); })
          Button('深色')
            .type(ButtonType.Normal)
            .layoutWeight(1)
            .height(36)
            .fontSize(12)
            .borderRadius(10)
            .fontColor(this.cfg.themeMode === 'dark' ? $r('app.color.on_accent') : $r('app.color.ink'))
            .backgroundColor(this.cfg.themeMode === 'dark' ? $r('app.color.accent') : $r('app.color.panel'))
            .onClick(async () => { await this.setThemeMode('dark'); })
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .padding(14)
      .borderRadius(16)
      .backgroundColor($r('app.color.surface'))
      .width('100%')

      Column({ space: 10 }) {
        Text('内置配色盘（9 套）')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(BUILTIN_PALETTES, (pal: ThemePalette) => {
            Button() {
              Row({ space: 6 }) {
                Row()
                  .width(12)
                  .height(12)
                  .borderRadius(6)
                  .backgroundColor(pal.light.accent)
                Text(pal.name)
                  .fontSize(12)
                  .fontColor(findPalette(this.cfg.paletteId).id === pal.id ? pal.light.onAccent : $r('app.color.ink'))
                if (findPalette(this.cfg.paletteId).id === pal.id) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(12)
                    .fontColor([pal.light.onAccent])
                }
              }
            }
            .type(ButtonType.Normal)
            .height(36)
            .padding({ left: 10, right: 12 })
            .margin({ right: 8, bottom: 8 })
            .borderRadius(12)
            .backgroundColor(findPalette(this.cfg.paletteId).id === pal.id ? pal.light.accent : $r('app.color.panel'))
            .onClick(async () => { await this.setPalette(pal.id); })
          }, (pal: ThemePalette) => pal.id)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .padding(14)
      .borderRadius(16)
      .backgroundColor($r('app.color.surface'))
      .width('100%')

      Column({ space: 8 }) {
        Text('聊天背景壁纸')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(WALLPAPER_PRESETS, (wp: WallpaperPreset) => {
            Button(wp.name)
              .type(ButtonType.Normal)
              .height(32)
              .fontSize(12)
              .padding({ left: 12, right: 12 })
              .margin({ right: 6, bottom: 6 })
              .borderRadius(10)
              .fontColor(this.cfg.wallpaperValue === wp.id ? $r('app.color.on_accent') : $r('app.color.ink'))
              .backgroundColor(this.cfg.wallpaperValue === wp.id ? $r('app.color.accent') : $r('app.color.panel'))
              .onClick(async () => { await this.setWallpaper(wp.id); })
          }, (wp: WallpaperPreset) => wp.id)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .padding(14)
      .borderRadius(16)
      .backgroundColor($r('app.color.surface'))
      .width('100%')

      Column({ space: 8 }) {
        Row() {
          Text('自定义主题 JSON 导入/导出')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
          Blank()
          Button('导出当前JSON')
            .type(ButtonType.Normal)
            .height(28)
            .fontSize(11)
            .borderRadius(8)
            .fontColor($r('app.color.accent'))
            .backgroundColor($r('app.color.tint'))
            .onClick(async () => { await this.copyCurrentThemeJson(); })
        }
        .width('100%')

        TextArea({ text: this.customJsonInput, placeholder: '{"accent":"#4D5C92","canvas":"#F7F7F7",...}' })
          .height(78)
          .borderRadius(10)
          .backgroundColor($r('app.color.canvas'))
          .onChange((v: string) => { this.customJsonInput = v; })

        Button('应用自定义主题 JSON')
          .type(ButtonType.Normal)
          .width('100%')
          .height(38)
          .fontSize(13)
          .borderRadius(10)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor($r('app.color.accent'))
          .onClick(async () => { await this.applyCustomJson(); })
      }
      .alignItems(HorizontalAlign.Start)
      .padding(14)
      .borderRadius(16)
      .backgroundColor($r('app.color.surface'))
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private renderMessageStyleSubView() {
    Column({ space: 10 }) {
      // Live Preview Card
      Column({ space: 10 }) {
        Text('实时效果预览')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.muted'))
          .width('100%')

        Row() {
          Blank()
          Text('帮我解释 ArkTS 声明式 UI 的优势')
            .fontSize(Math.round(15 * this.cfg.fontScale))
            .fontColor($r('app.color.ink'))
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .borderRadius(this.cfg.bubbleRadius)
            .backgroundColor($r('app.color.tint'))
        }
        .width('100%')

        Row({ space: 8 }) {
          KelivoAvatarBadge({
            brandId: 'openai',
            avatarText: '',
            fallbackLetter: 'AI',
            badgeSize: 24
          })
          Text('GPT-4o')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.accent'))
        }
        .width('100%')

        Column({ space: 4 }) {
          Text('第一段：ArkUI 提供简洁的声明式状态驱动视图。')
            .fontSize(Math.round(15 * this.cfg.fontScale))
            .fontColor($r('app.color.ink'))
            .padding(this.cfg.bubbleStyle === 'default' && !this.cfg.splitParagraphsIntoBubbles ? 0 : 10)
            .borderRadius(this.cfg.bubbleRadius)
            .backgroundColor(this.cfg.bubbleStyle === 'default' && !this.cfg.splitParagraphsIntoBubbles
              ? Color.Transparent
              : $r('app.color.panel'))
            .width(this.cfg.fitAssistantBubble ? undefined : '100%')

          if (this.cfg.splitParagraphsIntoBubbles) {
            Text('第二段：分段气泡开关开启后会为每段独立包裹圆角卡片。')
              .fontSize(Math.round(15 * this.cfg.fontScale))
              .fontColor($r('app.color.ink'))
              .padding(10)
              .borderRadius(this.cfg.bubbleRadius)
              .backgroundColor($r('app.color.panel'))
              .width(this.cfg.fitAssistantBubble ? undefined : '100%')
          }

          Text('const ok: boolean = true;')
            .fontFamily('monospace')
            .fontSize(this.cfg.codeFontSize)
            .fontColor($r('app.color.accent'))
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .borderRadius(6)
            .backgroundColor($r('app.color.canvas'))
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }
      .width('100%')
      .padding(14)
      .borderRadius(16)
      .backgroundColor($r('app.color.surface'))

      Column({ space: 10 }) {
        Text('气泡风格')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
        Row({ space: 8 }) {
          Button('默认')
            .type(ButtonType.Normal)
            .layoutWeight(1)
            .height(34)
            .fontSize(12)
            .borderRadius(10)
            .fontColor(this.cfg.bubbleStyle === 'default' ? $r('app.color.on_accent') : $r('app.color.ink'))
            .backgroundColor(this.cfg.bubbleStyle === 'default' ? $r('app.color.accent') : $r('app.color.panel'))
            .onClick(async () => { await this.setBubbleStyle('default'); })
          Button('磨砂玻璃')
            .type(ButtonType.Normal)
            .layoutWeight(1)
            .height(34)
            .fontSize(12)
            .borderRadius(10)
            .fontColor(this.cfg.bubbleStyle === 'frosted' ? $r('app.color.on_accent') : $r('app.color.ink'))
            .backgroundColor(this.cfg.bubbleStyle === 'frosted' ? $r('app.color.accent') : $r('app.color.panel'))
            .onClick(async () => { await this.setBubbleStyle('frosted'); })
          Button('极简纯色')
            .type(ButtonType.Normal)
            .layoutWeight(1)
            .height(34)
            .fontSize(12)
            .borderRadius(10)
            .fontColor(this.cfg.bubbleStyle === 'solid' ? $r('app.color.on_accent') : $r('app.color.ink'))
            .backgroundColor(this.cfg.bubbleStyle === 'solid' ? $r('app.color.accent') : $r('app.color.panel'))
            .onClick(async () => { await this.setBubbleStyle('solid'); })
        }
        .width('100%')

        Divider().color($r('app.color.line'))

        KelivoSwitchRow({
          rowTitle: '助手气泡自适应文本宽度',
          desc: '开启后助手短消息气泡按内容宽度贴合显示',
          isOn: this.cfg.fitAssistantBubble === true,
          showDivider: true,
          onToggle: async (v: boolean) => {
            const next = this.cloneCfg();
            next.fitAssistantBubble = v;
            await this.commitAppearance(next);
          }
        })

        KelivoSwitchRow({
          rowTitle: '按段落分拆助手回复气泡',
          desc: '将普通文本段落分拆成多条紧凑气泡（保留代码块完整）',
          isOn: this.cfg.splitParagraphsIntoBubbles === true,
          showDivider: false,
          onToggle: async (v: boolean) => {
            const next = this.cloneCfg();
            next.splitParagraphsIntoBubbles = v;
            await this.commitAppearance(next);
          }
        })
      }
      .alignItems(HorizontalAlign.Start)
      .padding(14)
      .borderRadius(16)
      .backgroundColor($r('app.color.surface'))
      .width('100%')

      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Text(`圆角 ${this.cfg.bubbleRadius}vp`).fontSize(12).width(104).fontColor($r('app.color.muted'))
          Slider({ value: this.cfg.bubbleRadius, min: 6, max: 24, step: 2 })
            .layoutWeight(1)
            .onChange(async (val: number) => {
              const next = this.cloneCfg();
              next.bubbleRadius = Math.round(val);
              await this.commitAppearance(next);
            })
            .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.isImmersiveOn()))
        }
        .width('100%')

        Row({ space: 8 }) {
          Text(`文字缩放 ${this.cfg.fontScale.toFixed(2)}x`).fontSize(12).width(104).fontColor($r('app.color.muted'))
          Slider({ value: Math.round(this.cfg.fontScale * 100), min: 85, max: 135, step: 5 })
            .layoutWeight(1)
            .onChange(async (val: number) => {
              const next = this.cloneCfg();
              next.fontScale = Math.round(val) / 100;
              await this.commitAppearance(next);
            })
            .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.isImmersiveOn()))
        }
        .width('100%')

        Row({ space: 8 }) {
          Text(`代码字号 ${this.cfg.codeFontSize}fp`).fontSize(12).width(104).fontColor($r('app.color.muted'))
          Slider({ value: this.cfg.codeFontSize, min: 11, max: 18, step: 1 })
            .layoutWeight(1)
            .onChange(async (val: number) => {
              const next = this.cloneCfg();
              next.codeFontSize = Math.round(val);
              await this.commitAppearance(next);
            })
            .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.isImmersiveOn()))
        }
        .width('100%')

        Row({ space: 8 }) {
          Text(`输入框不透明度 ${Math.round((this.cfg.inputBoxOpacity ?? 0.88) * 100)}%`)
            .fontSize(12)
            .width(126)
            .fontColor($r('app.color.muted'))
          Slider({ value: Math.round((this.cfg.inputBoxOpacity ?? 0.88) * 100), min: 40, max: 100, step: 5 })
            .layoutWeight(1)
            .onChange(async (val: number) => {
              const next = this.cloneCfg();
              next.inputBoxOpacity = Math.round(val) / 100;
              await this.commitAppearance(next);
            })
            .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.isImmersiveOn()))
        }
        .width('100%')
      }
      .padding(14)
      .borderRadius(16)
      .backgroundColor($r('app.color.surface'))
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private renderDisplaySubView() {
    Column({ space: 4 }) {
      KelivoSectionHeader({ titleText: '用户消息显示', topSpacing: 4 })
      Column() {
        KelivoSwitchRow({
          rowTitle: '显示用户头像',
          desc: '',
          isOn: this.displayCfg().showUserAvatar,
          showDivider: true,
          onToggle: async (v: boolean) => { await this.updateDisplayFlag('showUserAvatar', v); }
        })
        KelivoSwitchRow({
          rowTitle: '显示用户昵称',
          desc: '',
          isOn: this.displayCfg().showUserName,
          showDivider: true,
          onToggle: async (v: boolean) => { await this.updateDisplayFlag('showUserName', v); }
        })
        KelivoSwitchRow({
          rowTitle: '显示用户消息时间戳',
          desc: '',
          isOn: this.displayCfg().showUserTimestamp,
          showDivider: true,
          onToggle: async (v: boolean) => { await this.updateDisplayFlag('showUserTimestamp', v); }
        })
        KelivoSwitchRow({
          rowTitle: '显示用户消息操作按钮',
          desc: '',
          isOn: this.displayCfg().showUserMessageActions,
          showDivider: false,
          onToggle: async (v: boolean) => { await this.updateDisplayFlag('showUserMessageActions', v); }
        })
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor($r('app.color.surface'))

      KelivoSectionHeader({ titleText: '助手与模型显示', topSpacing: 12 })
      Column() {
        KelivoSwitchRow({
          rowTitle: '显示模型/助手图标',
          desc: '',
          isOn: this.displayCfg().showModelIcon,
          showDivider: true,
          onToggle: async (v: boolean) => { await this.updateDisplayFlag('showModelIcon', v); }
        })
        KelivoSwitchRow({
          rowTitle: '顶栏显示助手头像',
          desc: '',
          isOn: this.displayCfg().showAssistantAvatarInTitleBar,
          showDivider: true,
          onToggle: async (v: boolean) => { await this.updateDisplayFlag('showAssistantAvatarInTitleBar', v); }
        })
        KelivoSwitchRow({
          rowTitle: '显示模型/助手名称',
          desc: '',
          isOn: this.displayCfg().showModelName,
          showDivider: true,
          onToggle: async (v: boolean) => { await this.updateDisplayFlag('showModelName', v); }
        })
        KelivoSwitchRow({
          rowTitle: '显示回复时间戳',
          desc: '',
          isOn: this.displayCfg().showModelTimestamp,
          showDivider: true,
          onToggle: async (v: boolean) => { await this.updateDisplayFlag('showModelTimestamp', v); }
        })
        KelivoSwitchRow({
          rowTitle: '模型名后显示服务商名称',
          desc: '',
          isOn: this.displayCfg().showProviderAfterModelName,
          showDivider: true,
          onToggle: async (v: boolean) => { await this.updateDisplayFlag('showProviderAfterModelName', v); }
        })
        KelivoSwitchRow({
          rowTitle: '显示 Token 用量与耗时',
          desc: '',
          isOn: this.displayCfg().showTokenStats,
          showDivider: true,
          onToggle: async (v: boolean) => { await this.updateDisplayFlag('showTokenStats', v); }
        })
        KelivoSwitchRow({
          rowTitle: '显示深度思考折叠卡片',
          desc: '',
          isOn: this.displayCfg().showThinkingCards,
          showDivider: true,
          onToggle: async (v: boolean) => { await this.updateDisplayFlag('showThinkingCards', v); }
        })
        KelivoSwitchRow({
          rowTitle: '显示工具调用详情卡片',
          desc: '',
          isOn: this.displayCfg().showToolCards,
          showDivider: true,
          onToggle: async (v: boolean) => { await this.updateDisplayFlag('showToolCards', v); }
        })
        KelivoSwitchRow({
          rowTitle: '在回复下方显示生成文件/图片',
          desc: '',
          isOn: this.displayCfg().showFilesBelowReplies,
          showDivider: true,
          onToggle: async (v: boolean) => { await this.updateDisplayFlag('showFilesBelowReplies', v); }
        })
        KelivoSwitchRow({
          rowTitle: '思考按钮上显示当前推理深度文字',
          desc: '',
          isOn: this.displayCfg().showReasoningLevelOnButton,
          showDivider: false,
          onToggle: async (v: boolean) => { await this.updateDisplayFlag('showReasoningLevelOnButton', v); }
        })
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor($r('app.color.surface'))
    }
    .width('100%')
  }

  @Builder
  private renderLanguageSubView() {
    Column() {
      ForEach(SUPPORTED_LANGUAGES, (opt: LanguageOption, idx: number) => {
        Column() {
          Row() {
            Text(opt.label)
              .fontSize(15)
              .fontColor($r('app.color.ink'))
              .layoutWeight(1)
            if (this.cfg.language === opt.code) {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(17)
                .fontColor([$r('app.color.accent')])
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          .onClick(async () => { await this.setLanguage(opt.code); })

          if (idx < SUPPORTED_LANGUAGES.length - 1) {
            Divider().color($r('app.color.line')).margin({ left: 16 })
          }
        }
        .width('100%')
      }, (opt: LanguageOption) => opt.code)
    }
    .width('100%')
    .borderRadius(16)
    .backgroundColor($r('app.color.surface'))
  }

  build() {
    Column() {
      if (!this.embeddedInNav) {
        KelivoPageHeader({
          titleText: this.headerTitle(),
          showBack: true,
          onBack: () => { this.handleBack(); }
        })
      }

      Scroll() {
        Column() {
          if (this.statusTip.length > 0) {
            Text(this.statusTip)
              .fontSize(12)
              .fontColor($r('app.color.accent'))
              .padding({ left: 4, right: 4, bottom: 8 })
              .width('100%')
          }
          if (this.subView === 'theme') {
            this.renderThemeSubView()
          } else if (this.subView === 'messageStyle') {
            this.renderMessageStyleSubView()
          } else if (this.subView === 'display') {
            this.renderDisplaySubView()
          } else if (this.subView === 'language') {
            this.renderLanguageSubView()
          } else {
            this.renderHub()
          }
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: this.embeddedInNav ? (56 + this.winTopInset + 4) : 4,
          bottom: Math.max(36, this.winBottomInset + 20)
        })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }
}
