import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { Persona, Provider, ScheduledTask } from '../core/Models';
import { computeNextRunMs } from '../core/ScheduleCalc';
import { newId } from '../core/Storage';

@Component
export struct ScheduledTasksPanel {
  @Prop tasks: ScheduledTask[] = [];
  @Prop personas: Persona[] = [];
  @Prop providers: Provider[] = [];
  @Prop embeddedInNav: boolean = false;

  onSaveTasks: (next: ScheduledTask[]) => Promise<void> = async () => {};
  onRunTaskNow: (task: ScheduledTask) => Promise<void> = async () => {};
  onOpenConversation: (chatId: string) => void = () => {};
  onClose: () => void = () => {};

  @StorageProp('immersiveLightEnabled') immersiveLightEnabled: boolean = true;
  @StorageProp('windowTopInsetVp') winTopInset: number = 0;

  @State newName: string = '';
  @State newType: 'daily' | 'weekly' | 'interval' | 'once' = 'daily';
  @State newTimeHHMM: string = '09:00';
  @State newIntervalMin: string = '60';
  @State newWeekdays: number[] = [1, 2, 3, 4, 5];
  @State newPersonaId: string = '';
  @State newProviderId: string = '';
  @State newPrompt: string = '';
  @State runningTaskId: string = '';
  @State statusTip: string = '';

  private readonly wdLabels: string[] = ['日', '一', '二', '三', '四', '五', '六'];

  aboutToAppear(): void {
    if (this.personas.length > 0 && this.newPersonaId.length === 0) {
      this.newPersonaId = this.personas[0].id;
    }
    if (this.providers.length > 0 && this.newProviderId.length === 0) {
      this.newProviderId = this.providers[0].id;
    }
  }

  private personaName(id: string): string {
    return this.personas.find((p: Persona): boolean => p.id === id)?.name || '默认助手';
  }

  private providerName(id: string): string {
    return this.providers.find((p: Provider): boolean => p.id === id)?.name || '默认服务商';
  }

  private scheduleSummary(t: ScheduledTask): string {
    if (t.scheduleType === 'daily') {
      return `每天 ${t.timeHHMM}`;
    }
    if (t.scheduleType === 'weekly') {
      const days = t.weekdays.map((d: number): string => '周' + (this.wdLabels[d] || String(d))).join('/');
      return `${days} ${t.timeHHMM}`;
    }
    if (t.scheduleType === 'interval') {
      return `每 ${t.intervalMinutes} 分钟`;
    }
    return `单次 (${t.runAtMs > 0 ? new Date(t.runAtMs).toLocaleString() : '立即'})`;
  }

  private nextRunText(t: ScheduledTask): string {
    const nextMs = computeNextRunMs(t, Date.now());
    if (nextMs <= 0) {
      return '未排期';
    }
    return `下次: ${new Date(nextMs).toLocaleString()}`;
  }

  private async addTask(): Promise<void> {
    if (this.newName.trim().length === 0 || this.newPrompt.trim().length === 0) {
      this.statusTip = '请填写任务名称和执行指令';
      return;
    }
    const interval = Math.max(1, parseInt(this.newIntervalMin, 10) || 60);
    const created: ScheduledTask = {
      id: 'st_' + newId(),
      name: this.newName.trim(),
      personaId: this.newPersonaId || (this.personas[0]?.id || 'default'),
      providerId: this.newProviderId || (this.providers[0]?.id || ''),
      modelId: '',
      prompt: this.newPrompt.trim(),
      scheduleType: this.newType,
      timeHHMM: /^\d{1,2}:\d{2}$/.test(this.newTimeHHMM.trim()) ? this.newTimeHHMM.trim() : '09:00',
      weekdays: this.newWeekdays.slice(),
      intervalMinutes: interval,
      runAtMs: Date.now() + 3600000,
      enabled: true,
      lastRunAt: this.newType === 'interval' ? Date.now() : 0,
      lastStatus: '等待执行',
      lastConversationId: ''
    };
    const next = [created, ...this.tasks];
    this.newName = '';
    this.newPrompt = '';
    await this.onSaveTasks(next);
    this.statusTip = `已创建定时任务「${created.name}」`;
  }

  private toggleWeekday(wd: number): void {
    const idx = this.newWeekdays.indexOf(wd);
    const next = this.newWeekdays.slice();
    if (idx >= 0 && next.length > 1) {
      next.splice(idx, 1);
    } else if (idx < 0) {
      next.push(wd);
      next.sort((a: number, b: number): number => a - b);
    }
    this.newWeekdays = next;
  }

