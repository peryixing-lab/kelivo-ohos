import {
  Attachment,
  InstructionCard,
  QuickPhrase,
  ReasoningEffort
} from '../core/Models';
import { BrandIconId } from '../core/BrandIcons';
import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { hexWithAlpha } from '../core/ImmersiveUtils';
import { SystemMotion } from '../core/SystemMotion';
import { BUILTIN_PALETTES, PaletteTokens } from '../core/ThemeManager';
import { KelivoAvatarBadge } from './KelivoChrome';
import { ChatToolApprovalBox } from './ChatMessageRowView';
import { reasoningBulbResource } from './ChatQuickSheets';

@Component
export struct ChatComposerView {
  @Link draft: string;
  @Link showPromptQuickBar: boolean;
  @Link askQuestionAnswer: string;

  @Prop quoteExcerpt: string = '';
  @Prop attachedList: Attachment[] = [];
  @Prop instructionCards: InstructionCard[] = [];
  @Prop activeInstructionIds: string[] = [];
  @Prop quickPhrases: QuickPhrase[] = [];
  @Prop placeholderText: string = '';
  @Prop working: boolean = false;
  @Prop picking: boolean = false;
  @Prop enterToSend: boolean = false;
  @Prop activeBrandId: BrandIconId = '';
  @Prop providerName: string = '';
  @Prop builtinSearchOn: boolean = false;
  @Prop searchOn: boolean = false;
  @Prop reasoningLevelCount: number = 1;
  @Prop reasoningBulbRays: number = 0;
  @Prop reasoningEffort: ReasoningEffort = 'off';
  @Prop reasoningLabel: string = '关闭';
  @Prop showReasoningLevelOnButton: boolean = false;
  @Prop fullAccessMode: boolean = false;
  @Prop imageGenMode: boolean = false;
  @Prop recording: boolean = false;
  @Prop stopLabel: string = '停止';
  @Prop sendLabel: string = '发送';
  @Prop readingId: string = '';
  @Prop ttsPaused: boolean = false;
  @Prop pendingPromptChatId: string = '';
  @Prop activeConversationId: string = '';
  @Prop pendingPromptLabel: string = '';
  @Prop askQuestionText: string = '';
  @Prop askQuestionOptions: string[] = [];
  @Prop askQuestionPlaceholder: string = '';
  @Prop pendingApprovalTool: string = '';
  @Prop pendingApprovalArgs: string = '';
  @Prop showToolCards: boolean = true;
  @Prop notice: string = '';
  @Prop palette: PaletteTokens = BUILTIN_PALETTES[0].light;
  @Prop composerBgHex: string = '#F8FFFFFF';
  @Prop bubbleStyle: string = 'default';
  @Prop chatBgHex: string = '#FFFFFF';
  @Prop wide: boolean = false;
  @Prop wideSide: boolean = false;
  @Prop hasSidePanel: boolean = false;
  @Prop bottomInset: number = 0;

  @StorageProp('immersiveLightEnabled') immersiveLight: boolean = true;
  @StorageProp('effectiveDarkMode') isDark: boolean = false;
  @StorageProp('windowLeftInsetVp') winLeftInset: number = 0;
  @StorageProp('windowRightInsetVp') winRightInset: number = 0;
  @StorageProp('windowKeyboardHeightVp') winKeyboardHeight: number = 0;
  @StorageProp('reduceMotionEnabled') reduceMotion: boolean = false;

