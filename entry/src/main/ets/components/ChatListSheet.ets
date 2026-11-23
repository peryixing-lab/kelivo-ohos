import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { BUILTIN_PALETTES, PaletteTokens } from '../core/ThemeManager';

const HEADER_HEIGHT: number = 124;
const FOOTER_HEIGHT: number = 72;

@Component
export struct ChatListSheet {
  @Require @Prop heading: string = '';
  @Require @Prop palette: PaletteTokens = BUILTIN_PALETTES[0].light;
  @Prop isDark: boolean = false;
  @Prop immersiveLightEnabled: boolean = true;
  onClose: () => void = () => {};
  @BuilderParam controls: () => void;
  @BuilderParam items: () => void;
  @BuilderParam footer?: () => void;

  private overlapsTitle(): boolean {
    return ImmersiveMaterialStyle.isActive(this.immersiveLightEnabled);
  }

  private titleOptions(): NavigationTitleOptions {
    if (this.overlapsTitle()) return ImmersiveMaterialStyle.titleBarOptions(true, true);
    return { barStyle: BarStyle.STANDARD, backgroundColor: this.palette.surface };
  }

  @Builder
  private header() {
    Column({ space: 6 }) {
      Row({ space: 12 }) {
        Text(this.heading).fontSize(22).fontWeight(FontWeight.Bold).fontColor(this.palette.ink)
          .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(19)
            .fontColor([this.overlapsTitle() ? $r('sys.color.icon_primary') : this.palette.ink])
        }
        .width(40).height(40).padding(0)
        .backgroundColor(this.overlapsTitle() ? Color.Transparent : this.palette.panel)
        .accessibilityText('关闭' + this.heading)
        .onClick(() => this.onClose())
        .systemMaterial(ImmersiveMaterialStyle.titleButtonMaterial(this.palette, this.isDark, this.immersiveLightEnabled))
      }.width('100%')
      this.controls()
    }
    .width('100%').height(HEADER_HEIGHT)
    .padding({ left: 16, right: 16, top: 20, bottom: 8 })
    .justifyContent(FlexAlign.Center).clip(false)
  }

  @Builder
  private listNavigation() {
    Navigation() {
      Scroll() {
        Column() {
          this.items()
        }
        .width('100%')
        .padding({
          left: 16, right: 16,
          top: this.overlapsTitle() ? HEADER_HEIGHT + 4 : 4,
          bottom: this.footer && this.overlapsTitle() ? FOOTER_HEIGHT + 8 : 12
        })
      }
      .align(Alignment.Top).width('100%').height('100%').edgeEffect(EdgeEffect.Spring)
    }
    .mode(NavigationMode.Stack).titleMode(NavigationTitleMode.Mini)
    .hideBackButton(true).hideToolBar(true)
    .title({ builder: () => this.header(), height: HEADER_HEIGHT }, this.titleOptions())
    .backgroundColor(Color.Transparent).width('100%').height('100%')
  }

  @Builder
  private filterBar() {
    Column() {
      Row() {
        if (this.footer) { this.footer() }
      }
      .width('100%').height(44).padding({ left: 6, right: 6 }).borderRadius(22)
      .backgroundColor(ImmersiveMaterialStyle.composerBackground(this.palette.surface, this.immersiveLightEnabled))
      .systemMaterial(ImmersiveMaterialStyle.composerMaterial(this.palette, this.isDark, this.immersiveLightEnabled))
    }
    .width('100%').height(FOOTER_HEIGHT).padding({ left: 10, right: 10, top: 4, bottom: 24 })
  }

  build() {
    WithTheme({ theme: ImmersiveMaterialStyle.pageTheme(this.palette.surface) }) {
      if (this.footer) {
        Tabs({ barPosition: BarPosition.End }) {
          TabContent() {
            this.listNavigation()
          }
          .tabBar(this.filterBar())
        }
        .vertical(false).barOverlap(this.overlapsTitle())
        .barBackgroundColor(Color.Transparent).barBackgroundBlurStyle(BlurStyle.NONE)
        .barHeight(FOOTER_HEIGHT).divider(null).scrollable(false).animationDuration(0)
        .backgroundColor(Color.Transparent).width('100%').height('100%')
      } else {
        this.listNavigation()
      }
    }
  }
}
