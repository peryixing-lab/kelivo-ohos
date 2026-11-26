import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { MEMORY_CATEGORIES } from '../core/MemoryLogic';
import { MemoryCategory, MemoryEntry, ModelSpec, Provider, providerEnabledModels } from '../core/Models';
import {
  PERSONA_EMOJI_CHOICES,
  formatPersonaMemDate,
  personaMemCategoryLabel,
  personaMemSourceLabel
} from './PersonaAdvancedTabs';

@Component
export struct PersonaMemoryTab {
  @Link editMemoryEnabled: boolean;
  @Link editAutoOrganizeIndex: number;
  @Link editMemoryCadence: string;
  @Link editFullMemoryTypes: MemoryCategory[];
  @Link editSmartAddModeIndex: number;
  @Link editWriteScopeIndex: number;
  @Link editPastRecall: boolean;
  @Link editGenSummary: boolean;
  @Link editSummaryEveryN: string;
  @Link asstMemLimit: number;
  @Prop pagedMemories: MemoryEntry[] = [];
  @Prop totalVisibleCount: number = 0;
  @Prop remainingCount: number = 0;
  @Prop latestOrganizeStatus: string = '';
  @Prop isOrganizing: boolean = false;
  @StorageProp('immersiveLightEnabled') immersiveLightEnabled: boolean = true;

  onOpenMemorySettings: () => void = () => {};
  onOrganizeMemory: () => void = () => {};
  onAddMemory: () => void = () => {};
  onEditMemory: (item: MemoryEntry) => void = () => {};
  onDeleteMemory: (id: string) => Promise<void> = async () => {};

  @Builder
  private renderMemoryCategory(title: string, category: MemoryCategory) {
    Row() {
      Text(title).fontSize(13).fontColor($r('app.color.ink'))
      Blank()
      Toggle({ type: ToggleType.Switch, isOn: this.editFullMemoryTypes.includes(category) })
        .onChange((enabled: boolean) => {
          const remaining = this.editFullMemoryTypes.filter((item: MemoryCategory): boolean => item !== category);
          this.editFullMemoryTypes = enabled ? remaining.concat([category]) : remaining;
        })
        .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
    }
    .width('100%')
  }

