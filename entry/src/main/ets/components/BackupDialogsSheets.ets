import { BackupScopeConfig, countSelectedBackupScope } from '../core/Models';
import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import {
  BACKUP_REMINDER_DAY_PRESETS,
  BACKUP_SCOPE_GROUP_DATA,
  BACKUP_SCOPE_GROUP_MEDIA,
  BackupScopeCategoryMeta,
  formatReminderFreqText,
  getBackupScopeCategory,
  makeAllBackupScope,
  withBackupScopeCategory
} from './BackupPanelTypes';

@Component
export struct BackupScopeSheet {
  @Link draftScope: BackupScopeConfig;
  @StorageProp('windowBottomInsetVp') winBottomInset: number = 0;
  @StorageProp('immersiveLightEnabled') immersiveLight: boolean = true;
  onSave: () => void = () => {};
  onClose: () => void = () => {};

  @Builder
  private scopeItemRow(item: BackupScopeCategoryMeta, showDivider: boolean) {
    Column() {
      Row({ space: 12 }) {
        Column() {
          SymbolGlyph(item.symbol).fontSize(18).fontColor([$r('app.color.muted')])
        }
        .width(24)
        .alignItems(HorizontalAlign.Center)

        Text(item.label)
          .fontSize(15)
          .fontColor($r('app.color.ink'))
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: getBackupScopeCategory(this.draftScope, item.key) })
          .onChange((val: boolean) => {
            this.draftScope = withBackupScopeCategory(this.draftScope, item.key, val);
          })
          .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLight))
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .onClick(() => {
        const nextVal = !getBackupScopeCategory(this.draftScope, item.key);
        this.draftScope = withBackupScopeCategory(this.draftScope, item.key, nextVal);
      })

      if (showDivider) {
        Divider().strokeWidth(0.5).color($r('app.color.line')).margin({ left: 50, right: 14 })
      }
    }
    .width('100%')
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Text('备份与导入内容')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
          .layoutWeight(1)
        Button('保存')
          .height(34)
          .fontSize(14)
          .fontColor('#FFFFFF')
          .backgroundColor($r('app.color.accent'))
          .borderRadius(17)
          .onClick(() => { this.onSave(); })
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(17).fontColor([$r('app.color.muted')])
        }
        .width(34)
        .height(34)
        .onClick(() => { this.onClose(); })
      }
      .width('100%')
      .padding({ left: 18, right: 12, top: 14, bottom: 10 })

      Scroll() {
        Column() {
          Text('选择备份和导入的内容，适用于本地、WebDAV 和 S3。导入时保留未选中的内容。技能和工作区包含各自的文件。')
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.muted'))
            .width('100%')
            .padding({ left: 4, right: 4, bottom: 8 })

          Row({ space: 10 }) {
            Text(countSelectedBackupScope(this.draftScope) + '/15')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.muted'))
              .layoutWeight(1)
            Text('全选')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.accent'))
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .onClick(() => { this.draftScope = makeAllBackupScope(true); })
            Text('全不选')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.muted'))
              .padding({ left: 8, right: 4, top: 4, bottom: 4 })
              .onClick(() => { this.draftScope = makeAllBackupScope(false); })
          }
          .width('100%')
          .padding({ left: 4, right: 4, bottom: 8 })

          Column() {
            ForEach(BACKUP_SCOPE_GROUP_MEDIA, (item: BackupScopeCategoryMeta, idx: number) => {
              this.scopeItemRow(item, idx < BACKUP_SCOPE_GROUP_MEDIA.length - 1)
            }, (item: BackupScopeCategoryMeta): string => item.key)
          }
          .width('100%')
          .backgroundColor($r('app.color.panel'))
          .borderRadius(14)
          .clip(true)

          Text('聊天附件、头像、背景图和自定义字体。恢复头像或背景图时，还需选中对应的助手、供应商或设置。')
            .fontSize(12)
            .lineHeight(17)
            .fontColor($r('app.color.muted'))
            .width('100%')
            .padding({ left: 4, right: 4, top: 8, bottom: 12 })

          Column() {
            ForEach(BACKUP_SCOPE_GROUP_DATA, (item: BackupScopeCategoryMeta, idx: number) => {
              this.scopeItemRow(item, idx < BACKUP_SCOPE_GROUP_DATA.length - 1)
            }, (item: BackupScopeCategoryMeta): string => item.key)
          }
          .width('100%')
          .backgroundColor($r('app.color.panel'))
          .borderRadius(14)
          .clip(true)
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 + this.winBottomInset })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct BackupPasswordSheet {
  @Prop passwordMode: 'create' | 'change' | 'manual' | 'unlock' = 'create';
  @Link passwordInput: string;
  @Link passwordConfirm: string;
  @Link passwordRememberDraft: boolean;
  @Link passwordShowText: boolean;
  @Link passwordRetryError: boolean;
  @StorageProp('windowBottomInsetVp') winBottomInset: number = 0;
  @StorageProp('immersiveLightEnabled') immersiveLight: boolean = true;
  onCancel: () => void = () => {};
  onSubmit: () => void = () => {};

  build() {
    Column({ space: 12 }) {
      Text(this.passwordMode === 'unlock' ? '解锁加密备份'
        : this.passwordMode === 'change' ? '更改备份密码'
        : '加密备份')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ink'))
        .width('100%')

      Text('口令')
        .fontSize(12)
        .fontColor($r('app.color.muted'))
        .width('100%')
      Row({ space: 8 }) {
        TextInput({ text: this.passwordInput, placeholder: '请输入备份口令' })
          .type(this.passwordShowText ? InputType.Normal : InputType.Password)
          .showPasswordIcon(false)
          .layoutWeight(1)
          .height(44)
          .borderRadius(12)
          .backgroundColor($r('app.color.panel'))
          .onChange((v: string) => {
            this.passwordInput = v;
            this.passwordRetryError = false;
          })
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph(this.passwordShowText ? $r('sys.symbol.eye_slash') : $r('sys.symbol.eye'))
            .fontSize(18)
            .fontColor([$r('app.color.muted')])
        }
        .width(42)
        .height(42)
        .borderRadius(12)
        .backgroundColor($r('app.color.panel'))
        .onClick(() => { this.passwordShowText = !this.passwordShowText; })
      }
      .width('100%')

      if (this.passwordMode === 'create' || this.passwordMode === 'change') {
        Text('确认口令')
          .fontSize(12)
          .fontColor($r('app.color.muted'))
          .width('100%')
        TextInput({ text: this.passwordConfirm, placeholder: '请再次输入口令' })
          .type(this.passwordShowText ? InputType.Normal : InputType.Password)
          .showPasswordIcon(false)
          .width('100%')
          .height(44)
          .borderRadius(12)
          .backgroundColor($r('app.color.panel'))
          .onChange((v: string) => { this.passwordConfirm = v; })
      }

      if (this.passwordRetryError) {
        Text('口令错误或备份已损坏，请重试。')
          .fontSize(12)
          .fontColor('#D93838')
          .width('100%')
      } else if ((this.passwordMode === 'create' || this.passwordMode === 'change') &&
        this.passwordConfirm.length > 0 && this.passwordInput !== this.passwordConfirm) {
        Text('两次输入的口令不一致。')
          .fontSize(12)
          .fontColor('#D93838')
          .width('100%')
      }

      Text(this.passwordMode === 'unlock'
        ? '请输入创建这份备份时使用的口令（兼容 Android .kbackup 格式）。'
        : '请妥善保存密码。在其他设备上恢复备份时仍需输入。')
        .fontSize(12)
        .lineHeight(17)
        .fontColor($r('app.color.muted'))
        .width('100%')

      if (this.passwordMode === 'create' || this.passwordMode === 'change') {
        Row({ space: 10 }) {
          Text('在本机记住密码')
            .fontSize(14)
            .fontColor($r('app.color.ink'))
            .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.passwordRememberDraft })
            .onChange((v: boolean) => { this.passwordRememberDraft = v; })
            .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLight))
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .borderRadius(12)
        .backgroundColor($r('app.color.panel'))
      }

      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(42)
          .fontColor($r('app.color.ink'))
          .backgroundColor($r('app.color.panel'))
          .borderRadius(12)
          .onClick(() => { this.onCancel(); })
        Button(this.passwordMode === 'unlock' ? '解锁' : '保存')
          .layoutWeight(1)
          .height(42)
          .fontColor('#FFFFFF')
          .backgroundColor($r('app.color.accent'))
          .borderRadius(12)
          .enabled(this.passwordInput.length > 0 &&
            (this.passwordMode === 'unlock' || this.passwordMode === 'manual' || this.passwordInput === this.passwordConfirm))
          .onClick(() => { this.onSubmit(); })
      }
      .width('100%')
      .padding({ top: 4 })
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 18, bottom: 24 + this.winBottomInset })
  }
}

