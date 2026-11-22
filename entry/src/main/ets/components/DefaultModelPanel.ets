import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { ModelDefaults, ModelSpec, Provider, isProviderConfigured, providerEnabledModels } from '../core/Models';
import { KelivoPageHeader } from './KelivoChrome';

interface RoleModelChoice {
  key: string;
  providerId: string;
  providerName: string;
  modelId: string;
}

@Component
export struct DefaultModelPanel {
  @Prop providers: Provider[] = [];
  @Prop modelDefaults: ModelDefaults = {
    chatProviderId: '', chatModelId: '', perChatModel: false,
    titleProviderId: '', titleModelId: '',
    summaryProviderId: '', summaryModelId: '',
    suggestionsProviderId: '', suggestionsModelId: '',
    compressProviderId: '', compressModelId: '',
    translateProviderId: '', translateModelId: '',
    ocrProviderId: '', ocrModelId: '',
    memoryProviderId: '', memoryModelId: ''
  };
  @Prop chatSuggestionsEnabled: boolean = false;
  @Prop immersiveLightEnabled: boolean = true;
  @Prop embeddedInNav: boolean = false;

  onSaveDefaults: (next: ModelDefaults) => Promise<void> = async () => {};
  onToggleChatSuggestions: (enabled: boolean) => Promise<void> = async () => {};
  onClose: () => void = () => {};

  @State editingRoleKey: string = '';
  @StorageProp('windowTopInsetVp') winTopInset: number = 0;

  private cloneDefaults(): ModelDefaults {
    return {
      chatProviderId: this.modelDefaults.chatProviderId || '',
      chatModelId: this.modelDefaults.chatModelId || '',
      perChatModel: this.modelDefaults.perChatModel === true,
      titleProviderId: this.modelDefaults.titleProviderId || '',
      titleModelId: this.modelDefaults.titleModelId || '',
      summaryProviderId: this.modelDefaults.summaryProviderId || '',
      summaryModelId: this.modelDefaults.summaryModelId || '',
      suggestionsProviderId: this.modelDefaults.suggestionsProviderId || '',
      suggestionsModelId: this.modelDefaults.suggestionsModelId || '',
      compressProviderId: this.modelDefaults.compressProviderId || '',
      compressModelId: this.modelDefaults.compressModelId || '',
      translateProviderId: this.modelDefaults.translateProviderId || '',
      translateModelId: this.modelDefaults.translateModelId || '',
      ocrProviderId: this.modelDefaults.ocrProviderId || '',
      ocrModelId: this.modelDefaults.ocrModelId || '',
      memoryProviderId: this.modelDefaults.memoryProviderId || '',
      memoryModelId: this.modelDefaults.memoryModelId || ''
    };
  }

  private availableRoleChoices(): RoleModelChoice[] {
    const enabled = this.providers.filter((p: Provider): boolean => p.enabled !== false && providerEnabledModels(p).length > 0);
    const configured = enabled.filter((p: Provider): boolean => isProviderConfigured(p));
    const source = configured.length > 0 ? configured : enabled;
    const out: RoleModelChoice[] = [];
    for (let i = 0; i < source.length; i++) {
      const p = source[i];
      const specs: ModelSpec[] = providerEnabledModels(p);
      for (let j = 0; j < specs.length; j++) {
        out.push({
          key: `${p.id}::${specs[j].id}`,
          providerId: p.id,
          providerName: p.name,
          modelId: specs[j].id
        });
      }
    }
    return out;
  }

  private roleDisplayLabel(provId?: string, modelId?: string, fallbackText: string = '使用当前聊天模型'): string {
    if (!provId || !modelId) {
      return fallbackText;
    }
    const prov = this.providers.find((p: Provider): boolean => p.id === provId);
    return prov ? `${modelId} (${prov.name})` : modelId;
  }

  private async assignRole(roleKey: string, provId: string, modelId: string): Promise<void> {
    const next = this.cloneDefaults();
    if (roleKey === 'chat') {
      next.chatProviderId = provId;
      next.chatModelId = modelId;
    } else if (roleKey === 'title') {
      next.titleProviderId = provId;
      next.titleModelId = modelId;
    } else if (roleKey === 'summary') {
      next.summaryProviderId = provId;
      next.summaryModelId = modelId;
    } else if (roleKey === 'suggestions') {
      next.suggestionsProviderId = provId;
      next.suggestionsModelId = modelId;
    } else if (roleKey === 'compress') {
      next.compressProviderId = provId;
      next.compressModelId = modelId;
    } else if (roleKey === 'translate') {
      next.translateProviderId = provId;
      next.translateModelId = modelId;
    } else if (roleKey === 'ocr') {
      next.ocrProviderId = provId;
      next.ocrModelId = modelId;
    } else if (roleKey === 'memory') {
      next.memoryProviderId = provId;
      next.memoryModelId = modelId;
    }
    this.editingRoleKey = '';
    await this.onSaveDefaults(next);
  }

