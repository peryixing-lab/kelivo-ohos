import { webview } from '@kit.ArkWeb';
import { OAuthProviderKind, Provider } from '../core/Models';
import {
  OAuthPreset,
  PkceSession,
  buildOAuthAuthorizeUrl,
  createOrUpdateOAuthProvider,
  createPkceSession,
  exchangeOAuthCode,
  getOAuthPreset,
  parseOAuthCallbackParams
} from '../core/OAuthService';

@Component
export struct OAuthLoginSheet {
  @Prop oauthKind: OAuthProviderKind = 'chatgpt';
  @Prop providers: Provider[] = [];

  onConnected: (provider: Provider) => Promise<void> = async () => {};
  onClose: () => void = () => {};

  private webController: webview.WebviewController = new webview.WebviewController();
  private pkceSession?: PkceSession;

  @State preset: OAuthPreset = getOAuthPreset('chatgpt');
  @State authUrl: string = '';
  @State manualInput: string = '';
  @State accountLabel: string = '';
  @State showManualMode: boolean = false;
  @State showWebPane: boolean = false;
  @State busy: boolean = false;
  @State statusTip: string = '';

  aboutToAppear(): void {
    this.initOAuthFlow().catch(() => {});
  }

  private connectedProvider(): Provider | undefined {
    return this.providers.find((p: Provider): boolean => p.oauth?.kind === this.oauthKind);
  }

  private async initOAuthFlow(): Promise<void> {
    this.preset = getOAuthPreset(this.oauthKind);
    this.pkceSession = await createPkceSession();
    this.authUrl = buildOAuthAuthorizeUrl(this.preset, this.pkceSession);
    this.showWebPane = true;
  }

  private async completeWithCallbackOrToken(rawInput: string): Promise<void> {
    const clean = rawInput.trim();
    if (clean.length === 0) {
      this.statusTip = '请粘贴回调 URL、授权码或 Token';
      return;
    }
    this.busy = true;
    this.statusTip = '正在完成 OAuth 验证...';
    try {
      const parsed = parseOAuthCallbackParams(clean);
      if (parsed.error.length > 0) {
        this.statusTip = `授权被拒绝: ${parsed.error}`;
        this.busy = false;
        return;
      }
      if (parsed.code.length > 0 && this.pkceSession && (clean.indexOf('code=') >= 0 || !clean.startsWith('sk-'))) {
        try {
          const tok = await exchangeOAuthCode(this.preset, parsed.code, this.pkceSession.verifier);
          const prov = await createOrUpdateOAuthProvider(this.preset, tok, this.providers, this.accountLabel);
          await this.onConnected(prov);
          this.statusTip = '订阅账号已连接';
          this.onClose();
          return;
        } catch (exchangeErr) {
          if (clean.indexOf('http') >= 0 || clean.indexOf('code=') >= 0) {
            throw exchangeErr as Error;
          }
          // Fall through if user pasted a direct bearer session token
        }
      }
      const prov = await createOrUpdateOAuthProvider(
        this.preset,
        {
          accessToken: clean,
          refreshToken: '',
          expiresInSec: 86400 * 7,
          accountEmail: this.accountLabel || `${this.oauthKind}@session`
        },
        this.providers,
        this.accountLabel
      );
      await this.onConnected(prov);
      this.statusTip = '已通过会话令牌绑定服务商';
      this.onClose();
    } catch (e) {
      this.statusTip = `认证失败: ${(e as Error).message || String(e)}`;
    } finally {
      this.busy = false;
    }
  }

  private handleInterceptUrl(url: string): boolean {
    if (!url.startsWith('http://localhost') && url.indexOf(this.preset.redirectUri) < 0) {
      return false;
    }
    const parsed = parseOAuthCallbackParams(url);
    if (parsed.code.length > 0 || parsed.error.length > 0) {
      this.showWebPane = false;
      this.completeWithCallbackOrToken(url).catch(() => {});
      return true;
    }
    return false;
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(this.preset.label)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ink'))
          .layoutWeight(1)
        Button(this.showManualMode ? '网页登录' : '手动粘贴')
          .type(ButtonType.Normal)
          .height(30)
          .fontSize(12)
          .borderRadius(8)
          .fontColor($r('app.color.accent'))
          .backgroundColor($r('app.color.tint'))
          .onClick(() => {
            this.showManualMode = !this.showManualMode;
          })
        Button('关闭')
          .type(ButtonType.Normal)
          .height(30)
          .fontSize(12)
          .borderRadius(8)
          .fontColor($r('app.color.ink'))
          .backgroundColor($r('app.color.surface'))
          .onClick(() => this.onClose())
      }
      .width('100%')

      if (this.connectedProvider()?.oauth) {
        Column({ space: 4 }) {
          Text(`已绑定账号：${this.connectedProvider()!.oauth!.accountEmail}`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.accent'))
          Text(this.connectedProvider()!.oauth!.quotaSummary)
            .fontSize(11)
            .fontColor($r('app.color.muted'))
        }
        .alignItems(HorizontalAlign.Start)
        .padding(10)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(10)
        .width('100%')
      }

      if (this.statusTip.length > 0) {
        Text(this.statusTip)
          .fontSize(12)
          .fontColor($r('app.color.accent'))
      }

      if (this.showManualMode) {
        Column({ space: 8 }) {
          Text('若系统浏览器跳转回调地址或需直接绑定 OAuth / Session Token，请粘贴到下方：')
            .fontSize(12)
            .fontColor($r('app.color.muted'))
          TextInput({ text: this.accountLabel, placeholder: '账号备注（如 name@domain.com，可选）' })
            .height(38)
            .borderRadius(8)
            .backgroundColor($r('app.color.surface'))
            .onChange((v: string) => {
              this.accountLabel = v;
            })
          TextArea({ text: this.manualInput, placeholder: '粘贴 http://localhost:1455/...?code=... 或 Access Token' })
            .height(110)
            .borderRadius(8)
            .backgroundColor($r('app.color.surface'))
            .onChange((v: string) => {
              this.manualInput = v;
            })
          Button(this.busy ? '验证中...' : '完成认证并创建服务商')
            .type(ButtonType.Normal)
            .width('100%')
            .height(40)
            .fontSize(13)
            .borderRadius(10)
            .fontColor($r('app.color.on_accent'))
            .backgroundColor($r('app.color.accent'))
            .enabled(!this.busy)
            .onClick(async () => {
              await this.completeWithCallbackOrToken(this.manualInput);
            })
        }
        .width('100%')
        .layoutWeight(1)
      } else if (this.showWebPane && this.authUrl.length > 0) {
        Web({ src: this.authUrl, controller: this.webController })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .onLoadIntercept((ev) => {
            return this.handleInterceptUrl(ev.data.getRequestUrl());
          })
          .onPageBegin((ev) => {
            this.handleInterceptUrl(ev.url);
          })
          .layoutWeight(1)
          .width('100%')
          .borderRadius(12)
      } else {
        Column() {
          LoadingProgress().width(32).height(32)
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 32 })
    .backgroundColor(Color.Transparent)
  }
}