  build() {
    Column({ space: 12 }) {
      if (!this.embeddedInNav) {
        Row() {
          Text('自动化定时任务')
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

      Scroll() {
        Column({ space: 10 }) {
          if (this.statusTip.length > 0) {
            Text(this.statusTip)
              .fontSize(12)
              .fontColor($r('app.color.accent'))
          }
          Column({ space: 8 }) {
            Text('新建定时任务 (支持应用启动补运行错过的日程)')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))

            TextInput({ text: this.newName, placeholder: '任务名称（如：每日早报摘要）' })
              .height(38)
              .borderRadius(8)
              .backgroundColor($r('app.color.canvas'))
              .onChange((v: string) => {
                this.newName = v;
              })

            Row({ space: 6 }) {
              ForEach(['daily', 'weekly', 'interval', 'once'], (kind: string) => {
                Button(kind === 'daily' ? '每天' : (kind === 'weekly' ? '每周' : (kind === 'interval' ? '间隔' : '单次')))
                  .type(ButtonType.Normal)
                  .layoutWeight(1)
                  .height(30)
                  .fontSize(11)
                  .borderRadius(8)
                  .fontColor(this.newType === kind ? $r('app.color.on_accent') : $r('app.color.ink'))
                  .backgroundColor(this.newType === kind ? $r('app.color.accent') : $r('app.color.canvas'))
                  .onClick(() => {
                    this.newType = kind as 'daily' | 'weekly' | 'interval' | 'once';
                  })
              }, (kind: string) => 'stype_' + kind)
            }
            .width('100%')

            if (this.newType === 'daily' || this.newType === 'weekly') {
              Row({ space: 8 }) {
                Text('执行时刻 HH:MM')
                  .fontSize(12)
                  .fontColor($r('app.color.muted'))
                TextInput({ text: this.newTimeHHMM, placeholder: '09:00' })
                  .width(96)
                  .height(34)
                  .borderRadius(8)
                  .backgroundColor($r('app.color.canvas'))
                  .onChange((v: string) => {
                    this.newTimeHHMM = v;
                  })
              }
              .width('100%')
            }

            if (this.newType === 'weekly') {
              Row({ space: 4 }) {
                ForEach([0, 1, 2, 3, 4, 5, 6], (wd: number) => {
                  Button(this.wdLabels[wd])
                    .type(ButtonType.Normal)
                    .layoutWeight(1)
                    .height(28)
                    .fontSize(11)
                    .borderRadius(6)
                    .fontColor(this.newWeekdays.indexOf(wd) >= 0 ? $r('app.color.on_accent') : $r('app.color.ink'))
                    .backgroundColor(this.newWeekdays.indexOf(wd) >= 0 ? $r('app.color.accent') : $r('app.color.canvas'))
                    .onClick(() => {
                      this.toggleWeekday(wd);
                    })
                }, (wd: number) => 'wd_' + wd)
              }
              .width('100%')
            }

            if (this.newType === 'interval') {
              Row({ space: 8 }) {
                Text('间隔分钟数')
                  .fontSize(12)
                  .fontColor($r('app.color.muted'))
                TextInput({ text: this.newIntervalMin, placeholder: '60' })
                  .width(96)
                  .height(34)
                  .borderRadius(8)
                  .backgroundColor($r('app.color.canvas'))
                  .onChange((v: string) => {
                    this.newIntervalMin = v;
                  })
              }
              .width('100%')
            }

            Row({ space: 6 }) {
              Button(`助手: ${this.personaName(this.newPersonaId)}`)
                .type(ButtonType.Normal)
                .layoutWeight(1)
                .height(32)
                .fontSize(11)
                .borderRadius(8)
                .fontColor($r('app.color.ink'))
                .backgroundColor($r('app.color.canvas'))
                .onClick(() => {
                  if (this.personas.length === 0) return;
                  const idx = this.personas.findIndex((p: Persona): boolean => p.id === this.newPersonaId);
                  this.newPersonaId = this.personas[(idx + 1) % this.personas.length].id;
                })
              Button(`模型: ${this.providerName(this.newProviderId)}`)
                .type(ButtonType.Normal)
                .layoutWeight(1)
                .height(32)
                .fontSize(11)
                .borderRadius(8)
                .fontColor($r('app.color.ink'))
                .backgroundColor($r('app.color.canvas'))
                .onClick(() => {
                  if (this.providers.length === 0) return;
                  const idx = this.providers.findIndex((p: Provider): boolean => p.id === this.newProviderId);
                  this.newProviderId = this.providers[(idx + 1) % this.providers.length].id;
                })
            }
            .width('100%')

            TextArea({ text: this.newPrompt, placeholder: '任务触发时发送给 AI 的提示词（支持 {{date}} 等模板变量）...' })
              .height(74)
              .borderRadius(8)
              .backgroundColor($r('app.color.canvas'))
              .onChange((v: string) => {
                this.newPrompt = v;
              })

            Button('添加定时任务')
              .type(ButtonType.Normal)
              .width('100%')
              .height(38)
              .fontSize(13)
              .borderRadius(8)
              .fontColor($r('app.color.on_accent'))
              .backgroundColor($r('app.color.accent'))
              .onClick(async () => {
                await this.addTask();
              })
          }
          .alignItems(HorizontalAlign.Start)
          .padding(12)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .width('100%')

          if (this.tasks.length === 0) {
            Text('暂无定时任务')
              .fontSize(12)
              .fontColor($r('app.color.muted'))
              .padding(16)
          } else {
            ForEach(this.tasks, (task: ScheduledTask) => {
              Column({ space: 6 }) {
                Row({ space: 8 }) {
                  Column({ space: 2 }) {
                    Text(task.name)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.ink'))
                    Text(`${this.scheduleSummary(task)} · ${this.personaName(task.personaId)}`)
                      .fontSize(11)
                      .fontColor($r('app.color.accent'))
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  Toggle({ type: ToggleType.Switch, isOn: task.enabled })
                    .onChange(async (v: boolean) => {
                      const next = this.tasks.map((item: ScheduledTask): ScheduledTask => {
                        if (item.id !== task.id) return item;
                        return {
                          id: item.id,
                          name: item.name,
                          personaId: item.personaId,
                          providerId: item.providerId,
                          modelId: item.modelId,
                          prompt: item.prompt,
                          scheduleType: item.scheduleType,
                          timeHHMM: item.timeHHMM,
                          weekdays: item.weekdays.slice(),
                          intervalMinutes: item.intervalMinutes,
                          runAtMs: item.runAtMs,
                          enabled: v,
                          lastRunAt: item.lastRunAt,
                          lastStatus: item.lastStatus,
                          lastConversationId: item.lastConversationId
                        };
                      });
                      await this.onSaveTasks(next);
                    })
                    .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
                }
                .width('100%')

                Text(task.prompt)
                  .fontSize(12)
                  .fontColor($r('app.color.muted'))
                  .maxLines(2)

                Text(`${this.nextRunText(task)} · 上次: ${task.lastStatus || '未运行'}`)
                  .fontSize(11)
                  .fontColor($r('app.color.muted'))

                Row({ space: 8 }) {
                  Button(this.runningTaskId === task.id ? '执行中...' : '立即运行')
                    .type(ButtonType.Normal)
                    .height(28)
                    .fontSize(11)
                    .borderRadius(6)
                    .fontColor($r('app.color.on_accent'))
                    .backgroundColor($r('app.color.accent'))
                    .enabled(this.runningTaskId !== task.id)
                    .onClick(async () => {
                      this.runningTaskId = task.id;
                      try {
                        await this.onRunTaskNow(task);
                        this.statusTip = `已执行「${task.name}」并保存新对话`;
                      } finally {
                        this.runningTaskId = '';
                      }
                    })
                  if (task.lastConversationId.length > 0) {
                    Button('查看结果对话')
                      .type(ButtonType.Normal)
                      .height(28)
                      .fontSize(11)
                      .borderRadius(6)
                      .fontColor($r('app.color.accent'))
                      .backgroundColor($r('app.color.tint'))
                      .onClick(() => {
                        this.onOpenConversation(task.lastConversationId);
                      })
                  }
                  Blank()
                  Button('删除')
                    .type(ButtonType.Normal)
                    .height(28)
                    .fontSize(11)
                    .borderRadius(6)
                    .fontColor($r('app.color.warning'))
                    .backgroundColor($r('app.color.canvas'))
                    .onClick(async () => {
                      await this.onSaveTasks(this.tasks.filter((item: ScheduledTask): boolean => item.id !== task.id));
                    })
                }
                .width('100%')
              }
              .alignItems(HorizontalAlign.Start)
              .padding(12)
              .backgroundColor($r('app.color.surface'))
              .borderRadius(12)
              .width('100%')
            }, (task: ScheduledTask) => `${task.id}_${task.lastRunAt}_${task.enabled}`)
          }
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
