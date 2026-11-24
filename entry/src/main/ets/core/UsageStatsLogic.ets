import { Persona, UsageStatRow } from './Models';

export interface UsageHeatmapCell {
  day: string;
  shortDay: string;
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
  msgCount: number;
  level: number;
  isToday: boolean;
}

export interface UsageHeatmapRow {
  dayOfWeek: number;
  label: string;
  cells: UsageHeatmapCell[];
}

export interface UsageDailyBar {
  day: string;
  shortDay: string;
  promptTokens: number;
  completionTokens: number;
  totalTokens: number;
  promptPct: number;
  compPct: number;
  isToday: boolean;
}

export interface UsageRankRow {
  key: string;
  label: string;
  totalTokens: number;
  msgCount: number;
  ratioPct: number;
}

export interface UsageBarPctPair {
  promptPct: number;
  compPct: number;
}

export interface UsageDashboardData {
  totalTokens: number;
  promptTokens: number;
  completionTokens: number;
  cachedTokens: number;
  totalMessages: number;
  activeDays: number;
  avgTokensPerMsg: number;
  outputSharePct: number;
  heatmapStartDay: string;
  heatmapEndDay: string;
  heatmapRows: UsageHeatmapRow[];
  recentBars: UsageDailyBar[];
  modelRanks: UsageRankRow[];
  personaRanks: UsageRankRow[];
}

interface DayUsageBucket {
  prompt: number;
  comp: number;
  msgs: number;
}

interface RankCountBucket {
  total: number;
  msgs: number;
}

interface RankRawEntry {
  key: string;
  label: string;
  totalTokens: number;
  msgCount: number;
}

function padTwo(n: number): string {
  return n < 10 ? `0${n}` : `${n}`;
}

/**
 * Formats a Date into local calendar `YYYY-MM-DD`.
 */
export function formatLocalDay(d: Date): string {
  return `${d.getFullYear()}-${padTwo(d.getMonth() + 1)}-${padTwo(d.getDate())}`;
}

/**
 * Formats a Date into local wall-clock `HH:mm:ss`.
 */
export function formatLocalTime(d: Date): string {
  return `${padTwo(d.getHours())}:${padTwo(d.getMinutes())}:${padTwo(d.getSeconds())}`;
}

/**
 * Formats token or request counts compactly (`M`, `K`, or integer).
 */
export function formatUsageCount(n: number): string {
  const safe = n > 0 ? n : 0;
  if (safe >= 1000000) {
    return `${(safe / 1000000).toFixed(2)}M`;
  }
  if (safe >= 1000) {
    return `${(safe / 1000).toFixed(1)}K`;
  }
  return `${Math.round(safe)}`;
}

/**
 * Computes stacked input/output bar percentages strictly bounded to `[0, 100]` in total.
 */
export function computeStackedBarPcts(
  promptTokens: number,
  completionTokens: number,
  maxBar: number
): UsageBarPctPair {
  if (maxBar <= 0 || (promptTokens <= 0 && completionTokens <= 0)) {
    return { promptPct: 0, compPct: 0 };
  }
  let promptPct = promptTokens > 0 ? Math.max(2, Math.round((promptTokens / maxBar) * 100)) : 0;
  let compPct = completionTokens > 0 ? Math.max(2, Math.round((completionTokens / maxBar) * 100)) : 0;

  if (promptPct + compPct > 100) {
    if (promptPct > 0 && compPct > 0) {
      if (promptPct <= compPct) {
        promptPct = Math.min(promptPct, 98);
        compPct = 100 - promptPct;
      } else {
        compPct = Math.min(compPct, 98);
        promptPct = 100 - compPct;
      }
    } else if (promptPct > 0) {
      promptPct = 100;
    } else {
      compPct = 100;
    }
  }
  return { promptPct, compPct };
}

