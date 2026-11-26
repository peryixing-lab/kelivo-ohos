import {
  ApiFamily,
  AppearanceConfig,
  Attachment,
  ChatItemDisplayConfig,
  ChatMessage,
  RegexRule,
  SearchHit,
  ToolCallRecord,
  defaultAppearance,
  defaultChatItemDisplay,
  getAllAttachments
} from '../core/Models';
import { ToolCallGroup, groupToolCallRecords } from '../core/ToolLoop';
import {
  chatToolGroupBadgeText,
  chatToolRecordStatusLabel,
  chatToolRowLabel,
  formatChatCompactTokens,
  formatChatMessageTime
} from '../core/ChatAuxService';
import { resolveBrandIconId, splitAssistantParagraphs } from '../core/BrandIcons';
import { applyRegexRules } from '../core/PromptEngine';
import { hexWithAlpha } from '../core/ImmersiveUtils';
import { SystemMotion } from '../core/SystemMotion';
import { KelivoAvatarBadge } from './KelivoChrome';
import { MessageBody } from './MessageBody';
import { RichPreviewKind } from './RichPreviewSheet';

@Component
export struct ChatToolApprovalBox {
  @Prop toolName: string = '';
  @Prop argsText: string = '';
  onResolve: (choice: 'allow_once' | 'allow_all' | 'deny') => void = () => {};

