import { ApiKeyEntry, KeyRotationStrategy } from './Models';

const roundRobinCursor = new Map<string, number>();

export function selectApiKey(
  poolId: string,
  entries: ApiKeyEntry[],
  strategy: KeyRotationStrategy,
  nowMs: number = Date.now(),
  randZeroToOne: number = Math.random()
): ApiKeyEntry | undefined {
  if (!entries.length) return undefined;
  let candidates = entries.filter((e: ApiKeyEntry): boolean => e.disabledUntil <= nowMs);
  if (!candidates.length) {
    // All keys are on cooldown; pick the one whose cooldown expires earliest.
    candidates = entries.slice().sort((a: ApiKeyEntry, b: ApiKeyEntry): number => a.disabledUntil - b.disabledUntil);
    return candidates[0];
  }
  if (strategy === 'priority') {
    const sorted = candidates.slice().sort((a: ApiKeyEntry, b: ApiKeyEntry): number => a.priority - b.priority);
    return sorted[0];
  }
  if (strategy === 'least_used') {
    const sorted = candidates.slice().sort((a: ApiKeyEntry, b: ApiKeyEntry): number => a.usageCount - b.usageCount);
    return sorted[0];
  }
  if (strategy === 'random') {
    const idx = Math.min(candidates.length - 1, Math.max(0, Math.floor(randZeroToOne * candidates.length)));
    return candidates[idx];
  }
  const current = roundRobinCursor.get(poolId) || 0;
  const selected = candidates[current % candidates.length];
  roundRobinCursor.set(poolId, (current + 1) % candidates.length);
  return selected;
}

export function markKeySuccess(entries: ApiKeyEntry[], keyId: string): ApiKeyEntry[] {
  return entries.map((e: ApiKeyEntry): ApiKeyEntry => {
    if (e.id !== keyId) return e;
    return {
      id: e.id,
      label: e.label,
      secretRef: e.secretRef,
      priority: e.priority,
      usageCount: e.usageCount + 1,
      errorCount: 0,
      disabledUntil: 0
    };
  });
}

export function markKeyError(entries: ApiKeyEntry[], keyId: string, status: number, nowMs: number = Date.now()): ApiKeyEntry[] {
  const cooldownMs = status === 401 || status === 403 ? 30 * 60 * 1000 : status === 429 ? 60 * 1000 : 15 * 1000;
  return entries.map((e: ApiKeyEntry): ApiKeyEntry => {
    if (e.id !== keyId) return e;
    return {
      id: e.id,
      label: e.label,
      secretRef: e.secretRef,
      priority: e.priority,
      usageCount: e.usageCount + 1,
      errorCount: e.errorCount + 1,
      disabledUntil: nowMs + cooldownMs
    };
  });
}
