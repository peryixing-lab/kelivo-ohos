import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { hexWithAlpha } from '../core/ImmersiveUtils';
import { BUILTIN_PALETTES, PaletteTokens } from '../core/ThemeManager';

@Component
export struct ChatTitleBarView {
  @Prop wide: boolean = false;
  @Prop wideSide: boolean = false;
  @Prop picking: boolean = false;
  @Prop working: boolean = false;
  @Prop hasOtherGenerating: boolean = false;
  @Prop titleLabel: string = '';
  @Prop subtitleLabel: string = '';
  @Prop sidePanelMode: '' | 'browser' | 'workspace' = '';
  @Prop hasActiveMessages: boolean = false;
  @Prop ephemeralMode: boolean = false;
  @Prop fullAccessMode: boolean = false;
  @Prop newChatLabel: string = '新对话';
  @Prop chatBgHex: string = '#FFFFFF';
  @Prop palette: PaletteTokens = BUILTIN_PALETTES[0].light;
  @Prop scrollUnderTitle: boolean = true;

  @StorageProp('immersiveLightEnabled') immersiveLight: boolean = true;
  @StorageProp('effectiveDarkMode') isDark: boolean = false;
  @StorageProp('windowTopInsetVp') winTopInset: number = 0;
  @StorageProp('windowTitleRightAvoidVp') winTitleRightAvoid: number = 0;

