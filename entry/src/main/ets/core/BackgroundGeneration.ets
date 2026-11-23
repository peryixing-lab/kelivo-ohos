import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { Callback } from '@kit.BasicServicesKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const BG_DOMAIN = 0x0000;
const BG_TAG = 'KelivoBgGen';

export type GenerationPhase = 'searching' | 'thinking' | 'streaming' | 'tool' | 'image';

export interface TrackedGenerationTask {
  chatId: string;
  title: string;
  phase: GenerationPhase;
  charCount: number;
  startedAt: number;
  updatedAt: number;
}

export interface BackgroundProgressSnapshot {
  title: string;
  detail: string;
  progressValue: number;
  primaryChatId: string;
  activeCount: number;
}

export class GenerationTaskTracker {
  private tasks: Map<string, TrackedGenerationTask> = new Map<string, TrackedGenerationTask>();
  private tickCounter: number = 0;

  register(chatId: string, title: string, nowMs: number = Date.now()): void {
    const cleanTitle = title.trim() || '新对话';
    const existing = this.tasks.get(chatId);
    this.tasks.set(chatId, {
      chatId,
      title: cleanTitle,
      phase: 'streaming',
      charCount: 0,
      startedAt: existing ? existing.startedAt : nowMs,
      updatedAt: nowMs
    });
  }

  update(chatId: string, title: string, phase: GenerationPhase, charCount: number, nowMs: number = Date.now()): void {
    const existing = this.tasks.get(chatId);
    const cleanTitle = title.trim() || existing?.title || '新对话';
    const safeChars = Math.max(0, Math.floor(charCount));
    this.tasks.set(chatId, {
      chatId,
      title: cleanTitle,
      phase,
      charCount: safeChars,
      startedAt: existing ? existing.startedAt : nowMs,
      updatedAt: nowMs
    });
  }

  unregister(chatId: string): void {
    this.tasks.delete(chatId);
    if (this.tasks.size === 0) {
      this.tickCounter = 0;
    }
  }

  clear(): void {
    this.tasks.clear();
    this.tickCounter = 0;
  }

  activeCount(): number {
    return this.tasks.size;
  }

  has(chatId: string): boolean {
    return this.tasks.has(chatId);
  }

  activeChatIds(): string[] {
    return Array.from(this.tasks.keys());
  }

  buildLiveProgressSummary(nowMs: number = Date.now()): BackgroundProgressSnapshot {
    const count = this.tasks.size;
    if (count === 0) {
      return {
        title: 'Kelivo',
        detail: '',
        progressValue: 0,
        primaryChatId: '',
        activeCount: 0
      };
    }

    this.tickCounter += 1;
    let primary: TrackedGenerationTask | undefined = undefined;
    let earliestStart = nowMs;
    let totalChars = 0;

    this.tasks.forEach((task: TrackedGenerationTask) => {
      if (!primary || task.startedAt < primary.startedAt) {
        primary = task;
      }
      if (task.startedAt < earliestStart) {
        earliestStart = task.startedAt;
      }
      totalChars += task.charCount;
    });

    const elapsedSec = Math.max(0, Math.floor((nowMs - earliestStart) / 1000));
    const rawProgress = 5 +
      Math.floor(Math.min(45, elapsedSec * 1.5)) +
      Math.floor(Math.min(35, totalChars / 80)) +
      Math.min(10, Math.floor(this.tickCounter / 2));
    const progressValue = Math.max(1, Math.min(95, rawProgress));
    const mainTask = primary!;

    if (count === 1) {
      const cleanTitle = (mainTask.title.trim() || '新对话').slice(0, 24);
      let detail = '等待模型响应…';
      if (mainTask.phase === 'searching') {
        detail = '正在联网检索…';
      } else if (mainTask.phase === 'thinking') {
        detail = mainTask.charCount > 0 ? `正在深度思考 · 已生成 ${mainTask.charCount} 字` : '正在深度思考…';
      } else if (mainTask.phase === 'tool') {
        detail = '正在执行工具…';
      } else if (mainTask.phase === 'image') {
        detail = '正在生成图片…';
      } else if (mainTask.charCount > 0) {
        detail = `已生成 ${mainTask.charCount} 字`;
      }
      return {
        title: `正在后台生成 · ${cleanTitle}`,
        detail,
        progressValue,
        primaryChatId: mainTask.chatId,
        activeCount: 1
      };
    }

    return {
      title: `${count} 个对话正在后台生成`,
      detail: totalChars > 0 ? `已累计生成 ${totalChars} 字` : '正在并行生成回复…',
      progressValue,
      primaryChatId: mainTask.chatId,
      activeCount: count
    };
  }
}

