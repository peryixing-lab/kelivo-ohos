import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import {
  ApiKeyEntry,
  KeyRotationStrategy,
  SearchConfig,
  SearchServiceConfig,
  checkEndpoint
} from '../core/Models';
import { resolveBrandIconId } from '../core/BrandIcons';
import { SEARCH_ENGINE_CATALOG, SearchEngineCatalogItem, findSearchCatalog } from '../core/SearchAdapters';
import { forgetKey, newId, storeKey } from '../core/Storage';
import { KelivoAvatarBadge, KelivoPageHeader } from './KelivoChrome';

@Component
export struct SearchEditor {
  config: SearchConfig = { kind: 'searxng', endpoint: '', secretRef: '' };
  @Prop services: SearchServiceConfig[] = [];
  activeServiceId: string = '';
  @Prop embeddedInNav: boolean = false;
  onApply: (config: SearchConfig, key: string) => Promise<void> = async () => {};
  onSaveServices: (services: SearchServiceConfig[], activeId: string, enableSearch: boolean) => void = () => {};
  onClose: () => void = () => {};
  onDisable: () => void = () => {};

  @StorageProp('immersiveLightEnabled') immersiveLightEnabled: boolean = true;
  @StorageProp('windowTopInsetVp') winTopInset: number = 0;

  @State list: SearchServiceConfig[] = [];
  @State selectedId: string = '';
  @State kind: string = 'duckduckgo';
  @State serviceName: string = '';
  @State endpoint: string = '';
  @State keyInput: string = '';
  @State keyLabel: string = '';
  @State apiKeys: ApiKeyEntry[] = [];
  @State keyStrategy: KeyRotationStrategy = 'round_robin';
  @State maxResults: number = 5;
  @State mode: 'agent_tool' | 'pre_search' = 'agent_tool';
  @State webFetchEnabled: boolean = true;
  @State detail: string = '';
  @State saving: boolean = false;

  aboutToAppear(): void {
    if (this.services.length > 0) {
      this.list = this.services.slice();
      const first = this.list.find((s: SearchServiceConfig): boolean => s.id === this.activeServiceId) || this.list[0];
      this.loadService(first);
    } else {
      this.kind = this.config.kind;
      this.endpoint = this.config.endpoint;
      this.serviceName = findSearchCatalog(this.kind).name;
    }
  }

  private loadService(s: SearchServiceConfig): void {
    this.selectedId = s.id;
    this.kind = s.kind;
    this.serviceName = s.name;
    this.endpoint = s.endpoint;
    this.apiKeys = s.apiKeys ? s.apiKeys.slice() : [];
    this.keyStrategy = s.keyStrategy || 'round_robin';
    this.maxResults = s.maxResults || 5;
    this.mode = s.mode || 'agent_tool';
    this.webFetchEnabled = s.webFetchEnabled !== false;
    this.keyInput = '';
    this.detail = '';
  }

  private addNewService(cat: SearchEngineCatalogItem): void {
    const fresh: SearchServiceConfig = {
      id: newId(),
      kind: cat.kind,
      name: cat.name,
      endpoint: cat.defaultEndpoint,
      apiKeys: [],
      keyStrategy: 'round_robin',
      maxResults: 5,
      enabled: true,
      mode: 'agent_tool',
      webFetchEnabled: true
    };
    this.list = [...this.list, fresh];
    this.loadService(fresh);
  }

  private async addApiKey(): Promise<void> {
    if (!this.keyInput.trim()) return;
    const ref = newId();
    await storeKey(ref, this.keyInput.trim());
    this.apiKeys = [...this.apiKeys, {
      id: newId(),
      label: this.keyLabel.trim() || ('Key ' + (this.apiKeys.length + 1)),
      secretRef: ref,
      priority: this.apiKeys.length,
      usageCount: 0,
      errorCount: 0,
      disabledUntil: 0
    }];
    this.keyInput = '';
    this.keyLabel = '';
  }

  private async removeApiKey(item: ApiKeyEntry): Promise<void> {
    await forgetKey(item.secretRef).catch(() => {});
    this.apiKeys = this.apiKeys.filter((k: ApiKeyEntry): boolean => k.id !== item.id);
  }

