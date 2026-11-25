import { BrandIconId, brandInitial, isMonochromeBrandIcon } from '../core/BrandIcons';
import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';

export function brandIconResource(id: BrandIconId): Resource | undefined {
  switch (id) {
    case 'openai':
      return $r('app.media.icon_openai');
    case 'opencode':
      return $r('app.media.icon_opencode');
    case 'gemini':
      return $r('app.media.icon_gemini');
    case 'claude':
      return $r('app.media.icon_claude');
    case 'deepseek':
      return $r('app.media.icon_deepseek');
    case 'openrouter':
      return $r('app.media.icon_openrouter');
    case 'siliconflow':
      return $r('app.media.icon_siliconflow');
    case 'qwen':
      return $r('app.media.icon_qwen');
    case 'zhipu':
      return $r('app.media.icon_zhipu');
    case 'doubao':
      return $r('app.media.icon_doubao');
    case 'kimi':
      return $r('app.media.icon_kimi');
    case 'minimax':
      return $r('app.media.icon_minimax');
    case 'stepfun':
      return $r('app.media.icon_stepfun');
    case 'grok':
      return $r('app.media.icon_grok');
    case 'ollama':
      return $r('app.media.icon_ollama');
    case 'bing':
      return $r('app.media.icon_bing');
    case 'brave':
      return $r('app.media.icon_brave');
    case 'tavily':
      return $r('app.media.icon_tavily');
    case 'exa':
      return $r('app.media.icon_exa');
    case 'mcp':
      return $r('app.media.icon_mcp');
    case 'kelivo':
      return $r('app.media.kelivo');
    default:
      return undefined;
  }
}

@Component
export struct KelivoNavTitleBar {
  @Prop titleText: string = '';
  @Prop subtitleText: string = '';
  @Prop showBack: boolean = true;
  @Prop rightText: string = '';
  @Prop rightPrimary: boolean = false;
  rightSymbol?: Resource = undefined;
  secondSymbol?: Resource = undefined;
  thirdSymbol?: Resource = undefined;
  onBack: () => void = () => {};
  onRightAction: () => void = () => {};
  onSecondAction: () => void = () => {};
  onThirdAction: () => void = () => {};

  @StorageProp('immersiveLightEnabled') immersiveLight: boolean = true;
  @StorageProp('effectiveDarkMode') isDark: boolean = false;
  @StorageProp('themeSurfaceHex') surfaceHex: string = '#FFFFFF';
  @StorageProp('themeAccentHex') accentHex: string = '#4D5C92';
  @StorageProp('themeTintHex') tintHex: string = '#DCE1FF';
  @StorageProp('windowTopInsetVp') winTopInset: number = 0;
  @StorageProp('windowLeftInsetVp') winLeftInset: number = 0;
  @StorageProp('windowRightInsetVp') winRightInset: number = 0;
  @StorageProp('windowTitleRightAvoidVp') winTitleRightAvoid: number = 0;