  onOpenDrawer: () => void = () => {};
  onOpenModelQuickSheet: () => void = () => {};
  onToggleSidePanel: () => void = () => {};
  onOpenMiniMap: () => void = () => {};
  onToggleEphemeral: () => void = () => {};
  onNewChat: () => void = () => {};
  onToggleInChatSearch: () => void = () => {};
  onToggleFullAccess: () => void = () => {};
  onOrganizeMemory: () => void = () => {};
  onOpenPersonas: () => void = () => {};
  onOpenContext: () => void = () => {};
  onOpenBrowser: () => void = () => {};
  onOpenStats: () => void = () => {};
  onOpenSettings: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.immersiveLight && this.scrollUnderTitle) {
        Column()
          .width('100%')
          .height('100%')
          .linearGradient({
            direction: GradientDirection.Bottom,
            colors: [[hexWithAlpha(this.chatBgHex, '99'), 0.0], [hexWithAlpha(this.chatBgHex, '00'), 1.0]]
          })
          .hitTestBehavior(HitTestMode.None)
          .accessibilityLevel('no')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      }

      Row({ space: 6 }) {
        if (!this.wide) {
          Stack({ alignContent: Alignment.TopEnd }) {
            Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
              Image($r('app.media.icon_list'))
                .width(20)
                .height(20)
                .objectFit(ImageFit.Contain)
                .fillColor($r('sys.color.icon_primary'))
            }
            .id('openDrawer')
            .width(40)
            .height(40)
            .padding(0)
            .accessibilityText('打开侧边栏')
            .backgroundColor(ImmersiveMaterialStyle.titleButtonBackground(this.palette, this.immersiveLight))
            .onClick(() => {
              if (!this.picking) {
                this.onOpenDrawer();
              }
            })
            .systemMaterial(ImmersiveMaterialStyle.titleButtonMaterial(this.palette, this.isDark, this.immersiveLight))

            if (this.hasOtherGenerating) {
              Column()
                .width(8)
                .height(8)
                .borderRadius(4)
                .backgroundColor($r('app.color.accent'))
                .margin({ top: 3, right: 3 })
                .hitTestBehavior(HitTestMode.None)
            }
          }
          .width(40)
          .height(40)
        }

        Column({ space: 1 }) {
          Text(this.titleLabel)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.font_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.subtitleLabel)
            .fontSize(11)
            .fontColor($r('sys.color.font_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ maxWidth: this.wide ? 360 : 185 })
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(18)
        .backgroundColor(ImmersiveMaterialStyle.titleButtonBackground(this.palette, this.immersiveLight))
        .onClick(() => {
          if (!this.working && !this.picking) {
            this.onOpenModelQuickSheet();
          }
        })
        .systemMaterial(ImmersiveMaterialStyle.titlePillMaterial(this.palette, this.isDark, this.immersiveLight))

        Blank()

        if (this.wideSide) {
          Button(this.sidePanelMode ? '收起' : '分栏', { buttonStyle: ButtonStyleMode.TEXTUAL })
            .height(36)
            .fontSize(12)
            .fontColor($r('sys.color.font_primary'))
            .borderRadius(18)
            .padding({ left: 12, right: 12 })
            .backgroundColor(ImmersiveMaterialStyle.titleButtonBackground(this.palette, this.immersiveLight, this.sidePanelMode !== ''))
            .onClick(() => { this.onToggleSidePanel(); })
            .systemMaterial(ImmersiveMaterialStyle.titleButtonMaterial(this.palette, this.isDark, this.immersiveLight, this.sidePanelMode !== ''))
        }

        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.map'))
            .fontSize(18)
            .fontColor([$r('sys.color.icon_primary')])
        }
        .width(40)
        .height(40)
        .padding(0)
        .accessibilityText('对话大纲')
        .enabled(!this.picking)
        .backgroundColor(ImmersiveMaterialStyle.titleButtonBackground(this.palette, this.immersiveLight))
        .onClick(() => { this.onOpenMiniMap(); })
        .systemMaterial(ImmersiveMaterialStyle.titleButtonMaterial(this.palette, this.isDark, this.immersiveLight))

        if (!this.hasActiveMessages) {
          Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            if (this.ephemeralMode) {
              Image($r('app.media.icon_temp_chat_checked'))
                .width(19)
                .height(19)
                .objectFit(ImageFit.Contain)
                .fillColor($r('app.color.accent'))
            } else {
              SymbolGlyph($r('sys.symbol.circle_dashed'))
                .fontSize(19)
                .fontColor([$r('sys.color.icon_primary')])
            }
          }
          .id('tempChatToggle')
          .width(40)
          .height(40)
          .padding(0)
          .accessibilityText(this.ephemeralMode ? '退出临时对话' : '临时对话')
          .enabled(!this.picking)
          .backgroundColor(ImmersiveMaterialStyle.titleButtonBackground(this.palette, this.immersiveLight, this.ephemeralMode))
          .onClick(() => { this.onToggleEphemeral(); })
          .systemMaterial(ImmersiveMaterialStyle.titleButtonMaterial(this.palette, this.isDark, this.immersiveLight, this.ephemeralMode))
        } else {
          Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(19)
              .fontColor([$r('sys.color.icon_primary')])
          }
          .width(40)
          .height(40)
          .padding(0)
          .accessibilityText(this.newChatLabel)
          .backgroundColor(ImmersiveMaterialStyle.titleButtonBackground(this.palette, this.immersiveLight))
          .onClick(() => { this.onNewChat(); })
          .systemMaterial(ImmersiveMaterialStyle.titleButtonMaterial(this.palette, this.isDark, this.immersiveLight))
        }

        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.ellipsis_circle'))
            .fontSize(19)
            .fontColor([$r('sys.color.icon_primary')])
        }
        .id('chatMenu')
        .width(40)
        .height(40)
        .padding(0)
        .accessibilityText('更多操作')
        .enabled(!this.picking)
        .backgroundColor(ImmersiveMaterialStyle.titleButtonBackground(this.palette, this.immersiveLight))
        .bindMenu([
          { value: '搜索本对话内容', action: () => { this.onToggleInChatSearch(); } },
          { value: this.fullAccessMode ? '切换为工具审批模式' : '切换为工具完全访问', action: () => { this.onToggleFullAccess(); } },
          { value: '整理本对话记忆', action: () => { this.onOrganizeMemory(); } },
          { value: '助手与提示词设置', action: () => { this.onOpenPersonas(); } },
          { value: '上下文与生成参数', action: () => { this.onOpenContext(); } },
          { value: '内置浏览器', action: () => { this.onOpenBrowser(); } },
          { value: '用量统计', action: () => { this.onOpenStats(); } },
          { value: '设置中心', action: () => { this.onOpenSettings(); } }
        ], ImmersiveMaterialStyle.menuOptions(this.immersiveLight))
        .systemMaterial(ImmersiveMaterialStyle.titleButtonMaterial(this.palette, this.isDark, this.immersiveLight))
      }
      .width('100%')
      .height('100%')
      .padding({
        top: this.winTopInset,
        left: this.wide ? 16 : 8,
        right: 8 + this.winTitleRightAvoid
      })
      .alignItems(VerticalAlign.Center)
      .clip(false)
    }
    .width('100%')
    .height('100%')
    .clip(false)
  }
}
