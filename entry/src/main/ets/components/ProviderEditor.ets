import { scanBarcode, scanCore } from '@kit.ScanKit';
import { common } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { resolveBrandIconId } from '../core/BrandIcons';
import { ImportedProvider, fromProviderText, toProviderLink } from '../core/ProviderLink';
import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { SystemMotion } from '../core/SystemMotion';
import {
  ApiFamily,
  CHATGPT_PLAN_API,
  CHATGPT_PLAN_PREFIX,
  planClientId,
  ModelDefaults,
  ModelModality,
  ModelOutputModality,
  ModelSpec,
  OPENCODE_GO_OAUTH_PREFIX,
  Provider,
  checkEndpoint,
  cloneModelSpec,
  cloneProvider,
  defaultModelSpec,
  extractUrlHost,
  isOpenCodeGoEndpoint,
  isProviderConfigured,
  openCodeGoPreset,
  openCodeGoSessionId,
  preset
} from '../core/Models';
import { checkProviderHealth, fetchModels, fetchOllamaCapabilities, fetchProviderBalance, providerBalanceUrl } from '../core/ChatClient';
import { newId, readKey } from '../core/Storage';
import { AddProviderSheet } from './AddProviderSheet';
import { ChatGptPlanLogin } from './ChatGptPlanLogin';
import { PlanSession } from '../core/ChatGptSession';
import { OpenCodeGoPlanLogin } from './OpenCodeGoPlanLogin';
import { OpenCodeGoSession } from '../core/OpenCodeGoSession';
import { OpenCodeGoQuota } from './OpenCodeGoQuota';
import { KelivoAvatarBadge, KelivoNavTitleBar, KelivoSectionHeader, KelivoStatusPill } from './KelivoChrome';

@Component
export struct ProviderEditor {
  @Prop @Watch('onProvidersPropChange') providers: Provider[] = [];
  @Prop @Watch('onProvidersPropChange') activeId: string = '';
  pageMode: 'list' | 'detail' = 'list';
  initialProviderId: string = '';
  @Prop modelDefaults: ModelDefaults = {
    chatProviderId: '', chatModelId: '', titleProviderId: '', titleModelId: '',
    translateProviderId: '', translateModelId: '', ocrProviderId: '', ocrModelId: '',
    memoryProviderId: '', memoryModelId: ''
  };
  onApply: (provider: Provider, key: string, reuseKey: boolean, setActive: boolean) => Promise<Provider[]> = async () => [];
  onImportProviders: (items: ImportedProvider[]) => Promise<Provider[]> = async () => [];
  onDeleteProvider: (id: string) => Promise<Provider[]> = async () => [];
  onOpenDetail: (providerId: string) => void = () => {};
  onOpenModelEditor: (
    provider: Provider,
    spec: ModelSpec,
    isNew: boolean,
    onSaved: (spec: ModelSpec) => void
  ) => void = () => {};
  onDismissOverlay: () => boolean = () => false;
  onRouteShown: () => void = () => {};
  onRouteHidden: () => void = () => {};
  onClose: () => void = () => {};

  @State modelsRev: number = 0;
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
  @State showAddSheet: boolean = false;
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
  @State sendConvCacheKey: boolean = false;
  @State balanceResult: string = '';
  @State healthResult: string = '';
  @State activeTab: 'config' | 'models' = 'config';
  @State shareCode: string = '';
  @State notice: string = '';
  @State busy: boolean = false;
  @State clearSecret: boolean = false;
  private original: Provider = preset('', '', 'openai', '', '');
  private detailScroller: Scroller = new Scroller();

  private onProvidersPropChange(): void {
    this.localProviders = this.providers.slice();
    this.localActiveId = this.activeId;
  }

  aboutToAppear(): void {
    this.localProviders = this.providers.slice();
    this.localActiveId = this.activeId;
    if (this.pageMode === 'detail') {
      if (this.initialProviderId.length > 0) {
        const target = this.localProviders.find((p: Provider): boolean => p.id === this.initialProviderId) ||
          this.localProviders.find((p: Provider): boolean => p.id === this.localActiveId) ||
          this.localProviders[0];
        if (target) {
          this.selectProvider(target);
        } else {
          this.selectProvider(preset(newId(), '', 'openai', '', ''));
        }
      } else {
        this.selectProvider(preset(newId(), '', 'openai', '', ''));
      }
    }
  }

