import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { HeaderEntry, McpServerConfig } from '../core/Models';
import { McpManager, McpTool } from '../core/RemoteTools';
import { parseMcpConfigJson } from '../core/McpConfigParser';
import { forgetKey, newId, storeKey } from '../core/Storage';
import { KelivoAvatarBadge, KelivoPageHeader, KelivoStatusPill } from './KelivoChrome';

@Component
export struct ToolsPanel {
  lastEndpoint: string = '';
  @Prop servers: McpServerConfig[] = [];
  @Prop builtinFetchEnabled: boolean = true;
  @Prop embeddedInNav: boolean = false;
  mcpManager: McpManager = new McpManager();
  onRemember: (endpoint: string) => void = () => {};
  onSaveServers: (servers: McpServerConfig[], builtinFetch: boolean) => void = () => {};
  onUseResult: (name: string, text: string) => void = () => {};
  onClose: () => void = () => {};

  @StorageProp('immersiveLightEnabled') immersiveLightEnabled: boolean = true;
  @StorageProp('windowTopInsetVp') winTopInset: number = 0;

  @State list: McpServerConfig[] = [];
  @State fetchEnabled: boolean = true;
  @State selectedServerId: string = '';
  @State serverName: string = '';
  @State transport: 'streamable-http' | 'sse' = 'streamable-http';
  @State address: string = '';
  @State bearer: string = '';
  @State serverEnabled: boolean = true;
  @State headerKey: string = '';
  @State headerVal: string = '';
  @State customHeaders: HeaderEntry[] = [];
  @State toolset: McpTool[] = [];
  @State selected: number = 0;
  @State argsText: string = '{}';
  @State output: string = '';
  @State detail: string = '';
  @State busy: boolean = false;
  @State showJsonImport: boolean = false;
  @State jsonImportText: string = '';

  aboutToAppear(): void {
    this.fetchEnabled = this.builtinFetchEnabled;
    this.list = this.servers.slice();
    if (this.list.length > 0) {
      this.selectServer(this.list[0]);
    } else {
      this.address = this.lastEndpoint;
      this.serverName = '自定义 MCP';
    }
  }

  aboutToDisappear(): void {
    if (this.embeddedInNav) {
      this.onSaveServers(this.list, this.fetchEnabled);
    }
  }

  private selectServer(s: McpServerConfig): void {
    this.selectedServerId = s.id;
    this.serverName = s.name;
    this.transport = s.transport;
    this.address = s.endpoint;
    this.serverEnabled = s.enabled;
    this.customHeaders = s.customHeaders ? s.customHeaders.slice() : [];
    this.bearer = '';
    this.toolset = this.mcpManager.getCachedTools(s.id);
    this.selected = 0;
    this.output = '';
    this.detail = '';
  }

  private startNewServer(): void {
    this.selectedServerId = newId();
    this.serverName = '新 MCP 服务器';
    this.transport = 'streamable-http';
    this.address = '';
    this.bearer = '';
    this.serverEnabled = true;
    this.customHeaders = [];
    this.toolset = [];
    this.output = '';
    this.detail = '';
  }

  private currentServerObj(): McpServerConfig | undefined {
    return this.list.find((s: McpServerConfig): boolean => s.id === this.selectedServerId);
  }

  private async saveCurrentServer(): Promise<McpServerConfig> {
    const cleanAddr = this.address.trim();
    if (!cleanAddr) throw new Error('请输入服务器地址');
    const prev = this.currentServerObj();
    let secretRef = prev?.bearerSecretRef || '';
    if (this.bearer.trim()) {
      const nextRef = newId();
      await storeKey(nextRef, this.bearer.trim());
      if (secretRef) await forgetKey(secretRef).catch(() => {});
      secretRef = nextRef;
      this.bearer = '';
    }
    const cfg: McpServerConfig = {
      id: this.selectedServerId || newId(),
      name: this.serverName.trim() || 'MCP 服务',
      transport: this.transport,
      endpoint: cleanAddr,
      bearerSecretRef: secretRef,
      customHeaders: this.customHeaders.slice(),
      oauthAccessTokenRef: prev?.oauthAccessTokenRef,
      enabled: this.serverEnabled,
      disabledTools: prev?.disabledTools || [],
      autoApproveTools: prev?.autoApproveTools || []
    };
    this.selectedServerId = cfg.id;
    this.list = this.list.some((s: McpServerConfig): boolean => s.id === cfg.id)
      ? this.list.map((s: McpServerConfig): McpServerConfig => s.id === cfg.id ? cfg : s)
      : [...this.list, cfg];
    this.onRemember(cleanAddr);
    this.onSaveServers(this.list, this.fetchEnabled);
    return cfg;
  }