  build() {
    Column({ space: 12 }) {
      Column({ space: 10 }) {
        Row() {
          Column({ space: 2 }) {
            Text('使用长期记忆').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.ink'))
            Text('把已保存的记忆注入对话，并允许此助手写入新记忆').fontSize(11).fontColor($r('app.color.muted'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.editMemoryEnabled })
            .onChange((value: boolean) => { this.editMemoryEnabled = value; })
            .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
        }
        .width('100%')

        if (this.editMemoryEnabled) {
          Divider().color($r('app.color.line'))

          Column({ space: 6 }) {
            Text('全量注入类型').fontSize(14).fontColor($r('app.color.ink'))
            Text('选中类型会注入全部有效记忆，不受条数限制').fontSize(11).fontColor($r('app.color.muted'))
            this.renderMemoryCategory('身份信息 (identity)', 'identity')
            this.renderMemoryCategory('工作方式 (workflow)', 'workflow')
            this.renderMemoryCategory('表达风格 (voice)', 'tone')
            this.renderMemoryCategory('用户指令 (instruction)', 'instruction')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Divider().color($r('app.color.line'))

          Row() {
            Text('自动整理记忆').fontSize(14).fontColor($r('app.color.ink'))
            Blank()
            Select([{ value: '跟随全局' }, { value: '开启' }, { value: '关闭' }])
              .selected(this.editAutoOrganizeIndex)
              .value(['跟随全局', '开启', '关闭'][this.editAutoOrganizeIndex])
              .onSelect((index: number) => { this.editAutoOrganizeIndex = index; })
              .menuSystemMaterial(ImmersiveMaterialStyle.selectMenuMaterial(this.immersiveLightEnabled))
              .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
          }
          .width('100%')

          if (this.editAutoOrganizeIndex !== 2) {
            Row({ space: 8 }) {
              Text('整理频率（每 N 轮）').fontSize(14).fontColor($r('app.color.ink'))
              Blank()
              TextInput({ text: this.editMemoryCadence })
                .type(InputType.Number)
                .maxLength(2)
                .width(64)
                .height(34)
                .textAlign(TextAlign.Center)
                .backgroundColor($r('app.color.canvas'))
                .borderRadius(8)
                .onChange((value: string) => { this.editMemoryCadence = value; })
            }
            .width('100%')
          }

          Row() {
            Text('去重方式').fontSize(14).fontColor($r('app.color.ink'))
            Blank()
            Select([{ value: '批量 (Batched)' }, { value: '逐条 (Per item)' }])
              .selected(this.editSmartAddModeIndex)
              .value(['批量 (Batched)', '逐条 (Per item)'][this.editSmartAddModeIndex])
              .onSelect((index: number) => { this.editSmartAddModeIndex = index; })
              .menuSystemMaterial(ImmersiveMaterialStyle.selectMenuMaterial(this.immersiveLightEnabled))
              .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
          }
          .width('100%')

          Row() {
            Text('记忆写入范围').fontSize(14).fontColor($r('app.color.ink'))
            Blank()
            Select([{ value: '始终全局' }, { value: '一律本助手' }, { value: '由工具决定 · 默认全局' },
              { value: '由工具决定 · 默认本助手' }])
              .selected(this.editWriteScopeIndex)
              .value(['始终全局', '一律本助手', '由工具决定 · 默认全局', '由工具决定 · 默认本助手'][this.editWriteScopeIndex])
              .onSelect((index: number) => { this.editWriteScopeIndex = index; })
              .menuSystemMaterial(ImmersiveMaterialStyle.selectMenuMaterial(this.immersiveLightEnabled))
              .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
          }
          .width('100%')
        }

        Divider().color($r('app.color.line'))

        Row() {
          Column({ space: 2 }) {
            Text('允许回忆过去对话').fontSize(14).fontColor($r('app.color.ink'))
            Text('启用跨会话的对话搜索').fontSize(11).fontColor($r('app.color.muted'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.editPastRecall })
            .onChange((value: boolean) => { this.editPastRecall = value; })
            .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
        }
        .width('100%')

        Row() {
          Column({ space: 2 }) {
            Text('生成会话摘要').fontSize(14).fontColor($r('app.color.ink'))
            Text('摘要仅供对话搜索使用').fontSize(11).fontColor($r('app.color.muted'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.editGenSummary })
            .onChange((value: boolean) => { this.editGenSummary = value; })
            .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
        }
        .width('100%')

        if (this.editGenSummary) {
          Row({ space: 8 }) {
            Text('摘要更新频率（每 N 条）').fontSize(14).fontColor($r('app.color.ink'))
            Blank()
            TextInput({ text: this.editSummaryEveryN })
              .type(InputType.Number)
              .maxLength(2)
              .width(64)
              .height(34)
              .textAlign(TextAlign.Center)
              .backgroundColor($r('app.color.canvas'))
              .borderRadius(8)
              .onChange((value: string) => { this.editSummaryEveryN = value; })
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding(14)
      .alignItems(HorizontalAlign.Start)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)

      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text('记忆')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
          Text('记忆模式、模型与提示词')
            .fontSize(12)
            .fontColor($r('app.color.muted'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(15)
          .fontColor([$r('app.color.muted')])
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)
      .onClick(() => { this.onOpenMemorySettings(); })

      Column({ space: 10 }) {
        Row({ space: 6 }) {
          Column({ space: 2 }) {
            Text('本助手可见的记忆')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))
            Text(`共 ${this.totalVisibleCount} 条有效记忆`)
              .fontSize(11)
              .fontColor($r('app.color.muted'))
            if (this.latestOrganizeStatus.length > 0) {
              Text(this.latestOrganizeStatus)
                .fontSize(11)
                .fontColor($r('app.color.muted'))
            }
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button(this.isOrganizing ? '整理中…' : '整理记忆')
            .type(ButtonType.Normal)
            .height(30)
            .fontSize(12)
            .padding({ left: 10, right: 10 })
            .borderRadius(10)
            .fontColor($r('app.color.accent'))
            .backgroundColor($r('app.color.tint'))
            .enabled(!this.isOrganizing)
            .opacity(this.isOrganizing ? 0.55 : 1)
            .onClick(() => { this.onOrganizeMemory(); })

          Button('+ 添加')
            .type(ButtonType.Normal)
            .height(30)
            .fontSize(12)
            .padding({ left: 10, right: 10 })
            .borderRadius(10)
            .fontColor($r('app.color.on_accent'))
            .backgroundColor($r('app.color.accent'))
            .onClick(() => { this.onAddMemory(); })
        }
        .width('100%')

        if (this.totalVisibleCount === 0) {
          Text('当前助手暂无可见的长期记忆')
            .fontSize(12)
            .fontColor($r('app.color.muted'))
            .padding(14)
        } else {
          ForEach(this.pagedMemories, (item: MemoryEntry) => {
            Column({ space: 6 }) {
              Row({ space: 6 }) {
                Text(personaMemCategoryLabel(item.category))
                  .fontSize(11)
                  .fontColor($r('app.color.accent'))
                  .backgroundColor($r('app.color.tint'))
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .borderRadius(10)

                Text(item.assistantId ? '仅本助手' : '全局')
                  .fontSize(11)
                  .fontColor($r('app.color.muted'))
                  .backgroundColor($r('app.color.canvas'))
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .borderRadius(10)

                Blank()

                Button('编辑')
                  .type(ButtonType.Normal)
                  .height(26)
                  .fontSize(11)
                  .padding({ left: 8, right: 8 })
                  .borderRadius(6)
                  .fontColor($r('app.color.accent'))
                  .backgroundColor($r('app.color.canvas'))
                  .onClick(() => { this.onEditMemory(item); })

                Button('删除')
                  .type(ButtonType.Normal)
                  .height(26)
                  .fontSize(11)
                  .padding({ left: 8, right: 8 })
                  .borderRadius(6)
                  .fontColor($r('app.color.warning'))
                  .backgroundColor($r('app.color.canvas'))
                  .onClick(async () => {
                    await this.onDeleteMemory(item.id);
                  })
              }
              .width('100%')

              Text(item.content)
                .fontSize(13)
                .lineHeight(19)
                .fontColor($r('app.color.ink'))

              Text(`更新于 ${formatPersonaMemDate(item.updatedAt)} · ${personaMemSourceLabel(item.source)}`)
                .fontSize(11)
                .fontColor($r('app.color.muted'))
            }
            .width('100%')
            .padding(12)
            .backgroundColor($r('app.color.surface'))
            .borderRadius(12)
            .alignItems(HorizontalAlign.Start)
          }, (item: MemoryEntry) => `am_${item.id}_${item.updatedAt}`)

          if (this.remainingCount > 0) {
            Button(`加载更多（剩余 ${this.remainingCount} 条）`)
              .type(ButtonType.Normal)
              .width('100%')
              .height(38)
              .fontSize(12)
              .borderRadius(10)
              .fontColor($r('app.color.accent'))
              .backgroundColor($r('app.color.surface'))
              .onClick(() => { this.asstMemLimit += 30; })
          }
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct PersonaAvatarSheet {
  @Link editAvatar: string;
  @Prop bottomInsetVp: number = 0;
  onClose: () => void = () => {};

  build() {
    Column({ space: 12 }) {
      Text('选择预设图标，或使用助手名称首字作为头像')
        .fontSize(12)
        .fontColor($r('app.color.muted'))

      Flex({ wrap: FlexWrap.Wrap }) {
        Button('首字')
          .type(ButtonType.Normal)
          .height(38)
          .fontSize(12)
          .margin({ right: 8, bottom: 8 })
          .borderRadius(10)
          .fontColor(this.editAvatar === '' ? $r('app.color.on_accent') : $r('app.color.ink'))
          .backgroundColor(this.editAvatar === '' ? $r('app.color.accent') : $r('app.color.panel'))
          .onClick(() => {
            this.editAvatar = '';
            this.onClose();
          })

        ForEach(PERSONA_EMOJI_CHOICES, (em: string) => {
          Button(em)
            .type(ButtonType.Normal)
            .width(42)
            .height(42)
            .padding(0)
            .fontSize(21)
            .margin({ right: 8, bottom: 8 })
            .backgroundColor(this.editAvatar === em ? $r('app.color.tint') : $r('app.color.panel'))
            .borderRadius(12)
            .onClick(() => {
              this.editAvatar = em;
              this.onClose();
            })
        }, (em: string) => em)
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 4, bottom: Math.max(24, this.bottomInsetVp + 12) })
  }
}

@Component
export struct PersonaModelSheet {
  @Prop providers: Provider[] = [];
  @Link editProviderId: string;
  @Link editModelId: string;
  @Prop modelSummary: string = '';
  @Prop bottomInsetVp: number = 0;
  onClose: () => void = () => {};

  private modelsForSelectedProvider(): string[] {
    for (let i = 0; i < this.providers.length; i++) {
      const p = this.providers[i];
      if (p.id === this.editProviderId) {
        const enabled = providerEnabledModels(p);
        if (enabled.length > 0) return enabled.map((m: ModelSpec): string => m.id);
        return p.model ? [p.model] : [];
      }
    }
    return [];
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: 12 }) {
          Text(`当前选择：${this.modelSummary}`)
            .fontSize(12)
            .fontColor($r('app.color.muted'))

          Text('服务商')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))

          Flex({ wrap: FlexWrap.Wrap }) {
            Button('跟随全局')
              .type(ButtonType.Normal)
              .height(32)
              .fontSize(12)
              .margin({ right: 6, bottom: 6 })
              .borderRadius(10)
              .fontColor(this.editProviderId === '' ? $r('app.color.on_accent') : $r('app.color.ink'))
              .backgroundColor(this.editProviderId === '' ? $r('app.color.accent') : $r('app.color.panel'))
              .onClick(() => {
                this.editProviderId = '';
                this.editModelId = '';
                this.onClose();
              })

            ForEach(this.providers, (prov: Provider) => {
              Button(prov.name)
                .type(ButtonType.Normal)
                .height(32)
                .fontSize(12)
                .margin({ right: 6, bottom: 6 })
                .borderRadius(10)
                .fontColor(this.editProviderId === prov.id ? $r('app.color.on_accent') : $r('app.color.ink'))
                .backgroundColor(this.editProviderId === prov.id ? $r('app.color.accent') : $r('app.color.panel'))
                .onClick(() => {
                  this.editProviderId = prov.id;
                  this.editModelId = prov.model;
                })
            }, (prov: Provider) => prov.id)
          }
          .width('100%')

          if (this.editProviderId.length > 0 && this.modelsForSelectedProvider().length > 0) {
            Text('模型列表')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.modelsForSelectedProvider(), (mId: string) => {
                Button(mId)
                  .type(ButtonType.Normal)
                  .height(30)
                  .fontSize(12)
                  .margin({ right: 6, bottom: 6 })
                  .borderRadius(10)
                  .fontColor(this.editModelId === mId ? $r('app.color.accent') : $r('app.color.ink'))
                  .backgroundColor(this.editModelId === mId ? $r('app.color.tint') : $r('app.color.panel'))
                  .onClick(() => {
                    this.editModelId = mId;
                    this.onClose();
                  })
              }, (mId: string) => mId)
            }
            .width('100%')
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 16, right: 16, top: 4, bottom: Math.max(24, this.bottomInsetVp + 12) })
      }
      .width('100%')
      .layoutWeight(1)
      .edgeEffect(EdgeEffect.Spring)
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct PersonaMemoryEntrySheet {
  @Link asstMemCat: MemoryCategory;
  @Link asstMemScopeGlobal: boolean;
  @Link asstMemContent: string;
  @Prop bottomInsetVp: number = 0;
  onCancel: () => void = () => {};
  onSave: () => Promise<void> = async () => {};

  build() {
    Column({ space: 10 }) {
      Row({ space: 6 }) {
        ForEach(MEMORY_CATEGORIES, (cat: MemoryCategory) => {
          Button(personaMemCategoryLabel(cat))
            .type(ButtonType.Normal)
            .height(28)
            .fontSize(11)
            .borderRadius(8)
            .fontColor(this.asstMemCat === cat ? $r('app.color.on_accent') : $r('app.color.ink'))
            .backgroundColor(this.asstMemCat === cat ? $r('app.color.accent') : $r('app.color.panel'))
            .onClick(() => { this.asstMemCat = cat; })
        }, (cat: MemoryCategory) => `acat_${cat}`)
      }
      .width('100%')

      TextArea({ text: this.asstMemContent, placeholder: '输入记忆内容...' })
        .height(92)
        .borderRadius(10)
        .backgroundColor($r('app.color.panel'))
        .onChange((v: string) => { this.asstMemContent = v; })

      Row({ space: 8 }) {
        Button(this.asstMemScopeGlobal ? '范围：全局' : '范围：仅本助手')
          .type(ButtonType.Normal)
          .height(34)
          .fontSize(12)
          .borderRadius(10)
          .fontColor($r('app.color.ink'))
          .backgroundColor($r('app.color.panel'))
          .onClick(() => { this.asstMemScopeGlobal = !this.asstMemScopeGlobal; })
        Blank()
        Button('取消')
          .type(ButtonType.Normal)
          .height(34)
          .fontSize(12)
          .borderRadius(10)
          .fontColor($r('app.color.muted'))
          .backgroundColor($r('app.color.panel'))
          .onClick(() => { this.onCancel(); })
        Button('保存')
          .type(ButtonType.Normal)
          .height(34)
          .fontSize(12)
          .borderRadius(10)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor($r('app.color.accent'))
          .onClick(async () => { await this.onSave(); })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 16, right: 16, top: 4, bottom: Math.max(24, this.bottomInsetVp + 12) })
  }
}
