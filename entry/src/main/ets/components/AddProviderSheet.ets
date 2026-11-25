import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { BrandIconId } from '../core/BrandIcons';
import { ChatGptLogin } from '../core/ChatGptLogin';
import { PlanSession, savePlanSession } from '../core/ChatGptSession';
import { hexWithAlpha } from '../core/ImmersiveUtils';
import { ApiFamily, Provider, checkEndpoint, preset } from '../core/Models';
import { OpenCodeGoLogin } from '../core/OpenCodeGoLogin';
import { OpenCodeGoSession } from '../core/OpenCodeGoSession';
import { newId } from '../core/Storage';
import { KelivoAvatarBadge } from './KelivoChrome';

const OPENAI_DEFAULT_BASE = 'https://api.openai.com/v1';
const OPENAI_DEFAULT_PATH = '/chat/completions';
const GOOGLE_GEMINI_DEFAULT_BASE = 'https://generativelanguage.googleapis.com/v1beta';
const GOOGLE_VERTEX_DEFAULT_BASE = 'https://aiplatform.googleapis.com/v1';
const CLAUDE_DEFAULT_BASE = 'https://api.anthropic.com/v1';

@Component
export struct AddProviderSheet {
  onCreateProvider: (provider: Provider, apiKey: string) => Promise<void> = async () => {};
  onConnectChatGpt: (session: PlanSession) => Promise<Provider> = async () => preset('', '', 'openai', '', '');
  onConnectOpenCodeGo: (session: OpenCodeGoSession) => Promise<Provider> = async () => preset('', '', 'openai', '', '');
  onViewProviderDetail: (providerId: string) => void = () => {};
  onClose: () => void = () => {};

  @StorageProp('immersiveLightEnabled') immersiveLightEnabled: boolean = true;
  @StorageProp('effectiveDarkMode') isDarkMode: boolean = false;
  @StorageProp('themeAccentHex') themeAccentHex: string = '#4D5C92';
  @StorageProp('windowBottomInsetVp') winBottomInset: number = 0;

  @State activeTabIndex: number = 0;

  // OpenAI
  @State openaiEnabled: boolean = true;
  @State openaiUseResponse: boolean = false;
  @State openaiName: string = 'OpenAI';
  @State openaiKey: string = '';
  @State openaiBase: string = OPENAI_DEFAULT_BASE;
  @State openaiPath: string = OPENAI_DEFAULT_PATH;

  // Google
  @State googleEnabled: boolean = true;
  @State googleVertex: boolean = false;
  @State googleName: string = 'Google';
  @State googleKey: string = '';
  @State googleBase: string = GOOGLE_GEMINI_DEFAULT_BASE;

  // Claude
  @State claudeEnabled: boolean = true;
  @State claudeName: string = 'Claude';
  @State claudeKey: string = '';
  @State claudeBase: string = CLAUDE_DEFAULT_BASE;

  // Account login
  @State signingKind: '' | 'chatgpt' | 'opencode-go' = '';
  @State deviceUserCode: string = '';
  @State deviceVerifyUrl: string = '';
  @State oauthStatusText: string = '';
  @State oauthErrorText: string = '';
  @State copiedCode: boolean = false;
  @State connectedProviderId: string = '';
  @State connectedProviderName: string = '';
  @State connectedAccountLabel: string = '';
  @State connectedBrandId: BrandIconId = '';

  @State formError: string = '';
  @State submitting: boolean = false;

  private chatGptAttempt?: ChatGptLogin;
  private openCodeAttempt?: OpenCodeGoLogin;
  private chatGptRetryClientId: string = '';

  aboutToDisappear(): void {
    this.chatGptAttempt?.cancel();
    this.openCodeAttempt?.cancel();
  }

  private switchTab(idx: number): void {
    this.activeTabIndex = idx;
    this.formError = '';
  }

  private previewBase(tab: number): string {
    if (tab === 0) {
      return (this.openaiBase.trim() || OPENAI_DEFAULT_BASE).replace(/\/+$/, '');
    }
    if (tab === 1) {
      const defBase = this.googleVertex ? GOOGLE_VERTEX_DEFAULT_BASE : GOOGLE_GEMINI_DEFAULT_BASE;
      return (this.googleBase.trim() || defBase).replace(/\/+$/, '');
    }
    return (this.claudeBase.trim() || CLAUDE_DEFAULT_BASE).replace(/\/+$/, '');
  }

