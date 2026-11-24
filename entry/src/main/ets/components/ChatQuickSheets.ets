import { ReasoningControl, reasoningBulbRayCount } from '../core/Reasoning';
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
  @Prop supportsBuiltinSearch: boolean = false;
  @Prop builtinSearchOn: boolean = false;
  @Prop needsResponsesHint: boolean = false;
  @Prop supportsClaudeDynamicSearch: boolean = false;
  @Prop claudeDynamicSearchOn: boolean = false;

  onToggleSearch: (enabled: boolean) => void = () => {};
  onSelectSearchService: (id: string) => void = () => {};
  onOpenSearchSettings: () => void = () => {};
  onToggleBuiltinSearch: (enabled: boolean) => void = () => {};
  onToggleClaudeDynamicSearch: (enabled: boolean) => void = () => {};
  onOpenProviderSettings: () => void = () => {};

  build() {
    Column({ space: 10 }) {
      if (this.supportsBuiltinSearch) {
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(20)
            .fontColor([$r('app.color.accent')])
          Column({ space: 2 }) {
            Text('模型内置搜索')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))
              .maxLines(1)
            Text('使用模型自带联网搜索，自动关闭外置服务')
              .fontSize(11)
              .fontColor($r('app.color.muted'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.builtinSearchOn })
            .selectedColor($r('app.color.accent'))
            .onChange((v: boolean) => {
              if (v !== this.builtinSearchOn) {
                this.onToggleBuiltinSearch(v);
              }
            })
            .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(14)
        .backgroundColor(ImmersiveMaterialStyle.sheetCardBackground(this.immersiveLightEnabled))
        .onClick(() => {
          this.onToggleBuiltinSearch(!this.builtinSearchOn);
        })

        if (this.supportsClaudeDynamicSearch && this.builtinSearchOn) {
          Row({ space: 10 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(18)
              .fontColor([$r('app.color.accent')])
            Column({ space: 2 }) {
              Text('动态过滤')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.ink'))
                .maxLines(1)
              Text('筛选搜索结果，节省 token')
                .fontSize(11)
                .fontColor($r('app.color.muted'))
                .maxLines(1)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.claudeDynamicSearchOn })
              .selectedColor($r('app.color.accent'))
              .onChange((v: boolean) => {
                if (v !== this.claudeDynamicSearchOn) {
                  this.onToggleClaudeDynamicSearch(v);
                }
              })
              .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(14)
          .backgroundColor(ImmersiveMaterialStyle.sheetCardBackground(this.immersiveLightEnabled))
          .onClick(() => {
            this.onToggleClaudeDynamicSearch(!this.claudeDynamicSearchOn);
          })
        }
      } else if (this.needsResponsesHint) {
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.magnifyingglass'))
            .fontSize(20)
            .fontColor([$r('app.color.muted')])
          Column({ space: 2 }) {
            Text('模型内置搜索')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))
              .maxLines(1)
            Text('当前服务商需在设置中切换为 OpenAI Responses 协议')
              .fontSize(11)
              .fontColor($r('app.color.muted'))
              .maxLines(2)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button('去设置')
            .type(ButtonType.Normal)
            .height(28)
            .fontSize(12)
            .borderRadius(8)
            .padding({ left: 10, right: 10 })
            .backgroundColor($r('app.color.tint'))
            .fontColor($r('app.color.accent'))
            .onClick(() => {
              this.onOpenProviderSettings();
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(14)
        .backgroundColor(ImmersiveMaterialStyle.sheetCardBackground(this.immersiveLightEnabled))
      }

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
          .selectedColor($r('app.color.accent'))
          .onChange((v: boolean) => {
            if (v !== this.searchOn) {
              this.onToggleSearch(v);
            }
          })
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
                  .fontColor([this.searchOn ? $r('app.color.accent') : $r('app.color.muted')])
              }
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .borderRadius(12)
            .backgroundColor(svc.id === this.activeSearchId && this.searchOn ? $r('app.color.tint') : Color.Transparent)
            .onClick(() => { this.onSelectSearchService(svc.id); })
          }, (svc: SearchServiceConfig) => svc.id)
        }
        .width('100%')
      }
      .constraintSize({ maxHeight: 280 })
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
  { effort: 'minimal', label: '最低推理', desc: '使用模型支持的最低思考强度' },
  { effort: 'low', label: '轻度推理', desc: '简短思考后响应' },
  { effort: 'medium', label: '标准推理', desc: '均衡思考深度与延迟' },
  { effort: 'high', label: '深度推理', desc: '适合复杂架构与推导' },
  { effort: 'xhigh', label: '极高推理', desc: '为复杂任务增加推理深度' },
  { effort: 'max', label: '极限推理', desc: '分配最大推理预算' }
];

