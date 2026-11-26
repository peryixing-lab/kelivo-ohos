import {
  BackupPreferencesConfig,
  LocalSnapshotMeta,
  defaultBackupConfig
} from '../core/Models';
import { formatBytesReadable } from '../core/BackupManager';
import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { KelivoSectionHeader } from './KelivoChrome';
import {
  BACKUP_COPY_INTERVAL_PRESETS,
  BACKUP_COPY_KEEP_PRESETS,
  BACKUP_COPY_MAX_BYTES_PRESETS,
  RemoteBackupEntry,
  cloneBackupPreferences,
  formatBackupTimeFull,
  formatCopyIntervalText
} from './BackupPanelTypes';

@Component
export struct BackupLocalCopiesSheet {
  @Prop cfg: BackupPreferencesConfig = defaultBackupConfig();
  @Prop snapshots: LocalSnapshotMeta[] = [];
  @Prop busy: boolean = false;
  @Prop summaryText: string = '';
  @State copiesPicker: '' | 'freq' | 'keep' | 'max' = '';
  @StorageProp('windowBottomInsetVp') winBottomInset: number = 0;
  @StorageProp('immersiveLightEnabled') immersiveLight: boolean = true;
  onUpdateCfg: (next: BackupPreferencesConfig) => void = () => {};
  onTakeCopyNow: () => void = () => {};
  onRestoreCopy: (snap: LocalSnapshotMeta) => void = () => {};
  onExportCopy: (snap: LocalSnapshotMeta) => void = () => {};
  onDeleteCopy: (snap: LocalSnapshotMeta) => void = () => {};
  onTogglePin: (snap: LocalSnapshotMeta) => void = () => {};
  onClose: () => void = () => {};

