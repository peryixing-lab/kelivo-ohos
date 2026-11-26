import { BrowserAgentManager } from '../core/BrowserAgent';
import { BrowserBookmark, ChatMessage, EnvVar, LocalWorkspace } from '../core/Models';
import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { hexWithAlpha } from '../core/ImmersiveUtils';
import { SystemMotion } from '../core/SystemMotion';
import { BUILTIN_PALETTES, PaletteTokens } from '../core/ThemeManager';
import { BrowserPanel } from './BrowserPanel';
import { ChatListSheet } from './ChatListSheet';
import { WorkspacePanel } from './WorkspacePanel';

@Component
export struct ChatScrollNavOverlay {
  @Prop hasSidePanel: boolean = false;
  @Prop wideSide: boolean = false;
  @Prop composerBarHeightVp: number = 0;
  @Prop surfaceHex: string = '#FFFFFF';
  @StorageProp('effectiveDarkMode') isDark: boolean = false;
  @StorageProp('windowRightInsetVp') winRightInset: number = 0;
  @StorageProp('reduceMotionEnabled') reduceMotion: boolean = false;

  onJumpTop: () => void = () => {};
  onJumpPrev: () => void = () => {};
  onJumpNext: () => void = () => {};
  onJumpBottom: () => void = () => {};

  @Builder
  private navButton(symbolRes: Resource, rotate180: boolean, a11yText: string, onTap: () => void) {
    Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
      SymbolGlyph(symbolRes)
        .fontSize(13)
        .fontColor([$r('app.color.muted')])
        .rotate({ angle: rotate180 ? 180 : 0 })
    }
    .width(30)
    .height(30)
    .padding(0)
    .accessibilityText(a11yText)
    .backgroundColor(hexWithAlpha(this.surfaceHex, this.isDark ? '98' : 'A8'))
    .backgroundBlurStyle(BlurStyle.Thin)
    .border({ width: 0.5, color: $r('app.color.line') })
    .shadow({
      radius: 6,
      color: this.isDark ? '#24000000' : '#0C000000',
      offsetX: 0,
      offsetY: 1
    })
    .opacity(0.82)
    .onClick(() => { onTap(); })
  }

  build() {
    Row() {
      Column({ space: 6 }) {
        this.navButton($r('sys.symbol.chevron_up_2'), false, '跳转到顶部对话', () => { this.onJumpTop(); })
        this.navButton($r('sys.symbol.chevron_up'), false, '跳转到上一条对话', () => { this.onJumpPrev(); })
        this.navButton($r('sys.symbol.chevron_down'), false, '跳转到下一条对话', () => { this.onJumpNext(); })
        this.navButton($r('sys.symbol.chevron_up_2'), true, '跳转到最新对话', () => { this.onJumpBottom(); })
      }
      .margin({
        right: (this.hasSidePanel && this.wideSide ? 0 : this.winRightInset) + 10,
        bottom: this.composerBarHeightVp + 4
      })
    }
    .width('100%')
    .justifyContent(FlexAlign.End)
    .hitTestBehavior(HitTestMode.None)
    .transition(SystemMotion.endSlideTransition(this.reduceMotion))
  }
}

@Component
export struct ChatMessageActionSheet {
  @Prop hasTarget: boolean = false;
  @Prop isAssistant: boolean = false;
  @Prop hasMultiVersions: boolean = false;
  @Prop bottomInset: number = 0;

  onAction: (actionKey: string) => void = () => {};

