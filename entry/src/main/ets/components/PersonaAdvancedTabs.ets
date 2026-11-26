import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { normalizeMemoryTimestamp } from '../core/MemoryLogic';
import {
  HeaderEntry,
  McpServerConfig,
  MemoryCategory,
  MemorySourceKind,
  MemorySmartAddMode,
  MemoryWriteScope,
  PresetMessage,
  QuickPhrase,
  RegexRule,
  SkillRecord,
  WorldBook
} from '../core/Models';
import { newId } from '../core/Storage';

export interface PersonaLocalToolSpec {
  id: string;
  name: string;
  desc: string;
}

export const PERSONA_BUILTIN_LOCAL_TOOLS: PersonaLocalToolSpec[] = [
  { id: 'browser_action', name: '浏览器控制', desc: '浏览并操作内置浏览器中的网页。' },
  { id: 'get_time_info', name: '时间信息', desc: '读取设备日期、星期、时间、时区与时间戳。' },
  { id: 'clipboard_tool', name: '剪切板', desc: '在明确需要时读取或写入设备剪切板文本。' },
  { id: 'text_to_speech', name: '文字转语音', desc: '允许助手使用已配置的语音播放朗读文本。' },
  { id: 'ask_user_input', name: '询问用户', desc: '允许助手提出简短问题，并在你回答后继续生成。' },
  { id: 'calculate', name: '计算器', desc: '计算数学表达式，支持加减乘除与常用科学函数。' },
  { id: 'read_chat_context', name: '读取会话上下文', desc: '读取当前或历史会话列表与消息上下文。' },
  { id: 'calendar_query', name: '查询日历', desc: '读取本设备上的日历日程，需要日历权限。' },
  { id: 'calendar_create', name: '创建日程', desc: '在你确认后于本设备创建日历日程。' },
  { id: 'get_current_location', name: '当前位置', desc: '读取本设备的一次性定位，需要定位权限。' }
];

