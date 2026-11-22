import { http } from '@kit.NetworkKit';
import { randomBytes, sha256Bytes } from './BackupCrypto';
import { ApiFamily, OAuthAccountInfo, OAuthProviderKind, Provider, defaultModelSpec } from './Models';
import { newId, storeKey } from './Storage';

export interface OAuthPreset {
  kind: OAuthProviderKind;
  label: string;
  authorizeUrl: string;
  tokenUrl: string;
  redirectUri: string;
  clientId: string;
  scope: string;
  apiBaseUrl: string;
  defaultModel: string;
  apiFamily: ApiFamily;
}

export interface PkceSession {
  verifier: string;
  challenge: string;
  state: string;
}

export interface OAuthCallbackParseResult {
  code: string;
  state: string;
  error: string;
}

export interface OAuthTokenResult {
  accessToken: string;
  refreshToken: string;
  expiresInSec: number;
  accountEmail: string;
}

const B64_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

export function bytesToBase64Url(bytes: Uint8Array): string {
  let b64 = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const a = bytes[i];
    const b = i + 1 < bytes.length ? bytes[i + 1] : 0;
    const c = i + 2 < bytes.length ? bytes[i + 2] : 0;
    const triplet = (a << 16) | (b << 8) | c;
    b64 += B64_ALPHABET.charAt((triplet >> 18) & 63);
    b64 += B64_ALPHABET.charAt((triplet >> 12) & 63);
    if (i + 1 < bytes.length) {
      b64 += B64_ALPHABET.charAt((triplet >> 6) & 63);
    }
    if (i + 2 < bytes.length) {
      b64 += B64_ALPHABET.charAt(triplet & 63);
    }
  }
  return b64.replace(/\+/g, '-').replace(/\//g, '_');
}

function asciiToBytes(s: string): Uint8Array {
  const arr = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) {
    arr[i] = s.charCodeAt(i) & 0xff;
  }
  return arr;
}

export function getOAuthPreset(kind: OAuthProviderKind): OAuthPreset {
  if (kind === 'claude') {
    return {
      kind: 'claude',
      label: 'Claude 订阅 (OAuth)',
      authorizeUrl: 'https://claude.ai/oauth/authorize',
      tokenUrl: 'https://console.anthropic.com/v1/oauth/token',
      redirectUri: 'http://localhost:1455/callback',
      clientId: '9d1c250a-e61b-44d9-88ed-5944d1962f5e',
      scope: 'org:create_api_key user:profile user:inference',
      apiBaseUrl: 'https://api.anthropic.com/v1',
      defaultModel: 'claude-sonnet-4-20250514',
      apiFamily: 'anthropic'
    };
  }
  if (kind === 'grok') {
    return {
      kind: 'grok',
      label: 'Grok 订阅 (xAI OAuth)',
      authorizeUrl: 'https://accounts.x.ai/oauth/authorize',
      tokenUrl: 'https://accounts.x.ai/oauth/token',
      redirectUri: 'http://localhost:1455/callback',
      clientId: 'kelivo-xai-client',
      scope: 'openid profile chat',
      apiBaseUrl: 'https://api.x.ai/v1',
      defaultModel: 'grok-3',
      apiFamily: 'openai'
    };
  }
  if (kind === 'kimi') {
    return {
      kind: 'kimi',
      label: 'Kimi 订阅 (Moonshot OAuth)',
      authorizeUrl: 'https://auth.kimi.com/oauth/authorize',
      tokenUrl: 'https://auth.kimi.com/oauth/token',
      redirectUri: 'http://localhost:1455/callback',
      clientId: 'kelivo-kimi-client',
      scope: 'openid profile chat',
      apiBaseUrl: 'https://api.moonshot.cn/v1',
      defaultModel: 'kimi-k2-0711-preview',
      apiFamily: 'openai'
    };
  }
  return {
    kind: 'chatgpt',
    label: 'ChatGPT Plus/Pro 订阅 (OAuth)',
    authorizeUrl: 'https://auth.openai.com/oauth/authorize',
    tokenUrl: 'https://auth.openai.com/oauth/token',
    redirectUri: 'http://localhost:1455/auth/callback',
    clientId: 'app_EMoamEEZ73f0CkXaXp7hrann',
    scope: 'openid profile email offline_access',
    apiBaseUrl: 'https://api.openai.com/v1',
    defaultModel: 'gpt-5',
    apiFamily: 'openai-responses'
  };
}

export async function createPkceSession(): Promise<PkceSession> {
  const verifierBytes = await randomBytes(32);
  const verifier = bytesToBase64Url(verifierBytes);
  const challengeBytes = await sha256Bytes(asciiToBytes(verifier));
  const challenge = bytesToBase64Url(challengeBytes);
  const stateBytes = await randomBytes(16);
  const state = bytesToBase64Url(stateBytes);
  return { verifier, challenge, state };
}