  private previewPath(tab: number): string {
    if (tab === 0) {
      if (this.openaiUseResponse) {
        return '/responses';
      }
      const raw = this.openaiPath.trim();
      if (!raw) {
        return OPENAI_DEFAULT_PATH;
      }
      return raw.startsWith('/') ? raw : '/' + raw;
    }
    if (tab === 1) {
      return '/models/{model}:streamGenerateContent';
    }
    return '/messages';
  }

  private tabLabel(idx: number): string {
    if (idx === 0) return 'OpenAI';
    if (idx === 1) return 'Google';
    if (idx === 2) return 'Claude';
    return '账号登录';
  }

  private segmentBgColor(selected: boolean): ResourceColor {
    if (!selected) {
      return Color.Transparent;
    }
    return hexWithAlpha(this.themeAccentHex, this.isDarkMode ? '38' : '22');
  }

  private addButtonBgColor(): ResourceColor {
    return hexWithAlpha(this.themeAccentHex, this.isDarkMode ? '33' : '1E');
  }

  private addButtonBorderColor(): ResourceColor {
    return hexWithAlpha(this.themeAccentHex, this.isDarkMode ? '77' : '55');
  }

  private cancelActiveLogin(): void {
    this.chatGptAttempt?.cancel();
    this.openCodeAttempt?.cancel();
    this.chatGptAttempt = undefined;
    this.openCodeAttempt = undefined;
    this.signingKind = '';
    this.deviceUserCode = '';
    this.deviceVerifyUrl = '';
    this.copiedCode = false;
    this.oauthStatusText = '';
  }

