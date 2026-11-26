import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import {
  BackupPreferencesConfig,
  BackupScopeConfig,
  Conversation,
  LocalSnapshotMeta,
  S3BackupConfig,
  Workspace,
  countSelectedBackupScope,
  defaultBackupConfig,
  defaultBackupScope,
  normalizeBackupConfig,
  normalizeBackupScope
} from '../core/Models';
import {
  BackupCancelledError,
  buildBackupArchiveBytes,
  createLocalSnapshot,
  deleteLocalSnapshotFile,
  exportFullBackupToFile,
  exportLocalSnapshotToFile,
  formatBytesReadable,
  importBackupBytes,
  pickAnyBackupBytes,
  pickChatboxBackupBytes,
  pickCherryBackupBytes,
  readLocalSnapshotBytes
} from '../core/BackupManager';
import { makeBackupPasswordVerifier, verifyBackupPassword } from '../core/BackupCrypto';
import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { S3Client } from '../core/S3Client';
import { S3RemoteObject } from '../core/S3SigV4';
import { readKey, storeKey, forgetKey } from '../core/Storage';
import { WebDavClient, WebDavRemoteItem } from '../core/WebDavClient';
import { KelivoPageHeader, KelivoSectionHeader } from './KelivoChrome';
import {
  RemoteBackupEntry,
  cloneBackupPreferences,
  formatBackupTimeFull,
  formatNextReminderText,
  formatReminderFreqText,
  formatReminderTimeText
} from './BackupPanelTypes';
import {
  BackupCherryWarnSheet,
  BackupImportModeSheet,
  BackupPasswordSheet,
  BackupReminderFreqSheet,
  BackupReminderTimeSheet,
  BackupScopeSheet
} from './BackupDialogsSheets';
import {
  BackupLocalCopiesSheet,
  BackupRemoteListSheet,
  BackupS3SettingsSheet,
  BackupWebDavSettingsSheet
} from './BackupCloudAndCopiesSheets';

@Component
export struct WebDavPanel {
  initialDirectory: string = '';
  initialPath: string = 'kelivo_backups';
  initialUsername: string = '';
  initialPassRef: string = '';
  initialUserAgent: string = '';
  initialFile: string = '';
  conversations: Conversation[] = [];
  @Prop workspaceData: Workspace;
  @Prop embeddedInNav: boolean = false;

  onWorkspaceRestored: (next: Workspace) => Promise<void> = async () => {};
  onSaveBackupConfig: (cfg: BackupPreferencesConfig) => void = () => {};
  onSaveWebDavConfig: (url: string, path: string, user: string, passRef: string, userAgent: string) => void = () => {};
  onSaveS3Config: (s3: S3BackupConfig) => void = () => {};
  onUpdateSnapshots: (list: LocalSnapshotMeta[]) => void = () => {};
  onOpenUrl: (url: string) => void = () => {};
  onClose: () => void = () => {};

  // Working state synced with workspace
  @State cfg: BackupPreferencesConfig = defaultBackupConfig();
  @State snapshots: LocalSnapshotMeta[] = [];
  @State busy: boolean = false;
  @State statusBanner: string = '';
  @State statusIsError: boolean = false;

  // WebDAV & S3 form draft fields (kept in memory, secrets persisted to AssetStoreKit)
  @State davUrl: string = '';
  @State davPath: string = 'kelivo_backups';
  @State davUser: string = '';
  @State davPass: string = '';
  @State davPassRef: string = '';
  @State davUserAgent: string = '';
  @State davShowPass: boolean = false;

  @State s3Endpoint: string = '';
  @State s3Region: string = 'us-east-1';
  @State s3Bucket: string = '';
  @State s3Prefix: string = 'kelivo_backups';
  @State s3AccessKey: string = '';
  @State s3SecretKey: string = '';
  @State s3SecretRef: string = '';
  @State s3SessionToken: string = '';
  @State s3TokenRef: string = '';
  @State s3UserAgent: string = '';
  @State s3PathStyle: boolean = true;
  @State s3ShowSecret: boolean = false;
  @State s3ShowToken: boolean = false;

  // Single unified bottom sheet state
  @State activeSheet: string = ''; // '' | 'scope' | 'password' | 'import_mode' | 'cherry_warn' | 'reminder_freq' | 'reminder_time' | 'copies' | 'webdav_settings' | 's3_settings' | 'remote_list'
  @State draftScope: BackupScopeConfig = defaultBackupScope();

  // Password sheet state
  @State passwordMode: 'create' | 'change' | 'manual' | 'unlock' = 'create';
  @State passwordInput: string = '';
  @State passwordConfirm: string = '';
  @State passwordRememberDraft: boolean = false;
  @State passwordShowText: boolean = false;
  @State passwordRetryError: boolean = false;

  // Reminder sheet drafts
  @State reminderCustomDaysInput: string = '7';
  @State reminderHourInput: string = '20';
  @State reminderMinuteInput: string = '00';

  // Remote list sheet state
  @State remoteItems: RemoteBackupEntry[] = [];
  @State remoteKind: 'webdav' | 's3' = 'webdav';
  @State remoteLoading: boolean = false;

  @StorageProp('windowTopInsetVp') winTopInset: number = 0;
  @StorageProp('windowBottomInsetVp') winBottomInset: number = 0;
  @StorageProp('immersiveLightEnabled') immersiveLight: boolean = true;

  private sessionManualPassword: string = '';
  private pwdResolver?: (val: string | undefined) => void;
  private modeResolver?: (mode: 'overwrite' | 'merge' | undefined) => void;
  private cherryResolver?: (ok: boolean) => void;

  aboutToAppear(): void {
    this.syncFromWorkspace(this.workspaceData);
    this.loadStoredSecrets().catch(() => {});
  }

