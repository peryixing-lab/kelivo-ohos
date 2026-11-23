import { http } from '@kit.NetworkKit';
import { ApiKeyEntry, SearchConfig, SearchHit, SearchServiceConfig, checkEndpoint } from './Models';
import { selectApiKey, markKeyError, markKeySuccess } from './KeyPool';
import { buildSearchRequestSpec, extractHtmlReadableText, parseSearchResponse } from './SearchAdapters';
import { readKey } from './Storage';

export class WebSearch {
  private request?: http.HttpRequest;
  stop(): void { this.request?.destroy(); this.request = undefined; }

  async find(config: SearchConfig, key: string, query: string): Promise<SearchHit[]> {
    const svc: SearchServiceConfig = {
      id: 'legacy',
      kind: config.kind,
      name: config.kind,
      endpoint: config.endpoint,
      apiKeys: [],
      keyStrategy: 'round_robin',
      maxResults: 5,
      enabled: true,
      mode: 'pre_search',
      webFetchEnabled: false
    };
    return this.findWithService(svc, key, query);
  }

  async findWithService(service: SearchServiceConfig, fallbackKey: string, query: string): Promise<SearchHit[]> {
    let chosen: ApiKeyEntry | undefined = undefined;
    let apiKey = fallbackKey;
    if (service.apiKeys && service.apiKeys.length > 0) {
      chosen = selectApiKey('search-' + service.id, service.apiKeys, service.keyStrategy || 'round_robin');
      if (chosen) apiKey = await readKey(chosen.secretRef);
    }

    const spec = buildSearchRequestSpec(service, apiKey, query);
    const req = http.createHttp();
    this.request = req;
    try {
      const opts: http.HttpRequestOptions = {
        method: spec.method === 'POST' ? http.RequestMethod.POST : http.RequestMethod.GET,
        header: spec.headers,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        readTimeout: 20000,
        connectTimeout: 12000,
        maxRedirects: 3
      };
      if (spec.method === 'POST' && spec.body) opts.extraData = spec.body;
      const response = await req.request(spec.url, opts);
      if (response.responseCode < 200 || response.responseCode >= 300) {
        if (chosen) service.apiKeys = markKeyError(service.apiKeys, chosen.id, response.responseCode);
        throw new Error('搜索服务返回 HTTP ' + response.responseCode);
      }
      if (chosen) service.apiKeys = markKeySuccess(service.apiKeys, chosen.id);
      return parseSearchResponse(spec.parserKind, response.result as string, service.maxResults || 5);
    } finally {
      if (this.request === req) this.stop();
    }
  }
}

export async function fetchWebPage(url: string, maxChars: number = 8000, offset: number = 0): Promise<string> {
  const cleanUrl = checkEndpoint(url);
  const req = http.createHttp();
  try {
    const response = await req.request(cleanUrl, {
      method: http.RequestMethod.GET,
      header: {
        'User-Agent': 'Mozilla/5.0 (HarmonyOS; kelivo/1.0)',
        'Accept': 'text/html,application/xhtml+xml,text/plain,application/json,*/*'
      },
      expectDataType: http.HttpDataType.STRING,
      usingCache: false,
      readTimeout: 20000,
      connectTimeout: 12000,
      maxRedirects: 5
    });
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error('抓取网页失败: HTTP ' + response.responseCode);
    }
    const raw = response.result as string;
    const headerRecord = response.header as Record<string, string>;
    let contentType = '';
    Object.keys(headerRecord).forEach((k: string) => {
      if (k.toLowerCase() === 'content-type') contentType = String(headerRecord[k] || '').toLowerCase();
    });
    const readable = (contentType.includes('html') || /^\s*<!doctype|^\s*<html/i.test(raw))
      ? extractHtmlReadableText(raw)
      : raw;
    const start = Math.max(0, offset);
    const slice = readable.slice(start, start + Math.max(500, maxChars));
    const hasMore = start + slice.length < readable.length;
    return slice + (hasMore ? '\n\n[已截断，总长度 ' + readable.length + ' 字符，可使用 offset=' + (start + slice.length) + ' 继续读取]' : '');
  } finally {
    req.destroy();
  }
}