  @Builder
  private sheetActionRow(
    symbol: Resource,
    label: string,
    isDanger: boolean,
    idStr: string,
    actionKey: string
  ) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 16 }) {
        SymbolGlyph(symbol)
          .fontSize(20)
          .fontColor([isDanger ? $r('app.color.warning') : $r('app.color.ink')])
        Text(label)
          .fontSize(16)
          .fontColor(isDanger ? $r('app.color.warning') : $r('app.color.ink'))
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .id(idStr)
    .width('100%')
    .height(52)
    .padding({ left: 22, right: 22 })
    .backgroundColor(Color.Transparent)
    .onClick(() => { this.onAction(actionKey); })
  }

  build() {
    Column({ space: 2 }) {
      if (this.hasTarget) {
        this.sheetActionRow($r('sys.symbol.textformat'), '选择复制', false, 'sheetSelectCopy', 'select_copy')
        this.sheetActionRow($r('sys.symbol.book'), '网页视图渲染', false, 'sheetWebRender', 'web_render')
        if (this.isAssistant) {
          this.sheetActionRow($r('sys.symbol.pencil_line'), '编辑', false, 'sheetEdit', 'edit')
        }
        this.sheetActionRow($r('sys.symbol.share'), '分享', false, 'sheetShare', 'share')
        this.sheetActionRow($r('sys.symbol.checkmark_square'), '选择消息', false, 'sheetSelectMessages', 'select_messages')
        this.sheetActionRow($r('sys.symbol.arrow_triangle_divide'), '创建分支', false, 'sheetFork', 'fork')
        this.sheetActionRow($r('sys.symbol.trash'), '删除本版本', true, 'sheetDeleteVersion', 'delete_version')
        if (this.hasMultiVersions) {
          this.sheetActionRow($r('sys.symbol.trash'), '删除全部版本', true, 'sheetDeleteAll', 'delete_all')
        }
      }
    }
    .width('100%')
    .padding({ top: 6, bottom: Math.max(16, this.bottomInset + 8) })
    .backgroundColor(Color.Transparent)
  }
}

@Component
export struct ChatMiniMapSheet {
  @Prop messages: ChatMessage[] = [];
  @Prop palette: PaletteTokens = BUILTIN_PALETTES[0].light;
  @StorageProp('effectiveDarkMode') isDark: boolean = false;
  @StorageProp('immersiveLightEnabled') immersiveLight: boolean = true;

  onClose: () => void = () => {};
  onJumpTop: () => void = () => {};
  onJumpBottom: () => void = () => {};
  onJumpIndex: (idx: number) => void = () => {};

  @Builder
  private miniMapControls() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.map'))
        .fontSize(17)
        .fontColor([$r('app.color.accent')])
      Text('共 ' + this.messages.length + ' 条消息 · 点击跳转')
        .fontSize(13)
        .fontColor($r('app.color.muted'))
        .layoutWeight(1)
      if (this.messages.length > 1) {
        Button('顶部')
          .type(ButtonType.Normal)
          .height(26)
          .fontSize(11)
          .padding({ left: 10, right: 10 })
          .borderRadius(13)
          .backgroundColor($r('app.color.tint'))
          .fontColor($r('app.color.accent'))
          .onClick(() => { this.onJumpTop(); })
        Button('最新')
          .type(ButtonType.Normal)
          .height(26)
          .fontSize(11)
          .padding({ left: 10, right: 10 })
          .borderRadius(13)
          .backgroundColor($r('app.color.tint'))
          .fontColor($r('app.color.accent'))
          .onClick(() => { this.onJumpBottom(); })
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .borderRadius(14)
    .backgroundColor(ImmersiveMaterialStyle.sheetCardBackground(this.immersiveLight))
  }