export const PERSONA_MEMORY_POLICIES: MemoryWriteScope[] = [
  'alwaysGlobal', 'alwaysAssistant', 'toolDefaultGlobal', 'toolDefaultAssistant'
];
export const PERSONA_SMART_ADD_MODES: MemorySmartAddMode[] = ['batched', 'perItem'];
export const PERSONA_EMOJI_CHOICES: string[] = ['🤖', '💻', '✍️', '🔬', '🎓', '🌐', '🎨', '⚡', '🧭', '📚'];
export const PERSONA_BG_CHOICES: string[] = ['', '#F0F6FC', '#F3F7F2', '#FDF6EC', '#F6F0FC', '#F4F4F6'];
export const PERSONA_REASONING_OPTIONS: string[] = ['', 'off', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max'];
export const PERSONA_REASONING_LABELS: string[] = [
  '跟随全局设置', '关闭', '最低 (minimal)', '低 (low)', '中 (medium)', '高 (high)', '极高 (xhigh)', '最大 (max)'
];
export const PERSONA_PROMPT_VARS: string[] = [
  '{cur_date}', '{cur_time}', '{cur_datetime}', '{model_id}', '{model_name}',
  '{locale}', '{timezone}', '{nickname}', '{assistant_name}'
];

export function togglePersonaIdInArray(list: string[], id: string): string[] {
  const idx = list.indexOf(id);
  const next = list.slice();
  if (idx >= 0) next.splice(idx, 1);
  else next.push(id);
  return next;
}

export function personaMemCategoryLabel(cat: MemoryCategory): string {
  if (cat === 'identity') return '身份';
  if (cat === 'workflow') return '工作方式';
  if (cat === 'tone') return '表达风格';
  return '用户指令';
}

export function personaMemSourceLabel(src?: MemorySourceKind): string {
  if (src === 'tool') return '工具写入';
  if (src === 'manual') return '手动';
  return '自动提取';
}

export function formatPersonaMemDate(ts?: number): string {
  const ms = normalizeMemoryTimestamp(ts);
  const d = new Date(ms);
  if (!Number.isFinite(d.getTime())) return '';
  const pad = (n: number): string => (n < 10 ? `0${n}` : `${n}`);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

@Component
export struct PersonaPromptTab {
  @Link editPrompt: string;
  @Link editAllowConvSystemPrompt: boolean;
  @Link editAllowConvPromptInjection: boolean;
  @Link editAppendCurrentTime: boolean;
  @Link editWorldBookIds: string[];
  @Link editPresets: PresetMessage[];
  @Prop worldBooks: WorldBook[] = [];
  @StorageProp('immersiveLightEnabled') immersiveLightEnabled: boolean = true;

  @Builder
  private switchRow(title: string, subtitle: string, checked: boolean, onChangeVal: (v: boolean) => void) {
    Row({ space: 12 }) {
      Column({ space: 2 }) {
        Text(title)
          .fontSize(15)
          .fontColor($r('app.color.ink'))
        if (subtitle.length > 0) {
          Text(subtitle)
            .fontSize(12)
            .fontColor($r('app.color.muted'))
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: checked })
        .onChange((v: boolean) => { onChangeVal(v); })
        .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
    }
    .width('100%')
    .padding({ left: 14, right: 12, top: 11, bottom: 11 })
  }

  build() {
    Column({ space: 12 }) {
      // System Prompt Card
      Column({ space: 10 }) {
        Text('系统提示词')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))

        TextArea({ text: this.editPrompt, placeholder: '输入系统提示词...' })
          .height(210)
          .fontSize(13)
          .borderRadius(10)
          .backgroundColor($r('app.color.canvas'))
          .onChange((v: string) => { this.editPrompt = v; })

        Text('可用变量（点击插入）：')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.muted'))

        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(PERSONA_PROMPT_VARS, (tpl: string) => {
            Button(tpl)
              .type(ButtonType.Normal)
              .height(26)
              .fontSize(11)
              .padding({ left: 8, right: 8 })
              .margin({ right: 6, bottom: 6 })
              .borderRadius(6)
              .fontColor($r('app.color.accent'))
              .backgroundColor($r('app.color.tint'))
              .onClick(() => {
                this.editPrompt = this.editPrompt.length > 0 ? `${this.editPrompt}${tpl}` : tpl;
              })
          }, (tpl: string) => tpl)
        }
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)
      .alignItems(HorizontalAlign.Start)

      // Per-conversation Prompt Toggles Card
      Column() {
        this.switchRow(
          '独立对话系统提示',
          '允许每个对话设置自己的系统提示词。',
          this.editAllowConvSystemPrompt,
          (v: boolean) => { this.editAllowConvSystemPrompt = v; }
        )
        Divider().color($r('app.color.line')).margin({ left: 14 })
        this.switchRow(
          '独立对话指令注入',
          '每个对话单独选择指令注入和世界书，默认不选中。',
          this.editAllowConvPromptInjection,
          (v: boolean) => { this.editAllowConvPromptInjection = v; }
        )
        Divider().color($r('app.color.line')).margin({ left: 14 })
        this.switchRow(
          '追加当前时间',
          '在每条用户消息末尾追加发送时刻，不影响缓存。',
          this.editAppendCurrentTime,
          (v: boolean) => { this.editAppendCurrentTime = v; }
        )
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)

      if (this.worldBooks.length > 0) {
        Column({ space: 8 }) {
          Text('绑定世界书 (不选则跟随全部已启用世界书)')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.worldBooks, (wb: WorldBook) => {
              Button(wb.name)
                .type(ButtonType.Normal).height(28).fontSize(11).margin({ right: 6, bottom: 6 }).borderRadius(8)
                .fontColor(this.editWorldBookIds.indexOf(wb.id) >= 0 ? $r('app.color.on_accent') : $r('app.color.ink'))
                .backgroundColor(this.editWorldBookIds.indexOf(wb.id) >= 0 ? $r('app.color.accent') : $r('app.color.canvas'))
                .onClick(() => { this.editWorldBookIds = togglePersonaIdInArray(this.editWorldBookIds, wb.id); })
            }, (wb: WorldBook) => wb.id)
          }
        }
        .width('100%')
        .padding(14)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(14)
        .alignItems(HorizontalAlign.Start)
      }

      // Preset Messages Card
      Row() {
        Text('预设对话消息 (Few-shot / 开场前置)')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
        Blank()
        Button('+ 添加')
          .type(ButtonType.Normal)
          .height(28)
          .fontSize(11)
          .borderRadius(8)
          .fontColor($r('app.color.accent'))
          .backgroundColor($r('app.color.tint'))
          .onClick(() => {
            const next = this.editPresets.slice();
            next.push({ id: 'pm_' + newId(), role: 'user', content: '' });
            this.editPresets = next;
          })
      }
      .width('100%')

      ForEach(this.editPresets, (pm: PresetMessage, idx: number) => {
        Column({ space: 6 }) {
          Row({ space: 6 }) {
            Button(pm.role)
              .type(ButtonType.Normal).height(26).fontSize(11).borderRadius(6)
              .fontColor($r('app.color.accent')).backgroundColor($r('app.color.tint'))
              .onClick(() => {
                const next = this.editPresets.slice();
                const nextRole: 'user' | 'assistant' | 'system' =
                  pm.role === 'user' ? 'assistant' : (pm.role === 'assistant' ? 'system' : 'user');
                next[idx] = { id: pm.id, role: nextRole, content: pm.content };
                this.editPresets = next;
              })
            Blank()
            Button('删除')
              .type(ButtonType.Normal).height(26).fontSize(11).borderRadius(6)
              .fontColor($r('app.color.warning')).backgroundColor($r('app.color.canvas'))
              .onClick(() => {
                const next = this.editPresets.slice();
                next.splice(idx, 1);
                this.editPresets = next;
              })
          }
          .width('100%')

          TextArea({ text: pm.content, placeholder: '消息内容...' })
            .height(64).borderRadius(8).backgroundColor($r('app.color.canvas'))
            .onChange((v: string) => {
              const next = this.editPresets.slice();
              next[idx] = { id: pm.id, role: pm.role, content: v };
              this.editPresets = next;
            })
        }
        .padding(10)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(12)
        .width('100%')
      }, (pm: PresetMessage) => pm.id)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}

