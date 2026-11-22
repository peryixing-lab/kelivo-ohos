import { Persona, UsageStatRow } from '../core/Models';

interface HeatmapCell {
  day: string;
  tokens: number;
  level: number;
}

interface HeatmapWeek {
  weekIdx: number;
  cells: HeatmapCell[];
}

interface DailyBarItem {
  day: string;
  shortDay: string;
  promptTokens: number;
  completionTokens: number;
  total: number;
  promptPct: number;
  compPct: number;
}

interface UsageRankItem {
  key: string;
  label: string;
  totalTokens: number;
  msgCount: number;
  ratioPct: number;
}

interface DayTokenBucket {
  prompt: number;
  comp: number;
}

interface UsageCountBucket {
  total: number;
  msgs: number;
}

interface RawRankRow {
  key: string;
  label: string;
  totalTokens: number;
  msgCount: number;
}

@Component
export struct StatsPanel {
  @Prop usageStats: UsageStatRow[] = [];
  @Prop personas: Persona[] = [];
  @Prop embeddedInNav: boolean = false;
  onRefresh: () => Promise<void> = async () => {};
  onClose: () => void = () => {};

  @StorageProp('windowTopInsetVp') winTopInset: number = 0;

  @State totalTokens: number = 0;
  @State promptTokens: number = 0;
  @State completionTokens: number = 0;
  @State cachedTokens: number = 0;
  @State totalMessages: number = 0;
  @State activeDays: number = 0;
  @State weeksGrid: HeatmapWeek[] = [];
  @State recentBars: DailyBarItem[] = [];
  @State modelRanks: UsageRankItem[] = [];
  @State personaRanks: UsageRankItem[] = [];
  @State selectedDayTip: string = '';

  aboutToAppear(): void {
    this.recompute();
  }

  private pad2(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
  }

  private formatDay(d: Date): string {
    return `${d.getFullYear()}-${this.pad2(d.getMonth() + 1)}-${this.pad2(d.getDate())}`;
  }

  private personaLabel(pid: string): string {
    if (!pid) {
      return '默认助手';
    }
    for (let i = 0; i < this.personas.length; i++) {
      if (this.personas[i].id === pid) {
        return this.personas[i].name;
      }
    }
    return pid;
  }

  private formatCount(n: number): string {
    if (n >= 1000000) {
      return `${(n / 1000000).toFixed(2)}M`;
    }
    if (n >= 1000) {
      return `${(n / 1000).toFixed(1)}K`;
    }
    return `${n}`;
  }

  private recompute(): void {
    let pSum = 0;
    let cSum = 0;
    let cachedSum = 0;
    let mSum = 0;
    const dayMap = new Map<string, DayTokenBucket>();
    const modelMap = new Map<string, UsageCountBucket>();
    const personaMap = new Map<string, UsageCountBucket>();

    for (let i = 0; i < this.usageStats.length; i++) {
      const r = this.usageStats[i];
      pSum += r.promptTokens;
      cSum += r.completionTokens;
      cachedSum += r.cachedTokens;
      mSum += r.msgCount;

      const dEntry: DayTokenBucket = dayMap.get(r.day) ?? { prompt: 0, comp: 0 };
      dEntry.prompt += r.promptTokens;
      dEntry.comp += r.completionTokens;
      dayMap.set(r.day, dEntry);

      const mKey = r.model || 'unknown';
      const mEntry: UsageCountBucket = modelMap.get(mKey) ?? { total: 0, msgs: 0 };
      mEntry.total += r.promptTokens + r.completionTokens;
      mEntry.msgs += r.msgCount;
      modelMap.set(mKey, mEntry);

      const perKey = r.personaId || 'default';
      const perEntry: UsageCountBucket = personaMap.get(perKey) ?? { total: 0, msgs: 0 };
      perEntry.total += r.promptTokens + r.completionTokens;
      perEntry.msgs += r.msgCount;
      personaMap.set(perKey, perEntry);
    }

    this.promptTokens = pSum;
    this.completionTokens = cSum;
    this.totalTokens = pSum + cSum;
    this.cachedTokens = cachedSum;
    this.totalMessages = mSum;
    this.activeDays = dayMap.size;

    // Compute 91-day (13 weeks x 7 days) heatmap ending today
    let maxDaily = 1;
    dayMap.forEach((v) => {
      const tot = v.prompt + v.comp;
      if (tot > maxDaily) {
        maxDaily = tot;
      }
    });

    const today = new Date();
    const totalDays = 91;
    const flatCells: HeatmapCell[] = [];
    for (let offset = totalDays - 1; offset >= 0; offset--) {
      const dt = new Date(today.getTime() - offset * 86400000);
      const dayStr = this.formatDay(dt);
      const stat = dayMap.get(dayStr);
      const tok = stat ? stat.prompt + stat.comp : 0;
      let level = 0;
      if (tok > 0) {
        const ratio = tok / maxDaily;
        level = ratio > 0.75 ? 4 : (ratio > 0.45 ? 3 : (ratio > 0.18 ? 2 : 1));
      }
      flatCells.push({ day: dayStr, tokens: tok, level });
    }

    const weeks: HeatmapWeek[] = [];
    for (let w = 0; w < 13; w++) {
      weeks.push({
        weekIdx: w,
        cells: flatCells.slice(w * 7, w * 7 + 7)
      });
    }
    this.weeksGrid = weeks;

    // Last 14 days bar chart
    const bars: DailyBarItem[] = [];
    let maxBar = 1;
    for (let offset = 13; offset >= 0; offset--) {
      const dt = new Date(today.getTime() - offset * 86400000);
      const dayStr = this.formatDay(dt);
      const stat = dayMap.get(dayStr);
      const tot = stat ? stat.prompt + stat.comp : 0;
      if (tot > maxBar) {
        maxBar = tot;
      }
    }
    for (let offset = 13; offset >= 0; offset--) {
      const dt = new Date(today.getTime() - offset * 86400000);
      const dayStr = this.formatDay(dt);
      const stat = dayMap.get(dayStr);
      const pr = stat ? stat.prompt : 0;
      const cp = stat ? stat.comp : 0;
      const tot = pr + cp;
      bars.push({
        day: dayStr,
        shortDay: dayStr.slice(5),
        promptTokens: pr,
        completionTokens: cp,
        total: tot,
        promptPct: tot > 0 ? Math.max(2, Math.round((pr / maxBar) * 100)) : 0,
        compPct: tot > 0 ? Math.max(2, Math.round((cp / maxBar) * 100)) : 0
      });
    }
    this.recentBars = bars;

    // Rankings
    this.modelRanks = this.buildRankList(modelMap, (k: string): string => k);
    this.personaRanks = this.buildRankList(personaMap, (k: string): string => this.personaLabel(k));
  }

