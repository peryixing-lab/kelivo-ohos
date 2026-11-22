import { pasteboard } from '@kit.BasicServicesKit';
import { completeOnce } from '../core/ChatClient';
import { selectApiKey } from '../core/KeyPool';
import { Provider, isProviderConfigured, providerEnabledModels } from '../core/Models';

@Component
export struct TranslatePanel {
  @Prop providers: Provider[] = [];
  @Prop activeProviderId: string = '';
  @Prop defaultTranslateProviderId: string = '';
  @Prop defaultTranslateModelId: string = '';
  @Prop initialText: string = '';
  @Prop embeddedInNav: boolean = false;

  resolveSecret: (ref: string) => Promise<string> = async () => '';
  onSendToChat: (text: string) => void = () => {};
  onClose: () => void = () => {};

  @StorageProp('windowTopInsetVp') winTopInset: number = 0;

  @State sourceLang: string = '自动检测';
  @State targetLang: string = '简体中文';
  @State selectedProviderId: string = '';
  @State selectedModel: string = '';
  @State tone: string = '自然地道';
  @State sourceText: string = '';
  @State translatedText: string = '';
  @State busy: boolean = false;
  @State errMsg: string = '';

  private readonly langs: string[] = [
    '自动检测', '简体中文', '繁體中文', 'English', '日本語', '한국어', 'Русский', 'Türkçe', 'Français', 'Deutsch'
  ];
  private readonly tones: string[] = ['自然地道', '商务正式', '学术严谨', '技术文档', '口语简洁'];

  aboutToAppear(): void {
    this.sourceText = this.initialText;
    const usable = this.usableProviders();
    if (this.defaultTranslateProviderId) {
      const defProv = usable.find((item: Provider): boolean => item.id === this.defaultTranslateProviderId)
        || this.providers.find((item: Provider): boolean => item.id === this.defaultTranslateProviderId);
      if (defProv) {
        this.selectedProviderId = defProv.id;
        this.selectedModel = this.defaultTranslateModelId || this.firstModelId(defProv);
        return;
      }
    }
    if (usable.length > 0) {
      const p = usable.find((item: Provider): boolean => item.id === this.activeProviderId) ?? usable[0];
      this.selectedProviderId = p.id;
      this.selectedModel = this.firstModelId(p);
    } else if (this.providers.length > 0) {
      const p = this.providers.find((item: Provider): boolean => item.id === this.activeProviderId) ?? this.providers[0];
      this.selectedProviderId = p.id;
      this.selectedModel = this.firstModelId(p);
    }
  }

  private firstModelId(p: Provider): string {
    if (p.model.trim()) return p.model.trim();
    const specs = providerEnabledModels(p);
    return specs.length > 0 ? specs[0].id : '';
  }

  private usableProviders(): Provider[] {
    const ready = this.providers.filter((p: Provider): boolean =>
      p.enabled !== false && isProviderConfigured(p) && providerEnabledModels(p).length > 0
    );
    if (ready.length > 0) return ready;
    return this.providers.filter((p: Provider): boolean =>
      p.enabled !== false && providerEnabledModels(p).length > 0
    );
  }

  private currentProvider(): Provider | undefined {
    return this.providers.find((p: Provider): boolean => p.id === this.selectedProviderId)
      ?? this.usableProviders()[0]
      ?? this.providers[0];
  }

  private async runTranslate(): Promise<void> {
    const clean = this.sourceText.trim();
    if (clean.length === 0) {
      this.errMsg = '请输入要翻译的文本';
      return;
    }
    const prov = this.currentProvider();
    if (!prov) {
      this.errMsg = '请先在服务商设置中添加至少一个模型供应商';
      return;
    }
    this.busy = true;
    this.errMsg = '';
    try {
      const picked = prov.apiKeys && prov.apiKeys.length > 0
        ? selectApiKey(prov.id, prov.apiKeys, prov.keyStrategy || 'round_robin')
        : undefined;
      const ref = picked ? picked.secretRef : prov.secretRef;
      const secret = ref ? await this.resolveSecret(ref) : '';
      const proxyPwd = prov.proxy?.passwordRef ? await this.resolveSecret(prov.proxy.passwordRef) : '';
      const sys =
        `你是专业多语言翻译专家。请将用户输入从「${this.sourceLang}」精准翻译为「${this.targetLang}」，语气风格要求「${this.tone}」。` +
        '保留原有的 Markdown 格式、代码块、数字和专有名词；只输出译文正文，不要添加多余解释。';
      const out = await completeOnce(
        prov,
        secret,
        sys,
        clean,
        this.selectedModel || prov.model,
        2048,
        proxyPwd
      );
      this.translatedText = out;
    } catch (e) {
      this.errMsg = `翻译失败: ${String(e)}`;
    } finally {
      this.busy = false;
    }
  }

