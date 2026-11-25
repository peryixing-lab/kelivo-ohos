import {
  ApiFamily,
  OAuthProviderKind,
  Provider,
  checkEndpoint,
  defaultModelSpec,
  preset
} from './Models';

interface SharedConfig {
  type?: string;
  name?: string;
  baseUrl?: string;
  apiKey?: string;
  model?: string;
  models?: string[];
  providerType?: string;
  useResponseApi?: boolean;
  vertexAI?: boolean;
  oauthProvider?: string;
  oauthCredentials?: OAuthCredentialsPayload;
  config?: SharedConfig;
}

interface OAuthCredentialsPayload {
  accessToken?: string;
  refreshToken?: string;
  email?: string;
  accountEmail?: string;
  expiresAt?: number | string;
}

interface ChatBoxProvidersMap {
  openai?: SharedConfig;
  claude?: SharedConfig;
  anthropic?: SharedConfig;
  gemini?: SharedConfig;
  google?: SharedConfig;
}

interface ChatBoxConfigPayload {
  providers?: ChatBoxProvidersMap;
  type?: string;
  name?: string;
  baseUrl?: string;
  apiKey?: string;
  model?: string;
  config?: SharedConfig;
}

export interface ImportedProvider {
  provider: Provider;
  key: string;
}

const PREFIX = 'ai-provider:v1:';
const B64_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

function utf8ToBytes(text: string): number[] {
  const out: number[] = [];
  for (let i = 0; i < text.length; i++) {
    let code = text.charCodeAt(i);
    if (code >= 0xD800 && code <= 0xDBFF && i + 1 < text.length) {
      const next = text.charCodeAt(i + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        const cp = 0x10000 + ((code - 0xD800) << 10) + (next - 0xDC00);
        out.push(0xF0 | (cp >> 18));
        out.push(0x80 | ((cp >> 12) & 0x3F));
        out.push(0x80 | ((cp >> 6) & 0x3F));
        out.push(0x80 | (cp & 0x3F));
        i++;
        continue;
      }
    }
    if (code < 0x80) {
      out.push(code);
    } else if (code < 0x800) {
      out.push(0xC0 | (code >> 6));
      out.push(0x80 | (code & 0x3F));
    } else {
      out.push(0xE0 | (code >> 12));
      out.push(0x80 | ((code >> 6) & 0x3F));
      out.push(0x80 | (code & 0x3F));
    }
  }
  return out;
}

function bytesToUtf8(bytes: number[]): string {
  let out = '';
  let i = 0;
  while (i < bytes.length) {
    const b0 = bytes[i] & 0xFF;
    if (b0 < 0x80) {
      out += String.fromCharCode(b0);
      i++;
    } else if ((b0 & 0xE0) === 0xC0 && i + 1 < bytes.length) {
      const b1 = bytes[i + 1] & 0x3F;
      out += String.fromCharCode(((b0 & 0x1F) << 6) | b1);
      i += 2;
    } else if ((b0 & 0xF0) === 0xE0 && i + 2 < bytes.length) {
      const b1 = bytes[i + 1] & 0x3F;
      const b2 = bytes[i + 2] & 0x3F;
      out += String.fromCharCode(((b0 & 0x0F) << 12) | (b1 << 6) | b2);
      i += 3;
    } else if ((b0 & 0xF8) === 0xF0 && i + 3 < bytes.length) {
      const b1 = bytes[i + 1] & 0x3F;
      const b2 = bytes[i + 2] & 0x3F;
      const b3 = bytes[i + 3] & 0x3F;
      const cp = ((b0 & 0x07) << 18) | (b1 << 12) | (b2 << 6) | b3;
      const adj = cp - 0x10000;
      out += String.fromCharCode(0xD800 + (adj >> 10), 0xDC00 + (adj & 0x3FF));
      i += 4;
    } else {
      out += String.fromCharCode(0xFFFD);
      i++;
    }
  }
  return out;
}