  private catalogSelectOptions(): SelectOption[] {
    return SEARCH_ENGINE_CATALOG.map((c: SearchEngineCatalogItem): SelectOption => {
      return { value: c.name };
    });
  }

  private existingSelectOptions(): SelectOption[] {
    return this.list.map((s: SearchServiceConfig): SelectOption => {
      return { value: s.name };
    });
  }

  async applySearch(): Promise<void> {
    if (this.saving) return;
    this.saving = true;
    try {
      const cat = findSearchCatalog(this.kind);
      const url = this.kind === 'searxng' || this.kind === 'fourget'
        ? checkEndpoint(this.endpoint)
        : (this.endpoint.trim() || cat.defaultEndpoint);
      if (this.keyInput.trim()) {
        await this.addApiKey();
      }
      if (cat.needsKey && !this.apiKeys.length && !this.config.secretRef) {
        throw new Error('请为 ' + cat.name + ' 添加至少一个 API 密钥');
      }
      const updated: SearchServiceConfig = {
        id: this.selectedId || newId(),
        kind: this.kind,
        name: this.serviceName.trim() || cat.name,
        endpoint: url,
        apiKeys: this.apiKeys.slice(),
        keyStrategy: this.keyStrategy,
        maxResults: this.maxResults,
        enabled: true,
        mode: this.mode,
        webFetchEnabled: this.webFetchEnabled
      };
      const nextList = this.list.some((s: SearchServiceConfig): boolean => s.id === updated.id)
        ? this.list.map((s: SearchServiceConfig): SearchServiceConfig => s.id === updated.id ? updated : s)
        : [...this.list, updated];
      if (this.services.length > 0 || this.list.length > 0) {
        this.onSaveServices(nextList, updated.id, true);
      }
      const fallbackRef = this.apiKeys[0]?.secretRef || this.config.secretRef;
      await this.onApply({ kind: this.kind, endpoint: url, secretRef: fallbackRef }, '');
      this.onClose();
    } catch (e) { this.detail = (e as Error).message || '保存失败'; }
    finally { this.saving = false; }
  }