  @Builder
  private miniMapItems() {
    if (this.messages.length === 0) {
      Column({ space: 6 }) {
        Text('当前对话暂无消息')
          .fontSize(14)
          .fontColor($r('app.color.muted'))
      }
      .width('100%')
      .padding({ top: 24, bottom: 24 })
      .alignItems(HorizontalAlign.Center)
      .borderRadius(14)
      .backgroundColor(ImmersiveMaterialStyle.sheetCardBackground(this.immersiveLight))
    } else {
      Column({ space: 6 }) {
        ForEach(this.messages, (m: ChatMessage, idx: number) => {
          Row({ space: 10 }) {
            Text('#' + (idx + 1) + (m.role === 'user' ? ' 问' : ' 答'))
              .fontSize(12)
              .fontWeight(FontWeight.Bold)
              .fontColor(m.role === 'user' ? $r('app.color.accent') : $r('app.color.muted'))
              .width(54)
            Text(m.text.replace(/\s+/g, ' ').slice(0, 80) || '[空/附件]')
              .fontSize(13)
              .fontColor($r('app.color.ink'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .borderRadius(12)
          .backgroundColor(ImmersiveMaterialStyle.sheetCardBackground(this.immersiveLight))
          .onClick(() => { this.onJumpIndex(idx); })
        }, (m: ChatMessage, idx: number) => 'mm-' + idx + '-' + m.id)
      }
      .width('100%')
      .padding({ top: 2, bottom: 4 })
    }
  }

  build() {
    ChatListSheet({
      heading: '对话大纲',
      palette: this.palette,
      isDark: this.isDark,
      immersiveLightEnabled: this.immersiveLight,
      onClose: () => { this.onClose(); },
      controls: () => { this.miniMapControls(); },
      items: () => { this.miniMapItems(); }
    })
  }
}

@Component
export struct ChatEditMessageModal {
  @Link editingMsgText: string;
  @Prop canvasHex: string = '#FFFFFF';
  @Prop bottomInset: number = 0;

  @StorageProp('windowTopInsetVp') winTopInset: number = 0;
  @StorageProp('windowLeftInsetVp') winLeftInset: number = 0;
  @StorageProp('windowRightInsetVp') winRightInset: number = 0;
  @StorageProp('reduceMotionEnabled') reduceMotion: boolean = false;

  onCancel: () => void = () => {};
  onSaveOnly: () => void = () => {};
  onSaveAndRerun: () => void = () => {};

  build() {
    Column({ space: 12 }) {
      Row() {
        Button('取消').backgroundColor(Color.Transparent).fontColor($r('app.color.muted'))
          .onClick(() => { this.onCancel(); })
        Text('编辑消息').fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink')).layoutWeight(1)
        Button('仅保存').height(32).fontSize(12).backgroundColor($r('app.color.panel')).fontColor($r('app.color.ink'))
          .onClick(() => { this.onSaveOnly(); })
        Button('保存并重发').height(32).fontSize(12).backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
          .margin({ left: 6 }).onClick(() => { this.onSaveAndRerun(); })
      }.width('100%').padding(12)
      TextArea({ text: this.editingMsgText }).layoutWeight(1).width('94%').fontSize(15)
        .onChange((v: string) => { this.editingMsgText = v; })
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.winTopInset, bottom: Math.max(16, this.bottomInset + 8), left: this.winLeftInset, right: this.winRightInset })
    .backgroundColor(this.canvasHex)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .transition(SystemMotion.overlayModalTransition(this.reduceMotion))
  }
}

@Component
export struct ChatSelectCopyModal {
  @Prop selectCopyText: string = '';
  @Prop canvasHex: string = '#FFFFFF';
  @Prop bottomInset: number = 0;

  @StorageProp('windowTopInsetVp') winTopInset: number = 0;
  @StorageProp('windowLeftInsetVp') winLeftInset: number = 0;
  @StorageProp('windowRightInsetVp') winRightInset: number = 0;
  @StorageProp('reduceMotionEnabled') reduceMotion: boolean = false;

  onCopyAll: () => void = () => {};
  onClose: () => void = () => {};

  build() {
    Column({ space: 12 }) {
      Row() {
        Text('自由选词复制').fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink')).layoutWeight(1)
        Button('全部复制').height(32).fontSize(12).backgroundColor($r('app.color.tint')).fontColor($r('app.color.accent'))
          .onClick(() => { this.onCopyAll(); })
        Button('关闭').backgroundColor(Color.Transparent).fontColor($r('app.color.muted'))
          .onClick(() => { this.onClose(); })
      }.width('100%').padding(12)
      TextArea({ text: this.selectCopyText }).layoutWeight(1).width('94%').fontSize(15)
        .onChange((_v: string) => {})
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.winTopInset, bottom: Math.max(16, this.bottomInset + 8), left: this.winLeftInset, right: this.winRightInset })
    .backgroundColor(this.canvasHex)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .transition(SystemMotion.overlayModalTransition(this.reduceMotion))
  }
}

@Component
export struct ChatWideSidePanel {
  @Prop sidePanelMode: '' | 'browser' | 'workspace' = '';
  browserManager: BrowserAgentManager = new BrowserAgentManager();
  @Prop workspaces: LocalWorkspace[] = [];
  @Prop activeWorkspaceId: string = '';
  @Prop envVars: EnvVar[] = [];
  @Prop filesDir: string = '';
  @Prop bookmarks: BrowserBookmark[] = [];
  @Prop bottomInset: number = 0;

