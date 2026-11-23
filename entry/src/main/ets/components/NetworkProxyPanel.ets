import { ProxyTestResult, testProxyConnection } from '../core/ChatClient';
import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import {
  DEFAULT_PROXY_BYPASS_RULES,
  ProxyConfig,
  ProxyType,
  defaultGlobalProxy,
  normalizeProxyConfig,
  normalizeProxyType
} from '../core/Models';
import { KelivoPageHeader } from './KelivoChrome';

@Component
export struct NetworkProxyPanel {
  @Prop globalProxy: ProxyConfig = defaultGlobalProxy();
  @Prop initialPassword: string = '';
  @Prop immersiveLightEnabled: boolean = true;
  @Prop embeddedInNav: boolean = false;

  onSaveGlobalProxy: (next: ProxyConfig, passwordPlain: string) => Promise<void> = async () => {};
  onClose: () => void = () => {};

  @StorageProp('windowTopInsetVp') winTopInset: number = 0;
  @StorageProp('windowBottomInsetVp') winBottomInset: number = 0;

  @State proxyEnabled: boolean = false;
  @State proxyType: ProxyType = 'http';
  @State host: string = '';
  @State portText: string = '8080';
  @State username: string = '';
  @State password: string = '';
  @State bypass: string = DEFAULT_PROXY_BYPASS_RULES;

  @State testUrl: string = 'https://www.google.com';
  @State testing: boolean = false;
  @State testOk: number = -1; // -1: not run, 1: ok, 0: fail
  @State testMessage: string = '';

  private saveTimer: number = -1;
  private dirty: boolean = false;

  aboutToAppear(): void {
    const cfg = normalizeProxyConfig(this.globalProxy, true);
    this.proxyEnabled = cfg.enabled === true;
    this.proxyType = normalizeProxyType(cfg.type);
    this.host = cfg.host || '';
    this.portText = String(cfg.port > 0 ? cfg.port : 8080);
    this.username = cfg.username || '';
    this.password = this.initialPassword || '';
    this.bypass = cfg.bypass !== undefined ? cfg.bypass : DEFAULT_PROXY_BYPASS_RULES;
    this.dirty = false;
  }

