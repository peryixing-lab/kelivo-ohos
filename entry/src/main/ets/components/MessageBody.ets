import { pasteboard } from '@kit.BasicServicesKit';
import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import {
  CodeLine,
  CodeToken,
  CodeTokenKind,
  MdBlock,
  MdInline,
  MdListItem,
  findStableMarkdownPrefixEnd,
  highlightCode,
  parseMarkdownBlocks,
  parseMdInlines,
  splitInlineTail
} from '../core/MarkdownParser';
import { GenUiRenderer } from './GenUiRenderer';
import { RichPreviewKind } from './RichPreviewSheet';

function inlineRunsEqual(a: MdInline[], b: MdInline[]): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i].kind !== b[i].kind || a[i].text !== b[i].text || a[i].url !== b[i].url) {
      return false;
    }
  }
  return true;
}

function listItemsEqual(a: MdListItem[], b: MdListItem[]): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i].text !== b[i].text || a[i].ordered !== b[i].ordered ||
      a[i].index !== b[i].index || a[i].checked !== b[i].checked) {
      return false;
    }
  }
  return true;
}

function tableDataEqual(hA: string[], rA: string[][], hB: string[], rB: string[][]): boolean {
  if (hA.length !== hB.length || rA.length !== rB.length) return false;
  for (let i = 0; i < hA.length; i++) {
    if (hA[i] !== hB[i]) return false;
  }
  for (let r = 0; r < rA.length; r++) {
    if (rA[r].length !== rB[r].length) return false;
    for (let c = 0; c < rA[r].length; c++) {
      if (rA[r][c] !== rB[r][c]) return false;
    }
  }
  return true;
}

function blockDigest(b: MdBlock): string {
  return `${b.kind}:${b.level}:${b.language}:${b.text.length}:${b.rows.length}:${b.items.length}`;
}

function listMarkerText(item: MdListItem): string {
  if (item.checked !== undefined) {
    return item.checked ? '☑' : '☐';
  }
  return item.ordered ? `${item.index}.` : '•';
}

@Component
export struct MessageBody {
  @Prop @Watch('onSourceChange') source: string = '';
  @Prop bodyFontSize: number = 16;
  @Prop codeFontSize: number = 13;
  @Prop @Watch('onSourceChange') enableMarkdown: boolean = true;
  @Prop enableMathLatex: boolean = true;
  @Prop @Watch('onStreamingChange') streaming: boolean = false;
  onPreviewRich: (kind: RichPreviewKind, title: string, code: string) => void = () => {};
  onOpenUrl: (url: string) => void = () => {};
  onViewImage: (url: string, alt: string) => void = () => {};
  onAskDraft: (draft: string) => void = () => {};
  @StorageProp('immersiveLightEnabled') immersiveLightEnabled: boolean = true;

  @State private stableBlocks: MdBlock[] = [];
  @State private tailKind: string = '';
  @State private tailText: string = '';
  @State private tailLevel: number = 0;
  @State private tailLang: string = '';
  @State private tailImageUrl: string = '';
  @State private tailImageAlt: string = '';
  @State private tailInlinePrefix: MdInline[] = [];
  @State private tailPlainSuffix: string = '';
  @State private tailListStable: MdListItem[] = [];
  @State private tailListLastMarker: string = '';
  @State private tailListLastPrefix: MdInline[] = [];
  @State private tailListLastSuffix: string = '';
  @State private tailTableHeaders: string[] = [];
  @State private tailTableRows: string[][] = [];

  private lastSource: string = '';
  private lastStreaming: boolean = false;
  private lastEnableMd: boolean = true;
  private frozenOffset: number = 0;
  private frozenBlocksCache: MdBlock[] = [];
  private lastStableCount: number = -1;
  private lastStableTailSig: string = '';

  aboutToAppear(): void {
    this.syncParsedState(true);
  }

  private onSourceChange(): void {
    this.syncParsedState(false);
  }

