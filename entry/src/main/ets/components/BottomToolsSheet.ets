import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';

@Component
export struct BottomToolsSheet {
  @Prop imageGenMode: boolean = false;
  @Prop immersiveLightEnabled: boolean = true;
  @Prop enabledSkillCount: number = 0;
  @Prop totalSkillCount: number = 0;
  @Prop activeInstructionCount: number = 0;
  @Prop activeWorldBookCount: number = 0;
  @Prop hasMessages: boolean = false;

  onTakePhoto: () => void = () => {};
  onPickPhotos: () => void = () => {};
  onUploadFile: () => void = () => {};
  onOpenBrowser: () => void = () => {};
  onOpenSkills: () => void = () => {};
  onOpenInstructionCards: () => void = () => {};
  onOpenWorldBook: () => void = () => {};
  onOpenQuickPhrases: () => void = () => {};
  onToggleImageGen: (enabled: boolean) => void = () => {};
  onOpenContext: () => void = () => {};
  onClearContext: () => void = () => {};

  @Builder
  private actionRow(
    symbolRes: Resource,
    labelText: string,
    detailText: string,
    showChevron: boolean,
    onTap: () => void
  ) {
    Row({ space: 12 }) {
      SymbolGlyph(symbolRes)
        .fontSize(20)
        .fontColor([$r('app.color.ink')])
      Text(labelText)
        .fontSize(15)
        .fontColor($r('app.color.ink'))
        .layoutWeight(1)
      if (detailText.length > 0) {
        Text(detailText)
          .fontSize(13)
          .fontColor($r('app.color.accent'))
      }
      if (showChevron) {
        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontColor([$r('app.color.muted')])
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: 12, right: 12 })
    .borderRadius(12)
    .onClick(() => { onTap(); })
  }

  build() {
    Column({ space: 14 }) {
      Row({ space: 10 }) {
        Column({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.camera'))
            .fontSize(22)
            .fontColor([$r('app.color.ink')])
          Text('拍照')
            .fontSize(13)
            .fontColor($r('app.color.ink'))
        }
        .layoutWeight(1)
        .height(74)
        .justifyContent(FlexAlign.Center)
        .borderRadius(14)
        .backgroundColor(ImmersiveMaterialStyle.sheetCardBackground(this.immersiveLightEnabled))
        .onClick(() => { this.onTakePhoto(); })

        Column({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.picture'))
            .fontSize(22)
            .fontColor([$r('app.color.ink')])
          Text('相册')
            .fontSize(13)
            .fontColor($r('app.color.ink'))
        }
        .layoutWeight(1)
        .height(74)
        .justifyContent(FlexAlign.Center)
        .borderRadius(14)
        .backgroundColor(ImmersiveMaterialStyle.sheetCardBackground(this.immersiveLightEnabled))
        .onClick(() => { this.onPickPhotos(); })

        Column({ space: 6 }) {
          SymbolGlyph($r('sys.symbol.paperclip'))
            .fontSize(22)
            .fontColor([$r('app.color.ink')])
          Text('上传文件')
            .fontSize(13)
            .fontColor($r('app.color.ink'))
        }
        .layoutWeight(1)
        .height(74)
        .justifyContent(FlexAlign.Center)
        .borderRadius(14)
        .backgroundColor(ImmersiveMaterialStyle.sheetCardBackground(this.immersiveLightEnabled))
        .onClick(() => { this.onUploadFile(); })
      }
      .width('100%')

      Column({ space: 2 }) {
        this.actionRow($r('sys.symbol.compass'), '内置浏览器', '', false, () => { this.onOpenBrowser(); })
        this.actionRow(
          $r('sys.symbol.wand_and_stars'),
          'Skills 技能',
          this.totalSkillCount > 0 ? `${this.enabledSkillCount}/${this.totalSkillCount}` : '',
          false,
          () => { this.onOpenSkills(); }
        )
        this.actionRow(
          $r('sys.symbol.rectangle_stack'),
          '指令注入',
          this.activeInstructionCount > 0 ? `${this.activeInstructionCount}` : '',
          true,
          () => { this.onOpenInstructionCards(); }
        )
        this.actionRow(
          $r('sys.symbol.book'),
          '世界书',
          this.activeWorldBookCount > 0 ? `${this.activeWorldBookCount}` : '',
          true,
          () => { this.onOpenWorldBook(); }
        )
        this.actionRow($r('sys.symbol.bolt'), '快捷短语', '', true, () => { this.onOpenQuickPhrases(); })

        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.paintbrush'))
            .fontSize(20)
            .fontColor([$r('app.color.ink')])
          Text('图像生成模式')
            .fontSize(15)
            .fontColor($r('app.color.ink'))
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.imageGenMode })
            .onChange((v: boolean) => { this.onToggleImageGen(v); })
            .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
        }
        .width('100%')
        .height(48)
        .padding({ left: 12, right: 12 })

        this.actionRow($r('sys.symbol.slider_horizontal_2'), '上下文与生成参数', '', true, () => { this.onOpenContext(); })
        if (this.hasMessages) {
          this.actionRow($r('sys.symbol.arrow_counterclockwise'), '重置上下文窗口', '', false, () => { this.onClearContext(); })
        }
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor(ImmersiveMaterialStyle.sheetCardBackground(this.immersiveLightEnabled))
      .padding({ top: 4, bottom: 4 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 20 })
  }
}
