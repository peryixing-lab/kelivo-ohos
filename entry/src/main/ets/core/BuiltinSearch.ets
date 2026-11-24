import { ModelSpec, Provider, SearchHit, extractUrlHost } from './Models';
import { usesResponsesApi } from './Reasoning';

export function isOpenRouterProvider(provider: Provider): boolean {
  const host = extractUrlHost(provider.baseUrl);
  const id = provider.id.toLowerCase();
  return host.includes('openrouter.ai') || id.includes('openrouter');
}

export function isDashScopeProvider(provider: Provider): boolean {
  const host = extractUrlHost(provider.baseUrl);
  return host === 'dashscope.aliyuncs.com' || host === 'dashscope-intl.aliyuncs.com';
}

export function isZhipuProvider(provider: Provider): boolean {
  const host = extractUrlHost(provider.baseUrl);
  const id = provider.id.toLowerCase();
  const name = provider.name.toLowerCase();
  return host.includes('open.bigmodel.cn') ||
    host.includes('bigmodel') ||
    host === 'api.z.ai' ||
    id.includes('zhipu') ||
    id.includes('智谱') ||
    name.includes('zhipu') ||
    name.includes('智谱');
}

export function isGrokProvider(provider: Provider): boolean {
  if (provider.oauth?.kind === 'grok') {
    return true;
  }
  const host = extractUrlHost(provider.baseUrl);
  const id = provider.id.toLowerCase();
  const name = provider.name.toLowerCase();
  return host.includes('x.ai') ||
    host.includes('grok') ||
    id.includes('grok') ||
    id.includes('xai') ||
    name.includes('grok') ||
    name.includes('xai');
}

export function isArkProvider(provider: Provider): boolean {
  const host = extractUrlHost(provider.baseUrl);
  const id = provider.id.toLowerCase();
  const name = provider.name.toLowerCase();
  return host.includes('volces.com') ||
    ((host.includes('ark') || host.includes('volc')) &&
      (id.includes('doubao') ||
        id.includes('volc') ||
        id.includes('ark') ||
        name.includes('doubao') ||
        name.includes('火山') ||
        name.includes('方舟')));
}

export function isMoonshotProvider(provider: Provider): boolean {
  if (provider.oauth?.kind === 'kimi') {
    return true;
  }
  const host = extractUrlHost(provider.baseUrl);
  const id = provider.id.toLowerCase();
  const name = provider.name.toLowerCase();
  return host.includes('moonshot') ||
    host.includes('kimi.ai') ||
    id.includes('moonshot') ||
    id.includes('kimi') ||
    name.includes('moonshot') ||
    name.includes('kimi') ||
    name.includes('月之暗面');
}

export function isMimoProvider(provider: Provider): boolean {
  const host = extractUrlHost(provider.baseUrl);
  const id = provider.id.toLowerCase();
  const name = provider.name.toLowerCase();
  return host.includes('xiaomimimo') ||
    host.includes('mimo') ||
    id.includes('mimo') ||
    name.includes('mimo') ||
    name.includes('小米');
}

export function isVercelProvider(provider: Provider): boolean {
  return extractUrlHost(provider.baseUrl) === 'ai-gateway.vercel.sh';
}

export function isDeepSeekProvider(provider: Provider): boolean {
  const host = extractUrlHost(provider.baseUrl);
  const id = provider.id.toLowerCase();
  return host.includes('deepseek.com') || id.includes('deepseek');
}

export function isOfficialAnthropicEndpoint(provider: Provider): boolean {
  const raw = provider.baseUrl.trim();
  if (!raw) {
    return true;
  }
  return extractUrlHost(raw) === 'api.anthropic.com';
}

export function isOpenAIChatSearchModel(modelId: string): boolean {
  return /(?:^|\/)(?:gpt-4o(?:-mini)?-search-preview|gpt-5-search-api)/i.test(modelId.trim());
}

export function isChatSearchEligibleModel(modelId: string, spec?: ModelSpec): boolean {
  const clean = modelId.trim();
  if (!clean) {
    return false;
  }
  if (spec?.modelType === 'embedding' || spec?.modelType === 'image') {
    return false;
  }
  if (spec?.imageGen === true) {
    return false;
  }
  if (/(embedding|tts|whisper|rerank|dall-e|gpt-image|imagen|flux)/i.test(clean)) {
    return false;
  }
  return true;
}