  build() {
    Column({ space: 6 }) {
      Text('工具执行授权请求：' + this.toolName)
        .fontSize(13).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink'))
      Text(this.argsText).fontFamily('monospace').fontSize(11).fontColor($r('app.color.muted'))
        .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
      Row({ space: 6 }) {
        Button('允许一次').height(28).fontSize(12).backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
          .onClick(() => this.onResolve('allow_once'))
        Button('本对话全部允许').height(28).fontSize(12).backgroundColor($r('app.color.tint')).fontColor($r('app.color.accent'))
          .onClick(() => this.onResolve('allow_all'))
        Button('拒绝').height(28).fontSize(12).backgroundColor($r('app.color.panel')).fontColor($r('app.color.warning'))
          .onClick(() => this.onResolve('deny'))
      }
    }.width('100%').padding(10).alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct ChatReplyActivityCard {
  @Prop messageId: string = '';
  @Prop reasoning: string = '';
  @Prop records: ToolCallRecord[] = [];
  @Prop thinking: boolean = false;
  @Prop durationMs: number = 0;
  @Prop showThinkingCards: boolean = true;
  @Prop showToolCards: boolean = true;
  @Prop enableReasoningMarkdown: boolean = true;
  @Prop enableMathLatex: boolean = true;
  @Prop codeFontSize: number = 13;
  @Prop tintHex: string = '#DCE1FF';
  @Prop isDark: boolean = false;
  @Prop liveMessageId: string = '';
  @Prop working: boolean = false;
  @Prop pendingApprovalTool: string = '';
  @Prop pendingApprovalArgs: string = '';
  @Link expandedReasoning: string;
  @Link expandedToolId: string;
  @StorageProp('reduceMotionEnabled') reduceMotion: boolean = false;

  onPreviewRich: (kind: RichPreviewKind, title: string, code: string) => void = () => {};
  onOpenUrl: (url: string) => void = () => {};
  onViewImage: (url: string, alt: string) => void = () => {};
  onAskDraft: (draftStr: string) => void = () => {};
  onResolveToolApproval: (choice: 'allow_once' | 'allow_all' | 'deny') => void = () => {};

  private toggleReasoning(msgId: string): void {
    const nextId = this.expandedReasoning === msgId ? '' : msgId;
    if (this.reduceMotion) {
      this.expandedReasoning = nextId;
      return;
    }
    SystemMotion.quickAnimate(this.getUIContext(), this.reduceMotion, () => {
      this.expandedReasoning = nextId;
    });
  }

  @Builder
  private toolCallGroupRow(grp: ToolCallGroup, rowId: string, isLive: boolean) {
    Column({ space: 4 }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          Text('•••').fontSize(11).fontColor($r('app.color.muted'))
          Row({ space: 5 }) {
            Text(chatToolRowLabel(grp.name))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.muted'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: '80%' })
            if (grp.count > 1) {
              Text(`×${grp.count}`)
                .fontSize(11)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.muted'))
            }
          }
          .layoutWeight(1)
          .alignItems(VerticalAlign.Center)

          if (chatToolGroupBadgeText(grp).length > 0) {
            Text(chatToolGroupBadgeText(grp))
              .fontSize(11)
              .fontColor((grp.status === 'error' || grp.status === 'denied' || grp.failedCount > 0)
                ? $r('app.color.warning')
                : $r('app.color.accent'))
          }
          SymbolGlyph(this.expandedToolId === rowId ? $r('sys.symbol.chevron_down') : $r('sys.symbol.chevron_right'))
            .fontSize(12).fontColor([$r('app.color.muted')])
        }.width('100%')
      }
      .width('100%').height(36).padding({ left: 12, right: 12 }).backgroundColor(Color.Transparent)
      .onClick(() => { this.expandedToolId = this.expandedToolId === rowId ? '' : rowId; })

      if (this.expandedToolId === rowId) {
        Column({ space: 8 }) {
          ForEach(grp.records, (tc: ToolCallRecord, idx: number) => {
            Column({ space: 4 }) {
              if (grp.count > 1) {
                if (idx > 0) {
                  Divider().color($r('app.color.line')).margin({ bottom: 2 })
                }
                Text(`#${idx + 1} · ${chatToolRecordStatusLabel(tc.status)}${tc.durationMs > 0 ? ' · ' + tc.durationMs + ' ms' : ''}`)
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor((tc.status === 'error' || tc.status === 'denied') ? $r('app.color.warning') : $r('app.color.muted'))
              } else {
                Text(tc.name + (tc.durationMs > 0 ? ' · ' + tc.durationMs + ' ms' : ''))
                  .fontSize(11).fontColor($r('app.color.muted'))
              }
              Text('参数：' + tc.argsJson).fontFamily('monospace').fontSize(11).fontColor($r('app.color.muted'))
                .copyOption(CopyOptions.LocalDevice)
              if (tc.diffText) {
                Text(tc.diffText).fontFamily('monospace').fontSize(11).fontColor($r('app.color.ink'))
                  .padding(6).borderRadius(6).backgroundColor($r('app.color.surface')).copyOption(CopyOptions.LocalDevice)
              }
              if (tc.resultText) {
                Text(tc.resultText.slice(0, 2000)).fontSize(12).fontColor($r('app.color.ink')).copyOption(CopyOptions.LocalDevice)
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }, (tc: ToolCallRecord, idx: number) => `${rowId}-${idx}-${tc.id}-${tc.status}`)
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ left: 12, right: 12, bottom: 8 })
      }
      if (isLive && grp.status === 'pending' && this.pendingApprovalTool === grp.name) {
        ChatToolApprovalBox({
          toolName: this.pendingApprovalTool,
          argsText: this.pendingApprovalArgs,
          onResolve: (choice: 'allow_once' | 'allow_all' | 'deny') => this.onResolveToolApproval(choice)
        })
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      if ((this.reasoning && this.showThinkingCards) || (this.records.length && this.showToolCards)) {
        Column() {
          if (this.reasoning && this.showThinkingCards) {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.lightbulb')).fontSize(15).fontColor([$r('app.color.accent')])
                Text(this.thinking ? '正在思考' : '深度思考').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink'))
                if (!this.thinking && this.durationMs > 0) {
                  Text('(' + (this.durationMs / 1000).toFixed(1) + 's)').fontSize(12).fontColor($r('app.color.muted'))
                }
                Blank().layoutWeight(1)
                SymbolGlyph($r('sys.symbol.chevron_down'))
                  .fontSize(12).fontColor([$r('app.color.muted')])
                  .rotate({ angle: this.expandedReasoning === this.messageId ? 180 : 0 })
              }.width('100%')
            }
            .width('100%').height(36).padding({ left: 12, right: 12 }).backgroundColor(Color.Transparent)
            .accessibilityText(this.expandedReasoning === this.messageId ? '收起思考过程' : '展开思考过程')
            .onClick(() => this.toggleReasoning(this.messageId))

            if (this.expandedReasoning === this.messageId) {
              Column() {
                if (!this.thinking && this.enableReasoningMarkdown) {
                  MessageBody({
                    source: this.reasoning,
                    bodyFontSize: 13,
                    codeFontSize: Math.max(11, this.codeFontSize - 1),
                    enableMarkdown: true,
                    enableMathLatex: this.enableMathLatex,
                    onPreviewRich: (kind: RichPreviewKind, title: string, code: string) => this.onPreviewRich(kind, title, code),
                    onOpenUrl: (url: string) => { this.onOpenUrl(url); },
                    onViewImage: (url: string, alt: string) => this.onViewImage(url, alt || '图片'),
                    onAskDraft: (draftStr: string) => { this.onAskDraft(draftStr); }
                  })
                } else {
                  Text(this.reasoning).fontSize(13).lineHeight(20).fontColor($r('app.color.muted'))
                    .copyOption(CopyOptions.LocalDevice).width('100%')
                }
              }.width('100%').padding({ left: 12, right: 12, bottom: 8 })
                .transition(SystemMotion.reasoningRevealTransition(this.reduceMotion))
            }
          }
          if (this.showToolCards) {
            ForEach(
              groupToolCallRecords(this.records),
              (grp: ToolCallGroup) => {
                this.toolCallGroupRow(grp, this.messageId + '/' + grp.name, this.messageId === this.liveMessageId && this.working);
              },
              (grp: ToolCallGroup) => `${this.messageId}/${grp.name}/${grp.count}/${grp.status}/${grp.failedCount}`
            )
          }
        }.width('100%').padding({ top: 2, bottom: 2 }).borderRadius(16)
          .clip(true)
          .backgroundColor(hexWithAlpha(this.tintHex, this.isDark ? '80' : '60'))
      }
    }
    .width('100%')
  }
}

