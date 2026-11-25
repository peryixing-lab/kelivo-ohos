import { ProxyConfig } from './Models';
import {
  OPENCODE_GO_CLIENT_ID,
  OpenCodeGoAuthError,
  OpenCodeGoDeviceChallenge,
  OpenCodeGoSession,
  fetchOpenCodeProfile,
  parseOpenCodeDeviceCodeResponse,
  parseOpenCodeTokenResponse,
  postOpenCodeConsoleJson,
  saveOpenCodeGoSession
} from './OpenCodeGoSession';
import { newId } from './Storage';

function sanitizeSessionSegment(raw: string): string {
  return raw.replace(/[^A-Za-z0-9_-]/g, '_');
}

export class OpenCodeGoLogin {
  private cancelled: boolean = false;
  private abortWait?: () => void;

  cancel(): void {
    this.cancelled = true;
    this.abortWait?.();
  }

  private sleep(ms: number): Promise<void> {
    if (this.cancelled) {
      return Promise.reject(new Error('已取消登录'));
    }
    return new Promise<void>((resolve, reject) => {
      let done = false;
      const timer = setTimeout(() => {
        if (!done) {
          done = true;
          this.abortWait = undefined;
          resolve();
        }
      }, Math.max(200, ms));
      this.abortWait = () => {
        if (!done) {
          done = true;
          clearTimeout(timer);
          this.abortWait = undefined;
          reject(new Error('已取消登录'));
        }
      };
    });
  }

  async requestChallenge(proxy?: ProxyConfig, proxyPassword?: string): Promise<OpenCodeGoDeviceChallenge> {
    if (this.cancelled) {
      throw new Error('已取消登录');
    }
    const fields: Record<string, Object> = {};
    fields['client_id'] = OPENCODE_GO_CLIENT_ID;
    fields['supports_org_scope'] = true;
    const reply = await postOpenCodeConsoleJson('/auth/device/code', fields, proxy, proxyPassword);
    if (reply.status < 200 || reply.status >= 300) {
      throw new Error('获取 OpenCode Go 授权码失败（HTTP ' + reply.status + '），请稍后重试');
    }
    const challenge = parseOpenCodeDeviceCodeResponse(reply.body);
    if (this.cancelled) {
      throw new Error('已取消登录');
    }
    return challenge;
  }

  async pollForSession(
    challenge: OpenCodeGoDeviceChallenge,
    existingSessionId: string = '',
    proxy?: ProxyConfig,
    proxyPassword?: string
  ): Promise<OpenCodeGoSession> {
    let intervalMs = challenge.intervalMs;
    while (Date.now() < challenge.expiresAt) {
      const remaining = challenge.expiresAt - Date.now();
      await this.sleep(Math.min(intervalMs, remaining));
      if (this.cancelled) {
        throw new Error('已取消登录');
      }
      if (Date.now() >= challenge.expiresAt) {
        break;
      }
      const fields: Record<string, Object> = {};
      fields['grant_type'] = 'urn:ietf:params:oauth:grant-type:device_code';
      fields['device_code'] = challenge.deviceCode;
      fields['client_id'] = OPENCODE_GO_CLIENT_ID;
      let replyStatus = 0;
      let replyBody = '';
      try {
        const reply = await postOpenCodeConsoleJson('/auth/device/token', fields, proxy, proxyPassword);
        replyStatus = reply.status;
        replyBody = reply.body;
      } catch (e) {
        if (this.cancelled) {
          throw new Error('已取消登录');
        }
        throw e as Error;
      }
      if (this.cancelled) {
        throw new Error('已取消登录');
      }
      try {
        const tok = parseOpenCodeTokenResponse(replyBody);
        if (replyStatus < 200 || replyStatus >= 300) {
          throw new Error('OpenCode Go 授权失败（HTTP ' + replyStatus + '）');
        }
        const profile = await fetchOpenCodeProfile(tok.accessToken, tok.orgId, proxy, proxyPassword);
        if (this.cancelled) {
          throw new Error('已取消登录');
        }
        const cleanExisting = existingSessionId.trim();
        let sessionId = cleanExisting;
        if (!sessionId) {
          if (profile.accountId) {
            const acctPart = sanitizeSessionSegment(profile.accountId);
            const orgPart = tok.orgId ? '_' + sanitizeSessionSegment(tok.orgId) : '';
            sessionId = acctPart + orgPart;
          } else {
            sessionId = newId();
          }
        }
        const session: OpenCodeGoSession = {
          sessionId,
          access: tok.accessToken,
          refresh: tok.refreshToken,
          expires: tok.expires,
          accountId: profile.accountId,
          email: profile.email,
          orgId: tok.orgId,
          orgName: profile.orgName
        };
        await saveOpenCodeGoSession(session);
        return session;
      } catch (e) {
        if (e instanceof OpenCodeGoAuthError) {
          if (e.code === 'authorization_pending') {
            continue;
          }
          if (e.code === 'slow_down') {
            intervalMs = Math.min(intervalMs + 5000, 60000);
            continue;
          }
          throw e;
        }
        if (replyStatus >= 500 && replyStatus < 600) {
          continue;
        }
        throw e as Error;
      }
    }
    throw new Error('设备授权码已过期，请重新开始登录');
  }
}