  build() {
    Row({ space: 10 }) {
      if (this.showBack) {
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(19)
            .fontColor([$r('sys.color.icon_primary')])
        }
        .width(40)
        .height(40)
        .padding(0)
        .accessibilityText('返回')
        .backgroundColor(ImmersiveMaterialStyle.headerActionBackground(
          this.surfaceHex, this.tintHex, this.immersiveLight, false
        ))
        .onClick(() => { this.onBack(); })
        .systemMaterial(ImmersiveMaterialStyle.headerActionMaterial(
          this.surfaceHex, this.accentHex, this.isDark, this.immersiveLight, false
        ))
      }

      Column({ space: 1 }) {
        Text(this.titleText)
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subtitleText.length > 0) {
          Text(this.subtitleText)
            .fontSize(12)
            .fontColor($r('app.color.muted'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.thirdSymbol !== undefined) {
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph(this.thirdSymbol)
            .fontSize(19)
            .fontColor([$r('sys.color.icon_primary')])
        }
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor(ImmersiveMaterialStyle.headerActionBackground(
          this.surfaceHex, this.tintHex, this.immersiveLight, false
        ))
        .onClick(() => { this.onThirdAction(); })
        .systemMaterial(ImmersiveMaterialStyle.headerActionMaterial(
          this.surfaceHex, this.accentHex, this.isDark, this.immersiveLight, false
        ))
      }

      if (this.secondSymbol !== undefined) {
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph(this.secondSymbol)
            .fontSize(19)
            .fontColor([$r('sys.color.icon_primary')])
        }
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor(ImmersiveMaterialStyle.headerActionBackground(
          this.surfaceHex, this.tintHex, this.immersiveLight, false
        ))
        .onClick(() => { this.onSecondAction(); })
        .systemMaterial(ImmersiveMaterialStyle.headerActionMaterial(
          this.surfaceHex, this.accentHex, this.isDark, this.immersiveLight, false
        ))
      }

      if (this.rightText.length > 0) {
        Button(this.rightText, { buttonStyle: ButtonStyleMode.TEXTUAL })
          .height(36)
          .fontSize(13)
          .fontColor(this.rightPrimary && !ImmersiveMaterialStyle.isActive(this.immersiveLight)
            ? $r('app.color.accent')
            : $r('sys.color.font_primary'))
          .padding({ left: 14, right: 14 })
          .borderRadius(18)
          .backgroundColor(ImmersiveMaterialStyle.headerActionBackground(
            this.surfaceHex, this.tintHex, this.immersiveLight, this.rightPrimary
          ))
          .onClick(() => { this.onRightAction(); })
          .systemMaterial(ImmersiveMaterialStyle.headerActionMaterial(
            this.surfaceHex, this.accentHex, this.isDark, this.immersiveLight, this.rightPrimary
          ))
      } else if (this.rightSymbol !== undefined) {
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph(this.rightSymbol)
            .fontSize(19)
            .fontColor([
              this.rightPrimary && !ImmersiveMaterialStyle.isActive(this.immersiveLight)
                ? $r('app.color.accent')
                : $r('sys.color.icon_primary')
            ])
        }
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor(ImmersiveMaterialStyle.headerActionBackground(
          this.surfaceHex, this.tintHex, this.immersiveLight, this.rightPrimary
        ))
        .onClick(() => { this.onRightAction(); })
        .systemMaterial(ImmersiveMaterialStyle.headerActionMaterial(
          this.surfaceHex, this.accentHex, this.isDark, this.immersiveLight, this.rightPrimary
        ))
      }
    }
    .width('100%')
    .height('100%')
    .padding({
      top: this.winTopInset,
      left: 10 + this.winLeftInset,
      right: 10 + this.winRightInset + this.winTitleRightAvoid
    })
    .alignItems(VerticalAlign.Center)
    .clip(false)
  }
}

@Component
export struct KelivoSwitchRow {
  rowTitle: string = '';
  desc: string = '';
  @Prop isOn: boolean = false;
  showDivider: boolean = true;
  onToggle: (v: boolean) => Promise<void> = async () => {};

  @StorageProp('immersiveLightEnabled') immersiveLight: boolean = true;

  build() {
    Column() {
      Row({ space: 12 }) {
        Column({ space: 2 }) {
          Text(this.rowTitle)
            .fontSize(14)
            .fontColor($r('app.color.ink'))
          if (this.desc.length > 0) {
            Text(this.desc)
              .fontSize(11)
              .fontColor($r('app.color.muted'))
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.isOn })
          .onChange((v: boolean) => {
            if (v === this.isOn) {
              return;
            }
            this.onToggle(v).catch(() => {});
          })
          .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLight))
      }
      .width('100%')
      .padding({ left: 16, right: 14, top: 11, bottom: 11 })

      if (this.showDivider) {
        Divider()
          .color($r('app.color.line'))
          .margin({ left: 16 })
      }
    }
    .width('100%')
  }
}

@Component
export struct KelivoPageHeader {
  @Prop titleText: string = '';
  @Prop subtitleText: string = '';
  @Prop showBack: boolean = true;
  @Prop rightText: string = '';
  rightSymbol?: Resource = undefined;
  secondSymbol?: Resource = undefined;
  thirdSymbol?: Resource = undefined;
  onBack: () => void = () => {};
  onRightAction: () => void = () => {};
  onSecondAction: () => void = () => {};
  onThirdAction: () => void = () => {};

