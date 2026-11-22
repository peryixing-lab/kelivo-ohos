import { Permissions, abilityAccessCtrl, common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { calendarManager } from '@kit.CalendarKit';
import { geoLocationManager } from '@kit.LocationKit';
import { evaluateMathExpression } from './MathEval';
import { ChatMessage, Conversation } from './Models';
import { ToolExecutionOutput } from './ToolLoop';
import { RegisteredTool } from './ToolRegistry';

export interface AskUserPromptRequest {
  question: string;
  options: string[];
  placeholder: string;
}

export interface DeviceToolBridge {
  hostContext: common.UIAbilityContext;
  speakText: (text: string) => Promise<void>;
  askUserInput: (req: AskUserPromptRequest) => Promise<string>;
  getConversations: () => Conversation[];
  getActiveConversation: () => Conversation | undefined;
}

async function requestRuntimePermissions(
  ctx: common.UIAbilityContext,
  perms: Permissions[]
): Promise<boolean> {
  try {
    const mgr = abilityAccessCtrl.createAtManager();
    const res = await mgr.requestPermissionsFromUser(ctx, perms);
    for (let i = 0; i < res.authResults.length; i++) {
      if (res.authResults[i] !== 0) {
        return false;
      }
    }
    return true;
  } catch (_) {
    return false;
  }
}

export function buildDeviceTools(): RegisteredTool[] {
  return [
    {
      declaration: {
        name: 'get_time_info',
        description: '获取设备当前精确本地日期时间、星期、时区及 Unix 毫秒时间戳。',
        parametersJson: '{"type":"object","properties":{}}'
      },
      source: 'device',
      requiresApproval: false
    },
    {
      declaration: {
        name: 'clipboard_tool',
        description: '读取或写入系统剪贴板文本（需要时触发系统权限）。',
        parametersJson:
          '{"type":"object","properties":{"action":{"type":"string","enum":["read","write"],"description":"read 读取剪贴板，write 写入剪贴板"},"text":{"type":"string","description":"write 时要复制的文本"}},"required":["action"]}'
      },
      source: 'device',
      requiresApproval: false
    },
    {
      declaration: {
        name: 'calculate',
        description: '安全精确求值数学与科学计算表达式（支持 + - * / % ^ ()、pi、e、sin/cos/tan/sqrt/abs/ln/log10/pow/min/max/round）。',
        parametersJson:
          '{"type":"object","properties":{"expression":{"type":"string","description":"数学表达式"}},"required":["expression"]}'
      },
      source: 'device',
      requiresApproval: false
    },
    {
      declaration: {
        name: 'text_to_speech',
        description: '使用当前配置的 TTS 引擎朗读一段文本给用户听。',
        parametersJson:
          '{"type":"object","properties":{"text":{"type":"string","description":"要朗读的文本"}},"required":["text"]}'
      },
      source: 'device',
      requiresApproval: false
    },
    {
      declaration: {
        name: 'ask_user_input',
        description: '向用户展示交互式追问卡片（支持预设选项和自由输入）并等待用户确认后继续执行工具循环。',
        parametersJson:
          '{"type":"object","properties":{"question":{"type":"string","description":"提问正文"},"options":{"type":"array","items":{"type":"string"},"description":"可选预设回答选项"},"placeholder":{"type":"string","description":"输入框占位提示"}},"required":["question"]}'
      },
      source: 'device',
      requiresApproval: false
    },
    {
      declaration: {
        name: 'read_chat_context',
        description: '读取当前对话或历史会话列表，用于跨会话引用和回顾上下文。',
        parametersJson:
          '{"type":"object","properties":{"mode":{"type":"string","enum":["messages","conversations"]},"conversation_id":{"type":"string","description":"可选会话 ID"},"limit":{"type":"integer","description":"返回条数，默认 12"}}}'
      },
      source: 'device',
      requiresApproval: false
    },
    {
      declaration: {
        name: 'calendar_query',
        description: '按未来天数或标题关键词查询系统日历日程。',
        parametersJson:
          '{"type":"object","properties":{"days_ahead":{"type":"integer","description":"查询未来多少天，默认 7"},"keyword":{"type":"string","description":"按日程标题过滤"}}}'
      },
      source: 'device',
      requiresApproval: false
    },
    {
      declaration: {
        name: 'calendar_create',
        description: '在系统日历中创建一个新的日程提醒事件。',
        parametersJson:
          '{"type":"object","properties":{"title":{"type":"string","description":"日程标题"},"start_iso":{"type":"string","description":"开始时间 ISO 字符串或时间戳"},"end_iso":{"type":"string","description":"结束时间，默认开始后 1 小时"},"description":{"type":"string","description":"日程备注"}},"required":["title","start_iso"]}'
      },
      source: 'device',
      requiresApproval: true
    },
    {
      declaration: {
        name: 'get_current_location',
        description: '获取当前设备的地理经纬度定位（仅在用户授权位置权限后返回）。',
        parametersJson: '{"type":"object","properties":{}}'
      },
      source: 'device',
      requiresApproval: true
    }
  ];
}

function parseTimeMs(raw: Object | undefined): number {
  if (typeof raw === 'number') {
    return raw;
  }
  const s = String(raw || '').trim();
  if (/^\d{10,13}$/.test(s)) {
    const n = Number(s);
    return s.length === 10 ? n * 1000 : n;
  }
  const t = Date.parse(s);
  return Number.isNaN(t) ? Date.now() + 3600000 : t;
}

export async function executeDeviceTool(
  toolName: string,
  argsJson: string,
  bridge: DeviceToolBridge
): Promise<ToolExecutionOutput> {
  let args: Record<string, Object> = {};
  try {
    args = JSON.parse(argsJson || '{}') as Record<string, Object>;
  } catch (_) {
    return { text: '参数 JSON 解析失败', isError: true };
  }

  try {
    if (toolName === 'get_time_info') {
      const now = new Date();
      const weekdays = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
      const tzOffsetMin = -now.getTimezoneOffset();
      const sign = tzOffsetMin >= 0 ? '+' : '-';
      const absH = Math.floor(Math.abs(tzOffsetMin) / 60);
      const absM = Math.abs(tzOffsetMin) % 60;
      const tz = `UTC${sign}${absH < 10 ? '0' : ''}${absH}:${absM < 10 ? '0' : ''}${absM}`;
      return {
        text: JSON.stringify({
          localString: now.toLocaleString(),
          iso: now.toISOString(),
          weekday: weekdays[now.getDay()] || '',
          timezone: tz,
          timestampMs: now.getTime()
        }, null, 2)
      };
    }

    if (toolName === 'calculate') {
      const expr = String(args['expression'] || '');
      const val = evaluateMathExpression(expr);
      return { text: `${expr} = ${val}` };
    }

    if (toolName === 'clipboard_tool') {
      const action = String(args['action'] || 'read');
      const pb = pasteboard.getSystemPasteboard();
      if (action === 'write') {
        const text = String(args['text'] || '');
        await pb.setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text));
        return { text: `已写入系统剪贴板 (${text.length} 字符)` };
      }
      try {
        const data = await pb.getData();
        const txt = data.getPrimaryText() || '';
        return { text: txt.length > 0 ? txt : '(剪贴板为空)' };
      } catch (_) {
        return { text: '鸿蒙系统隐私策略禁止后台静默读取剪贴板，请直接在输入框或粘贴按钮中粘贴内容。', isError: true };
      }
    }

    if (toolName === 'text_to_speech') {
      const text = String(args['text'] || '').trim();
      if (text.length === 0) {
        return { text: '朗读文本不能为空', isError: true };
      }
      await bridge.speakText(text);
      return { text: `已开始朗读 (${text.length} 字符)` };
    }

    if (toolName === 'ask_user_input') {
      const question = String(args['question'] || '请提供进一步说明：');
      const placeholder = typeof args['placeholder'] === 'string' ? (args['placeholder'] as string) : '输入您的回答...';
      const optsRaw = args['options'];
      const options: string[] = [];
      if (Array.isArray(optsRaw)) {
        for (let i = 0; i < optsRaw.length; i++) {
          const item = String(optsRaw[i]).trim();
          if (item.length > 0) {
            options.push(item);
          }
        }
      }
      const reply = await bridge.askUserInput({ question, options, placeholder });
      return { text: reply.length > 0 ? `用户回复：${reply}` : '用户取消或未填写输入' };
    }

    if (toolName === 'read_chat_context') {
      const mode = String(args['mode'] || 'messages');
      const limit = Math.max(1, Math.min(40, Number(args['limit'] || 12)));
      const allChats = bridge.getConversations();
      if (mode === 'conversations') {
        const lines = allChats.slice(0, limit).map((c: Conversation): string =>
          `- id=${c.id} | ${c.title} | ${c.messages.length}条 | ${new Date(c.updated).toLocaleString()}`
        );
        return { text: lines.length > 0 ? lines.join('\n') : '暂无会话' };
      }
      const cid = typeof args['conversation_id'] === 'string' ? (args['conversation_id'] as string) : '';
      const target = cid.length > 0
        ? allChats.find((c: Conversation): boolean => c.id === cid)
        : bridge.getActiveConversation();
      if (!target) {
        return { text: '未找到指定会话' };
      }
      const slice = target.messages.slice(Math.max(0, target.messages.length - limit));
      const lines = slice.map((m: ChatMessage): string => `[${m.role}] ${m.text.slice(0, 600)}`);
      return { text: `# 会话：${target.title}\n${lines.join('\n\n')}` };
    }

    if (toolName === 'calendar_query') {
      const perms: Permissions[] = ['ohos.permission.READ_CALENDAR', 'ohos.permission.WRITE_CALENDAR'];
      const granted = await requestRuntimePermissions(bridge.hostContext, perms);
      if (!granted) {
        return { text: '用户未授予日历权限，无法查询日程。', isError: true };
      }
      const mgr = calendarManager.getCalendarManager(bridge.hostContext);
      const cal = await mgr.getCalendar();
      const daysAhead = Math.max(1, Math.min(90, Number(args['days_ahead'] || 7)));
      const keyword = typeof args['keyword'] === 'string' ? (args['keyword'] as string).trim() : '';
      const nowMs = Date.now();
      const filter = keyword.length > 0
        ? calendarManager.EventFilter.filterByTitle(keyword)
        : calendarManager.EventFilter.filterByTime(nowMs - 86400000, nowMs + daysAhead * 86400000);
      const events = await cal.getEvents(filter);
      if (!events || events.length === 0) {
        return { text: '指定范围内暂无日历日程' };
      }
      const lines = events.slice(0, 25).map((ev: calendarManager.Event): string =>
        `- ${ev.title || '(无标题)'} | ${new Date(ev.startTime).toLocaleString()} ~ ${new Date(ev.endTime).toLocaleString()}`
      );
      return { text: lines.join('\n') };
    }

    if (toolName === 'calendar_create') {
      const perms: Permissions[] = ['ohos.permission.READ_CALENDAR', 'ohos.permission.WRITE_CALENDAR'];
      const granted = await requestRuntimePermissions(bridge.hostContext, perms);
      if (!granted) {
        return { text: '用户未授予日历权限，无法创建日程。', isError: true };
      }
      const mgr = calendarManager.getCalendarManager(bridge.hostContext);
      const cal = await mgr.getCalendar();
      const startTime = parseTimeMs(args['start_iso']);
      const endTime = args['end_iso'] ? parseTimeMs(args['end_iso']) : startTime + 3600000;
      const ev: calendarManager.Event = {
        type: calendarManager.EventType.NORMAL,
        title: String(args['title'] || 'Kelivo 提醒'),
        startTime,
        endTime: Math.max(startTime + 60000, endTime),
        description: typeof args['description'] === 'string' ? (args['description'] as string) : ''
      };
      const id = await cal.addEvent(ev);
      return { text: `已创建系统日历日程「${ev.title}」(id=${id})，时间：${new Date(startTime).toLocaleString()}` };
    }

    if (toolName === 'get_current_location') {
      const perms: Permissions[] = ['ohos.permission.APPROXIMATELY_LOCATION', 'ohos.permission.LOCATION'];
      const granted = await requestRuntimePermissions(bridge.hostContext, perms);
      if (!granted) {
        return { text: '用户未授予位置权限，无法获取定位。', isError: true };
      }
      const req: geoLocationManager.SingleLocationRequest = {
        locatingPriority: geoLocationManager.LocatingPriority.PRIORITY_LOCATING_SPEED,
        locatingTimeoutMs: 10000
      };
      const loc = await geoLocationManager.getCurrentLocation(req);
      return {
        text: JSON.stringify({
          latitude: loc.latitude,
          longitude: loc.longitude,
          altitude: loc.altitude,
          accuracyMeters: loc.accuracy
        }, null, 2)
      };
    }

    return { text: `未知设备工具: ${toolName}`, isError: true };
  } catch (e) {
    return { text: `工具 ${toolName} 执行异常: ${(e as Error).message || String(e)}`, isError: true };
  }
}
