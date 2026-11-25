import { fetchOpenCodeGoUsage, GoQuotaRow } from '../core/ChatClient';
import { ProxyConfig } from '../core/Models';
import { openCodeGoAccessToken } from '../core/OpenCodeGoSession';
import { readKey } from '../core/Storage';

@Component
export struct OpenCodeGoQuota {
  @Prop @Watch('credentialChanged') oauthSessionId: string = '';
  @Prop @Watch('credentialChanged') savedKeyRef: string = '';
  @Prop @Watch('credentialChanged') draftKey: string = '';
  @Prop proxy?: ProxyConfig = undefined;
  @State private rows: GoQuotaRow[] = [];
  @State private loading: boolean = false;
  @State private errorText: string = '';
  private requestId: number = 0;

  aboutToAppear(): void {
    this.credentialChanged();
  }

  aboutToDisappear(): void {
    this.requestId++;
  }

  private credentialChanged(): void {
    this.requestId++;
    this.rows = [];
    this.loading = false;
    this.errorText = '';
    if (this.oauthSessionId.length > 0 || (!this.draftKey.trim() && this.savedKeyRef)) this.refresh();
  }

  private async refresh(): Promise<void> {
    if (this.loading) return;
    const id = ++this.requestId;
    this.loading = true;
    this.rows = [];
    this.errorText = '';
    try {
      const proxy = this.proxy;
      const password = proxy?.enabled && proxy.passwordRef ? await readKey(proxy.passwordRef) : '';
      const key = this.oauthSessionId.length > 0
        ? await openCodeGoAccessToken(this.oauthSessionId, proxy, password)
        : (this.draftKey.trim() || await readKey(this.savedKeyRef));
      if (this.requestId !== id) return;
      const rows = await fetchOpenCodeGoUsage(key, proxy, password);
      if (this.requestId === id) this.rows = rows;
    } catch (err) {
      if (this.requestId === id) this.errorText = (err as Error).message || '无法查询额度，请检查网络后刷新';
    } finally {
      if (this.requestId === id) this.loading = false;
    }
  }

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('OpenCode Go 订阅额度').layoutWeight(1).fontSize(15)
          .fontWeight(FontWeight.Medium).fontColor($r('app.color.ink'))
        Button(this.loading ? '查询中…' : '刷新额度').height(32).fontSize(12)
          .enabled(!this.loading && (!!this.oauthSessionId || !!this.savedKeyRef || !!this.draftKey.trim()))
          .backgroundColor($r('app.color.tint')).fontColor($r('app.color.accent'))
          .onClick(() => { this.refresh(); })
      }.width('100%')
      ForEach(this.rows, (row: GoQuotaRow) => {
        Column({ space: 4 }) {
          Row() {
            Text(row.label).layoutWeight(1).fontSize(13).fontColor($r('app.color.ink'))
            Text('剩余 ' + row.remaining + '%').fontSize(13).fontColor($r('app.color.ink'))
          }.width('100%')
          Progress({ value: row.remaining, total: 100, type: ProgressType.Linear })
            .width('100%').color($r('app.color.accent'))
          Text('重置时间  ' + new Date(row.resetTime).toLocaleString()).fontSize(12).fontColor($r('app.color.muted'))
        }.width('100%').alignItems(HorizontalAlign.Start)
      }, (row: GoQuotaRow): string => row.label + '-' + row.remaining + '-' + row.resetTime)
      if (this.errorText) {
        Text(this.errorText).fontSize(13).fontColor($r('app.color.warning'))
      } else if (!this.oauthSessionId && !this.savedKeyRef && !this.draftKey.trim()) {
        Text('填写主 API 密钥或完成账号登录后可查询额度').fontSize(13).fontColor($r('app.color.muted'))
      }
    }.width('100%').padding(12).borderRadius(14).alignItems(HorizontalAlign.Start)
    .backgroundColor($r('app.color.surface'))
  }
}