  build() {
    Column() {
      if (!this.embeddedInNav) {
        KelivoPageHeader({
          titleText: '联网搜索',
          subtitleText: '26 种搜索引擎 · Agent 工具 / 预检索',
          showBack: true,
          onBack: () => { this.onClose(); }
        })
      }

      Scroll() {
        Column({ space: 12 }) {
          Row({ space: 12 }) {
            KelivoAvatarBadge({
              brandId: resolveBrandIconId(`${this.kind} ${this.serviceName}`),
              avatarText: '',
              fallbackLetter: this.serviceName || this.kind,
              badgeSize: 36
            })
            Column({ space: 2 }) {
              Text(findSearchCatalog(this.kind).name)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.ink'))
              Text(`引擎类型: ${this.kind} · 支持多 Key 轮换与正文抓取`)
                .fontSize(11)
                .fontColor($r('app.color.muted'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .width('100%')
          .padding(14)
          .borderRadius(16)
          .backgroundColor($r('app.color.surface'))

          if (this.list.length > 0) {
            Text('已配置搜索服务').fontSize(13).fontColor($r('app.color.muted'))
            Row({ space: 8 }) {
              Select(this.existingSelectOptions()).value(this.serviceName || '选择服务').layoutWeight(1)
                .onSelect((i: number) => this.loadService(this.list[i]))
                .menuSystemMaterial(ImmersiveMaterialStyle.selectMenuMaterial(this.immersiveLightEnabled))
                .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
              Select(this.catalogSelectOptions()).value('+ 新增引擎')
                .onSelect((i: number) => this.addNewService(SEARCH_ENGINE_CATALOG[i]))
                .menuSystemMaterial(ImmersiveMaterialStyle.selectMenuMaterial(this.immersiveLightEnabled))
                .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
            }.width('100%')
          } else {
            Select(this.catalogSelectOptions()).value(findSearchCatalog(this.kind).name)
              .onSelect((i: number) => {
                const cat = SEARCH_ENGINE_CATALOG[i];
                this.kind = cat.kind;
                this.serviceName = cat.name;
                this.endpoint = cat.defaultEndpoint;
                this.detail = '';
              })
              .menuSystemMaterial(ImmersiveMaterialStyle.selectMenuMaterial(this.immersiveLightEnabled))
              .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
          }

          TextInput({ text: this.endpoint, placeholder: '接口地址（免密钥引擎可留默认）' })
            .onChange((v: string) => { this.endpoint = v; })

          Row({ space: 8 }) {
            Text('搜索模式').fontSize(13).fontColor($r('app.color.ink')).layoutWeight(1)
            Button('Agent 工具调用').height(30).fontSize(12)
              .backgroundColor(this.mode === 'agent_tool' ? $r('app.color.accent') : $r('app.color.panel'))
              .fontColor(this.mode === 'agent_tool' ? $r('app.color.on_accent') : $r('app.color.ink'))
              .onClick(() => { this.mode = 'agent_tool'; })
            Button('发前自动检索').height(30).fontSize(12)
              .backgroundColor(this.mode === 'pre_search' ? $r('app.color.accent') : $r('app.color.panel'))
              .fontColor(this.mode === 'pre_search' ? $r('app.color.on_accent') : $r('app.color.ink'))
              .onClick(() => { this.mode = 'pre_search'; })
          }.width('100%')

          Row() {
            Text('允许模型抓取网页正文 (web_fetch)').fontSize(13).fontColor($r('app.color.ink')).layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.webFetchEnabled })
              .selectedColor($r('app.color.accent'))
              .onChange((v: boolean) => { this.webFetchEnabled = v; })
              .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
          }.width('100%')

          Row({ space: 10 }) {
            Text('每次返回结果数: ' + this.maxResults).fontSize(13).fontColor($r('app.color.ink')).layoutWeight(1)
            Slider({ value: this.maxResults, min: 1, max: 10, step: 1 }).width(150)
              .selectedColor($r('app.color.accent'))
              .onChange((v: number) => { this.maxResults = Math.round(v); })
              .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
          }.width('100%')

          if (findSearchCatalog(this.kind).needsKey || this.kind === 'jina') {
            Divider().color($r('app.color.line'))
            Text('API 密钥池（自动轮换）').fontSize(13).fontColor($r('app.color.muted'))
            Row({ space: 6 }) {
              TextInput({ text: this.keyLabel, placeholder: '备注' }).layoutWeight(1)
                .onChange((v: string) => { this.keyLabel = v; })
              TextInput({ text: this.keyInput, placeholder: '输入密钥' }).type(InputType.Password).layoutWeight(2)
                .onChange((v: string) => { this.keyInput = v; })
              Button('添加').height(36).backgroundColor($r('app.color.tint')).fontColor($r('app.color.accent'))
                .onClick(() => { this.addApiKey(); })
            }.width('100%')
            ForEach(this.apiKeys, (ak: ApiKeyEntry) => {
              Row() {
                Text(ak.label + ' · 已用 ' + ak.usageCount + ' 次').fontSize(12).fontColor($r('app.color.ink')).layoutWeight(1)
                Button('删').height(24).fontSize(11).backgroundColor(Color.Transparent).fontColor($r('app.color.warning'))
                  .onClick(() => { this.removeApiKey(ak); })
              }.width('100%').padding(6).backgroundColor($r('app.color.surface')).borderRadius(8)
            }, (ak: ApiKeyEntry) => ak.id + '-' + ak.usageCount)
          }

          if (this.detail) { Text(this.detail).fontColor($r('app.color.warning')).fontSize(13) }
          Button('保存并启用').width('100%').backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
            .onClick(() => { this.applySearch(); })
          Button('关闭联网搜索').width('100%').backgroundColor($r('app.color.panel')).fontColor($r('app.color.ink'))
            .onClick(() => {
              this.onSaveServices(this.list, this.selectedId, false);
              this.onDisable();
              this.onClose();
            })
        }.padding({ left: 18, right: 18, top: this.embeddedInNav ? (56 + this.winTopInset + 4) : 18, bottom: 48 }).width('100%').constraintSize({ maxWidth: 620 }).alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').align(Alignment.Top)
    }.width('100%').height('100%').enabled(!this.saving).backgroundColor(Color.Transparent)
  }
}