  private syncFromWorkspace(ws: Workspace): void {
    this.cfg = normalizeBackupConfig(ws.backupConfig);
    this.snapshots = (ws.snapshots || []).slice().sort((a: LocalSnapshotMeta, b: LocalSnapshotMeta): number => b.createdAt - a.createdAt);

    this.davUrl = ws.davDirectory || this.initialDirectory || '';
    this.davPath = ws.davPath || this.initialPath || 'kelivo_backups';
    this.davUser = ws.davUsername || this.initialUsername || '';
    this.davPassRef = ws.davPasswordRef || this.initialPassRef || '';
    this.davUserAgent = ws.davUserAgent || this.initialUserAgent || '';

    const s3 = ws.s3Config;
    this.s3Endpoint = s3?.endpoint || '';
    this.s3Region = s3?.region || 'us-east-1';
    this.s3Bucket = s3?.bucket || '';
    this.s3Prefix = s3?.prefix || 'kelivo_backups';
    this.s3AccessKey = s3?.accessKeyId || '';
    this.s3SecretRef = s3?.secretAccessKeyRef || '';
    this.s3TokenRef = s3?.sessionTokenRef || '';
    this.s3UserAgent = s3?.userAgent || '';
    this.s3PathStyle = s3 ? s3.pathStyle !== false : true;
  }

  private async loadStoredSecrets(): Promise<void> {
    if (this.davPassRef) {
      try {
        const v = await readKey(this.davPassRef);
        if (v) this.davPass = v;
      } catch (_) {}
    }
    if (this.s3SecretRef) {
      try {
        const v = await readKey(this.s3SecretRef);
        if (v) this.s3SecretKey = v;
      } catch (_) {}
    }
    if (this.s3TokenRef) {
      try {
        const v = await readKey(this.s3TokenRef);
        if (v) this.s3SessionToken = v;
      } catch (_) {}
    }
  }

  private host(): common.UIAbilityContext | undefined {
    return this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
  }

  private showToast(msg: string, isErr: boolean = false): void {
    this.statusBanner = msg;
    this.statusIsError = isErr;
    try {
      this.getUIContext().getPromptAction().showToast(
        ImmersiveMaterialStyle.toastOptions(msg, this.immersiveLight)
      );
    } catch (_) {}
  }

  private saveCfg(next: BackupPreferencesConfig): void {
    this.cfg = normalizeBackupConfig(next);
    this.workspaceData.backupConfig = this.cfg;
    this.onSaveBackupConfig(this.cfg);
  }

  private async closeSheetAndWait(): Promise<void> {
    if (this.activeSheet.length === 0) return;
    this.activeSheet = '';
    await new Promise<void>((resolve: () => void) => {
      setTimeout(() => resolve(), 220);
    });
  }

  private async promptPasswordModal(
    mode: 'create' | 'change' | 'manual' | 'unlock',
    isRetry: boolean = false
  ): Promise<string | undefined> {
    await this.closeSheetAndWait();
    return new Promise<string | undefined>((resolve: (val: string | undefined) => void) => {
      this.pwdResolver = resolve;
      this.passwordMode = mode;
      this.passwordInput = '';
      this.passwordConfirm = '';
      this.passwordRememberDraft = this.cfg.rememberPassword;
      this.passwordShowText = false;
      this.passwordRetryError = isRetry;
      this.activeSheet = 'password';
    });
  }

  private async promptImportMode(): Promise<'overwrite' | 'merge' | undefined> {
    await this.closeSheetAndWait();
    return new Promise<'overwrite' | 'merge' | undefined>((resolve: (mode: 'overwrite' | 'merge' | undefined) => void) => {
      this.modeResolver = resolve;
      this.activeSheet = 'import_mode';
    });
  }

  private async promptCherryWarning(): Promise<boolean> {
    await this.closeSheetAndWait();
    return new Promise<boolean>((resolve: (ok: boolean) => void) => {
      this.cherryResolver = resolve;
      this.activeSheet = 'cherry_warn';
    });
  }

  private settlePendingResolvers(): void {
    if (this.pwdResolver) {
      const fn = this.pwdResolver;
      this.pwdResolver = undefined;
      fn(undefined);
    }
    if (this.modeResolver) {
      const fn = this.modeResolver;
      this.modeResolver = undefined;
      fn(undefined);
    }
    if (this.cherryResolver) {
      const fn = this.cherryResolver;
      this.cherryResolver = undefined;
      fn(false);
    }
  }

  private async resolveExportPassword(): Promise<string> {
    if (!this.cfg.encryptionEnabled) return '';
    if (this.cfg.rememberPassword && this.cfg.passwordSecretRef) {
      try {
        const stored = await readKey(this.cfg.passwordSecretRef);
        if (stored) return stored;
      } catch (_) {}
    }
    if (this.sessionManualPassword) return this.sessionManualPassword;

    const mode: 'create' | 'manual' = this.cfg.passwordVerifier ? 'manual' : 'create';
    let retry = false;
    while (true) {
      const entered = await this.promptPasswordModal(mode, retry);
      if (entered === undefined) throw new BackupCancelledError();
      if (this.cfg.passwordVerifier) {
        const ok = await verifyBackupPassword(entered, this.cfg.passwordVerifier);
        if (!ok) {
          retry = true;
          continue;
        }
      }
      this.sessionManualPassword = entered;
      return entered;
    }
  }

  private async handleToggleEncryption(enable: boolean): Promise<void> {
    if (!enable) {
      const oldRef = this.cfg.passwordSecretRef;
      const next = cloneBackupPreferences(this.cfg);
      next.encryptionEnabled = false;
      next.rememberPassword = false;
      next.passwordVerifier = undefined;
      next.passwordSecretRef = undefined;
      this.sessionManualPassword = '';
      this.saveCfg(next);
      if (oldRef) await forgetKey(oldRef).catch(() => {});
      this.showToast('已关闭加密备份');
      return;
    }
    const pwd = await this.promptPasswordModal('create', false);
    if (!pwd) return;
    await this.applyNewBackupPassword(pwd, this.passwordRememberDraft);
    this.showToast('已开启加密备份');
  }

  private async applyNewBackupPassword(pwd: string, remember: boolean): Promise<void> {
    const verifier = await makeBackupPasswordVerifier(pwd);
    const next = cloneBackupPreferences(this.cfg);
    next.encryptionEnabled = true;
    next.passwordVerifier = verifier;
    next.rememberPassword = remember;
    this.sessionManualPassword = pwd;

    if (remember) {
      const ref = next.passwordSecretRef || ('bk-pwd-' + util.generateRandomUUID(true));
      await storeKey(ref, pwd);
      next.passwordSecretRef = ref;
    } else if (next.passwordSecretRef) {
      const oldRef = next.passwordSecretRef;
      next.passwordSecretRef = undefined;
      await forgetKey(oldRef).catch(() => {});
    }
    this.saveCfg(next);
  }