  private onStreamingChange(): void {
    this.syncParsedState(false);
  }

  private resetTailState(): void {
    if (this.tailKind !== '') this.tailKind = '';
    if (this.tailText !== '') this.tailText = '';
    if (this.tailLevel !== 0) this.tailLevel = 0;
    if (this.tailLang !== '') this.tailLang = '';
    if (this.tailImageUrl !== '') this.tailImageUrl = '';
    if (this.tailImageAlt !== '') this.tailImageAlt = '';
    if (this.tailInlinePrefix.length > 0) this.tailInlinePrefix = [];
    if (this.tailPlainSuffix !== '') this.tailPlainSuffix = '';
    if (this.tailListStable.length > 0) this.tailListStable = [];
    if (this.tailListLastMarker !== '') this.tailListLastMarker = '';
    if (this.tailListLastPrefix.length > 0) this.tailListLastPrefix = [];
    if (this.tailListLastSuffix !== '') this.tailListLastSuffix = '';
    if (this.tailTableHeaders.length > 0) this.tailTableHeaders = [];
    if (this.tailTableRows.length > 0) this.tailTableRows = [];
  }

  private commitStableBlocksIfChanged(blocks: MdBlock[]): void {
    const tailSig = blocks.length > 0 ? blockDigest(blocks[blocks.length - 1]) : '';
    if (blocks.length !== this.lastStableCount || tailSig !== this.lastStableTailSig) {
      this.lastStableCount = blocks.length;
      this.lastStableTailSig = tailSig;
      this.stableBlocks = blocks.slice();
    }
  }

  private applyTailBlock(tail: MdBlock | undefined): void {
    if (!tail) {
      this.resetTailState();
      return;
    }
    this.tailKind = tail.kind;
    this.tailLevel = tail.level;
    this.tailLang = tail.language;

    if (tail.kind === 'paragraph' || tail.kind === 'heading' || tail.kind === 'blockquote') {
      const split = splitInlineTail(tail.text);
      if (!inlineRunsEqual(this.tailInlinePrefix, split.prefix)) {
        this.tailInlinePrefix = split.prefix;
      }
      if (this.tailPlainSuffix !== split.suffix) {
        this.tailPlainSuffix = split.suffix;
      }
      if (this.tailText !== '') this.tailText = '';
      if (this.tailListStable.length > 0) this.tailListStable = [];
      if (this.tailListLastPrefix.length > 0) this.tailListLastPrefix = [];
      if (this.tailListLastSuffix !== '') this.tailListLastSuffix = '';
      if (this.tailTableHeaders.length > 0) this.tailTableHeaders = [];
      if (this.tailTableRows.length > 0) this.tailTableRows = [];
      return;
    }

    if (tail.kind === 'list') {
      const items = tail.items;
      if (items.length === 0) {
        this.resetTailState();
        return;
      }
      const prevItems = items.slice(0, items.length - 1);
      if (!listItemsEqual(this.tailListStable, prevItems)) {
        this.tailListStable = prevItems;
      }
      const lastItem = items[items.length - 1];
      const nextMarker = listMarkerText(lastItem);
      if (this.tailListLastMarker !== nextMarker) {
        this.tailListLastMarker = nextMarker;
      }
      const split = splitInlineTail(lastItem.text);
      if (!inlineRunsEqual(this.tailListLastPrefix, split.prefix)) {
        this.tailListLastPrefix = split.prefix;
      }
      if (this.tailListLastSuffix !== split.suffix) {
        this.tailListLastSuffix = split.suffix;
      }
      if (this.tailInlinePrefix.length > 0) this.tailInlinePrefix = [];
      if (this.tailPlainSuffix !== '') this.tailPlainSuffix = '';
      if (this.tailText !== '') this.tailText = '';
      return;
    }

    if (tail.kind === 'table') {
      if (!tableDataEqual(this.tailTableHeaders, this.tailTableRows, tail.headers, tail.rows)) {
        this.tailTableHeaders = tail.headers;
        this.tailTableRows = tail.rows;
      }
      if (this.tailInlinePrefix.length > 0) this.tailInlinePrefix = [];
      if (this.tailPlainSuffix !== '') this.tailPlainSuffix = '';
      if (this.tailListStable.length > 0) this.tailListStable = [];
      if (this.tailText !== '') this.tailText = '';
      return;
    }

    if (tail.kind === 'image') {
      this.tailImageUrl = tail.imageUrl;
      this.tailImageAlt = tail.imageAlt;
      this.tailText = tail.text;
      return;
    }

    if (this.tailText !== tail.text) {
      this.tailText = tail.text;
    }
    if (this.tailInlinePrefix.length > 0) this.tailInlinePrefix = [];
    if (this.tailPlainSuffix !== '') this.tailPlainSuffix = '';
    if (this.tailListStable.length > 0) this.tailListStable = [];
    if (this.tailTableHeaders.length > 0) this.tailTableHeaders = [];
    if (this.tailTableRows.length > 0) this.tailTableRows = [];
  }