@Component
export struct BackupImportModeSheet {
  @StorageProp('windowBottomInsetVp') winBottomInset: number = 0;
  onSelectMode: (mode: 'overwrite' | 'merge' | undefined) => void = () => {};

  build() {
    Column({ space: 12 }) {
      Text('选择导入模式')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ink'))
        .width('100%')

      Text('请选择恢复方式。备份管理中的分类开关同样适用于本次导入。')
        .fontSize(13)
        .lineHeight(18)
        .fontColor($r('app.color.muted'))
        .width('100%')

      Row({ space: 12 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.arrow_clockwise')).fontSize(20).fontColor([$r('app.color.accent')])
        }
        .width(40)
        .height(40)
        .borderRadius(10)
        .backgroundColor($r('app.color.tint'))
        .justifyContent(FlexAlign.Center)

        Column({ space: 2 }) {
          Text('完全覆盖')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
          Text('替换所选内容，保留未选内容及其他本机设置。')
            .fontSize(12)
            .lineHeight(17)
            .fontColor($r('app.color.muted'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([$r('app.color.muted')])
      }
      .width('100%')
      .padding(14)
      .borderRadius(14)
      .backgroundColor($r('app.color.panel'))
      .onClick(() => { this.onSelectMode('overwrite'); })

      Row({ space: 12 }) {
        Column() {
          SymbolGlyph($r('sys.symbol.plus')).fontSize(20).fontColor([$r('app.color.accent')])
        }
        .width(40)
        .height(40)
        .borderRadius(10)
        .backgroundColor($r('app.color.tint'))
        .justifyContent(FlexAlign.Center)

        Column({ space: 2 }) {
          Text('合并')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
          Text('保留本地数据并加入备份数据；相同会话会跳过，冲突会话会重新分配 ID。')
            .fontSize(12)
            .lineHeight(17)
            .fontColor($r('app.color.muted'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([$r('app.color.muted')])
      }
      .width('100%')
      .padding(14)
      .borderRadius(14)
      .backgroundColor($r('app.color.panel'))
      .onClick(() => { this.onSelectMode('merge'); })

      Button('取消')
        .width('100%')
        .height(42)
        .fontColor($r('app.color.ink'))
        .backgroundColor($r('app.color.panel'))
        .borderRadius(12)
        .onClick(() => { this.onSelectMode(undefined); })
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 18, bottom: 24 + this.winBottomInset })
  }
}

@Component
export struct BackupCherryWarnSheet {
  @StorageProp('windowBottomInsetVp') winBottomInset: number = 0;
  onConfirm: (ok: boolean) => void = () => {};

  build() {
    Column({ space: 14 }) {
      Text('从 Cherry Studio 导入')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ink'))
        .width('100%')

      Text('此功能目前仍处于实验阶段，可导入助手、对话、供应商（含 API Key）和文件。部分供应商需要在基础 URL 后添加 /v1 或 /v1beta。为确保数据安全，请在导入前备份。是否继续选择文件？')
        .fontSize(14)
        .lineHeight(21)
        .fontColor($r('app.color.ink'))
        .width('100%')

      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(42)
          .fontColor($r('app.color.ink'))
          .backgroundColor($r('app.color.panel'))
          .borderRadius(12)
          .onClick(() => { this.onConfirm(false); })
        Button('好的')
          .layoutWeight(1)
          .height(42)
          .fontColor('#FFFFFF')
          .backgroundColor($r('app.color.accent'))
          .borderRadius(12)
          .onClick(() => { this.onConfirm(true); })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 18, bottom: 24 + this.winBottomInset })
  }
}

@Component
export struct BackupReminderFreqSheet {
  @Prop currentDays: number = 7;
  @Link customDaysInput: string;
  @StorageProp('windowBottomInsetVp') winBottomInset: number = 0;
  onSelectDays: (days: number) => void = () => {};
  onInvalidInput: (msg: string) => void = () => {};

  build() {
    Column({ space: 8 }) {
      Text('提醒频率')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ink'))
        .width('100%')
        .padding({ bottom: 4 })

      ForEach(BACKUP_REMINDER_DAY_PRESETS, (days: number) => {
        Row({ space: 10 }) {
          Text(formatReminderFreqText(days))
            .fontSize(15)
            .fontColor($r('app.color.ink'))
            .layoutWeight(1)
          if (this.currentDays === days) {
            SymbolGlyph($r('sys.symbol.checkmark')).fontSize(17).fontColor([$r('app.color.accent')])
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .borderRadius(12)
        .backgroundColor(this.currentDays === days ? $r('app.color.tint') : $r('app.color.panel'))
        .onClick(() => { this.onSelectDays(days); })
      }, (days: number): string => String(days))

      Row({ space: 8 }) {
        Text('自定义天数')
          .fontSize(14)
          .fontColor($r('app.color.muted'))
        TextInput({ text: this.customDaysInput, placeholder: '1 - 365' })
          .type(InputType.Number)
          .layoutWeight(1)
          .height(40)
          .borderRadius(10)
          .backgroundColor($r('app.color.panel'))
          .onChange((v: string) => { this.customDaysInput = v; })
        Button('应用')
          .height(38)
          .fontSize(13)
          .fontColor('#FFFFFF')
          .backgroundColor($r('app.color.accent'))
          .borderRadius(10)
          .onClick(() => {
            const parsed = Number(this.customDaysInput);
            if (!Number.isFinite(parsed) || parsed < 1 || parsed > 365) {
              this.onInvalidInput('请输入 1 到 365 之间的整数');
              return;
            }
            this.onSelectDays(Math.round(parsed));
          })
      }
      .width('100%')
      .padding({ top: 6 })
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 18, bottom: 24 + this.winBottomInset })
  }
}

@Component
export struct BackupReminderTimeSheet {
  @Link hourInput: string;
  @Link minuteInput: string;
  @StorageProp('windowBottomInsetVp') winBottomInset: number = 0;
  onSaveMinutes: (minutesOfDay: number) => void = () => {};
  onCancel: () => void = () => {};

  build() {
    Column({ space: 12 }) {
      Text('提醒时间')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ink'))
        .width('100%')

      Row({ space: 8 }) {
        Button('09:00')
          .layoutWeight(1)
          .height(36)
          .fontSize(13)
          .fontColor($r('app.color.ink'))
          .backgroundColor($r('app.color.panel'))
          .borderRadius(10)
          .onClick(() => { this.hourInput = '9'; this.minuteInput = '00'; })
        Button('12:00')
          .layoutWeight(1)
          .height(36)
          .fontSize(13)
          .fontColor($r('app.color.ink'))
          .backgroundColor($r('app.color.panel'))
          .borderRadius(10)
          .onClick(() => { this.hourInput = '12'; this.minuteInput = '00'; })
        Button('20:00')
          .layoutWeight(1)
          .height(36)
          .fontSize(13)
          .fontColor($r('app.color.ink'))
          .backgroundColor($r('app.color.panel'))
          .borderRadius(10)
          .onClick(() => { this.hourInput = '20'; this.minuteInput = '00'; })
        Button('22:00')
          .layoutWeight(1)
          .height(36)
          .fontSize(13)
          .fontColor($r('app.color.ink'))
          .backgroundColor($r('app.color.panel'))
          .borderRadius(10)
          .onClick(() => { this.hourInput = '22'; this.minuteInput = '00'; })
      }
      .width('100%')

      Row({ space: 8 }) {
        TextInput({ text: this.hourInput, placeholder: '时 (0-23)' })
          .type(InputType.Number)
          .layoutWeight(1)
          .height(42)
          .borderRadius(10)
          .backgroundColor($r('app.color.panel'))
          .onChange((v: string) => { this.hourInput = v; })
        Text(':')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ink'))
        TextInput({ text: this.minuteInput, placeholder: '分 (0-59)' })
          .type(InputType.Number)
          .layoutWeight(1)
          .height(42)
          .borderRadius(10)
          .backgroundColor($r('app.color.panel'))
          .onChange((v: string) => { this.minuteInput = v; })
      }
      .width('100%')

      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(42)
          .fontColor($r('app.color.ink'))
          .backgroundColor($r('app.color.panel'))
          .borderRadius(12)
          .onClick(() => { this.onCancel(); })
        Button('保存')
          .layoutWeight(1)
          .height(42)
          .fontColor('#FFFFFF')
          .backgroundColor($r('app.color.accent'))
          .borderRadius(12)
          .onClick(() => {
            const h = Math.max(0, Math.min(23, Math.round(Number(this.hourInput) || 0)));
            const m = Math.max(0, Math.min(59, Math.round(Number(this.minuteInput) || 0)));
            this.onSaveMinutes(h * 60 + m);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 18, bottom: 24 + this.winBottomInset })
  }
}
