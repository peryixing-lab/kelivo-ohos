import { pasteboard } from '@kit.BasicServicesKit';
import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import {
  CodeLine,
  CodeToken,
  CodeTokenKind,
  MdBlock,
  MdInline,
  MdListItem,
  highlightCode,
  parseMarkdownBlocks,
  parseMdInlines
} from '../core/MarkdownParser';
import { GenUiRenderer } from './GenUiRenderer';
import { RichPreviewKind } from './RichPreviewSheet';

@Component
export struct MessageBody {
  @Prop source: string = '';
  @Prop bodyFontSize: number = 16;
  @Prop codeFontSize: number = 13;
  @Prop enableMarkdown: boolean = true;
  @Prop enableMathLatex: boolean = true;
  onPreviewRich: (kind: RichPreviewKind, title: string, code: string) => void = () => {};
  onOpenUrl: (url: string) => void = () => {};
  onViewImage: (url: string, alt: string) => void = () => {};
  onAskDraft: (draft: string) => void = () => {};
  @StorageProp('immersiveLightEnabled') immersiveLightEnabled: boolean = true;

  private parsedBlocks(): MdBlock[] {
    return parseMarkdownBlocks(this.source);
  }

  private inlineRuns(text: string): MdInline[] {
    return parseMdInlines(text);
  }

  private codeLines(code: string, lang: string): CodeLine[] {
    return highlightCode(code, lang);
  }

  private headingSize(level: number): number {
    if (level <= 1) return Math.round(this.bodyFontSize * 1.45);
    if (level === 2) return Math.round(this.bodyFontSize * 1.28);
    if (level === 3) return Math.round(this.bodyFontSize * 1.15);
    return this.bodyFontSize + 1;
  }

  private tokenColor(kind: CodeTokenKind): ResourceColor {
    if (kind === 'keyword') return $r('app.color.accent');
    if (kind === 'string') return '#2E8B57';
    if (kind === 'number') return '#D97706';
    if (kind === 'comment') return $r('app.color.muted');
    if (kind === 'type') return '#0284C7';
    return $r('app.color.ink');
  }

  private previewKindForLang(lang: string): RichPreviewKind | undefined {
    const l = lang.trim().toLowerCase();
    if (l === 'html' || l === 'htm') return 'html';
    if (l === 'svg') return 'svg';
    if (l === 'mermaid') return 'mermaid';
    if (l === 'plantuml' || l === 'puml') return 'plantuml';
    return undefined;
  }