export function buildOAuthAuthorizeUrl(preset: OAuthPreset, pkce: PkceSession): string {
  const qs =
    `response_type=code` +
    `&client_id=${encodeURIComponent(preset.clientId)}` +
    `&redirect_uri=${encodeURIComponent(preset.redirectUri)}` +
    `&scope=${encodeURIComponent(preset.scope)}` +
    `&state=${encodeURIComponent(pkce.state)}` +
    `&code_challenge=${encodeURIComponent(pkce.challenge)}` +
    `&code_challenge_method=S256`;
  const sep = preset.authorizeUrl.indexOf('?') >= 0 ? '&' : '?';
  return `${preset.authorizeUrl}${sep}${qs}`;
}

export function parseOAuthCallbackParams(urlOrCode: string): OAuthCallbackParseResult {
  const trimmed = urlOrCode.trim();
  if (trimmed.indexOf('?') < 0 && trimmed.indexOf('#') < 0 && trimmed.indexOf('=') < 0) {
    return { code: trimmed, state: '', error: '' };
  }
  let queryStr = trimmed;
  const qIdx = trimmed.indexOf('?');
  if (qIdx >= 0) {
    queryStr = trimmed.slice(qIdx + 1);
  }
  const hIdx = queryStr.indexOf('#');
  if (hIdx >= 0) {
    queryStr = queryStr.slice(0, hIdx);
  }
  const pairs = queryStr.split('&');
  let code = '';
  let state = '';
  let error = '';
  for (let i = 0; i < pairs.length; i++) {
    const eq = pairs[i].indexOf('=');
    if (eq <= 0) {
      continue;
    }
    const k = decodeURIComponent(pairs[i].slice(0, eq));
    const v = decodeURIComponent(pairs[i].slice(eq + 1));
    if (k === 'code') {
      code = v;
    } else if (k === 'state') {
      state = v;
    } else if (k === 'error') {
      error = v;
    }
  }
  return { code, state, error };
}

export async function exchangeOAuthCode(
  preset: OAuthPreset,
  code: string,
  verifier: string
): Promise<OAuthTokenResult> {
  const req = http.createHttp();
  const body =
    `grant_type=authorization_code` +
    `&client_id=${encodeURIComponent(preset.clientId)}` +
    `&code=${encodeURIComponent(code)}` +
    `&redirect_uri=${encodeURIComponent(preset.redirectUri)}` +
    `&code_verifier=${encodeURIComponent(verifier)}`;
  try {
    const resp = await req.request(preset.tokenUrl, {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json'
      },
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 15000,
      readTimeout: 20000
    });
    const raw = typeof resp.result === 'string' ? resp.result : JSON.stringify(resp.result);
    if (resp.responseCode < 200 || resp.responseCode >= 300) {
      throw new Error(`OAuth 换取 Token 失败 (${resp.responseCode}): ${raw.slice(0, 200)}`);
    }
    const obj = JSON.parse(raw) as Record<string, Object>;
    const accessToken = typeof obj['access_token'] === 'string' ? (obj['access_token'] as string) : '';
    if (accessToken.length === 0) {
      throw new Error('响应中未包含 access_token');
    }
    const refreshToken = typeof obj['refresh_token'] === 'string' ? (obj['refresh_token'] as string) : '';
    const expiresInSec = typeof obj['expires_in'] === 'number' ? (obj['expires_in'] as number) : 3600;
    let email = '';
    if (typeof obj['email'] === 'string') {
      email = obj['email'] as string;
    }
    return { accessToken, refreshToken, expiresInSec, accountEmail: email };
  } finally {
    req.destroy();
  }
}

export async function createOrUpdateOAuthProvider(
  preset: OAuthPreset,
  tokenResult: OAuthTokenResult,
  existingProviders: Provider[],
  accountEmailOverride: string = ''
): Promise<Provider> {
  const accessRef = `oauth_acc_${newId()}`;
  await storeKey(accessRef, tokenResult.accessToken);
  let refreshRef = '';
  if (tokenResult.refreshToken.length > 0) {
    refreshRef = `oauth_ref_${newId()}`;
    await storeKey(refreshRef, tokenResult.refreshToken);
  }
  const email = accountEmailOverride.trim().length > 0
    ? accountEmailOverride.trim()
    : (tokenResult.accountEmail || `${preset.kind}@oauth`);
  const expiresAt = Date.now() + tokenResult.expiresInSec * 1000;
  const oauthInfo: OAuthAccountInfo = {
    kind: preset.kind,
    accountEmail: email,
    accessTokenRef: accessRef,
    refreshTokenRef: refreshRef,
    expiresAt,
    quotaSummary: `有效期至 ${new Date(expiresAt).toLocaleString()}`
  };

  const existing = existingProviders.find((p: Provider): boolean => p.oauth?.kind === preset.kind);
  return {
    id: existing ? existing.id : `oauth_${preset.kind}_${newId()}`,
    name: preset.label,
    family: preset.apiFamily,
    baseUrl: preset.apiBaseUrl,
    model: existing ? existing.model : preset.defaultModel,
    secretRef: accessRef,
    models: existing && existing.models && existing.models.length > 0
      ? existing.models
      : [defaultModelSpec(preset.defaultModel)],
    oauth: oauthInfo,
    enabled: true
  };
}