  private openSystemBrowser(targetUrl: string): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ctx.openLink(targetUrl, { appLinkingOnly: false })
      .catch(() => {
        this.oauthErrorText = '无法打开系统浏览器，请手动访问 ' + targetUrl;
      });
  }

  private async copyDeviceCode(): Promise<void> {
    if (!this.deviceUserCode) {
      return;
    }
    try {
      await pasteboard.getSystemPasteboard().setData(
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.deviceUserCode)
      );
      this.copiedCode = true;
      this.oauthStatusText = '已复制授权码，请在浏览器页面中确认';
    } catch (_) {
      this.oauthErrorText = '复制授权码失败，请手动输入：' + this.deviceUserCode;
    }
  }

  private async startChatGptLogin(): Promise<void> {
    if (this.signingKind.length > 0) {
      return;
    }
    const attempt = new ChatGptLogin();
    this.chatGptAttempt = attempt;
    this.signingKind = 'chatgpt';
    this.deviceUserCode = '';
    this.deviceVerifyUrl = '';
    this.oauthErrorText = '';
    this.oauthStatusText = '请在系统浏览器中授权 ChatGPT 套餐，完成后返回 Kelivo';
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const session = await attempt.authorize(ctx, this.chatGptRetryClientId);
      await savePlanSession(session);
      const prov = await this.onConnectChatGpt(session);
      this.connectedProviderId = prov.id;
      this.connectedProviderName = prov.name;
      this.connectedAccountLabel = session.email || session.subject || prov.name;
      this.connectedBrandId = 'openai';
      this.oauthStatusText = '';
    } catch (e) {
      this.chatGptRetryClientId = attempt.issuedId;
      this.oauthErrorText = (e as Error).message || 'ChatGPT 登录失败，请重试';
      this.oauthStatusText = '';
    } finally {
      this.signingKind = '';
      this.chatGptAttempt = undefined;
    }
  }

  private async startOpenCodeGoLogin(): Promise<void> {
    if (this.signingKind.length > 0) {
      return;
    }
    const attempt = new OpenCodeGoLogin();
    this.openCodeAttempt = attempt;
    this.signingKind = 'opencode-go';
    this.deviceUserCode = '';
    this.deviceVerifyUrl = '';
    this.copiedCode = false;
    this.oauthErrorText = '';
    this.oauthStatusText = '正在请求 OpenCode Go 授权码…';
    try {
      const challenge = await attempt.requestChallenge();
      this.deviceUserCode = challenge.userCode;
      this.deviceVerifyUrl = challenge.verificationUrl;
      this.oauthStatusText = '等待浏览器批准授权…';
      this.openSystemBrowser(challenge.verificationUrl);
      const session = await attempt.pollForSession(challenge);
      const prov = await this.onConnectOpenCodeGo(session);
      this.connectedProviderId = prov.id;
      this.connectedProviderName = prov.name;
      this.connectedAccountLabel = session.email && session.orgName
        ? `${session.email} · ${session.orgName}`
        : (session.email || session.orgName || prov.name);
      this.connectedBrandId = 'opencode';
      this.deviceUserCode = '';
      this.deviceVerifyUrl = '';
      this.oauthStatusText = '';
    } catch (e) {
      this.oauthErrorText = (e as Error).message || 'OpenCode Go 登录失败，请重试';
      this.oauthStatusText = '';
    } finally {
      this.signingKind = '';
      this.openCodeAttempt = undefined;
    }
  }

  private async submitAdd(): Promise<void> {
    if (this.submitting || this.activeTabIndex >= 3) {
      return;
    }
    this.formError = '';
    this.submitting = true;
    try {
      let displayName = '';
      let family: ApiFamily = 'openai';
      let rawBase = '';
      let rawKey = '';
      let enabledState = true;
      let chatPath = '';

      if (this.activeTabIndex === 0) {
        displayName = this.openaiName.trim() || 'OpenAI';
        family = this.openaiUseResponse ? 'openai-responses' : 'openai';
        rawBase = this.openaiBase.trim() || OPENAI_DEFAULT_BASE;
        rawKey = this.openaiKey.trim();
        enabledState = this.openaiEnabled;
        if (!this.openaiUseResponse) {
          const p = this.openaiPath.trim();
          chatPath = p ? (p.startsWith('/') ? p : '/' + p) : OPENAI_DEFAULT_PATH;
        }
      } else if (this.activeTabIndex === 1) {
        displayName = this.googleName.trim() || 'Google';
        family = this.googleVertex ? 'vertex' : 'gemini';
        rawBase = this.googleBase.trim() || (this.googleVertex ? GOOGLE_VERTEX_DEFAULT_BASE : GOOGLE_GEMINI_DEFAULT_BASE);
        rawKey = this.googleKey.trim();
        enabledState = this.googleEnabled;
      } else {
        displayName = this.claudeName.trim() || 'Claude';
        family = 'anthropic';
        rawBase = this.claudeBase.trim() || CLAUDE_DEFAULT_BASE;
        rawKey = this.claudeKey.trim();
        enabledState = this.claudeEnabled;
      }

      const checkedBase = checkEndpoint(rawBase);
      const prov = preset(newId(), displayName, family, checkedBase, '');
      prov.enabled = enabledState;
      prov.chatPath = chatPath;
      await this.onCreateProvider(prov, rawKey);
      this.onClose();
    } catch (e) {
      this.formError = (e as Error).message || '添加供应商失败';
    } finally {
      this.submitting = false;
    }
  }

  @Builder
  private fieldLabel(titleText: string) {
    Text(titleText)
      .fontSize(13)
      .fontColor($r('app.color.muted'))
      .margin({ left: 8, top: 2 })
  }

  @Builder
  private requestPreview(tab: number) {
    Text() {
      Span('请求地址 ' + this.previewBase(tab)).fontColor($r('app.color.muted'))
      Span(this.previewPath(tab)).fontColor($r('app.color.accent'))
    }
    .fontSize(12)
    .lineHeight(18)
    .padding({ left: 8, right: 8 })
    .width('100%')
    .copyOption(CopyOptions.LocalDevice)
  }

  @Builder
  private openaiForm() {
    Column({ space: 10 }) {
      Column() {
        Row() {
          Text('是否启用')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.openaiEnabled })
            .selectedColor($r('app.color.accent'))
            .onChange((v: boolean) => { this.openaiEnabled = v; })
        }
        .width('100%')
        .height(52)
        .padding({ left: 16, right: 14 })

        Divider().color($r('app.color.line')).margin({ left: 16 })

        Row() {
          Text('Response API')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.openaiUseResponse })
            .selectedColor($r('app.color.accent'))
            .onChange((v: boolean) => { this.openaiUseResponse = v; })
        }
        .width('100%')
        .height(52)
        .padding({ left: 16, right: 14 })
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor($r('app.color.surface'))

      this.fieldLabel('名称')
      TextInput({ text: this.openaiName, placeholder: 'OpenAI' })
        .id('addProviderName')
        .width('100%')
        .height(48)
        .fontSize(15)
        .padding({ left: 14, right: 14 })
        .borderRadius(14)
        .border({ width: 1, color: $r('app.color.line') })
        .backgroundColor($r('app.color.surface'))
        .onChange((v: string) => { this.openaiName = v; })

      this.fieldLabel('API Key')
      TextInput({ text: this.openaiKey, placeholder: '例如 sk-...' })
        .id('addProviderApiKey')
        .width('100%')
        .height(48)
        .fontSize(15)
        .padding({ left: 14, right: 14 })
        .borderRadius(14)
        .border({ width: 1, color: $r('app.color.line') })
        .backgroundColor($r('app.color.surface'))
        .onChange((v: string) => { this.openaiKey = v; })

      this.fieldLabel('API Base URL')
      TextInput({ text: this.openaiBase, placeholder: OPENAI_DEFAULT_BASE })
        .id('addProviderBaseUrl')
        .width('100%')
        .height(48)
        .fontSize(15)
        .padding({ left: 14, right: 14 })
        .borderRadius(14)
        .border({ width: 1, color: $r('app.color.line') })
        .backgroundColor($r('app.color.surface'))
        .onChange((v: string) => { this.openaiBase = v; })

      this.requestPreview(0)

      if (!this.openaiUseResponse) {
        this.fieldLabel('API 路径')
        TextInput({ text: this.openaiPath, placeholder: OPENAI_DEFAULT_PATH })
          .id('addProviderApiPath')
          .width('100%')
          .height(48)
          .fontSize(15)
          .padding({ left: 14, right: 14 })
          .borderRadius(14)
          .border({ width: 1, color: $r('app.color.line') })
          .backgroundColor($r('app.color.surface'))
          .onChange((v: string) => { this.openaiPath = v; })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private googleForm() {
    Column({ space: 10 }) {
      Column() {
        Row() {
          Text('是否启用')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.googleEnabled })
            .selectedColor($r('app.color.accent'))
            .onChange((v: boolean) => { this.googleEnabled = v; })
        }
        .width('100%')
        .height(52)
        .padding({ left: 16, right: 14 })

        Divider().color($r('app.color.line')).margin({ left: 16 })

        Row() {
          Text('Vertex AI')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.googleVertex })
            .selectedColor($r('app.color.accent'))
            .onChange((v: boolean) => {
              this.googleVertex = v;
              if (v && this.googleBase.trim() === GOOGLE_GEMINI_DEFAULT_BASE) {
                this.googleBase = GOOGLE_VERTEX_DEFAULT_BASE;
              } else if (!v && this.googleBase.trim() === GOOGLE_VERTEX_DEFAULT_BASE) {
                this.googleBase = GOOGLE_GEMINI_DEFAULT_BASE;
              }
            })
        }
        .width('100%')
        .height(52)
        .padding({ left: 16, right: 14 })
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor($r('app.color.surface'))

      this.fieldLabel('名称')
      TextInput({ text: this.googleName, placeholder: 'Google' })
        .width('100%')
        .height(48)
        .fontSize(15)
        .padding({ left: 14, right: 14 })
        .borderRadius(14)
        .border({ width: 1, color: $r('app.color.line') })
        .backgroundColor($r('app.color.surface'))
        .onChange((v: string) => { this.googleName = v; })

      this.fieldLabel('API Key')
      TextInput({ text: this.googleKey, placeholder: this.googleVertex ? 'Access Token 或 API Key' : '例如 AIza...' })
        .width('100%')
        .height(48)
        .fontSize(15)
        .padding({ left: 14, right: 14 })
        .borderRadius(14)
        .border({ width: 1, color: $r('app.color.line') })
        .backgroundColor($r('app.color.surface'))
        .onChange((v: string) => { this.googleKey = v; })

      this.fieldLabel('API Base URL')
      TextInput({
        text: this.googleBase,
        placeholder: this.googleVertex ? GOOGLE_VERTEX_DEFAULT_BASE : GOOGLE_GEMINI_DEFAULT_BASE
      })
        .width('100%')
        .height(48)
        .fontSize(15)
        .padding({ left: 14, right: 14 })
        .borderRadius(14)
        .border({ width: 1, color: $r('app.color.line') })
        .backgroundColor($r('app.color.surface'))
        .onChange((v: string) => { this.googleBase = v; })

      this.requestPreview(1)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private claudeForm() {
    Column({ space: 10 }) {
      Column() {
        Row() {
          Text('是否启用')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.claudeEnabled })
            .selectedColor($r('app.color.accent'))
            .onChange((v: boolean) => { this.claudeEnabled = v; })
        }
        .width('100%')
        .height(52)
        .padding({ left: 16, right: 14 })
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor($r('app.color.surface'))

      this.fieldLabel('名称')
      TextInput({ text: this.claudeName, placeholder: 'Claude' })
        .width('100%')
        .height(48)
        .fontSize(15)
        .padding({ left: 14, right: 14 })
        .borderRadius(14)
        .border({ width: 1, color: $r('app.color.line') })
        .backgroundColor($r('app.color.surface'))
        .onChange((v: string) => { this.claudeName = v; })

      this.fieldLabel('API Key')
      TextInput({ text: this.claudeKey, placeholder: '例如 sk-ant-...' })
        .width('100%')
        .height(48)
        .fontSize(15)
        .padding({ left: 14, right: 14 })
        .borderRadius(14)
        .border({ width: 1, color: $r('app.color.line') })
        .backgroundColor($r('app.color.surface'))
        .onChange((v: string) => { this.claudeKey = v; })

      this.fieldLabel('API Base URL')
      TextInput({ text: this.claudeBase, placeholder: CLAUDE_DEFAULT_BASE })
        .width('100%')
        .height(48)
        .fontSize(15)
        .padding({ left: 14, right: 14 })
        .borderRadius(14)
        .border({ width: 1, color: $r('app.color.line') })
        .backgroundColor($r('app.color.surface'))
        .onChange((v: string) => { this.claudeBase = v; })

      this.requestPreview(2)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private accountLoginView() {
    Column({ space: 12 }) {
      if (this.connectedProviderId.length > 0) {
        Column({ space: 12 }) {
          KelivoAvatarBadge({
            brandId: this.connectedBrandId,
            avatarText: '',
            fallbackLetter: this.connectedProviderName || 'A',
            badgeSize: 48
          })
          Text('已连接')
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.accent'))
          Text(this.connectedAccountLabel || this.connectedProviderName)
            .fontSize(13)
            .fontColor($r('app.color.muted'))
            .textAlign(TextAlign.Center)
          Row({ space: 10 }) {
            Button('查看详情')
              .type(ButtonType.Normal)
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .borderRadius(12)
              .backgroundColor($r('app.color.accent'))
              .fontColor($r('app.color.on_accent'))
              .onClick(() => { this.onViewProviderDetail(this.connectedProviderId); })
            Button('完成')
              .type(ButtonType.Normal)
              .layoutWeight(1)
              .height(40)
              .fontSize(14)
              .borderRadius(12)
              .backgroundColor($r('app.color.panel'))
              .fontColor($r('app.color.ink'))
              .onClick(() => { this.onClose(); })
          }
          .width('100%')

          Button('继续登录其他账号')
            .type(ButtonType.Normal)
            .height(34)
            .fontSize(13)
            .backgroundColor(Color.Transparent)
            .fontColor($r('app.color.muted'))
            .onClick(() => {
              this.connectedProviderId = '';
              this.connectedProviderName = '';
              this.connectedAccountLabel = '';
              this.oauthErrorText = '';
            })
        }
        .width('100%')
        .padding(18)
        .borderRadius(16)
        .backgroundColor($r('app.color.surface'))
        .alignItems(HorizontalAlign.Center)
      } else if (this.signingKind === 'opencode-go') {
        Column({ space: 12 }) {
          Row({ space: 10 }) {
            KelivoAvatarBadge({
              brandId: 'opencode',
              avatarText: '',
              fallbackLetter: 'O',
              badgeSize: 34
            })
            Column({ space: 2 }) {
              Text('OpenCode Go 设备码登录')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.ink'))
              Text('OpenCode Console · 浏览器确认授权')
                .fontSize(12)
                .fontColor($r('app.color.muted'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')

          if (this.deviceUserCode.length > 0) {
            Column({ space: 6 }) {
              Text(this.deviceUserCode)
                .fontSize(24)
                .fontWeight(FontWeight.Bold)
                .fontFamily('monospace')
                .letterSpacing(3)
                .fontColor($r('app.color.accent'))
              Text('请在系统浏览器中确认以上授权码，并选择包含 Go 订阅的工作区')
                .fontSize(12)
                .fontColor($r('app.color.muted'))
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .padding(14)
            .borderRadius(12)
            .backgroundColor($r('app.color.panel'))
            .alignItems(HorizontalAlign.Center)

            Row({ space: 10 }) {
              Button(this.copiedCode ? '已复制授权码' : '复制授权码')
                .type(ButtonType.Normal)
                .layoutWeight(1)
                .height(38)
                .fontSize(13)
                .borderRadius(10)
                .backgroundColor($r('app.color.tint'))
                .fontColor($r('app.color.accent'))
                .onClick(() => { this.copyDeviceCode(); })
              if (this.deviceVerifyUrl.length > 0) {
                Button('打开授权页面')
                  .type(ButtonType.Normal)
                  .layoutWeight(1)
                  .height(38)
                  .fontSize(13)
                  .borderRadius(10)
                  .backgroundColor($r('app.color.panel'))
                  .fontColor($r('app.color.ink'))
                  .onClick(() => { this.openSystemBrowser(this.deviceVerifyUrl); })
              }
            }
            .width('100%')
          }

          Row({ space: 8 }) {
            LoadingProgress().width(18).height(18).color($r('app.color.accent'))
            Text(this.oauthStatusText || '等待浏览器批准授权…')
              .fontSize(12)
              .fontColor($r('app.color.muted'))
              .layoutWeight(1)
          }
          .width('100%')

          Button('取消登录')
            .type(ButtonType.Normal)
            .width('100%')
            .height(38)
            .fontSize(13)
            .borderRadius(10)
            .backgroundColor($r('app.color.panel'))
            .fontColor($r('app.color.ink'))
            .onClick(() => { this.cancelActiveLogin(); })
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor($r('app.color.surface'))
        .alignItems(HorizontalAlign.Start)
      } else if (this.signingKind === 'chatgpt') {
        Column({ space: 12 }) {
          Row({ space: 10 }) {
            KelivoAvatarBadge({
              brandId: 'openai',
              avatarText: '',
              fallbackLetter: 'C',
              badgeSize: 34
            })
            Column({ space: 2 }) {
              Text('ChatGPT 账号登录')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.ink'))
              Text('Codex · 浏览器 PKCE 授权')
                .fontSize(12)
                .fontColor($r('app.color.muted'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')

          Row({ space: 8 }) {
            LoadingProgress().width(18).height(18).color($r('app.color.accent'))
            Text(this.oauthStatusText || '请在系统浏览器中授权 ChatGPT 套餐，完成后返回 Kelivo')
              .fontSize(12)
              .fontColor($r('app.color.muted'))
              .layoutWeight(1)
          }
          .width('100%')

          Button('取消登录')
            .type(ButtonType.Normal)
            .width('100%')
            .height(38)
            .fontSize(13)
            .borderRadius(10)
            .backgroundColor($r('app.color.panel'))
            .fontColor($r('app.color.ink'))
            .onClick(() => { this.cancelActiveLogin(); })
        }
        .width('100%')
        .padding(16)
        .borderRadius(16)
        .backgroundColor($r('app.color.surface'))
        .alignItems(HorizontalAlign.Start)
      } else {
        Column() {
          Row({ space: 12 }) {
            KelivoAvatarBadge({
              brandId: 'openai',
              avatarText: '',
              fallbackLetter: 'C',
              badgeSize: 36
            })
            Column({ space: 3 }) {
              Text('ChatGPT')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.ink'))
              Text('ChatGPT 订阅 · 浏览器授权')
                .fontSize(12)
                .fontColor($r('app.color.muted'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Button('登录')
              .id('loginChatGptAccount')
              .type(ButtonType.Normal)
              .height(34)
              .fontSize(13)
              .padding({ left: 14, right: 14 })
              .borderRadius(10)
              .backgroundColor($r('app.color.tint'))
              .fontColor($r('app.color.accent'))
              .onClick(() => { this.startChatGptLogin(); })
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 14, bottom: 14 })

          Divider().color($r('app.color.line')).margin({ left: 62 })

          Row({ space: 12 }) {
            KelivoAvatarBadge({
              brandId: 'opencode',
              avatarText: '',
              fallbackLetter: 'O',
              badgeSize: 36
            })
            Column({ space: 3 }) {
              Text('OpenCode Go')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.ink'))
              Text('OpenCode Console · 设备码登录')
                .fontSize(12)
                .fontColor($r('app.color.muted'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Button('登录')
              .id('loginOpenCodeGoAccount')
              .type(ButtonType.Normal)
              .height(34)
              .fontSize(13)
              .padding({ left: 14, right: 14 })
              .borderRadius(10)
              .backgroundColor($r('app.color.tint'))
              .fontColor($r('app.color.accent'))
              .onClick(() => { this.startOpenCodeGoLogin(); })
          }
          .width('100%')
          .padding({ left: 14, right: 14, top: 14, bottom: 14 })
        }
        .width('100%')
        .borderRadius(16)
        .backgroundColor($r('app.color.surface'))

        Text('账号登录后将自动同步可用模型，并可在供应商详情中查看订阅额度或重新授权。')
          .fontSize(12)
          .lineHeight(18)
          .fontColor($r('app.color.muted'))
          .padding({ left: 6, right: 6 })
          .width('100%')
      }

      if (this.oauthErrorText.length > 0) {
        Text(this.oauthErrorText)
          .fontSize(12)
          .fontColor($r('app.color.warning'))
          .padding({ left: 6, right: 6 })
          .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Stack() {
        Text('添加供应商')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
        Row() {
          Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            SymbolGlyph($r('sys.symbol.xmark'))
              .fontSize(19)
              .fontColor([$r('app.color.ink')])
          }
          .id('closeAddProviderSheet')
          .width(36)
          .height(36)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText('关闭')
          .onClick(() => {
            this.cancelActiveLogin();
            this.onClose();
          })
          Blank()
        }
        .width('100%')
      }
      .width('100%')
      .height(44)
      .padding({ left: 10, right: 10 })

      Row({ space: 4 }) {
        ForEach([0, 1, 2, 3], (idx: number) => {
          Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Text(this.tabLabel(idx))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.activeTabIndex === idx ? $r('app.color.accent') : $r('app.color.ink'))
              .opacity(this.activeTabIndex === idx ? 1 : 0.82)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .height('100%')
          .padding({ left: 4, right: 4 })
          .borderRadius(14)
          .backgroundColor(this.segmentBgColor(this.activeTabIndex === idx))
          .onClick(() => { this.switchTab(idx); })
        }, (idx: number): string => String(idx))
      }
      .height(44)
      .padding(4)
      .margin({ left: 16, right: 16, top: 8, bottom: 14 })
      .borderRadius(18)
      .backgroundColor($r('app.color.surface'))

      Scroll() {
        Column() {
          if (this.activeTabIndex === 0) {
            this.openaiForm()
          } else if (this.activeTabIndex === 1) {
            this.googleForm()
          } else if (this.activeTabIndex === 2) {
            this.claudeForm()
          } else {
            this.accountLoginView()
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 20 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)

      if (this.activeTabIndex < 3) {
        Column({ space: 8 }) {
          if (this.formError.length > 0) {
            Text(this.formError)
              .fontSize(12)
              .fontColor($r('app.color.warning'))
              .width('100%')
              .padding({ left: 4, right: 4 })
          }
          Button({ type: ButtonType.Normal, buttonStyle: ButtonStyleMode.TEXTUAL }) {
            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.plus'))
                .fontSize(16)
                .fontColor([$r('app.color.accent')])
              Text(this.submitting ? '添加中…' : '添加')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.accent'))
            }
          }
          .id('confirmAddProvider')
          .width('100%')
          .height(46)
          .borderRadius(12)
          .backgroundColor(this.addButtonBgColor())
          .border({ width: 1, color: this.addButtonBorderColor() })
          .enabled(!this.submitting)
          .onClick(() => { this.submitAdd(); })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 6, bottom: Math.max(16, this.winBottomInset + 8) })
      } else {
        Column()
          .width('100%')
          .height(Math.max(16, this.winBottomInset + 8))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }
}