  private syncParsedState(force: boolean): void {
    const src = this.source || '';
    const mdOn = this.enableMarkdown !== false;
    const isStreaming = this.streaming === true;
    if (!force && src === this.lastSource && isStreaming === this.lastStreaming && mdOn === this.lastEnableMd) {
      return;
    }
    const appended = !force && mdOn && this.lastEnableMd && isStreaming && this.lastStreaming &&
      src.length >= this.lastSource.length && src.startsWith(this.lastSource);

    this.lastSource = src;
    this.lastStreaming = isStreaming;
    this.lastEnableMd = mdOn;

    if (!mdOn || !src) {
      this.frozenOffset = 0;
      this.frozenBlocksCache = [];
      this.commitStableBlocksIfChanged([]);
      this.resetTailState();
      return;
    }

    if (!isStreaming) {
      const fullBlocks = parseMarkdownBlocks(src);
      this.frozenOffset = src.length;
      this.frozenBlocksCache = fullBlocks;
      this.commitStableBlocksIfChanged(fullBlocks);
      this.resetTailState();
      return;
    }

    if (!appended) {
      this.frozenOffset = 0;
      this.frozenBlocksCache = [];
    }

    const activeSlice = src.slice(this.frozenOffset);
    const localCut = findStableMarkdownPrefixEnd(activeSlice);
    if (localCut > 0) {
      const newlyFrozen = parseMarkdownBlocks(activeSlice.slice(0, localCut));
      for (let i = 0; i < newlyFrozen.length; i++) {
        this.frozenBlocksCache.push(newlyFrozen[i]);
      }
      this.frozenOffset += localCut;
    }

    const tailSource = src.slice(this.frozenOffset);
    const tailBlocks = parseMarkdownBlocks(tailSource);
    let activeTail: MdBlock | undefined = undefined;
    if (tailBlocks.length > 1) {
      const combined = this.frozenBlocksCache.slice();
      for (let i = 0; i < tailBlocks.length - 1; i++) {
        combined.push(tailBlocks[i]);
      }
      this.commitStableBlocksIfChanged(combined);
      activeTail = tailBlocks[tailBlocks.length - 1];
    } else {
      this.commitStableBlocksIfChanged(this.frozenBlocksCache);
      activeTail = tailBlocks.length === 1 ? tailBlocks[0] : undefined;
    }
    this.applyTailBlock(activeTail);
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
      }, (run: MdInline, ri: number): string => ri + '-' + run.kind + '-' + run.text)
    }
    .fontSize(fontSizeVal)
    .lineHeight(Math.round(fontSizeVal * 1.55))
    .fontColor($r('app.color.ink'))
    .copyOption(CopyOptions.LocalDevice)
  }

  @Builder
  renderBlock(block: MdBlock) {
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
                }, (tok: CodeToken, ti: number): string => li + '-' + ti + '-' + tok.kind)
              }
              .fontFamily('monospace')
              .fontSize(this.codeFontSize)
              .lineHeight(Math.round(this.codeFontSize * 1.5))
              .copyOption(CopyOptions.LocalDevice)
            }, (lineObj: CodeLine, li: number): string => 'cl-' + li + '-' + lineObj.tokens.length)
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
            }, (hCell: string, hi: number): string => 'th-' + hi + '-' + hCell)
          }.backgroundColor($r('app.color.panel')).border({ width: { bottom: 1 }, color: $r('app.color.line') })

          ForEach(block.rows, (tRow: string[], ri: number) => {
            Row() {
              ForEach(tRow, (cellVal: string, ci: number) => {
                Text(cellVal).fontSize(13).fontColor($r('app.color.ink')).width(125).padding(8)
                  .copyOption(CopyOptions.LocalDevice)
              }, (cellVal: string, ci: number): string => 'td-' + ri + '-' + ci + '-' + cellVal)
            }.border({ width: { bottom: 1 }, color: $r('app.color.line') })
          }, (tRow: string[], ri: number): string => 'tr-' + ri)
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
            Text(listMarkerText(lItem))
              .fontSize(this.bodyFontSize).fontColor($r('app.color.accent')).fontWeight(FontWeight.Bold)
            Column() {
              this.inlineTextView(lItem.text, this.bodyFontSize, false)
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          }.width('100%').alignItems(VerticalAlign.Top)
        }, (lItem: MdListItem, ii: number): string => 'li-' + ii + '-' + lItem.text)
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
        ForEach(this.stableBlocks, (block: MdBlock, bi: number) => {
          this.renderBlock(block)
        }, (block: MdBlock, bi: number): string => bi + '-' + block.kind + '-' + block.text.length + '-' + block.rows.length)

        if (this.tailKind === 'heading') {
          Text() {
            ForEach(this.tailInlinePrefix, (tRun: MdInline, tri: number) => {
              if (tRun.kind === 'link') {
                Span(tRun.text)
                  .fontColor($r('app.color.accent'))
                  .decoration({ type: TextDecorationType.Underline, color: $r('app.color.accent') })
                  .onClick(() => this.onOpenUrl(tRun.url))
              } else if (tRun.kind === 'code') {
                Span(' ' + tRun.text + ' ')
                  .fontFamily('monospace')
                  .fontSize(Math.max(12, this.headingSize(this.tailLevel) - 2))
                  .fontColor($r('app.color.accent'))
              } else if (tRun.kind === 'math_inline') {
                if (this.enableMathLatex) {
                  Span(' ' + tRun.text + ' ')
                    .fontFamily('monospace')
                    .fontSize(Math.max(12, this.headingSize(this.tailLevel) - 2))
                    .fontColor($r('app.color.accent'))
                } else {
                  Span('$' + tRun.text + '$')
                }
              } else {
                Span(tRun.text)
                  .fontWeight(FontWeight.Bold)
                  .fontStyle(tRun.kind === 'italic' || tRun.kind === 'bold_italic' ? FontStyle.Italic : FontStyle.Normal)
                  .decoration(tRun.kind === 'strike' ? { type: TextDecorationType.LineThrough } : { type: TextDecorationType.None })
              }
            }, (tRun: MdInline, tri: number): string => 'th-run-' + tri + '-' + tRun.kind + '-' + tRun.text)
            if (this.tailPlainSuffix.length > 0) {
              Span(this.tailPlainSuffix).fontWeight(FontWeight.Bold)
            }
          }
          .fontSize(this.headingSize(this.tailLevel))
          .lineHeight(Math.round(this.headingSize(this.tailLevel) * 1.55))
          .fontColor($r('app.color.ink'))
          .copyOption(CopyOptions.LocalDevice)
        } else if (this.tailKind === 'hr') {
          Divider().color($r('app.color.line')).margin({ top: 4, bottom: 4 })
        } else if (this.tailKind === 'gen_ui') {
          Column({ space: 6 }) {
            Row({ space: 8 }) {
              LoadingProgress().width(16).height(16).color($r('app.color.accent'))
              Text('正在生成交互视图…').fontSize(12).fontColor($r('app.color.muted'))
            }
          }
          .padding(12)
          .width('100%')
          .borderRadius(12)
          .backgroundColor($r('app.color.panel'))
          .border({ width: 1, color: $r('app.color.line') })
          .alignItems(HorizontalAlign.Start)
        } else if (this.tailKind === 'math_block') {
          if (this.enableMathLatex) {
            Column({ space: 6 }) {
              Row() {
                Text('LaTeX 公式').fontSize(11).fontColor($r('app.color.muted')).layoutWeight(1)
              }.width('100%')
              Text(this.tailText)
                .fontFamily('monospace')
                .fontSize(this.codeFontSize)
                .lineHeight(this.codeFontSize + 7)
                .fontColor($r('app.color.ink'))
                .copyOption(CopyOptions.LocalDevice)
            }
            .padding(12).width('100%').borderRadius(12)
            .backgroundColor($r('app.color.panel')).border({ width: 1, color: $r('app.color.line') })
            .alignItems(HorizontalAlign.Start)
          } else {
            Text('$$\n' + this.tailText + '\n$$')
              .fontSize(this.bodyFontSize)
              .lineHeight(Math.round(this.bodyFontSize * 1.55))
              .fontColor($r('app.color.ink'))
              .copyOption(CopyOptions.LocalDevice)
              .width('100%')
          }
        } else if (this.tailKind === 'code') {
          Column({ space: 6 }) {
            Row({ space: 6 }) {
              Text(this.tailLang || 'code').fontSize(12).fontWeight(FontWeight.Medium).fontColor($r('app.color.muted')).layoutWeight(1)
              Button('复制').height(26).fontSize(11).backgroundColor($r('app.color.surface'))
                .fontColor($r('app.color.ink')).padding({ left: 10, right: 10 })
                .onClick(() => this.copyCode(this.tailText))
            }.width('100%')

            Scroll() {
              Text(this.tailText)
                .fontFamily('monospace')
                .fontSize(this.codeFontSize)
                .lineHeight(Math.round(this.codeFontSize * 1.5))
                .fontColor($r('app.color.ink'))
                .copyOption(CopyOptions.LocalDevice)
            }.scrollable(ScrollDirection.Horizontal).width('100%')
          }
          .padding(12).width('100%').backgroundColor($r('app.color.panel')).borderRadius(12)
          .alignItems(HorizontalAlign.Start)
        } else if (this.tailKind === 'table') {
          Scroll() {
            Column() {
              Row() {
                ForEach(this.tailTableHeaders, (thCell: string, thi: number) => {
                  Text(thCell).fontSize(13).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink'))
                    .width(125).padding(8)
                }, (thCell: string, thi: number): string => 'tail-th-' + thi + '-' + thCell)
              }.backgroundColor($r('app.color.panel')).border({ width: { bottom: 1 }, color: $r('app.color.line') })

              ForEach(this.tailTableRows, (tRowTail: string[], tri: number) => {
                Row() {
                  ForEach(tRowTail, (tCellTail: string, tci: number) => {
                    Text(tCellTail).fontSize(13).fontColor($r('app.color.ink')).width(125).padding(8)
                      .copyOption(CopyOptions.LocalDevice)
                  }, (tCellTail: string, tci: number): string => 'tail-td-' + tri + '-' + tci + '-' + tCellTail)
                }.border({ width: { bottom: 1 }, color: $r('app.color.line') })
              }, (tRowTail: string[], tri: number): string => 'tail-tr-' + tri + '-' + tRowTail.join('|'))
            }.alignItems(HorizontalAlign.Start)
          }.scrollable(ScrollDirection.Horizontal).width('100%')
            .border({ width: 1, color: $r('app.color.line') }).borderRadius(10)
        } else if (this.tailKind === 'blockquote') {
          Column() {
            Text() {
              ForEach(this.tailInlinePrefix, (bRun: MdInline, bri: number) => {
                if (bRun.kind === 'link') {
                  Span(bRun.text)
                    .fontColor($r('app.color.accent'))
                    .decoration({ type: TextDecorationType.Underline, color: $r('app.color.accent') })
                    .onClick(() => this.onOpenUrl(bRun.url))
                } else if (bRun.kind === 'code') {
                  Span(' ' + bRun.text + ' ')
                    .fontFamily('monospace')
                    .fontSize(Math.max(12, this.bodyFontSize - 3))
                    .fontColor($r('app.color.accent'))
                } else if (bRun.kind === 'math_inline') {
                  if (this.enableMathLatex) {
                    Span(' ' + bRun.text + ' ')
                      .fontFamily('monospace')
                      .fontSize(Math.max(12, this.bodyFontSize - 3))
                      .fontColor($r('app.color.accent'))
                  } else {
                    Span('$' + bRun.text + '$')
                  }
                } else {
                  Span(bRun.text)
                    .fontWeight(bRun.kind === 'bold' || bRun.kind === 'bold_italic' ? FontWeight.Bold : FontWeight.Normal)
                    .fontStyle(bRun.kind === 'italic' || bRun.kind === 'bold_italic' ? FontStyle.Italic : FontStyle.Normal)
                    .decoration(bRun.kind === 'strike' ? { type: TextDecorationType.LineThrough } : { type: TextDecorationType.None })
                }
              }, (bRun: MdInline, bri: number): string => 'tb-run-' + bri + '-' + bRun.kind + '-' + bRun.text)
              if (this.tailPlainSuffix.length > 0) {
                Span(this.tailPlainSuffix)
              }
            }
            .fontSize(this.bodyFontSize - 1)
            .lineHeight(Math.round((this.bodyFontSize - 1) * 1.55))
            .fontColor($r('app.color.ink'))
            .copyOption(CopyOptions.LocalDevice)
          }
          .padding({ left: 10, right: 8, top: 6, bottom: 6 })
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .backgroundColor($r('app.color.panel'))
          .border({ width: { left: 3 }, color: $r('app.color.accent') })
          .borderRadius({ topRight: 8, bottomRight: 8 })
        } else if (this.tailKind === 'list') {
          Column({ space: 5 }) {
            ForEach(this.tailListStable, (slItem: MdListItem, sii: number) => {
              Row({ space: 8 }) {
                Text(listMarkerText(slItem))
                  .fontSize(this.bodyFontSize).fontColor($r('app.color.accent')).fontWeight(FontWeight.Bold)
                Column() {
                  this.inlineTextView(slItem.text, this.bodyFontSize, false)
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              }.width('100%').alignItems(VerticalAlign.Top)
            }, (slItem: MdListItem, sii: number): string => 'tail-sli-' + sii + '-' + slItem.text)

            Row({ space: 8 }) {
              Text(this.tailListLastMarker)
                .fontSize(this.bodyFontSize).fontColor($r('app.color.accent')).fontWeight(FontWeight.Bold)
              Column() {
                Text() {
                  ForEach(this.tailListLastPrefix, (lRun: MdInline, lri: number) => {
                    if (lRun.kind === 'link') {
                      Span(lRun.text)
                        .fontColor($r('app.color.accent'))
                        .decoration({ type: TextDecorationType.Underline, color: $r('app.color.accent') })
                        .onClick(() => this.onOpenUrl(lRun.url))
                    } else if (lRun.kind === 'code') {
                      Span(' ' + lRun.text + ' ')
                        .fontFamily('monospace')
                        .fontSize(Math.max(12, this.bodyFontSize - 2))
                        .fontColor($r('app.color.accent'))
                    } else if (lRun.kind === 'math_inline') {
                      if (this.enableMathLatex) {
                        Span(' ' + lRun.text + ' ')
                          .fontFamily('monospace')
                          .fontSize(Math.max(12, this.bodyFontSize - 2))
                          .fontColor($r('app.color.accent'))
                      } else {
                        Span('$' + lRun.text + '$')
                      }
                    } else {
                      Span(lRun.text)
                        .fontWeight(lRun.kind === 'bold' || lRun.kind === 'bold_italic' ? FontWeight.Bold : FontWeight.Normal)
                        .fontStyle(lRun.kind === 'italic' || lRun.kind === 'bold_italic' ? FontStyle.Italic : FontStyle.Normal)
                        .decoration(lRun.kind === 'strike' ? { type: TextDecorationType.LineThrough } : { type: TextDecorationType.None })
                    }
                  }, (lRun: MdInline, lri: number): string => 'tl-run-' + lri + '-' + lRun.kind + '-' + lRun.text)
                  if (this.tailListLastSuffix.length > 0) {
                    Span(this.tailListLastSuffix)
                  }
                }
                .fontSize(this.bodyFontSize)
                .lineHeight(Math.round(this.bodyFontSize * 1.55))
                .fontColor($r('app.color.ink'))
                .copyOption(CopyOptions.LocalDevice)
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            }.width('100%').alignItems(VerticalAlign.Top)
          }.width('100%').alignItems(HorizontalAlign.Start)
        } else if (this.tailKind === 'image') {
          Column({ space: 4 }) {
            Image(this.tailImageUrl)
              .width('100%').constraintSize({ maxHeight: 260 }).objectFit(ImageFit.Contain).borderRadius(10)
              .onClick(() => this.onViewImage(this.tailImageUrl, this.tailImageAlt))
            if (this.tailImageAlt) {
              Text(this.tailImageAlt).fontSize(12).fontColor($r('app.color.muted'))
            }
          }.width('100%').alignItems(HorizontalAlign.Start)
        } else if (this.tailKind === 'paragraph') {
          Text() {
            ForEach(this.tailInlinePrefix, (pRun: MdInline, pri: number) => {
              if (pRun.kind === 'link') {
                Span(pRun.text)
                  .fontColor($r('app.color.accent'))
                  .decoration({ type: TextDecorationType.Underline, color: $r('app.color.accent') })
                  .onClick(() => this.onOpenUrl(pRun.url))
              } else if (pRun.kind === 'code') {
                Span(' ' + pRun.text + ' ')
                  .fontFamily('monospace')
                  .fontSize(Math.max(12, this.bodyFontSize - 2))
                  .fontColor($r('app.color.accent'))
              } else if (pRun.kind === 'math_inline') {
                if (this.enableMathLatex) {
                  Span(' ' + pRun.text + ' ')
                    .fontFamily('monospace')
                    .fontSize(Math.max(12, this.bodyFontSize - 2))
                    .fontColor($r('app.color.accent'))
                } else {
                  Span('$' + pRun.text + '$')
                }
              } else {
                Span(pRun.text)
                  .fontWeight(pRun.kind === 'bold' || pRun.kind === 'bold_italic' ? FontWeight.Bold : FontWeight.Normal)
                  .fontStyle(pRun.kind === 'italic' || pRun.kind === 'bold_italic' ? FontStyle.Italic : FontStyle.Normal)
                  .decoration(pRun.kind === 'strike' ? { type: TextDecorationType.LineThrough } : { type: TextDecorationType.None })
              }
            }, (pRun: MdInline, pri: number): string => 'tp-run-' + pri + '-' + pRun.kind + '-' + pRun.text)
            if (this.tailPlainSuffix.length > 0) {
              Span(this.tailPlainSuffix)
            }
          }
          .fontSize(this.bodyFontSize)
          .lineHeight(Math.round(this.bodyFontSize * 1.55))
          .fontColor($r('app.color.ink'))
          .copyOption(CopyOptions.LocalDevice)
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
