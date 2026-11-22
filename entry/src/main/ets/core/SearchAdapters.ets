import { SearchHit, SearchServiceConfig, checkEndpoint } from './Models';

export interface SearchEngineCatalogItem {
  kind: string;
  name: string;
  defaultEndpoint: string;
  needsKey: boolean;
}

export interface SearchWireRequest {
  url: string;
  method: 'GET' | 'POST';
  headers: Record<string, string>;
  body: string;
  parserKind: string;
}

interface ExaContentsOpt { text: boolean }
interface ExaSearchBody { query: string; numResults: number; contents: ExaContentsOpt }
interface SearchLlmMsg { role: string; content: string }

export const SEARCH_ENGINE_CATALOG: SearchEngineCatalogItem[] = [
  { kind: 'duckduckgo', name: 'DuckDuckGo（免密钥）', defaultEndpoint: 'https://html.duckduckgo.com', needsKey: false },
  { kind: 'bing', name: 'Bing 网页搜索（免密钥）', defaultEndpoint: 'https://www.bing.com', needsKey: false },
  { kind: 'searxng', name: 'SearXNG 自建实例', defaultEndpoint: '', needsKey: false },
  { kind: 'fourget', name: '4get 实例', defaultEndpoint: 'https://4get.ca', needsKey: false },
  { kind: 'tavily', name: 'Tavily Search', defaultEndpoint: 'https://api.tavily.com/search', needsKey: true },
  { kind: 'brave', name: 'Brave Search API', defaultEndpoint: 'https://api.search.brave.com/res/v1/web/search', needsKey: true },
  { kind: 'exa', name: 'Exa AI Search', defaultEndpoint: 'https://api.exa.ai/search', needsKey: true },
  { kind: 'perplexity', name: 'Perplexity Search', defaultEndpoint: 'https://api.perplexity.ai/search', needsKey: true },
  { kind: 'serper', name: 'Serper (Google)', defaultEndpoint: 'https://google.serper.dev/search', needsKey: true },
  { kind: 'firecrawl', name: 'Firecrawl Search', defaultEndpoint: 'https://api.firecrawl.dev/v1/search', needsKey: true },
  { kind: 'jina', name: 'Jina Search (s.jina.ai)', defaultEndpoint: 'https://s.jina.ai', needsKey: false },
  { kind: 'you', name: 'You.com Search', defaultEndpoint: 'https://api.ydc-index.io/search', needsKey: true },
  { kind: 'linkup', name: 'LinkUp Search', defaultEndpoint: 'https://api.linkup.so/v1/search', needsKey: true },
  { kind: 'parallel', name: 'Parallel Search', defaultEndpoint: 'https://api.parallel.ai/v1beta/search', needsKey: true },
  { kind: 'kagi', name: 'Kagi Search', defaultEndpoint: 'https://kagi.com/api/v0/search', needsKey: true },
  { kind: 'querit', name: 'Querit Search', defaultEndpoint: 'https://api.querit.ai/v1/search', needsKey: true },
  { kind: 'tinyfish', name: 'TinyFish Search', defaultEndpoint: 'https://api.tinyfish.ai/v1/search', needsKey: true },
  { kind: 'anysearch', name: 'AnySearch', defaultEndpoint: 'https://api.anysearch.io/v1/search', needsKey: true },
  { kind: 'grok', name: 'xAI Grok Live Search', defaultEndpoint: 'https://api.x.ai/v1/chat/completions', needsKey: true },
  { kind: 'ollama', name: 'Ollama Web Search', defaultEndpoint: 'https://ollama.com/api/web_search', needsKey: true },
  { kind: 'bocha', name: '博查 Bocha AI', defaultEndpoint: 'https://api.bochaai.com/v1/web-search', needsKey: true },
  { kind: 'metaso', name: '秘塔 Metaso', defaultEndpoint: 'https://metaso.cn/api/v1/search', needsKey: true },
  { kind: 'zhipu', name: '智谱 Web Search', defaultEndpoint: 'https://open.bigmodel.cn/api/paas/v4/web_search', needsKey: true },
  { kind: 'doubao', name: '豆包搜索', defaultEndpoint: 'https://ark.cn-beijing.volces.com/api/v3/bots/chat/completions', needsKey: true },
  { kind: 'stepfun', name: '阶跃星辰搜索', defaultEndpoint: 'https://api.stepfun.com/v1/chat/completions', needsKey: true },
  { kind: 'kimi', name: 'Kimi 联网搜索', defaultEndpoint: 'https://api.moonshot.cn/v1/chat/completions', needsKey: true }
];