export function reasoningBulbResource(rayCount: number): Resource {
  switch (Math.max(0, Math.min(6, Math.round(rayCount)))) {
    case 0:
      return $r('app.media.icon_reasoning_bulb_0');
    case 1:
      return $r('app.media.icon_reasoning_bulb_1');
    case 2:
      return $r('app.media.icon_reasoning_bulb_2');
    case 3:
      return $r('app.media.icon_reasoning_bulb_3');
    case 4:
      return $r('app.media.icon_reasoning_bulb_4');
    case 5:
      return $r('app.media.icon_reasoning_bulb_5');
    case 6:
      return $r('app.media.icon_reasoning_bulb_6');
    default:
      return $r('app.media.icon_reasoning_bulb_0');
  }
}

@Component
export struct ReasoningLevelSheet {
  @Prop currentEffort: ReasoningEffort = 'off';
  @Prop budgetTokens: number = 0;
  @Prop control: ReasoningControl = { dialect: 'fixed', levels: [], budgetLimit: 0 };
  @Prop immersiveLightEnabled: boolean = true;

  onSelectEffort: (effort: ReasoningEffort) => void = () => {};
  onChangeBudget: (tokens: number) => void = () => {};

  private toggleOnly(): boolean {
    return this.control.levels.length === 2 && this.control.levels.includes('off');
  }

  private visibleChoices(): ReasoningChoice[] {
    return REASONING_CHOICES.filter((item: ReasoningChoice): boolean => this.control.levels.includes(item.effort));
  }

  private badgeBgColor(effort: ReasoningEffort, selected: boolean): ResourceColor {
    if (selected) {
      return $r('app.color.accent');
    }
    return effort === 'off' ? $r('app.color.panel') : $r('app.color.tint');
  }

  private badgeIconColor(effort: ReasoningEffort, selected: boolean): ResourceColor {
    if (selected) {
      return $r('app.color.on_accent');
    }
    return effort === 'off' ? $r('app.color.muted') : $r('app.color.accent');
  }

  build() {
    Scroll() {
      Column({ space: 10 }) {
        Column({ space: 2 }) {
          ForEach(this.visibleChoices(), (item: ReasoningChoice) => {
            Row({ space: 12 }) {
              Stack({ alignContent: Alignment.Center }) {
                Image(reasoningBulbResource(reasoningBulbRayCount(this.control, item.effort)))
                  .width(22)
                  .height(22)
                  .objectFit(ImageFit.Contain)
                  .fillColor(this.badgeIconColor(item.effort, this.currentEffort === item.effort))
              }
              .width(34)
              .height(34)
              .borderRadius(10)
              .backgroundColor(this.badgeBgColor(item.effort, this.currentEffort === item.effort))

              Column({ space: 2 }) {
                Text(this.toggleOnly() && item.effort !== 'off' ? '开启思考' : item.label)
                  .fontSize(15)
                  .fontWeight(this.currentEffort === item.effort ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor($r('app.color.ink'))
                if (!this.toggleOnly()) {
                  Text(item.desc)
                    .fontSize(11)
                    .fontColor($r('app.color.muted'))
                }
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
            .padding({ left: 10, right: 12, top: 8, bottom: 8 })
            .borderRadius(12)
            .backgroundColor(this.currentEffort === item.effort ? $r('app.color.tint') : Color.Transparent)
            .onClick(() => { this.onSelectEffort(item.effort); })
          }, (item: ReasoningChoice): string => item.effort)
        }
        .width('100%')
        .borderRadius(16)
        .backgroundColor(ImmersiveMaterialStyle.sheetCardBackground(this.immersiveLightEnabled))
        .padding(6)

        if (this.currentEffort !== 'off' && this.control.budgetLimit > 0) {
          Column({ space: 6 }) {
            Row() {
              Text('思考 Token 预算')
                .fontSize(14)
                .fontColor($r('app.color.ink'))
                .layoutWeight(1)
              Text(String(this.budgetTokens))
                .fontSize(13)
                .fontColor($r('app.color.accent'))
            }
            .width('100%')

            Slider({ value: this.budgetTokens, min: 1024, max: this.control.budgetLimit, step: 1024 })
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
    .constraintSize({ maxHeight: 520 })
    .width('100%')
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