  @Builder
  private modelRoleCard(
    roleKey: string,
    symbolRes: Resource,
    titleText: string,
    descText: string,
    provId?: string,
    modelId?: string,
    emptyText: string = '使用当前聊天模型'
  ) {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        SymbolGlyph(symbolRes)
          .fontSize(20)
          .fontColor([$r('app.color.ink')])
        Text(titleText)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
          .layoutWeight(1)
        if (provId && modelId) {
          Button('重置')
            .type(ButtonType.Normal)
            .height(26)
            .fontSize(11)
            .padding({ left: 8, right: 8 })
            .borderRadius(8)
            .backgroundColor($r('app.color.panel'))
            .fontColor($r('app.color.muted'))
            .onClick(async () => { await this.assignRole(roleKey, '', ''); })
        }
      }
      .width('100%')

      Text(descText)
        .fontSize(12)
        .lineHeight(18)
        .fontColor($r('app.color.muted'))

      Row() {
        Text(this.roleDisplayLabel(provId, modelId, emptyText))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(15)
          .fontColor([$r('app.color.muted')])
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 12, bottom: 12 })
      .borderRadius(12)
      .backgroundColor($r('app.color.panel'))
      .onClick(() => {
        this.editingRoleKey = this.editingRoleKey === roleKey ? '' : roleKey;
      })

      if (this.editingRoleKey === roleKey) {
        Flex({ wrap: FlexWrap.Wrap }) {
          Button('跟随当前模型')
            .type(ButtonType.Normal)
            .height(28)
            .fontSize(11)
            .margin({ right: 6, bottom: 6 })
            .padding({ left: 10, right: 10 })
            .borderRadius(8)
            .backgroundColor(!provId ? $r('app.color.accent') : $r('app.color.panel'))
            .fontColor(!provId ? $r('app.color.on_accent') : $r('app.color.ink'))
            .onClick(async () => { await this.assignRole(roleKey, '', ''); })

          ForEach(this.availableRoleChoices(), (choice: RoleModelChoice) => {
            Button(`${choice.providerName} · ${choice.modelId}`)
              .type(ButtonType.Normal)
              .height(28)
              .fontSize(11)
              .margin({ right: 6, bottom: 6 })
              .padding({ left: 10, right: 10 })
              .borderRadius(8)
              .backgroundColor(provId === choice.providerId && modelId === choice.modelId ? $r('app.color.accent') : $r('app.color.panel'))
              .fontColor(provId === choice.providerId && modelId === choice.modelId ? $r('app.color.on_accent') : $r('app.color.ink'))
              .onClick(async () => { await this.assignRole(roleKey, choice.providerId, choice.modelId); })
          }, (choice: RoleModelChoice) => `${roleKey}-${choice.key}`)
        }
      }
    }
    .width('100%')
    .padding(14)
    .borderRadius(16)
    .backgroundColor($r('app.color.surface'))
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      if (!this.embeddedInNav) {
        KelivoPageHeader({
          titleText: '默认模型',
          showBack: true,
          onBack: () => { this.onClose(); }
        })
      }

      Scroll() {
        Column({ space: 12 }) {
          this.modelRoleCard(
            'chat',
            $r('sys.symbol.message'),
            '默认对话模型',
            '新对话或未指定专属模型的助手默认使用的对话模型。',
            this.modelDefaults.chatProviderId,
            this.modelDefaults.chatModelId
          )

          Row({ space: 12 }) {
            SymbolGlyph($r('sys.symbol.message'))
              .fontSize(20)
              .fontColor([$r('app.color.ink')])
            Column({ space: 3 }) {
              Text('按对话记忆所选模型')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.ink'))
              Text('开启后在聊天中切换模型仅作用于当前对话；关闭则同步更新当前助手的默认模型。')
                .fontSize(12)
                .lineHeight(18)
                .fontColor($r('app.color.muted'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.modelDefaults.perChatModel === true })
              .onChange(async (v: boolean) => {
                const next = this.cloneDefaults();
                next.perChatModel = v;
                await this.onSaveDefaults(next);
              })
              .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
          }
          .width('100%')
          .padding(14)
          .borderRadius(16)
          .backgroundColor($r('app.color.surface'))

          this.modelRoleCard(
            'title',
            $r('sys.symbol.textformat'),
            '对话标题总结模型',
            '首轮问答完成后自动提炼简短会话标题，推荐快速且低成本模型。',
            this.modelDefaults.titleProviderId,
            this.modelDefaults.titleModelId
          )

          this.modelRoleCard(
            'summary',
            $r('sys.symbol.doc_text'),
            '会话摘要模型',
            '用于长对话归纳与知识提炼；推荐使用响应快速、性价比高的模型。',
            this.modelDefaults.summaryProviderId,
            this.modelDefaults.summaryModelId
          )

          Column({ space: 10 }) {
            Row({ space: 10 }) {
              SymbolGlyph($r('sys.symbol.ellipsis_bubble'))
                .fontSize(20)
                .fontColor([$r('app.color.ink')])
              Text('追问建议模型')
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.ink'))
                .layoutWeight(1)
              if (this.modelDefaults.suggestionsProviderId && this.modelDefaults.suggestionsModelId) {
                Button('重置')
                  .type(ButtonType.Normal)
                  .height(26)
                  .fontSize(11)
                  .padding({ left: 8, right: 8 })
                  .borderRadius(8)
                  .backgroundColor($r('app.color.panel'))
                  .fontColor($r('app.color.muted'))
                  .onClick(async () => { await this.assignRole('suggestions', '', ''); })
              }
              Toggle({ type: ToggleType.Switch, isOn: this.chatSuggestionsEnabled })
                .onChange(async (v: boolean) => { await this.onToggleChatSuggestions(v); })
                .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
            }
            .width('100%')

            Text('回复完成后自动生成后续追问建议气泡；默认关闭，开启后使用当前聊天模型或指定模型。')
              .fontSize(12)
              .lineHeight(18)
              .fontColor($r('app.color.muted'))

            if (this.chatSuggestionsEnabled) {
              Row() {
                Text(this.roleDisplayLabel(
                  this.modelDefaults.suggestionsProviderId,
                  this.modelDefaults.suggestionsModelId,
                  '使用当前聊天模型'
                ))
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.ink'))
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                SymbolGlyph($r('sys.symbol.chevron_down'))
                  .fontSize(15)
                  .fontColor([$r('app.color.muted')])
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 12, bottom: 12 })
              .borderRadius(12)
              .backgroundColor($r('app.color.panel'))
              .onClick(() => {
                this.editingRoleKey = this.editingRoleKey === 'suggestions' ? '' : 'suggestions';
              })

              if (this.editingRoleKey === 'suggestions') {
                Flex({ wrap: FlexWrap.Wrap }) {
                  Button('跟随当前模型')
                    .type(ButtonType.Normal)
                    .height(28)
                    .fontSize(11)
                    .margin({ right: 6, bottom: 6 })
                    .padding({ left: 10, right: 10 })
                    .borderRadius(8)
                    .backgroundColor(!this.modelDefaults.suggestionsProviderId ? $r('app.color.accent') : $r('app.color.panel'))
                    .fontColor(!this.modelDefaults.suggestionsProviderId ? $r('app.color.on_accent') : $r('app.color.ink'))
                    .onClick(async () => { await this.assignRole('suggestions', '', ''); })

                  ForEach(this.availableRoleChoices(), (choice: RoleModelChoice) => {
                    Button(`${choice.providerName} · ${choice.modelId}`)
                      .type(ButtonType.Normal)
                      .height(28)
                      .fontSize(11)
                      .margin({ right: 6, bottom: 6 })
                      .padding({ left: 10, right: 10 })
                      .borderRadius(8)
                      .backgroundColor(this.modelDefaults.suggestionsProviderId === choice.providerId && this.modelDefaults.suggestionsModelId === choice.modelId ? $r('app.color.accent') : $r('app.color.panel'))
                      .fontColor(this.modelDefaults.suggestionsProviderId === choice.providerId && this.modelDefaults.suggestionsModelId === choice.modelId ? $r('app.color.on_accent') : $r('app.color.ink'))
                      .onClick(async () => { await this.assignRole('suggestions', choice.providerId, choice.modelId); })
                  }, (choice: RoleModelChoice) => `suggestions-${choice.key}`)
                }
              }
            }
          }
          .width('100%')
          .padding(14)
          .borderRadius(16)
          .backgroundColor($r('app.color.surface'))
          .alignItems(HorizontalAlign.Start)

          this.modelRoleCard(
            'compress',
            $r('sys.symbol.rectangle_stack'),
            '上下文压缩模型',
            '当上下文达到阈值或手动压缩时生成结构化继承摘要。',
            this.modelDefaults.compressProviderId,
            this.modelDefaults.compressModelId
          )

          this.modelRoleCard(
            'translate',
            $r('sys.symbol.translate'),
            '默认翻译模型',
            '用于消息原位翻译和独立翻译页面的模型。',
            this.modelDefaults.translateProviderId,
            this.modelDefaults.translateModelId
          )

          this.modelRoleCard(
            'ocr',
            $r('sys.symbol.eye'),
            '图像识别 OCR 模型',
            '对纯图片附件执行高精度文字提取时使用的视觉模型。',
            this.modelDefaults.ocrProviderId,
            this.modelDefaults.ocrModelId
          )

          this.modelRoleCard(
            'memory',
            $r('sys.symbol.lightbulb'),
            '长期记忆提炼模型',
            '对话后门控提取用户身份、习惯与指令偏好时使用的后台模型。',
            this.modelDefaults.memoryProviderId,
            this.modelDefaults.memoryModelId
          )
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.embeddedInNav ? (56 + this.winTopInset + 4) : 8, bottom: 48 })
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