  private async handleToggleRememberPassword(remember: boolean): Promise<void> {
    const next = cloneBackupPreferences(this.cfg);
    if (!remember) {
      const oldRef = next.passwordSecretRef;
      next.rememberPassword = false;
      next.passwordSecretRef = undefined;
      this.saveCfg(next);
      if (oldRef) await forgetKey(oldRef).catch(() => {});
      this.showToast('已清除本机保存的备份口令');
      return;
    }
    let pwd = this.sessionManualPassword;
    if (!pwd) {
      let retry = false;
      while (true) {
        const entered = await this.promptPasswordModal('manual', retry);
        if (!entered) return;
        if (this.cfg.passwordVerifier) {
          const ok = await verifyBackupPassword(entered, this.cfg.passwordVerifier);
          if (!ok) {
            retry = true;
            continue;
          }
        }
        pwd = entered;
        break;
      }
    }
    const ref = next.passwordSecretRef || ('bk-pwd-' + util.generateRandomUUID(true));
    await storeKey(ref, pwd);
    next.rememberPassword = true;
    next.passwordSecretRef = ref;
    this.saveCfg(next);
    this.showToast('已在本机安全保存备份口令');
  }

  private markBackupSucceeded(): void {
    const next = cloneBackupPreferences(this.cfg);
    next.lastBackupAt = Date.now();
    this.saveCfg(next);
  }

  private async doLocalBackup(): Promise<void> {
    const ctx = this.host();
    if (!ctx || this.busy) return;
    try {
      const pwd = await this.resolveExportPassword();
      this.busy = true;
      const saved = await exportFullBackupToFile(ctx, this.workspaceData, this.cfg.scope, pwd);
      if (saved) {
        this.markBackupSucceeded();
        this.showToast('备份文件已保存');
      }
    } catch (e) {
      if (!(e instanceof BackupCancelledError)) {
        this.showToast('备份失败：' + ((e as Error).message || '未知错误'), true);
      }
    } finally {
      this.busy = false;
    }
  }

  private async runImportFlow(bytes: Uint8Array, forcedSource: 'cherry' | 'chatbox' | 'auto'): Promise<void> {
    const ctx = this.host();
    if (!ctx) return;
    const mode = await this.promptImportMode();
    if (!mode) return;
    await this.closeSheetAndWait();
    this.busy = true;
    try {
      const outcome = await importBackupBytes(
        ctx,
        this.workspaceData,
        bytes,
        this.cfg.scope,
        mode,
        this.sessionManualPassword,
        async (isRetry: boolean): Promise<string | undefined> => {
          return this.promptPasswordModal('unlock', isRetry);
        },
        forcedSource
      );
      outcome.workspace.snapshots = this.snapshots;
      outcome.workspace.backupConfig = this.cfg;
      this.workspaceData = outcome.workspace;
      await this.onWorkspaceRestored(outcome.workspace);
      this.showToast(outcome.summary);
    } catch (e) {
      if (!(e instanceof BackupCancelledError)) {
        this.showToast('导入失败：' + ((e as Error).message || '文件格式不支持'), true);
      }
    } finally {
      this.busy = false;
    }
  }

  private async doImportBackupFile(): Promise<void> {
    const ctx = this.host();
    if (!ctx || this.busy) return;
    try {
      const bytes = await pickAnyBackupBytes(ctx);
      if (!bytes) return;
      await this.runImportFlow(bytes, 'auto');
    } catch (e) {
      this.showToast('读取备份失败：' + ((e as Error).message || '未知错误'), true);
    }
  }

  private async doImportCherry(): Promise<void> {
    const ctx = this.host();
    if (!ctx || this.busy) return;
    const confirmed = await this.promptCherryWarning();
    if (!confirmed) return;
    try {
      const bytes = await pickCherryBackupBytes(ctx);
      if (!bytes) return;
      await this.runImportFlow(bytes, 'cherry');
    } catch (e) {
      this.showToast('Cherry Studio 导入失败：' + ((e as Error).message || '未知错误'), true);
    }
  }

  private async doImportChatbox(): Promise<void> {
    const ctx = this.host();
    if (!ctx || this.busy) return;
    try {
      const bytes = await pickChatboxBackupBytes(ctx);
      if (!bytes) return;
      await this.runImportFlow(bytes, 'chatbox');
    } catch (e) {
      this.showToast('Chatbox 导入失败：' + ((e as Error).message || '未知错误'), true);
    }
  }

  // ===== Local Copies / Snapshots =====
  private totalCopiesBytes(): number {
    let total = 0;
    for (let i = 0; i < this.snapshots.length; i++) total += this.snapshots[i].sizeBytes;
    return total;
  }

  private copiesSummaryText(): string {
    if (this.snapshots.length === 0) return '暂无副本 · 0 B';
    return this.snapshots.length + ' 份 · ' + formatBytesReadable(this.totalCopiesBytes());
  }

  private async doTakeCopyNow(): Promise<void> {
    const ctx = this.host();
    if (!ctx || this.busy) return;
    this.busy = true;
    try {
      await createLocalSnapshot(ctx.filesDir, this.workspaceData, 'manual');
      this.snapshots = (this.workspaceData.snapshots || []).slice();
      const next = cloneBackupPreferences(this.cfg);
      next.localCopiesLastSuccessAt = Date.now();
      next.localCopiesLastError = undefined;
      this.saveCfg(next);
      this.onUpdateSnapshots(this.snapshots);
      this.showToast('副本已保存');
    } catch (e) {
      const next = cloneBackupPreferences(this.cfg);
      next.localCopiesLastError = (e as Error).message || '保存失败';
      this.saveCfg(next);
      this.showToast('保存副本失败：' + next.localCopiesLastError, true);
    } finally {
      this.busy = false;
    }
  }