  onClearQuote: () => void = () => {};
  onRemoveAttachment: (idx: number) => void = () => {};
  onToggleInstructionCard: (cardId: string) => void = () => {};
  onOpenModelQuickSheet: () => void = () => {};
  onOpenSearchQuickSheet: () => void = () => {};
  onOpenReasoningSheet: () => void = () => {};
  onOpenChatToolsSheet: () => void = () => {};
  onClearImageGenMode: () => void = () => {};
  onToggleDictation: () => void = () => {};
  onOpenBottomToolsSheet: () => void = () => {};
  onSend: () => void = () => {};
  onStop: () => void = () => {};
  onToggleTtsPause: () => void = () => {};
  onStopTts: () => void = () => {};
  onOpenPendingPromptChat: (chatId: string) => void = () => {};
  onAskAnswerChanged: (v: string) => void = () => {};
  onSubmitAskAnswer: (ans: string) => void = () => {};
  onResolveToolApproval: (choice: 'allow_once' | 'allow_all' | 'deny') => void = () => {};
  onAreaHeightChange: (heightVp: number) => void = () => {};

  private inactiveIconColor(): Resource {
    return ImmersiveMaterialStyle.isActive(this.immersiveLight)
      ? $r('sys.color.icon_secondary')
      : $r('app.color.muted');
  }

  private pillBg(): Resource {
    return ImmersiveMaterialStyle.isActive(this.immersiveLight)
      ? $r('sys.color.comp_background_tertiary')
      : $r('app.color.panel');
  }