  selectProvider(provider: Provider): void {
    this.original = provider;
    this.shareCode = '';
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
    this.savedModels = provider.models
      ? provider.models.map((m: ModelSpec): ModelSpec => cloneModelSpec(m))
      : (provider.model ? [defaultModelSpec(provider.model)] : []);
    this.sendConvCacheKey = provider.sendConversationCacheKey === true;
    this.balanceResult = provider.lastBalance || '';
    this.notice = '';
  }

  private async connectChatGpt(session: PlanSession): Promise<Provider> {
    const id = CHATGPT_PLAN_PREFIX + session.clientId;
    const previous = this.localProviders.find((p: Provider): boolean => p.id === id);
    const provider = previous ? cloneProvider(previous) : preset(id, 'ChatGPT 订阅', 'openai-responses', CHATGPT_PLAN_API, '');
    provider.oauth = { kind: 'chatgpt', accountEmail: session.email || session.subject, accessTokenRef: '',
      refreshTokenRef: '', expiresAt: session.expires, quotaSummary: '' };
    let modelNotice = '';
    try {
      const list = await fetchModels(provider, '');
      if (!list.includes(provider.model)) provider.model = list[0] || '';
      provider.models = list.map((mid: string): ModelSpec =>
        provider.models?.find((m: ModelSpec): boolean => m.id === mid) || defaultModelSpec(mid));
      if (!list.length) modelNotice = '账号没有返回可用模型';
    } catch (_) { modelNotice = '可在「模型」中重试获取账号模型'; }
    const updated = await this.onApply(provider, '', false, true);
    this.localProviders = updated.slice();
    this.localActiveId = provider.id;
    if (this.pageMode === 'detail') {
      this.selectProvider(provider);
      this.notice = modelNotice || '已选用 ChatGPT 订阅';
    }
    return provider;
  }

  private async connectOpenCodeGo(session: OpenCodeGoSession): Promise<Provider> {
    const id = OPENCODE_GO_OAUTH_PREFIX + session.sessionId;
    const previous = this.localProviders.find((p: Provider): boolean => p.id === id);
    const provider = previous ? cloneProvider(previous) : openCodeGoPreset(id);
    if (!previous && session.orgName) {
      provider.name = 'OpenCode Go · ' + session.orgName;
    }
    provider.oauth = {
      kind: 'opencode-go',
      accountEmail: session.email || session.orgName || session.accountId || 'OpenCode Go',
      accessTokenRef: '',
      refreshTokenRef: '',
      expiresAt: session.expires,
      quotaSummary: session.orgName || ''
    };
    let modelNotice = '';
    try {
      const list = await fetchModels(provider, '');
      if (!list.includes(provider.model)) provider.model = list[0] || '';
      provider.models = list.map((mid: string): ModelSpec =>
        provider.models?.find((m: ModelSpec): boolean => m.id === mid) || defaultModelSpec(mid));
      if (!list.length) modelNotice = '账号没有返回可用模型';
    } catch (_) { modelNotice = '可在「模型」中重试获取账号模型'; }
    const updated = await this.onApply(provider, '', false, true);
    this.localProviders = updated.slice();
    this.localActiveId = provider.id;
    if (this.pageMode === 'detail') {
      this.selectProvider(provider);
      this.notice = modelNotice || '已连接 OpenCode Go 账号';
    }
    return provider;
  }

