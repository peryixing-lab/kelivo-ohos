import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

@Component
export struct ImageViewerSheet {
  imageSrc: string = '';
  imageTitle: string = '图片预览';
  canOcr: boolean = false;
  onRunOcr: (imageSrc: string) => Promise<string> = async () => '';
  onClose: () => void = () => {};
  @State zoomScale: number = 1;
  @State ocrResult: string = '';
  @State busy: boolean = false;
  @State statusMsg: string = '';

  private async saveToFile(): Promise<void> {
    if (this.busy || !this.imageSrc.startsWith('data:image/')) {
      this.statusMsg = '仅支持保存本地生成或附加的图片';
      return;
    }
    this.busy = true;
    try {
      const comma = this.imageSrc.indexOf(',');
      if (comma < 0) throw new Error('无效图片数据');
      const header = this.imageSrc.slice(0, comma);
      const b64 = this.imageSrc.slice(comma + 1);
      const ext = header.includes('jpeg') ? 'jpg' : header.includes('webp') ? 'webp' : 'png';
      const bytes = new util.Base64Helper().decodeSync(b64);
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const paths = await new picker.DocumentViewPicker(ctx).save({
        newFileNames: ['Kelivo-' + Date.now() + '.' + ext]
      });
      if (!paths.length) return;
      const file = await fs.open(paths[0], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        await fs.write(file.fd, bytes.buffer);
      } finally {
        await fs.close(file);
      }
      this.statusMsg = '图片已保存';
    } catch (e) {
      this.statusMsg = (e as Error).message || '保存失败';
    } finally {
      this.busy = false;
    }
  }

  private async triggerOcr(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    this.statusMsg = '';
    try {
      this.ocrResult = await this.onRunOcr(this.imageSrc);
      if (!this.ocrResult) this.statusMsg = '未识别到文字';
    } catch (e) {
      this.statusMsg = (e as Error).message || 'OCR 识别失败';
    } finally {
      this.busy = false;
    }
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Button('关闭').backgroundColor(Color.Transparent).fontColor($r('app.color.accent')).onClick(() => this.onClose())
        Text(this.imageTitle).fontSize(17).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink'))
          .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Button(this.zoomScale > 1.2 ? '1x' : '2x').height(32).fontSize(12)
          .backgroundColor($r('app.color.panel')).fontColor($r('app.color.ink'))
          .onClick(() => { this.zoomScale = this.zoomScale > 1.2 ? 1 : 2; })
        if (this.canOcr) {
          Button('OCR 识字').height(32).fontSize(12).backgroundColor($r('app.color.tint')).fontColor($r('app.color.accent'))
            .onClick(() => { this.triggerOcr(); })
        }
        if (this.imageSrc.startsWith('data:image/')) {
          Button('保存').height(32).fontSize(12).backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
            .onClick(() => { this.saveToFile(); })
        }
      }.width('100%').height(58).padding({ left: 8, right: 12 })

      Scroll() {
        Column({ space: 12 }) {
          Image(this.imageSrc)
            .width('100%')
            .height(this.zoomScale > 1.2 ? 540 : 340)
            .objectFit(ImageFit.Contain)
            .borderRadius(12)
          if (this.busy) {
            LoadingProgress().width(28).height(28)
          }
          if (this.statusMsg) {
            Text(this.statusMsg).fontSize(13).fontColor($r('app.color.muted'))
          }
          if (this.ocrResult) {
            Column({ space: 6 }) {
              Text('OCR 识别结果').fontSize(13).fontWeight(FontWeight.Bold).fontColor($r('app.color.accent'))
              Text(this.ocrResult).fontSize(14).lineHeight(22).fontColor($r('app.color.ink'))
                .copyOption(CopyOptions.LocalDevice)
            }.width('100%').padding(12).borderRadius(12).backgroundColor($r('app.color.panel')).alignItems(HorizontalAlign.Start)
          }
        }.padding({ left: 16, right: 16, top: 16, bottom: 40 }).width('100%')
      }.layoutWeight(1).width('100%').scrollable(ScrollDirection.Vertical)
    }.width('100%').height('100%').backgroundColor(Color.Transparent)
  }
}