  @Builder
  private composerCardContent() {
    if (this.quoteExcerpt.length > 0) {
      Row({ space: 6 }) {
        Text('引用: ' + this.quoteExcerpt).fontSize(12).fontColor($r('app.color.muted'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        Button('×').height(24).fontSize(12).padding(0).backgroundColor(Color.Transparent).fontColor($r('app.color.muted'))
          .onClick(() => { this.onClearQuote(); })
      }.width('100%').padding({ left: 8, right: 4 }).backgroundColor($r('app.color.panel')).borderRadius(8)
        .transition(SystemMotion.inlineBarTransition(this.reduceMotion))
    }
    if (this.attachedList.length) {
      Scroll() {
        Row({ space: 6 }) {
          ForEach(this.attachedList, (att: Attachment, ai: number) => {
            Button(att.name + '  ×').height(28).fontSize(12).backgroundColor($r('app.color.tint'))
              .fontColor($r('app.color.accent')).onClick(() => {
                this.onRemoveAttachment(ai);
              })
          }, (att: Attachment, ai: number) => 'catt-' + ai + '-' + att.name)
        }
      }.scrollable(ScrollDirection.Horizontal).width('100%')
    }
    if (this.showPromptQuickBar) {
      Column({ space: 6 }) {
        if (this.instructionCards.length > 0) {
          Scroll() {
            Row({ space: 6 }) {
              ForEach(this.instructionCards, (card: InstructionCard) => {
                Button((this.activeInstructionIds.includes(card.id) ? '✓ ' : '') + card.title)
                  .height(26).fontSize(11).borderRadius(8)
                  .backgroundColor(this.activeInstructionIds.includes(card.id) ? $r('app.color.accent') : $r('app.color.panel'))
                  .fontColor(this.activeInstructionIds.includes(card.id) ? $r('app.color.on_accent') : $r('app.color.ink'))
                  .onClick(() => { this.onToggleInstructionCard(card.id); })
              }, (card: InstructionCard) => 'ic-' + card.id)
            }
          }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
        }
        if (this.quickPhrases.length > 0) {
          Scroll() {
            Row({ space: 6 }) {
              ForEach(this.quickPhrases, (qp: QuickPhrase) => {
                Button('» ' + qp.title)
                  .height(26).fontSize(11).borderRadius(8)
                  .backgroundColor($r('app.color.tint')).fontColor($r('app.color.accent'))
                  .onClick(() => {
                    this.draft = this.draft.trim().length > 0 ? `${this.draft}\n${qp.content}` : qp.content;
                    SystemMotion.quickAnimate(this.getUIContext(), this.reduceMotion, () => {
                      this.showPromptQuickBar = false;
                    });
                  })
              }, (qp: QuickPhrase) => 'qp-' + qp.id)
            }
          }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%')
        }
      }.width('100%').padding({ bottom: 4 })
        .transition(SystemMotion.inlineBarTransition(this.reduceMotion))
    }

    TextArea({ text: this.draft, placeholder: this.placeholderText })
      .id('composer')
      .width('100%')
      .enabled(!this.working && !this.picking)
      .fontSize(16)
      .fontColor(ImmersiveMaterialStyle.isActive(this.immersiveLight) ? $r('sys.color.font_primary') : $r('app.color.ink'))
      .placeholderColor(ImmersiveMaterialStyle.isActive(this.immersiveLight) ? $r('sys.color.font_secondary') : $r('app.color.muted'))
      .barState(BarState.Auto)
      .constraintSize({ minHeight: 40, maxHeight: 160 })
      .backgroundColor(Color.Transparent)
      .onSubmit((_enterKey: EnterKeyType) => {
        if (this.enterToSend && !this.working && !this.picking && (this.draft.trim().length > 0 || this.attachedList.length > 0)) {
          this.onSend();
        }
      })
      .onChange((v: string) => { this.draft = v; })

    Row({ space: 4 }) {
      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        KelivoAvatarBadge({
          brandId: this.activeBrandId,
          avatarText: '',
          fallbackLetter: this.providerName,
          badgeSize: 20,
          plain: true
        })
      }
      .id('currentModel')
      .width(36)
      .height(36)
      .padding(0)
      .borderRadius(10)
      .accessibilityText('选择模型')
      .enabled(!this.working && !this.picking)
      .backgroundColor(Color.Transparent)
      .onClick(() => { this.onOpenModelQuickSheet(); })

      Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
        SymbolGlyph(this.builtinSearchOn
          ? $r('sys.symbol.magnifyingglass')
          : $r('sys.symbol.globe_badge_message'))
          .fontSize(19)
          .fontColor([(this.builtinSearchOn || this.searchOn)
            ? $r('app.color.accent')
            : this.inactiveIconColor()])
      }
      .id('webSearch')
      .width(36)
      .height(36)
      .padding(0)
      .borderRadius(10)
      .accessibilityText(this.builtinSearchOn
        ? '模型内置搜索已开启'
        : (this.searchOn ? '联网搜索已开启' : '联网搜索'))
      .enabled(!this.working && !this.picking)
      .backgroundColor(Color.Transparent)
      .onClick(() => { this.onOpenSearchQuickSheet(); })

      if (this.reasoningLevelCount > 1) {
        Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          Row({ space: 4 }) {
            Image(reasoningBulbResource(this.reasoningBulbRays))
              .width(this.showReasoningLevelOnButton ? 18 : 20)
              .height(this.showReasoningLevelOnButton ? 18 : 20)
              .objectFit(ImageFit.Contain)
              .fillColor(this.reasoningEffort !== 'off' ? $r('app.color.accent') : this.inactiveIconColor())
            if (this.showReasoningLevelOnButton) {
              Text(this.reasoningLabel)
                .fontSize(11)
                .fontColor(this.reasoningEffort !== 'off' ? $r('app.color.accent') : this.inactiveIconColor())
            }
          }
        }
        .id('reasoningToggle')
        .height(36)
        .constraintSize({ minWidth: 36 })
        .padding(this.showReasoningLevelOnButton ? { left: 6, right: 6 } : 0)
        .borderRadius(10)
        .accessibilityText(`思考深度: ${this.reasoningLabel}`)
        .enabled(!this.working && !this.picking)
        .backgroundColor(Color.Transparent)
        .onClick(() => { this.onOpenReasoningSheet(); })
      }

      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.wrench_and_screwdriver'))
          .fontSize(16)
          .fontColor([this.fullAccessMode ? $r('app.color.accent') : this.inactiveIconColor()])
      }
      .id('chatTools')
      .width(36)
      .height(36)
      .padding(0)
      .accessibilityText('对话工具与工作区')
      .enabled(!this.working && !this.picking)
      .backgroundColor(this.fullAccessMode ? $r('app.color.tint') : Color.Transparent)
      .onClick(() => { this.onOpenChatToolsSheet(); })

