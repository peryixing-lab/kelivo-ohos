import { pasteboard } from '@kit.BasicServicesKit';
import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { clearDirectoryFiles, computeStorageBreakdown, StorageBreakdown } from '../core/AttachmentStore';
import { ContextLogEntry, RequestLogEntry, ToolSchemaOverride } from '../core/Models';

export interface ToolSchemaCandidate {
  name: string;
  defaultDescription: string;
  source: string;
}

@Component
export struct DiagnosticsPanel {
  @Prop requestLogs: RequestLogEntry[] = [];
  @Prop contextLogs: ContextLogEntry[] = [];
  @Prop toolCandidates: ToolSchemaCandidate[] = [];
  @Prop toolOverrides: ToolSchemaOverride[] = [];
  @Prop filesDir: string = '';
  @Prop dbDir: string = '';
  @Prop embeddedInNav: boolean = false;
  initialTab: number = 0;

  onRefreshLogs: () => Promise<void> = async () => {};
  onClearRequestLogs: () => Promise<void> = async () => {};
  onClearContextLogs: () => Promise<void> = async () => {};
  onSaveToolOverrides: (overrides: ToolSchemaOverride[]) => Promise<void> = async () => {};
  onClose: () => void = () => {};

  @StorageProp('immersiveLightEnabled') immersiveLightEnabled: boolean = true;
  @StorageProp('windowTopInsetVp') winTopInset: number = 0;

  @State currentTab: number = 0; // 0: 请求日志, 1: 上下文日志, 2: 存储分析, 3: 工具Schema
  @State onlyErrors: boolean = false;
  @State expandedId: string = '';
  @State storageInfo: StorageBreakdown = {
    databaseBytes: 0,
    attachmentsBytes: 0,
    snapshotsBytes: 0,
    workspacesBytes: 0,
    skillsBytes: 0,
    totalBytes: 0
  };
  @State statusTip: string = '';

  aboutToAppear(): void {
    this.currentTab = this.initialTab;
    this.refreshStorage();
  }

  private async refreshStorage(): Promise<void> {
    if (this.filesDir.length === 0) {
      return;
    }
    this.storageInfo = await computeStorageBreakdown(this.filesDir, this.dbDir || this.filesDir);
  }

  private formatBytes(bytes: number): string {
    if (bytes >= 1048576) {
      return `${(bytes / 1048576).toFixed(2)} MB`;
    }
    if (bytes >= 1024) {
      return `${(bytes / 1024).toFixed(1)} KB`;
    }
    return `${bytes} B`;
  }