  private async deleteServer(id: string): Promise<void> {
    const target = this.list.find((s: McpServerConfig): boolean => s.id === id);
    await this.mcpManager.disconnectServer(id);
    if (target?.bearerSecretRef) await forgetKey(target.bearerSecretRef).catch(() => {});
    this.list = this.list.filter((s: McpServerConfig): boolean => s.id !== id);
    this.onSaveServers(this.list, this.fetchEnabled);
    if (this.list.length > 0) this.selectServer(this.list[0]);
    else this.startNewServer();
  }

  private async importJsonServers(): Promise<void> {
    if (this.busy || !this.jsonImportText.trim()) return;
    this.busy = true;
    this.detail = '';
    try {
      const imported = parseMcpConfigJson(this.jsonImportText, () => newId());
      for (let i = 0; i < imported.length; i++) {
        const item = imported[i];
        if (item.bearerToken) {
          const ref = newId();
          await storeKey(ref, item.bearerToken);
          item.config.bearerSecretRef = ref;
        }
        this.list = [...this.list, item.config];
      }
      this.onSaveServers(this.list, this.fetchEnabled);
      this.selectServer(imported[0].config);
      this.showJsonImport = false;
      this.jsonImportText = '';
      this.detail = '成功导入 ' + imported.length + ' 个 MCP 服务器';
    } catch (e) {
      this.detail = (e as Error).message || 'JSON 导入失败';
    } finally {
      this.busy = false;
    }
  }

  async connectTools(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    this.detail = '';
    try {
      const cfg = await this.saveCurrentServer();
      const tools = await this.mcpManager.connectServer(cfg);
      this.toolset = tools;
      this.selected = 0;
      this.argsText = '{}';
      this.detail = tools.length ? ('已连接，发现 ' + tools.length + ' 个工具') : '服务器没有可用工具';
    } catch (e) {
      this.detail = (e as Error).message || '连接失败';
    } finally {
      this.busy = false;
    }
  }

  async invokeTool(): Promise<void> {
    if (this.busy || !this.toolset[this.selected]) return;
    this.busy = true;
    this.detail = '';
    this.output = '';
    try {
      const res = await this.mcpManager.invokeMcpTool(
        this.selectedServerId,
        this.toolset[this.selected].name,
        this.argsText
      );
      this.output = res.text;
    } catch (e) {
      this.detail = (e as Error).message || '工具调用失败';
    } finally {
      this.busy = false;
    }
  }

  private isToolDisabled(name: string): boolean {
    const s = this.currentServerObj();
    return s ? s.disabledTools.includes(name) : false;
  }

  private isToolAutoApproved(name: string): boolean {
    const s = this.currentServerObj();
    return s ? s.autoApproveTools.includes(name) : false;
  }

  private toggleToolFlag(name: string, kind: 'disabled' | 'auto'): void {
    const s = this.currentServerObj();
    if (!s) return;
    let disabled = s.disabledTools.slice();
    let auto = s.autoApproveTools.slice();
    if (kind === 'disabled') {
      disabled = disabled.includes(name)
        ? disabled.filter((n: string): boolean => n !== name)
        : [...disabled, name];
    } else {
      auto = auto.includes(name)
        ? auto.filter((n: string): boolean => n !== name)
        : [...auto, name];
    }
    const updated: McpServerConfig = {
      id: s.id, name: s.name, transport: s.transport, endpoint: s.endpoint,
      bearerSecretRef: s.bearerSecretRef, customHeaders: s.customHeaders,
      oauthAccessTokenRef: s.oauthAccessTokenRef, enabled: s.enabled,
      disabledTools: disabled, autoApproveTools: auto
    };
    this.list = this.list.map((item: McpServerConfig): McpServerConfig => item.id === updated.id ? updated : item);
    this.onSaveServers(this.list, this.fetchEnabled);
  }

  private serverSelectOptions(): SelectOption[] {
    return this.list.map((s: McpServerConfig): SelectOption => {
      return { value: (s.enabled ? '● ' : '○ ') + s.name };
    });
  }

