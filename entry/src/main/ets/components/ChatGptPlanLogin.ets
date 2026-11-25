import { common } from '@kit.AbilityKit';
import { ChatGptLogin } from '../core/ChatGptLogin';
import { PlanSession, savePlanSession } from '../core/ChatGptSession';

@Component
export struct ChatGptPlanLogin {
  @Prop clientId: string = '';
  @Prop accountLabel: string = '';
  onConnected: (session: PlanSession) => Promise<void> = async () => {};
  @State private signingIn: boolean = false;
  @State private message: string = '';
  private attempt?: ChatGptLogin;
  private retryClientId: string = '';

  aboutToDisappear(): void { this.attempt?.cancel(); }

  private async connect(): Promise<void> {
    if (this.signingIn) { this.attempt?.cancel(); return; }
    const attempt = new ChatGptLogin();
    this.attempt = attempt;
    this.signingIn = true;
    this.message = '请在系统浏览器中授权，然后返回 Kelivo';
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const session = await attempt.authorize(ctx, this.clientId || this.retryClientId);
      await savePlanSession(session);
      await this.onConnected(session);
      this.message = '已连接 ChatGPT 套餐';
    } catch (e) {
      this.retryClientId = attempt.issuedId;
      this.message = (e as Error).message || 'ChatGPT 登录失败，请重试';
    } finally { this.signingIn = false; this.attempt = undefined; }
  }

  build() {
    Column({ space: 8 }) {
      Text(this.accountLabel || '使用 ChatGPT 套餐').fontSize(15).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink'))
      Text('模型请求使用授权账号的 ChatGPT 套餐额度。').fontSize(12).fontColor($r('app.color.muted'))
      Row({ space: 8 }) {
        Button(this.signingIn ? '取消登录' : (this.clientId ? '重新授权' : '使用 ChatGPT 登录'))
          .height(36).fontSize(13).onClick(() => { this.connect(); })
        if (this.clientId) {
          Button('管理用量').height(36).fontSize(13).backgroundColor($r('app.color.tint')).fontColor($r('app.color.accent'))
            .onClick(() => {
              const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
              ctx.openLink('https://chatgpt.com/settings/usage', { appLinkingOnly: false })
                .catch(() => { this.message = '无法打开 ChatGPT 用量设置'; });
            })
        }
      }
      if (this.message) { Text(this.message).fontSize(12).fontColor($r('app.color.muted')) }
    }.width('100%').padding(12).borderRadius(14).alignItems(HorizontalAlign.Start).backgroundColor($r('app.color.surface'))
  }
}
