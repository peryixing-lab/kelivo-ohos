import { ScheduledTask } from './Models';

export interface ParsedHHMM {
  hour: number;
  minute: number;
}

export function parseTimeHHMM(hhmm: string): ParsedHHMM {
  const parts = (hhmm || '09:00').trim().split(':');
  const h = parseInt(parts[0] || '9', 10);
  const m = parseInt(parts[1] || '0', 10);
  return {
    hour: Number.isNaN(h) ? 9 : Math.max(0, Math.min(23, h)),
    minute: Number.isNaN(m) ? 0 : Math.max(0, Math.min(59, m))
  };
}

function daySlotMs(refMs: number, dayOffset: number, hour: number, minute: number): number {
  const d = new Date(refMs + dayOffset * 86400000);
  d.setHours(hour, minute, 0, 0);
  return d.getTime();
}

/**
 * Computes the next trigger timestamp strictly after fromMs (or 0 if inactive / completed once task).
 */
export function computeNextRunMs(task: ScheduledTask, fromMs: number): number {
  if (!task.enabled) {
    return 0;
  }
  if (task.scheduleType === 'once') {
    if (task.lastRunAt > 0) {
      return 0;
    }
    return task.runAtMs;
  }
  if (task.scheduleType === 'interval') {
    const intervalMs = Math.max(1, task.intervalMinutes || 60) * 60000;
    const base = task.lastRunAt > 0 ? task.lastRunAt : fromMs;
    return base + intervalMs;
  }
  const hm = parseTimeHHMM(task.timeHHMM);
  if (task.scheduleType === 'daily') {
    const todaySlot = daySlotMs(fromMs, 0, hm.hour, hm.minute);
    if (todaySlot > fromMs) {
      return todaySlot;
    }
    return daySlotMs(fromMs, 1, hm.hour, hm.minute);
  }
  const days = task.weekdays && task.weekdays.length > 0 ? task.weekdays : [1, 2, 3, 4, 5];
  for (let offset = 0; offset <= 7; offset++) {
    const candidate = daySlotMs(fromMs, offset, hm.hour, hm.minute);
    const wd = new Date(candidate).getDay();
    if (days.indexOf(wd) >= 0 && candidate > fromMs) {
      return candidate;
    }
  }
  return daySlotMs(fromMs, 7, hm.hour, hm.minute);
}

/**
 * Checks whether a scheduled task is due at nowMs (including missed runs since lastRunAt).
 */
export function isTaskDue(task: ScheduledTask, nowMs: number): boolean {
  if (!task.enabled || task.prompt.trim().length === 0) {
    return false;
  }
  if (task.scheduleType === 'once') {
    return task.lastRunAt <= 0 && task.runAtMs > 0 && nowMs >= task.runAtMs;
  }
  if (task.scheduleType === 'interval') {
    const intervalMs = Math.max(1, task.intervalMinutes || 60) * 60000;
    if (task.lastRunAt <= 0) {
      return true;
    }
    return nowMs - task.lastRunAt >= intervalMs;
  }
  const hm = parseTimeHHMM(task.timeHHMM);
  if (task.scheduleType === 'daily') {
    const todaySlot = daySlotMs(nowMs, 0, hm.hour, hm.minute);
    return nowMs >= todaySlot && task.lastRunAt < todaySlot;
  }
  const days = task.weekdays && task.weekdays.length > 0 ? task.weekdays : [1, 2, 3, 4, 5];
  const todaySlot = daySlotMs(nowMs, 0, hm.hour, hm.minute);
  const todayWd = new Date(nowMs).getDay();
  if (days.indexOf(todayWd) >= 0 && nowMs >= todaySlot && task.lastRunAt < todaySlot) {
    return true;
  }
  // Catch up one missed scheduled slot within the past 6 days if app wasn't open.
  if (task.lastRunAt > 0) {
    for (let back = 1; back <= 6; back++) {
      const slot = daySlotMs(nowMs, -back, hm.hour, hm.minute);
      const wd = new Date(slot).getDay();
      if (days.indexOf(wd) >= 0 && slot > task.lastRunAt && slot <= nowMs) {
        return true;
      }
    }
  }
  return false;
}