@Component
export struct PersonaLocalToolsTab {
  @Link editBuiltinTools: string[];
  @StorageProp('immersiveLightEnabled') immersiveLightEnabled: boolean = true;

  build() {
    Column({ space: 10 }) {
      Text('为该助手启用的设备本地工具')
        .fontSize(12)
        .fontColor($r('app.color.muted'))
        .padding({ left: 4 })

      Column() {
        ForEach(PERSONA_BUILTIN_LOCAL_TOOLS, (tool: PersonaLocalToolSpec, idx: number) => {
          Column() {
            if (idx > 0) {
              Divider().color($r('app.color.line')).margin({ left: 14 })
            }
            Row({ space: 12 }) {
              Column({ space: 2 }) {
                Text(tool.name).fontSize(15).fontColor($r('app.color.ink'))
                Text(tool.desc).fontSize(12).fontColor($r('app.color.muted'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Toggle({ type: ToggleType.Switch, isOn: this.editBuiltinTools.indexOf(tool.id) >= 0 })
                .onChange((enabled: boolean) => {
                  const has = this.editBuiltinTools.indexOf(tool.id) >= 0;
                  if (enabled !== has) {
                    this.editBuiltinTools = togglePersonaIdInArray(this.editBuiltinTools, tool.id);
                  }
                })
                .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
            }
            .width('100%')
            .padding({ left: 14, right: 12, top: 12, bottom: 12 })
          }
        }, (tool: PersonaLocalToolSpec) => `lt_${tool.id}`)
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct PersonaSkillsTab {
  @Prop skills: SkillRecord[] = [];
  @Link editSkillIds: string[];
  @StorageProp('immersiveLightEnabled') immersiveLightEnabled: boolean = true;

  build() {
    Column({ space: 10 }) {
      Text('为该助手启用的 Agent Skills 技能包')
        .fontSize(12)
        .fontColor($r('app.color.muted'))
        .padding({ left: 4 })

      if (this.skills.length === 0) {
        Text('暂无可用技能，可在「设置 → 技能」中添加或导入')
          .fontSize(13)
          .fontColor($r('app.color.muted'))
          .padding(16)
      } else {
        Column() {
          ForEach(this.skills, (sk: SkillRecord, idx: number) => {
            Column() {
              if (idx > 0) {
                Divider().color($r('app.color.line')).margin({ left: 14 })
              }
              Row({ space: 12 }) {
                Column({ space: 2 }) {
                  Text(sk.name).fontSize(15).fontColor($r('app.color.ink'))
                  Text(sk.description).fontSize(12).fontColor($r('app.color.muted')).maxLines(2)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: this.editSkillIds.indexOf(sk.id) >= 0 })
                  .onChange((enabled: boolean) => {
                    const has = this.editSkillIds.indexOf(sk.id) >= 0;
                    if (enabled !== has) {
                      this.editSkillIds = togglePersonaIdInArray(this.editSkillIds, sk.id);
                    }
                  })
                  .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
              }
              .width('100%')
              .padding({ left: 14, right: 12, top: 12, bottom: 12 })
            }
          }, (sk: SkillRecord) => `sk_${sk.id}`)
        }
        .width('100%')
        .backgroundColor($r('app.color.surface'))
        .borderRadius(14)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct PersonaMcpTab {
  @Prop mcpServers: McpServerConfig[] = [];
  @Link editAllowConvMcp: boolean;
  @Link editMcpIds: string[];
  @StorageProp('immersiveLightEnabled') immersiveLightEnabled: boolean = true;

  build() {
    Column({ space: 12 }) {
      Column() {
        Row({ space: 12 }) {
          Column({ space: 2 }) {
            Text('允许对话自定义 MCP')
              .fontSize(15)
              .fontColor($r('app.color.ink'))
            Text('开启后，对话可单独选择 MCP 服务器；未自定义时跟随助手设置。')
              .fontSize(12)
              .fontColor($r('app.color.muted'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.editAllowConvMcp })
            .onChange((v: boolean) => { this.editAllowConvMcp = v; })
            .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
        }
        .width('100%')
        .padding({ left: 14, right: 12, top: 11, bottom: 11 })
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)

      Text('MCP 服务器（为该助手启用的服务）')
        .fontSize(12)
        .fontColor($r('app.color.muted'))
        .padding({ left: 4 })

      if (this.mcpServers.length === 0) {
        Text('尚未添加 MCP 服务器，可在「设置 → MCP」中配置')
          .fontSize(13)
          .fontColor($r('app.color.muted'))
          .padding(16)
      } else {
        Column() {
          ForEach(this.mcpServers, (srv: McpServerConfig, idx: number) => {
            Column() {
              if (idx > 0) {
                Divider().color($r('app.color.line')).margin({ left: 14 })
              }
              Row({ space: 12 }) {
                Column({ space: 2 }) {
                  Text(srv.name).fontSize(15).fontColor($r('app.color.ink'))
                  Text(srv.endpoint).fontSize(11).fontColor($r('app.color.muted')).maxLines(1)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: this.editMcpIds.indexOf(srv.id) >= 0 })
                  .onChange((enabled: boolean) => {
                    const has = this.editMcpIds.indexOf(srv.id) >= 0;
                    if (enabled !== has) {
                      this.editMcpIds = togglePersonaIdInArray(this.editMcpIds, srv.id);
                    }
                  })
                  .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
              }
              .width('100%')
              .padding({ left: 14, right: 12, top: 12, bottom: 12 })
            }
          }, (srv: McpServerConfig) => `mcp_${srv.id}`)
        }
        .width('100%')
        .backgroundColor($r('app.color.surface'))
        .borderRadius(14)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct PersonaQuickPhrasesTab {
  @Link editQuickPhrases: QuickPhrase[];

  build() {
    Column({ space: 10 }) {
      Row() {
        Text('管理该助手的专属快捷短语')
          .fontSize(13)
          .fontColor($r('app.color.muted'))
        Blank()
        Button('+ 添加快捷短语')
          .type(ButtonType.Normal)
          .height(30)
          .fontSize(12)
          .borderRadius(10)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor($r('app.color.accent'))
          .onClick(() => {
            const next = this.editQuickPhrases.slice();
            next.push({ id: 'qp_' + newId(), title: '快捷短语', content: '', scope: 'assistant' });
            this.editQuickPhrases = next;
          })
      }
      .width('100%')

      if (this.editQuickPhrases.length === 0) {
        Text('尚未添加快捷短语，点击右上角按钮添加。')
          .fontSize(13)
          .fontColor($r('app.color.muted'))
          .padding(16)
      } else {
        ForEach(this.editQuickPhrases, (qp: QuickPhrase, idx: number) => {
          Column({ space: 6 }) {
            Row({ space: 6 }) {
              TextInput({ text: qp.title, placeholder: '短语标题' })
                .layoutWeight(1).height(36).borderRadius(8).backgroundColor($r('app.color.canvas'))
                .onChange((v: string) => {
                  const next = this.editQuickPhrases.slice();
                  next[idx] = { id: qp.id, title: v, content: qp.content, scope: 'assistant' };
                  this.editQuickPhrases = next;
                })
              Button('删除')
                .type(ButtonType.Normal).height(32).fontSize(11).borderRadius(8)
                .fontColor($r('app.color.warning')).backgroundColor($r('app.color.canvas'))
                .onClick(() => {
                  const next = this.editQuickPhrases.slice();
                  next.splice(idx, 1);
                  this.editQuickPhrases = next;
                })
            }
            TextArea({ text: qp.content, placeholder: '短语内容...' })
              .height(64).borderRadius(8).backgroundColor($r('app.color.canvas'))
              .onChange((v: string) => {
                const next = this.editQuickPhrases.slice();
                next[idx] = { id: qp.id, title: qp.title, content: v, scope: 'assistant' };
                this.editQuickPhrases = next;
              })
          }
          .padding(12)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .width('100%')
        }, (qp: QuickPhrase) => qp.id)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct PersonaCustomRequestTab {
  @Link editHeaderRows: HeaderEntry[];
  @Link editBodyJson: string;

  build() {
    Column({ space: 12 }) {
      Column({ space: 8 }) {
        Row() {
          Text('自定义 Header')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
          Blank()
          Button('+ 添加 Header')
            .type(ButtonType.Normal)
            .height(28)
            .fontSize(11)
            .borderRadius(8)
            .fontColor($r('app.color.accent'))
            .backgroundColor($r('app.color.tint'))
            .onClick(() => {
              const next = this.editHeaderRows.slice();
              next.push({ key: '', value: '' });
              this.editHeaderRows = next;
            })
        }
        .width('100%')

        if (this.editHeaderRows.length === 0) {
          Text('未添加 Header')
            .fontSize(12)
            .fontColor($r('app.color.muted'))
        } else {
          ForEach(this.editHeaderRows, (hdr: HeaderEntry, idx: number) => {
            Row({ space: 6 }) {
              TextInput({ text: hdr.key, placeholder: 'Header 名' })
                .layoutWeight(1).height(36).borderRadius(8).backgroundColor($r('app.color.canvas'))
                .onChange((v: string) => {
                  const next = this.editHeaderRows.slice();
                  next[idx] = { key: v, value: hdr.value };
                  this.editHeaderRows = next;
                })
              TextInput({ text: hdr.value, placeholder: 'Header 值' })
                .layoutWeight(1).height(36).borderRadius(8).backgroundColor($r('app.color.canvas'))
                .onChange((v: string) => {
                  const next = this.editHeaderRows.slice();
                  next[idx] = { key: hdr.key, value: v };
                  this.editHeaderRows = next;
                })
              Button('删除')
                .type(ButtonType.Normal).height(32).fontSize(11).borderRadius(8)
                .fontColor($r('app.color.warning')).backgroundColor($r('app.color.canvas'))
                .onClick(() => {
                  const next = this.editHeaderRows.slice();
                  next.splice(idx, 1);
                  this.editHeaderRows = next;
                })
            }
            .width('100%')
          }, (hdr: HeaderEntry, idx: number) => `hdr_${idx}`)
        }
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 8 }) {
        Text('自定义 Body (JSON 对象)')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
        TextArea({ text: this.editBodyJson, placeholder: '{"presence_penalty": 0.2}' })
          .height(100)
          .fontSize(12)
          .borderRadius(8)
          .backgroundColor($r('app.color.canvas'))
          .onChange((v: string) => { this.editBodyJson = v; })
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct PersonaRegexTab {
  @Link editRegexRules: RegexRule[];

  build() {
    Column({ space: 10 }) {
      Row() {
        Text('为用户/助手消息配置正则替换规则')
          .fontSize(13)
          .fontColor($r('app.color.muted'))
        Blank()
        Button('+ 添加正则规则')
          .type(ButtonType.Normal)
          .height(30)
          .fontSize(12)
          .borderRadius(10)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor($r('app.color.accent'))
          .onClick(() => {
            const next = this.editRegexRules.slice();
            next.push({
              id: 'rx_' + newId(),
              name: '新正则',
              pattern: '',
              replacement: '',
              flags: 'g',
              scope: 'output',
              enabled: true
            });
            this.editRegexRules = next;
          })
      }
      .width('100%')

      if (this.editRegexRules.length === 0) {
        Text('未配置正则规则，点击右上角按钮添加。')
          .fontSize(13)
          .fontColor($r('app.color.muted'))
          .padding(16)
      } else {
        ForEach(this.editRegexRules, (rule: RegexRule, idx: number) => {
          Column({ space: 6 }) {
            Row({ space: 6 }) {
              TextInput({ text: rule.name, placeholder: '规则名' })
                .layoutWeight(1).height(34).borderRadius(8).backgroundColor($r('app.color.canvas'))
                .onChange((v: string) => {
                  const next = this.editRegexRules.slice();
                  next[idx] = {
                    id: rule.id, name: v, pattern: rule.pattern, replacement: rule.replacement,
                    flags: rule.flags, scope: rule.scope, enabled: rule.enabled
                  };
                  this.editRegexRules = next;
                })
              Button(rule.scope)
                .type(ButtonType.Normal).height(30).fontSize(11).borderRadius(6)
                .fontColor($r('app.color.accent')).backgroundColor($r('app.color.tint'))
                .onClick(() => {
                  const next = this.editRegexRules.slice();
                  const nextScope: 'input' | 'output' | 'display' =
                    rule.scope === 'output' ? 'display' : (rule.scope === 'display' ? 'input' : 'output');
                  next[idx] = {
                    id: rule.id, name: rule.name, pattern: rule.pattern, replacement: rule.replacement,
                    flags: rule.flags, scope: nextScope, enabled: rule.enabled
                  };
                  this.editRegexRules = next;
                })
              Button('删除')
                .type(ButtonType.Normal).height(30).fontSize(11).borderRadius(6)
                .fontColor($r('app.color.warning')).backgroundColor($r('app.color.canvas'))
                .onClick(() => {
                  const next = this.editRegexRules.slice();
                  next.splice(idx, 1);
                  this.editRegexRules = next;
                })
            }
            Row({ space: 6 }) {
              TextInput({ text: rule.pattern, placeholder: '正则表达式 (Pattern)' })
                .layoutWeight(2).height(34).borderRadius(8).backgroundColor($r('app.color.canvas'))
                .onChange((v: string) => {
                  const next = this.editRegexRules.slice();
                  next[idx] = {
                    id: rule.id, name: rule.name, pattern: v, replacement: rule.replacement,
                    flags: rule.flags, scope: rule.scope, enabled: rule.enabled
                  };
                  this.editRegexRules = next;
                })
              TextInput({ text: rule.flags, placeholder: 'flags' })
                .width(56).height(34).borderRadius(8).backgroundColor($r('app.color.canvas'))
                .onChange((v: string) => {
                  const next = this.editRegexRules.slice();
                  next[idx] = {
                    id: rule.id, name: rule.name, pattern: rule.pattern, replacement: rule.replacement,
                    flags: v, scope: rule.scope, enabled: rule.enabled
                  };
                  this.editRegexRules = next;
                })
            }
            TextInput({ text: rule.replacement, placeholder: '替换为...' })
              .height(34).borderRadius(8).backgroundColor($r('app.color.canvas'))
              .onChange((v: string) => {
                const next = this.editRegexRules.slice();
                next[idx] = {
                  id: rule.id, name: rule.name, pattern: rule.pattern, replacement: v,
                  flags: rule.flags, scope: rule.scope, enabled: rule.enabled
                };
                this.editRegexRules = next;
              })
          }
          .padding(10)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .width('100%')
        }, (rule: RegexRule) => rule.id)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }
}
