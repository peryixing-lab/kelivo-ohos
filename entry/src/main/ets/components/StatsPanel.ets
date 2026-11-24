import { Persona, UsageStatRow } from '../core/Models';
import {
  computeUsageDashboard,
  formatLocalTime,
  formatUsageCount,
  UsageDailyBar,
  UsageDashboardData,
  UsageHeatmapCell,
  UsageHeatmapRow,
  UsageRankRow
} from '../core/UsageStatsLogic';

@Component
export struct StatsPanel {
  @Prop @Watch('onPropsChanged') usageStats: UsageStatRow[] = [];
  @Prop @Watch('onPropsChanged') personas: Persona[] = [];
  @Prop embeddedInNav: boolean = false;
  onRefresh: () => Promise<UsageStatRow[] | void> = async () => {};
  onClose: () => void = () => {};

  @StorageProp('windowTopInsetVp') winTopInset: number = 0;
  @StorageProp('windowBottomInsetVp') winBottomInset: number = 0;
  @StorageProp('effectiveDarkMode') isDark: boolean = false;

  @State dashboard: UsageDashboardData = computeUsageDashboard([], []);
  @State dataRev: number = 0;
  @State refreshing: boolean = false;
  @State lastRefreshedText: string = '';
  @State selectedDay: string = '';
  @State selectedDayTip: string = '';

  private readonly legendLevels: number[] = [0, 1, 2, 3, 4];

  aboutToAppear(): void {
    this.applyStats(this.usageStats);
    this.triggerRefresh(false);
  }

  private onPropsChanged(): void {
    this.applyStats(this.usageStats);
  }

  private applyStats(rows: UsageStatRow[]): void {
    const next = computeUsageDashboard(rows, this.personas);
    this.dashboard = next;
    this.dataRev += 1;
    if (this.selectedDay.length > 0) {
      let matched = false;
      for (let r = 0; r < next.heatmapRows.length; r++) {
        const cells = next.heatmapRows[r].cells;
        for (let c = 0; c < cells.length; c++) {
          if (cells[c].day === this.selectedDay && cells[c].level >= 0) {
            this.selectedDayTip = this.formatCellTip(cells[c]);
            matched = true;
            break;
          }
        }
        if (matched) {
          break;
        }
      }
      if (!matched) {
        this.selectedDay = '';
        this.selectedDayTip = '';
      }
    }
  }

  private async triggerRefresh(showTimestamp: boolean): Promise<void> {
    if (this.refreshing) {
      return;
    }
    this.refreshing = true;
    try {
      const fresh = await this.onRefresh();
      if (Array.isArray(fresh)) {
        this.applyStats(fresh);
      } else {
        this.applyStats(this.usageStats);
      }
      if (showTimestamp) {
        this.lastRefreshedText = '已更新 ' + formatLocalTime(new Date());
      }
    } catch (_) {
      if (showTimestamp) {
        this.lastRefreshedText = '刷新失败，请重试';
      }
    } finally {
      this.refreshing = false;
    }
  }

  private formatCellTip(cell: UsageHeatmapCell): string {
    if (cell.totalTokens <= 0) {
      return `${cell.day} · 暂无记录`;
    }
    return `${cell.day} · ${formatUsageCount(cell.totalTokens)}（输入 ${formatUsageCount(cell.promptTokens)} / 输出 ${formatUsageCount(cell.completionTokens)}）`;
  }

  private selectCell(cell: UsageHeatmapCell): void {
    if (cell.level < 0) {
      return;
    }
    if (this.selectedDay === cell.day) {
      this.selectedDay = '';
      this.selectedDayTip = '';
      return;
    }
    this.selectedDay = cell.day;
    this.selectedDayTip = this.formatCellTip(cell);
  }