@Component
export struct ChatMessageRowView {
  @Prop msg: ChatMessage = { id: '', role: 'user', text: '', model: '' };
  @Prop msgIdx: number = 0;
  @Prop multiSelectMode: boolean = false;
  @Prop isSelected: boolean = false;
  @Prop working: boolean = false;
  @Prop readingId: string = '';
  @Prop userName: string = '用户';
  @Prop displayCfg: ChatItemDisplayConfig = defaultChatItemDisplay();
  @Prop appearance: AppearanceConfig = defaultAppearance();
  @Prop useAssistantAvatar: boolean = false;
  @Prop useAssistantName: boolean = false;
  @Prop personaName: string = '';
  @Prop personaAvatar: string = '';
  @Prop personaRegexRules: RegexRule[] = [];
  @Prop providerName: string = '';
  @Prop providerFamily: ApiFamily = 'openai';
  @Prop surfaceHex: string = '#FFFFFF';
  @Prop tintHex: string = '#DCE1FF';
  @Prop isDark: boolean = false;
  @Prop liveMessageId: string = '';
  @Prop pendingApprovalTool: string = '';
  @Prop pendingApprovalArgs: string = '';

  @Link expandedReasoning: string;
  @Link expandedToolId: string;
  @Link expandedSources: string;
  @Link expandedLongMsgIds: string[];

  onToggleSelect: (msgId: string) => void = () => {};
  onCopyText: (text: string) => void = () => {};
  onRegenerate: (msgId: string) => void = () => {};
  onNarrate: (msg: ChatMessage) => void = () => {};
  onTranslate: (msgId: string) => void = () => {};
  onOpenActionSheet: (msg: ChatMessage) => void = () => {};
  onSwitchVersion: (msgId: string, delta: number) => void = () => {};
  onStartEdit: (msg: ChatMessage) => void = () => {};
  onPreviewRich: (kind: RichPreviewKind, title: string, code: string) => void = () => {};
  onOpenUrl: (url: string) => void = () => {};
  onViewImage: (url: string, alt: string) => void = () => {};
  onAskDraft: (draftStr: string) => void = () => {};
  onResolveToolApproval: (choice: 'allow_once' | 'allow_all' | 'deny') => void = () => {};