  private async pasteInput(): Promise<void> {
    try {
      const data = await pasteboard.getSystemPasteboard().getData();
      const txt = data.getPrimaryText();
      if (txt && txt.length > 0) {
        this.sourceText = txt;
      }
    } catch (e) {
      this.errMsg = `读取剪贴板失败: ${String(e)}`;
    }
  }

  private async copyOutput(): Promise<void> {
    if (this.translatedText.length === 0) {
      return;
    }
    try {
      await pasteboard.getSystemPasteboard().setData(
        pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.translatedText)
      );
      this.errMsg = '译文已复制到剪贴板';
    } catch (e) {
      this.errMsg = `复制失败: ${String(e)}`;
    }
  }

  build() {
    Column({ space: 12 }) {
      if (!this.embeddedInNav) {
        Row() {
          Text('双语划词翻译')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.ink'))
          Blank()
          Button('关闭')
            .type(ButtonType.Normal)
            .height(32)
            .fontSize(12)
            .borderRadius(8)
            .fontColor($r('app.color.ink'))
            .backgroundColor($r('app.color.surface'))
            .onClick(() => this.onClose())
        }
        .width('100%')
      }

      Scroll() {
        Column({ space: 10 }) {
          Row({ space: 8 }) {
            Button(`源：${this.sourceLang}`)
              .type(ButtonType.Normal)
              .layoutWeight(1)
              .height(36)
              .fontSize(12)
              .borderRadius(8)
              .fontColor($r('app.color.ink'))
              .backgroundColor($r('app.color.surface'))
              .onClick(() => {
                const idx = this.langs.indexOf(this.sourceLang);
                this.sourceLang = this.langs[(idx + 1) % this.langs.length];
              })
            Button('⇄')
              .type(ButtonType.Normal)
              .width(40)
              .height(36)
              .fontSize(14)
              .borderRadius(8)
              .fontColor($r('app.color.accent'))
              .backgroundColor($r('app.color.tint'))
              .onClick(() => {
                if (this.sourceLang !== '自动检测') {
                  const tmp = this.sourceLang;
                  this.sourceLang = this.targetLang;
                  this.targetLang = tmp;
                }
              })
            Button(`译：${this.targetLang}`)
              .type(ButtonType.Normal)
              .layoutWeight(1)
              .height(36)
              .fontSize(12)
              .borderRadius(8)
              .fontColor($r('app.color.on_accent'))
              .backgroundColor($r('app.color.accent'))
              .onClick(() => {
                const idx = this.langs.indexOf(this.targetLang);
                const nextIdx = (idx + 1) % this.langs.length;
                this.targetLang = this.langs[nextIdx] === '自动检测' ? this.langs[1] : this.langs[nextIdx];
              })
          }
          .width('100%')

          Scroll() {
            Row({ space: 6 }) {
              ForEach(this.tones, (t: string) => {
                Button(t)
                  .type(ButtonType.Normal)
                  .height(28)
                  .fontSize(11)
                  .borderRadius(8)
                  .fontColor(this.tone === t ? $r('app.color.on_accent') : $r('app.color.ink'))
                  .backgroundColor(this.tone === t ? $r('app.color.accent') : $r('app.color.surface'))
                  .onClick(() => {
                    this.tone = t;
                  })
              }, (t: string) => t)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')

          if (this.usableProviders().length > 0) {
            Scroll() {
              Row({ space: 6 }) {
                ForEach(this.usableProviders(), (p: Provider) => {
                  Button(`${p.name} (${this.firstModelId(p)})`)
                    .type(ButtonType.Normal)
                    .height(28)
                    .fontSize(11)
                    .borderRadius(8)
                    .fontColor(this.selectedProviderId === p.id ? $r('app.color.accent') : $r('app.color.muted'))
                    .backgroundColor(this.selectedProviderId === p.id ? $r('app.color.tint') : $r('app.color.surface'))
                    .onClick(() => {
                      this.selectedProviderId = p.id;
                      this.selectedModel = this.firstModelId(p);
                    })
                }, (p: Provider) => p.id)
              }
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
          }

          Column({ space: 6 }) {
            Row({ space: 6 }) {
              Text('原文')
                .fontSize(12)
                .fontColor($r('app.color.muted'))
              Blank()
              PasteButton({
                icon: PasteIconStyle.LINES,
                text: PasteDescription.PASTE,
                buttonType: ButtonType.Capsule
              })
                .height(26)
                .onClick((_event: ClickEvent, result: PasteButtonOnClickResult) => {
                  if (result === PasteButtonOnClickResult.SUCCESS) {
                    this.pasteInput().catch(() => {});
                  } else {
                    this.errMsg = '读取剪贴板失败，请长按输入框手动粘贴';
                  }
                })
              Button('清空')
                .type(ButtonType.Normal)
                .height(26)
                .fontSize(11)
                .borderRadius(6)
                .fontColor($r('app.color.muted'))
                .backgroundColor($r('app.color.surface'))
                .onClick(() => {
                  this.sourceText = '';
                  this.translatedText = '';
                })
            }
            .width('100%')

            TextArea({ text: this.sourceText, placeholder: '输入或粘贴需要翻译的内容...' })
              .height(140)
              .borderRadius(10)
              .backgroundColor($r('app.color.surface'))
              .onChange((v: string) => {
                this.sourceText = v;
              })
          }
          .width('100%')

          Button(this.busy ? '翻译中...' : '立即翻译')
            .type(ButtonType.Normal)
            .width('100%')
            .height(42)
            .fontSize(14)
            .borderRadius(10)
            .fontColor($r('app.color.on_accent'))
            .backgroundColor($r('app.color.accent'))
            .enabled(!this.busy)
            .onClick(async () => {
              await this.runTranslate();
            })

          if (this.errMsg.length > 0) {
            Text(this.errMsg)
              .fontSize(12)
              .fontColor($r('app.color.accent'))
          }

          if (this.translatedText.length > 0) {
            Column({ space: 8 }) {
              Row({ space: 8 }) {
                Text('译文结果')
                  .fontSize(12)
                  .fontColor($r('app.color.muted'))
                Blank()
                Button('复制译文')
                  .type(ButtonType.Normal)
                  .height(26)
                  .fontSize(11)
                  .borderRadius(6)
                  .fontColor($r('app.color.accent'))
                  .backgroundColor($r('app.color.tint'))
                  .onClick(async () => {
                    await this.copyOutput();
                  })
                Button('填入对话')
                  .type(ButtonType.Normal)
                  .height(26)
                  .fontSize(11)
                  .borderRadius(6)
                  .fontColor($r('app.color.ink'))
                  .backgroundColor($r('app.color.canvas'))
                  .onClick(() => {
                    this.onSendToChat(this.translatedText);
                    this.onClose();
                  })
              }
              .width('100%')

              Text(this.translatedText)
                .fontSize(14)
                .fontColor($r('app.color.ink'))
                .copyOption(CopyOptions.LocalDevice)
                .width('100%')
            }
            .padding(12)
            .backgroundColor($r('app.color.surface'))
            .borderRadius(10)
            .width('100%')
          }
        }
        .width('100%')
        .padding({ top: this.embeddedInNav ? (56 + this.winTopInset + 8) : 0, bottom: 48 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: this.embeddedInNav ? 0 : 16, bottom: 0 })
    .backgroundColor(Color.Transparent)
  }
}