      if (this.imageGenMode) {
        Text('绘图')
          .fontSize(11)
          .fontColor($r('app.color.accent'))
          .backgroundColor($r('app.color.tint'))
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(10)
          .onClick(() => { this.onClearImageGenMode(); })
      }

      Blank()

      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.mic'))
          .fontSize(17)
          .fontColor([this.recording ? Color.White : this.inactiveIconColor()])
      }
      .id('dictateBtn')
      .width(34)
      .height(34)
      .padding(0)
      .accessibilityText(this.recording ? '停止录音' : '语音输入')
      .enabled(!this.working && !this.picking)
      .backgroundColor(this.recording ? $r('app.color.warning') : Color.Transparent)
      .onClick(() => { this.onToggleDictation(); })

      Button({ type: ButtonType.Circle }) {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(18)
          .fontColor([ImmersiveMaterialStyle.isActive(this.immersiveLight) ? $r('sys.color.icon_primary') : $r('app.color.ink')])
      }
      .id('plusToolsBtn')
      .width(36)
      .height(36)
      .padding(0)
      .accessibilityText('更多功能')
      .enabled(!this.working && !this.picking)
      .backgroundColor(this.pillBg())
      .onClick(() => { this.onOpenBottomToolsSheet(); })

      Button({ type: ButtonType.Circle }) {
        if (this.working) {
          Rect().width(13).height(13).radius(3).fill($r('app.color.on_accent'))
        } else {
          SymbolGlyph($r('sys.symbol.arrow_up')).fontSize(18).fontColor([$r('app.color.on_accent')])
        }
      }
      .id(this.working ? 'stop' : 'send')
      .width(36)
      .height(36)
      .padding(0)
      .backgroundColor($r('app.color.accent'))
      .accessibilityText(this.working ? this.stopLabel : this.sendLabel)
      .enabled(this.working || (!this.picking && (!!this.draft.trim() || !!this.attachedList.length)))
      .onClick(() => { if (this.working) this.onStop(); else this.onSend(); })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      if (this.readingId) {
        Row({ space: 8 }) {
          Text('🔊 正在语音朗读').fontSize(12).fontWeight(FontWeight.Medium).fontColor($r('app.color.accent')).layoutWeight(1)
          Button(this.ttsPaused ? '继续' : '暂停').height(26).fontSize(11)
            .backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink'))
            .onClick(() => { this.onToggleTtsPause(); })
          Button('停止').height(26).fontSize(11)
            .backgroundColor($r('app.color.surface')).fontColor($r('app.color.warning'))
            .onClick(() => { this.onStopTts(); })
        }.width('94%').constraintSize({ maxWidth: 800 }).padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .borderRadius(12).backgroundColor($r('app.color.tint')).margin({ bottom: 6 })
      }

      if (this.pendingPromptChatId.length > 0 && this.pendingPromptChatId !== this.activeConversationId) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_circle'))
            .fontSize(15)
            .fontColor([$r('app.color.accent')])
          Text(this.pendingPromptLabel)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Button('前往处理')
            .height(26)
            .fontSize(11)
            .borderRadius(13)
            .padding({ left: 10, right: 10 })
            .backgroundColor($r('app.color.accent'))
            .fontColor($r('app.color.on_accent'))
            .onClick(() => { this.onOpenPendingPromptChat(this.pendingPromptChatId); })
        }
        .width('94%')
        .constraintSize({ maxWidth: 800 })
        .padding({ left: 12, right: 10, top: 6, bottom: 6 })
        .borderRadius(12)
        .backgroundColor($r('app.color.tint'))
        .margin({ bottom: 6 })
      }

      if (this.askQuestionText) {
        Column({ space: 8 }) {
          Text('🤖 AI 向您确认：' + this.askQuestionText)
            .fontSize(13).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink'))
          if (this.askQuestionOptions.length > 0) {
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.askQuestionOptions, (opt: string, oi: number) => {
                Button(opt)
                  .height(28).fontSize(12).margin({ right: 6, bottom: 6 }).borderRadius(8)
                  .backgroundColor($r('app.color.tint')).fontColor($r('app.color.accent'))
                  .onClick(() => this.onSubmitAskAnswer(opt))
              }, (opt: string, oi: number) => `ask_${oi}_${opt}`)
            }
          }
          Row({ space: 6 }) {
            TextInput({ text: this.askQuestionAnswer, placeholder: this.askQuestionPlaceholder || '输入回答...' })
              .layoutWeight(1).height(34).fontSize(12).borderRadius(8).backgroundColor($r('app.color.canvas'))
              .onChange((v: string) => {
                this.askQuestionAnswer = v;
                this.onAskAnswerChanged(v);
              })
            Button('提交').height(34).fontSize(12).borderRadius(8)
              .backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
              .onClick(() => this.onSubmitAskAnswer(this.askQuestionAnswer.trim()))
            Button('跳过').height(34).fontSize(12).borderRadius(8)
              .backgroundColor($r('app.color.panel')).fontColor($r('app.color.muted'))
              .onClick(() => this.onSubmitAskAnswer(''))
          }.width('100%')
        }.width('94%').constraintSize({ maxWidth: 800 }).padding(10).borderRadius(12)
          .backgroundColor($r('app.color.surface')).border({ width: 1, color: $r('app.color.accent') })
          .alignItems(HorizontalAlign.Start).margin({ bottom: 6 })
      }

      if (this.pendingApprovalTool && !this.showToolCards) {
        ChatToolApprovalBox({
          toolName: this.pendingApprovalTool,
          argsText: this.pendingApprovalArgs,
          onResolve: (choice: 'allow_once' | 'allow_all' | 'deny') => this.onResolveToolApproval(choice)
        })
      }

      if (this.notice) {
        Text(this.notice).width('100%').padding({ left: 18, right: 18, bottom: 6 }).fontSize(13).fontColor($r('app.color.warning'))
      }

      if (ImmersiveMaterialStyle.isActive(this.immersiveLight)) {
        Column({ space: 6 }) {
          this.composerCardContent()
        }
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .borderRadius(24)
        .backgroundColor(Color.Transparent)
        .width('94%')
        .constraintSize({ maxWidth: 800 })
        .alignItems(HorizontalAlign.Start)
        .systemMaterial(ImmersiveMaterialStyle.composerMaterial(this.palette, this.isDark, true))
      } else {
        Column({ space: 6 }) {
          this.composerCardContent()
        }
        .padding({ left: 10, right: 10, top: 8, bottom: 8 })
        .borderRadius(24)
        .backgroundColor(this.composerBgHex)
        .backgroundBlurStyle(this.immersiveLight || this.bubbleStyle === 'frosted'
          ? BlurStyle.COMPONENT_THICK
          : BlurStyle.NONE)
        .border({ width: 1, color: $r('app.color.line') })
        .width('94%')
        .constraintSize({ maxWidth: 800 })
        .alignItems(HorizontalAlign.Start)
        .systemMaterial(ImmersiveMaterialStyle.composerMaterial(this.palette, this.isDark, false))
      }
    }
    .width('100%')
    .clip(false)
    .alignItems(HorizontalAlign.Center)
    .padding({
      left: this.wide ? 0 : this.winLeftInset,
      right: this.hasSidePanel && this.wideSide ? 0 : this.winRightInset,
      top: 10,
      bottom: this.winKeyboardHeight > 0 ? 8 : Math.max(8, this.bottomInset + 2)
    })
    .linearGradient(this.immersiveLight
      ? {
          direction: GradientDirection.Top,
          colors: [[hexWithAlpha(this.chatBgHex, 'B8'), 0.0], [hexWithAlpha(this.chatBgHex, '00'), 1.0]]
        }
      : undefined)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.onAreaHeightChange(Number(newArea.height));
    })
  }
}