  private cellColor(level: number): ResourceColor {
    if (level < 0) {
      return Color.Transparent;
    }
    if (this.isDark) {
      if (level === 4) {
        return '#60A5FA';
      }
      if (level === 3) {
        return '#3B82F6';
      }
      if (level === 2) {
        return '#1D4ED8';
      }
      if (level === 1) {
        return '#1E3A5F';
      }
      return '#272B36';
    }
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
    Column() {
      Text(title)
        .fontSize(12)
        .fontColor($r('app.color.muted'))
        .maxLines(1)
      Text(metricVal)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.ink'))
        .maxLines(1)
        .minFontSize(14)
        .maxFontSize(20)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(sub)
        .fontSize(11)
        .fontColor($r('app.color.accent'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .height(82)
    .layoutWeight(1)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(12)
    .border({ width: 1, color: $r('app.color.line') })
  }

  @Builder
  private rankRowItem(item: UsageRankRow, barColor: ResourceColor) {
    Column({ space: 5 }) {
      Row({ space: 8 }) {
        Text(item.label)
          .fontSize(12)
          .fontColor($r('app.color.ink'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(`${formatUsageCount(item.totalTokens)} (${item.msgCount} 次)`)
          .fontSize(11)
          .maxLines(1)
          .fontColor($r('app.color.muted'))
      }
      .width('100%')

      Row() {
        if (item.ratioPct > 0) {
          Row()
            .height('100%')
            .width(`${item.ratioPct}%`)
            .backgroundColor(barColor)
            .borderRadius(3)
        }
      }
      .width('100%')
      .height(6)
      .borderRadius(3)
      .backgroundColor($r('app.color.panel'))
      .clip(true)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
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
          Button(this.refreshing ? '刷新中...' : '刷新')
            .type(ButtonType.Normal)
            .height(32)
            .fontSize(12)
            .borderRadius(8)
            .padding({ left: 12, right: 12 })
            .fontColor($r('app.color.accent'))
            .backgroundColor($r('app.color.tint'))
            .margin({ right: 6 })
            .enabled(!this.refreshing)
            .opacity(this.refreshing ? 0.65 : 1)
            .onClick(() => {
              this.triggerRefresh(true);
            })
          Button('关闭')
            .type(ButtonType.Normal)
            .height(32)
            .fontSize(12)
            .borderRadius(8)
            .padding({ left: 12, right: 12 })
            .fontColor($r('app.color.ink'))
            .backgroundColor($r('app.color.surface'))
            .onClick(() => this.onClose())
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }

      Scroll() {
        Column({ space: 12 }) {
          if (this.embeddedInNav) {
            Row({ space: 8 }) {
              Column({ space: 2 }) {
                Text('用量汇总与热力图')
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.muted'))
                if (this.lastRefreshedText.length > 0) {
                  Text(this.lastRefreshedText)
                    .fontSize(11)
                    .fontColor($r('app.color.muted'))
                }
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Button(this.refreshing ? '刷新中...' : '刷新数据')
                .type(ButtonType.Normal)
                .height(30)
                .fontSize(12)
                .borderRadius(8)
                .padding({ left: 12, right: 12 })
                .fontColor($r('app.color.accent'))
                .backgroundColor($r('app.color.tint'))
                .enabled(!this.refreshing)
                .opacity(this.refreshing ? 0.65 : 1)
                .onClick(() => {
                  this.triggerRefresh(true);
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }

          Column({ space: 10 }) {
            Row({ space: 10 }) {
              this.metricBox('总 Token', formatUsageCount(this.dashboard.totalTokens), `${this.dashboard.activeDays} 个活跃日`)
              this.metricBox('对话轮次', `${this.dashboard.totalMessages} 次`, `次均 ${formatUsageCount(this.dashboard.avgTokensPerMsg)}`)
            }
            .width('100%')

            Row({ space: 10 }) {
              this.metricBox('输入 Token', formatUsageCount(this.dashboard.promptTokens), `缓存命中 ${formatUsageCount(this.dashboard.cachedTokens)}`)
              this.metricBox('输出 Token', formatUsageCount(this.dashboard.completionTokens), `占总量 ${this.dashboard.outputSharePct.toFixed(1)}%`)
            }
            .width('100%')
          }
          .width('100%')

          Column({ space: 10 }) {
            Row({ space: 8 }) {
              Text('近 91 天活跃度热力图')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.ink'))
                .layoutWeight(1)
                .maxLines(1)
              Text(`${this.dashboard.heatmapStartDay.slice(5)} ~ ${this.dashboard.heatmapEndDay.slice(5)}`)
                .fontSize(11)
                .fontColor($r('app.color.muted'))
            }
            .width('100%')

            Column({ space: 4 }) {
              ForEach(this.dashboard.heatmapRows, (row: UsageHeatmapRow) => {
                Row({ space: 4 }) {
                  Text(row.label)
                    .width(14)
                    .fontSize(10)
                    .textAlign(TextAlign.Start)
                    .fontColor($r('app.color.muted'))
                  ForEach(row.cells, (cell: UsageHeatmapCell) => {
                    Row()
                      .layoutWeight(1)
                      .aspectRatio(1)
                      .borderRadius(3)
                      .backgroundColor(this.cellColor(cell.level))
                      .border({
                        width: cell.level >= 0 && this.selectedDay === cell.day ? 1.5 : 0,
                        color: $r('app.color.ink')
                      })
                      .onClick(() => {
                        if (cell.level >= 0) {
                          this.selectCell(cell);
                        }
                      })
                  }, (cell: UsageHeatmapCell) => `${this.dataRev}_${this.isDark ? 'd' : 'l'}_hc_${cell.day}_${cell.level}`)
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)
              }, (row: UsageHeatmapRow) => `${this.dataRev}_${this.isDark ? 'd' : 'l'}_hr_${row.dayOfWeek}`)
            }
            .width('100%')
            .constraintSize({ maxWidth: 380 })
            .alignSelf(ItemAlign.Center)

            Row({ space: 8 }) {
              Text(this.selectedDayTip.length > 0 ? this.selectedDayTip : '点击方格查看当日详情')
                .fontSize(11)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .fontColor(this.selectedDayTip.length > 0 ? $r('app.color.accent') : $r('app.color.muted'))

              Row({ space: 3 }) {
                Text('少')
                  .fontSize(10)
                  .fontColor($r('app.color.muted'))
                ForEach(this.legendLevels, (lv: number) => {
                  Row()
                    .width(10)
                    .height(10)
                    .borderRadius(2)
                    .backgroundColor(this.cellColor(lv))
                }, (lv: number) => `${this.isDark ? 'd' : 'l'}_lg_${lv}`)
                Text('多')
                  .fontSize(10)
                  .fontColor($r('app.color.muted'))
              }
              .alignItems(VerticalAlign.Center)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          .padding(12)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.line') })
          .width('100%')

          Column({ space: 8 }) {
            Row({ space: 8 }) {
              Text('近 14 天每日 Token 分布')
                .fontSize(13)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.ink'))
                .layoutWeight(1)
                .maxLines(1)
              Row({ space: 8 }) {
                Row({ space: 4 }) {
                  Row()
                    .width(7)
                    .height(7)
                    .borderRadius(3.5)
                    .backgroundColor('#2563EB')
                  Text('输入')
                    .fontSize(11)
                    .fontColor($r('app.color.muted'))
                }
                .alignItems(VerticalAlign.Center)
                Row({ space: 4 }) {
                  Row()
                    .width(7)
                    .height(7)
                    .borderRadius(3.5)
                    .backgroundColor('#60A5FA')
                  Text('输出')
                    .fontSize(11)
                    .fontColor($r('app.color.muted'))
                }
                .alignItems(VerticalAlign.Center)
              }
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            ForEach(this.dashboard.recentBars, (bar: UsageDailyBar) => {
              Row({ space: 8 }) {
                Text(bar.shortDay)
                  .fontSize(11)
                  .width(40)
                  .fontColor(bar.isToday ? $r('app.color.accent') : $r('app.color.muted'))
                  .fontWeight(bar.isToday ? FontWeight.Medium : FontWeight.Normal)

                Row() {
                  if (bar.promptPct + bar.compPct > 0) {
                    Row() {
                      if (bar.promptPct > 0) {
                        Row()
                          .height('100%')
                          .layoutWeight(bar.promptPct)
                          .backgroundColor('#2563EB')
                      }
                      if (bar.compPct > 0) {
                        Row()
                          .height('100%')
                          .layoutWeight(bar.compPct)
                          .backgroundColor('#60A5FA')
                      }
                    }
                    .height('100%')
                    .width(`${bar.promptPct + bar.compPct}%`)
                    .borderRadius(5)
                    .clip(true)
                  }
                }
                .layoutWeight(1)
                .height(10)
                .borderRadius(5)
                .backgroundColor($r('app.color.panel'))
                .clip(true)

                Text(formatUsageCount(bar.totalTokens))
                  .fontSize(11)
                  .width(54)
                  .maxLines(1)
                  .textAlign(TextAlign.End)
                  .fontColor(bar.totalTokens > 0 ? $r('app.color.ink') : $r('app.color.muted'))
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
            }, (bar: UsageDailyBar) => `${this.dataRev}_b_${bar.day}`)
          }
          .alignItems(HorizontalAlign.Start)
          .padding(12)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.line') })
          .width('100%')

          Column({ space: 8 }) {
            Text('模型用量排行')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))
            if (this.dashboard.modelRanks.length === 0) {
              Text('暂无记录，发送消息后将自动统计各模型 Token 消耗')
                .fontSize(12)
                .fontColor($r('app.color.muted'))
            } else {
              ForEach(this.dashboard.modelRanks, (mr: UsageRankRow) => {
                this.rankRowItem(mr, $r('app.color.accent'))
              }, (mr: UsageRankRow) => `${this.dataRev}_m_${mr.key}`)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .padding(12)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.line') })
          .width('100%')

          Column({ space: 8 }) {
            Text('助手用量分布')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))
            if (this.dashboard.personaRanks.length === 0) {
              Text('暂无记录，发送消息后将自动统计各助手 Token 消耗')
                .fontSize(12)
                .fontColor($r('app.color.muted'))
            } else {
              ForEach(this.dashboard.personaRanks, (pr: UsageRankRow) => {
                this.rankRowItem(pr, '#10B981')
              }, (pr: UsageRankRow) => `${this.dataRev}_p_${pr.key}`)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .padding(12)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .border({ width: 1, color: $r('app.color.line') })
          .width('100%')
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: this.embeddedInNav ? (56 + this.winTopInset + 8) : 0,
          bottom: 24 + this.winBottomInset
        })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.embeddedInNav ? 0 : 16 })
    .backgroundColor(Color.Transparent)
  }
}