  private bodyTextSize(): number {
    return Math.round(16 * (this.appearance.fontScale || 1.0));
  }

  private codeTextSize(): number {
    return this.appearance.codeFontSize || 13;
  }

  private bubbleRadiusVal(): number {
    return this.appearance.bubbleRadius || 18;
  }

  private assistantParagraphs(): string[] {
    const full = applyRegexRules(this.msg.text, this.personaRegexRules, 'display');
    if (this.appearance.splitParagraphsIntoBubbles) {
      const parts = splitAssistantParagraphs(full);
      if (parts.length > 0) return parts;
    }
    return full ? [full] : [];
  }

  private assistantBubbleBg(): ResourceColor {
    const st = this.appearance.bubbleStyle;
    if (st === 'frosted') {
      return hexWithAlpha(this.surfaceHex, this.isDark ? '90' : 'B8');
    }
    if (st === 'solid') {
      return this.surfaceHex;
    }
    return Color.Transparent;
  }

  private userBubbleBg(): ResourceColor {
    const st = this.appearance.bubbleStyle;
    if (st === 'frosted') {
      return hexWithAlpha(this.tintHex, this.isDark ? 'A8' : 'C0');
    }
    return $r('app.color.tint');
  }

  private modelHeaderLabel(): string {
    const name = this.msg.model || '助手';
    if (this.displayCfg.showProviderAfterModelName && this.msg.model) {
      return `${name} (${this.providerName})`;
    }
    return name;
  }

  private versionLabelText(): string {
    const total = this.msg.versions?.length || 1;
    const cur = (this.msg.activeVersion ?? (total - 1)) + 1;
    return `${cur}/${total}`;
  }

  private activeVersionCount(): number {
    return this.msg.versions?.length || 1;
  }

  private canPrevVersion(): boolean {
    const cur = this.msg.activeVersion ?? ((this.msg.versions?.length || 1) - 1);
    return cur > 0;
  }

  private canNextVersion(): boolean {
    const total = this.msg.versions?.length || 1;
    const cur = this.msg.activeVersion ?? (total - 1);
    return cur < total - 1;
  }

  private imageSrcForAttachment(att: Attachment): string {
    return att.data ? 'data:' + att.mime + ';base64,' + att.data : (att.filePath ? 'file://' + att.filePath : '');
  }

