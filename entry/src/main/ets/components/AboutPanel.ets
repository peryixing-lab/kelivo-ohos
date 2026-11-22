import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { KelivoPageHeader, KelivoSectionHeader } from './KelivoChrome';

@Component
export struct AboutPanel {
  @Prop providerCount: number = 0;
  @Prop conversationCount: number = 0;
  @Prop embeddedInNav: boolean = false;
  @State capText: string = '';
  @StorageProp('windowTopInsetVp') winTopInset: number = 0;

  onClose: () => void = () => {};

  aboutToAppear(): void {
    this.capText = ImmersiveMaterialStyle.capabilitySummary();
  }

  build() {
    Column() {
      if (!this.embeddedInNav) {
        KelivoPageHeader({
          titleText: '关于 Kelivo',
          showBack: true,
          onBack: () => { this.onClose(); }
        })
      }

      Scroll() {
        Column({ space: 12 }) {
          Column({ space: 8 }) {
            Image($r('app.media.kelivo'))
              .width(72)
              .height(72)
              .borderRadius(20)
            Text('Kelivo · 鸿蒙原生版')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.ink'))
            Text('基于 HarmonyOS NEXT ArkTS/ArkUI 原生构建')
              .fontSize(12)
              .fontColor($r('app.color.muted'))
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .padding(20)
          .borderRadius(16)
          .backgroundColor($r('app.color.surface'))

          KelivoSectionHeader({ titleText: '运行状态', topSpacing: 4 })
          Column() {
            Row() {
              Text('已配置服务商')
                .fontSize(14)
                .fontColor($r('app.color.ink'))
                .layoutWeight(1)
              Text(`${this.providerCount}`)
                .fontSize(14)
                .fontColor($r('app.color.muted'))
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })

            Divider().color($r('app.color.line')).margin({ left: 16 })

            Row() {
              Text('本地保存会话')
                .fontSize(14)
                .fontColor($r('app.color.ink'))
                .layoutWeight(1)
              Text(`${this.conversationCount}`)
                .fontSize(14)
                .fontColor($r('app.color.muted'))
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })

            Divider().color($r('app.color.line')).margin({ left: 16 })

            Row() {
              Text('沉浸光感能力')
                .fontSize(14)
                .fontColor($r('app.color.ink'))
                .layoutWeight(1)
              Text(this.capText || '标准模式')
                .fontSize(12)
                .fontColor($r('app.color.accent'))
                .maxLines(1)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14, bottom: 14 })
          }
          .width('100%')
          .borderRadius(16)
          .backgroundColor($r('app.color.surface'))
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.embeddedInNav ? (56 + this.winTopInset + 4) : 4, bottom: 48 })
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
