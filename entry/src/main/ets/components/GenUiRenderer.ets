import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import {
  GenUiChartPoint,
  GenUiDocument,
  GenUiNode,
  GenUiScalar,
  GenUiSelectOption,
  evalGenUiExpr,
  formatGenUiScalar,
  interpolateGenUi,
  parseGenUiDocument
} from '../core/GenUiParser';

@Component
struct GenUiNodeView {
  @Prop node: GenUiNode = { type: 'text' };
  @Prop renderTick: number = 0;
  readState: () => Record<string, GenUiScalar> = (): Record<string, GenUiScalar> => ({});
  writeState: (key: string, val: GenUiScalar) => void = () => {};
  onAskDraft: (draft: string) => void = () => {};
  @StorageProp('immersiveLightEnabled') immersiveLightEnabled: boolean = true;

  private isNodeVisible(): boolean {
    if (!this.node.visibleIf) return true;
    const v = evalGenUiExpr(this.node.visibleIf, this.readState());
    return Boolean(v);
  }

  private textValue(): string {
    const st = this.readState();
    if (this.node.expr) return formatGenUiScalar(evalGenUiExpr(this.node.expr, st));
    return interpolateGenUi(this.node.text || '', st);
  }

  private numberValue(): number {
    const key = this.node.bind || '';
    const v = this.readState()[key];
    return typeof v === 'number' ? v : (Number(v) || this.node.min || 0);
  }

  private stringValue(): string {
    const key = this.node.bind || '';
    const v = this.readState()[key];
    return v !== undefined ? String(v) : '';
  }

  private boolValue(): boolean {
    const key = this.node.bind || '';
    const v = this.readState()[key];
    return Boolean(v);
  }

  private chartMax(): number {
    const pts = this.node.points || [];
    const st = this.readState();
    let mx = 1;
    for (let i = 0; i < pts.length; i++) {
      const v = Math.abs(Number(evalGenUiExpr(pts[i].valueExpr, st)) || 0);
      if (v > mx) mx = v;
    }
    return mx;
  }

  private chartPointVal(pt: GenUiChartPoint): number {
    return Number(evalGenUiExpr(pt.valueExpr, this.readState())) || 0;
  }

  private selectLabels(): SelectOption[] {
    const opts = this.node.options || [];
    return opts.map((o: GenUiSelectOption): SelectOption => {
      return { value: o.label };
    });
  }

  private selectedLabel(): string {
    const cur = this.stringValue();
    const opts = this.node.options || [];
    const found = opts.find((o: GenUiSelectOption): boolean => o.value === cur);
    return found ? found.label : (opts.length ? opts[0].label : '选择');
  }