  aboutToDisappear(): void {
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
    }
    if (this.dirty) {
      this.saveNow().catch(() => {});
    }
  }

  private buildCurrentConfig(): ProxyConfig {
    const parsedPort = Number(this.portText.trim());
    const port = Number.isFinite(parsedPort) && parsedPort > 0 && parsedPort <= 65535
      ? Math.floor(parsedPort)
      : 8080;
    return {
      enabled: this.proxyEnabled,
      type: this.proxyType,
      host: this.host.trim(),
      port,
      username: this.username.trim(),
      passwordRef: this.globalProxy.passwordRef,
      bypass: this.bypass.trim()
    };
  }

  private scheduleSave(): void {
    this.dirty = true;
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
    }
    this.saveTimer = setTimeout(() => {
      this.saveTimer = -1;
      this.saveNow().catch(() => {});
    }, 350);
  }

  private async saveNow(): Promise<void> {
    if (this.saveTimer >= 0) {
      clearTimeout(this.saveTimer);
      this.saveTimer = -1;
    }
    this.dirty = false;
    await this.onSaveGlobalProxy(this.buildCurrentConfig(), this.password);
  }

  private proxyTypeLabel(t: ProxyType): string {
    if (t === 'https') return 'HTTPS';
    if (t === 'socks5') return 'SOCKS5';
    return 'HTTP';
  }

  private async runConnectionTest(): Promise<void> {
    if (this.testing) return;
    await this.saveNow();
    this.testing = true;
    this.testOk = -1;
    this.testMessage = '';
    try {
      const res: ProxyTestResult = await testProxyConnection(
        this.buildCurrentConfig(),
        this.password,
        this.testUrl
      );
      if (res.ok) {
        this.testOk = 1;
        this.testMessage = `连接成功 (HTTP ${res.status} · ${res.elapsedMs} ms)`;
      } else {
        this.testOk = 0;
        this.testMessage = `测试失败：${res.error || '未知错误'}`;
      }
    } catch (e) {
      this.testOk = 0;
      this.testMessage = `测试失败：${(e as Error).message || String(e)}`;
    } finally {
      this.testing = false;
    }
  }

  @Builder
  private fieldLabel(label: string) {
    Text(label)
      .fontSize(12)
      .fontColor($r('app.color.muted'))
      .width('100%')
  }

  @Builder
  private typePill(label: string, kind: ProxyType) {
    Button(label)
      .type(ButtonType.Normal)
      .height(32)
      .fontSize(12)
      .borderRadius(8)
      .layoutWeight(1)
      .fontColor(this.proxyType === kind ? $r('app.color.on_accent') : $r('app.color.ink'))
      .backgroundColor(this.proxyType === kind ? $r('app.color.accent') : $r('app.color.canvas'))
      .onClick(async () => {
        if (this.proxyType !== kind) {
          this.proxyType = kind;
          await this.saveNow();
        }
      })
  }

  build() {
    Column() {
      if (!this.embeddedInNav) {
        KelivoPageHeader({
          titleText: '网络代理',
          showBack: true,
          onBack: async () => {
            if (this.dirty) {
              await this.saveNow();
            }
            this.onClose();
          }
        })
      }

      Scroll() {
        Column({ space: 12 }) {
          Column({ space: 12 }) {
            Row({ space: 10 }) {
              Text('启动代理')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.ink'))
                .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.proxyEnabled })
                .onChange(async (v: boolean) => {
                  if (v !== this.proxyEnabled) {
                    this.proxyEnabled = v;
                    await this.saveNow();
                  }
                })
                .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
            }
            .width('100%')

            Column({ space: 6 }) {
              this.fieldLabel('代理类型')
              Row({ space: 8 }) {
                this.typePill(this.proxyTypeLabel('http'), 'http')
                this.typePill(this.proxyTypeLabel('https'), 'https')
                this.typePill(this.proxyTypeLabel('socks5'), 'socks5')
              }
              .width('100%')
            }
            .width('100%')

            Column({ space: 6 }) {
              this.fieldLabel('服务器地址')
              TextInput({ text: this.host, placeholder: '127.0.0.1' })
                .height(40)
                .fontSize(14)
                .borderRadius(10)
                .backgroundColor($r('app.color.canvas'))
                .onChange((v: string) => {
                  if (v !== this.host) {
                    this.host = v;
                    this.scheduleSave();
                  }
                })
                .onEditChange((isEditing: boolean) => {
                  if (!isEditing && this.dirty) {
                    this.saveNow().catch(() => {});
                  }
                })
            }
            .width('100%')

            Column({ space: 6 }) {
              this.fieldLabel('端口')
              TextInput({ text: this.portText, placeholder: '8080' })
                .type(InputType.Number)
                .height(40)
                .fontSize(14)
                .borderRadius(10)
                .backgroundColor($r('app.color.canvas'))
                .onChange((v: string) => {
                  if (v !== this.portText) {
                    this.portText = v;
                    this.scheduleSave();
                  }
                })
                .onEditChange((isEditing: boolean) => {
                  if (!isEditing && this.dirty) {
                    this.saveNow().catch(() => {});
                  }
                })
            }
            .width('100%')

            Column({ space: 6 }) {
              this.fieldLabel('用户名')
              TextInput({ text: this.username, placeholder: '可选' })
                .height(40)
                .fontSize(14)
                .borderRadius(10)
                .backgroundColor($r('app.color.canvas'))
                .onChange((v: string) => {
                  if (v !== this.username) {
                    this.username = v;
                    this.scheduleSave();
                  }
                })
                .onEditChange((isEditing: boolean) => {
                  if (!isEditing && this.dirty) {
                    this.saveNow().catch(() => {});
                  }
                })
            }
            .width('100%')

            Column({ space: 6 }) {
              this.fieldLabel('密码')
              TextInput({ text: this.password, placeholder: '可选' })
                .type(InputType.Password)
                .height(40)
                .fontSize(14)
                .borderRadius(10)
                .backgroundColor($r('app.color.canvas'))
                .onChange((v: string) => {
                  if (v !== this.password) {
                    this.password = v;
                    this.scheduleSave();
                  }
                })
                .onEditChange((isEditing: boolean) => {
                  if (!isEditing && this.dirty) {
                    this.saveNow().catch(() => {});
                  }
                })
            }
            .width('100%')

            Column({ space: 6 }) {
              this.fieldLabel('代理绕过')
              TextArea({
                text: this.bypass,
                placeholder: '用逗号分隔的主机或 CIDR，例如：localhost,127.0.0.1,192.168.0.0/16,*.local'
              })
                .height(68)
                .fontSize(13)
                .borderRadius(10)
                .backgroundColor($r('app.color.canvas'))
                .onChange((v: string) => {
                  if (v !== this.bypass) {
                    this.bypass = v;
                    this.scheduleSave();
                  }
                })
                .onEditChange((isEditing: boolean) => {
                  if (!isEditing && this.dirty) {
                    this.saveNow().catch(() => {});
                  }
                })
            }
            .width('100%')

            Text('当同时开启全局代理与供应商代理时，将优先使用供应商代理。')
              .fontSize(12)
              .lineHeight(18)
              .fontColor($r('app.color.muted'))
              .width('100%')
          }
          .width('100%')
          .padding(14)
          .borderRadius(14)
          .backgroundColor($r('app.color.surface'))

          Text('连接测试')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.muted'))
            .width('100%')
            .padding({ left: 6, top: 2 })

          Column({ space: 10 }) {
            TextInput({ text: this.testUrl, placeholder: '测试地址' })
              .height(40)
              .fontSize(14)
              .borderRadius(10)
              .backgroundColor($r('app.color.canvas'))
              .onChange((v: string) => {
                this.testUrl = v;
              })

            Row() {
              Blank()
              Button(this.testing ? '测试中…' : '测试')
                .type(ButtonType.Normal)
                .height(34)
                .fontSize(13)
                .borderRadius(10)
                .padding({ left: 16, right: 16 })
                .fontColor($r('app.color.ink'))
                .backgroundColor($r('app.color.panel'))
                .enabled(!this.testing)
                .onClick(() => {
                  this.runConnectionTest().catch(() => {});
                })
            }
            .width('100%')
          }
          .width('100%')
          .padding(14)
          .borderRadius(14)
          .backgroundColor($r('app.color.surface'))

          if (this.testOk === 1) {
            Text(this.testMessage)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor('#16A34A')
              .width('100%')
              .padding({ left: 6, right: 6 })
          } else if (this.testOk === 0) {
            Text(this.testMessage)
              .fontSize(13)
              .fontColor($r('app.color.warning'))
              .width('100%')
              .padding({ left: 6, right: 6 })
          }
        }
        .width('100%')
        .padding({
          left: 16,
          right: 16,
          top: this.embeddedInNav ? (56 + this.winTopInset + 4) : 12,
          bottom: Math.max(36, this.winBottomInset + 20)
        })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }
}