  @Builder
  private navRow(
    symbol: Resource,
    label: string,
    detail: string,
    showDivider: boolean,
    onAction: () => void
  ) {
    Column() {
      Row({ space: 12 }) {
        Column() {
          SymbolGlyph(symbol)
            .fontSize(20)
            .fontColor([$r('app.color.ink')])
        }
        .width(28)
        .alignItems(HorizontalAlign.Center)

        Text(label)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        if (detail.length > 0) {
          Text(detail)
            .fontSize(13)
            .fontColor($r('app.color.muted'))
        }

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(15)
          .fontColor([$r('app.color.muted')])
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 13, bottom: 13 })
      .enabled(!this.busy)
      .opacity(this.busy ? 0.55 : 1.0)
      .onClick(() => {
        if (!this.busy) onAction();
      })

      if (showDivider) {
        Divider()
          .strokeWidth(0.6)
          .color($r('app.color.line'))
          .margin({ left: 54, right: 12 })
      }
    }
    .width('100%')
  }

  @Builder
  private switchRow(
    symbol: Resource,
    label: string,
    isOn: boolean,
    showDivider: boolean,
    onChangeVal: (v: boolean) => void
  ) {
    Column() {
      Row({ space: 12 }) {
        Column() {
          SymbolGlyph(symbol)
            .fontSize(20)
            .fontColor([$r('app.color.ink')])
        }
        .width(28)
        .alignItems(HorizontalAlign.Center)

        Text(label)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn })
          .enabled(!this.busy)
          .onChange((val: boolean) => {
            if (val === isOn) return;
            onChangeVal(val);
          })
          .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLight))
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 10 })

      if (showDivider) {
        Divider()
          .strokeWidth(0.6)
          .color($r('app.color.line'))
          .margin({ left: 54, right: 12 })
      }
    }
    .width('100%')
  }

  build() {
    Column() {
      Row({ space: 10 }) {
        Text('本地副本')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
          .layoutWeight(1)
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(17).fontColor([$r('app.color.muted')])
        }
        .width(34)
        .height(34)
        .onClick(() => { this.onClose(); })
      }
      .width('100%')
      .padding({ left: 18, right: 12, top: 14, bottom: 8 })

      Scroll() {
        Column() {
          KelivoSectionHeader({ titleText: '本地副本', topSpacing: 4 })
          Column() {
            this.switchRow(
              $r('sys.symbol.checkmark_shield'),
              '保留本地副本',
              this.cfg.localCopiesEnabled,
              this.cfg.localCopiesEnabled,
              (v: boolean) => {
                const next = cloneBackupPreferences(this.cfg);
                next.localCopiesEnabled = v;
                this.onUpdateCfg(next);
              }
            )
            if (this.cfg.localCopiesEnabled) {
              this.navRow(
                $r('sys.symbol.arrow_clockwise'),
                '备份频率',
                formatCopyIntervalText(this.cfg.localCopiesIntervalDays),
                true,
                () => { this.copiesPicker = this.copiesPicker === 'freq' ? '' : 'freq'; }
              )
              if (this.copiesPicker === 'freq') {
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(BACKUP_COPY_INTERVAL_PRESETS, (d: number) => {
                    Text(formatCopyIntervalText(d))
                      .fontSize(12)
                      .fontColor(this.cfg.localCopiesIntervalDays === d ? '#FFFFFF' : $r('app.color.ink'))
                      .backgroundColor(this.cfg.localCopiesIntervalDays === d ? $r('app.color.accent') : $r('app.color.tint'))
                      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                      .borderRadius(12)
                      .margin({ right: 6, bottom: 6 })
                      .onClick(() => {
                        const next = cloneBackupPreferences(this.cfg);
                        next.localCopiesIntervalDays = d;
                        this.onUpdateCfg(next);
                        this.copiesPicker = '';
                      })
                  }, (d: number): string => String(d))
                }
                .width('100%')
                .padding({ left: 54, right: 14, top: 6, bottom: 8 })
              }

              this.navRow(
                $r('sys.symbol.externaldrive'),
                '保留份数',
                this.cfg.localCopiesKeepRecent + ' 份',
                true,
                () => { this.copiesPicker = this.copiesPicker === 'keep' ? '' : 'keep'; }
              )
              if (this.copiesPicker === 'keep') {
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(BACKUP_COPY_KEEP_PRESETS, (cnt: number) => {
                    Text(cnt + ' 份')
                      .fontSize(12)
                      .fontColor(this.cfg.localCopiesKeepRecent === cnt ? '#FFFFFF' : $r('app.color.ink'))
                      .backgroundColor(this.cfg.localCopiesKeepRecent === cnt ? $r('app.color.accent') : $r('app.color.tint'))
                      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                      .borderRadius(12)
                      .margin({ right: 6, bottom: 6 })
                      .onClick(() => {
                        const next = cloneBackupPreferences(this.cfg);
                        next.localCopiesKeepRecent = cnt;
                        this.onUpdateCfg(next);
                        this.copiesPicker = '';
                      })
                  }, (cnt: number): string => String(cnt))
                }
                .width('100%')
                .padding({ left: 54, right: 14, top: 6, bottom: 8 })
              }

              this.switchRow(
                $r('sys.symbol.calendar'),
                '保留每周副本',
                this.cfg.localCopiesKeepWeekly,
                true,
                (v: boolean) => {
                  const next = cloneBackupPreferences(this.cfg);
                  next.localCopiesKeepWeekly = v;
                  this.onUpdateCfg(next);
                }
              )
              this.switchRow(
                $r('sys.symbol.calendar'),
                '保留每月副本',
                this.cfg.localCopiesKeepMonthly,
                true,
                (v: boolean) => {
                  const next = cloneBackupPreferences(this.cfg);
                  next.localCopiesKeepMonthly = v;
                  this.onUpdateCfg(next);
                }
              )
              this.navRow(
                $r('sys.symbol.externaldrive'),
                '占用上限',
                this.cfg.localCopiesMaxBytes <= 0 ? '不限制' : formatBytesReadable(this.cfg.localCopiesMaxBytes),
                false,
                () => { this.copiesPicker = this.copiesPicker === 'max' ? '' : 'max'; }
              )
              if (this.copiesPicker === 'max') {
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(BACKUP_COPY_MAX_BYTES_PRESETS, (lim: number) => {
                    Text(lim <= 0 ? '不限制' : formatBytesReadable(lim))
                      .fontSize(12)
                      .fontColor(this.cfg.localCopiesMaxBytes === lim ? '#FFFFFF' : $r('app.color.ink'))
                      .backgroundColor(this.cfg.localCopiesMaxBytes === lim ? $r('app.color.accent') : $r('app.color.tint'))
                      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                      .borderRadius(12)
                      .margin({ right: 6, bottom: 6 })
                      .onClick(() => {
                        const next = cloneBackupPreferences(this.cfg);
                        next.localCopiesMaxBytes = lim;
                        this.onUpdateCfg(next);
                        this.copiesPicker = '';
                      })
                  }, (lim: number): string => String(lim))
                }
                .width('100%')
                .padding({ left: 54, right: 14, top: 6, bottom: 10 })
              }
            }
          }
          .width('100%')
          .backgroundColor($r('app.color.panel'))
          .borderRadius(14)
          .clip(true)

          Text(this.cfg.localCopiesLastError
            ? ('上次备份失败：' + this.cfg.localCopiesLastError)
            : (this.cfg.localCopiesLastSuccessAt
              ? ('上次成功备份：' + formatBackupTimeFull(this.cfg.localCopiesLastSuccessAt))
              : '还没有自动保存过副本'))
            .fontSize(12)
            .fontColor(this.cfg.localCopiesLastError ? '#D93838' : $r('app.color.muted'))
            .width('100%')
            .padding({ left: 6, right: 6, top: 8, bottom: 10 })

          Button(this.busy ? '正在备份...' : '立即备份一份')
            .width('100%')
            .height(42)
            .fontColor('#FFFFFF')
            .backgroundColor($r('app.color.accent'))
            .borderRadius(12)
            .enabled(!this.busy)
            .onClick(() => { this.onTakeCopyNow(); })

          KelivoSectionHeader({
            titleText: '本地副本 · ' + this.summaryText,
            topSpacing: 14
          })

          if (this.snapshots.length === 0) {
            Text('还没有本地副本。点击上方按钮即可立即创建一份完整数据副本。')
              .fontSize(13)
              .fontColor($r('app.color.muted'))
              .width('100%')
              .padding({ left: 8, right: 8, top: 12, bottom: 12 })
          } else {
            ForEach(this.snapshots, (snap: LocalSnapshotMeta) => {
              Column({ space: 6 }) {
                Row({ space: 8 }) {
                  SymbolGlyph($r('sys.symbol.externaldrive')).fontSize(17).fontColor([$r('app.color.accent')])
                  Text(formatBackupTimeFull(snap.createdAt))
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.ink'))
                    .layoutWeight(1)
                  Text(formatBytesReadable(snap.sizeBytes))
                    .fontSize(12)
                    .fontColor($r('app.color.muted'))
                }
                .width('100%')

                Text(snap.reason === 'manual' ? '手动保存'
                  : (snap.reason === 'pre_restore' ? '恢复前自动保留' : '自动保存'))
                  .fontSize(12)
                  .fontColor($r('app.color.muted'))
                  .width('100%')

                if (typeof snap.conversationCount === 'number' && typeof snap.messageCount === 'number') {
                  Text(snap.conversationCount + ' 段对话 · ' + snap.messageCount + ' 条消息')
                    .fontSize(12)
                    .fontColor($r('app.color.muted'))
                    .width('100%')
                }

                Row({ space: 8 }) {
                  Button('恢复')
                    .layoutWeight(1)
                    .height(34)
                    .fontSize(13)
                    .fontColor($r('app.color.ink'))
                    .backgroundColor($r('app.color.tint'))
                    .borderRadius(10)
                    .onClick(() => { this.onRestoreCopy(snap); })
                  Button('导出')
                    .layoutWeight(1)
                    .height(34)
                    .fontSize(13)
                    .fontColor($r('app.color.ink'))
                    .backgroundColor($r('app.color.tint'))
                    .borderRadius(10)
                    .onClick(() => { this.onExportCopy(snap); })
                  Button('删除')
                    .layoutWeight(1)
                    .height(34)
                    .fontSize(13)
                    .fontColor('#FFFFFF')
                    .backgroundColor('#D93838')
                    .borderRadius(10)
                    .onClick(() => { this.onDeleteCopy(snap); })
                }
                .width('100%')
                .padding({ top: 4 })

                Row({ space: 6 }) {
                  SymbolGlyph($r('sys.symbol.pin')).fontSize(14).fontColor([$r('app.color.accent')])
                  Text(snap.pinned ? '已保留此份（取消保留）' : '固定保留此份')
                    .fontSize(12)
                    .fontColor($r('app.color.accent'))
                }
                .width('100%')
                .justifyContent(FlexAlign.Center)
                .padding({ top: 6, bottom: 2 })
                .onClick(() => { this.onTogglePin(snap); })
              }
              .width('100%')
              .padding(14)
              .margin({ bottom: 10 })
              .borderRadius(14)
              .backgroundColor($r('app.color.panel'))
            }, (snap: LocalSnapshotMeta): string => snap.id)
          }

          Text('本地副本只存在这台设备上。它防的是应用内数据被损坏或误删，防不了设备丢失或卸载应用——那要靠 WebDAV / S3 备份。')
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.muted'))
            .width('100%')
            .padding({ left: 6, right: 6, top: 8 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 28 + this.winBottomInset })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct BackupWebDavSettingsSheet {
  @Link davUrl: string;
  @Link davUser: string;
  @Link davPass: string;
  @Link davPath: string;
  @Link davUserAgent: string;
  @Link davShowPass: boolean;
  @StorageProp('windowBottomInsetVp') winBottomInset: number = 0;
  onSave: () => void = () => {};
  onClose: () => void = () => {};

  build() {
    Column() {
      Row({ space: 10 }) {
        Text('WebDAV 服务器设置')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
          .layoutWeight(1)
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([$r('app.color.accent')])
        }
        .width(34)
        .height(34)
        .onClick(() => { this.onSave(); })
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(17).fontColor([$r('app.color.muted')])
        }
        .width(34)
        .height(34)
        .onClick(() => { this.onClose(); })
      }
      .width('100%')
      .padding({ left: 18, right: 12, top: 14, bottom: 8 })

      Scroll() {
        Column({ space: 10 }) {
          Text('WebDAV 服务器地址').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.muted')).width('100%')
          TextInput({ text: this.davUrl, placeholder: 'https://example.com/dav' })
            .height(44).borderRadius(12).backgroundColor($r('app.color.panel'))
            .onChange((v: string) => { this.davUrl = v; })

          Text('用户名').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.muted')).width('100%')
          TextInput({ text: this.davUser, placeholder: 'WebDAV 用户名' })
            .height(44).borderRadius(12).backgroundColor($r('app.color.panel'))
            .onChange((v: string) => { this.davUser = v; })

          Text('密码').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.muted')).width('100%')
          Row({ space: 8 }) {
            TextInput({ text: this.davPass, placeholder: '应用专用密码（加密存入本机密钥库）' })
              .type(this.davShowPass ? InputType.Normal : InputType.Password)
              .showPasswordIcon(false)
              .layoutWeight(1)
              .height(44)
              .borderRadius(12)
              .backgroundColor($r('app.color.panel'))
              .onChange((v: string) => { this.davPass = v; })
            Button({ type: ButtonType.Normal }) {
              SymbolGlyph(this.davShowPass ? $r('sys.symbol.eye_slash') : $r('sys.symbol.eye'))
                .fontSize(18).fontColor([$r('app.color.muted')])
            }
            .width(42).height(42).borderRadius(12).backgroundColor($r('app.color.panel'))
            .onClick(() => { this.davShowPass = !this.davShowPass; })
          }
          .width('100%')

          Text('路径').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.muted')).width('100%')
          TextInput({ text: this.davPath, placeholder: 'kelivo_backups' })
            .height(44).borderRadius(12).backgroundColor($r('app.color.panel'))
            .onChange((v: string) => { this.davPath = v; })

          Text('User-Agent').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.muted')).width('100%')
          TextInput({ text: this.davUserAgent, placeholder: '可选' })
            .height(44).borderRadius(12).backgroundColor($r('app.color.panel'))
            .onChange((v: string) => { this.davUserAgent = v; })

          Button('保存')
            .width('100%')
            .height(44)
            .margin({ top: 10 })
            .fontColor('#FFFFFF')
            .backgroundColor($r('app.color.accent'))
            .borderRadius(12)
            .onClick(() => { this.onSave(); })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 28 + this.winBottomInset })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct BackupS3SettingsSheet {
  @Link s3Endpoint: string;
  @Link s3Region: string;
  @Link s3Bucket: string;
  @Link s3AccessKey: string;
  @Link s3SecretKey: string;
  @Link s3SessionToken: string;
  @Link s3Prefix: string;
  @Link s3UserAgent: string;
  @Link s3PathStyle: boolean;
  @Link s3ShowSecret: boolean;
  @Link s3ShowToken: boolean;
  @StorageProp('windowBottomInsetVp') winBottomInset: number = 0;
  @StorageProp('immersiveLightEnabled') immersiveLight: boolean = true;
  onSave: () => void = () => {};
  onClose: () => void = () => {};

  build() {
    Column() {
      Row({ space: 10 }) {
        Text('S3 设置')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
          .layoutWeight(1)
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([$r('app.color.accent')])
        }
        .width(34)
        .height(34)
        .onClick(() => { this.onSave(); })
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(17).fontColor([$r('app.color.muted')])
        }
        .width(34)
        .height(34)
        .onClick(() => { this.onClose(); })
      }
      .width('100%')
      .padding({ left: 18, right: 12, top: 14, bottom: 8 })

      Scroll() {
        Column({ space: 10 }) {
          Text('端点').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.muted')).width('100%')
          TextInput({ text: this.s3Endpoint, placeholder: 'https://s3.amazonaws.com' })
            .height(44).borderRadius(12).backgroundColor($r('app.color.panel'))
            .onChange((v: string) => { this.s3Endpoint = v; })

          Text('区域').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.muted')).width('100%')
          TextInput({ text: this.s3Region, placeholder: 'us-east-1 / auto' })
            .height(44).borderRadius(12).backgroundColor($r('app.color.panel'))
            .onChange((v: string) => { this.s3Region = v; })

          Text('Bucket').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.muted')).width('100%')
          TextInput({ text: this.s3Bucket, placeholder: '存储桶名称' })
            .height(44).borderRadius(12).backgroundColor($r('app.color.panel'))
            .onChange((v: string) => { this.s3Bucket = v; })

          Text('访问密钥 ID').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.muted')).width('100%')
          TextInput({ text: this.s3AccessKey, placeholder: 'Access Key ID' })
            .height(44).borderRadius(12).backgroundColor($r('app.color.panel'))
            .onChange((v: string) => { this.s3AccessKey = v; })

          Text('秘密访问密钥').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.muted')).width('100%')
          Row({ space: 8 }) {
            TextInput({ text: this.s3SecretKey, placeholder: 'Secret Access Key（存入密钥库）' })
              .type(this.s3ShowSecret ? InputType.Normal : InputType.Password)
              .showPasswordIcon(false)
              .layoutWeight(1)
              .height(44)
              .borderRadius(12)
              .backgroundColor($r('app.color.panel'))
              .onChange((v: string) => { this.s3SecretKey = v; })
            Button({ type: ButtonType.Normal }) {
              SymbolGlyph(this.s3ShowSecret ? $r('sys.symbol.eye_slash') : $r('sys.symbol.eye'))
                .fontSize(18).fontColor([$r('app.color.muted')])
            }
            .width(42).height(42).borderRadius(12).backgroundColor($r('app.color.panel'))
            .onClick(() => { this.s3ShowSecret = !this.s3ShowSecret; })
          }
          .width('100%')

          Text('Session Token（可选）').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.muted')).width('100%')
          Row({ space: 8 }) {
            TextInput({ text: this.s3SessionToken, placeholder: '临时安全令牌' })
              .type(this.s3ShowToken ? InputType.Normal : InputType.Password)
              .showPasswordIcon(false)
              .layoutWeight(1)
              .height(44)
              .borderRadius(12)
              .backgroundColor($r('app.color.panel'))
              .onChange((v: string) => { this.s3SessionToken = v; })
            Button({ type: ButtonType.Normal }) {
              SymbolGlyph(this.s3ShowToken ? $r('sys.symbol.eye_slash') : $r('sys.symbol.eye'))
                .fontSize(18).fontColor([$r('app.color.muted')])
            }
            .width(42).height(42).borderRadius(12).backgroundColor($r('app.color.panel'))
            .onClick(() => { this.s3ShowToken = !this.s3ShowToken; })
          }
          .width('100%')

          Text('前缀（目录）').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.muted')).width('100%')
          TextInput({ text: this.s3Prefix, placeholder: 'kelivo_backups' })
            .height(44).borderRadius(12).backgroundColor($r('app.color.panel'))
            .onChange((v: string) => { this.s3Prefix = v; })

          Text('User-Agent').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.muted')).width('100%')
          TextInput({ text: this.s3UserAgent, placeholder: '可选' })
            .height(44).borderRadius(12).backgroundColor($r('app.color.panel'))
            .onChange((v: string) => { this.s3UserAgent = v; })

          Row({ space: 10 }) {
            Text('路径风格（Path-style）')
              .fontSize(14)
              .fontColor($r('app.color.ink'))
              .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.s3PathStyle })
              .onChange((v: boolean) => { this.s3PathStyle = v; })
              .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLight))
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .borderRadius(12)
          .backgroundColor($r('app.color.panel'))

          Button('保存')
            .width('100%')
            .height(44)
            .margin({ top: 8 })
            .fontColor('#FFFFFF')
            .backgroundColor($r('app.color.accent'))
            .borderRadius(12)
            .onClick(() => { this.onSave(); })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 28 + this.winBottomInset })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }
}

