import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import {
  STANDARD_PROFILE_FIELDS,
  StandardProfileFieldSpec,
  profileFieldKey,
  profileKeyDisplayLabel
} from '../core/MemoryLogic';
import {
  MemoryCategory,
  MemoryEntry,
  MemoryTrace,
  MemoryTraceStep,
  Persona,
  UserProfileField
} from '../core/Models';
import {
  MemoryRoleModelChoice,
  customMemoryProfileFields,
  formatMemoryDateOnly,
  formatMemoryTs,
  memoryCategoryLabel,
  memoryPersonaName,
  memorySourceLabel,
  memoryTraceStatusLabel,
  memoryTraceStepResponseText,
  memoryTraceStepStatusLabel,
  standardMemoryProfileValue
} from './MemoryPanelHelpers';

@Component
export struct MemoryModelPickerSubView {
  @Prop selectedProviderId: string = '';
  @Prop selectedModelId: string = '';
  @Prop choices: MemoryRoleModelChoice[] = [];
  onSelectFollowChat: () => Promise<void> = async () => {};
  onSelectChoice: (choice: MemoryRoleModelChoice) => Promise<void> = async () => {};

  build() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text('跟随当前对话模型')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
          Text('不指定独立记忆模型，直接使用对话所选模型')
            .fontSize(12)
            .fontColor($r('app.color.muted'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (!this.selectedProviderId || !this.selectedModelId) {
          SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16).fontColor([$r('app.color.accent')])
        }
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)
      .onClick(async () => {
        await this.onSelectFollowChat();
      })