export function findSearchCatalog(kind: string): SearchEngineCatalogItem {
  const found = SEARCH_ENGINE_CATALOG.find((item: SearchEngineCatalogItem): boolean => item.kind === kind);
  return found || SEARCH_ENGINE_CATALOG[0];
}

export function buildSearchRequestSpec(
  service: SearchServiceConfig,
  apiKey: string,
  query: string
): SearchWireRequest {
  const kind = service.kind;
  const maxR = Math.max(1, Math.min(10, service.maxResults || 5));
  const catalog = findSearchCatalog(kind);
  const rawEndpoint = service.endpoint.trim() || catalog.defaultEndpoint;
  const qEnc = encodeURIComponent(query);

  if (catalog.needsKey && !apiKey.trim()) {
    throw new Error('请先为 ' + catalog.name + ' 配置 API 密钥');
  }

  if (kind === 'duckduckgo') {
    return {
      url: 'https://html.duckduckgo.com/html/?q=' + qEnc,
      method: 'GET',
      headers: { 'User-Agent': 'Mozilla/5.0 (HarmonyOS; LexiKelivo)' },
      body: '',
      parserKind: 'duckduckgo_html'
    };
  }
  if (kind === 'bing') {
    return {
      url: 'https://www.bing.com/search?q=' + qEnc + '&count=' + maxR,
      method: 'GET',
      headers: { 'User-Agent': 'Mozilla/5.0 (HarmonyOS; LexiKelivo)' },
      body: '',
      parserKind: 'bing_html'
    };
  }
  if (kind === 'searxng') {
    const base = checkEndpoint(rawEndpoint);
    return {
      url: base + '/search?format=json&q=' + qEnc,
      method: 'GET',
      headers: { 'Accept': 'application/json' },
      body: '',
      parserKind: 'searxng_json'
    };
  }
  if (kind === 'fourget') {
    const base = checkEndpoint(rawEndpoint);
    return {
      url: base + '/api/v1/web?s=' + qEnc,
      method: 'GET',
      headers: { 'Accept': 'application/json' },
      body: '',
      parserKind: 'fourget_json'
    };
  }
  if (kind === 'tavily') {
    return {
      url: rawEndpoint || 'https://api.tavily.com/search',
      method: 'POST',
      headers: { 'Authorization': 'Bearer ' + apiKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query, max_results: maxR }),
      parserKind: 'generic_json'
    };
  }
  if (kind === 'brave') {
    return {
      url: 'https://api.search.brave.com/res/v1/web/search?q=' + qEnc + '&count=' + maxR,
      method: 'GET',
      headers: { 'X-Subscription-Token': apiKey, 'Accept': 'application/json' },
      body: '',
      parserKind: 'brave_json'
    };
  }
  if (kind === 'serper') {
    return {
      url: rawEndpoint || 'https://google.serper.dev/search',
      method: 'POST',
      headers: { 'X-API-KEY': apiKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({ q: query, num: maxR }),
      parserKind: 'serper_json'
    };
  }
  if (kind === 'exa') {
    const exaBody: ExaSearchBody = { query, numResults: maxR, contents: { text: true } };
    return {
      url: rawEndpoint || 'https://api.exa.ai/search',
      method: 'POST',
      headers: { 'x-api-key': apiKey, 'Content-Type': 'application/json' },
      body: JSON.stringify(exaBody),
      parserKind: 'generic_json'
    };
  }
  if (kind === 'jina') {
    const hdrs: Record<string, string> = { 'Accept': 'application/json' };
    if (apiKey.trim()) hdrs['Authorization'] = 'Bearer ' + apiKey.trim();
    return {
      url: 'https://s.jina.ai/' + qEnc,
      method: 'GET',
      headers: hdrs,
      body: '',
      parserKind: 'jina_json'
    };
  }
  if (kind === 'bocha') {
    return {
      url: rawEndpoint || 'https://api.bochaai.com/v1/web-search',
      method: 'POST',
      headers: { 'Authorization': 'Bearer ' + apiKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({ query, count: maxR, summary: true }),
      parserKind: 'bocha_json'
    };
  }
  if (kind === 'zhipu') {
    return {
      url: rawEndpoint || 'https://open.bigmodel.cn/api/paas/v4/web_search',
      method: 'POST',
      headers: { 'Authorization': 'Bearer ' + apiKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({ search_query: query, search_engine: 'search_std', count: maxR }),
      parserKind: 'zhipu_json'
    };
  }
  if (kind === 'kagi') {
    return {
      url: 'https://kagi.com/api/v0/search?q=' + qEnc + '&limit=' + maxR,
      method: 'GET',
      headers: { 'Authorization': 'Bot ' + apiKey, 'Accept': 'application/json' },
      body: '',
      parserKind: 'generic_json'
    };
  }
  if (kind === 'you') {
    return {
      url: 'https://api.ydc-index.io/search?query=' + qEnc,
      method: 'GET',
      headers: { 'X-API-Key': apiKey, 'Accept': 'application/json' },
      body: '',
      parserKind: 'you_json'
    };
  }
  if (kind === 'grok' || kind === 'doubao' || kind === 'stepfun' || kind === 'kimi') {
    const modelName = kind === 'grok' ? 'grok-3-mini' : kind === 'kimi' ? 'moonshot-v1-8k' :
      kind === 'stepfun' ? 'step-1-8k' : 'doubao-1-5-pro-32k';
    const bodyObj: Record<string, Object> = {};
    bodyObj['model'] = modelName;
    const msgs: SearchLlmMsg[] = [{ role: 'user', content: '请联网搜索并列出与以下查询最相关的网页事实与链接：' + query }];
    bodyObj['messages'] = msgs;
    if (kind === 'grok') {
      const sp: Record<string, Object> = {};
      sp['mode'] = 'on';
      bodyObj['search_parameters'] = sp;
    }
    return {
      url: rawEndpoint,
      method: 'POST',
      headers: { 'Authorization': 'Bearer ' + apiKey, 'Content-Type': 'application/json' },
      body: JSON.stringify(bodyObj),
      parserKind: 'llm_search_json'
    };
  }

  // Generic POST JSON search providers (perplexity, firecrawl, linkup, parallel, querit, tinyfish, anysearch, ollama, metaso)
  return {
    url: checkEndpoint(rawEndpoint),
    method: 'POST',
    headers: { 'Authorization': 'Bearer ' + apiKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query, max_results: maxR, limit: maxR }),
    parserKind: 'generic_json'
  };
}

interface SearchRowObj {
  title?: string;
  name?: string;
  url?: string;
  link?: string;
  href?: string;
  content?: string;
  snippet?: string;
  description?: string;
  summary?: string;
  text?: string;
}
interface BraveWebBlock { results?: SearchRowObj[] }
interface BochaPages { value?: SearchRowObj[] }
interface BochaData { webPages?: BochaPages }
interface LlmMsg { content?: string }
interface LlmChoice { message?: LlmMsg }
interface SearchWirePayload {
  results?: SearchRowObj[];
  organic?: SearchRowObj[];
  data?: SearchRowObj[] | BochaData;
  web?: BraveWebBlock | SearchRowObj[];
  hits?: SearchRowObj[];
  search_result?: SearchRowObj[];
  choices?: LlmChoice[];
  citations?: string[];
}

function stripTags(html: string): string {
  return html
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\s+/g, ' ')
    .trim();
}

