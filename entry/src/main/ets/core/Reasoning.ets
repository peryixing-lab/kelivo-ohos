import { GenerationParams, ModelSpec, Provider, ReasoningEffort, extractUrlHost } from './Models';

export type ReasoningDialect = 'effort' | 'router' | 'budgetFlag' | 'thinkingType' | 'kimi' | 'intern' |
  'claudeBudget' | 'adaptive' | 'geminiBudget' | 'geminiLevel' | 'fixed';

export const REASONING_NON_OFF_ORDER: ReasoningEffort[] = ['minimal', 'low', 'medium', 'high', 'xhigh', 'max'];

export interface ReasoningControl {
  dialect: ReasoningDialect;
  levels: ReasoningEffort[];
  budgetLimit: number;
}

const ORDER: ReasoningEffort[] = ['off', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max'];
const EXTENDED: ReasoningEffort[] = ['off', 'low', 'medium', 'high', 'xhigh'];
const ALL: ReasoningEffort[] = ['off', 'low', 'medium', 'high', 'max'];
const STANDARD: ReasoningEffort[] = ['off', 'low', 'medium', 'high'];
const DEEPSEEK: ReasoningEffort[] = ['off', 'low', 'high', 'max'];
const TOGGLE: ReasoningEffort[] = ['off', 'high'];

export function usesResponsesApi(provider: Provider): boolean {
  const path = (provider.chatPath || '').trim().replace(/^\/+|\/+$/g, '');
  return provider.family === 'openai-responses' && !/^(?:v1\/)?chat\/completions$/i.test(path);
}

export function inferReasoningControl(provider: Provider, model: string, reasoningEnabled: boolean): ReasoningControl {
  const id = model.toLowerCase();
  const host = extractUrlHost(provider.baseUrl);
  const deepseek = /deepseek-(v4|flash|chat)/.test(id) || (host === 'api.deepseek.com' && !id.includes('r1'));
  if (!reasoningEnabled) return { dialect: 'fixed', levels: [], budgetLimit: 0 };

  if (provider.family === 'gemini' || provider.family === 'vertex') {
    if (/gemini-[34]/.test(id)) {
      let levels: ReasoningEffort[] = ['low', 'medium', 'high'];
      if (id.includes('gemini-3-pro')) levels = ['low', 'high'];
      if (/gemini-3(?:\.[1-6])?-flash/.test(id)) levels = ['minimal', 'low', 'medium', 'high'];
      if (/gemini-3(?:\.\d+)?-flash(?:-lite)?-image/.test(id)) levels = ['minimal', 'high'];
      return { dialect: 'geminiLevel', levels, budgetLimit: 0 };
    }
    const pro = id.includes('2.5-pro');
    return { dialect: 'geminiBudget', levels: pro ? ALL.slice(1) : ALL, budgetLimit: pro ? 32768 : 24576 };
  }
  if (provider.family === 'anthropic') {
    if (deepseek) return { dialect: 'thinkingType', levels: DEEPSEEK, budgetLimit: 0 };
    if (/claude-(?:(?:sonnet|opus|haiku)-(?:4[.-][6-9]|5)|mythos|fable)/.test(id)) {
      const alwaysOn = /claude-(?:opus-5[.-]5|mythos|fable)/.test(id);
      const extended = /claude-(?:(?:opus|sonnet|haiku)-5|opus-4[.-][78]|mythos|fable)/.test(id);
      const levels = extended ? ORDER.filter((e: ReasoningEffort): boolean => e !== 'minimal') : ALL;
      return { dialect: 'adaptive', levels: alwaysOn ? levels.slice(1) : levels, budgetLimit: 0 };
    }
    return { dialect: 'claudeBudget', levels: ALL, budgetLimit: 32768 };
  }

  if (host === 'openrouter.ai') return { dialect: 'router', levels: EXTENDED, budgetLimit: 0 };
  if (provider.id === 'ollama' || host === 'ollama.com' || /:11434(?:\/|$)/.test(provider.baseUrl)) {
    const levels = id.includes('gpt-oss') ? STANDARD.slice(1) : TOGGLE;
    return { dialect: 'effort', levels, budgetLimit: 0 };
  }
  if (host.includes('siliconflow') || host.includes('dashscope') || /qwen3|qwq/.test(id)) {
    const forced = /qwq|qwen3[^/]*thinking|deepseek-r1/.test(id);
    if (usesResponsesApi(provider)) return { dialect: 'budgetFlag', levels: forced ? [] : TOGGLE, budgetLimit: 0 };
    return { dialect: 'budgetFlag', levels: forced ? ALL.slice(1) : ALL, budgetLimit: 32768 };
  }
  if (deepseek) return { dialect: 'thinkingType', levels: DEEPSEEK, budgetLimit: 0 };
  if (/deepseek-r1|deepseek-reasoner|kimi-k2-thinking/.test(id)) return { dialect: 'fixed', levels: [], budgetLimit: 0 };
  if (/glm-5[.-][23]|kimi-k3|kimi-for-coding/.test(id)) {
    if (id.includes('kimi-k3')) return { dialect: 'effort', levels: DEEPSEEK.slice(1), budgetLimit: 0 };
    if (id.includes('kimi')) return { dialect: 'kimi', levels: DEEPSEEK, budgetLimit: 0 };
    return { dialect: 'thinkingType', levels: id.includes('5.3') ? DEEPSEEK.slice(1) : ALL, budgetLimit: 0 };
  }
  if (/glm-|doubao|seed-1/.test(id) || host.includes('bigmodel.cn') || host.includes('volces.com')) {
    return { dialect: 'thinkingType', levels: TOGGLE, budgetLimit: 0 };
  }
  if (/kimi-k2/.test(id) || host.includes('moonshot')) return { dialect: 'kimi', levels: TOGGLE, budgetLimit: 0 };
  if (/intern-s1|internlm/.test(id)) return { dialect: 'intern', levels: TOGGLE, budgetLimit: 0 };

  if (/gpt-6|gpt-5\.6/.test(id)) {
    const levels: ReasoningEffort[] = ['low', 'medium', 'high', 'xhigh', 'max'];
    if (!id.includes('gpt-6')) levels.unshift('off');
    return { dialect: 'effort', levels, budgetLimit: 0 };
  }
  if (/gpt-5\.[2-5]|gpt-5\.1-codex-max/.test(id)) {
    const levels = id.includes('-pro') ? EXTENDED.slice(2) : id.includes('codex') ? EXTENDED.slice(1) : EXTENDED;
    return { dialect: 'effort', levels, budgetLimit: 0 };
  }
  if (/gpt-5-pro/.test(id)) return { dialect: 'effort', levels: ['high'], budgetLimit: 0 };
  if (/gpt-5(?:$|-(?:mini|nano|20))/.test(id)) {
    return { dialect: 'effort', levels: ['minimal', 'low', 'medium', 'high'], budgetLimit: 0 };
  }
  if (/\bo[134]\b|gpt-oss|gpt-5-codex|gpt-5\.1-codex/.test(id)) {
    return { dialect: 'effort', levels: STANDARD.slice(1), budgetLimit: 0 };
  }
  if (/grok-3-mini/.test(id)) return { dialect: 'effort', levels: ['low', 'high'], budgetLimit: 0 };
  // A custom OpenAI-compatible model explicitly marked as reasoning uses the standard effort field.
  return { dialect: 'effort', levels: STANDARD, budgetLimit: 0 };
}

function resolveBudgetLimitForDialect(provider: Provider, model: string, dialect: ReasoningDialect): number {
  if (dialect === 'claudeBudget') {
    return 32768;
  }
  if (dialect === 'geminiBudget') {
    return model.toLowerCase().includes('2.5-pro') ? 32768 : 24576;
  }
  if (dialect === 'budgetFlag') {
    return usesResponsesApi(provider) ? 0 : 32768;
  }
  return 0;
}

export function reasoningControl(provider: Provider, model: string, spec: ModelSpec): ReasoningControl {
  if (!spec.reasoning) {
    return { dialect: 'fixed', levels: [], budgetLimit: 0 };
  }
  const base = inferReasoningControl(provider, model, true);
  const dialect: ReasoningDialect = (spec.reasoningDialect && spec.reasoningDialect !== 'auto')
    ? spec.reasoningDialect
    : base.dialect;
  if (dialect === 'fixed') {
    return { dialect: 'fixed', levels: [], budgetLimit: 0 };
  }
  const budgetLimit = resolveBudgetLimitForDialect(provider, model, dialect);
  let nonOff: ReasoningEffort[];
  if (spec.reasoningLevels !== undefined) {
    nonOff = REASONING_NON_OFF_ORDER.filter((lv: ReasoningEffort): boolean => spec.reasoningLevels!.includes(lv));
  } else {
    nonOff = base.levels.filter((lv: ReasoningEffort): boolean => lv !== 'off');
    if (nonOff.length === 0) {
      nonOff = ['low', 'medium', 'high'];
    }
  }
  const allowOff = spec.reasoningAllowOff !== undefined ? spec.reasoningAllowOff : base.levels.includes('off');
  const levels: ReasoningEffort[] = allowOff ? (['off'] as ReasoningEffort[]).concat(nonOff) : nonOff;
  return { dialect, levels, budgetLimit };
}

export function withReasoning(params: GenerationParams, effort?: ReasoningEffort, budget?: number): GenerationParams {
  return {
    temperature: params.temperature, topP: params.topP, maxTokens: params.maxTokens,
    contextLimit: params.contextLimit, responseSpeed: params.responseSpeed,
    retryBaseMs: params.retryBaseMs, autoRetryCount: params.autoRetryCount,
    reasoningEffort: effort, reasoningBudget: budget
  };
}

export function effectiveEffort(control: ReasoningControl, requested: ReasoningEffort): ReasoningEffort {
  const levels = control.levels;
  if (!levels.length) return 'off';
  if (levels.includes(requested)) return requested;
  if (requested === 'off') return levels[0];
  // A saved preference may come from a different model. Prefer the next supported intensity.
  return levels.find((level: ReasoningEffort): boolean => ORDER.indexOf(level) >= ORDER.indexOf(requested)) ||
    levels[levels.length - 1];
}

export function reasoningBulbRayCount(control: ReasoningControl, effort: ReasoningEffort): number {
  if (effort === 'off') return 0;
  const nonOff = control.levels.filter((lv: ReasoningEffort): boolean => lv !== 'off');
  if (nonOff.length === 1 && control.levels.includes('off')) return 3;
  const idx = nonOff.indexOf(effort);
  if (idx >= 0) return Math.min(6, idx + 1);
  const fallbackIdx = ORDER.indexOf(effort);
  return fallbackIdx > 0 ? Math.min(6, fallbackIdx) : 0;
}

export function reasoningTokens(control: ReasoningControl, effort: ReasoningEffort, custom?: number): number {
  if (!control.budgetLimit || effort === 'off') return 0;
  const preset = effort === 'low' ? 1024 : effort === 'medium' ? 4096 : effort === 'high' ? 8192 : control.budgetLimit;
  const budget = custom !== undefined && Number.isFinite(custom) && custom > 0 ? Math.round(custom) : preset;
  return Math.min(control.budgetLimit, Math.max(1024, budget));
}

export function applyReasoning(body: Record<string, Object>, provider: Provider, model: string,
  control: ReasoningControl, params?: GenerationParams): void {
  if (!params?.reasoningEffort || !control.levels.length) return;
  const effort = effectiveEffort(control, params.reasoningEffort);
  const off = effort === 'off';
  const wire = off ? 'none' : effort;
  const budget = reasoningTokens(control, effort, params.reasoningBudget);
  const kind = control.dialect;
  const setting: Record<string, Object> = {};
  if (kind === 'geminiBudget' || kind === 'geminiLevel') {
    const config = (body['generationConfig'] as Record<string, Object>) || {};
    setting['includeThoughts'] = params.reasoningEffort !== 'off';
    if (kind === 'geminiLevel') setting['thinkingLevel'] = wire.toUpperCase();
    else setting['thinkingBudget'] = budget;
    config['thinkingConfig'] = setting;
    body['generationConfig'] = config;
  } else if (kind === 'budgetFlag') {
    if (control.levels.includes('off')) body['enable_thinking'] = !off;
    if (budget > 0) body['thinking_budget'] = budget;
  } else if (kind === 'router' || usesResponsesApi(provider)) {
    if (kind === 'router' && off) setting['enabled'] = false;
    else setting['effort'] = wire;
    body['reasoning'] = setting;
  } else if (kind === 'effort') {
    body['reasoning_effort'] = wire;
  } else if (kind === 'intern') {
    body['thinking_mode'] = !off;
  } else {
    setting['type'] = off ? 'disabled' : 'enabled';
    if (!off && kind === 'claudeBudget') {
      setting['budget_tokens'] = budget;
      if ((body['max_tokens'] as number) <= budget) body['max_tokens'] = budget + 4096;
    } else if (kind === 'adaptive') {
      setting['type'] = off && /claude-sonnet-5[.-]5/i.test(model) ? 'between_tools' : off ? 'disabled' : 'adaptive';
    }
    if (!off && control.levels.length > 2 && kind !== 'claudeBudget') {
      if (provider.family === 'anthropic') {
        const output: Record<string, Object> = { 'effort': wire };
        body['output_config'] = output;
      } else if (kind === 'kimi') setting['effort'] = wire;
      else body['reasoning_effort'] = wire;
    }
    body['thinking'] = setting;
  }
}
