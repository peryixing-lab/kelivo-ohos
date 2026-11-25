import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { OPENCODE_GO_CONSOLE_URL } from '../core/Models';
import { OpenCodeGoLogin } from '../core/OpenCodeGoLogin';
import { OpenCodeGoSession } from '../core/OpenCodeGoSession';

@Component
export struct OpenCodeGoPlanLogin {
  @Prop sessionId: string = '';
  @Prop accountLabel: string = '';
  @Prop workspaceLabel: string = '';
  onConnected: (session: OpenCodeGoSession) => Promise<void> = async () => {};

  @State private signingIn: boolean = false;
  @State private userCode: string = '';
  @State private verificationUrl: string = '';
  @State private statusText: string = '';
  @State private errorText: string = '';
  @State private copiedCode: boolean = false;
  private attempt?: OpenCodeGoLogin;

  aboutToDisappear(): void {
    this.attempt?.cancel();
  }

  private async copyUserCode(): Promise<void> {
    if (!this.userCode) {
      return;
    }
    try {
      await pasteboard.getSystemPasteboard().setData(
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.userCode)
      );
      this.copiedCode = true;
      this.statusText = '已复制授权码，请在浏览器页面中粘贴确认';
    } catch (_) {
      this.errorText = '复制授权码失败，请手动输入：' + this.userCode;
    }
  }

  private openAuthBrowser(targetUrl: string): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ctx.openLink(targetUrl, { appLinkingOnly: false })
      .catch(() => {
        this.errorText = '无法打开系统浏览器，请手动访问 ' + targetUrl;
      });
  }

  private async startLogin(): Promise<void> {
    if (this.signingIn) {
      this.attempt?.cancel();
      return;
    }
    const attempt = new OpenCodeGoLogin();
    this.attempt = attempt;
    this.signingIn = true;
    this.userCode = '';
    this.verificationUrl = '';
    this.copiedCode = false;
    this.errorText = '';
    this.statusText = '正在向 OpenCode Console 请求设备授权码…';
    try {
      const challenge = await attempt.requestChallenge();
      this.userCode = challenge.userCode;
      this.verificationUrl = challenge.verificationUrl;
      this.statusText = '请在系统浏览器中确认授权码并选择 Go 订阅工作区';
      this.openAuthBrowser(challenge.verificationUrl);
      const session = await attempt.pollForSession(challenge, this.sessionId);
      await this.onConnected(session);
      this.userCode = '';
      this.verificationUrl = '';
      this.statusText = '已连接 OpenCode Go 账号';
    } catch (e) {
      this.errorText = (e as Error).message || 'OpenCode Go 登录失败，请重试';
      this.statusText = '';
    } finally {
      this.signingIn = false;
      this.attempt = undefined;
    }
  }

  private displayTitle(): string {
    if (this.accountLabel && this.workspaceLabel) {
      return `${this.accountLabel} · ${this.workspaceLabel}`;
    }
    return this.accountLabel || this.workspaceLabel || '使用 OpenCode Go 账号登录';
  }

  build() {
    Column({ space: 8 }) {
      Text(this.displayTitle())
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ink'))
      Text('通过 OpenCode Console 授权访问已订阅的 OpenCode Go 模型与实时额度。')
        .fontSize(12)
        .fontColor($r('app.color.muted'))

      if (this.signingIn && this.userCode.length > 0) {
        Column({ space: 8 }) {
          Text(this.userCode)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontFamily('monospace')
            .letterSpacing(2)
            .fontColor($r('app.color.accent'))
          Row({ space: 8 }) {
            Button(this.copiedCode ? '已复制' : '复制授权码')
              .height(34)
              .fontSize(12)
              .backgroundColor($r('app.color.tint'))
              .fontColor($r('app.color.accent'))
              .onClick(() => { this.copyUserCode(); })
            if (this.verificationUrl.length > 0) {
              Button('打开浏览器')
                .height(34)
                .fontSize(12)
                .backgroundColor($r('app.color.panel'))
                .fontColor($r('app.color.ink'))
                .onClick(() => { this.openAuthBrowser(this.verificationUrl); })
            }
          }
        }
        .width('100%')
        .padding(12)
        .borderRadius(12)
        .backgroundColor($r('app.color.panel'))
        .alignItems(HorizontalAlign.Center)
      }

      Row({ space: 8 }) {
        Button(this.signingIn ? '取消登录' : (this.sessionId ? '重新授权' : '使用 OpenCode Go 登录'))
          .height(36)
          .fontSize(13)
          .onClick(() => { this.startLogin(); })
        if (this.sessionId) {
          Button('管理订阅')
            .height(36)
            .fontSize(13)
            .backgroundColor($r('app.color.tint'))
            .fontColor($r('app.color.accent'))
            .onClick(() => { this.openAuthBrowser(OPENCODE_GO_CONSOLE_URL + '/go'); })
        }
      }

      if (this.statusText.length > 0) {
        Text(this.statusText).fontSize(12).fontColor($r('app.color.muted'))
      }
      if (this.errorText.length > 0) {
        Text(this.errorText).fontSize(12).fontColor($r('app.color.warning'))
      }
    }
    .width('100%')
    .padding(12)
    .borderRadius(14)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.surface'))
  }
}