function buildSortedRankList(
  src: Map<string, RankCountBucket>,
  labelLookup: (k: string) => string
): UsageRankRow[] {
  const raw: RankRawEntry[] = [];
  let top = 0;
  src.forEach((v: RankCountBucket, k: string) => {
    if (v.total > top) {
      top = v.total;
    }
    raw.push({
      key: k,
      label: labelLookup(k),
      totalTokens: v.total,
      msgCount: v.msgs
    });
  });

  raw.sort((a: RankRawEntry, b: RankRawEntry): number => {
    if (b.totalTokens !== a.totalTokens) {
      return b.totalTokens - a.totalTokens;
    }
    if (b.msgCount !== a.msgCount) {
      return b.msgCount - a.msgCount;
    }
    return a.key < b.key ? -1 : (a.key > b.key ? 1 : 0);
  });

  return raw.map((item: RankRawEntry): UsageRankRow => ({
    key: item.key,
    label: item.label,
    totalTokens: item.totalTokens,
    msgCount: item.msgCount,
    ratioPct: top > 0 && item.totalTokens > 0
      ? Math.max(4, Math.min(100, Math.round((item.totalTokens / top) * 100)))
      : 0
  }));
}

/**
 * Aggregates raw SQLite usage rows into KPI summaries, a Mon-Sun aligned 13-week
 * heatmap, 14-day stacked bars, and model/assistant rankings.
 */