export function supportsBuiltInSearch(provider: Provider, modelId: string, spec?: ModelSpec): boolean {
  if (!isChatSearchEligibleModel(modelId, spec)) {
    return false;
  }
  if (provider.family === 'gemini' || provider.family === 'vertex') {
    return true;
  }
  if (provider.family === 'anthropic') {
    if (isDeepSeekProvider(provider)) {
      return false;
    }
    if (isVercelProvider(provider) && !modelId.trim().toLowerCase().startsWith('anthropic/')) {
      return false;
    }
    return true;
  }
  if (usesResponsesApi(provider)) {
    if (isVercelProvider(provider) && !modelId.trim().toLowerCase().startsWith('openai/')) {
      return false;
    }
    return true;
  }
  return isOpenRouterProvider(provider) ||
    isDashScopeProvider(provider) ||
    isZhipuProvider(provider) ||
    isMimoProvider(provider) ||
    isMoonshotProvider(provider) ||
    isVercelProvider(provider) ||
    isOpenAIChatSearchModel(modelId);
}

export function requiresResponsesApiForBuiltInSearch(
  provider: Provider,
  modelId: string,
  spec?: ModelSpec
): boolean {
  if (provider.family !== 'openai' || usesResponsesApi(provider)) {
    return false;
  }
  if (!isChatSearchEligibleModel(modelId, spec)) {
    return false;
  }
  if (supportsBuiltInSearch(provider, modelId, spec)) {
    return false;
  }
  const host = extractUrlHost(provider.baseUrl);
  return host === 'api.openai.com' ||
    provider.oauth?.kind === 'chatgpt' ||
    isGrokProvider(provider) ||
    isArkProvider(provider);
}

export function supportsClaudeDynamicWebSearch(
  provider: Provider,
  modelId: string,
  spec?: ModelSpec
): boolean {
  return provider.family === 'anthropic' &&
    isOfficialAnthropicEndpoint(provider) &&
    isChatSearchEligibleModel(modelId, spec) &&
    /claude-(?:(?:sonnet|opus|haiku)-(?:4[.-][6-9]|5)|mythos|fable)/i.test(modelId);
}

export function claudeSearchToolType(
  provider: Provider,
  modelId: string,
  dynamicEnabled: boolean
): string {
  return dynamicEnabled && supportsClaudeDynamicWebSearch(provider, modelId)
    ? 'web_search_20260318'
    : 'web_search_20250305';
}

export function supportsGeminiMixedBuiltInAndFunctionTools(modelId: string): boolean {
  const m = modelId.match(/gemini-(\d+)/i);
  return m !== null && Number(m[1]) >= 3;
}

export function isBuiltInSearchEnabled(provider: Provider, modelId: string): boolean {
  const explicitSpec = provider.models?.find((m: ModelSpec): boolean => m.id === modelId);
  if (!supportsBuiltInSearch(provider, modelId, explicitSpec)) {
    return false;
  }
  if (explicitSpec && explicitSpec.builtinSearch !== undefined) {
    return explicitSpec.builtinSearch === true;
  }
  return provider.builtinSearch === true;
}

export function isClaudeDynamicSearchEnabled(provider: Provider, modelId: string): boolean {
  const explicitSpec = provider.models?.find((m: ModelSpec): boolean => m.id === modelId);
  return supportsClaudeDynamicWebSearch(provider, modelId, explicitSpec) &&
    explicitSpec?.claudeDynamicSearch === true;
}

export function needsMoonshotBuiltinSearchLoop(
  provider: Provider,
  modelId: string,
  builtinSearchEnabled: boolean
): boolean {
  return builtinSearchEnabled &&
    supportsBuiltInSearch(provider, modelId) &&
    provider.family === 'openai' &&
    !usesResponsesApi(provider) &&
    isMoonshotProvider(provider);
}

export function buildResponsesBuiltInSearchTools(
  provider: Provider,
  _modelId: string
): Array<Record<string, Object>> {
  if (isOpenRouterProvider(provider)) {
    const orTool: Record<string, Object> = {};
    orTool['type'] = 'openrouter:web_search';
    return [orTool];
  }
  if (isGrokProvider(provider)) {
    const ws: Record<string, Object> = {};
    ws['type'] = 'web_search';
    const xs: Record<string, Object> = {};
    xs['type'] = 'x_search';
    return [ws, xs];
  }
  const genericWs: Record<string, Object> = {};
  genericWs['type'] = 'web_search';
  return [genericWs];
}