function base64EncodeBytes(bytes: number[]): string {
  let out = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const b0 = bytes[i] & 0xFF;
    const hasB1 = i + 1 < bytes.length;
    const hasB2 = i + 2 < bytes.length;
    const b1 = hasB1 ? (bytes[i + 1] & 0xFF) : 0;
    const b2 = hasB2 ? (bytes[i + 2] & 0xFF) : 0;
    const triple = (b0 << 16) | (b1 << 8) | b2;
    out += B64_CHARS.charAt((triple >> 18) & 0x3F);
    out += B64_CHARS.charAt((triple >> 12) & 0x3F);
    out += hasB1 ? B64_CHARS.charAt((triple >> 6) & 0x3F) : '=';
    out += hasB2 ? B64_CHARS.charAt(triple & 0x3F) : '=';
  }
  return out;
}

function base64DecodeBytes(raw: string): number[] {
  const cleaned = raw.replace(/\s+/g, '').replace(/-/g, '+').replace(/_/g, '/').replace(/=+$/, '');
  if (cleaned.length === 0 || cleaned.length % 4 === 1) {
    throw new Error('配置码的 Base64 编码格式无效');
  }
  const out: number[] = [];
  for (let i = 0; i < cleaned.length; i += 4) {
    const c0 = B64_CHARS.indexOf(cleaned.charAt(i));
    const c1 = B64_CHARS.indexOf(cleaned.charAt(i + 1));
    const c2Char = i + 2 < cleaned.length ? cleaned.charAt(i + 2) : '';
    const c3Char = i + 3 < cleaned.length ? cleaned.charAt(i + 3) : '';
    const c2 = c2Char ? B64_CHARS.indexOf(c2Char) : 0;
    const c3 = c3Char ? B64_CHARS.indexOf(c3Char) : 0;
    if (c0 < 0 || c1 < 0 || (c2Char && c2 < 0) || (c3Char && c3 < 0)) {
      throw new Error('配置码包含无效字符');
    }
    const triple = (c0 << 18) | (c1 << 12) | (c2 << 6) | c3;
    out.push((triple >> 16) & 0xFF);
    if (c2Char) {
      out.push((triple >> 8) & 0xFF);
    }
    if (c3Char) {
      out.push(triple & 0xFF);
    }
  }
  return out;
}

function defaultBaseUrlForFamily(family: ApiFamily): string {
  if (family === 'gemini' || family === 'vertex') {
    return 'https://generativelanguage.googleapis.com/v1beta';
  }
  if (family === 'anthropic') {
    return 'https://api.anthropic.com/v1';
  }
  return 'https://api.openai.com/v1';
}

function mapRawTypeToFamily(rawType: string, useResponseApi?: boolean, vertexAI?: boolean): ApiFamily {
  const norm = rawType.trim().toLowerCase();
  if (norm === 'google' || norm === 'gemini') {
    return vertexAI ? 'vertex' : 'gemini';
  }
  if (norm === 'vertex') {
    return 'vertex';
  }
  if (norm === 'claude' || norm === 'anthropic') {
    return 'anthropic';
  }
  if (norm === 'openai-responses') {
    return 'openai-responses';
  }
  if (norm === 'openai' || norm === 'openai-compat') {
    return useResponseApi ? 'openai-responses' : 'openai';
  }
  throw new Error('配置码的服务商类型无效: ' + rawType);
}

function normalizeOAuthKind(raw: string): OAuthProviderKind | undefined {
  const norm = raw.trim().toLowerCase();
  if (norm === 'chatgpt' || norm === 'openai' || norm === 'codex') {
    return 'chatgpt';
  }
  if (norm === 'grok' || norm === 'xai') {
    return 'grok';
  }
  if (norm === 'kimi' || norm === 'moonshot') {
    return 'kimi';
  }
  if (norm === 'claude' || norm === 'anthropic') {
    return 'claude';
  }
  if (norm === 'opencode-go' || norm === 'opencode' || norm === 'opencode_go') {
    return 'opencode-go';
  }
  return undefined;
}

function sanitizeBaseUrlOrDefault(rawUrl: string | undefined, family: ApiFamily): string {
  const fallback = defaultBaseUrlForFamily(family);
  const candidate = typeof rawUrl === 'string' ? rawUrl.trim() : '';
  if (!candidate) {
    return fallback;
  }
  try {
    return checkEndpoint(candidate);
  } catch (_) {
    return fallback;
  }
}