export function computeUsageDashboard(
  rows: UsageStatRow[],
  personas: Persona[],
  now?: Date
): UsageDashboardData {
  let pSum = 0;
  let cSum = 0;
  let cachedSum = 0;
  let mSum = 0;

  const dayMap = new Map<string, DayUsageBucket>();
  const modelMap = new Map<string, RankCountBucket>();
  const personaMap = new Map<string, RankCountBucket>();

  const personaNames = new Map<string, string>();
  for (let i = 0; i < personas.length; i++) {
    personaNames.set(personas[i].id, personas[i].name);
  }

  for (let i = 0; i < rows.length; i++) {
    const r = rows[i];
    pSum += r.promptTokens;
    cSum += r.completionTokens;
    cachedSum += r.cachedTokens;
    mSum += r.msgCount;

    const dEntry: DayUsageBucket = dayMap.get(r.day) ?? { prompt: 0, comp: 0, msgs: 0 };
    dEntry.prompt += r.promptTokens;
    dEntry.comp += r.completionTokens;
    dEntry.msgs += r.msgCount;
    dayMap.set(r.day, dEntry);

    const mKey = r.model || 'unknown';
    const mEntry: RankCountBucket = modelMap.get(mKey) ?? { total: 0, msgs: 0 };
    mEntry.total += r.promptTokens + r.completionTokens;
    mEntry.msgs += r.msgCount;
    modelMap.set(mKey, mEntry);

    const perKey = r.personaId || 'default';
    const perEntry: RankCountBucket = personaMap.get(perKey) ?? { total: 0, msgs: 0 };
    perEntry.total += r.promptTokens + r.completionTokens;
    perEntry.msgs += r.msgCount;
    personaMap.set(perKey, perEntry);
  }

  let activeDays = 0;
  dayMap.forEach((v: DayUsageBucket) => {
    if (v.prompt + v.comp > 0 || v.msgs > 0) {
      activeDays += 1;
    }
  });

  const totalTokens = pSum + cSum;
  const avgTokensPerMsg = mSum > 0 ? Math.round(totalTokens / mSum) : 0;
  const outputSharePct = totalTokens > 0 ? Math.round((cSum / totalTokens) * 1000) / 10 : 0;

  const refNow = now ?? new Date();
  const today = new Date(refNow.getFullYear(), refNow.getMonth(), refNow.getDate());
  const todayStr = formatLocalDay(today);
  const todayDow = (today.getDay() + 6) % 7; // 0 = Mon .. 6 = Sun
  const currentWeekMonday = new Date(today.getFullYear(), today.getMonth(), today.getDate() - todayDow);
  const gridStartMonday = new Date(
    currentWeekMonday.getFullYear(),
    currentWeekMonday.getMonth(),
    currentWeekMonday.getDate() - 12 * 7
  );

  let maxHeatmapCell = 0;
  const weekCount = 13;
  for (let w = 0; w < weekCount; w++) {
    for (let dow = 0; dow < 7; dow++) {
      const dt = new Date(
        gridStartMonday.getFullYear(),
        gridStartMonday.getMonth(),
        gridStartMonday.getDate() + w * 7 + dow
      );
      if (dt.getTime() <= today.getTime()) {
        const dayStr = formatLocalDay(dt);
        const stat = dayMap.get(dayStr);
        const tot = stat ? stat.prompt + stat.comp : 0;
        if (tot > maxHeatmapCell) {
          maxHeatmapCell = tot;
        }
      }
    }
  }

  const weekdayLabels: string[] = ['一', '', '三', '', '五', '', '日'];
  const heatmapRows: UsageHeatmapRow[] = [];
  for (let dow = 0; dow < 7; dow++) {
    const cells: UsageHeatmapCell[] = [];
    for (let w = 0; w < weekCount; w++) {
      const dt = new Date(
        gridStartMonday.getFullYear(),
        gridStartMonday.getMonth(),
        gridStartMonday.getDate() + w * 7 + dow
      );
      const dayStr = formatLocalDay(dt);
      if (dt.getTime() > today.getTime()) {
        cells.push({
          day: dayStr,
          shortDay: dayStr.slice(5),
          promptTokens: 0,
          completionTokens: 0,
          totalTokens: 0,
          msgCount: 0,
          level: -1,
          isToday: false
        });
      } else {
        const stat = dayMap.get(dayStr);
        const pr = stat ? stat.prompt : 0;
        const cp = stat ? stat.comp : 0;
        const tot = pr + cp;
        const msgs = stat ? stat.msgs : 0;
        const level = tot <= 0 || maxHeatmapCell <= 0
          ? 0
          : Math.min(4, Math.max(1, Math.ceil((tot / maxHeatmapCell) * 4)));
        cells.push({
          day: dayStr,
          shortDay: dayStr.slice(5),
          promptTokens: pr,
          completionTokens: cp,
          totalTokens: tot,
          msgCount: msgs,
          level,
          isToday: dayStr === todayStr
        });
      }
    }
    heatmapRows.push({
      dayOfWeek: dow,
      label: weekdayLabels[dow],
      cells
    });
  }

  let maxBar = 0;
  for (let offset = 13; offset >= 0; offset--) {
    const dt = new Date(today.getFullYear(), today.getMonth(), today.getDate() - offset);
    const stat = dayMap.get(formatLocalDay(dt));
    const tot = stat ? stat.prompt + stat.comp : 0;
    if (tot > maxBar) {
      maxBar = tot;
    }
  }

  const recentBars: UsageDailyBar[] = [];
  for (let offset = 13; offset >= 0; offset--) {
    const dt = new Date(today.getFullYear(), today.getMonth(), today.getDate() - offset);
    const dayStr = formatLocalDay(dt);
    const stat = dayMap.get(dayStr);
    const pr = stat ? stat.prompt : 0;
    const cp = stat ? stat.comp : 0;
    const tot = pr + cp;
    const pcts = computeStackedBarPcts(pr, cp, maxBar);
    recentBars.push({
      day: dayStr,
      shortDay: dayStr.slice(5),
      promptTokens: pr,
      completionTokens: cp,
      totalTokens: tot,
      promptPct: pcts.promptPct,
      compPct: pcts.compPct,
      isToday: offset === 0
    });
  }

  const modelRanks = buildSortedRankList(modelMap, (k: string): string => k);
  const personaRanks = buildSortedRankList(personaMap, (k: string): string => {
    const named = personaNames.get(k);
    if (named && named.length > 0) {
      return named;
    }
    if (!k || k === 'default') {
      return '默认助手';
    }
    return k;
  });

  return {
    totalTokens,
    promptTokens: pSum,
    completionTokens: cSum,
    cachedTokens: cachedSum,
    totalMessages: mSum,
    activeDays,
    avgTokensPerMsg,
    outputSharePct,
    heatmapStartDay: formatLocalDay(gridStartMonday),
    heatmapEndDay: todayStr,
    heatmapRows,
    recentBars,
    modelRanks,
    personaRanks
  };
}
