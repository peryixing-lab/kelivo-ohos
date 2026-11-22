import { scanBarcode, scanCore } from '@kit.ScanKit';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { resolveBrandIconId } from '../core/BrandIcons';
import { ImportedProvider, fromProviderText, toProviderLink } from '../core/ProviderLink';
import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { SystemMotion } from '../core/SystemMotion';
import {
  ApiFamily,
  ApiKeyEntry,
  HeaderEntry,
  KeyRotationStrategy,
  ModelDefaults,
  ModelSpec,
  OAuthProviderKind,
  Provider,
  ProxyConfig,
  checkEndpoint,
  defaultModelSpec,
  extractUrlHost,
  isProviderConfigured,
  preset
} from '../core/Models';
import { checkProviderHealth, fetchModels, fetchOllamaCapabilities, fetchProviderBalance } from '../core/ChatClient';
import { forgetKey, newId, readKey, storeKey } from '../core/Storage';
import { KelivoAvatarBadge, KelivoNavTitleBar, KelivoSectionHeader, KelivoStatusPill } from './KelivoChrome';

@Component
export struct ProviderEditor {
  @Prop @Watch('onProvidersPropChange') providers: Provider[] = [];
  @Prop @Watch('onProvidersPropChange') activeId: string = '';
  initialViewMode: 'list' | 'detail' = 'list';
  initialTab: number = 0;
  @Prop modelDefaults: ModelDefaults = {
    chatProviderId: '', chatModelId: '', titleProviderId: '', titleModelId: '',
    translateProviderId: '', translateModelId: '', ocrProviderId: '', ocrModelId: '',
    memoryProviderId: '', memoryModelId: ''
  };
  onApply: (provider: Provider, key: string, reuseKey: boolean, setActive: boolean) => Promise<Provider[]> = async () => [];
  onImportProviders: (items: ImportedProvider[]) => Promise<Provider[]> = async () => [];
  onDeleteProvider: (id: string) => Promise<Provider[]> = async () => [];
  onStartOAuth: (kind: OAuthProviderKind) => void = () => {};
  onDismissOverlay: () => boolean = () => false;
  onClose: () => void = () => {};

  @State viewMode: 'list' | 'detail' = 'list';
  @State localProviders: Provider[] = [];
  @State localActiveId: string = '';
  @State listQuery: string = '';
  @State onlyEnabledFilter: boolean = false;
  @State selectedId: string = '';
  @State provEnabled: boolean = true;
  @StorageProp('windowTopInsetVp') winTopInset: number = 0;
  @StorageProp('windowBottomInsetVp') winBottomInset: number = 0;
  @StorageProp('immersiveLightEnabled') immersiveLightEnabled: boolean = true;
  @StorageProp('themeSurfaceHex') themeSurfaceHex: string = '#FFFFFF';
  @StorageProp('themeCanvasHex') themeCanvasHex: string = '#F7F7F7';
  @StorageProp('reduceMotionEnabled') reduceMotion: boolean = false;
  @State showImportSheet: boolean = false;
  @State importText: string = '';
  @State importError: string = '';
  @State labelText: string = '';
  @State groupName: string = '';
  @State endpoint: string = '';
  @State chatPath: string = '';
  @State family: ApiFamily = 'openai';
  @State keyInput: string = '';
  @State modelId: string = '';
  @State modelChoices: string[] = [];
  @State savedModels: ModelSpec[] = [];
  @State extraKeys: ApiKeyEntry[] = [];
  @State keyStrategy: KeyRotationStrategy = 'round_robin';
  @State extraKeyLabel: string = '';
  @State extraKeySecret: string = '';
  @State proxyEnabled: boolean = false;
  @State proxyHost: string = '';
  @State proxyPortText: string = '7890';
  @State proxyUser: string = '';
  @State proxyPass: string = '';
  @State customHeaders: HeaderEntry[] = [];
  @State newHeaderKey: string = '';
  @State newHeaderVal: string = '';
  @State customBodyJson: string = '';
  @State promptCaching: boolean = false;
  @State sendConvCacheKey: boolean = false;
  @State builtinSearch: boolean = false;
  @State builtinUrlContext: boolean = false;
  @State builtinCodeExec: boolean = false;
  @State balanceUrl: string = '';
  @State balanceResult: string = '';
  @State healthResult: string = '';
  @State activeTab: number = 0; // 0: 配置, 1: 模型列表, 2: 网络与高级
  @State moreOptions: boolean = false;
  @State linkInput: string = '';
  @State shareCode: string = '';
  @State notice: string = '';
  @State busy: boolean = false;
  @State clearSecret: boolean = false;
  private original: Provider = preset('', '', 'openai', '', '');
  private existingProxyPassRef: string = '';

  private onProvidersPropChange(): void {
    this.localProviders = this.providers.slice();
    this.localActiveId = this.activeId;
  }

  aboutToAppear(): void {
    this.localProviders = this.providers.slice();
    this.localActiveId = this.activeId;
    this.viewMode = this.initialViewMode;
    this.activeTab = this.initialTab;
    const first = this.localProviders.find((p: Provider): boolean => p.id === this.localActiveId) || this.localProviders[0];
    if (first) this.selectProvider(first);
  }

  selectProvider(provider: Provider): void {
    this.original = provider;
    this.shareCode = '';
    this.linkInput = '';
    this.healthResult = '';
    this.selectedId = provider.id;
    this.provEnabled = provider.enabled !== false;
    this.labelText = provider.name;
    this.groupName = provider.groupName || '';
    this.endpoint = provider.baseUrl;
    this.chatPath = provider.chatPath || '';
    this.family = provider.family;
    this.modelId = provider.model;
    this.keyInput = '';
    this.clearSecret = false;
    this.modelChoices = [];
    this.savedModels = provider.models ? provider.models.slice() : (provider.model ? [defaultModelSpec(provider.model)] : []);
    this.extraKeys = provider.apiKeys ? provider.apiKeys.slice() : [];
    this.keyStrategy = provider.keyStrategy || 'round_robin';
    this.proxyEnabled = provider.proxy?.enabled || false;
    this.proxyHost = provider.proxy?.host || '';
    this.proxyPortText = String(provider.proxy?.port || 7890);
    this.proxyUser = provider.proxy?.username || '';
    this.existingProxyPassRef = provider.proxy?.passwordRef || '';
    this.proxyPass = '';
    this.customHeaders = provider.customHeaders ? provider.customHeaders.slice() : [];
    this.newHeaderKey = '';
    this.newHeaderVal = '';
    this.customBodyJson = provider.customBodyJson || '';
    this.promptCaching = provider.promptCaching || false;
    this.sendConvCacheKey = provider.sendConversationCacheKey === true;
    this.builtinSearch = provider.builtinSearch || false;
    this.builtinUrlContext = provider.builtinUrlContext || false;
    this.builtinCodeExec = provider.builtinCodeExec || false;
    this.balanceUrl = provider.balanceUrl || '';
    this.balanceResult = provider.lastBalance || '';
    this.notice = '';
  }