@Component
export struct BackupRemoteListSheet {
  @Prop items: RemoteBackupEntry[] = [];
  @Prop loading: boolean = false;
  @StorageProp('windowBottomInsetVp') winBottomInset: number = 0;
  onRestore: (item: RemoteBackupEntry) => void = () => {};
  onDelete: (item: RemoteBackupEntry) => void = () => {};
  onClose: () => void = () => {};

  build() {
    Column() {
      Row({ space: 10 }) {
        Text('远端备份')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
          .layoutWeight(1)
        if (this.loading) {
          LoadingProgress().width(18).height(18).color($r('app.color.accent'))
        }
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(17).fontColor([$r('app.color.muted')])
        }
        .width(34)
        .height(34)
        .onClick(() => { this.onClose(); })
      }
      .width('100%')
      .padding({ left: 18, right: 12, top: 14, bottom: 8 })

      Scroll() {
        Column({ space: 8 }) {
          if (!this.loading && this.items.length === 0) {
            Text('暂无备份')
              .fontSize(14)
              .fontColor($r('app.color.muted'))
              .padding({ top: 32, bottom: 32 })
          } else {
            ForEach(this.items, (item: RemoteBackupEntry) => {
              Row({ space: 10 }) {
                Column({ space: 3 }) {
                  Text(item.name)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.ink'))
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(formatBytesReadable(item.sizeBytes) + (item.lastModified ? (' · ' + item.lastModified) : ''))
                    .fontSize(12)
                    .fontColor($r('app.color.muted'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
                  SymbolGlyph($r('sys.symbol.arrow_down_circle')).fontSize(20).fontColor([$r('app.color.ink')])
                }
                .width(38)
                .height(38)
                .onClick(() => { this.onRestore(item); })

                Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
                  SymbolGlyph($r('sys.symbol.trash')).fontSize(18).fontColor(['#D93838'])
                }
                .width(38)
                .height(38)
                .onClick(() => { this.onDelete(item); })
              }
              .width('100%')
              .padding({ left: 14, right: 10, top: 10, bottom: 10 })
              .borderRadius(14)
              .backgroundColor($r('app.color.panel'))
            }, (item: RemoteBackupEntry): string => item.remoteKey)
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 28 + this.winBottomInset })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
  }
}
