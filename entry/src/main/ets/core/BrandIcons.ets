export type BrandIconId =
  | 'openai'
  | 'opencode'
  | 'gemini'
  | 'claude'
  | 'deepseek'
  | 'openrouter'
  | 'siliconflow'
  | 'qwen'
  | 'zhipu'
  | 'doubao'
  | 'kimi'
  | 'minimax'
  | 'stepfun'
  | 'grok'
  | 'ollama'
  | 'bing'
  | 'brave'
  | 'tavily'
  | 'exa'
  | 'mcp'
  | 'kelivo'
  | '';

export function resolveBrandIconId(nameOrModelId: string, family?: string): BrandIconId {
  const s = (nameOrModelId || '').toLowerCase();
  const fam = (family || '').toLowerCase();
  if (s.includes('kelivo') || s === 'auto') {
    return 'kelivo';
  }
  if (s.includes('gemini') || fam === 'gemini' || fam === 'vertex') {
    return 'gemini';
  }
  if (s.includes('claude') || s.includes('anthropic') || fam === 'anthropic') {
    return 'claude';
  }
  if (s.includes('deepseek')) {
    return 'deepseek';
  }
  if (s.includes('qwen') || s.includes('qwq') || s.includes('aliyun') || s.includes('百炼') || s.includes('dashscope')) {
    return 'qwen';
  }
  if (s.includes('glm') || s.includes('zhipu') || s.includes('智谱')) {
    return 'zhipu';
  }
  if (s.includes('doubao') || s.includes('volc') || s.includes('豆包') || s.includes('火山')) {
    return 'doubao';
  }
  if (s.includes('kimi') || s.includes('moonshot')) {
    return 'kimi';
  }
  if (s.includes('minimax') || s.includes('abab')) {
    return 'minimax';
  }
  if (s.includes('step') || s.includes('阶跃')) {
    return 'stepfun';
  }
  if (s.includes('grok') || s.includes('xai') || s.includes('x.ai')) {
    return 'grok';
  }
  if (s.includes('ollama') || fam === 'ollama') {
    return 'ollama';
  }
  if (s.includes('openrouter')) {
    return 'openrouter';
  }
  if (s.includes('silicon') || s.includes('硅基')) {
    return 'siliconflow';
  }
  if (s.includes('bing')) {
    return 'bing';
  }
  if (s.includes('brave')) {
    return 'brave';
  }
  if (s.includes('tavily')) {
    return 'tavily';
  }
  if (s.includes('exa')) {
    return 'exa';
  }
  if (s.includes('mcp')) {
    return 'mcp';
  }
  if (s.includes('opencode')) {
    return 'opencode';
  }
  if (
    s.includes('openai') ||
    s.includes('gpt') ||
    s.includes('chatgpt') ||
    /^o[134](-|$)/.test(s) ||
    fam === 'openai-responses'
  ) {
    return 'openai';
  }
  return '';
}

export function isMonochromeBrandIcon(id: BrandIconId): boolean {
  return (
    id === 'openai' ||
    id === 'opencode' ||
    id === 'openrouter' ||
    id === 'grok' ||
    id === 'ollama' ||
    id === 'stepfun' ||
    id === 'mcp'
  );
}

export function formatContextWindowShort(tokens: number): string {
  if (!tokens || tokens <= 0) {
    return '';
  }
  if (tokens >= 1000000) {
    const m = tokens / 1000000;
    return Number.isInteger(m) ? `${m}M` : `${m.toFixed(1)}M`;
  }
  const k = tokens / 1000;
  return Number.isInteger(k) ? `${k}k` : `${k.toFixed(1)}k`;
}

/**
 * Splits assistant response text into paragraph blocks by blank lines outside fenced code blocks.
 */
export function splitAssistantParagraphs(text: string): string[] {
  const src = (text || '').trim();
  if (src.length === 0) {
    return [];
  }
  const lines = src.split('\n');
  const blocks: string[] = [];
  let buf: string[] = [];
  let inFence = false;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (line.trimStart().startsWith('```')) {
      inFence = !inFence;
      buf.push(line);
      continue;
    }
    if (!inFence && line.trim().length === 0) {
      if (buf.length > 0) {
        blocks.push(buf.join('\n').trim());
        buf = [];
      }
      continue;
    }
    buf.push(line);
  }
  if (buf.length > 0) {
    blocks.push(buf.join('\n').trim());
  }
  return blocks.filter((b: string): boolean => b.length > 0);
}

export function brandInitial(name: string): string {
  const clean = (name || '').trim();
  if (clean.length === 0) {
    return 'K';
  }
  return clean.slice(0, 1).toUpperCase();
}