  private reuseSecret(): boolean {
    if (!this.original.secretRef || this.keyInput.trim().length > 0 || this.clearSecret) {
      return false;
    }
    const prevHost = extractUrlHost(this.original.baseUrl);
    const nextHost = extractUrlHost(this.endpoint);
    if (prevHost && nextHost && prevHost !== nextHost) {
      throw new Error('修改服务器域名后请重新填写 API 密钥，或点击「移除已存密钥」后再保存');
    }
    return true;
  }

  private defaultChatPath(): string {
    if (this.family === 'openai-responses') return '/responses';
    if (this.family === 'anthropic') return '/messages';
    if (this.family === 'gemini' || this.family === 'vertex') return '/models/{model}:streamGenerateContent';
    return '/chat/completions';
  }

  private requestUrlPreview(): string {
    const base = this.endpoint.trim().replace(/\/+$/, '');
    if (!base) return '';
    if (this.family === 'gemini' || this.family === 'vertex') {
      const m = this.modelId.trim() || '{model}';
      return `${base}/models/${m}:streamGenerateContent?alt=sse`;
    }
    const custom = this.chatPath.trim();
    const path = custom ? (custom.startsWith('/') ? custom : '/' + custom) : this.defaultChatPath();
    return `${base}${path}`;
  }

  private familyLabel(f: ApiFamily): string {
    if (f === 'openai') return 'OpenAI Chat';
    if (f === 'openai-responses') return 'OpenAI Responses';
    if (f === 'anthropic') return 'Anthropic Messages';
    if (f === 'gemini') return 'Google Gemini';
    return 'Google Vertex AI';
  }

  private familyFromIndex(i: number): ApiFamily {
    if (i === 0) return 'openai';
    if (i === 1) return 'openai-responses';
    if (i === 2) return 'anthropic';
    if (i === 3) return 'gemini';
    return 'vertex';
  }

  private strategyLabel(s: KeyRotationStrategy): string {
    if (s === 'priority') return '优先级';
    if (s === 'least_used') return '最少使用';
    if (s === 'random') return '随机';
    return '轮询';
  }

  private async formProvider(): Promise<Provider> {
    if (!this.labelText.trim()) throw new Error('请填写服务商名称');
    const cleanBody = this.customBodyJson.trim();
    if (cleanBody.length > 0) {
      try {
        const parsed = JSON.parse(cleanBody) as Object;
        if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
          throw new Error('自定义 JSON 请求体必须是 JSON 对象，例如 {"seed": 42}');
        }
      } catch (err) {
        throw new Error('自定义 JSON 请求体格式无效，请检查语法');
      }
    }
    const headersToSave = this.customHeaders.slice();
    if (this.newHeaderKey.trim()) {
      headersToSave.push({ key: this.newHeaderKey.trim(), value: this.newHeaderVal });
      this.customHeaders = headersToSave;
      this.newHeaderKey = '';
      this.newHeaderVal = '';
    }
    let passRef = this.existingProxyPassRef;
    if (this.proxyPass.trim()) {
      passRef = newId();
      await storeKey(passRef, this.proxyPass.trim());
    }
    const proxyCfg: ProxyConfig | undefined = this.proxyHost.trim() ? {
      enabled: this.proxyEnabled,
      host: this.proxyHost.trim(),
      port: Number(this.proxyPortText) || 7890,
      username: this.proxyUser.trim() || undefined,
      passwordRef: passRef || undefined
    } : undefined;

