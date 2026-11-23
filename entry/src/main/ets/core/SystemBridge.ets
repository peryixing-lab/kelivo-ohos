import { common, ConfigurationConstant, Want, wantAgent, WantAgent } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { notificationManager } from '@kit.NotificationKit';
import { vibrator } from '@kit.SensorServiceKit';
import { systemShare } from '@kit.ShareKit';

let nextNotifyId: number = 1001;

export function applySystemColorMode(
  ctx: common.UIAbilityContext | undefined,
  mode: 'system' | 'light' | 'dark'
): void {
  if (!ctx) {
    return;
  }
  try {
    let target = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    if (mode === 'light') {
      target = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    } else if (mode === 'dark') {
      target = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    ctx.getApplicationContext().setColorMode(target);
  } catch (_) {
    // Ignore unsupported platform colorMode failures
  }
}

export async function applyKeepScreenOn(
  ctx: common.UIAbilityContext | undefined,
  keepOn: boolean
): Promise<void> {
  if (!ctx) {
    return;
  }
  try {
    const win = await window.getLastWindow(ctx);
    await win.setWindowKeepScreenOn(keepOn);
  } catch (_) {
    // Window may be detached or minimized
  }
}

export function triggerHapticFeedback(enabled: boolean, durationMs: number = 18): void {
  if (!enabled) {
    return;
  }
  try {
    const effect: vibrator.VibrateTime = {
      type: 'time',
      duration: Math.max(10, Math.min(200, durationMs))
    };
    const attr: vibrator.VibrateAttribute = {
      id: 0,
      usage: 'touch'
    };
    vibrator.startVibration(effect, attr).catch(() => {});
  } catch (_) {
    // Safe fallback if vibrator is unavailable
  }
}

export async function ensureNotificationPermission(ctx: common.UIAbilityContext | undefined): Promise<void> {
  if (!ctx) {
    return;
  }
  try {
    await notificationManager.requestEnableNotification(ctx);
  } catch (_) {
    // Already enabled or denied by user
  }
}

export async function notifyGenerationComplete(
  ctx: common.UIAbilityContext | undefined,
  enabled: boolean,
  title: string,
  previewText: string,
  chatId?: string
): Promise<void> {
  if (!enabled || !ctx) {
    return;
  }
  try {
    const cleanTitle = title.trim().length > 0 ? title.trim() : 'Kelivo';
    const cleanBody = previewText.trim().length > 0 ? previewText.trim().slice(0, 120) : '回复已生成完成';
    const basic: notificationManager.NotificationBasicContent = {
      title: cleanTitle,
      text: cleanBody
    };
    const content: notificationManager.NotificationContent = {
      notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
      normal: basic
    };
    nextNotifyId += 1;
    let agent: WantAgent | undefined = undefined;
    try {
      const wantParams: Record<string, Object> = {};
      const cleanChatId = chatId ? chatId.trim() : '';
      if (cleanChatId.length > 0) {
        wantParams['openChatId'] = cleanChatId;
      }
      const info: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: ctx.abilityInfo.bundleName,
            abilityName: ctx.abilityInfo.name,
            parameters: cleanChatId.length > 0 ? wantParams : undefined
          }
        ],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: nextNotifyId,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      agent = await wantAgent.getWantAgent(info);
    } catch (_) {
      agent = undefined;
    }
    const req: notificationManager.NotificationRequest = {
      id: nextNotifyId,
      content,
      wantAgent: agent,
      tapDismissed: true
    };
    await notificationManager.publish(req);
  } catch (_) {
    // Ignore when notification permission is not granted
  }
}

export function extractIncomingShareText(want: Want | undefined): string {
  if (!want) {
    return '';
  }
  const params = want.parameters;
  if (params) {
    const candidateKeys = ['text', 'ohos.extra.param.key.shareText', 'ability.params.text', 'subject', 'title'];
    for (let i = 0; i < candidateKeys.length; i++) {
      const k = candidateKeys[i];
      const val = params[k];
      if (typeof val === 'string' && val.trim().length > 0) {
        return val.trim();
      }
    }
    const streamVal = params['ability.params.stream'];
    if (Array.isArray(streamVal) && streamVal.length > 0) {
      return String(streamVal[0]);
    }
  }
  if (want.uri && want.uri.trim().length > 0) {
    return want.uri.trim();
  }
  return '';
}

export function publishIncomingShareWant(want: Want | undefined): void {
  const txt = extractIncomingShareText(want);
  if (txt.length > 0) {
    AppStorage.setOrCreate('pendingShareText', txt);
  }
}

export function extractIncomingOpenChatId(want: Want | undefined): string {
  if (!want || !want.parameters) {
    return '';
  }
  const raw = want.parameters['openChatId'];
  return typeof raw === 'string' && raw.trim().length > 0 ? raw.trim() : '';
}

export function publishIncomingOpenChatWant(want: Want | undefined): void {
  const chatId = extractIncomingOpenChatId(want);
  if (chatId.length > 0) {
    AppStorage.setOrCreate('pendingOpenChatId', chatId);
  }
}

export async function sharePlainText(
  ctx: common.UIAbilityContext | undefined,
  text: string,
  title: string = '分享消息'
): Promise<boolean> {
  if (!ctx || !text.trim()) {
    return false;
  }
  try {
    const data = new systemShare.SharedData({
      utd: 'general.plain-text',
      content: text,
      title: title.trim().slice(0, 60) || '分享消息'
    });
    const controller = new systemShare.ShareController(data);
    await controller.show(ctx, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DEFAULT
    });
    return true;
  } catch (_) {
    return false;
  }
}