function buildProviderFromShared(obj: SharedConfig, id: string, fallbackType: string): ImportedProvider {
  const rawType = typeof obj.type === 'string' && obj.type.trim().length > 0 ? obj.type.trim() : fallbackType;
  if (rawType.toLowerCase() === 'oauth') {
    const cfg = obj.config;
    if (!cfg) {
      throw new Error('OAuth 配置码缺少 config 字段');
    }
    const kind = typeof cfg.oauthProvider === 'string' ? normalizeOAuthKind(cfg.oauthProvider) : undefined;
    if (!kind) {
      throw new Error('不支持的 OAuth 服务商类型');
    }
    const rawProvType = typeof cfg.providerType === 'string' && cfg.providerType.trim().length > 0
      ? cfg.providerType.trim()
      : (kind === 'claude' ? 'claude' : 'openai');
    const family = mapRawTypeToFamily(rawProvType, cfg.useResponseApi, cfg.vertexAI);
    const defaultName = typeof cfg.name === 'string' && cfg.name.trim().length > 0 ? cfg.name.trim() : kind.toUpperCase();
    const firstModel = typeof cfg.model === 'string' && cfg.model.trim().length > 0
      ? cfg.model.trim()
      : (Array.isArray(cfg.models) && cfg.models.length > 0 && typeof cfg.models[0] === 'string' ? cfg.models[0].trim() : '');
    const p = preset(id, defaultName, family, sanitizeBaseUrlOrDefault(cfg.baseUrl, family), firstModel);
    if (Array.isArray(cfg.models) && cfg.models.length > 0) {
      const specs = cfg.models
        .filter((m: string): boolean => typeof m === 'string' && m.trim().length > 0)
        .map((m: string) => defaultModelSpec(m.trim()));
      if (specs.length > 0) {
        p.models = specs;
      }
    }
    const creds = cfg.oauthCredentials;
    const rawExp = creds?.expiresAt;
    let expiresAt = 0;
    if (typeof rawExp === 'number') {
      expiresAt = rawExp;
    } else if (typeof rawExp === 'string') {
      const parsedTs = Date.parse(rawExp);
      if (!isNaN(parsedTs)) {
        expiresAt = parsedTs;
      }
    }
    p.oauth = {
      kind,
      accountEmail: (typeof creds?.email === 'string' ? creds.email : (typeof creds?.accountEmail === 'string' ? creds.accountEmail : '')),
      accessTokenRef: '',
      refreshTokenRef: '',
      expiresAt,
      quotaSummary: ''
    };
    const key = typeof cfg.apiKey === 'string' && cfg.apiKey.trim().length > 0
      ? cfg.apiKey.trim()
      : (typeof creds?.accessToken === 'string' ? creds.accessToken.trim() : '');
    return { provider: p, key };
  }

  const family = mapRawTypeToFamily(rawType, obj.useResponseApi, obj.vertexAI);
  const name = typeof obj.name === 'string' && obj.name.trim().length > 0
    ? obj.name.trim()
    : (family === 'gemini' || family === 'vertex' ? 'Google' : family === 'anthropic' ? 'Claude' : 'OpenAI');
  const firstModel = typeof obj.model === 'string' && obj.model.trim().length > 0
    ? obj.model.trim()
    : (Array.isArray(obj.models) && obj.models.length > 0 && typeof obj.models[0] === 'string' ? obj.models[0].trim() : '');
  const endpoint = family === 'gemini' && (!obj.baseUrl || !obj.baseUrl.trim())
    ? defaultBaseUrlForFamily('gemini')
    : sanitizeBaseUrlOrDefault(obj.baseUrl, family);
  const p = preset(id, name, family, endpoint, firstModel);
  if (Array.isArray(obj.models) && obj.models.length > 0) {
    const specs = obj.models
      .filter((m: string): boolean => typeof m === 'string' && m.trim().length > 0)
      .map((m: string) => defaultModelSpec(m.trim()));
    if (specs.length > 0) {
      p.models = specs;
    }
  }
  const key = typeof obj.apiKey === 'string' ? obj.apiKey.trim() : '';
  return { provider: p, key };
}