      ForEach(this.choices, (choice: MemoryRoleModelChoice) => {
        Row({ space: 10 }) {
          Column({ space: 2 }) {
            Text(choice.modelId)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))
            Text(choice.providerName)
              .fontSize(12)
              .fontColor($r('app.color.muted'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          if (this.selectedProviderId === choice.providerId &&
            this.selectedModelId === choice.modelId) {
            SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16).fontColor([$r('app.color.accent')])
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor($r('app.color.surface'))
        .borderRadius(12)
        .onClick(async () => {
          await this.onSelectChoice(choice);
        })
      }, (choice: MemoryRoleModelChoice) => `mp_${choice.key}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct MemoryTemplateEditorSubView {
  @Prop specSubtitle: string = '';
  @Prop editLang: 'zh' | 'en' = 'zh';
  @Link editText: string;
  onSwitchLang: (lang: 'zh' | 'en') => void = () => {};
  onReset: () => Promise<void> = async () => {};
  onSave: () => Promise<void> = async () => {};

  build() {
    Column({ space: 12 }) {
      Text(this.specSubtitle)
        .fontSize(12)
        .fontColor($r('app.color.muted'))

      Row({ space: 8 }) {
        Button('中文模板')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(34)
          .fontSize(12)
          .borderRadius(10)
          .fontColor(this.editLang === 'zh' ? $r('app.color.on_accent') : $r('app.color.ink'))
          .backgroundColor(this.editLang === 'zh' ? $r('app.color.accent') : $r('app.color.surface'))
          .onClick(() => { this.onSwitchLang('zh'); })
        Button('English 模板')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(34)
          .fontSize(12)
          .borderRadius(10)
          .fontColor(this.editLang === 'en' ? $r('app.color.on_accent') : $r('app.color.ink'))
          .backgroundColor(this.editLang === 'en' ? $r('app.color.accent') : $r('app.color.surface'))
          .onClick(() => { this.onSwitchLang('en'); })
      }
      .width('100%')

      TextArea({ text: this.editText, placeholder: '输入提示词模板内容...' })
        .width('100%')
        .height(360)
        .fontSize(13)
        .borderRadius(12)
        .backgroundColor($r('app.color.surface'))
        .onChange((v: string) => {
          this.editText = v;
        })

      Row({ space: 8 }) {
        Button('恢复默认')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(40)
          .fontSize(13)
          .borderRadius(10)
          .fontColor($r('app.color.warning'))
          .backgroundColor($r('app.color.surface'))
          .onClick(async () => { await this.onReset(); })

        Button('保存模板')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(40)
          .fontSize(13)
          .borderRadius(10)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor($r('app.color.accent'))
          .onClick(async () => { await this.onSave(); })
      }
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct MemoryListSubView {
  @Prop personas: Persona[] = [];
  @Prop orphanCount: number = 0;
  @Prop scopeLabel: string = '';
  @Prop filteredTotal: number = 0;
  @Prop remainingCount: number = 0;
  @Prop pagedItems: MemoryEntry[] = [];
  @Link searchQuery: string;
  @Link filterScope: string;
  @Link filterCat: string;
  @Link filterStatus: string;
  @Link pageLimit: number;
  @Link multiSelect: boolean;
  @Link selectedIds: string[];
  onOpenAdd: () => void = () => {};
  onOpenEdit: (item: MemoryEntry) => void = () => {};
  onToggleArchive: (id: string) => Promise<void> = async () => {};
  onDeleteMemory: (id: string) => Promise<void> = async () => {};
  onCleanupOrphaned: (convertToGlobal: boolean) => Promise<void> = async () => {};
  onBatchToggleArchive: () => Promise<void> = async () => {};
  onBatchDelete: () => Promise<void> = async () => {};
  onToggleSelected: (id: string) => void = () => {};

  build() {
    Column({ space: 10 }) {
      Row({ space: 6 }) {
        TextInput({ text: this.searchQuery, placeholder: '搜索记忆关键词...' })
          .layoutWeight(1)
          .height(38)
          .borderRadius(12)
          .backgroundColor($r('app.color.surface'))
          .onChange((v: string) => {
            this.searchQuery = v;
            this.pageLimit = 40;
          })
        Button(this.multiSelect ? '取消多选' : '多选')
          .type(ButtonType.Normal)
          .height(38)
          .fontSize(12)
          .borderRadius(10)
          .fontColor(this.multiSelect ? $r('app.color.on_accent') : $r('app.color.ink'))
          .backgroundColor(this.multiSelect ? $r('app.color.accent') : $r('app.color.surface'))
          .onClick(() => {
            this.multiSelect = !this.multiSelect;
            this.selectedIds = [];
          })
        Button('+ 添加')
          .type(ButtonType.Normal)
          .height(38)
          .fontSize(12)
          .borderRadius(10)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor($r('app.color.accent'))
          .onClick(() => { this.onOpenAdd(); })
      }
      .width('100%')

      // Scope filter strip
      Scroll() {
        Row({ space: 6 }) {
          Button('全部范围')
            .type(ButtonType.Normal).height(28).fontSize(11).borderRadius(14).padding({ left: 12, right: 12 })
            .fontColor(this.filterScope === 'all' ? $r('app.color.on_accent') : $r('app.color.ink'))
            .backgroundColor(this.filterScope === 'all' ? $r('app.color.accent') : $r('app.color.surface'))
            .onClick(() => { this.filterScope = 'all'; this.pageLimit = 40; })
          Button('全局')
            .type(ButtonType.Normal).height(28).fontSize(11).borderRadius(14).padding({ left: 12, right: 12 })
            .fontColor(this.filterScope === 'global' ? $r('app.color.on_accent') : $r('app.color.ink'))
            .backgroundColor(this.filterScope === 'global' ? $r('app.color.accent') : $r('app.color.surface'))
            .onClick(() => { this.filterScope = 'global'; this.pageLimit = 40; })
          if (this.orphanCount > 0) {
            Button(`孤立 (${this.orphanCount})`)
              .type(ButtonType.Normal).height(28).fontSize(11).borderRadius(14).padding({ left: 12, right: 12 })
              .fontColor(this.filterScope === 'orphan' ? $r('app.color.on_accent') : $r('app.color.warning'))
              .backgroundColor(this.filterScope === 'orphan' ? $r('app.color.warning') : $r('app.color.surface'))
              .onClick(() => { this.filterScope = 'orphan'; this.pageLimit = 40; })
          }
          ForEach(this.personas, (p: Persona) => {
            Button(p.name)
              .type(ButtonType.Normal).height(28).fontSize(11).borderRadius(14).padding({ left: 12, right: 12 })
              .fontColor(this.filterScope === p.id ? $r('app.color.on_accent') : $r('app.color.ink'))
              .backgroundColor(this.filterScope === p.id ? $r('app.color.accent') : $r('app.color.surface'))
              .onClick(() => { this.filterScope = p.id; this.pageLimit = 40; })
          }, (p: Persona) => `fs_${p.id}`)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      // Type + Status filter strip
      Scroll() {
        Row({ space: 6 }) {
          ForEach(['all', 'identity', 'workflow', 'tone', 'instruction'], (cat: string) => {
            Button(cat === 'all' ? '全部类型' : memoryCategoryLabel(cat as MemoryCategory))
              .type(ButtonType.Normal).height(26).fontSize(11).borderRadius(8).padding({ left: 10, right: 10 })
              .fontColor(this.filterCat === cat ? $r('app.color.accent') : $r('app.color.muted'))
              .backgroundColor(this.filterCat === cat ? $r('app.color.tint') : $r('app.color.surface'))
              .onClick(() => { this.filterCat = cat; this.pageLimit = 40; })
          }, (cat: string) => `fc_${cat}`)

          Button(this.filterStatus === 'active' ? '状态：生效中' : (this.filterStatus === 'archived' ? '状态：已归档' : '状态：全部'))
            .type(ButtonType.Normal).height(26).fontSize(11).borderRadius(8).padding({ left: 10, right: 10 })
            .fontColor($r('app.color.ink'))
            .backgroundColor($r('app.color.surface'))
            .onClick(() => {
              this.filterStatus = this.filterStatus === 'active' ? 'archived' : (this.filterStatus === 'archived' ? 'all' : 'active');
              this.pageLimit = 40;
            })
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      // Orphaned assistant memories banner
      if (this.orphanCount > 0) {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
              .fontSize(18)
              .fontColor([$r('app.color.warning')])
            Text(`${this.orphanCount} 条孤立助手记忆（原助手已删除）`)
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))
              .layoutWeight(1)
          }
          .width('100%')

          Row({ space: 8 }) {
            Button('转为全局')
              .type(ButtonType.Normal)
              .layoutWeight(1)
              .height(30)
              .fontSize(12)
              .borderRadius(8)
              .fontColor($r('app.color.accent'))
              .backgroundColor($r('app.color.surface'))
              .onClick(async () => { await this.onCleanupOrphaned(true); })

            Button('一键清理')
              .type(ButtonType.Normal)
              .layoutWeight(1)
              .height(30)
              .fontSize(12)
              .borderRadius(8)
              .fontColor($r('app.color.on_accent'))
              .backgroundColor($r('app.color.warning'))
              .onClick(async () => { await this.onCleanupOrphaned(false); })
          }
          .width('100%')
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#14BB0947')
        .borderRadius(12)
      }

      if (this.multiSelect) {
        Row({ space: 8 }) {
          Text(`已选 ${this.selectedIds.length} 条`)
            .fontSize(12)
            .fontColor($r('app.color.ink'))
          Blank()
          Button(this.filterStatus === 'archived' ? '批量恢复' : '批量归档')
            .type(ButtonType.Normal)
            .height(28)
            .fontSize(11)
            .borderRadius(8)
            .fontColor($r('app.color.accent'))
            .backgroundColor($r('app.color.tint'))
            .enabled(this.selectedIds.length > 0)
            .onClick(async () => { await this.onBatchToggleArchive(); })
          Button('批量删除')
            .type(ButtonType.Normal)
            .height(28)
            .fontSize(11)
            .borderRadius(8)
            .fontColor($r('app.color.on_accent'))
            .backgroundColor($r('app.color.warning'))
            .enabled(this.selectedIds.length > 0)
            .onClick(async () => { await this.onBatchDelete(); })
        }
        .width('100%')
        .padding(10)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(10)
      }

      Text(`当前筛选（${this.scopeLabel}）：共 ${this.filteredTotal} 条`)
        .fontSize(11)
        .fontColor($r('app.color.muted'))
        .padding({ left: 2 })

      if (this.filteredTotal === 0) {
        Text('暂无匹配的记忆条目')
          .fontSize(13)
          .fontColor($r('app.color.muted'))
          .padding(24)
      } else {
        ForEach(this.pagedItems, (item: MemoryEntry) => {
          Column({ space: 8 }) {
            Row({ space: 6 }) {
              if (this.multiSelect) {
                Button(this.selectedIds.indexOf(item.id) >= 0 ? '☑' : '☐')
                  .type(ButtonType.Normal)
                  .width(28)
                  .height(26)
                  .padding(0)
                  .fontSize(13)
                  .borderRadius(6)
                  .fontColor(this.selectedIds.indexOf(item.id) >= 0 ? $r('app.color.accent') : $r('app.color.muted'))
                  .backgroundColor(Color.Transparent)
                  .onClick(() => { this.onToggleSelected(item.id); })
              }
              Text(memoryCategoryLabel(item.category))
                .fontSize(11)
                .fontColor($r('app.color.accent'))
                .backgroundColor($r('app.color.tint'))
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .borderRadius(10)

              Text(memoryPersonaName(this.personas, item.assistantId))
                .fontSize(11)
                .fontColor($r('app.color.muted'))
                .backgroundColor($r('app.color.canvas'))
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .borderRadius(10)
                .maxLines(1)

              Blank()

              Button('编辑')
                .type(ButtonType.Normal)
                .height(26)
                .fontSize(11)
                .padding({ left: 8, right: 8 })
                .borderRadius(6)
                .fontColor($r('app.color.accent'))
                .backgroundColor($r('app.color.canvas'))
                .onClick(() => { this.onOpenEdit(item); })

              Button(item.archived ? '恢复' : '归档')
                .type(ButtonType.Normal)
                .height(26)
                .fontSize(11)
                .padding({ left: 8, right: 8 })
                .borderRadius(6)
                .fontColor($r('app.color.ink'))
                .backgroundColor($r('app.color.canvas'))
                .onClick(async () => { await this.onToggleArchive(item.id); })

              Button('删除')
                .type(ButtonType.Normal)
                .height(26)
                .fontSize(11)
                .padding({ left: 8, right: 8 })
                .borderRadius(6)
                .fontColor($r('app.color.warning'))
                .backgroundColor($r('app.color.canvas'))
                .onClick(async () => { await this.onDeleteMemory(item.id); })
            }
            .width('100%')

            Text(item.content)
              .fontSize(14)
              .lineHeight(20)
              .fontColor($r('app.color.ink'))
              .copyOption(CopyOptions.LocalDevice)

            Text(`更新于 ${formatMemoryDateOnly(item.updatedAt)} · ${memorySourceLabel(item.source)}${item.archived ? ' · 已归档' : ''}`)
              .fontSize(11)
              .fontColor($r('app.color.muted'))
          }
          .alignItems(HorizontalAlign.Start)
          .padding(12)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .width('100%')
        }, (item: MemoryEntry) => `${item.id}_${item.updatedAt}_${item.archived}_${this.selectedIds.indexOf(item.id) >= 0}`)

        if (this.remainingCount > 0) {
          Button(`加载更多（剩余 ${this.remainingCount} 条）`)
            .type(ButtonType.Normal)
            .width('100%')
            .height(40)
            .fontSize(13)
            .borderRadius(12)
            .fontColor($r('app.color.accent'))
            .backgroundColor($r('app.color.surface'))
            .onClick(() => {
              this.pageLimit += 50;
            })
        }
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct MemoryProfileSubView {
  @Prop userProfile: UserProfileField[] = [];
  @Link editingProfileKey: string;
  @Link editingProfileVal: string;
  onSaveProfileField: (key: string, val: string) => Promise<void> = async () => {};
  onOpenCustomField: (key: string, val: string) => void = () => {};

  build() {
    Column({ space: 12 }) {
      Text('标准画像字段')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.muted'))
        .padding({ left: 4, top: 4 })
        .width('100%')
      Column() {
        ForEach(STANDARD_PROFILE_FIELDS, (spec: StandardProfileFieldSpec, idx: number) => {
          Column() {
            if (idx > 0) {
              Divider().color($r('app.color.line')).margin({ left: 14 })
            }
            if (this.editingProfileKey === spec.key) {
              Column({ space: 8 }) {
                Text(spec.labelZh)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.ink'))
                TextInput({ text: this.editingProfileVal, placeholder: spec.placeholderZh })
                  .height(38)
                  .borderRadius(8)
                  .backgroundColor($r('app.color.canvas'))
                  .onChange((v: string) => { this.editingProfileVal = v; })
                Row({ space: 8 }) {
                  Button('清空')
                    .type(ButtonType.Normal)
                    .height(30)
                    .fontSize(12)
                    .borderRadius(8)
                    .fontColor($r('app.color.warning'))
                    .backgroundColor($r('app.color.canvas'))
                    .onClick(async () => { await this.onSaveProfileField(spec.key, ''); })
                  Blank()
                  Button('取消')
                    .type(ButtonType.Normal)
                    .height(30)
                    .fontSize(12)
                    .borderRadius(8)
                    .fontColor($r('app.color.muted'))
                    .backgroundColor($r('app.color.canvas'))
                    .onClick(() => { this.editingProfileKey = ''; })
                  Button('保存')
                    .type(ButtonType.Normal)
                    .height(30)
                    .fontSize(12)
                    .borderRadius(8)
                    .fontColor($r('app.color.on_accent'))
                    .backgroundColor($r('app.color.accent'))
                    .onClick(async () => { await this.onSaveProfileField(spec.key, this.editingProfileVal); })
                }
                .width('100%')
              }
              .width('100%')
              .padding(14)
              .alignItems(HorizontalAlign.Start)
            } else {
              Row({ space: 10 }) {
                Column({ space: 2 }) {
                  Text(spec.labelZh)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.ink'))
                  Text(standardMemoryProfileValue(this.userProfile, spec.key).length > 0
                    ? standardMemoryProfileValue(this.userProfile, spec.key)
                    : '未设置')
                    .fontSize(13)
                    .fontColor(standardMemoryProfileValue(this.userProfile, spec.key).length > 0
                      ? $r('app.color.ink')
                      : $r('app.color.muted'))
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                SymbolGlyph($r('sys.symbol.chevron_right'))
                  .fontSize(15)
                  .fontColor([$r('app.color.muted')])
              }
              .width('100%')
              .padding({ left: 14, right: 12, top: 12, bottom: 12 })
              .onClick(() => {
                this.editingProfileKey = spec.key;
                this.editingProfileVal = standardMemoryProfileValue(this.userProfile, spec.key);
              })
            }
          }
        }, (spec: StandardProfileFieldSpec) => `stdprof_${spec.key}`)
      }
      .width('100%')
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)

      Text('自定义字段')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.muted'))
        .padding({ left: 4, top: 4 })
        .width('100%')
      ForEach(customMemoryProfileFields(this.userProfile), (f: UserProfileField) => {
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text(profileKeyDisplayLabel(profileFieldKey(f)))
              .fontSize(13)
              .fontColor($r('app.color.accent'))
            Text(f.value)
              .fontSize(14)
              .fontColor($r('app.color.ink'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button('编辑')
            .type(ButtonType.Normal)
            .height(28)
            .fontSize(11)
            .borderRadius(6)
            .fontColor($r('app.color.accent'))
            .backgroundColor($r('app.color.canvas'))
            .onClick(() => {
              this.onOpenCustomField(profileFieldKey(f), f.value);
            })
          Button('删除')
            .type(ButtonType.Normal)
            .height(28)
            .fontSize(11)
            .borderRadius(6)
            .fontColor($r('app.color.warning'))
            .backgroundColor($r('app.color.canvas'))
            .onClick(async () => {
              await this.onSaveProfileField(profileFieldKey(f), '');
            })
        }
        .width('100%')
        .padding(12)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(12)
      }, (f: UserProfileField) => `cust_${f.id}_${f.key}_${f.value}`)

      Button('+ 添加自定义字段')
        .type(ButtonType.Normal)
        .width('100%')
        .height(42)
        .fontSize(14)
        .borderRadius(12)
        .fontColor($r('app.color.accent'))
        .backgroundColor($r('app.color.surface'))
        .onClick(() => {
          this.onOpenCustomField('', '');
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct MemoryLegacySubView {
  @Prop legacyItems: string[] = [];

  build() {
    Column({ space: 10 }) {
      if (this.legacyItems.length === 0) {
        Text('暂无旧版只读记忆')
          .fontSize(13)
          .fontColor($r('app.color.muted'))
          .padding(20)
      } else {
        ForEach(this.legacyItems, (item: string, idx: number) => {
          Row({ space: 8 }) {
            Text(`${idx + 1}.`)
              .fontSize(12)
              .fontColor($r('app.color.accent'))
            Text(item)
              .fontSize(13)
              .lineHeight(19)
              .fontColor($r('app.color.ink'))
              .layoutWeight(1)
              .copyOption(CopyOptions.LocalDevice)
          }
          .width('100%')
          .padding(12)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .alignItems(VerticalAlign.Top)
        }, (item: string, idx: number) => `leg_${idx}_${item.slice(0, 16)}`)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct MemoryTracesSubView {
  @Prop memoryTraces: MemoryTrace[] = [];
  @Prop recordTraces: boolean = true;
  @StorageProp('immersiveLightEnabled') immersiveLightEnabled: boolean = true;
  @State expandedTraceId: string = '';
  onToggleRecordTraces: (v: boolean) => Promise<void> = async () => {};
  onClearTraces: () => Promise<void> = async () => {};

  build() {
    Column({ space: 10 }) {
      Row({ space: 10 }) {
        Column({ space: 2 }) {
          Text('记录流水线追踪')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
          Text('保存每轮记忆整理的步骤耗时与提示词详情')
            .fontSize(12)
            .fontColor($r('app.color.muted'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.recordTraces })
          .onChange(async (v: boolean) => {
            await this.onToggleRecordTraces(v);
          })
          .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
      }
      .width('100%')
      .padding(12)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(12)

      Row() {
        Text(`共 ${this.memoryTraces.length} 条流水线记录`)
          .fontSize(12)
          .fontColor($r('app.color.muted'))
        Blank()
        if (this.memoryTraces.length > 0) {
          Button('清空流水')
            .type(ButtonType.Normal)
            .height(28)
            .fontSize(11)
            .borderRadius(8)
            .fontColor($r('app.color.warning'))
            .backgroundColor($r('app.color.surface'))
            .onClick(async () => { await this.onClearTraces(); })
        }
      }
      .width('100%')

      if (this.memoryTraces.length === 0) {
        Text('尚无后台记忆流水线运行记录')
          .fontSize(13)
          .fontColor($r('app.color.muted'))
          .padding(20)
      } else {
        ForEach(this.memoryTraces, (tr: MemoryTrace) => {
          Column({ space: 6 }) {
            Row({ space: 6 }) {
              Text(memoryTraceStatusLabel(tr))
                .fontSize(12)
                .fontWeight(FontWeight.Medium)
                .fontColor(tr.error ? $r('app.color.warning') : (tr.gatekeeperPassed ? $r('app.color.accent') : $r('app.color.muted')))
              if (tr.trigger) {
                Text(tr.trigger === 'manual' ? '手动' : '自动')
                  .fontSize(10)
                  .fontColor($r('app.color.muted'))
                  .backgroundColor($r('app.color.canvas'))
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                  .borderRadius(6)
              }
              Text(`新增 ${tr.extractedCount} · 合并 ${tr.mergedCount}${tr.conflictCount ? ' · 冲突 ' + tr.conflictCount : ''}${tr.skippedCount ? ' · 跳过 ' + tr.skippedCount : ''}`)
                .fontSize(11)
                .fontColor($r('app.color.muted'))
              Blank()
              Text(formatMemoryTs(tr.ts))
                .fontSize(10)
                .fontColor($r('app.color.muted'))
            }
            .width('100%')

            if (tr.modelId) {
              Text(`模型：${tr.modelId}`)
                .fontSize(11)
                .fontColor($r('app.color.muted'))
            }
            Text(tr.summary)
              .fontSize(13)
              .fontColor(tr.error ? $r('app.color.warning') : $r('app.color.ink'))

            if ((tr.steps || []).length > 0) {
              Button(this.expandedTraceId === tr.id ? '收起阶段详情' : `查看 ${(tr.steps || []).length} 个阶段详情`)
                .type(ButtonType.Normal)
                .height(26)
                .fontSize(11)
                .borderRadius(6)
                .fontColor($r('app.color.accent'))
                .backgroundColor($r('app.color.tint'))
                .onClick(() => {
                  this.expandedTraceId = this.expandedTraceId === tr.id ? '' : tr.id;
                })
            }

            if (this.expandedTraceId === tr.id && (tr.steps || []).length > 0) {
              ForEach(tr.steps || [], (st: MemoryTraceStep, si: number) => {
                Column({ space: 4 }) {
                  Row({ space: 6 }) {
                    Text(st.stage)
                      .fontSize(12)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.accent'))
                    Text(memoryTraceStepStatusLabel(st))
                      .fontSize(10)
                      .fontColor((st.status === 'failed' || st.error) ? $r('app.color.warning') : $r('app.color.muted'))
                    Blank()
                    if (st.durationMs !== undefined) {
                      Text(`${st.durationMs}ms`)
                        .fontSize(10)
                        .fontColor($r('app.color.muted'))
                    }
                  }
                  .width('100%')
                  Text(st.summary)
                    .fontSize(12)
                    .fontColor($r('app.color.ink'))
                  if (memoryTraceStepResponseText(st).length > 0) {
                    Text(memoryTraceStepResponseText(st))
                      .fontSize(11)
                      .fontColor((st.status === 'failed' || st.error) ? $r('app.color.warning') : $r('app.color.muted'))
                      .copyOption(CopyOptions.LocalDevice)
                  }
                }
                .width('100%')
                .padding(8)
                .backgroundColor($r('app.color.canvas'))
                .borderRadius(8)
                .alignItems(HorizontalAlign.Start)
              }, (st: MemoryTraceStep, si: number) => `${tr.id}_st_${si}`)
            }
          }
          .alignItems(HorizontalAlign.Start)
          .padding(12)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(12)
          .width('100%')
        }, (tr: MemoryTrace) => `${tr.id}_${this.expandedTraceId === tr.id}`)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

@Component
export struct MemoryAboutSubView {
  build() {
    Column({ space: 12 }) {
      Column({ space: 6 }) {
        Text('快速开始')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ink'))
        Text('1. 在「设置 → 记忆」中选择处理模型。\n2. 在助手的「记忆」标签页开启长期记忆与自动整理。\n3. 进行几轮对话或点击「整理」，然后在记忆列表中查看提取结果。')
          .fontSize(13)
          .lineHeight(20)
          .fontColor($r('app.color.ink'))
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 6 }) {
        Text('四种记忆类型')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ink'))
        Text('• 身份 (identity)：用户背景、称呼、职业与长期偏好等稳定事实，用完整第三人称陈述。\n• 工作方式 (workflow)：偏好的工具链、流程与复盘习惯。\n• 表达风格 (voice)：偏好的语气、篇幅、句式与语言风格。\n• 用户指令 (instruction)：助手需长期遵守的固定规则，而非一次性任务。')
          .fontSize(13)
          .lineHeight(20)
          .fontColor($r('app.color.ink'))
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 6 }) {
        Text('全局与助手范围')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ink'))
        Text('全局记忆对所有启用长期记忆的助手可见；助手范围记忆仅对该助手可见。适合全局的是应跨助手跟随的个人事实，适合助手范围的是特定角色的创作设定或规则。')
          .fontSize(13)
          .lineHeight(20)
          .fontColor($r('app.color.ink'))
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(14)
      .alignItems(HorizontalAlign.Start)

      Column({ space: 6 }) {
        Text('记忆如何注入与工具协作')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ink'))
        Text('新对话开始时，每个分类最新的条目会按注入上限注入上下文。超出上限的分类会标记 mode="summary" 与总数，助手可通过 memory_search_profile / memory_read 按需检索，并通过 memory_update / memory_edit / memory_delete 实时维护。')
          .fontSize(13)
          .lineHeight(20)
          .fontColor($r('app.color.ink'))
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