export class BackgroundGenerationManager {
  private ctx?: common.UIAbilityContext;
  private tracker: GenerationTaskTracker = new GenerationTaskTracker();
  private inBackground: boolean = false;
  private continuousRunning: boolean = false;
  private continuousStarting: boolean = false;
  private continuousNotificationId: number = -1;
  private continuousSlotType: notificationManager.SlotType = notificationManager.SlotType.LIVE_VIEW;
  private suspendDelayId: number = -1;
  private progressTimer: number = -1;
  private lastProgressPushAt: number = 0;
  private downloadTemplateSupported?: boolean = undefined;
  private cancelListenerRegistered: boolean = false;

  private readonly handleContinuousTaskCanceled: Callback<backgroundTaskManager.ContinuousTaskCancelInfo> =
    (_info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
      this.continuousRunning = false;
      this.continuousNotificationId = -1;
      this.stopProgressHeartbeat();
      if (this.inBackground && this.tracker.activeCount() > 0) {
        this.ensureTransientTask();
      }
    };

  attachContext(ctx: common.UIAbilityContext): void {
    this.ctx = ctx;
  }

  isAppInBackground(): boolean {
    return this.inBackground;
  }

  hasActiveTasks(): boolean {
    return this.tracker.activeCount() > 0;
  }

  onForeground(): void {
    this.inBackground = false;
    AppStorage.setOrCreate('appInBackground', false);
    this.cancelTransientTask();
    if (this.tracker.activeCount() > 0 && !this.continuousRunning && !this.continuousStarting) {
      this.startContinuousTask();
    }
  }

  onBackground(): void {
    this.inBackground = true;
    AppStorage.setOrCreate('appInBackground', true);
    if (this.tracker.activeCount() > 0) {
      this.ensureTransientTask();
      if (!this.continuousRunning && !this.continuousStarting) {
        this.startContinuousTask();
      }
      this.pushProgressNotification(true).catch(() => {});
    }
  }

  beginTask(chatId: string, title: string, ctx?: common.UIAbilityContext): void {
    if (ctx) {
      this.ctx = ctx;
    }
    this.tracker.register(chatId, title);
    if (!this.continuousRunning && !this.continuousStarting) {
      this.startContinuousTask();
    } else {
      this.pushProgressNotification(true).catch(() => {});
    }
    if (this.inBackground && !this.continuousRunning) {
      this.ensureTransientTask();
    }
  }

  updateTask(chatId: string, title: string, phase: GenerationPhase, charCount: number): void {
    this.tracker.update(chatId, title, phase, charCount);
    this.pushProgressNotification(false).catch(() => {});
  }

  endTask(chatId: string): void {
    this.tracker.unregister(chatId);
    if (this.tracker.activeCount() === 0) {
      this.stopProgressHeartbeat();
      this.stopContinuousTask();
      this.cancelTransientTask();
    } else {
      this.pushProgressNotification(true).catch(() => {});
    }
  }

  stopAll(): void {
    this.tracker.clear();
    this.stopProgressHeartbeat();
    this.stopContinuousTask();
    this.cancelTransientTask();
    if (this.cancelListenerRegistered) {
      try {
        backgroundTaskManager.off('continuousTaskCancel', this.handleContinuousTaskCanceled);
      } catch (_) {}
      this.cancelListenerRegistered = false;
    }
  }

  private startContinuousTask(): void {
    const ctx = this.ctx;
    if (!ctx || this.continuousRunning || this.continuousStarting || this.tracker.activeCount() === 0) {
      return;
    }
    this.continuousStarting = true;

    if (!this.cancelListenerRegistered) {
      try {
        backgroundTaskManager.on('continuousTaskCancel', this.handleContinuousTaskCanceled);
        this.cancelListenerRegistered = true;
      } catch (_) {}
    }

    const info: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: ctx.abilityInfo.bundleName,
          abilityName: ctx.abilityInfo.name
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };

    wantAgent.getWantAgent(info).then((agent: WantAgent): Promise<backgroundTaskManager.ContinuousTaskNotification> => {
      return backgroundTaskManager.startBackgroundRunning(ctx, ['dataTransfer'], agent);
    }).then((res: backgroundTaskManager.ContinuousTaskNotification) => {
      this.continuousStarting = false;
      if (this.tracker.activeCount() === 0) {
        backgroundTaskManager.stopBackgroundRunning(ctx).catch(() => {});
        return;
      }
      this.continuousRunning = true;
      this.continuousNotificationId = res.notificationId;
      this.continuousSlotType = res.slotType;
      this.startProgressHeartbeat();
      this.pushProgressNotification(true).catch(() => {});
    }).catch((err: Error) => {
      this.continuousStarting = false;
      hilog.warn(BG_DOMAIN, BG_TAG, 'startBackgroundRunning failed: %{public}s', err.message || String(err));
      if (this.inBackground && this.tracker.activeCount() > 0) {
        this.ensureTransientTask();
      }
    });
  }

  private stopContinuousTask(): void {
    this.stopProgressHeartbeat();
    this.continuousRunning = false;
    this.continuousNotificationId = -1;
    const ctx = this.ctx;
    if (ctx) {
      backgroundTaskManager.stopBackgroundRunning(ctx).catch(() => {});
    }
  }

  private startProgressHeartbeat(): void {
    this.stopProgressHeartbeat();
    this.progressTimer = setInterval(() => {
      if (!this.continuousRunning || this.tracker.activeCount() === 0) {
        this.stopProgressHeartbeat();
        return;
      }
      this.pushProgressNotification(false).catch(() => {});
    }, 3000);
  }

  private stopProgressHeartbeat(): void {
    if (this.progressTimer >= 0) {
      clearInterval(this.progressTimer);
      this.progressTimer = -1;
    }
  }

  private ensureTransientTask(): void {
    if (this.suspendDelayId >= 0) {
      return;
    }
    try {
      const info = backgroundTaskManager.requestSuspendDelay('Kelivo background AI generation', () => {
        this.cancelTransientTask();
      });
      this.suspendDelayId = info.requestId;
    } catch (err) {
      hilog.warn(BG_DOMAIN, BG_TAG, 'requestSuspendDelay failed: %{public}s', (err as Error).message || String(err));
    }
  }

  private cancelTransientTask(): void {
    if (this.suspendDelayId < 0) {
      return;
    }
    const id = this.suspendDelayId;
    this.suspendDelayId = -1;
    try {
      backgroundTaskManager.cancelSuspendDelay(id);
    } catch (_) {}
  }

  private async pushProgressNotification(force: boolean): Promise<void> {
    if (!this.continuousRunning || this.continuousNotificationId < 0 || this.tracker.activeCount() === 0) {
      return;
    }
    const now = Date.now();
    if (!force && now - this.lastProgressPushAt < 2000) {
      return;
    }
    if (this.downloadTemplateSupported === undefined) {
      try {
        this.downloadTemplateSupported = await notificationManager.isSupportTemplate('downloadTemplate');
      } catch (_) {
        this.downloadTemplateSupported = false;
      }
    }
    if (!this.downloadTemplateSupported || !this.continuousRunning || this.continuousNotificationId < 0 || this.tracker.activeCount() === 0) {
      return;
    }

    this.lastProgressPushAt = now;
    const snap = this.tracker.buildLiveProgressSummary(now);
    const tmplData: Record<string, Object> = {};
    tmplData['title'] = snap.title;
    tmplData['fileName'] = snap.detail;
    tmplData['progressValue'] = snap.progressValue;

    const req: notificationManager.NotificationRequest = {
      id: this.continuousNotificationId,
      notificationSlotType: this.continuousSlotType,
      template: {
        name: 'downloadTemplate',
        data: tmplData
      },
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW,
        systemLiveView: {
          title: snap.title,
          text: snap.detail,
          typeCode: 8
        }
      }
    };

    try {
      await notificationManager.publish(req);
    } catch (_) {}
  }
}

export const backgroundGenerationManager: BackgroundGenerationManager = new BackgroundGenerationManager();