  build() {
    Row({ space: 8 }) {
      if (this.showBack) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.arrow_left'))
            .fontSize(20)
            .fontColor([$r('app.color.ink')])
        }
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText('返回')
        .onClick(() => { this.onBack(); })
      }

      Column({ space: 1 }) {
        Text(this.titleText)
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subtitleText.length > 0) {
          Text(this.subtitleText)
            .fontSize(12)
            .fontColor($r('app.color.muted'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.secondSymbol !== undefined) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph(this.secondSymbol)
            .fontSize(20)
            .fontColor([$r('app.color.ink')])
        }
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .onClick(() => { this.onSecondAction(); })
      }

      if (this.rightText.length > 0) {
        Button(this.rightText)
          .height(34)
          .fontSize(13)
          .padding({ left: 12, right: 12 })
          .borderRadius(17)
          .backgroundColor($r('app.color.panel'))
          .fontColor($r('app.color.ink'))
          .onClick(() => { this.onRightAction(); })
      } else if (this.rightSymbol !== undefined) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph(this.rightSymbol)
            .fontSize(20)
            .fontColor([$r('app.color.ink')])
        }
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .onClick(() => { this.onRightAction(); })
      }
    }
    .width('100%')
    .height(52)
    .padding({ left: 8, right: 8 })
    .alignItems(VerticalAlign.Center)
  }
}

@Component
export struct KelivoAvatarBadge {
  @Prop brandId: BrandIconId = '';
  @Prop avatarText: string = '';
  @Prop fallbackLetter: string = 'K';
  @Prop badgeSize: number = 32;
  @Prop plain: boolean = false;

  private resolvedRes(): Resource | undefined {
    return brandIconResource(this.brandId);
  }

  private isMono(): boolean {
    return isMonochromeBrandIcon(this.brandId);
  }

  private displayText(): string {
    if (this.avatarText && this.avatarText.trim().length > 0) {
      return this.avatarText.trim();
    }
    return brandInitial(this.fallbackLetter);
  }

  build() {
    Stack() {
      if (this.resolvedRes() !== undefined) {
        if (this.isMono()) {
          Image(this.resolvedRes() as Resource)
            .width(this.plain ? this.badgeSize : Math.round(this.badgeSize * 0.62))
            .height(this.plain ? this.badgeSize : Math.round(this.badgeSize * 0.62))
            .objectFit(ImageFit.Contain)
            .fillColor($r('app.color.ink'))
        } else {
          Image(this.resolvedRes() as Resource)
            .width(this.plain ? this.badgeSize : Math.round(this.badgeSize * 0.66))
            .height(this.plain ? this.badgeSize : Math.round(this.badgeSize * 0.66))
            .objectFit(ImageFit.Contain)
        }
      } else {
        Text(this.displayText())
          .fontSize(this.plain
            ? Math.max(12, Math.round(this.badgeSize * 0.72))
            : Math.max(12, Math.round(this.badgeSize * 0.45)))
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.accent'))
          .textAlign(TextAlign.Center)
          .maxLines(1)
      }
    }
    .width(this.badgeSize)
    .height(this.badgeSize)
    .borderRadius(this.plain ? 0 : this.badgeSize / 2)
    .backgroundColor(this.plain
      ? Color.Transparent
      : (this.resolvedRes() !== undefined ? $r('app.color.panel') : $r('app.color.tint')))
    .alignContent(Alignment.Center)
    .clip(!this.plain)
  }
}

@Component
export struct KelivoStatusPill {
  @Prop enabledState: boolean = true;

  build() {
    Text(this.enabledState ? 'ON' : 'OFF')
      .fontSize(11)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.enabledState ? '#0F7B45' : '#C45100')
      .backgroundColor(this.enabledState ? '#E5F7ED' : '#FFF0E5')
      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
      .borderRadius(999)
  }
}

@Component
export struct KelivoSectionHeader {
  @Prop titleText: string = '';
  @Prop topSpacing: number = 12;

  build() {
    Text(this.titleText)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.muted'))
      .width('100%')
      .padding({ left: 12, right: 12, top: this.topSpacing, bottom: 6 })
  }
}