  build() {
    Column() {
      if (this.isNodeVisible()) {
        if (this.node.type === 'card' || this.node.type === 'column') {
          Column({ space: 8 }) {
            if (this.node.title) {
              Text(interpolateGenUi(this.node.title, this.readState()))
                .fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink'))
            }
            ForEach(this.node.children || [], (child: GenUiNode, idx: number) => {
              GenUiNodeView({
                node: child,
                renderTick: this.renderTick,
                readState: this.readState,
                writeState: this.writeState,
                onAskDraft: this.onAskDraft
              })
            }, (child: GenUiNode, idx: number) => (child.id || child.type) + '-' + idx + '-' + this.renderTick)
          }
          .width('100%')
          .padding(this.node.type === 'card' ? 12 : 0)
          .borderRadius(this.node.type === 'card' ? 12 : 0)
          .backgroundColor(this.node.type === 'card' ? $r('app.color.surface') : Color.Transparent)
          .border(this.node.type === 'card' ? { width: 1, color: $r('app.color.line') } : { width: 0 })
          .alignItems(HorizontalAlign.Start)
        } else if (this.node.type === 'row') {
          Row({ space: 10 }) {
            ForEach(this.node.children || [], (child: GenUiNode, idx: number) => {
              Column() {
                GenUiNodeView({
                  node: child,
                  renderTick: this.renderTick,
                  readState: this.readState,
                  writeState: this.writeState,
                  onAskDraft: this.onAskDraft
                })
              }.layoutWeight(1)
            }, (child: GenUiNode, idx: number) => (child.id || child.type) + '-' + idx + '-' + this.renderTick)
          }.width('100%').alignItems(VerticalAlign.Top)
        } else if (this.node.type === 'metric') {
          Column({ space: 2 }) {
            if (this.node.label) {
              Text(this.node.label).fontSize(12).fontColor($r('app.color.muted'))
            }
            Text(this.textValue() + (this.node.unit ? ' ' + this.node.unit : ''))
              .fontSize(20).fontWeight(FontWeight.Bold).fontColor($r('app.color.accent'))
          }
          .padding(10).width('100%').borderRadius(10).backgroundColor($r('app.color.panel'))
          .alignItems(HorizontalAlign.Start)
        } else if (this.node.type === 'callout') {
          Row({ space: 8 }) {
            Text(this.textValue()).fontSize(13).lineHeight(20).fontColor($r('app.color.ink')).layoutWeight(1)
          }
          .width('100%').padding(10).borderRadius(10)
          .backgroundColor(this.node.variant === 'warn' ? $r('app.color.tint') : $r('app.color.panel'))
        } else if (this.node.type === 'slider') {
          Column({ space: 4 }) {
            Row() {
              Text(this.node.label || this.node.bind || '').fontSize(13).fontColor($r('app.color.ink')).layoutWeight(1)
              Text(formatGenUiScalar(this.numberValue()) + (this.node.unit ? ' ' + this.node.unit : ''))
                .fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.accent'))
            }.width('100%')
            Slider({
              value: this.numberValue(),
              min: this.node.min ?? 0,
              max: this.node.max ?? 100,
              step: this.node.step ?? 1
            }).width('100%').selectedColor($r('app.color.accent'))
              .onChange((val: number) => {
                if (this.node.bind) this.writeState(this.node.bind, val);
              })
              .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
          }.width('100%')
        } else if (this.node.type === 'toggle') {
          Row() {
            Text(this.node.label || this.node.bind || '').fontSize(14).fontColor($r('app.color.ink')).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.boolValue() })
              .selectedColor($r('app.color.accent'))
              .onChange((checked: boolean) => {
                if (this.node.bind) this.writeState(this.node.bind, checked);
              })
              .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
          }.width('100%')
        } else if (this.node.type === 'input') {
          Column({ space: 4 }) {
            if (this.node.label) {
              Text(this.node.label).fontSize(12).fontColor($r('app.color.muted'))
            }
            TextInput({ text: this.stringValue(), placeholder: this.node.label || '输入数值或文本' })
              .onChange((val: string) => {
                if (this.node.bind) {
                  const num = Number(val);
                  this.writeState(this.node.bind, val.trim() !== '' && Number.isFinite(num) ? num : val);
                }
              })
          }.width('100%').alignItems(HorizontalAlign.Start)
        } else if (this.node.type === 'select') {
          Row({ space: 8 }) {
            if (this.node.label) {
              Text(this.node.label).fontSize(14).fontColor($r('app.color.ink')).layoutWeight(1)
            }
            Select(this.selectLabels()).value(this.selectedLabel())
              .onSelect((idx: number) => {
                const opts = this.node.options || [];
                if (this.node.bind && opts[idx]) this.writeState(this.node.bind, opts[idx].value);
              })
              .menuSystemMaterial(ImmersiveMaterialStyle.selectMenuMaterial(this.immersiveLightEnabled))
              .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
          }.width('100%')
        } else if (this.node.type === 'table') {
          Column({ space: 4 }) {
            if (this.node.headers?.length) {
              Row() {
                ForEach(this.node.headers, (h: string, hi: number) => {
                  Text(h).fontSize(12).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink'))
                    .layoutWeight(1).padding(6)
                }, (h: string, hi: number) => 'gh-' + hi + '-' + h)
              }.width('100%').backgroundColor($r('app.color.panel')).borderRadius(6)
            }
            ForEach(this.node.rows || [], (row: string[], ri: number) => {
              Row() {
                ForEach(row, (cell: string, ci: number) => {
                  Text(interpolateGenUi(cell, this.readState())).fontSize(12).fontColor($r('app.color.ink'))
                    .layoutWeight(1).padding(6)
                }, (cell: string, ci: number) => 'gc-' + ri + '-' + ci + '-' + this.renderTick)
              }.width('100%').border({ width: { bottom: 1 }, color: $r('app.color.line') })
            }, (row: string[], ri: number) => 'gr-' + ri + '-' + this.renderTick)
          }.width('100%')
        } else if (this.node.type === 'bar_chart') {
          Column({ space: 6 }) {
            if (this.node.title) {
              Text(this.node.title).fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink'))
            }
            ForEach(this.node.points || [], (pt: GenUiChartPoint, pi: number) => {
              Column({ space: 2 }) {
                Row() {
                  Text(pt.label).fontSize(12).fontColor($r('app.color.muted')).layoutWeight(1)
                  Text(formatGenUiScalar(this.chartPointVal(pt))).fontSize(12).fontColor($r('app.color.ink'))
                }.width('100%')
                Progress({
                  value: Math.max(0, Math.abs(this.chartPointVal(pt))),
                  total: this.chartMax(),
                  type: ProgressType.Linear
                }).width('100%').color($r('app.color.accent')).backgroundColor($r('app.color.panel'))
              }.width('100%')
            }, (pt: GenUiChartPoint, pi: number) => 'gp-' + pi + '-' + this.renderTick)
          }.width('100%')
        } else if (this.node.type === 'button') {
          Button(this.node.label || '追问模型')
            .height(34).fontSize(13).backgroundColor($r('app.color.tint')).fontColor($r('app.color.accent'))
            .onClick(() => {
              const draft = interpolateGenUi(this.node.askDraft || this.node.text || this.node.label || '', this.readState());
              this.onAskDraft(draft);
            })
        } else {
          Text(this.textValue()).fontSize(14).lineHeight(21).fontColor($r('app.color.ink'))
        }
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct GenUiRenderer {
  @Prop source: string = '';
  onAskDraft: (draft: string) => void = () => {};
  @StorageProp('immersiveLightEnabled') immersiveLightEnabled: boolean = true;
  @State renderTick: number = 0;
  @State docTitle: string = '';
  @State docError: string = '';
  @State docNodes: GenUiNode[] = [];
  private stateMap: Record<string, GenUiScalar> = {};
  private lastParsedSource: string = '';

  aboutToAppear(): void {
    this.syncDocument();
  }

  private syncDocument(): void {
    if (this.lastParsedSource === this.source) return;
    this.lastParsedSource = this.source;
    const doc: GenUiDocument = parseGenUiDocument(this.source);
    this.docTitle = doc.title;
    this.docError = doc.error || '';
    this.docNodes = doc.nodes;
    this.stateMap = doc.state;
    this.renderTick++;
  }

  private readState = (): Record<string, GenUiScalar> => {
    return this.stateMap;
  };

  private writeState = (key: string, val: GenUiScalar): void => {
    this.stateMap[key] = val;
    this.renderTick++;
  };

  build() {
    Column({ space: 10 }) {
      if (this.docError) {
        Text('交互组件解析中: ' + this.docError).fontSize(12).fontColor($r('app.color.muted'))
      } else {
        if (this.docTitle) {
          Text(this.docTitle).fontSize(16).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink'))
        }
        ForEach(this.docNodes, (node: GenUiNode, idx: number) => {
          GenUiNodeView({
            node,
            renderTick: this.renderTick,
            readState: this.readState,
            writeState: this.writeState,
            onAskDraft: this.onAskDraft
          })
        }, (node: GenUiNode, idx: number) => (node.id || node.type) + '-' + idx + '-' + this.renderTick)
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(14)
    .backgroundColor($r('app.color.panel'))
    .border({ width: 1, color: $r('app.color.line') })
    .alignItems(HorizontalAlign.Start)
  }
}