  build() {
    Column() {
      if (!this.embeddedInNav) {
        KelivoPageHeader({
          titleText: 'MCP 工具中心',
          showBack: true,
          rightText: '导入 JSON',
          onBack: () => {
            this.onSaveServers(this.list, this.fetchEnabled);
            this.onClose();
          },
          onRightAction: () => { this.showJsonImport = !this.showJsonImport; }
        })
      }

      Scroll() {
        Column({ space: 12 }) {
          if (this.embeddedInNav) {
            Row({ space: 8 }) {
              Button(this.showJsonImport ? '收起 JSON 导入' : '导入 mcpServers JSON')
                .height(34).fontSize(12).borderRadius(10)
                .backgroundColor($r('app.color.panel')).fontColor($r('app.color.ink'))
                .onClick(() => { this.showJsonImport = !this.showJsonImport; })
              Blank()
              Button('保存配置')
                .height(34).fontSize(12).borderRadius(10)
                .backgroundColor($r('app.color.tint')).fontColor($r('app.color.accent'))
                .onClick(() => { this.onSaveServers(this.list, this.fetchEnabled); })
            }.width('100%')
          }

          Row({ space: 12 }) {
            KelivoAvatarBadge({
              brandId: 'mcp',
              avatarText: '',
              fallbackLetter: 'F',
              badgeSize: 36
            })
            Column({ space: 3 }) {
              Row({ space: 8 }) {
                Text('@kelivo/fetch')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.ink'))
                KelivoStatusPill({ enabledState: this.fetchEnabled })
              }
              Text('内置网页正文抓取 (kelivo_fetch_url)，免部署即开即用')
                .fontSize(11)
                .fontColor($r('app.color.muted'))
            }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            Toggle({ type: ToggleType.Switch, isOn: this.fetchEnabled }).selectedColor($r('app.color.accent'))
              .onChange((v: boolean) => {
                this.fetchEnabled = v;
                this.onSaveServers(this.list, this.fetchEnabled);
              })
              .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
          }.width('100%').padding(14).borderRadius(16).backgroundColor($r('app.color.surface'))

          if (this.showJsonImport) {
            Column({ space: 8 }) {
              Text('粘贴标准 mcpServers JSON 配置').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink'))
              TextArea({
                text: this.jsonImportText,
                placeholder: '{"mcpServers": {"fetch": {"url": "https://example.com/mcp", "transport": "streamable-http"}}}'
              }).height(110).onChange((v: string) => { this.jsonImportText = v; })
              Button('解析并导入').backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
                .onClick(() => { this.importJsonServers(); })
            }.width('100%').padding(12).borderRadius(12).backgroundColor($r('app.color.panel')).alignItems(HorizontalAlign.Start)
          }

          Row({ space: 8 }) {
            if (this.list.length > 0) {
              Select(this.serverSelectOptions()).value(this.serverName || '选择 MCP').layoutWeight(1)
                .onSelect((i: number) => this.selectServer(this.list[i]))
                .menuSystemMaterial(ImmersiveMaterialStyle.selectMenuMaterial(this.immersiveLightEnabled))
                .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
            }
            Button('+ 新增').height(36).backgroundColor($r('app.color.tint')).fontColor($r('app.color.accent'))
              .onClick(() => this.startNewServer())
            if (this.currentServerObj()) {
              Button('删除').height(36).backgroundColor(Color.Transparent).fontColor($r('app.color.warning'))
                .onClick(() => { this.deleteServer(this.selectedServerId); })
            }
          }.width('100%')

          Row({ space: 8 }) {
            TextInput({ text: this.serverName, placeholder: '服务器名称' }).layoutWeight(1)
              .onChange((v: string) => { this.serverName = v; })
            Toggle({ type: ToggleType.Switch, isOn: this.serverEnabled }).selectedColor($r('app.color.accent'))
              .onChange((v: boolean) => { this.serverEnabled = v; })
              .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
          }.width('100%')

          Row({ space: 8 }) {
            Text('传输协议').fontSize(13).fontColor($r('app.color.muted')).layoutWeight(1)
            Button('Streamable HTTP').height(30).fontSize(12)
              .backgroundColor(this.transport === 'streamable-http' ? $r('app.color.accent') : $r('app.color.panel'))
              .fontColor(this.transport === 'streamable-http' ? $r('app.color.on_accent') : $r('app.color.ink'))
              .onClick(() => { this.transport = 'streamable-http'; })
            Button('Legacy SSE').height(30).fontSize(12)
              .backgroundColor(this.transport === 'sse' ? $r('app.color.accent') : $r('app.color.panel'))
              .fontColor(this.transport === 'sse' ? $r('app.color.on_accent') : $r('app.color.ink'))
              .onClick(() => { this.transport = 'sse'; })
          }.width('100%')

          TextInput({ text: this.address, placeholder: 'https://example.com/mcp' })
            .onChange((v: string) => { this.address = v; })
          TextInput({
            text: this.bearer,
            placeholder: this.currentServerObj()?.bearerSecretRef ? '已安全保存令牌（输入可替换）' : 'Bearer 令牌（可选，写入密钥库）'
          }).type(InputType.Password).onChange((v: string) => { this.bearer = v; })

          Row({ space: 6 }) {
            TextInput({ text: this.headerKey, placeholder: '自定义 Header 名' }).layoutWeight(1)
              .onChange((v: string) => { this.headerKey = v; })
            TextInput({ text: this.headerVal, placeholder: 'Header 值' }).layoutWeight(1)
              .onChange((v: string) => { this.headerVal = v; })
            Button('+').height(36).backgroundColor($r('app.color.panel')).fontColor($r('app.color.ink'))
              .onClick(() => {
                if (this.headerKey.trim()) {
                  this.customHeaders = [...this.customHeaders, { key: this.headerKey.trim(), value: this.headerVal }];
                  this.headerKey = ''; this.headerVal = '';
                }
              })
          }.width('100%')

          Row({ space: 8 }) {
            Button('保存并连接获取工具').layoutWeight(1).backgroundColor($r('app.color.accent')).fontColor($r('app.color.on_accent'))
              .onClick(() => { this.connectTools(); })
          }.width('100%')

          if (this.toolset.length) {
            Divider().color($r('app.color.line'))
            Text('已发现工具（点击可配置启用/免审批，或下方手动运行）').fontSize(13).fontColor($r('app.color.muted'))
            ForEach(this.toolset, (t: McpTool, ti: number) => {
              Row({ space: 6 }) {
                Column({ space: 2 }) {
                  Text(t.name).fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink'))
                  if (t.description) {
                    Text(t.description).fontSize(11).fontColor($r('app.color.muted')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                }.layoutWeight(1).alignItems(HorizontalAlign.Start).onClick(() => {
                  this.selected = ti; this.argsText = '{}'; this.output = '';
                })
                Button(this.isToolDisabled(t.name) ? '已禁用' : '已启用').height(26).fontSize(11)
                  .backgroundColor(this.isToolDisabled(t.name) ? $r('app.color.panel') : $r('app.color.tint'))
                  .fontColor(this.isToolDisabled(t.name) ? $r('app.color.muted') : $r('app.color.accent'))
                  .onClick(() => this.toggleToolFlag(t.name, 'disabled'))
                Button(this.isToolAutoApproved(t.name) ? '免审批' : '需审批').height(26).fontSize(11)
                  .backgroundColor(this.isToolAutoApproved(t.name) ? $r('app.color.tint') : $r('app.color.panel'))
                  .fontColor(this.isToolAutoApproved(t.name) ? $r('app.color.accent') : $r('app.color.muted'))
                  .onClick(() => this.toggleToolFlag(t.name, 'auto'))
              }.width('100%').padding(8).borderRadius(10).backgroundColor($r('app.color.surface'))
            }, (t: McpTool, ti: number) => t.name + '-' + ti + '-' + this.isToolDisabled(t.name) + '-' + this.isToolAutoApproved(t.name))

            if (this.toolset[this.selected]) {
              Text('测试工具: ' + this.toolset[this.selected].name).fontSize(13).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink'))
              Text(JSON.stringify(this.toolset[this.selected].inputSchema, null, 2))
                .fontFamily('monospace').fontSize(11).fontColor($r('app.color.muted')).copyOption(CopyOptions.LocalDevice)
              TextArea({ text: this.argsText }).height(84).onChange((v: string) => { this.argsText = v; this.output = ''; })
              Button('运行 ' + this.toolset[this.selected].name).backgroundColor($r('app.color.tint'))
                .fontColor($r('app.color.accent')).onClick(() => { this.invokeTool(); })
            }
          }

          if (this.output) {
            Text(this.output).maxLines(15).textOverflow({ overflow: TextOverflow.Ellipsis })
              .fontSize(13).fontColor($r('app.color.ink')).copyOption(CopyOptions.LocalDevice)
            Button('将结果附到消息').backgroundColor($r('app.color.tint')).fontColor($r('app.color.accent'))
              .onClick(() => this.onUseResult(this.toolset[this.selected]?.name || 'mcp', this.output))
          }
          if (this.busy) { LoadingProgress().width(28).height(28) }
          if (this.detail) { Text(this.detail).fontSize(13).fontColor($r('app.color.accent')) }
        }.padding({ left: 18, right: 18, top: this.embeddedInNav ? (56 + this.winTopInset + 4) : 18, bottom: 48 }).width('100%').constraintSize({ maxWidth: 620 }).alignItems(HorizontalAlign.Start).enabled(!this.busy)
      }.width('100%').layoutWeight(1).align(Alignment.Top)
    }.width('100%').height('100%').backgroundColor(Color.Transparent)
  }
}
