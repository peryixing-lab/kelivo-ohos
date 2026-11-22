import { resolveBrandIconId } from '../core/BrandIcons';
import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { LocalWorkspace, McpServerConfig, ReasoningEffort, SearchServiceConfig, ToolPermissionMode } from '../core/Models';
import { KelivoAvatarBadge } from './KelivoChrome';

@Component
export struct SearchQuickSheet {
  @Prop searchOn: boolean = false;
  @Prop searchServices: SearchServiceConfig[] = [];
  @Prop activeSearchId: string = '';
  @Prop immersiveLightEnabled: boolean = true;

  onToggleSearch: (enabled: boolean) => void = () => {};
  onSelectSearchService: (id: string) => void = () => {};
  onOpenSearchSettings: () => void = () => {};

  build() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.globe_badge_message'))
          .fontSize(20)
          .fontColor([$r('app.color.accent')])
        Text('联网搜索')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
          .layoutWeight(1)
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.gearshape'))
            .fontSize(19)
            .fontColor([$r('app.color.ink')])
        }
        .width(36)
        .height(36)
        .padding(0)
        .backgroundColor(Color.Transparent)
        .onClick(() => { this.onOpenSearchSettings(); })
        Toggle({ type: ToggleType.Switch, isOn: this.searchOn })
          .onChange((v: boolean) => { this.onToggleSearch(v); })
          .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(14)
      .backgroundColor(ImmersiveMaterialStyle.sheetCardBackground(this.immersiveLightEnabled))

      Scroll() {
        Column({ space: 4 }) {
          ForEach(this.searchServices, (svc: SearchServiceConfig) => {
            Row({ space: 10 }) {
              KelivoAvatarBadge({
                brandId: resolveBrandIconId(`${svc.kind} ${svc.name}`),
                avatarText: '',
                fallbackLetter: svc.name,
                badgeSize: 28
              })
              Column({ space: 2 }) {
                Text(svc.name)
                  .fontSize(14)
                  .fontColor($r('app.color.ink'))
                Text(svc.mode === 'agent_tool' ? 'Agent 工具检索' : '对话前预检索')
                  .fontSize(11)
                  .fontColor($r('app.color.muted'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              if (svc.id === this.activeSearchId) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(17)
                  .fontColor([$r('app.color.accent')])
              }
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .borderRadius(12)
            .backgroundColor(svc.id === this.activeSearchId ? $r('app.color.tint') : Color.Transparent)
            .onClick(() => { this.onSelectSearchService(svc.id); })
          }, (svc: SearchServiceConfig) => svc.id)
        }
        .width('100%')
      }
      .constraintSize({ maxHeight: 340 })
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 20 })
  }
}

interface ReasoningChoice {
  effort: ReasoningEffort;
  label: string;
  desc: string;
}

const REASONING_CHOICES: ReasoningChoice[] = [
  { effort: 'off', label: '关闭思考', desc: '直接回答，速度最快' },
  { effort: 'low', label: '轻度推理', desc: '简短思考后响应' },
  { effort: 'medium', label: '标准推理', desc: '均衡思考深度与延迟' },
  { effort: 'high', label: '深度推理', desc: '适合复杂架构与推导' },
  { effort: 'max', label: '极限推理', desc: '分配最大推理预算' }
];

@Component
export struct ReasoningLevelSheet {
  @Prop currentEffort: ReasoningEffort = 'off';
  @Prop budgetTokens: number = 8192;
  @Prop immersiveLightEnabled: boolean = true;

  onSelectEffort: (effort: ReasoningEffort) => void = () => {};
  onChangeBudget: (tokens: number) => void = () => {};