  private formatTs(ts: number): string {
    const d = new Date(ts);
    const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
    return `${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
  }

  private filteredReqLogs(): RequestLogEntry[] {
    if (!this.onlyErrors) {
      return this.requestLogs;
    }
    return this.requestLogs.filter((r) => r.error.length > 0 || r.status >= 400);
  }

  private getOverride(toolName: string): ToolSchemaOverride | undefined {
    return this.toolOverrides.find((o) => o.toolName === toolName);
  }

  private async updateOverride(toolName: string, enabled: boolean, customDesc: string): Promise<void> {
    const next = this.toolOverrides.filter((o) => o.toolName !== toolName);
    next.push({
      toolName,
      enabled,
      customDescription: customDesc
    });
    await this.onSaveToolOverrides(next);
  }

  private async copyText(label: string, content: string): Promise<void> {
    try {
      await pasteboard.getSystemPasteboard().setData(
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, content)
      );
      this.statusTip = `已复制${label}到剪贴板`;
    } catch (e) {
      this.statusTip = `复制失败: ${String(e)}`;
    }
  }

  @Builder
  private tabPill(label: string, idx: number) {
    Button(label)
      .type(ButtonType.Normal)
      .height(32)
      .fontSize(12)
      .fontColor(this.currentTab === idx ? $r('app.color.on_accent') : $r('app.color.ink'))
      .backgroundColor(this.currentTab === idx ? $r('app.color.accent') : $r('app.color.surface'))
      .borderRadius(16)
      .padding({ left: 10, right: 10 })
      .onClick(() => {
        this.currentTab = idx;
      })
  }

  @Builder
  private renderRequestLogsTab() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Button(this.onlyErrors ? '仅看异常 · 开' : '全部请求')
          .type(ButtonType.Normal)
          .height(30)
          .fontSize(11)
          .borderRadius(8)
          .fontColor(this.onlyErrors ? $r('app.color.on_accent') : $r('app.color.ink'))
          .backgroundColor(this.onlyErrors ? $r('app.color.warning') : $r('app.color.surface'))
          .onClick(() => {
            this.onlyErrors = !this.onlyErrors;
          })
        Blank()
        Button('刷新')
          .type(ButtonType.Normal)
          .height(30)
          .fontSize(11)
          .borderRadius(8)
          .fontColor($r('app.color.accent'))
          .backgroundColor($r('app.color.tint'))
          .onClick(async () => {
            await this.onRefreshLogs();
          })
        Button('清空')
          .type(ButtonType.Normal)
          .height(30)
          .fontSize(11)
          .borderRadius(8)
          .fontColor($r('app.color.warning'))
          .backgroundColor($r('app.color.surface'))
          .onClick(async () => {
            await this.onClearRequestLogs();
          })
      }
      .width('100%')

      if (this.filteredReqLogs().length === 0) {
        Text('暂无 HTTP 请求日志')
          .fontSize(12)
          .fontColor($r('app.color.muted'))
          .padding(16)
      } else {
        ForEach(this.filteredReqLogs(), (entry: RequestLogEntry) => {
          Column({ space: 6 }) {
            Row({ space: 6 }) {
              Text(`${entry.status || (entry.error ? 'ERR' : 'OK')} · ${entry.provider}/${entry.model}`)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(entry.error.length > 0 || entry.status >= 400 ? $r('app.color.warning') : $r('app.color.ink'))
                .layoutWeight(1)
              Text(`${entry.durationMs}ms · ${this.formatTs(entry.ts)}`)
                .fontSize(10)
                .fontColor($r('app.color.muted'))
            }
            .width('100%')

            Text(entry.url)
              .fontSize(10)
              .fontColor($r('app.color.muted'))
              .maxLines(1)

            if (entry.error.length > 0) {
              Text(entry.error)
                .fontSize(11)
                .fontColor($r('app.color.warning'))
            }

            if (this.expandedId === entry.id) {
              Column({ space: 6 }) {
                Row() {
                  Text('请求预览')
                    .fontSize(11)
                    .fontColor($r('app.color.accent'))
                  Blank()
                  Button('复制详情')
                    .type(ButtonType.Normal)
                    .height(24)
                    .fontSize(10)
                    .borderRadius(6)
                    .fontColor($r('app.color.accent'))
                    .backgroundColor($r('app.color.tint'))
                    .onClick(async () => {
                      await this.copyText('请求日志', JSON.stringify(entry, null, 2));
                    })
                }
                .width('100%')
                Text(entry.reqPreview)
                  .fontSize(11)
                  .fontColor($r('app.color.ink'))
                  .copyOption(CopyOptions.LocalDevice)
                Text('响应预览')
                  .fontSize(11)
                  .fontColor($r('app.color.accent'))
                Text(entry.respPreview)
                  .fontSize(11)
                  .fontColor($r('app.color.ink'))
                  .copyOption(CopyOptions.LocalDevice)
              }
              .padding(8)
              .backgroundColor($r('app.color.canvas'))
              .borderRadius(8)
              .width('100%')
            }
          }
          .alignItems(HorizontalAlign.Start)
          .padding(10)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(10)
          .width('100%')
          .onClick(() => {
            this.expandedId = this.expandedId === entry.id ? '' : entry.id;
          })
        }, (entry: RequestLogEntry) => entry.id)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private renderContextLogsTab() {
    Column({ space: 8 }) {
      Row() {
        Text('查看实际发送给模型的上下文装配结果')
          .fontSize(12)
          .fontColor($r('app.color.muted'))
        Blank()
        Button('清空')
          .type(ButtonType.Normal)
          .height(30)
          .fontSize(11)
          .borderRadius(8)
          .fontColor($r('app.color.warning'))
          .backgroundColor($r('app.color.surface'))
          .onClick(async () => {
            await this.onClearContextLogs();
          })
      }
      .width('100%')

      if (this.contextLogs.length === 0) {
        Text('暂无上下文快照记录')
          .fontSize(12)
          .fontColor($r('app.color.muted'))
          .padding(16)
      } else {
        ForEach(this.contextLogs, (clog: ContextLogEntry) => {
          Column({ space: 6 }) {
            Row({ space: 6 }) {
              Text(`${clog.model} · ~${clog.tokenEstimate} tokens`)
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.ink'))
                .layoutWeight(1)
              Text(this.formatTs(clog.ts))
                .fontSize(10)
                .fontColor($r('app.color.muted'))
              Button('复制')
                .type(ButtonType.Normal)
                .height(24)
                .fontSize(10)
                .borderRadius(6)
                .fontColor($r('app.color.accent'))
                .backgroundColor($r('app.color.tint'))
                .onClick(async () => {
                  await this.copyText('上下文 JSON', clog.payloadJson);
                })
            }
            .width('100%')

            Text(this.expandedId === clog.id ? clog.payloadJson : clog.payloadJson.slice(0, 220))
              .fontSize(11)
              .fontColor($r('app.color.muted'))
              .copyOption(CopyOptions.LocalDevice)
          }
          .alignItems(HorizontalAlign.Start)
          .padding(10)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(10)
          .width('100%')
          .onClick(() => {
            this.expandedId = this.expandedId === clog.id ? '' : clog.id;
          })
        }, (clog: ContextLogEntry) => clog.id)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private storageRow(label: string, sizeBytes: number, subDir: string) {
    Row({ space: 8 }) {
      Column({ space: 2 }) {
        Text(label)
          .fontSize(14)
          .fontColor($r('app.color.ink'))
        Text(this.formatBytes(sizeBytes))
          .fontSize(12)
          .fontColor($r('app.color.accent'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (subDir.length > 0) {
        Button('清理目录')
          .type(ButtonType.Normal)
          .height(30)
          .fontSize(11)
          .borderRadius(8)
          .fontColor($r('app.color.warning'))
          .backgroundColor($r('app.color.canvas'))
          .onClick(async () => {
            const removed = await clearDirectoryFiles(`${this.filesDir}/${subDir}`);
            await this.refreshStorage();
            this.statusTip = `已从 ${subDir} 清理 ${removed} 个缓存文件`;
          })
      }
    }
    .padding(12)
    .backgroundColor($r('app.color.surface'))
    .borderRadius(10)
    .width('100%')
  }

  @Builder
  private renderStorageTab() {
    Column({ space: 10 }) {
      Row() {
        Text(`应用沙箱总占用：${this.formatBytes(this.storageInfo.totalBytes)}`)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
        Blank()
        Button('重新统计')
          .type(ButtonType.Normal)
          .height(30)
          .fontSize(11)
          .borderRadius(8)
          .fontColor($r('app.color.accent'))
          .backgroundColor($r('app.color.tint'))
          .onClick(async () => {
            await this.refreshStorage();
          })
      }
      .width('100%')

      this.storageRow('SQLite 对话与统计数据库', this.storageInfo.databaseBytes, '')
      this.storageRow('附件文件缓存 (attachments)', this.storageInfo.attachmentsBytes, 'attachments')
      this.storageRow('本地备份快照 (snapshots)', this.storageInfo.snapshotsBytes, 'snapshots')
      this.storageRow('沙箱工作区文件 (workspaces)', this.storageInfo.workspacesBytes, 'workspaces')
      this.storageRow('已安装 Skills (skills)', this.storageInfo.skillsBytes, 'skills')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private renderToolSchemaTab() {
    Column({ space: 10 }) {
      Text('覆写注册工具的全局开关与发送给模型的英文/中文 Schema 描述')
        .fontSize(12)
        .fontColor($r('app.color.muted'))

      ForEach(this.toolCandidates, (cand: ToolSchemaCandidate) => {
        Column({ space: 6 }) {
          Row({ space: 6 }) {
            Text(`${cand.name} (${cand.source})`)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))
              .layoutWeight(1)
            Toggle({
              type: ToggleType.Switch,
              isOn: this.getOverride(cand.name) ? this.getOverride(cand.name)!.enabled : true
            })
              .onChange(async (v: boolean) => {
                const cur = this.getOverride(cand.name);
                await this.updateOverride(cand.name, v, cur ? cur.customDescription : '');
              })
              .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
          }
          .width('100%')

          TextArea({
            text: this.getOverride(cand.name)?.customDescription || '',
            placeholder: `默认描述：${cand.defaultDescription}`
          })
            .height(58)
            .borderRadius(8)
            .backgroundColor($r('app.color.canvas'))
            .onChange(async (v: string) => {
              const cur = this.getOverride(cand.name);
              await this.updateOverride(cand.name, cur ? cur.enabled : true, v);
            })
        }
        .padding(10)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(10)
        .width('100%')
      }, (cand: ToolSchemaCandidate) => cand.name)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  build() {
    Column({ space: 12 }) {
      if (!this.embeddedInNav) {
        Row() {
          Text('调试诊断与存储分析')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.ink'))
          Blank()
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

      Row({ space: 6 }) {
        this.tabPill('请求日志', 0)
        this.tabPill('上下文', 1)
        this.tabPill('存储清理', 2)
        this.tabPill('工具Schema', 3)
      }
      .width('100%')

      if (this.statusTip.length > 0) {
        Text(this.statusTip)
          .fontSize(12)
          .fontColor($r('app.color.accent'))
      }

      Scroll() {
        Column({ space: 10 }) {
          if (this.currentTab === 0) {
            this.renderRequestLogsTab()
          } else if (this.currentTab === 1) {
            this.renderContextLogsTab()
          } else if (this.currentTab === 2) {
            this.renderStorageTab()
          } else {
            this.renderToolSchemaTab()
          }
        }
        .width('100%')
        .padding({ bottom: 48 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: this.embeddedInNav ? (56 + this.winTopInset + 4) : 16, bottom: 0 })
    .backgroundColor(Color.Transparent)
  }
}