export function fromProviderLink(link: string, id: string): ImportedProvider {
  const value = link.trim();
  if (!value.startsWith(PREFIX)) {
    throw new Error('请使用 Kelivo 的 ai-provider:v1: 配置码');
  }
  const bytes = base64DecodeBytes(value.slice(PREFIX.length));
  const jsonStr = bytesToUtf8(bytes);
  const obj = JSON.parse(jsonStr) as SharedConfig;
  if (!obj || typeof obj.type !== 'string') {
    throw new Error('配置码的服务商格式无效');
  }
  if (obj.apiKey !== undefined && typeof obj.apiKey !== 'string') {
    throw new Error('配置码的密钥格式无效');
  }
  return buildProviderFromShared(obj, id, obj.type);
}

function decodeJsonLine(line: string, idFactory: () => string): ImportedProvider[] {
  const parsed = JSON.parse(line) as ChatBoxConfigPayload;
  if (!parsed) {
    throw new Error('JSON 配置内容为空');
  }
  if (parsed.providers) {
    const out: ImportedProvider[] = [];
    const map = parsed.providers;
    if (map.openai && typeof map.openai.apiKey === 'string' && map.openai.apiKey.trim().length > 0) {
      out.push(buildProviderFromShared(map.openai, idFactory(), 'openai'));
    }
    const claudeEntry = map.claude || map.anthropic;
    if (claudeEntry && typeof claudeEntry.apiKey === 'string' && claudeEntry.apiKey.trim().length > 0) {
      out.push(buildProviderFromShared(claudeEntry, idFactory(), 'claude'));
    }
    const geminiEntry = map.gemini || map.google;
    if (geminiEntry && typeof geminiEntry.apiKey === 'string' && geminiEntry.apiKey.trim().length > 0) {
      out.push(buildProviderFromShared(geminiEntry, idFactory(), 'google'));
    }
    if (out.length === 0) {
      throw new Error('未在 ChatBox JSON 中找到有效的服务商密钥');
    }
    return out;
  }
  if (typeof parsed.type === 'string') {
    const single: SharedConfig = {
      type: parsed.type,
      name: parsed.name,
      baseUrl: parsed.baseUrl,
      apiKey: parsed.apiKey,
      model: parsed.model,
      config: parsed.config
    };
    return [buildProviderFromShared(single, idFactory(), parsed.type)];
  }
  throw new Error('不支持的 JSON 服务商格式');
}

export function fromProviderText(raw: string, idFactory: () => string): ImportedProvider[] {
  const lines = raw
    .split(/\r?\n/)
    .map((line: string): string => line.trim())
    .filter((line: string): boolean => line.length > 0);
  if (lines.length === 0) {
    throw new Error('请输入 ai-provider:v1: 配置码或 ChatBox JSON');
  }
  if (lines.length === 1) {
    const single = lines[0];
    if (single.startsWith(PREFIX)) {
      return [fromProviderLink(single, idFactory())];
    }
    if (single.startsWith('{')) {
      return decodeJsonLine(single, idFactory);
    }
    throw new Error('请粘贴 ai-provider:v1: 配置码或 ChatBox JSON');
  }
  const out: ImportedProvider[] = [];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    try {
      if (line.startsWith(PREFIX)) {
        out.push(fromProviderLink(line, idFactory()));
      } else if (line.startsWith('{')) {
        const items = decodeJsonLine(line, idFactory);
        for (let j = 0; j < items.length; j++) {
          out.push(items[j]);
        }
      }
    } catch (_) {
      // Skip invalid lines in multi-line batch import just like official Kelivo
    }
  }
  if (out.length === 0) {
    throw new Error('未识别到有效的 ai-provider:v1: 配置码或 JSON');
  }
  return out;
}

export function toProviderLink(provider: Provider, key: string): string {
  const shareType = (provider.family === 'gemini' || provider.family === 'vertex')
    ? 'google'
    : (provider.family === 'anthropic' ? 'claude' : 'openai');
  const payload: SharedConfig = {
    type: shareType,
    name: provider.name,
    apiKey: key
  };
  if (shareType !== 'google') {
    payload.baseUrl = provider.baseUrl;
  }
  return PREFIX + base64EncodeBytes(utf8ToBytes(JSON.stringify(payload)));
}