  build() {
    Column({ space: 10 }) {
      Column({ space: 2 }) {
        ForEach(REASONING_CHOICES, (item: ReasoningChoice) => {
          Row({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.lightbulb'))
              .fontSize(18)
              .fontColor([this.currentEffort === item.effort ? $r('app.color.accent') : $r('app.color.muted')])
            Column({ space: 2 }) {
              Text(item.label)
                .fontSize(15)
                .fontColor($r('app.color.ink'))
              Text(item.desc)
                .fontSize(11)
                .fontColor($r('app.color.muted'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            if (this.currentEffort === item.effort) {
              SymbolGlyph($r('sys.symbol.checkmark'))
                .fontSize(17)
                .fontColor([$r('app.color.accent')])
            }
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .borderRadius(12)
          .backgroundColor(this.currentEffort === item.effort ? $r('app.color.tint') : Color.Transparent)
          .onClick(() => { this.onSelectEffort(item.effort); })
        }, (item: ReasoningChoice) => item.effort)
      }
      .width('100%')
      .borderRadius(16)
      .backgroundColor(ImmersiveMaterialStyle.sheetCardBackground(this.immersiveLightEnabled))
      .padding(6)

      if (this.currentEffort !== 'off') {
        Column({ space: 6 }) {
          Row() {
            Text('思考 Token 预算')
              .fontSize(14)
              .fontColor($r('app.color.ink'))
              .layoutWeight(1)
            Text(`${Math.round(this.budgetTokens / 1024)}k`)
              .fontSize(13)
              .fontColor($r('app.color.accent'))
          }
          .width('100%')

          Slider({ value: this.budgetTokens, min: 2048, max: 32768, step: 2048 })
            .onChange((v: number) => { this.onChangeBudget(Math.round(v)); })
            .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
        }
        .width('100%')
        .padding(12)
        .borderRadius(14)
        .backgroundColor(ImmersiveMaterialStyle.sheetCardBackground(this.immersiveLightEnabled))
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 20 })
  }
}

interface DeviceToolMeta {
  id: string;
  label: string;
}

const QUICK_DEVICE_TOOLS: DeviceToolMeta[] = [
  { id: 'get_time_info', label: '获取系统时间' },
  { id: 'calculate', label: '安全数学计算器' },
  { id: 'clipboard_tool', label: '剪贴板读写' },
  { id: 'ask_user_input', label: '交互式询问卡片' },
  { id: 'read_chat_context', label: '读取对话上下文' },
  { id: 'calendar_query', label: '查询系统日历' },
  { id: 'calendar_create', label: '创建系统日程' },
  { id: 'get_current_location', label: '获取当前位置' },
  { id: 'browser_action', label: '内置浏览器自动化' }
];

@Component
export struct ChatToolsSheet {
  @Prop mcpServers: McpServerConfig[] = [];
  @Prop enabledMcpIds: string[] = [];
  @Prop workspaces: LocalWorkspace[] = [];
  @Prop activeWorkspaceId: string = '';
  @Prop enabledDeviceTools: string[] = [];
  @Prop permissionMode: ToolPermissionMode = 'ask';
  @Prop immersiveLightEnabled: boolean = true;

  onToggleMcp: (id: string, on: boolean) => void = () => {};
  onToggleDeviceTool: (id: string, on: boolean) => void = () => {};
  onSelectWorkspace: (id: string) => void = () => {};
  onToggleFullAccess: (full: boolean) => void = () => {};
  onOpenMoreTools: () => void = () => {};

  build() {
    Scroll() {
      Column({ space: 12 }) {
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.bolt'))
            .fontSize(19)
            .fontColor([$r('app.color.accent')])
          Column({ space: 2 }) {
            Text('完全访问模式（免弹窗审批）')
              .fontSize(14)
              .fontColor($r('app.color.ink'))
            Text('开启后当前会话直接执行工具调用')
              .fontSize(11)
              .fontColor($r('app.color.muted'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.permissionMode === 'full' })
            .onChange((v: boolean) => { this.onToggleFullAccess(v); })
            .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
        }
        .width('100%')
        .padding(12)
        .borderRadius(14)
        .backgroundColor(ImmersiveMaterialStyle.sheetCardBackground(this.immersiveLightEnabled))

        Column({ space: 4 }) {
          Text('本地内置工具')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.muted'))
            .padding({ left: 6, bottom: 2 })
          ForEach(QUICK_DEVICE_TOOLS, (item: DeviceToolMeta) => {
            Row() {
              Text(item.label)
                .fontSize(14)
                .fontColor($r('app.color.ink'))
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.enabledDeviceTools.includes(item.id) })
                .onChange((v: boolean) => { this.onToggleDeviceTool(item.id, v); })
                .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
            }
            .width('100%')
            .padding({ left: 10, right: 6, top: 4, bottom: 4 })
          }, (item: DeviceToolMeta) => item.id)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding(10)
        .borderRadius(14)
        .backgroundColor(ImmersiveMaterialStyle.sheetCardBackground(this.immersiveLightEnabled))

        if (this.mcpServers.length > 0) {
          Column({ space: 4 }) {
            Text('MCP 服务')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.muted'))
              .padding({ left: 6, bottom: 2 })
            ForEach(this.mcpServers, (srv: McpServerConfig) => {
              Row() {
                Text(srv.name)
                  .fontSize(14)
                  .fontColor($r('app.color.ink'))
                  .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.enabledMcpIds.includes(srv.id) })
                  .onChange((v: boolean) => { this.onToggleMcp(srv.id, v); })
                  .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
              }
              .width('100%')
              .padding({ left: 10, right: 6, top: 4, bottom: 4 })
            }, (srv: McpServerConfig) => srv.id)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(10)
          .borderRadius(14)
          .backgroundColor(ImmersiveMaterialStyle.sheetCardBackground(this.immersiveLightEnabled))
        }

        if (this.workspaces.length > 0) {
          Column({ space: 4 }) {
            Text('绑定工作区')
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.muted'))
              .padding({ left: 6, bottom: 2 })
            ForEach(this.workspaces, (ws: LocalWorkspace) => {
              Row() {
                Text(ws.name)
                  .fontSize(14)
                  .fontColor($r('app.color.ink'))
                  .layoutWeight(1)
                if (this.activeWorkspaceId === ws.id) {
                  SymbolGlyph($r('sys.symbol.checkmark'))
                    .fontSize(16)
                    .fontColor([$r('app.color.accent')])
                }
              }
              .width('100%')
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .borderRadius(10)
              .backgroundColor(this.activeWorkspaceId === ws.id ? $r('app.color.tint') : Color.Transparent)
              .onClick(() => {
                this.onSelectWorkspace(this.activeWorkspaceId === ws.id ? '' : ws.id);
              })
            }, (ws: LocalWorkspace) => ws.id)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(10)
          .borderRadius(14)
          .backgroundColor(ImmersiveMaterialStyle.sheetCardBackground(this.immersiveLightEnabled))
        }

        Button('管理 MCP 与工作区')
          .type(ButtonType.Normal)
          .width('100%')
          .height(42)
          .borderRadius(12)
          .backgroundColor($r('app.color.tint'))
          .fontColor($r('app.color.accent'))
          .onClick(() => { this.onOpenMoreTools(); })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 24 })
    }
    .constraintSize({ maxHeight: 520 })
    .width('100%')
  }
}