  private buildRankList(
    src: Map<string, UsageCountBucket>,
    labelFn: (k: string) => string
  ): UsageRankItem[] {
    const raw: RawRankRow[] = [];
    let maxTok = 1;
    src.forEach((v, k) => {
      if (v.total > maxTok) {
        maxTok = v.total;
      }
      raw.push({ key: k, label: labelFn(k), totalTokens: v.total, msgCount: v.msgs });
    });
    raw.sort((a, b) => b.totalTokens - a.totalTokens);
    return raw.map((item): UsageRankItem => ({
      key: item.key,
      label: item.label,
      totalTokens: item.totalTokens,
      msgCount: item.msgCount,
      ratioPct: Math.max(4, Math.round((item.totalTokens / maxTok) * 100))
    }));
  }

  private cellColor(level: number): string {
    if (level === 4) {
      return '#1D4ED8';
    }
    if (level === 3) {
      return '#3B82F6';
    }
    if (level === 2) {
      return '#93C5FD';
    }
    if (level === 1) {
      return '#DBEAFE';
    }
    return '#E5E7EB';
  }

  @Builder
  private metricBox(title: string, metricVal: string, sub: string) {
    Column({ space: 4 }) {
      Text(title)
        .fontSize(11)
        .fontColor($r('app.color.muted'))
      Text(metricVal)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.ink'))
      Text(sub)
        .fontSize(10)
        .fontColor($r('app.color.accent'))
    }
    .alignItems(HorizontalAlign.Start)
    .padding(10)
    .layoutWeight(1)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(10)
  }