    const models = this.savedModels.slice();
    if (this.modelId.trim() && !models.some((m: ModelSpec): boolean => m.id === this.modelId.trim())) {
      models.unshift(defaultModelSpec(this.modelId.trim()));
    }
    return {
      id: this.selectedId,
      name: this.labelText.trim(),
      family: this.family,
      baseUrl: checkEndpoint(this.endpoint),
      chatPath: this.chatPath.trim(),
      model: this.modelId.trim(),
      secretRef: this.original.secretRef,
      models,
      apiKeys: this.extraKeys.slice(),
      keyStrategy: this.keyStrategy,
      groupName: this.groupName.trim(),
      proxy: proxyCfg,
      customHeaders: headersToSave,
      customBodyJson: cleanBody,
      promptCaching: this.promptCaching,
      sendConversationCacheKey: this.sendConvCacheKey,
      balanceUrl: this.balanceUrl.trim(),
      lastBalance: this.balanceResult,
      builtinSearch: this.builtinSearch,
      builtinUrlContext: this.builtinUrlContext,
      builtinCodeExec: this.builtinCodeExec,
      oauth: this.original.oauth,
      enabled: this.provEnabled
    };
  }

  private async addExtraKey(): Promise<void> {
    if (!this.extraKeySecret.trim()) return;
    const ref = newId();
    await storeKey(ref, this.extraKeySecret.trim());
    const item: ApiKeyEntry = {
      id: newId(),
      label: this.extraKeyLabel.trim() || ('Key ' + (this.extraKeys.length + 1)),
      secretRef: ref,
      priority: this.extraKeys.length,
      usageCount: 0,
      errorCount: 0,
      disabledUntil: 0
    };
    this.extraKeys = [...this.extraKeys, item];
    this.extraKeyLabel = '';
    this.extraKeySecret = '';
  }

  private async removeExtraKey(item: ApiKeyEntry): Promise<void> {
    await forgetKey(item.secretRef).catch(() => {});
    this.extraKeys = this.extraKeys.filter((k: ApiKeyEntry): boolean => k.id !== item.id);
  }

  private resetKeyCooldowns(): void {
    this.extraKeys = this.extraKeys.map((k: ApiKeyEntry): ApiKeyEntry => {
      return {
        id: k.id,
        label: k.label,
        secretRef: k.secretRef,
        priority: k.priority,
        usageCount: k.usageCount,
        errorCount: 0,
        disabledUntil: 0
      };
    });
    this.notice = '已重置备用密钥冷却状态';
  }

  private toggleSavedModel(id: string): void {
    if (this.savedModels.some((m: ModelSpec): boolean => m.id === id)) {
      this.savedModels = this.savedModels.filter((m: ModelSpec): boolean => m.id !== id);
    } else {
      this.savedModels = [...this.savedModels, defaultModelSpec(id)];
      if (!this.modelId) this.modelId = id;
    }
  }

  private toggleModelCap(idx: number, cap: 'vision' | 'tools' | 'reasoning' | 'imageGen'): void {
    const next = this.savedModels.slice();
    const cur = next[idx];
    if (!cur) return;
    next[idx] = {
      id: cur.id,
      displayName: cur.displayName,
      groupName: cur.groupName,
      vision: cap === 'vision' ? !cur.vision : cur.vision,
      tools: cap === 'tools' ? !cur.tools : cur.tools,
      reasoning: cap === 'reasoning' ? !cur.reasoning : cur.reasoning,
      imageGen: cap === 'imageGen' ? !cur.imageGen : cur.imageGen,
      contextWindow: cur.contextWindow,
      maxOutputTokens: cur.maxOutputTokens,
      enabled: cur.enabled
    };
    this.savedModels = next;
  }

  private async probeOllama(): Promise<void> {
    if (!this.modelId.trim() || this.busy) return;
    this.busy = true;
    try {
      const spec = await fetchOllamaCapabilities(this.endpoint, this.modelId.trim());
      const rest = this.savedModels.filter((m: ModelSpec): boolean => m.id !== spec.id);
      this.savedModels = [spec, ...rest];
      this.notice = 'Ollama 探测完成: ' + (spec.vision ? '视觉 ' : '') + (spec.tools ? '工具 ' : '') + (spec.reasoning ? '推理' : '');
    } catch (e) {
      this.notice = (e as Error).message || '探测失败';
    } finally {
      this.busy = false;
    }
  }

  private async queryBalance(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    try {
      const form = await this.formProvider();
      const key = this.reuseSecret() ? await readKey(this.original.secretRef) : this.keyInput.trim();
      const pass = this.proxyPass.trim() || (this.existingProxyPassRef ? await readKey(this.existingProxyPassRef) : '');
      this.balanceResult = await fetchProviderBalance(form, key, pass);
      this.notice = '余额已更新: ' + this.balanceResult;
    } catch (e) {
      this.notice = (e as Error).message || '余额查询失败';
    } finally {
      this.busy = false;
    }
  }

  private async pasteImportFromClipboard(): Promise<void> {
    try {
      const data = await pasteboard.getSystemPasteboard().getData();
      const txt = (data.getPrimaryText() || '').trim();
      if (!txt) {
        this.importError = '剪贴板为空';
        return;
      }
      this.importText = txt;
      this.importError = '';
    } catch (_) {
      this.importError = '读取剪贴板失败，请长按输入框手动粘贴';
    }
  }

  async importProvider(scan: boolean, rawText?: string): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    this.importError = '';
    try {
      let link = rawText !== undefined ? rawText : this.linkInput;
      if (scan) {
        const result = await scanBarcode.startScanForResult(this.getUIContext().getHostContext() as common.UIAbilityContext,
          { scanTypes: [scanCore.ScanType.QR_CODE], enableAlbum: true });
        link = result.originalValue;
      }
      const imported = fromProviderText(link, (): string => newId());
      const updated = await this.onImportProviders(imported);
      this.localProviders = updated.slice();
      if (imported.length > 0 && imported[0].key.trim().length > 0) {
        this.localActiveId = imported[0].provider.id;
      }
      this.showImportSheet = false;
      this.importText = '';
      this.importError = '';
      this.linkInput = '';
      this.moreOptions = false;
      this.activeTab = 0;
      if (this.viewMode !== 'list') {
        this.setViewMode('list');
      }
      this.notice = `已导入 ${imported.length} 个供应商并保存`;
    } catch (e) {
      const msg = (e as Error).message || '读取配置码失败';
      this.importError = msg;
      this.notice = msg;
    } finally {
      this.busy = false;
    }
  }

  async showCode(): Promise<void> {
    if (this.shareCode) { this.shareCode = ''; return; }
    this.busy = true;
    try {
      const form = await this.formProvider();
      const key = this.reuseSecret() ? await readKey(this.original.secretRef) : this.keyInput.trim();
      this.shareCode = toProviderLink(form, key);
    } catch (e) { this.notice = (e as Error).message || '无法生成配置码'; }
    finally { this.busy = false; }
  }

  async requestList(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    this.notice = '';
    try {
      const form = await this.formProvider();
      const key = this.reuseSecret() ? await readKey(this.original.secretRef) : this.keyInput.trim();
      const pass = this.proxyPass.trim() || (this.existingProxyPassRef ? await readKey(this.existingProxyPassRef) : '');
      this.modelChoices = await fetchModels(form, key, pass);
      this.notice = this.modelChoices.length ? '已获取 ' + this.modelChoices.length + ' 个模型' : '列表为空，可手动填写模型 ID';
    } catch (e) { this.notice = (e as Error).message || '无法获取模型列表'; }
    finally { this.busy = false; }
  }

  async testHealth(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    this.healthResult = '正在检测连通性...';
    this.notice = '';
    try {
      const form = await this.formProvider();
      const reuse = this.reuseSecret();
      const key = reuse ? await readKey(this.original.secretRef) : this.keyInput.trim();
      const pass = this.proxyPass.trim() || (this.existingProxyPassRef ? await readKey(this.existingProxyPassRef) : '');
      const ms = await checkProviderHealth(form, key, form.model, pass);
      this.healthResult = `连接正常 · ${ms}ms`;
      this.notice = this.healthResult;
    } catch (e) {
      const msg = (e as Error).message || '连通性测试失败';
      this.healthResult = `失败: ${msg}`;
      this.notice = this.healthResult;
    } finally {
      this.busy = false;
    }
  }

  async submitForm(setActive: boolean = false): Promise<boolean> {
    if (this.busy) return false;
    this.busy = true;
    this.notice = '';
    try {
      const form = await this.formProvider();
      const reuse = this.reuseSecret();
      const updated = await this.onApply(form, this.keyInput.trim(), reuse, setActive);
      this.localProviders = updated.slice();
      if (setActive) {
        this.localActiveId = form.id;
      }
      this.keyInput = '';
      this.notice = `已保存 ${form.name}`;
      return true;
    } catch (e) {
      this.notice = (e as Error).message || '保存失败';
      return false;
    } finally {
      this.busy = false;
    }
  }

  private filteredProviders(): Provider[] {
    const q = this.listQuery.trim().toLowerCase();
    const matched = this.localProviders.filter((p: Provider): boolean => {
      if (this.onlyEnabledFilter && (p.enabled === false || !isProviderConfigured(p))) {
        return false;
      }
      if (q.length === 0) return true;
      return (
        p.name.toLowerCase().indexOf(q) >= 0 ||
        p.family.toLowerCase().indexOf(q) >= 0 ||
        (p.groupName || '').toLowerCase().indexOf(q) >= 0 ||
        (p.model || '').toLowerCase().indexOf(q) >= 0
      );
    });
    const activeConfigured: Provider[] = [];
    const otherConfigured: Provider[] = [];
    const unconfigured: Provider[] = [];
    for (let i = 0; i < matched.length; i++) {
      const p = matched[i];
      if (p.id === this.localActiveId && isProviderConfigured(p)) {
        activeConfigured.push(p);
      } else if (isProviderConfigured(p)) {
        otherConfigured.push(p);
      } else {
        unconfigured.push(p);
      }
    }
    return [...activeConfigured, ...otherConfigured, ...unconfigured];
  }

  private providerModelCount(p: Provider): number {
    if (p.models && p.models.length > 0) return p.models.length;
    return p.model ? 1 : 0;
  }

  @Builder
  caption(name: string) {
    Text(name).fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.muted'))
  }

  private setViewMode(mode: 'list' | 'detail'): void {
    SystemMotion.springAnimate(this.getUIContext(), this.reduceMotion, () => {
      this.viewMode = mode;
    });
  }

  private setActiveTab(tab: number): void {
    SystemMotion.quickAnimate(this.getUIContext(), this.reduceMotion, () => {
      this.activeTab = tab;
    });
  }

  private canDeleteSelected(): boolean {
    return this.localProviders.length > 1 && this.localProviders.some((p: Provider): boolean => p.id === this.selectedId);
  }

  @Builder
  private navTitleBar() {
    if (this.viewMode === 'detail') {
      KelivoNavTitleBar({
        titleText: this.selectedId ? (this.labelText || '编辑服务商') : '新增服务商',
        subtitleText: this.familyLabel(this.family),
        showBack: true,
        rightText: this.busy ? '保存中' : '保存',
        rightPrimary: true,
        secondSymbol: this.canDeleteSelected() ? $r('sys.symbol.trash') : undefined,
        onBack: () => { this.setViewMode('list'); },
        onSecondAction: () => {
          if (this.canDeleteSelected()) {
            this.onDeleteProvider(this.selectedId).then((updated: Provider[]) => {
              this.localProviders = updated.slice();
              this.setViewMode('list');
            });
          }
        },
        onRightAction: () => {
          this.submitForm(false).then((ok: boolean) => {
            if (ok) {
              this.setViewMode('list');
            }
          });
        }
      })
    } else {
      KelivoNavTitleBar({
        titleText: '供应商',
        subtitleText: '',
        showBack: true,
        thirdSymbol: this.onlyEnabledFilter ? $r('sys.symbol.checkmark_circle_fill') : $r('sys.symbol.checkmark_circle'),
        secondSymbol: $r('sys.symbol.cloud'),
        rightSymbol: $r('sys.symbol.plus'),
        onBack: () => { this.onClose(); },
        onThirdAction: () => {
          this.onlyEnabledFilter = !this.onlyEnabledFilter;
        },
        onSecondAction: () => {
          this.importError = '';
          this.showImportSheet = true;
        },
        onRightAction: () => {
          this.selectProvider(preset(newId(), '', 'openai', '', ''));
          this.setViewMode('detail');
        }
      })
    }
  }

  @Builder
  private listView() {
    Column() {
      Scroll() {
        Column({ space: 10 }) {
          if (this.notice.length > 0) {
            Text(this.notice)
              .fontSize(12)
              .fontColor($r('app.color.accent'))
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .borderRadius(12)
              .backgroundColor($r('app.color.tint'))
              .width('100%')
          }

          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(16)
              .fontColor([$r('app.color.muted')])
            TextInput({ text: this.listQuery, placeholder: '搜索服务商或模型...' })
              .layoutWeight(1)
              .height(36)
              .padding(0)
              .fontSize(14)
              .backgroundColor(Color.Transparent)
              .onChange((v: string) => { this.listQuery = v; })
            if (this.listQuery.length > 0) {
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.xmark'))
                  .fontSize(12)
                  .fontColor([$r('app.color.muted')])
              }
              .width(24)
              .height(24)
              .padding(0)
              .backgroundColor(Color.Transparent)
              .onClick(() => { this.listQuery = ''; })
            }
          }
          .width('100%')
          .height(44)
          .padding({ left: 14, right: 12 })
          .borderRadius(22)
          .backgroundColor($r('app.color.surface'))

          Column() {
            ForEach(this.filteredProviders(), (p: Provider, idx: number) => {
              Column() {
                Row({ space: 12 }) {
                  KelivoAvatarBadge({
                    brandId: resolveBrandIconId(p.name, p.family),
                    avatarText: '',
                    fallbackLetter: p.name,
                    badgeSize: 38
                  })
                  Column({ space: 2 }) {
                    Row({ space: 6 }) {
                      Text(p.name)
                        .fontSize(15)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.ink'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      if (p.id === this.localActiveId) {
                        Text('当前')
                          .fontSize(10)
                          .fontColor($r('app.color.accent'))
                          .backgroundColor($r('app.color.tint'))
                          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                          .borderRadius(8)
                      }
                    }
                    Text(`${this.familyLabel(p.family)} · ${this.providerModelCount(p)} 个模型${p.secretRef ? ' · 已配密钥' : ''}`)
                      .fontSize(11)
                      .fontColor($r('app.color.muted'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)

                  KelivoStatusPill({ enabledState: p.enabled !== false })

                  SymbolGlyph($r('sys.symbol.chevron_right'))
                    .fontSize(15)
                    .fontColor([$r('app.color.muted')])
                }
                .width('100%')
                .padding({ left: 14, right: 14, top: 12, bottom: 12 })
                .onClick(() => {
                  this.selectProvider(p);
                  this.setViewMode('detail');
                })

                if (idx < this.filteredProviders().length - 1) {
                  Divider().color($r('app.color.line')).margin({ left: 64 })
                }
              }
              .width('100%')
            }, (p: Provider) => `${p.id}-${p.name}-${p.enabled !== false}-${p.model}-${p.models?.length || 0}-${p.secretRef ? 1 : 0}`)
          }
          .width('100%')
          .borderRadius(16)
          .backgroundColor($r('app.color.surface'))

          KelivoSectionHeader({ titleText: '快速导入', topSpacing: 4 })
          Row({ space: 8 }) {
            Button('导入配置码 / 扫码')
              .id('openImportProviderSheet')
              .type(ButtonType.Normal)
              .layoutWeight(1)
              .height(40)
              .fontSize(13)
              .borderRadius(12)
              .backgroundColor($r('app.color.surface'))
              .fontColor($r('app.color.ink'))
              .onClick(() => {
                this.importError = '';
                this.showImportSheet = true;
              })
            Button('OAuth 登录')
              .type(ButtonType.Normal)
              .layoutWeight(1)
              .height(40)
              .fontSize(13)
              .borderRadius(12)
              .backgroundColor($r('app.color.tint'))
              .fontColor($r('app.color.accent'))
              .onClick(() => {
                this.setViewMode('detail');
                this.activeTab = 2;
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 56 + this.winTopInset + 4, bottom: Math.max(36, this.winBottomInset + 20) })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .transition(SystemMotion.subViewTransition(this.reduceMotion))
  }

  @Builder
  private detailView() {
    Column() {
      Row({ space: 6 }) {
        Button('配置').layoutWeight(1).height(34).fontSize(12).borderRadius(17)
          .backgroundColor(this.activeTab === 0 ? $r('app.color.accent') : $r('app.color.surface'))
          .fontColor(this.activeTab === 0 ? $r('app.color.on_accent') : $r('app.color.ink'))
          .onClick(() => { this.setActiveTab(0); })
        Button('模型').layoutWeight(1).height(34).fontSize(12).borderRadius(17)
          .backgroundColor(this.activeTab === 1 ? $r('app.color.accent') : $r('app.color.surface'))
          .fontColor(this.activeTab === 1 ? $r('app.color.on_accent') : $r('app.color.ink'))
          .onClick(() => { this.setActiveTab(1); })
        Button('高级与OAuth').layoutWeight(1).height(34).fontSize(12).borderRadius(17)
          .backgroundColor(this.activeTab === 2 ? $r('app.color.accent') : $r('app.color.surface'))
          .fontColor(this.activeTab === 2 ? $r('app.color.on_accent') : $r('app.color.ink'))
          .onClick(() => { this.setActiveTab(2); })
      }.padding({ left: 16, right: 16, top: 56 + this.winTopInset + 4, bottom: 8 }).width('100%')

      Scroll() {
        Column({ space: 10 }) {
          if (this.activeTab === 0) {
            Row({ space: 12 }) {
              KelivoAvatarBadge({
                brandId: resolveBrandIconId(this.labelText, this.family),
                avatarText: '',
                fallbackLetter: this.labelText || 'P',
                badgeSize: 40
              })
              Column({ space: 2 }) {
                Text('启用此服务商')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.ink'))
                Text('关闭后模型选择器将隐藏该服务商模型')
                  .fontSize(11)
                  .fontColor($r('app.color.muted'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.provEnabled })
                .onChange((v: boolean) => { this.provEnabled = v; })
                .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
            }
            .width('100%')
            .padding(12)
            .borderRadius(14)
            .backgroundColor($r('app.color.surface'))

            Row({ space: 8 }) {
              Column({ space: 4 }) {
                this.caption('名称')
                TextInput({ text: this.labelText, placeholder: '服务商名称' }).id('providerName')
                  .backgroundColor($r('app.color.surface'))
                  .onChange((v: string) => { this.labelText = v; })
              }.layoutWeight(2).alignItems(HorizontalAlign.Start)
              Column({ space: 4 }) {
                this.caption('分组')
                TextInput({ text: this.groupName, placeholder: '如 国内/海外' })
                  .backgroundColor($r('app.color.surface'))
                  .onChange((v: string) => { this.groupName = v; })
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            }.width('100%')

            this.caption('接口协议')
            Select([
              { value: 'OpenAI Chat' },
              { value: 'OpenAI Responses' },
              { value: 'Anthropic Messages' },
              { value: 'Google Gemini' },
              { value: 'Google Vertex AI' }
            ]).value(this.familyLabel(this.family))
              .onSelect((i: number) => { this.family = this.familyFromIndex(i); this.modelChoices = []; })
              .menuSystemMaterial(ImmersiveMaterialStyle.selectMenuMaterial(this.immersiveLightEnabled))
              .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))

            if (this.family === 'openai' || this.family === 'openai-responses') {
              Row() {
                Column({ space: 2 }) {
                  Text('Response API (/responses)').fontSize(14).fontColor($r('app.color.ink'))
                  Text('开启后改用 OpenAI Responses 协议端点').fontSize(11).fontColor($r('app.color.muted'))
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.family === 'openai-responses' })
                  .selectedColor($r('app.color.accent'))
                  .onChange((v: boolean) => {
                    this.family = v ? 'openai-responses' : 'openai';
                  })
                  .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .borderRadius(12)
              .backgroundColor($r('app.color.surface'))

              Row() {
                Column({ space: 2 }) {
                  Text('发送会话缓存键 (prompt_cache_key)').fontSize(14).fontColor($r('app.color.ink'))
                  Text('附带当前会话 ID，提高上下文缓存命中率').fontSize(11).fontColor($r('app.color.muted'))
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.sendConvCacheKey })
                  .selectedColor($r('app.color.accent'))
                  .onChange((v: boolean) => { this.sendConvCacheKey = v; })
                  .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .borderRadius(12)
              .backgroundColor($r('app.color.surface'))
            }

            this.caption('API 基础地址')
            TextInput({ text: this.endpoint, placeholder: 'https://example.com/v1' }).id('baseUrl')
              .backgroundColor($r('app.color.surface'))
              .onChange((v: string) => { this.endpoint = v; this.modelChoices = []; })
            if (this.requestUrlPreview()) {
              Text('Request URL: ' + this.requestUrlPreview())
                .fontSize(11)
                .fontColor($r('app.color.muted'))
                .copyOption(CopyOptions.LocalDevice)
            }

            if (this.family !== 'gemini' && this.family !== 'vertex') {
              this.caption('API Path（可留空使用默认路径）')
              TextInput({ text: this.chatPath, placeholder: this.defaultChatPath() })
                .backgroundColor($r('app.color.surface'))
                .onChange((v: string) => { this.chatPath = v; })
            }

            this.caption('主 API 密钥')
            TextInput({ text: this.keyInput, placeholder: this.original.secretRef && !this.clearSecret ? '已安全保存，输入可替换' : '输入密钥，本地服务可留空' })
              .id('apiKey').type(InputType.Password).backgroundColor($r('app.color.surface'))
              .onChange((v: string) => { this.keyInput = v; })
            if (this.original.secretRef) {
              Button(this.clearSecret ? '撤销移除密钥' : '移除已存密钥').backgroundColor(Color.Transparent)
                .fontColor($r('app.color.muted')).onClick(() => { this.clearSecret = !this.clearSecret; this.keyInput = ''; })
            }

            Row({ space: 8 }) {
              Button(this.busy ? '检测中…' : '连通性测试')
                .type(ButtonType.Normal)
                .height(36)
                .fontSize(13)
                .borderRadius(10)
                .backgroundColor($r('app.color.tint'))
                .fontColor($r('app.color.accent'))
                .layoutWeight(1)
                .onClick(() => { this.testHealth(); })
              Button(this.shareCode ? '收起分享码' : '分享配置码')
                .type(ButtonType.Normal)
                .height(36)
                .fontSize(13)
                .borderRadius(10)
                .backgroundColor($r('app.color.surface'))
                .fontColor($r('app.color.ink'))
                .layoutWeight(1)
                .onClick(() => { this.showCode(); })
            }.width('100%')

            if (this.healthResult) {
              Text(this.healthResult)
                .fontSize(12)
                .fontColor(this.healthResult.startsWith('失败') ? $r('app.color.warning') : $r('app.color.accent'))
            }
            if (this.shareCode) {
              Column({ space: 8 }) {
                QRCode(this.shareCode).width(168).height(168).padding(8).backgroundColor(Color.White)
                Text(this.shareCode).maxLines(2).fontSize(11).fontColor($r('app.color.muted')).copyOption(CopyOptions.LocalDevice)
              }
              .width('100%')
              .padding(10)
              .borderRadius(12)
              .backgroundColor($r('app.color.surface'))
              .alignItems(HorizontalAlign.Center)
            }
          } else if (this.activeTab === 1) {
            this.caption('当前使用模型 ID')
            TextInput({ text: this.modelId, placeholder: '输入服务商提供的模型 ID' }).id('modelId')
              .backgroundColor($r('app.color.surface'))
              .onChange((v: string) => { this.modelId = v; })
            Row({ space: 8 }) {
              Button('获取模型').id('fetchModels').backgroundColor($r('app.color.tint')).fontColor($r('app.color.accent'))
                .onClick(() => { this.requestList(); })
              if (this.endpoint.includes('11434') || this.labelText.toLowerCase().includes('ollama')) {
                Button('Ollama探测').backgroundColor($r('app.color.panel')).fontColor($r('app.color.ink'))
                  .onClick(() => { this.probeOllama(); })
              }
              if (this.modelChoices.length) {
                Select(this.modelChoices.map((model: string): SelectOption => { return { value: model }; }))
                  .value('选择模型').layoutWeight(1).onSelect((i: number) => {
                    this.modelId = this.modelChoices[i];
                    if (!this.savedModels.some((m: ModelSpec): boolean => m.id === this.modelId)) {
                      this.savedModels = [...this.savedModels, defaultModelSpec(this.modelId)];
                    }
                  })
                  .menuSystemMaterial(ImmersiveMaterialStyle.selectMenuMaterial(this.immersiveLightEnabled))
                  .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
              }
            }.width('100%')

            if (this.savedModels.length) {
              this.caption('已收录模型与能力标签（点击切换选中/能力）')
              ForEach(this.savedModels, (ms: ModelSpec, idx: number) => {
                Column({ space: 6 }) {
                  Row({ space: 6 }) {
                    KelivoAvatarBadge({
                      brandId: resolveBrandIconId(`${ms.id} ${this.labelText}`, this.family),
                      avatarText: '',
                      fallbackLetter: ms.id,
                      badgeSize: 22
                    })
                    Text(ms.id).fontSize(13).fontWeight(this.modelId === ms.id ? FontWeight.Bold : FontWeight.Normal)
                      .fontColor(this.modelId === ms.id ? $r('app.color.accent') : $r('app.color.ink')).layoutWeight(1)
                      .onClick(() => { this.modelId = ms.id; })
                    Button('移除').height(24).fontSize(11).backgroundColor(Color.Transparent).fontColor($r('app.color.warning'))
                      .onClick(() => { this.toggleSavedModel(ms.id); })
                  }.width('100%')
                  Row({ space: 6 }) {
                    Button('视觉').height(24).fontSize(11)
                      .backgroundColor(ms.vision ? $r('app.color.tint') : $r('app.color.panel'))
                      .fontColor(ms.vision ? $r('app.color.accent') : $r('app.color.muted'))
                      .onClick(() => this.toggleModelCap(idx, 'vision'))
                    Button('工具').height(24).fontSize(11)
                      .backgroundColor(ms.tools ? $r('app.color.tint') : $r('app.color.panel'))
                      .fontColor(ms.tools ? $r('app.color.accent') : $r('app.color.muted'))
                      .onClick(() => this.toggleModelCap(idx, 'tools'))
                    Button('推理').height(24).fontSize(11)
                      .backgroundColor(ms.reasoning ? $r('app.color.tint') : $r('app.color.panel'))
                      .fontColor(ms.reasoning ? $r('app.color.accent') : $r('app.color.muted'))
                      .onClick(() => this.toggleModelCap(idx, 'reasoning'))
                    Button('生图').height(24).fontSize(11)
                      .backgroundColor(ms.imageGen ? $r('app.color.tint') : $r('app.color.panel'))
                      .fontColor(ms.imageGen ? $r('app.color.accent') : $r('app.color.muted'))
                      .onClick(() => this.toggleModelCap(idx, 'imageGen'))
                  }
                }.width('100%').padding(10).borderRadius(12).backgroundColor($r('app.color.surface'))
              }, (ms: ModelSpec, idx: number) => ms.id + '-' + idx + '-' + ms.vision + '-' + ms.tools + '-' + ms.reasoning + '-' + ms.imageGen)
            }
          } else {
            this.caption('多 API Key 负载均衡池')
            Row({ space: 8 }) {
              Text('轮换策略').fontSize(13).fontColor($r('app.color.ink')).layoutWeight(1)
              Select([{ value: '轮询' }, { value: '优先级' }, { value: '最少使用' }, { value: '随机' }])
                .value(this.strategyLabel(this.keyStrategy))
                .onSelect((idx: number) => {
                  const arr: KeyRotationStrategy[] = ['round_robin', 'priority', 'least_used', 'random'];
                  this.keyStrategy = arr[idx] || 'round_robin';
                })
                .menuSystemMaterial(ImmersiveMaterialStyle.selectMenuMaterial(this.immersiveLightEnabled))
                .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
            }.width('100%')
            Row({ space: 6 }) {
              TextInput({ text: this.extraKeyLabel, placeholder: '备注名称' }).layoutWeight(1)
                .backgroundColor($r('app.color.surface'))
                .onChange((v: string) => { this.extraKeyLabel = v; })
              TextInput({ text: this.extraKeySecret, placeholder: '备用 API Key' }).type(InputType.Password).layoutWeight(2)
                .backgroundColor($r('app.color.surface'))
                .onChange((v: string) => { this.extraKeySecret = v; })
              Button('添加').height(36).backgroundColor($r('app.color.tint')).fontColor($r('app.color.accent'))
                .onClick(() => { this.addExtraKey(); })
            }.width('100%')
            ForEach(this.extraKeys, (ak: ApiKeyEntry) => {
              Row({ space: 8 }) {
                Column({ space: 2 }) {
                  Text(ak.label).fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink'))
                  Text('已用 ' + ak.usageCount + ' 次 · 错误 ' + ak.errorCount + (ak.disabledUntil > Date.now() ? ' · 冷却中' : ''))
                    .fontSize(11).fontColor($r('app.color.muted'))
                }.layoutWeight(1).alignItems(HorizontalAlign.Start)
                Button('删除').height(28).fontSize(11).backgroundColor(Color.Transparent).fontColor($r('app.color.warning'))
                  .onClick(() => { this.removeExtraKey(ak); })
              }.width('100%').padding(10).borderRadius(10).backgroundColor($r('app.color.surface'))
            }, (ak: ApiKeyEntry) => ak.id + '-' + ak.errorCount + '-' + ak.disabledUntil)
            if (this.extraKeys.length) {
              Button('重置异常冷却').height(30).fontSize(12).backgroundColor($r('app.color.panel')).fontColor($r('app.color.ink'))
                .onClick(() => this.resetKeyCooldowns())
            }

            Divider().color($r('app.color.line'))
            this.caption('HTTP 代理（按服务商独立生效）')
            Row() {
              Text('启用代理').fontSize(14).fontColor($r('app.color.ink')).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.proxyEnabled }).selectedColor($r('app.color.accent'))
                .onChange((v: boolean) => { this.proxyEnabled = v; })
                .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
            }.width('100%')
            if (this.proxyEnabled) {
              Row({ space: 8 }) {
                TextInput({ text: this.proxyHost, placeholder: '主机如 127.0.0.1' }).layoutWeight(2)
                  .backgroundColor($r('app.color.surface'))
                  .onChange((v: string) => { this.proxyHost = v; })
                TextInput({ text: this.proxyPortText, placeholder: '端口' }).type(InputType.Number).layoutWeight(1)
                  .backgroundColor($r('app.color.surface'))
                  .onChange((v: string) => { this.proxyPortText = v; })
              }.width('100%')
              Row({ space: 8 }) {
                TextInput({ text: this.proxyUser, placeholder: '用户名（可选）' }).layoutWeight(1)
                  .backgroundColor($r('app.color.surface'))
                  .onChange((v: string) => { this.proxyUser = v; })
                TextInput({ text: this.proxyPass, placeholder: '密码（可选）' }).type(InputType.Password).layoutWeight(1)
                  .backgroundColor($r('app.color.surface'))
                  .onChange((v: string) => { this.proxyPass = v; })
              }.width('100%')
            }

            Divider().color($r('app.color.line'))
            this.caption('供应商内置功能与自定义请求')
            Row() {
              Text('Claude 提示词缓存').fontSize(13).fontColor($r('app.color.ink')).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.promptCaching }).selectedColor($r('app.color.accent'))
                .onChange((v: boolean) => { this.promptCaching = v; })
                .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
            }.width('100%')
            Row() {
              Text('内置联网搜索（Gemini/Responses）').fontSize(13).fontColor($r('app.color.ink')).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.builtinSearch }).selectedColor($r('app.color.accent'))
                .onChange((v: boolean) => { this.builtinSearch = v; })
                .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
            }.width('100%')
            Row() {
              Text('内置 URL 上下文（Gemini）').fontSize(13).fontColor($r('app.color.ink')).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.builtinUrlContext }).selectedColor($r('app.color.accent'))
                .onChange((v: boolean) => { this.builtinUrlContext = v; })
                .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
            }.width('100%')
            Row() {
              Text('内置代码执行（Gemini）').fontSize(13).fontColor($r('app.color.ink')).layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.builtinCodeExec }).selectedColor($r('app.color.accent'))
                .onChange((v: boolean) => { this.builtinCodeExec = v; })
                .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
            }.width('100%')

            Row({ space: 6 }) {
              TextInput({ text: this.newHeaderKey, placeholder: 'Header 名' }).layoutWeight(1)
                .backgroundColor($r('app.color.surface'))
                .onChange((v: string) => { this.newHeaderKey = v; })
              TextInput({ text: this.newHeaderVal, placeholder: 'Header 值' }).layoutWeight(1)
                .backgroundColor($r('app.color.surface'))
                .onChange((v: string) => { this.newHeaderVal = v; })
              Button('+').height(36).backgroundColor($r('app.color.tint')).fontColor($r('app.color.accent'))
                .onClick(() => {
                  if (this.newHeaderKey.trim()) {
                    this.customHeaders = [...this.customHeaders, { key: this.newHeaderKey.trim(), value: this.newHeaderVal }];
                    this.newHeaderKey = ''; this.newHeaderVal = '';
                  }
                })
            }.width('100%')
            ForEach(this.customHeaders, (hd: HeaderEntry, hi: number) => {
              Row() {
                Text(hd.key + ': ' + hd.value).fontSize(12).fontColor($r('app.color.muted')).layoutWeight(1)
                Button('删').height(24).fontSize(11).backgroundColor(Color.Transparent).fontColor($r('app.color.warning'))
                  .onClick(() => { this.customHeaders = this.customHeaders.filter((_h: HeaderEntry, idx: number): boolean => idx !== hi); })
              }.width('100%')
            }, (hd: HeaderEntry, hi: number) => hi + hd.key)

            TextArea({ text: this.customBodyJson, placeholder: '自定义 JSON 请求体覆写（例如 {"seed": 42}）' })
              .height(72).backgroundColor($r('app.color.surface')).onChange((v: string) => { this.customBodyJson = v; })

            Row({ space: 8 }) {
              TextInput({ text: this.balanceUrl, placeholder: '余额查询地址（DeepSeek/SiliconFlow/OpenRouter 可留空）' })
                .layoutWeight(1).backgroundColor($r('app.color.surface')).onChange((v: string) => { this.balanceUrl = v; })
              Button('查余额').height(36).backgroundColor($r('app.color.tint')).fontColor($r('app.color.accent'))
                .onClick(() => { this.queryBalance(); })
            }.width('100%')
            if (this.balanceResult) {
              Text('最近查询: ' + this.balanceResult).fontSize(12).fontColor($r('app.color.accent'))
            }

            Divider().color($r('app.color.line'))
            this.caption('订阅账号登录（OAuth）')
            Row({ space: 6 }) {
              ForEach(['chatgpt', 'grok', 'kimi', 'claude'] as OAuthProviderKind[], (okind: OAuthProviderKind) => {
                Button(okind.toUpperCase()).layoutWeight(1).height(34).fontSize(11)
                  .backgroundColor($r('app.color.tint')).fontColor($r('app.color.accent'))
                  .onClick(() => this.onStartOAuth(okind))
              }, (okind: OAuthProviderKind) => okind)
            }.width('100%')

            Button(this.moreOptions ? '收起配置码' : '导入或分享 Kelivo 配置码').backgroundColor(Color.Transparent)
              .fontSize(14).fontColor($r('app.color.accent')).onClick(() => {
                this.moreOptions = !this.moreOptions; this.shareCode = ''; this.linkInput = '';
              })
            if (this.moreOptions) {
              TextInput({ text: this.linkInput, placeholder: '粘贴 ai-provider:v1: 配置码或 ChatBox JSON' })
                .backgroundColor($r('app.color.surface'))
                .onChange((v: string) => { this.linkInput = v; })
              Row({ space: 8 }) {
                Button('读取并导入').enabled(!!this.linkInput.trim()).onClick(() => { this.importProvider(false); })
                Button('扫码导入').onClick(() => { this.importProvider(true); })
              }
              Button(this.shareCode ? '隐藏分享码' : '显示分享码（含密钥）').fontSize(14)
                .backgroundColor($r('app.color.panel')).fontColor($r('app.color.ink')).onClick(() => { this.showCode(); })
              if (this.shareCode) {
                QRCode(this.shareCode).width(180).height(180).padding(8).backgroundColor(Color.White)
                Text(this.shareCode).maxLines(2).fontSize(12).fontColor($r('app.color.muted')).copyOption(CopyOptions.LocalDevice)
              }
            }
          }

          if (this.notice) { Text(this.notice).fontSize(13).fontColor($r('app.color.accent')) }
          Button(this.busy ? '处理中…' : '保存并使用').id('saveProvider').width('100%')
            .height(44).borderRadius(14)
            .margin({ top: 10, bottom: 18 }).backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
            .onClick(() => {
              this.submitForm(true).then((ok: boolean) => {
                if (ok) {
                  this.setViewMode('list');
                }
              });
            })
        }.width('100%').constraintSize({ maxWidth: 620 }).padding({ left: 16, right: 16, bottom: Math.max(36, this.winBottomInset + 20) })
          .alignItems(HorizontalAlign.Start).enabled(!this.busy)
      }.layoutWeight(1).width('100%').align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .enabled(!this.busy)
    .transition(SystemMotion.subViewTransition(this.reduceMotion))
  }

  @Builder
  private importProviderSheet() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Capsule }) {
          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.camera'))
              .fontSize(15)
              .fontColor([$r('app.color.ink')])
            Text('扫码导入')
              .fontSize(13)
              .fontColor($r('app.color.ink'))
          }
        }
        .height(36)
        .padding({ left: 14, right: 14 })
        .backgroundColor($r('app.color.panel'))
        .onClick(() => {
          this.importProvider(true);
        })

        PasteButton({
          icon: PasteIconStyle.LINES,
          text: PasteDescription.PASTE,
          buttonType: ButtonType.Capsule
        })
          .height(36)
          .onClick((_event: ClickEvent, result: PasteButtonOnClickResult) => {
            if (result === PasteButtonOnClickResult.SUCCESS) {
              this.pasteImportFromClipboard().catch(() => {});
            } else {
              this.importError = '读取剪贴板失败，请长按输入框手动粘贴';
            }
          })

        Blank()
      }
      .width('100%')

      TextArea({
        text: this.importText,
        placeholder: '粘贴分享字符串（可多行，每行一个 ai-provider:v1:...）或 ChatBox JSON'
      })
        .id('importProviderInput')
        .width('100%')
        .height(150)
        .fontSize(13)
        .borderRadius(12)
        .backgroundColor($r('app.color.panel'))
        .onChange((v: string) => {
          this.importText = v;
          if (this.importError.length > 0) {
            this.importError = '';
          }
        })

      if (this.importError.length > 0) {
        Text(this.importError)
          .fontSize(12)
          .fontColor($r('app.color.warning'))
          .width('100%')
      }

      Row({ space: 10 }) {
        Button('取消')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .borderRadius(12)
          .backgroundColor($r('app.color.panel'))
          .fontColor($r('app.color.ink'))
          .onClick(() => {
            this.showImportSheet = false;
          })

        Button(this.busy ? '导入中…' : '导入')
          .id('confirmImportProvider')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(42)
          .fontSize(14)
          .borderRadius(12)
          .backgroundColor($r('app.color.accent'))
          .fontColor($r('app.color.on_accent'))
          .enabled(!this.busy && this.importText.trim().length > 0)
          .onClick(() => {
            this.importProvider(false, this.importText);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 24 })
  }

  build() {
    NavDestination() {
      Column() {
        if (this.viewMode === 'detail') {
          this.detailView()
        } else {
          this.listView()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
      .bindSheet(
        $$this.showImportSheet,
        this.importProviderSheet(),
        ImmersiveMaterialStyle.sheetOptions(
          this.immersiveLightEnabled,
          this.themeSurfaceHex,
          '导入供应商',
          () => { this.showImportSheet = false; },
          true
        )
      )
    }
    .hideBackButton(true)
    .backgroundColor(this.themeCanvasHex)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .title(
      { builder: () => this.navTitleBar(), height: 56 + this.winTopInset },
      ImmersiveMaterialStyle.titleBarOptions(this.immersiveLightEnabled, this.viewMode === 'list')
    )
    .systemTransition(SystemMotion.navTransition(this.reduceMotion))
    .onBackPressed(() => {
      if (this.onDismissOverlay()) {
        return true;
      }
      if (this.viewMode === 'detail') {
        this.setViewMode('list');
        return true;
      }
      return false;
    })
  }
}