  @Builder
  private msgActionIcon(
    symbol: Resource,
    label: string,
    lockWhileWorking: boolean,
    idStr: string,
    action: () => void
  ) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(symbol)
        .fontSize(17)
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)
        .fontColor([$r('app.color.muted')])
    }
    .id(idStr)
    .width(32)
    .height(32)
    .padding(0)
    .enabled(!(lockWhileWorking && this.working))
    .opacity(lockWhileWorking && this.working ? 0.38 : 1)
    .backgroundColor(Color.Transparent)
    .accessibilityText(label)
    .onClick(action)
  }

  @Builder
  private msgMoreDotsBtn(idStr: string, action: () => void) {
    Button({ type: ButtonType.Circle }) {
      Row({ space: 3 }) {
        Column().width(3.5).height(3.5).borderRadius(2).backgroundColor($r('app.color.muted'))
        Column().width(3.5).height(3.5).borderRadius(2).backgroundColor($r('app.color.muted'))
        Column().width(3.5).height(3.5).borderRadius(2).backgroundColor($r('app.color.muted'))
      }
      .alignItems(VerticalAlign.Center)
    }
    .id(idStr)
    .width(32)
    .height(32)
    .padding(0)
    .backgroundColor(Color.Transparent)
    .accessibilityText('更多操作')
    .onClick(action)
  }

  build() {
    Column({ space: 6 }) {
      if (this.multiSelectMode) {
        Row({ space: 6 }) {
          Button(this.isSelected ? '☑ 已选中' : '☐ 选择此消息')
            .height(26).fontSize(11)
            .backgroundColor(this.isSelected ? $r('app.color.accent') : $r('app.color.panel'))
            .fontColor(this.isSelected ? $r('app.color.on_accent') : $r('app.color.ink'))
            .onClick(() => this.onToggleSelect(this.msg.id))
        }.width('100%')
      }

      if (this.msg.role === 'assistant') {
        if (this.displayCfg.showModelIcon || this.displayCfg.showModelName ||
          this.displayCfg.showModelTimestamp || this.msg.isSummary) {
          Row({ space: 8 }) {
            if (this.displayCfg.showModelIcon) {
              KelivoAvatarBadge({
                brandId: this.useAssistantAvatar
                  ? ''
                  : resolveBrandIconId(`${this.msg.model || ''} ${this.providerName}`, this.providerFamily),
                avatarText: this.useAssistantAvatar ? this.personaAvatar : '',
                fallbackLetter: this.useAssistantName ? this.personaName : (this.msg.model || this.providerName),
                badgeSize: 22
              })
            }
            if (this.displayCfg.showModelName) {
              Text(this.useAssistantName ? this.personaName : this.modelHeaderLabel())
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.ink'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            if (this.msg.isSummary) {
              Text('摘要节点')
                .fontSize(11)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .borderRadius(6)
                .backgroundColor($r('app.color.tint'))
                .fontColor($r('app.color.accent'))
            }
            if (this.displayCfg.showModelTimestamp && formatChatMessageTime(this.msg.createdAt).length > 0) {
              Text(formatChatMessageTime(this.msg.createdAt))
                .fontSize(11)
                .fontColor($r('app.color.muted'))
            }
          }
          .alignItems(VerticalAlign.Center)
          .width('100%')
        }

        ChatReplyActivityCard({
          messageId: this.msg.id,
          reasoning: this.msg.reasoning || '',
          records: this.msg.toolCalls || [],
          thinking: false,
          durationMs: this.msg.reasoningDurationMs || 0,
          showThinkingCards: this.displayCfg.showThinkingCards,
          showToolCards: this.displayCfg.showToolCards,
          enableReasoningMarkdown: this.appearance.enableReasoningMarkdown !== false,
          enableMathLatex: this.appearance.enableMathLatex !== false,
          codeFontSize: this.codeTextSize(),
          tintHex: this.tintHex,
          isDark: this.isDark,
          liveMessageId: this.liveMessageId,
          working: this.working,
          pendingApprovalTool: this.pendingApprovalTool,
          pendingApprovalArgs: this.pendingApprovalArgs,
          expandedReasoning: this.expandedReasoning,
          expandedToolId: this.expandedToolId,
          onPreviewRich: (kind: RichPreviewKind, title: string, code: string) => this.onPreviewRich(kind, title, code),
          onOpenUrl: (url: string) => this.onOpenUrl(url),
          onViewImage: (url: string, alt: string) => this.onViewImage(url, alt),
          onAskDraft: (draftStr: string) => this.onAskDraft(draftStr),
          onResolveToolApproval: (choice: 'allow_once' | 'allow_all' | 'deny') => this.onResolveToolApproval(choice)
        })

        ForEach(this.assistantParagraphs(), (para: string, pi: number) => {
          Column() {
            MessageBody({
              source: para,
              bodyFontSize: this.bodyTextSize(),
              codeFontSize: this.codeTextSize(),
              enableMarkdown: this.appearance.enableAssistantMarkdown !== false,
              enableMathLatex: this.appearance.enableMathLatex !== false,
              onPreviewRich: (kind: RichPreviewKind, title: string, code: string) => this.onPreviewRich(kind, title, code),
              onOpenUrl: (url: string) => { this.onOpenUrl(url); },
              onViewImage: (url: string, alt: string) => this.onViewImage(url, alt || '图片'),
              onAskDraft: (draftStr: string) => { this.onAskDraft(draftStr); }
            })
          }
          .width(this.appearance.fitAssistantBubble ? undefined : '100%')
          .constraintSize(this.appearance.fitAssistantBubble ? { maxWidth: '92%' } : undefined)
          .alignItems(HorizontalAlign.Start)
          .padding(this.appearance.bubbleStyle === 'default' && !this.appearance.splitParagraphsIntoBubbles
            ? 0
            : { left: 12, right: 12, top: 10, bottom: 10 })
          .borderRadius(this.bubbleRadiusVal())
          .backgroundColor(this.appearance.bubbleStyle === 'default'
            ? (this.appearance.splitParagraphsIntoBubbles ? $r('app.color.surface') : Color.Transparent)
            : this.assistantBubbleBg())
          .backgroundBlurStyle(this.appearance.bubbleStyle === 'frosted' ? BlurStyle.COMPONENT_THICK : BlurStyle.NONE)
        }, (para: string, pi: number) => `${this.msg.id}-${this.versionLabelText()}-p-${pi}-${para.length}-${this.appearance.bubbleStyle}-${this.appearance.fitAssistantBubble}`)

        if (this.msg.sources?.length) {
          Button('搜索来源 · ' + this.msg.sources.length)
            .type(ButtonType.Normal)
            .height(28)
            .fontSize(12)
            .borderRadius(14)
            .padding({ left: 10, right: 10 })
            .fontColor($r('app.color.accent'))
            .backgroundColor($r('app.color.tint'))
            .onClick(() => { this.expandedSources = this.expandedSources === this.msg.id ? '' : this.msg.id; })
          if (this.expandedSources === this.msg.id) {
            Column({ space: 6 }) {
              ForEach(this.msg.sources, (hit: SearchHit, i: number) => {
                Column({ space: 2 }) {
                  Text(`[${i + 1}] ${hit.title || hit.url}`)
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.ink'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(hit.url)
                    .fontSize(11)
                    .fontColor($r('app.color.accent'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
                .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                .borderRadius(8)
                .backgroundColor($r('app.color.panel'))
                .onClick(() => { this.onOpenUrl(hit.url); })
              }, (hit: SearchHit, i: number) => `${this.msg.id}-src-${i}-${hit.url}`)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
        }
        if (this.msg.generatedImages?.length && this.displayCfg.showFilesBelowReplies) {
          Row({ space: 8 }) {
            ForEach(this.msg.generatedImages, (imgAtt: Attachment, ii: number) => {
              Image(this.imageSrcForAttachment(imgAtt)).width(160).height(160).objectFit(ImageFit.Cover).borderRadius(12)
                .onClick(() => this.onViewImage(this.imageSrcForAttachment(imgAtt), imgAtt.name))
            }, (imgAtt: Attachment, ii: number) => this.msg.id + '-gi-' + ii)
          }
        }
        if (this.msg.translation) {
          Column({ space: 4 }) {
            Text('译文').fontSize(11).fontWeight(FontWeight.Bold).fontColor($r('app.color.accent'))
            Text(this.msg.translation).fontSize(14).lineHeight(22).fontColor($r('app.color.ink')).copyOption(CopyOptions.LocalDevice)
          }.width('100%').padding(10).borderRadius(10).backgroundColor($r('app.color.panel')).alignItems(HorizontalAlign.Start)
        }

        Row({ space: 2 }) {
          this.msgActionIcon(
            $r('sys.symbol.rectangle_on_rectangle'),
            '复制',
            false,
            `msgCopy-${this.msgIdx}`,
            () => { this.onCopyText(this.msg.text); }
          )
          this.msgActionIcon(
            $r('sys.symbol.arrow_2_circlepath'),
            '重新生成',
            true,
            `msgRegen-${this.msgIdx}`,
            () => { this.onRegenerate(this.msg.id); }
          )
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph(this.readingId === this.msg.id ? $r('sys.symbol.speaker_slash') : $r('sys.symbol.speaker_wave_2'))
              .fontSize(17)
              .renderingStrategy(SymbolRenderingStrategy.SINGLE)
              .fontColor([this.readingId === this.msg.id ? $r('app.color.accent') : $r('app.color.muted')])
          }
          .id(`msgSpeak-${this.msgIdx}`)
          .width(32)
          .height(32)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText(this.readingId === this.msg.id ? '停止朗读' : '朗读')
          .onClick(() => { this.onNarrate(this.msg); })

          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.translate'))
              .fontSize(17)
              .renderingStrategy(SymbolRenderingStrategy.SINGLE)
              .fontColor([this.msg.translation ? $r('app.color.accent') : $r('app.color.muted')])
          }
          .id(`msgTrans-${this.msgIdx}`)
          .width(32)
          .height(32)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText(this.msg.translation ? '隐藏译文' : '翻译')
          .onClick(() => { this.onTranslate(this.msg.id); })

          this.msgMoreDotsBtn(`msgMore-${this.msgIdx}`, () => { this.onOpenActionSheet(this.msg); })
          if (this.activeVersionCount() > 1) {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.chevron_left'))
                .fontSize(15)
                .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                .fontColor([this.canPrevVersion() ? $r('app.color.muted') : $r('app.color.line')])
            }
            .id(`msgVerPrev-${this.msgIdx}`)
            .width(26)
            .height(28)
            .padding(0)
            .backgroundColor(Color.Transparent)
            .enabled(this.canPrevVersion())
            .accessibilityText('上一版本')
            .onClick(() => { this.onSwitchVersion(this.msg.id, -1); })

            Text(this.versionLabelText())
              .id(`msgVerLabel-${this.msgIdx}`)
              .fontSize(12)
              .fontColor($r('app.color.muted'))
              .padding({ left: 2, right: 2 })

            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.chevron_right'))
                .fontSize(15)
                .renderingStrategy(SymbolRenderingStrategy.SINGLE)
                .fontColor([this.canNextVersion() ? $r('app.color.muted') : $r('app.color.line')])
            }
            .id(`msgVerNext-${this.msgIdx}`)
            .width(26)
            .height(28)
            .padding(0)
            .backgroundColor(Color.Transparent)
            .enabled(this.canNextVersion())
            .accessibilityText('下一版本')
            .onClick(() => { this.onSwitchVersion(this.msg.id, 1); })
          }
          Blank()
          if (this.displayCfg.showTokenStats && formatChatCompactTokens(this.msg).length > 0) {
            Text(formatChatCompactTokens(this.msg))
              .fontSize(11)
              .fontColor($r('app.color.muted'))
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ top: 2 })
      } else {
        if (this.displayCfg.showUserAvatar || this.displayCfg.showUserName ||
          (this.displayCfg.showUserTimestamp && formatChatMessageTime(this.msg.createdAt).length > 0)) {
          Row({ space: 6 }) {
            if (this.displayCfg.showUserTimestamp && formatChatMessageTime(this.msg.createdAt).length > 0) {
              Text(formatChatMessageTime(this.msg.createdAt))
                .fontSize(11)
                .fontColor($r('app.color.muted'))
            }
            if (this.displayCfg.showUserName) {
              Text(this.userName || '用户')
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.muted'))
            }
            if (this.displayCfg.showUserAvatar) {
              KelivoAvatarBadge({
                brandId: '',
                avatarText: '',
                fallbackLetter: this.userName || '用户',
                badgeSize: 20
              })
            }
          }
          .justifyContent(FlexAlign.End)
          .width('100%')
        }
        Column({ space: 6 }) {
          if (this.msg.quote?.excerpt) {
            Text('❝ ' + this.msg.quote.excerpt).fontSize(12).fontColor($r('app.color.muted'))
              .padding(6).borderRadius(8).backgroundColor($r('app.color.surface'))
          }
          if (this.msg.sources?.length) {
            Button('网页来源 · ' + this.msg.sources.length).height(30).fontSize(12).fontColor($r('app.color.accent'))
              .backgroundColor($r('app.color.surface')).onClick(() => { this.expandedSources = this.expandedSources === this.msg.id ? '' : this.msg.id; })
            if (this.expandedSources === this.msg.id) {
              ForEach(this.msg.sources, (hit: SearchHit, i: number) => {
                Text('[' + (i + 1) + '] ' + hit.title + '\n' + hit.url).fontSize(12).fontColor($r('app.color.muted'))
                  .copyOption(CopyOptions.LocalDevice)
              }, (hit: SearchHit, i: number) => i + hit.url)
            }
          }
          ForEach(getAllAttachments(this.msg), (att: Attachment, ai: number) => {
            if (att.mime.startsWith('image/') && (att.data || att.filePath)) {
              Image(this.imageSrcForAttachment(att)).width(160).height(120).objectFit(ImageFit.Cover).borderRadius(10)
                .onClick(() => this.onViewImage(this.imageSrcForAttachment(att), att.name))
            } else {
              Text('附件 · ' + att.name).fontSize(12).fontColor($r('app.color.muted'))
            }
          }, (att: Attachment, ai: number) => this.msg.id + '-att-' + ai + '-' + att.name)
          if (this.msg.text) {
            if ((this.appearance.collapseLongUserChars || 0) > 0 &&
              this.msg.text.length > (this.appearance.collapseLongUserChars || 0) &&
              !this.expandedLongMsgIds.includes(this.msg.id)) {
              Column({ space: 4 }) {
                Text(this.msg.text.slice(0, this.appearance.collapseLongUserChars) + '...')
                  .fontSize(this.bodyTextSize())
                  .lineHeight(Math.round(this.bodyTextSize() * 1.48))
                  .fontColor($r('app.color.ink'))
                  .copyOption(CopyOptions.LocalDevice)
                Text(`展开全文 (${this.msg.text.length} 字)`)
                  .fontSize(12)
                  .fontColor($r('app.color.accent'))
                  .onClick(() => {
                    this.expandedLongMsgIds = [...this.expandedLongMsgIds, this.msg.id];
                  })
              }
              .alignItems(HorizontalAlign.Start)
            } else if (this.appearance.enableUserMarkdown !== false &&
              /(`|\*\*|#|\[.*\]\(|\n[-*>]\s)/.test(this.msg.text)) {
              MessageBody({
                source: this.msg.text,
                bodyFontSize: this.bodyTextSize(),
                codeFontSize: this.codeTextSize(),
                enableMarkdown: true,
                enableMathLatex: this.appearance.enableMathLatex !== false,
                onPreviewRich: (kind: RichPreviewKind, title: string, code: string) => this.onPreviewRich(kind, title, code),
                onOpenUrl: (url: string) => { this.onOpenUrl(url); },
                onViewImage: (url: string, alt: string) => this.onViewImage(url, alt || '图片'),
                onAskDraft: (draftStr: string) => { this.onAskDraft(draftStr); }
              })
            } else {
              Text(this.msg.text)
                .fontSize(this.bodyTextSize())
                .lineHeight(Math.round(this.bodyTextSize() * 1.48))
                .fontColor($r('app.color.ink'))
                .copyOption(CopyOptions.LocalDevice)
            }
          }
        }
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .constraintSize({ maxWidth: '88%' })
        .borderRadius(this.bubbleRadiusVal())
        .backgroundColor(this.userBubbleBg())
        .backgroundBlurStyle(this.appearance.bubbleStyle === 'frosted' ? BlurStyle.COMPONENT_THICK : BlurStyle.NONE)
        .alignItems(HorizontalAlign.Start)

        if (this.displayCfg.showUserMessageActions) {
          Row({ space: 4 }) {
            this.msgActionIcon(
              $r('sys.symbol.rectangle_on_rectangle'),
              '复制',
              false,
              `userCopy-${this.msgIdx}`,
              () => { this.onCopyText(this.msg.text); }
            )
            this.msgActionIcon(
              $r('sys.symbol.arrow_2_circlepath'),
              '重新生成',
              true,
              `userRegen-${this.msgIdx}`,
              () => { this.onRegenerate(this.msg.id); }
            )
            this.msgActionIcon(
              $r('sys.symbol.pencil_line'),
              '编辑',
              true,
              `userEdit-${this.msgIdx}`,
              () => { this.onStartEdit(this.msg); }
            )
            this.msgMoreDotsBtn(`userMore-${this.msgIdx}`, () => { this.onOpenActionSheet(this.msg); })
          }
          .padding({ top: 2, right: 2 })
        }
      }
    }.alignItems(this.msg.role === 'user' ? HorizontalAlign.End : HorizontalAlign.Start).width('100%')
  }
}