  private doRestoreCopyConfirm(snap: LocalSnapshotMeta): void {
    this.getUIContext().showAlertDialog({
      title: '恢复此本地副本？',
      message: '将创建当前数据的安全副本后，从 ' + formatBackupTimeFull(snap.createdAt) + ' 的副本恢复。',
      systemMaterial: ImmersiveMaterialStyle.alertDialogMaterial(this.immersiveLight),
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '恢复',
        action: () => {
          this.performRestoreCopy(snap).catch(() => {});
        }
      }
    });
  }

  private async performRestoreCopy(snap: LocalSnapshotMeta): Promise<void> {
    const ctx = this.host();
    if (!ctx || this.busy) return;
    this.busy = true;
    try {
      await createLocalSnapshot(ctx.filesDir, this.workspaceData, 'pre_restore', true);
      const bytes = await readLocalSnapshotBytes(ctx.filesDir, snap.fileName);
      const outcome = await importBackupBytes(
        ctx,
        this.workspaceData,
        bytes,
        defaultBackupScope(),
        'overwrite'
      );
      outcome.workspace.snapshots = (this.workspaceData.snapshots || []).slice();
      outcome.workspace.backupConfig = this.cfg;
      this.snapshots = outcome.workspace.snapshots;
      this.workspaceData = outcome.workspace;
      this.onUpdateSnapshots(this.snapshots);
      await this.onWorkspaceRestored(outcome.workspace);
      this.activeSheet = '';
      this.showToast('已从本地副本恢复');
    } catch (e) {
      this.showToast('恢复失败：' + ((e as Error).message || '文件可能已损坏'), true);
    } finally {
      this.busy = false;
    }
  }

  private async doExportCopy(snap: LocalSnapshotMeta): Promise<void> {
    const ctx = this.host();
    if (!ctx || this.busy) return;
    this.busy = true;
    try {
      const ok = await exportLocalSnapshotToFile(ctx, ctx.filesDir, snap);
      if (ok) this.showToast('副本已导出');
    } catch (e) {
      this.showToast('导出失败：' + ((e as Error).message || '未知错误'), true);
    } finally {
      this.busy = false;
    }
  }

  private doDeleteCopyConfirm(snap: LocalSnapshotMeta): void {
    this.getUIContext().showAlertDialog({
      title: '删除此本地副本？',
      message: formatBackupTimeFull(snap.createdAt) + ' · ' + formatBytesReadable(snap.sizeBytes),
      systemMaterial: ImmersiveMaterialStyle.alertDialogMaterial(this.immersiveLight),
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '删除',
        fontColor: '#D93838',
        action: () => {
          this.performDeleteCopy(snap).catch(() => {});
        }
      }
    });
  }

  private async performDeleteCopy(snap: LocalSnapshotMeta): Promise<void> {
    const ctx = this.host();
    if (!ctx) return;
    await deleteLocalSnapshotFile(ctx.filesDir, snap.fileName);
    this.snapshots = this.snapshots.filter((s: LocalSnapshotMeta): boolean => s.id !== snap.id);
    this.workspaceData.snapshots = this.snapshots;
    this.onUpdateSnapshots(this.snapshots);
    this.showToast('副本已删除');
  }

  private toggleCopyPinned(snap: LocalSnapshotMeta): void {
    const next = this.snapshots.map((s: LocalSnapshotMeta): LocalSnapshotMeta => {
      if (s.id !== snap.id) return s;
      return {
        id: s.id,
        fileName: s.fileName,
        createdAt: s.createdAt,
        sizeBytes: s.sizeBytes,
        reason: s.reason,
        encrypted: s.encrypted,
        pinned: s.pinned !== true,
        conversationCount: s.conversationCount,
        messageCount: s.messageCount
      };
    });
    this.snapshots = next;
    this.workspaceData.snapshots = next;
    this.onUpdateSnapshots(next);
  }

  // ===== WebDAV & S3 Operations =====
  private async webDavClientObj(): Promise<WebDavClient> {
    let pass = this.davPass;
    if (!pass && this.davPassRef) {
      pass = await readKey(this.davPassRef).catch((): string => '');
    }
    return new WebDavClient(this.davUrl, this.davUser, pass, this.davPath, this.davUserAgent);
  }

  private async s3ClientObj(): Promise<S3Client> {
    let secret = this.s3SecretKey;
    if (!secret && this.s3SecretRef) {
      secret = await readKey(this.s3SecretRef).catch((): string => '');
    }
    let token = this.s3SessionToken;
    if (!token && this.s3TokenRef) {
      token = await readKey(this.s3TokenRef).catch((): string => '');
    }
    const cfg: S3BackupConfig = {
      endpoint: this.s3Endpoint.trim(),
      region: this.s3Region.trim() || 'us-east-1',
      bucket: this.s3Bucket.trim(),
      prefix: this.s3Prefix.trim() || 'kelivo_backups',
      accessKeyId: this.s3AccessKey.trim(),
      secretAccessKeyRef: this.s3SecretRef,
      sessionTokenRef: this.s3TokenRef || undefined,
      userAgent: this.s3UserAgent.trim() || undefined,
      pathStyle: this.s3PathStyle
    };
    return new S3Client(cfg, secret, token);
  }

  private async saveWebDavForm(): Promise<void> {
    const url = this.davUrl.trim();
    const path = this.davPath.trim() || 'kelivo_backups';
    const user = this.davUser.trim();
    const ua = this.davUserAgent.trim();
    let passRef = this.davPassRef;
    if (this.davPass.trim().length > 0) {
      if (!passRef) passRef = 'dav-pass-' + util.generateRandomUUID(true);
      await storeKey(passRef, this.davPass);
      this.davPassRef = passRef;
    } else if (passRef) {
      await forgetKey(passRef).catch(() => {});
      passRef = '';
      this.davPassRef = '';
    }
    this.onSaveWebDavConfig(url, path, user, passRef, ua);
    this.activeSheet = '';
    this.showToast('WebDAV 设置已保存');
  }

  private async saveS3Form(): Promise<void> {
    let secretRef = this.s3SecretRef;
    if (this.s3SecretKey.trim().length > 0) {
      if (!secretRef) secretRef = 's3-secret-' + util.generateRandomUUID(true);
      await storeKey(secretRef, this.s3SecretKey.trim());
      this.s3SecretRef = secretRef;
    } else if (secretRef) {
      await forgetKey(secretRef).catch(() => {});
      secretRef = '';
      this.s3SecretRef = '';
    }
    let tokenRef = this.s3TokenRef;
    if (this.s3SessionToken.trim().length > 0) {
      if (!tokenRef) tokenRef = 's3-token-' + util.generateRandomUUID(true);
      await storeKey(tokenRef, this.s3SessionToken.trim());
      this.s3TokenRef = tokenRef;
    } else if (tokenRef) {
      await forgetKey(tokenRef).catch(() => {});
      tokenRef = '';
      this.s3TokenRef = '';
    }
    const nextCfg: S3BackupConfig = {
      endpoint: this.s3Endpoint.trim(),
      region: this.s3Region.trim() || 'us-east-1',
      bucket: this.s3Bucket.trim(),
      prefix: this.s3Prefix.trim() || 'kelivo_backups',
      accessKeyId: this.s3AccessKey.trim(),
      secretAccessKeyRef: secretRef,
      sessionTokenRef: tokenRef || undefined,
      userAgent: this.s3UserAgent.trim() || undefined,
      pathStyle: this.s3PathStyle
    };
    this.onSaveS3Config(nextCfg);
    this.activeSheet = '';
    this.showToast('S3 设置已保存');
  }

  private async testRemoteConnection(kind: 'webdav' | 's3'): Promise<void> {
    if (this.busy) return;
    if (kind === 'webdav' && !this.davUrl.trim()) {
      this.showToast('请先在 WebDAV 服务器设置中填写地址', true);
      return;
    }
    if (kind === 's3' && (!this.s3Endpoint.trim() || !this.s3Bucket.trim())) {
      this.showToast('请先在 S3 设置中填写端点与 Bucket', true);
      return;
    }
    this.busy = true;
    try {
      if (kind === 'webdav') {
        const client = await this.webDavClientObj();
        await client.testConnection();
      } else {
        const client = await this.s3ClientObj();
        await client.testConnection();
      }
      this.showToast('测试完成，连接正常');
    } catch (e) {
      this.showToast('连接失败：' + ((e as Error).message || '网络或凭证错误'), true);
    } finally {
      this.busy = false;
    }
  }

  private async backupRemoteNow(kind: 'webdav' | 's3'): Promise<void> {
    if (this.busy) return;
    if (kind === 'webdav' && !this.davUrl.trim()) {
      this.showToast('请先配置 WebDAV 服务器设置', true);
      return;
    }
    if (kind === 's3' && (!this.s3Endpoint.trim() || !this.s3Bucket.trim() || !this.s3AccessKey.trim())) {
      this.showToast('请先配置 S3 设置', true);
      return;
    }
    try {
      const pwd = await this.resolveExportPassword();
      this.busy = true;
      const built = await buildBackupArchiveBytes(this.workspaceData, this.cfg.scope, pwd);
      if (kind === 'webdav') {
        const client = await this.webDavClientObj();
        await client.putBytes(built.fileName, built.bytes);
      } else {
        const client = await this.s3ClientObj();
        await client.putBytes(built.fileName, built.bytes);
      }
      this.markBackupSucceeded();
      this.showToast('已上传备份：' + built.fileName);
    } catch (e) {
      if (!(e instanceof BackupCancelledError)) {
        this.showToast('上传失败：' + ((e as Error).message || '未知错误'), true);
      }
    } finally {
      this.busy = false;
    }
  }

  private async openRemoteRestoreList(kind: 'webdav' | 's3'): Promise<void> {
    if (this.busy) return;
    if (kind === 'webdav' && !this.davUrl.trim()) {
      this.showToast('请先配置 WebDAV 服务器设置', true);
      return;
    }
    if (kind === 's3' && (!this.s3Endpoint.trim() || !this.s3Bucket.trim() || !this.s3AccessKey.trim())) {
      this.showToast('请先配置 S3 设置', true);
      return;
    }
    this.remoteKind = kind;
    this.remoteItems = [];
    this.remoteLoading = true;
    this.activeSheet = 'remote_list';
    await this.refreshRemoteList(kind);
  }

  private async refreshRemoteList(kind: 'webdav' | 's3'): Promise<void> {
    this.remoteLoading = true;
    try {
      if (kind === 'webdav') {
        const client = await this.webDavClientObj();
        const items: WebDavRemoteItem[] = await client.listFiles();
        this.remoteItems = items
          .filter((it: WebDavRemoteItem): boolean => !it.isDir && /\.(zip|kbackup|json|bak)$/i.test(it.name))
          .map((it: WebDavRemoteItem): RemoteBackupEntry => ({
            kind: 'webdav',
            name: it.name,
            remoteKey: it.name,
            sizeBytes: it.sizeBytes,
            lastModified: it.lastModified
          }));
      } else {
        const client = await this.s3ClientObj();
        const items: S3RemoteObject[] = await client.listObjects();
        this.remoteItems = items
          .filter((it: S3RemoteObject): boolean => /\.(zip|kbackup|json|bak)$/i.test(it.key))
          .map((it: S3RemoteObject): RemoteBackupEntry => ({
            kind: 's3',
            name: it.key.split('/').pop() || it.key,
            remoteKey: it.key,
            sizeBytes: it.size,
            lastModified: it.lastModified
          }));
      }
    } catch (e) {
      this.showToast('获取远端列表失败：' + ((e as Error).message || '网络错误'), true);
    } finally {
      this.remoteLoading = false;
    }
  }

  private async restoreRemoteItem(item: RemoteBackupEntry): Promise<void> {
    await this.closeSheetAndWait();
    this.busy = true;
    try {
      let bytes: Uint8Array;
      if (item.kind === 'webdav') {
        const client = await this.webDavClientObj();
        bytes = await client.getBytes(item.remoteKey);
      } else {
        const client = await this.s3ClientObj();
        bytes = await client.getBytes(item.remoteKey);
      }
      this.busy = false;
      await this.runImportFlow(bytes, 'auto');
    } catch (e) {
      this.busy = false;
      this.showToast('下载远端备份失败：' + ((e as Error).message || '未知错误'), true);
    }
  }

  private confirmDeleteRemoteItem(item: RemoteBackupEntry): void {
    this.getUIContext().showAlertDialog({
      title: '删除远端备份？',
      message: item.name,
      systemMaterial: ImmersiveMaterialStyle.alertDialogMaterial(this.immersiveLight),
      primaryButton: { value: '取消', action: () => {} },
      secondaryButton: {
        value: '删除',
        fontColor: '#D93838',
        action: () => {
          this.performDeleteRemoteItem(item).catch(() => {});
        }
      }
    });
  }

  private async performDeleteRemoteItem(item: RemoteBackupEntry): Promise<void> {
    this.remoteLoading = true;
    try {
      if (item.kind === 'webdav') {
        const client = await this.webDavClientObj();
        await client.deleteFile(item.remoteKey);
      } else {
        const client = await this.s3ClientObj();
        await client.deleteObject(item.remoteKey);
      }
      await this.refreshRemoteList(item.kind);
      this.showToast('已删除远端备份：' + item.name);
    } catch (e) {
      this.remoteLoading = false;
      this.showToast('删除失败：' + ((e as Error).message || '未知错误'), true);
    }
  }

  private encryptionSubtitle(): string {
    if (!this.cfg.encryptionEnabled) return '未加密的备份可被直接读取。';
    if (this.cfg.rememberPassword) return '备份将加密保存，密码已记在本机。';
    return '备份将加密保存，重启应用后需重新输入口令。';
  }

  // ===== Shared UI Row Builders =====
  @Builder
  private navRow(
    symbol: Resource,
    label: string,
    subtitle: string,
    detail: string,
    showArrow: boolean,
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

        Column({ space: 2 }) {
          Text(label)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (subtitle.length > 0) {
            Text(subtitle)
              .fontSize(12)
              .lineHeight(17)
              .fontColor($r('app.color.muted'))
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (detail.length > 0) {
          Text(detail)
            .fontSize(13)
            .fontColor($r('app.color.muted'))
        }

        if (showArrow) {
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(15)
            .fontColor([$r('app.color.muted')])
        }
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: subtitle.length > 0 ? 11 : 13, bottom: subtitle.length > 0 ? 11 : 13 })
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
    subtitle: string,
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

        Column({ space: 2 }) {
          Text(label)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
          if (subtitle.length > 0) {
            Text(subtitle)
              .fontSize(12)
              .lineHeight(17)
              .fontColor($r('app.color.muted'))
          }
        }
        .alignItems(HorizontalAlign.Start)
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

  // ===== Main Scroll Body (Android Backup & Restore 6-section layout) =====
  build() {
    Column() {
      if (!this.embeddedInNav) {
        KelivoPageHeader({
          titleText: '备份与恢复',
          showBack: true,
          onBack: () => { this.onClose(); }
        })
      }

      Scroll() {
        Column() {
          if (this.busy) {
            Row({ space: 10 }) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color($r('app.color.accent'))
              Text('正在处理备份任务，请稍候...')
                .fontSize(13)
                .fontColor($r('app.color.ink'))
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 10, bottom: 10 })
            .margin({ bottom: 10 })
            .borderRadius(14)
            .backgroundColor($r('app.color.panel'))
          } else if (this.statusBanner.length > 0) {
            Row({ space: 8 }) {
              SymbolGlyph(this.statusIsError ? $r('sys.symbol.exclamationmark_triangle') : $r('sys.symbol.checkmark_circle'))
                .fontSize(16)
                .fontColor([this.statusIsError ? '#D93838' : $r('app.color.accent')])
              Text(this.statusBanner)
                .fontSize(12)
                .fontColor(this.statusIsError ? '#D93838' : $r('app.color.muted'))
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 9, bottom: 9 })
            .margin({ bottom: 8 })
            .borderRadius(12)
            .backgroundColor($r('app.color.panel'))
          }

          // Section 1: 备份管理
          KelivoSectionHeader({ titleText: '备份管理', topSpacing: 4 })
          Column() {
            this.navRow(
              $r('sys.symbol.slider_horizontal_2'),
              '备份与导入内容',
              '',
              countSelectedBackupScope(this.cfg.scope) + '/15',
              true,
              true,
              () => {
                this.draftScope = normalizeBackupScope(this.cfg.scope);
                this.activeSheet = 'scope';
              }
            )
            this.switchRow(
              $r('sys.symbol.lock'),
              '加密备份',
              this.encryptionSubtitle(),
              this.cfg.encryptionEnabled,
              this.cfg.encryptionEnabled,
              (v: boolean) => {
                this.handleToggleEncryption(v).catch(() => {});
              }
            )
            if (this.cfg.encryptionEnabled) {
              this.switchRow(
                $r('sys.symbol.key'),
                '在本机记住密码',
                '',
                this.cfg.rememberPassword,
                true,
                (v: boolean) => {
                  this.handleToggleRememberPassword(v).catch(() => {});
                }
              )
              this.navRow(
                $r('sys.symbol.square_and_pencil'),
                '更改备份密码',
                '',
                '',
                true,
                false,
                () => {
                  this.promptPasswordModal('change', false).then((pwd?: string) => {
                    if (pwd) {
                      this.applyNewBackupPassword(pwd, this.passwordRememberDraft).then(() => {
                        this.showToast('备份密码已更新');
                      }).catch(() => {});
                    }
                  }).catch(() => {});
                }
              )
            }
          }
          .width('100%')
          .backgroundColor($r('app.color.panel'))
          .borderRadius(16)
          .clip(true)

          // Section 2: 本地备份
          KelivoSectionHeader({ titleText: '本地备份', topSpacing: 14 })
          Column() {
            this.navRow(
              $r('sys.symbol.arrow_up_circle'),
              '立即备份',
              '将所选内容保存为备份文件',
              '',
              true,
              true,
              () => { this.doLocalBackup().catch(() => {}); }
            )
            this.navRow(
              $r('sys.symbol.arrow_down_circle'),
              '备份文件导入',
              '',
              '',
              true,
              true,
              () => { this.doImportBackupFile().catch(() => {}); }
            )
            this.navRow(
              $r('sys.symbol.archivebox'),
              '从 Cherry Studio 导入',
              '',
              '',
              true,
              true,
              () => { this.doImportCherry().catch(() => {}); }
            )
            this.navRow(
              $r('sys.symbol.archivebox'),
              '从 Chatbox 导入',
              '',
              '',
              true,
              true,
              () => { this.doImportChatbox().catch(() => {}); }
            )
            this.navRow(
              $r('sys.symbol.link'),
              '从其他APP导入',
              '新版 Chatbox、Cherry Studio 2.x 及 ChatGPT、Claude、DeepSeek 等，在浏览器本地转换后导入。',
              '',
              true,
              false,
              () => { this.onOpenUrl('https://kelivo.psycheas.top/tools/import'); }
            )
          }
          .width('100%')
          .backgroundColor($r('app.color.panel'))
          .borderRadius(16)
          .clip(true)

          // Section 3: 备份提醒
          KelivoSectionHeader({ titleText: '备份提醒', topSpacing: 14 })
          Column() {
            this.switchRow(
              $r('sys.symbol.bell'),
              '定期提醒我备份',
              '',
              this.cfg.reminderEnabled,
              this.cfg.reminderEnabled,
              (v: boolean) => {
                const next = cloneBackupPreferences(this.cfg);
                next.reminderEnabled = v;
                this.saveCfg(next);
              }
            )
            if (this.cfg.reminderEnabled) {
              this.navRow(
                $r('sys.symbol.calendar'),
                '提醒频率',
                '',
                formatReminderFreqText(this.cfg.reminderIntervalDays),
                true,
                true,
                () => {
                  this.reminderCustomDaysInput = String(this.cfg.reminderIntervalDays);
                  this.activeSheet = 'reminder_freq';
                }
              )
              this.navRow(
                $r('sys.symbol.clock'),
                '提醒时间',
                '',
                formatReminderTimeText(this.cfg.reminderMinutesOfDay),
                true,
                true,
                () => {
                  const h = Math.floor(this.cfg.reminderMinutesOfDay / 60) % 24;
                  const m = this.cfg.reminderMinutesOfDay % 60;
                  this.reminderHourInput = String(h);
                  this.reminderMinuteInput = String(m < 10 ? ('0' + m) : m);
                  this.activeSheet = 'reminder_time';
                }
              )
              this.navRow(
                $r('sys.symbol.checkmark_circle'),
                '上次备份',
                '',
                formatBackupTimeFull(this.cfg.lastBackupAt),
                false,
                true,
                () => {}
              )
              this.navRow(
                $r('sys.symbol.clock'),
                '下次提醒',
                '',
                formatNextReminderText(this.cfg),
                false,
                false,
                () => {}
              )
            }
          }
          .width('100%')
          .backgroundColor($r('app.color.panel'))
          .borderRadius(16)
          .clip(true)

          // Section 4: 本地副本
          KelivoSectionHeader({ titleText: '本地副本', topSpacing: 14 })
          Column() {
            this.switchRow(
              $r('sys.symbol.checkmark_shield'),
              '保留本地副本',
              '',
              this.cfg.localCopiesEnabled,
              true,
              (v: boolean) => {
                const next = cloneBackupPreferences(this.cfg);
                next.localCopiesEnabled = v;
                this.saveCfg(next);
              }
            )
            this.navRow(
              $r('sys.symbol.externaldrive'),
              '管理副本',
              '',
              this.copiesSummaryText(),
              true,
              false,
              () => {
                this.activeSheet = 'copies';
              }
            )
          }
          .width('100%')
          .backgroundColor($r('app.color.panel'))
          .borderRadius(16)
          .clip(true)

          Text('Kelivo 会定期在本机存一份数据库副本，让数据不只有一份。')
            .fontSize(12)
            .lineHeight(18)
            .fontColor($r('app.color.muted'))
            .width('100%')
            .padding({ left: 12, right: 12, top: 8 })

          // Section 5: WebDAV 备份
          KelivoSectionHeader({ titleText: 'WebDAV 备份', topSpacing: 14 })
          Column() {
            this.navRow(
              $r('sys.symbol.gearshape'),
              'WebDAV 服务器设置',
              '',
              '',
              true,
              true,
              () => {
                this.davShowPass = false;
                this.activeSheet = 'webdav_settings';
              }
            )
            this.navRow(
              $r('sys.symbol.link'),
              '测试连接',
              '',
              '',
              true,
              true,
              () => { this.testRemoteConnection('webdav').catch(() => {}); }
            )
            this.navRow(
              $r('sys.symbol.arrow_down_circle'),
              '恢复',
              '',
              '',
              true,
              true,
              () => { this.openRemoteRestoreList('webdav').catch(() => {}); }
            )
            this.navRow(
              $r('sys.symbol.arrow_up_circle'),
              '立即备份',
              '',
              '',
              true,
              false,
              () => { this.backupRemoteNow('webdav').catch(() => {}); }
            )
          }
          .width('100%')
          .backgroundColor($r('app.color.panel'))
          .borderRadius(16)
          .clip(true)

          // Section 6: S3 备份
          KelivoSectionHeader({ titleText: 'S3 备份', topSpacing: 14 })
          Column() {
            this.navRow(
              $r('sys.symbol.gearshape'),
              'S3 设置',
              '',
              '',
              true,
              true,
              () => {
                this.s3ShowSecret = false;
                this.s3ShowToken = false;
                this.activeSheet = 's3_settings';
              }
            )
            this.navRow(
              $r('sys.symbol.link'),
              '测试连接',
              '',
              '',
              true,
              true,
              () => { this.testRemoteConnection('s3').catch(() => {}); }
            )
            this.navRow(
              $r('sys.symbol.arrow_down_circle'),
              '恢复',
              '',
              '',
              true,
              true,
              () => { this.openRemoteRestoreList('s3').catch(() => {}); }
            )
            this.navRow(
              $r('sys.symbol.arrow_up_circle'),
              '立即备份',
              '',
              '',
              true,
              false,
              () => { this.backupRemoteNow('s3').catch(() => {}); }
            )
          }
          .width('100%')
          .backgroundColor($r('app.color.panel'))
          .borderRadius(16)
          .clip(true)
        }
        .width('100%')
        .padding({
          left: 14,
          right: 14,
          top: this.embeddedInNav ? (58 + this.winTopInset) : 6,
          bottom: 28 + this.winBottomInset
        })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .bindSheet(this.activeSheet.length > 0, this.unifiedSheetBuilder(), {
      detents: this.sheetDetents(),
      preferType: SheetType.BOTTOM,
      showClose: false,
      backgroundColor: Color.Transparent,
      blurStyle: BlurStyle.COMPONENT_ULTRA_THICK,
      onDisappear: () => {
        this.activeSheet = '';
        this.settlePendingResolvers();
      }
    })
  }

  private sheetDetents(): [SheetSize | Length, (SheetSize | Length)?, (SheetSize | Length)?] {
    if (this.activeSheet === 'scope' || this.activeSheet === 'copies' ||
      this.activeSheet === 's3_settings' || this.activeSheet === 'webdav_settings' ||
      this.activeSheet === 'remote_list') {
      return [SheetSize.LARGE];
    }
    return [SheetSize.FIT_CONTENT, SheetSize.LARGE];
  }

  private submitPasswordSheet(): void {
    const p1 = this.passwordInput;
    if (!p1) return;
    if ((this.passwordMode === 'create' || this.passwordMode === 'change') && p1 !== this.passwordConfirm) {
      return;
    }
    const resolver = this.pwdResolver;
    this.pwdResolver = undefined;
    this.activeSheet = '';
    if (resolver) resolver(p1);
  }

  // ===== Single Unified Sheet Router =====
  @Builder
  private unifiedSheetBuilder() {
    if (this.activeSheet === 'scope') {
      BackupScopeSheet({
        draftScope: this.draftScope,
        onSave: () => {
          const next = cloneBackupPreferences(this.cfg);
          next.scope = normalizeBackupScope(this.draftScope);
          this.saveCfg(next);
          this.activeSheet = '';
          this.showToast('备份范围已保存 (' + countSelectedBackupScope(next.scope) + '/15)');
        },
        onClose: () => { this.activeSheet = ''; }
      })
    } else if (this.activeSheet === 'password') {
      BackupPasswordSheet({
        passwordMode: this.passwordMode,
        passwordInput: this.passwordInput,
        passwordConfirm: this.passwordConfirm,
        passwordRememberDraft: this.passwordRememberDraft,
        passwordShowText: this.passwordShowText,
        passwordRetryError: this.passwordRetryError,
        onCancel: () => {
          const resolver = this.pwdResolver;
          this.pwdResolver = undefined;
          this.activeSheet = '';
          if (resolver) resolver(undefined);
        },
        onSubmit: () => { this.submitPasswordSheet(); }
      })
    } else if (this.activeSheet === 'import_mode') {
      BackupImportModeSheet({
        onSelectMode: (mode: 'overwrite' | 'merge' | undefined) => {
          const resolver = this.modeResolver;
          this.modeResolver = undefined;
          this.activeSheet = '';
          if (resolver) resolver(mode);
        }
      })
    } else if (this.activeSheet === 'cherry_warn') {
      BackupCherryWarnSheet({
        onConfirm: (ok: boolean) => {
          const resolver = this.cherryResolver;
          this.cherryResolver = undefined;
          this.activeSheet = '';
          if (resolver) resolver(ok);
        }
      })
    } else if (this.activeSheet === 'reminder_freq') {
      BackupReminderFreqSheet({
        currentDays: this.cfg.reminderIntervalDays,
        customDaysInput: this.reminderCustomDaysInput,
        onSelectDays: (days: number) => {
          const next = cloneBackupPreferences(this.cfg);
          next.reminderIntervalDays = days;
          this.saveCfg(next);
          this.activeSheet = '';
        },
        onInvalidInput: (msg: string) => {
          this.showToast(msg, true);
        }
      })
    } else if (this.activeSheet === 'reminder_time') {
      BackupReminderTimeSheet({
        hourInput: this.reminderHourInput,
        minuteInput: this.reminderMinuteInput,
        onSaveMinutes: (minutesOfDay: number) => {
          const next = cloneBackupPreferences(this.cfg);
          next.reminderMinutesOfDay = minutesOfDay;
          this.saveCfg(next);
          this.activeSheet = '';
        },
        onCancel: () => { this.activeSheet = ''; }
      })
    } else if (this.activeSheet === 'copies') {
      BackupLocalCopiesSheet({
        cfg: this.cfg,
        snapshots: this.snapshots,
        busy: this.busy,
        summaryText: this.copiesSummaryText(),
        onUpdateCfg: (next: BackupPreferencesConfig) => { this.saveCfg(next); },
        onTakeCopyNow: () => { this.doTakeCopyNow().catch(() => {}); },
        onRestoreCopy: (snap: LocalSnapshotMeta) => { this.doRestoreCopyConfirm(snap); },
        onExportCopy: (snap: LocalSnapshotMeta) => { this.doExportCopy(snap).catch(() => {}); },
        onDeleteCopy: (snap: LocalSnapshotMeta) => { this.doDeleteCopyConfirm(snap); },
        onTogglePin: (snap: LocalSnapshotMeta) => { this.toggleCopyPinned(snap); },
        onClose: () => { this.activeSheet = ''; }
      })
    } else if (this.activeSheet === 'webdav_settings') {
      BackupWebDavSettingsSheet({
        davUrl: this.davUrl,
        davUser: this.davUser,
        davPass: this.davPass,
        davPath: this.davPath,
        davUserAgent: this.davUserAgent,
        davShowPass: this.davShowPass,
        onSave: () => { this.saveWebDavForm().catch(() => {}); },
        onClose: () => { this.activeSheet = ''; }
      })
    } else if (this.activeSheet === 's3_settings') {
      BackupS3SettingsSheet({
        s3Endpoint: this.s3Endpoint,
        s3Region: this.s3Region,
        s3Bucket: this.s3Bucket,
        s3AccessKey: this.s3AccessKey,
        s3SecretKey: this.s3SecretKey,
        s3SessionToken: this.s3SessionToken,
        s3Prefix: this.s3Prefix,
        s3UserAgent: this.s3UserAgent,
        s3PathStyle: this.s3PathStyle,
        s3ShowSecret: this.s3ShowSecret,
        s3ShowToken: this.s3ShowToken,
        onSave: () => { this.saveS3Form().catch(() => {}); },
        onClose: () => { this.activeSheet = ''; }
      })
    } else if (this.activeSheet === 'remote_list') {
      BackupRemoteListSheet({
        items: this.remoteItems,
        loading: this.remoteLoading,
        onRestore: (item: RemoteBackupEntry) => { this.restoreRemoteItem(item).catch(() => {}); },
        onDelete: (item: RemoteBackupEntry) => { this.confirmDeleteRemoteItem(item); },
        onClose: () => { this.activeSheet = ''; }
      })
    } else {
      Column() {}
    }
  }
}