  private copyCode(code: string): void {
    pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, code))
      .then(() => {
        this.getUIContext().getPromptAction().showToast(
          ImmersiveMaterialStyle.toastOptions('代码已复制', this.immersiveLightEnabled)
        );
      }).catch(() => {});
  }

  @Builder
  inlineTextView(rawText: string, fontSizeVal: number, forceBold: boolean) {
    Text() {
      ForEach(this.inlineRuns(rawText), (run: MdInline, ri: number) => {
        if (run.kind === 'link') {
          Span(run.text)
            .fontColor($r('app.color.accent'))
            .decoration({ type: TextDecorationType.Underline, color: $r('app.color.accent') })
            .onClick(() => this.onOpenUrl(run.url))
        } else if (run.kind === 'code') {
          Span(' ' + run.text + ' ')
            .fontFamily('monospace')
            .fontSize(Math.max(12, fontSizeVal - 2))
            .fontColor($r('app.color.accent'))
        } else if (run.kind === 'math_inline') {
          if (this.enableMathLatex) {
            Span(' ' + run.text + ' ')
              .fontFamily('monospace')
              .fontSize(Math.max(12, fontSizeVal - 2))
              .fontColor($r('app.color.accent'))
          } else {
            Span('$' + run.text + '$')
          }
        } else {
          Span(run.text)
            .fontWeight(forceBold || run.kind === 'bold' || run.kind === 'bold_italic' ? FontWeight.Bold : FontWeight.Normal)
            .fontStyle(run.kind === 'italic' || run.kind === 'bold_italic' ? FontStyle.Italic : FontStyle.Normal)
            .decoration(run.kind === 'strike' ? { type: TextDecorationType.LineThrough } : { type: TextDecorationType.None })
        }
      }, (run: MdInline, ri: number) => ri + '-' + run.kind + '-' + run.text)
    }
    .fontSize(fontSizeVal)
    .lineHeight(Math.round(fontSizeVal * 1.55))
    .fontColor($r('app.color.ink'))
    .copyOption(CopyOptions.LocalDevice)
  }

  build() {
    Column({ space: 10 }) {
      if (!this.enableMarkdown) {
        Text(this.source)
          .fontSize(this.bodyFontSize)
          .lineHeight(Math.round(this.bodyFontSize * 1.55))
          .fontColor($r('app.color.ink'))
          .copyOption(CopyOptions.LocalDevice)
          .width('100%')
      } else {
      ForEach(this.parsedBlocks(), (block: MdBlock, bi: number) => {
        if (block.kind === 'heading') {
          this.inlineTextView(block.text, this.headingSize(block.level), true)
        } else if (block.kind === 'hr') {
          Divider().color($r('app.color.line')).margin({ top: 4, bottom: 4 })
        } else if (block.kind === 'gen_ui') {
          GenUiRenderer({ source: block.text, onAskDraft: this.onAskDraft })
        } else if (block.kind === 'math_block') {
          if (this.enableMathLatex) {
            Column({ space: 6 }) {
              Row() {
                Text('LaTeX 公式').fontSize(11).fontColor($r('app.color.muted')).layoutWeight(1)
                Button('渲染预览').height(24).fontSize(11).backgroundColor($r('app.color.surface'))
                  .fontColor($r('app.color.accent')).padding({ left: 8, right: 8 })
                  .onClick(() => this.onPreviewRich('math', '数学公式', block.text))
              }.width('100%')
              Text(block.text).fontFamily('monospace').fontSize(this.codeFontSize).lineHeight(this.codeFontSize + 7)
                .fontColor($r('app.color.ink')).copyOption(CopyOptions.LocalDevice)
            }
            .padding(12).width('100%').borderRadius(12)
            .backgroundColor($r('app.color.panel')).border({ width: 1, color: $r('app.color.line') })
            .alignItems(HorizontalAlign.Start)
          } else {
            Text('$$\n' + block.text + '\n$$')
              .fontSize(this.bodyFontSize)
              .lineHeight(Math.round(this.bodyFontSize * 1.55))
              .fontColor($r('app.color.ink'))
              .copyOption(CopyOptions.LocalDevice)
              .width('100%')
          }
        } else if (block.kind === 'code') {
          Column({ space: 6 }) {
            Row({ space: 6 }) {
              Text(block.language || 'code').fontSize(12).fontWeight(FontWeight.Medium).fontColor($r('app.color.muted')).layoutWeight(1)
              if (this.previewKindForLang(block.language) !== undefined) {
                Button('预览').height(26).fontSize(11).backgroundColor($r('app.color.tint'))
                  .fontColor($r('app.color.accent')).padding({ left: 10, right: 10 })
                  .onClick(() => {
                    const kind = this.previewKindForLang(block.language);
                    if (kind !== undefined) this.onPreviewRich(kind, (block.language || '代码') + ' 预览', block.text);
                  })
              }
              Button('复制').height(26).fontSize(11).backgroundColor($r('app.color.surface'))
                .fontColor($r('app.color.ink')).padding({ left: 10, right: 10 })
                .onClick(() => this.copyCode(block.text))
            }.width('100%')

            Scroll() {
              Column({ space: 2 }) {
                ForEach(this.codeLines(block.text, block.language), (lineObj: CodeLine, li: number) => {
                  Text() {
                    ForEach(lineObj.tokens, (tok: CodeToken, ti: number) => {
                      Span(tok.text).fontColor(this.tokenColor(tok.kind))
                    }, (tok: CodeToken, ti: number) => li + '-' + ti + '-' + tok.kind)
                  }
                  .fontFamily('monospace')
                  .fontSize(this.codeFontSize)
                  .lineHeight(Math.round(this.codeFontSize * 1.5))
                  .copyOption(CopyOptions.LocalDevice)
                }, (lineObj: CodeLine, li: number) => 'cl-' + li + '-' + lineObj.tokens.length)
              }.alignItems(HorizontalAlign.Start)
            }.scrollable(ScrollDirection.Horizontal).width('100%')
          }
          .padding(12).width('100%').backgroundColor($r('app.color.panel')).borderRadius(12)
          .alignItems(HorizontalAlign.Start)
        } else if (block.kind === 'table') {
          Scroll() {
            Column() {
              Row() {
                ForEach(block.headers, (hCell: string, hi: number) => {
                  Text(hCell).fontSize(13).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink'))
                    .width(125).padding(8)
                }, (hCell: string, hi: number) => 'th-' + hi + '-' + hCell)
              }.backgroundColor($r('app.color.panel')).border({ width: { bottom: 1 }, color: $r('app.color.line') })

              ForEach(block.rows, (tRow: string[], ri: number) => {
                Row() {
                  ForEach(tRow, (cellVal: string, ci: number) => {
                    Text(cellVal).fontSize(13).fontColor($r('app.color.ink')).width(125).padding(8)
                      .copyOption(CopyOptions.LocalDevice)
                  }, (cellVal: string, ci: number) => 'td-' + ri + '-' + ci + '-' + cellVal)
                }.border({ width: { bottom: 1 }, color: $r('app.color.line') })
              }, (tRow: string[], ri: number) => 'tr-' + ri)
            }.alignItems(HorizontalAlign.Start)
          }.scrollable(ScrollDirection.Horizontal).width('100%')
            .border({ width: 1, color: $r('app.color.line') }).borderRadius(10)
        } else if (block.kind === 'blockquote') {
          Column() {
            this.inlineTextView(block.text, this.bodyFontSize - 1, false)
          }
          .padding({ left: 10, right: 8, top: 6, bottom: 6 })
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .backgroundColor($r('app.color.panel'))
          .border({ width: { left: 3 }, color: $r('app.color.accent') })
          .borderRadius({ topRight: 8, bottomRight: 8 })
        } else if (block.kind === 'list') {
          Column({ space: 5 }) {
            ForEach(block.items, (lItem: MdListItem, ii: number) => {
              Row({ space: 8 }) {
                Text(lItem.checked !== undefined ? (lItem.checked ? '☑' : '☐') : (lItem.ordered ? lItem.index + '.' : '•'))
                  .fontSize(this.bodyFontSize).fontColor($r('app.color.accent')).fontWeight(FontWeight.Bold)
                Column() {
                  this.inlineTextView(lItem.text, this.bodyFontSize, false)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              }.width('100%').alignItems(VerticalAlign.Top)
            }, (lItem: MdListItem, ii: number) => 'li-' + ii + '-' + lItem.text)
          }.width('100%').alignItems(HorizontalAlign.Start)
        } else if (block.kind === 'image') {
          Column({ space: 4 }) {
            Image(block.imageUrl)
              .width('100%').constraintSize({ maxHeight: 260 }).objectFit(ImageFit.Contain).borderRadius(10)
              .onClick(() => this.onViewImage(block.imageUrl, block.imageAlt))
            if (block.imageAlt) {
              Text(block.imageAlt).fontSize(12).fontColor($r('app.color.muted'))
            }
          }.width('100%').alignItems(HorizontalAlign.Start)
        } else {
          this.inlineTextView(block.text, this.bodyFontSize, false)
        }
      }, (block: MdBlock, bi: number) => bi + '-' + block.kind + '-' + block.text.length + '-' + block.rows.length)
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