  build() {
    Column({ space: 12 }) {
      if (!this.embeddedInNav) {
        Row() {
          Text('Token 用量统计与热力图')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.ink'))
          Blank()
          Button('刷新')
            .type(ButtonType.Normal)
            .height(32)
            .fontSize(12)
            .borderRadius(8)
            .fontColor($r('app.color.accent'))
            .backgroundColor($r('app.color.tint'))
            .margin({ right: 6 })
            .onClick(async () => {
              await this.onRefresh();
              this.recompute();
            })
          Button('关闭')
            .type(ButtonType.Normal)
            .height(32)
            .fontSize(12)
            .borderRadius(8)
            .fontColor($r('app.color.ink'))
            .backgroundColor($r('app.color.surface'))
            .onClick(() => this.onClose())
        }
        .width('100%')
      }

      Scroll() {
        Column({ space: 12 }) {
          if (this.embeddedInNav) {
            Row() {
              Text('用量汇总与热力图')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.muted'))
              Blank()
              Button('刷新数据')
                .type(ButtonType.Normal)
                .height(30)
                .fontSize(12)
                .borderRadius(8)
                .fontColor($r('app.color.accent'))
                .backgroundColor($r('app.color.tint'))
                .onClick(async () => {
                  await this.onRefresh();
                  this.recompute();
                })
            }
            .width('100%')
          }
          Row({ space: 8 }) {
            this.metricBox('总 Token', this.formatCount(this.totalTokens), `${this.activeDays} 个活跃日`)
            this.metricBox('输入 / 输出', `${this.formatCount(this.promptTokens)} / ${this.formatCount(this.completionTokens)}`, `缓存命中 ${this.formatCount(this.cachedTokens)}`)
            this.metricBox('对话轮次', `${this.totalMessages}`, 'SQLite 持久化统计')
          }
          .width('100%')

          Column({ space: 8 }) {
            Row() {
              Text('近 91 天活跃度热力图')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.ink'))
              Blank()
              if (this.selectedDayTip.length > 0) {
                Text(this.selectedDayTip)
                  .fontSize(11)
                  .fontColor($r('app.color.accent'))
              }
            }
            .width('100%')

            Scroll() {
              Row({ space: 4 }) {
                ForEach(this.weeksGrid, (wk: HeatmapWeek) => {
                  Column({ space: 4 }) {
                    ForEach(wk.cells, (cell: HeatmapCell) => {
                      Row()
                        .width(16)
                        .height(16)
                        .borderRadius(3)
                        .backgroundColor(this.cellColor(cell.level))
                        .onClick(() => {
                          this.selectedDayTip = `${cell.day}: ${cell.tokens} tokens`;
                        })
                    }, (cell: HeatmapCell) => cell.day)
                  }
                }, (wk: HeatmapWeek) => `wk_${wk.weekIdx}`)
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }
          .padding(12)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .width('100%')

          Column({ space: 8 }) {
            Text('近 14 天每日 Token 分布（蓝：输入 / 浅蓝：输出）')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))
            ForEach(this.recentBars, (bar: DailyBarItem) => {
              Row({ space: 8 }) {
                Text(bar.shortDay)
                  .fontSize(11)
                  .width(42)
                  .fontColor($r('app.color.muted'))
                Row() {
                  if (bar.promptPct > 0) {
                    Row()
                      .height(10)
                      .width(`${bar.promptPct}%`)
                      .backgroundColor('#2563EB')
                      .borderRadius(3)
                  }
                  if (bar.compPct > 0) {
                    Row()
                      .height(10)
                      .width(`${bar.compPct}%`)
                      .backgroundColor('#60A5FA')
                      .borderRadius(3)
                  }
                }
                .layoutWeight(1)
                Text(this.formatCount(bar.total))
                  .fontSize(11)
                  .width(44)
                  .textAlign(TextAlign.End)
                  .fontColor($r('app.color.ink'))
              }
              .width('100%')
            }, (bar: DailyBarItem) => bar.day)
          }
          .alignItems(HorizontalAlign.Start)
          .padding(12)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .width('100%')

          Column({ space: 8 }) {
            Text('模型用量排行')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))
            if (this.modelRanks.length === 0) {
              Text('暂无记录，发送消息后将自动统计各模型 Token 消耗')
                .fontSize(12)
                .fontColor($r('app.color.muted'))
            } else {
              ForEach(this.modelRanks, (mr: UsageRankItem) => {
                Column({ space: 4 }) {
                  Row() {
                    Text(mr.label)
                      .fontSize(12)
                      .fontColor($r('app.color.ink'))
                      .layoutWeight(1)
                    Text(`${this.formatCount(mr.totalTokens)} (${mr.msgCount} 次)`)
                      .fontSize(11)
                      .fontColor($r('app.color.muted'))
                  }
                  .width('100%')
                  Row()
                    .height(6)
                    .width(`${mr.ratioPct}%`)
                    .backgroundColor($r('app.color.accent'))
                    .borderRadius(3)
                }
                .alignItems(HorizontalAlign.Start)
                .width('100%')
              }, (mr: UsageRankItem) => `m_${mr.key}`)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .padding(12)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .width('100%')

          Column({ space: 8 }) {
            Text('助手用量分布')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))
            ForEach(this.personaRanks, (pr: UsageRankItem) => {
              Column({ space: 4 }) {
                Row() {
                  Text(pr.label)
                    .fontSize(12)
                    .fontColor($r('app.color.ink'))
                    .layoutWeight(1)
                  Text(`${this.formatCount(pr.totalTokens)} (${pr.msgCount} 次)`)
                    .fontSize(11)
                    .fontColor($r('app.color.muted'))
                }
                .width('100%')
                Row()
                  .height(6)
                  .width(`${pr.ratioPct}%`)
                  .backgroundColor('#10B981')
                  .borderRadius(3)
              }
              .alignItems(HorizontalAlign.Start)
              .width('100%')
            }, (pr: UsageRankItem) => `p_${pr.key}`)
          }
          .alignItems(HorizontalAlign.Start)
          .padding(12)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .width('100%')
        }
        .width('100%')
        .padding({ top: this.embeddedInNav ? (56 + this.winTopInset + 8) : 0, bottom: 48 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: this.embeddedInNav ? 0 : 16, bottom: 0 })
    .backgroundColor(Color.Transparent)
  }
}