function extractToolFunctionName(tool: Record<string, Object>): string {
  const fnObj = tool['function'] as Record<string, Object> | undefined;
  if (fnObj && typeof fnObj['name'] === 'string') {
    return (fnObj['name'] as string).trim();
  }
  return '';
}

function appendToolByTypeOrName(body: Record<string, Object>, tool: Record<string, Object>): void {
  const existing = Array.isArray(body['tools']) ? (body['tools'] as Array<Record<string, Object>>).slice() : [];
  const nextType = typeof tool['type'] === 'string' ? (tool['type'] as string).trim() : '';
  const nextFnName = extractToolFunctionName(tool);

  for (let i = 0; i < existing.length; i++) {
    const cur = existing[i];
    if (!cur || typeof cur !== 'object') {
      continue;
    }
    const curFnName = extractToolFunctionName(cur);
    if (nextFnName && curFnName && curFnName === nextFnName) {
      return;
    }
    const curType = typeof cur['type'] === 'string' ? (cur['type'] as string).trim() : '';
    if (!nextFnName && nextType && curType === nextType) {
      return;
    }
  }
  existing.push(tool);
  body['tools'] = existing;
}

function omitBodyKey(body: Record<string, Object>, keyToOmit: string): Record<string, Object> {
  const out: Record<string, Object> = {};
  const keys = Object.keys(body);
  for (let i = 0; i < keys.length; i++) {
    const k = keys[i];
    if (k !== keyToOmit) {
      out[k] = body[k];
    }
  }
  return out;
}

export function applyChatCompletionsBuiltInSearch(
  body: Record<string, Object>,
  provider: Provider,
  modelId: string
): Record<string, Object> {
  if (!supportsBuiltInSearch(provider, modelId)) {
    return body;
  }

  if (isOpenRouterProvider(provider)) {
    const orTool: Record<string, Object> = {};
    orTool['type'] = 'openrouter:web_search';
    appendToolByTypeOrName(body, orTool);

    const rawPlugins = body['plugins'];
    if (Array.isArray(rawPlugins)) {
      const pluginsList: Object[] = rawPlugins as Object[];
      const kept: Object[] = [];
      for (let i = 0; i < pluginsList.length; i++) {
        const plugin: Object = pluginsList[i];
        if (plugin && typeof plugin === 'object') {
          const pluginMap = plugin as Record<string, Object>;
          const pid = typeof pluginMap['id'] === 'string' ? (pluginMap['id'] as string).trim().toLowerCase() : '';
          if (pid === 'web') {
            continue;
          }
        }
        kept.push(plugin);
      }
      if (kept.length > 0) {
        body['plugins'] = kept;
      } else {
        return omitBodyKey(body, 'plugins');
      }
    }
    return body;
  }

  if (isDashScopeProvider(provider)) {
    body['enable_search'] = true;
    return body;
  }

  if (isZhipuProvider(provider)) {
    const zhipuCfg: Record<string, Object> = {};
    zhipuCfg['enable'] = true;
    zhipuCfg['search_result'] = true;
    const zhipuTool: Record<string, Object> = {};
    zhipuTool['type'] = 'web_search';
    zhipuTool['web_search'] = zhipuCfg;
    appendToolByTypeOrName(body, zhipuTool);
    return body;
  }

  if (isMimoProvider(provider)) {
    const mimoTool: Record<string, Object> = {};
    mimoTool['type'] = 'web_search';
    appendToolByTypeOrName(body, mimoTool);
    return body;
  }

  if (isMoonshotProvider(provider)) {
    const fnSpec: Record<string, Object> = {};
    fnSpec['name'] = '$web_search';
    const moonTool: Record<string, Object> = {};
    moonTool['type'] = 'builtin_function';
    moonTool['function'] = fnSpec;
    appendToolByTypeOrName(body, moonTool);
    return body;
  }

  if (isVercelProvider(provider)) {
    const vercelTool: Record<string, Object> = {};
    vercelTool['type'] = 'vercel:perplexity_search';
    appendToolByTypeOrName(body, vercelTool);
    return body;
  }

  if (isOpenAIChatSearchModel(modelId) && body['web_search_options'] === undefined) {
    body['web_search_options'] = new Object();
  }
  return body;
}