  @StorageProp('windowTopInsetVp') winTopInset: number = 0;
  @StorageProp('windowRightInsetVp') winRightInset: number = 0;
  @StorageProp('reduceMotionEnabled') reduceMotion: boolean = false;

  onChangeMode: (mode: '' | 'browser' | 'workspace') => void = () => {};
  onSaveWorkspaces: (list: LocalWorkspace[], activeWsId: string) => Promise<void> = async () => {};
  onSaveEnvVars: (vars: EnvVar[]) => Promise<void> = async () => {};
  onOpenHtmlPreview: (title: string, html: string) => void = () => {};
  onSaveBookmarks: (list: BrowserBookmark[]) => Promise<void> = async () => {};
  onExtractToChat: (title: string, text: string) => void = () => {};

  build() {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        Button('🌐 浏览器')
          .height(26).fontSize(11).borderRadius(6)
          .backgroundColor(this.sidePanelMode === 'browser' ? $r('app.color.accent') : $r('app.color.panel'))
          .fontColor(this.sidePanelMode === 'browser' ? $r('app.color.on_accent') : $r('app.color.ink'))
          .onClick(() => { this.onChangeMode('browser'); })
        Button('📁 工作区')
          .height(26).fontSize(11).borderRadius(6)
          .backgroundColor(this.sidePanelMode === 'workspace' ? $r('app.color.accent') : $r('app.color.panel'))
          .fontColor(this.sidePanelMode === 'workspace' ? $r('app.color.on_accent') : $r('app.color.ink'))
          .onClick(() => { this.onChangeMode('workspace'); })
        Blank()
        Button('×')
          .width(26).height(26).fontSize(13).borderRadius(6)
          .backgroundColor(Color.Transparent).fontColor($r('app.color.muted'))
          .onClick(() => { this.onChangeMode(''); })
      }.width('100%').padding({ left: 8, right: 8, top: 6 })
      if (this.sidePanelMode === 'workspace') {
        WorkspacePanel({
          workspaces: this.workspaces,
          activeWorkspaceId: this.activeWorkspaceId,
          envVars: this.envVars,
          filesDir: this.filesDir,
          onSaveWorkspaces: (list: LocalWorkspace[], activeWsId: string) => this.onSaveWorkspaces(list, activeWsId),
          onSaveEnvVars: (vars: EnvVar[]) => this.onSaveEnvVars(vars),
          onOpenHtmlPreview: (title: string, html: string) => { this.onOpenHtmlPreview(title, html); },
          onClose: () => { this.onChangeMode(''); }
        }).layoutWeight(1)
      } else {
        BrowserPanel({
          manager: this.browserManager,
          workspaces: this.workspaces,
          bookmarks: this.bookmarks,
          compactMode: true,
          onSaveBookmarks: (list: BrowserBookmark[]) => this.onSaveBookmarks(list),
          onExtractToChat: (title: string, text: string) => { this.onExtractToChat(title, text); },
          onClose: () => { this.onChangeMode(''); }
        }).layoutWeight(1)
      }
    }
    .width('36%')
    .height('100%')
    .padding({ top: this.winTopInset, bottom: this.bottomInset, right: this.winRightInset })
    .backgroundColor($r('app.color.panel'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .border({ width: { left: 1 }, color: $r('app.color.line') })
    .transition(SystemMotion.endSlideTransition(this.reduceMotion))
  }
}