  private async createProviderFromSheet(provider: Provider, apiKey: string): Promise<void> {
    const updated = await this.onApply(provider, apiKey, false, false);
    this.localProviders = updated.slice();
    this.notice = `已添加 ${provider.name}`;
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

  private formProvider(): Provider {
    if (!this.labelText.trim()) throw new Error('请填写服务商名称');
    const models = this.savedModels.map((m: ModelSpec): ModelSpec => cloneModelSpec(m));
    if (this.modelId.trim() && !models.some((m: ModelSpec): boolean => m.id === this.modelId.trim())) {
      models.unshift(defaultModelSpec(this.modelId.trim()));
    }
    const provider = cloneProvider(this.original);
    provider.name = this.labelText.trim();
    provider.family = this.family;
    provider.baseUrl = checkEndpoint(this.endpoint);
    provider.chatPath = this.chatPath.trim();
    provider.model = this.modelId.trim();
    provider.models = models;
    provider.groupName = this.groupName.trim();
    provider.sendConversationCacheKey = this.sendConvCacheKey;
    provider.lastBalance = this.balanceResult;
    provider.enabled = this.provEnabled;
    return provider;
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
    const cloned = cloneModelSpec(cur);
    if (cap === 'vision') {
      cloned.vision = !cloned.vision;
      const baseIn: ModelModality[] = cloned.inputModalities && cloned.inputModalities.length > 0
        ? cloned.inputModalities.slice()
        : (cur.vision ? ['text', 'image'] : ['text']);
      if (cloned.vision) {
        if (!baseIn.includes('image')) {
          baseIn.push('image');
        }
        cloned.inputModalities = baseIn;
      } else {
        const filtered = baseIn.filter((m: ModelModality): boolean => m !== 'image');
        cloned.inputModalities = filtered.length > 0 ? filtered : ['text'];
      }
    } else if (cap === 'tools') {
      cloned.tools = !cloned.tools;
    } else if (cap === 'reasoning') {
      cloned.reasoning = !cloned.reasoning;
    } else if (cap === 'imageGen') {
      cloned.imageGen = !cloned.imageGen;
      const baseOut: ModelOutputModality[] = cloned.outputModalities && cloned.outputModalities.length > 0
        ? cloned.outputModalities.slice()
        : (cur.imageGen ? ['text', 'image'] : ['text']);
      if (cloned.imageGen) {
        if (!baseOut.includes('image')) {
          baseOut.push('image');
        }
        cloned.outputModalities = baseOut;
      } else {
        const filtered = baseOut.filter((m: ModelOutputModality): boolean => m !== 'image');
        cloned.outputModalities = filtered.length > 0 ? filtered : ['text'];
      }
    }
    next[idx] = cloned;
    this.savedModels = next;
    this.modelsRev += 1;
  }

  private editingProviderSnapshot(): Provider {
    const snap = preset(
      this.selectedId || this.original.id,
      this.labelText.trim() || this.original.name,
      this.family,
      this.endpoint.trim() || this.original.baseUrl,
      this.modelId.trim() || this.original.model
    );
    snap.chatPath = this.chatPath.trim();
    snap.secretRef = this.original.secretRef;
    snap.oauth = this.original.oauth;
    return snap;
  }

  private openModelEditor(idx: number): void {
    const ms = this.savedModels[idx];
    if (!ms) {
      return;
    }
    const prevId = ms.id;
    this.onOpenModelEditor(
      this.editingProviderSnapshot(),
      cloneModelSpec(ms),
      false,
      (saved: ModelSpec) => {
        this.applyEditedModelAt(idx, prevId, saved);
      }
    );
  }

  private openNewModelEditor(): void {
    this.onOpenModelEditor(
      this.editingProviderSnapshot(),
      defaultModelSpec(''),
      true,
      (saved: ModelSpec) => {
        this.applyEditedModelAt(-1, '', saved);
      }
    );
  }

  private modelSpecSummary(ms: ModelSpec): string {
    const parts: string[] = [];
    if (ms.modelType && ms.modelType !== 'chat') {
      parts.push(ms.modelType === 'embedding' ? '嵌入' : '图像');
    }
    if (ms.contextWindow > 0) {
      parts.push(Math.round(ms.contextWindow / 1000) + 'K 上下文');
    }
    if (ms.reasoningDialect && ms.reasoningDialect !== 'auto') {
      parts.push('方言 ' + ms.reasoningDialect);
    }
    if (ms.customHeaders && ms.customHeaders.length > 0) {
      parts.push(ms.customHeaders.length + ' Headers');
    }
    if (ms.customBodyEntries && ms.customBodyEntries.length > 0) {
      parts.push(ms.customBodyEntries.length + ' Body');
    }
    if (
      ms.builtinCodeInterpreter ||
      ms.builtinImageGen ||
      ms.builtinUrlContext ||
      ms.builtinCodeExec ||
      ms.builtinYoutube ||
      ms.builtinWebFetch ||
      ms.builtinShell
    ) {
      parts.push('内置工具');
    }
    return parts.join(' · ');
  }

  private applyEditedModelAt(editIdx: number, prevId: string, spec: ModelSpec): void {
    const next = this.savedModels.map((m: ModelSpec): ModelSpec => cloneModelSpec(m));
    const clonedSpec = cloneModelSpec(spec);
    if (editIdx >= 0 && editIdx < next.length && (!prevId || next[editIdx].id === prevId)) {
      next[editIdx] = clonedSpec;
      if (this.modelId === prevId) {
        this.modelId = clonedSpec.id;
      }
    } else {
      const existingIdx = next.findIndex((m: ModelSpec): boolean =>
        m.id === clonedSpec.id || (!!prevId && m.id === prevId)
      );
      if (existingIdx >= 0) {
        next[existingIdx] = clonedSpec;
        if (this.modelId === prevId) {
          this.modelId = clonedSpec.id;
        }
      } else {
        next.push(clonedSpec);
      }
      if (!this.modelId.trim()) {
        this.modelId = clonedSpec.id;
      }
    }
    this.savedModels = next;
    this.modelsRev += 1;
    this.activeTab = 'models';
    if (this.labelText.trim().length > 0 && this.endpoint.trim().length > 0) {
      this.submitForm(false);
    }
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
      const form = this.formProvider();
      const key = this.reuseSecret() ? await readKey(this.original.secretRef) : this.keyInput.trim();
      const pass = form.proxy?.passwordRef ? await readKey(form.proxy.passwordRef) : '';
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

  async importProvider(scan: boolean): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    this.importError = '';
    try {
      let link = this.importText;
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
      const form = this.formProvider();
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
      const form = this.formProvider();
      const key = this.reuseSecret() ? await readKey(this.original.secretRef) : this.keyInput.trim();
      const pass = form.proxy?.passwordRef ? await readKey(form.proxy.passwordRef) : '';
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
      const form = this.formProvider();
      const reuse = this.reuseSecret();
      const key = reuse ? await readKey(this.original.secretRef) : this.keyInput.trim();
      const pass = form.proxy?.passwordRef ? await readKey(form.proxy.passwordRef) : '';
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
      const form = this.formProvider();
      const reuse = this.reuseSecret();
      const updated = await this.onApply(form, this.keyInput.trim(), reuse, setActive);
      this.localProviders = updated.slice();
      const saved = updated.find((v: Provider): boolean => v.id === form.id);
      if (saved) {
        this.original = saved;
        this.clearSecret = false;
      }
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

  private setActiveTab(tab: 'config' | 'models'): void {
    this.activeTab = tab;
    try {
      this.detailScroller.scrollTo({ xOffset: 0, yOffset: 0 });
    } catch (_) {}
  }

  private canDeleteSelected(): boolean {
    return this.localProviders.length > 1 && this.localProviders.some((p: Provider): boolean => p.id === this.selectedId);
  }

  @Builder
  private navTitleBar() {
    if (this.pageMode === 'detail') {
      KelivoNavTitleBar({
        titleText: this.selectedId ? (this.labelText || '编辑服务商') : '新增服务商',
        subtitleText: this.familyLabel(this.family),
        showBack: true,
        rightText: this.busy ? '保存中' : '保存',
        rightPrimary: true,
        secondSymbol: this.canDeleteSelected() ? $r('sys.symbol.trash') : undefined,
        onBack: () => { this.onClose(); },
        onSecondAction: () => {
          if (this.canDeleteSelected()) {
            this.onDeleteProvider(this.selectedId).then((updated: Provider[]) => {
              this.localProviders = updated.slice();
              this.onClose();
            }).catch((e: Error) => { this.notice = e.message; });
          }
        },
        onRightAction: () => {
          this.submitForm(false).then((ok: boolean) => {
            if (ok) {
              this.onClose();
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
          this.showAddSheet = true;
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
                    Text(`${this.familyLabel(p.family)} · ${this.providerModelCount(p)} 个模型${p.secretRef ? ' · 已配密钥' : (p.oauth ? ' · 已登录' : '')}`)
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
                  this.onOpenDetail(p.id);
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
  }

  @Builder
  private detailView() {
    Column() {
      Scroll(this.detailScroller) {
        Column({ space: 10 }) {
          Row({ space: 6 }) {
            Button('配置').layoutWeight(1).height(34).fontSize(12).borderRadius(17)
              .backgroundColor(this.activeTab === 'config' ? $r('app.color.accent') : $r('app.color.surface'))
              .fontColor(this.activeTab === 'config' ? $r('app.color.on_accent') : $r('app.color.ink'))
              .onClick(() => { this.setActiveTab('config'); })
            Button('模型').layoutWeight(1).height(34).fontSize(12).borderRadius(17)
              .backgroundColor(this.activeTab === 'models' ? $r('app.color.accent') : $r('app.color.surface'))
              .fontColor(this.activeTab === 'models' ? $r('app.color.on_accent') : $r('app.color.ink'))
              .onClick(() => { this.setActiveTab('models'); })
          }
          .padding({ bottom: 4 })
          .width('100%')

          if (this.activeTab === 'config') {
            if (!this.initialProviderId && !this.labelText && !this.endpoint && !this.keyInput) {
              Button('使用 OpenCode Go 预设').height(36).fontSize(13)
                .backgroundColor($r('app.color.tint')).fontColor($r('app.color.accent'))
                .onClick(() => { this.selectProvider(openCodeGoPreset(this.selectedId)); })
            }
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

            if (planClientId(this.original) || this.endpoint === CHATGPT_PLAN_API || (!this.endpoint && !this.initialProviderId)) {
              ChatGptPlanLogin({
                clientId: planClientId(this.original),
                accountLabel: planClientId(this.original) ? this.original.oauth?.accountEmail || '' : '',
                onConnected: async (session: PlanSession): Promise<void> => {
                  await this.connectChatGpt(session);
                }
              })
            }
            if (openCodeGoSessionId(this.original) || isOpenCodeGoEndpoint(this.endpoint)) {
              OpenCodeGoPlanLogin({
                sessionId: openCodeGoSessionId(this.original),
                accountLabel: openCodeGoSessionId(this.original) ? this.original.oauth?.accountEmail || '' : '',
                workspaceLabel: openCodeGoSessionId(this.original) ? this.original.oauth?.quotaSummary || '' : '',
                onConnected: async (session: OpenCodeGoSession): Promise<void> => {
                  await this.connectOpenCodeGo(session);
                }
              })
            }
            if (isOpenCodeGoEndpoint(this.endpoint)) {
              OpenCodeGoQuota({
                oauthSessionId: openCodeGoSessionId(this.original),
                savedKeyRef: !this.clearSecret && isOpenCodeGoEndpoint(this.original.baseUrl) ? this.original.secretRef : '',
                draftKey: this.keyInput,
                proxy: this.original.proxy
              })
            } else if (providerBalanceUrl(this.endpoint, this.original.balanceUrl)) {
              Row({ space: 8 }) {
                Text(this.balanceResult ? '最近余额  ' + this.balanceResult : '账户余额')
                  .layoutWeight(1).fontSize(14).fontColor($r('app.color.ink'))
                Button('查余额').height(32).fontSize(12)
                  .backgroundColor($r('app.color.tint')).fontColor($r('app.color.accent'))
                  .onClick(() => { this.queryBalance(); })
              }.width('100%').padding(12).borderRadius(14).backgroundColor($r('app.color.surface'))
            }

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

            if (!planClientId(this.original) && !openCodeGoSessionId(this.original)) {
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
              if (!planClientId(this.original) && !openCodeGoSessionId(this.original)) {
                Button(this.shareCode ? '收起分享码' : '分享配置码')
                  .type(ButtonType.Normal)
                  .height(36)
                  .fontSize(13)
                  .borderRadius(10)
                  .backgroundColor($r('app.color.surface'))
                  .fontColor($r('app.color.ink'))
                  .layoutWeight(1)
                  .onClick(() => { this.showCode(); })
              }
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
          } else {
            this.caption('当前使用模型 ID')
            TextInput({ text: this.modelId, placeholder: '输入服务商提供的模型 ID' }).id('modelId')
              .backgroundColor($r('app.color.surface'))
              .onChange((v: string) => { this.modelId = v; })
            Row({ space: 8 }) {
              Button('获取模型').id('fetchModels').backgroundColor($r('app.color.tint')).fontColor($r('app.color.accent'))
                .onClick(() => { this.requestList(); })
              Button('添加模型').backgroundColor($r('app.color.surface')).fontColor($r('app.color.ink'))
                .onClick(() => { this.openNewModelEditor(); })
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
                      this.modelsRev += 1;
                    }
                  })
                  .menuSystemMaterial(ImmersiveMaterialStyle.selectMenuMaterial(this.immersiveLightEnabled))
                  .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
              }
            }.width('100%')

            if (this.savedModels.length) {
              this.caption('已收录模型与能力标签（点击选中 · 点编辑可配置完整参数）')
              ForEach(this.savedModels, (ms: ModelSpec, idx: number) => {
                Column({ space: 6 }) {
                  Row({ space: 6 }) {
                    KelivoAvatarBadge({
                      brandId: resolveBrandIconId(`${ms.id} ${this.labelText}`, this.family),
                      avatarText: '',
                      fallbackLetter: ms.id,
                      badgeSize: 22
                    })
                    Column({ space: 2 }) {
                      Text(ms.displayName || ms.id)
                        .fontSize(13)
                        .fontWeight(this.modelId === ms.id ? FontWeight.Bold : FontWeight.Medium)
                        .fontColor(this.modelId === ms.id ? $r('app.color.accent') : $r('app.color.ink'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      if (ms.displayName && ms.displayName !== ms.id) {
                        Text(ms.id)
                          .fontSize(11)
                          .fontColor($r('app.color.muted'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                      if (this.modelSpecSummary(ms).length > 0) {
                        Text(this.modelSpecSummary(ms))
                          .fontSize(10)
                          .fontColor($r('app.color.muted'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                      }
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                    .onClick(() => { this.modelId = ms.id; })

                    Button('编辑')
                      .height(26)
                      .fontSize(11)
                      .backgroundColor($r('app.color.panel'))
                      .fontColor($r('app.color.accent'))
                      .onClick(() => { this.openModelEditor(idx); })
                    Button('移除').height(26).fontSize(11).backgroundColor(Color.Transparent).fontColor($r('app.color.warning'))
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
              }, (ms: ModelSpec, idx: number) => this.modelsRev + '-' + ms.id + '-' + ms.displayName + '-' + idx + '-' + ms.vision + '-' + ms.tools + '-' + ms.reasoning + '-' + ms.imageGen)
            }

          }

          if (this.notice) { Text(this.notice).fontSize(13).fontColor($r('app.color.accent')) }
          Button(this.busy ? '处理中…' : '保存并使用').id('saveProvider').width('100%')
            .height(44).borderRadius(14)
            .margin({ top: 10, bottom: 18 }).backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
            .onClick(() => {
              this.submitForm(true).then((ok: boolean) => {
                if (ok) {
                  this.onClose();
                }
              });
            })
        }.width('100%').constraintSize({ maxWidth: 620 }).padding({
          left: 16,
          right: 16,
          top: 56 + this.winTopInset + 4,
          bottom: Math.max(36, this.winBottomInset + 20)
        }).alignItems(HorizontalAlign.Start).enabled(!this.busy)
      }.layoutWeight(1).width('100%').align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .enabled(!this.busy)
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
            this.importProvider(false);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 24 })
  }

  @Builder
  private addProviderSheetBuilder() {
    AddProviderSheet({
      onCreateProvider: (provider: Provider, apiKey: string) => this.createProviderFromSheet(provider, apiKey),
      onConnectChatGpt: (session: PlanSession) => this.connectChatGpt(session),
      onConnectOpenCodeGo: (session: OpenCodeGoSession) => this.connectOpenCodeGo(session),
      onViewProviderDetail: (pid: string) => {
        this.showAddSheet = false;
        this.onOpenDetail(pid);
      },
      onClose: () => { this.showAddSheet = false; }
    })
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          if (this.pageMode === 'detail') {
            this.detailView()
          } else {
            this.listView()
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)

        Column()
          .width(0)
          .height(0)
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

        Column()
          .width(0)
          .height(0)
          .bindSheet(
            $$this.showAddSheet,
            this.addProviderSheetBuilder(),
            ImmersiveMaterialStyle.addProviderSheetOptions(
              this.immersiveLightEnabled,
              this.themeCanvasHex,
              () => { this.showAddSheet = false; }
            )
          )
      }
      .width('100%')
      .height('100%')
    }
    .hideBackButton(true)
    .backgroundColor(this.themeCanvasHex)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .title(
      { builder: () => this.navTitleBar(), height: 56 + this.winTopInset },
      ImmersiveMaterialStyle.titleBarOptions(this.immersiveLightEnabled, true)
    )
    .systemTransition(SystemMotion.navTransition(this.reduceMotion))
    .onShown(() => { this.onRouteShown(); })
    .onHidden(() => { this.onRouteHidden(); })
    .onBackPressed(() => this.onDismissOverlay())
  }
}