export function buildModelExtraResponsesTools(
  provider: Provider,
  spec: ModelSpec
): Array<Record<string, Object>> {
  const out: Array<Record<string, Object>> = [];
  if (spec.builtinCodeInterpreter) {
    const container: Record<string, Object> = {};
    container['type'] = 'auto';
    container['memory_limit'] = '4g';
    const ci: Record<string, Object> = {};
    ci['type'] = 'code_interpreter';
    ci['container'] = container;
    out.push(ci);
  }
  if (isOpenRouterProvider(provider)) {
    if (spec.builtinWebFetch) {
      const wf: Record<string, Object> = {};
      wf['type'] = 'openrouter:web_fetch';
      out.push(wf);
    }
    if (spec.builtinImageGen) {
      const ig: Record<string, Object> = {};
      ig['type'] = 'openrouter:image_generation';
      out.push(ig);
    }
    if (spec.builtinShell) {
      const params: Record<string, Object> = {};
      params['engine'] = 'openrouter';
      const sh: Record<string, Object> = {};
      sh['type'] = 'openrouter:shell';
      sh['parameters'] = params;
      out.push(sh);
    }
    return out;
  }
  if (spec.builtinImageGen) {
    const ig: Record<string, Object> = {};
    ig['type'] = 'image_generation';
    out.push(ig);
  }
  return out;
}

export function applyModelExtraChatCompletionsTools(
  body: Record<string, Object>,
  provider: Provider,
  spec: ModelSpec
): void {
  if (!isOpenRouterProvider(provider)) {
    return;
  }
  if (spec.builtinWebFetch) {
    const wf: Record<string, Object> = {};
    wf['type'] = 'openrouter:web_fetch';
    appendToolByTypeOrName(body, wf);
  }
  if (spec.builtinImageGen) {
    const ig: Record<string, Object> = {};
    ig['type'] = 'openrouter:image_generation';
    appendToolByTypeOrName(body, ig);
  }
}

export function buildModelExtraClaudeTools(
  provider: Provider,
  modelId: string,
  spec: ModelSpec,
  dynamicEnabled: boolean,
  claimedNames: Set<string>
): Array<Record<string, Object>> {
  if (provider.family !== 'anthropic' || !isOfficialAnthropicEndpoint(provider) || isDeepSeekProvider(provider)) {
    return [];
  }
  const out: Array<Record<string, Object>> = [];
  if (spec.builtinWebFetch && !claimedNames.has('web_fetch')) {
    const wf: Record<string, Object> = {};
    wf['type'] = (dynamicEnabled && supportsClaudeDynamicWebSearch(provider, modelId, spec))
      ? 'web_fetch_20260318'
      : 'web_fetch_20250910';
    wf['name'] = 'web_fetch';
    wf['max_content_tokens'] = 30000;
    out.push(wf);
  }
  if (spec.builtinCodeExec && !claimedNames.has('code_execution')) {
    const ce: Record<string, Object> = {};
    ce['type'] = 'code_execution_20260521';
    ce['name'] = 'code_execution';
    out.push(ce);
  }
  return out;
}

export function mergeDeduplicatedCitations(existing: SearchHit[], incoming: SearchHit[]): SearchHit[] {
  if (incoming.length === 0) {
    return existing;
  }
  const out = existing.slice();
  const idxByUrl = new Map<string, number>();
  for (let i = 0; i < out.length; i++) {
    const norm = out[i].url.trim();
    if (norm) {
      idxByUrl.set(norm, i);
    }
  }
  for (let i = 0; i < incoming.length; i++) {
    const raw = incoming[i];
    const url = (raw.url || '').trim();
    if (!url) {
      continue;
    }
    const title = (raw.title || '').trim() || url;
    const excerpt = (raw.excerpt || '').trim();
    const prevIdx = idxByUrl.get(url);
    if (prevIdx !== undefined) {
      const prev = out[prevIdx];
      const nextTitle = prev.title && prev.title !== prev.url ? prev.title : title;
      const nextExcerpt = prev.excerpt || excerpt;
      if (nextTitle !== prev.title || nextExcerpt !== prev.excerpt) {
        out[prevIdx] = { title: nextTitle, url, excerpt: nextExcerpt };
      }
      continue;
    }
    idxByUrl.set(url, out.length);
    out.push({ title, url, excerpt });
  }
  return out;
}