export function extractHtmlReadableText(html: string): string {
  const cleaned = html
    .replace(/<script[\s\S]*?<\/script>/gi, '\n')
    .replace(/<style[\s\S]*?<\/style>/gi, '\n')
    .replace(/<noscript[\s\S]*?<\/noscript>/gi, '\n')
    .replace(/<(?:br|p|div|li|tr|h[1-6])[^>]*>/gi, '\n')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&nbsp;/g, ' ');
  return cleaned.split('\n').map((l: string): string => l.replace(/\s+/g, ' ').trim())
    .filter((l: string): boolean => l.length > 0).join('\n');
}

function mapRowsToHits(rows: SearchRowObj[], maxResults: number): SearchHit[] {
  const out: SearchHit[] = [];
  for (let i = 0; i < rows.length && out.length < maxResults; i++) {
    const r = rows[i];
    const url = r.url || r.link || r.href || '';
    if (!/^https?:\/\//i.test(url)) continue;
    const title = (r.title || r.name || url).slice(0, 200);
    const excerpt = (r.content || r.snippet || r.description || r.summary || r.text || '').slice(0, 1200);
    out.push({ title, url, excerpt });
  }
  return out;
}

export function parseSearchResponse(parserKind: string, raw: string, maxResults: number): SearchHit[] {
  if (parserKind === 'duckduckgo_html') {
    const hits: SearchHit[] = [];
    const regex = /<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>([\s\S]*?)<\/a>[\s\S]*?(?:class="result__snippet"[^>]*>([\s\S]*?)<\/a>|<\/div>)/gi;
    let m = regex.exec(raw);
    while (m && hits.length < maxResults) {
      let href = m[1];
      if (href.includes('uddg=')) {
        const enc = href.split('uddg=')[1].split('&')[0];
        try { href = decodeURIComponent(enc); } catch (_) {}
      }
      if (/^https?:\/\//i.test(href)) {
        hits.push({
          title: stripTags(m[2]).slice(0, 200) || href,
          url: href,
          excerpt: stripTags(m[3] || '').slice(0, 1200)
        });
      }
      m = regex.exec(raw);
    }
    return hits;
  }

  if (parserKind === 'bing_html') {
    const hits: SearchHit[] = [];
    const regex = /<li[^>]*class="[^"]*b_algo[^"]*"[^>]*>[\s\S]*?<h2[^>]*><a[^>]*href="(https?:\/\/[^"]+)"[^>]*>([\s\S]*?)<\/a><\/h2>([\s\S]*?)<\/li>/gi;
    let m = regex.exec(raw);
    while (m && hits.length < maxResults) {
      hits.push({
        title: stripTags(m[2]).slice(0, 200) || m[1],
        url: m[1],
        excerpt: stripTags(m[3]).slice(0, 1200)
      });
      m = regex.exec(raw);
    }
    return hits;
  }

  const parsed = JSON.parse(raw) as SearchWirePayload;
  if (parserKind === 'llm_search_json') {
    const content = parsed.choices?.[0]?.message?.content || '';
    const cites = parsed.citations || [];
    const out: SearchHit[] = [];
    for (let i = 0; i < cites.length && out.length < maxResults; i++) {
      if (/^https?:\/\//i.test(cites[i])) {
        out.push({ title: '来源 ' + (i + 1), url: cites[i], excerpt: i === 0 ? content.slice(0, 1200) : '' });
      }
    }
    if (!out.length && content) {
      out.push({ title: '模型联网检索摘要', url: 'https://search.local/summary', excerpt: content.slice(0, 1500) });
    }
    return out;
  }

  let rows: SearchRowObj[] = [];
  if (Array.isArray(parsed.results)) rows = parsed.results;
  else if (Array.isArray(parsed.organic)) rows = parsed.organic;
  else if (Array.isArray(parsed.search_result)) rows = parsed.search_result;
  else if (Array.isArray(parsed.hits)) rows = parsed.hits;
  else if (Array.isArray(parsed.data)) rows = parsed.data;
  else if (parsed.data && !Array.isArray(parsed.data) && parsed.data.webPages?.value) rows = parsed.data.webPages.value;
  else if (parsed.web && Array.isArray(parsed.web)) rows = parsed.web;
  else if (parsed.web && !Array.isArray(parsed.web) && parsed.web.results) rows = parsed.web.results;

  return mapRowsToHits(rows, maxResults);
}
