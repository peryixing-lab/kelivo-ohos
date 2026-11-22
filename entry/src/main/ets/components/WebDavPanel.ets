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

type BackupScopeKey = 'chats' | 'attachments' | 'assistants' | 'providers' | 'mcp' | 'envVars' | 'skills' | 'worldBooks' | 'memory' | 'quickPhrases' | 'instructions' | 'workspaces' | 'search' | 'speech' | 'settings';

interface ScopeCategoryMeta {
  key: BackupScopeKey;
  label: string;
  symbol: Resource;
}

interface RemoteBackupEntry {
  kind: 'webdav' | 's3';
  name: string;
  remoteKey: string;
  sizeBytes: number;
  lastModified: string;
}

const SCOPE_GROUP_MEDIA: ScopeCategoryMeta[] = [
  { key: 'chats', label: '聊天记录', symbol: $r('sys.symbol.ellipsis_bubble') },
  { key: 'attachments', label: '文件与图片', symbol: $r('sys.symbol.doc_text') }
];

const SCOPE_GROUP_DATA: ScopeCategoryMeta[] = [
  { key: 'assistants', label: '助手', symbol: $r('sys.symbol.person') },
  { key: 'providers', label: '供应商', symbol: $r('sys.symbol.square_grid_2x2') },
  { key: 'mcp', label: 'MCP 服务器', symbol: $r('sys.symbol.wrench_and_screwdriver') },
  { key: 'envVars', label: '环境变量', symbol: $r('sys.symbol.lightbulb') },
  { key: 'skills', label: '技能', symbol: $r('sys.symbol.bolt') },
  { key: 'worldBooks', label: '世界书', symbol: $r('sys.symbol.book') },
  { key: 'memory', label: '记忆', symbol: $r('sys.symbol.compass') },
  { key: 'quickPhrases', label: '快捷短语', symbol: $r('sys.symbol.message') },
  { key: 'instructions', label: '提示词注入', symbol: $r('sys.symbol.slider_horizontal_2') },
  { key: 'workspaces', label: '工作区', symbol: $r('sys.symbol.folder') },
  { key: 'search', label: '搜索服务', symbol: $r('sys.symbol.magnifyingglass') },
  { key: 'speech', label: '语音服务', symbol: $r('sys.symbol.speaker_wave_2') },
  { key: 'settings', label: '其他设置', symbol: $r('sys.symbol.gearshape') }
];

const REMINDER_DAY_PRESETS: number[] = [1, 3, 7, 14, 30];
const COPY_INTERVAL_PRESETS: number[] = [0, 1, 3, 7, 14, 30];
const COPY_KEEP_PRESETS: number[] = [1, 2, 3, 5, 7, 10];
const COPY_MAX_BYTES_PRESETS: number[] = [
  0,
  1024 * 1024 * 1024,
  2 * 1024 * 1024 * 1024,
  5 * 1024 * 1024 * 1024,
  10 * 1024 * 1024 * 1024
];

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

  // Local copies sheet state
  @State copiesPicker: '' | 'freq' | 'keep' | 'max' = '';

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

  private cloneCfg(): BackupPreferencesConfig {
    return {
      scope: normalizeBackupScope(this.cfg.scope),
      encryptionEnabled: this.cfg.encryptionEnabled,
      rememberPassword: this.cfg.rememberPassword,
      passwordVerifier: this.cfg.passwordVerifier,
      passwordSecretRef: this.cfg.passwordSecretRef,
      reminderEnabled: this.cfg.reminderEnabled,
      reminderIntervalDays: this.cfg.reminderIntervalDays,
      reminderMinutesOfDay: this.cfg.reminderMinutesOfDay,
      lastBackupAt: this.cfg.lastBackupAt,
      localCopiesEnabled: this.cfg.localCopiesEnabled,
      localCopiesIntervalDays: this.cfg.localCopiesIntervalDays,
      localCopiesKeepRecent: this.cfg.localCopiesKeepRecent,
      localCopiesKeepWeekly: this.cfg.localCopiesKeepWeekly,
      localCopiesKeepMonthly: this.cfg.localCopiesKeepMonthly,
      localCopiesMaxBytes: this.cfg.localCopiesMaxBytes,
      localCopiesLastSuccessAt: this.cfg.localCopiesLastSuccessAt,
      localCopiesLastError: this.cfg.localCopiesLastError
    };
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
      const next = this.cloneCfg();
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
    const next = this.cloneCfg();
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
    const next = this.cloneCfg();
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
    const next = this.cloneCfg();
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
      const next = this.cloneCfg();
      next.localCopiesLastSuccessAt = Date.now();
      next.localCopiesLastError = undefined;
      this.saveCfg(next);
      this.onUpdateSnapshots(this.snapshots);
      this.showToast('副本已保存');
    } catch (e) {
      const next = this.cloneCfg();
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
      message: '将创建当前数据的安全副本后，从 ' + this.formatTimeFull(snap.createdAt) + ' 的副本恢复。',
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
      message: this.formatTimeFull(snap.createdAt) + ' · ' + formatBytesReadable(snap.sizeBytes),
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

  // ===== Formatting Helpers =====
  private formatTimeFull(ms?: number): string {
    if (!ms) return '从未';
    const d = new Date(ms);
    const pad = (n: number): string => n < 10 ? ('0' + n) : String(n);
    return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate()) +
      ' ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
  }

  private reminderFreqText(days: number): string {
    if (days === 1) return '每天';
    if (days === 3) return '每 3 天';
    if (days === 7) return '每周';
    if (days === 14) return '每 14 天';
    if (days === 30) return '每月';
    return '每 ' + days + ' 天';
  }

  private reminderTimeText(minutes: number): string {
    const h = Math.floor(minutes / 60) % 24;
    const m = minutes % 60;
    return (h < 10 ? '0' : '') + h + ':' + (m < 10 ? '0' : '') + m;
  }

  private nextReminderText(): string {
    if (!this.cfg.reminderEnabled) return '未开启';
    const baseMs = this.cfg.lastBackupAt || Date.now();
    const intervalMs = Math.max(1, this.cfg.reminderIntervalDays) * 24 * 3600 * 1000;
    const target = new Date(baseMs + intervalMs);
    const h = Math.floor(this.cfg.reminderMinutesOfDay / 60) % 24;
    const m = this.cfg.reminderMinutesOfDay % 60;
    target.setHours(h, m, 0, 0);
    if (target.getTime() <= Date.now()) return '已到期，建议尽快备份';
    return this.formatTimeFull(target.getTime());
  }

  private copyIntervalText(days: number): string {
    if (days <= 0) return '自动';
    return this.reminderFreqText(days);
  }

  private encryptionSubtitle(): string {
    if (!this.cfg.encryptionEnabled) return '未加密的备份可被直接读取。';
    if (this.cfg.rememberPassword) return '备份将加密保存，密码已记在本机。';
    return '备份将加密保存，重启应用后需重新输入口令。';
  }

  private setDraftScopeCategory(key: BackupScopeKey, val: boolean): void {
    const s = normalizeBackupScope(this.draftScope);
    if (key === 'chats') s.chats = val;
    else if (key === 'attachments') s.attachments = val;
    else if (key === 'assistants') s.assistants = val;
    else if (key === 'providers') s.providers = val;
    else if (key === 'mcp') s.mcp = val;
    else if (key === 'envVars') s.envVars = val;
    else if (key === 'skills') s.skills = val;
    else if (key === 'worldBooks') s.worldBooks = val;
    else if (key === 'memory') s.memory = val;
    else if (key === 'quickPhrases') s.quickPhrases = val;
    else if (key === 'instructions') s.instructions = val;
    else if (key === 'workspaces') s.workspaces = val;
    else if (key === 'search') s.search = val;
    else if (key === 'speech') s.speech = val;
    else if (key === 'settings') s.settings = val;
    this.draftScope = s;
  }

  private getDraftScopeCategory(key: BackupScopeKey): boolean {
    const s = this.draftScope;
    if (key === 'chats') return s.chats;
    if (key === 'attachments') return s.attachments;
    if (key === 'assistants') return s.assistants;
    if (key === 'providers') return s.providers;
    if (key === 'mcp') return s.mcp;
    if (key === 'envVars') return s.envVars;
    if (key === 'skills') return s.skills;
    if (key === 'worldBooks') return s.worldBooks;
    if (key === 'memory') return s.memory;
    if (key === 'quickPhrases') return s.quickPhrases;
    if (key === 'instructions') return s.instructions;
    if (key === 'workspaces') return s.workspaces;
    if (key === 'search') return s.search;
    if (key === 'speech') return s.speech;
    return s.settings;
  }

  private setAllDraftScope(enabled: boolean): void {
    this.draftScope = {
      chats: enabled,
      attachments: enabled,
      assistants: enabled,
      providers: enabled,
      mcp: enabled,
      envVars: enabled,
      skills: enabled,
      worldBooks: enabled,
      memory: enabled,
      quickPhrases: enabled,
      instructions: enabled,
      workspaces: enabled,
      search: enabled,
      speech: enabled,
      settings: enabled
    };
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
                const next = this.cloneCfg();
                next.reminderEnabled = v;
                this.saveCfg(next);
              }
            )
            if (this.cfg.reminderEnabled) {
              this.navRow(
                $r('sys.symbol.calendar'),
                '提醒频率',
                '',
                this.reminderFreqText(this.cfg.reminderIntervalDays),
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
                this.reminderTimeText(this.cfg.reminderMinutesOfDay),
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
                this.formatTimeFull(this.cfg.lastBackupAt),
                false,
                true,
                () => {}
              )
              this.navRow(
                $r('sys.symbol.clock'),
                '下次提醒',
                '',
                this.nextReminderText(),
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
                const next = this.cloneCfg();
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
                this.copiesPicker = '';
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

  // ===== Single Unified Sheet Router =====
  @Builder
  private unifiedSheetBuilder() {
    if (this.activeSheet === 'scope') {
      this.scopeSheet()
    } else if (this.activeSheet === 'password') {
      this.passwordSheet()
    } else if (this.activeSheet === 'import_mode') {
      this.importModeSheet()
    } else if (this.activeSheet === 'cherry_warn') {
      this.cherryWarnSheet()
    } else if (this.activeSheet === 'reminder_freq') {
      this.reminderFreqSheet()
    } else if (this.activeSheet === 'reminder_time') {
      this.reminderTimeSheet()
    } else if (this.activeSheet === 'copies') {
      this.copiesSheet()
    } else if (this.activeSheet === 'webdav_settings') {
      this.webDavSettingsSheet()
    } else if (this.activeSheet === 's3_settings') {
      this.s3SettingsSheet()
    } else if (this.activeSheet === 'remote_list') {
      this.remoteListSheet()
    } else {
      Column() {}
    }
  }

  // --- Sheet 1: 15-Category Backup Scope Editor ---
  @Builder
  private scopeItemRow(item: ScopeCategoryMeta, showDivider: boolean) {
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

        Toggle({ type: ToggleType.Switch, isOn: this.getDraftScopeCategory(item.key) })
          .onChange((val: boolean) => {
            this.setDraftScopeCategory(item.key, val);
          })
          .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLight))
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .onClick(() => {
        this.setDraftScopeCategory(item.key, !this.getDraftScopeCategory(item.key));
      })

      if (showDivider) {
        Divider().strokeWidth(0.5).color($r('app.color.line')).margin({ left: 50, right: 14 })
      }
    }
    .width('100%')
  }

  @Builder
  private scopeSheet() {
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
          .onClick(() => {
            const next = this.cloneCfg();
            next.scope = normalizeBackupScope(this.draftScope);
            this.saveCfg(next);
            this.activeSheet = '';
            this.showToast('备份范围已保存 (' + countSelectedBackupScope(next.scope) + '/15)');
          })
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(17).fontColor([$r('app.color.muted')])
        }
        .width(34)
        .height(34)
        .onClick(() => { this.activeSheet = ''; })
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
              .onClick(() => { this.setAllDraftScope(true); })
            Text('全不选')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.muted'))
              .padding({ left: 8, right: 4, top: 4, bottom: 4 })
              .onClick(() => { this.setAllDraftScope(false); })
          }
          .width('100%')
          .padding({ left: 4, right: 4, bottom: 8 })

          Column() {
            ForEach(SCOPE_GROUP_MEDIA, (item: ScopeCategoryMeta, idx: number) => {
              this.scopeItemRow(item, idx < SCOPE_GROUP_MEDIA.length - 1)
            }, (item: ScopeCategoryMeta): string => item.key)
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
            ForEach(SCOPE_GROUP_DATA, (item: ScopeCategoryMeta, idx: number) => {
              this.scopeItemRow(item, idx < SCOPE_GROUP_DATA.length - 1)
            }, (item: ScopeCategoryMeta): string => item.key)
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

  // --- Sheet 2: Password Setup / Change / Unlock ---
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

  @Builder
  private passwordSheet() {
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
          .onClick(() => {
            const resolver = this.pwdResolver;
            this.pwdResolver = undefined;
            this.activeSheet = '';
            if (resolver) resolver(undefined);
          })
        Button(this.passwordMode === 'unlock' ? '解锁' : '保存')
          .layoutWeight(1)
          .height(42)
          .fontColor('#FFFFFF')
          .backgroundColor($r('app.color.accent'))
          .borderRadius(12)
          .enabled(this.passwordInput.length > 0 &&
            (this.passwordMode === 'unlock' || this.passwordMode === 'manual' || this.passwordInput === this.passwordConfirm))
          .onClick(() => { this.submitPasswordSheet(); })
      }
      .width('100%')
      .padding({ top: 4 })
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 18, bottom: 24 + this.winBottomInset })
  }

  // --- Sheet 3: Select Import Mode (Overwrite vs Merge) ---
  @Builder
  private importModeSheet() {
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
      .onClick(() => {
        const resolver = this.modeResolver;
        this.modeResolver = undefined;
        this.activeSheet = '';
        if (resolver) resolver('overwrite');
      })

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
      .onClick(() => {
        const resolver = this.modeResolver;
        this.modeResolver = undefined;
        this.activeSheet = '';
        if (resolver) resolver('merge');
      })

      Button('取消')
        .width('100%')
        .height(42)
        .fontColor($r('app.color.ink'))
        .backgroundColor($r('app.color.panel'))
        .borderRadius(12)
        .onClick(() => {
          const resolver = this.modeResolver;
          this.modeResolver = undefined;
          this.activeSheet = '';
          if (resolver) resolver(undefined);
        })
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 18, bottom: 24 + this.winBottomInset })
  }

  // --- Sheet 4: Cherry Studio Experimental Warning ---
  @Builder
  private cherryWarnSheet() {
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
          .onClick(() => {
            const resolver = this.cherryResolver;
            this.cherryResolver = undefined;
            this.activeSheet = '';
            if (resolver) resolver(false);
          })
        Button('好的')
          .layoutWeight(1)
          .height(42)
          .fontColor('#FFFFFF')
          .backgroundColor($r('app.color.accent'))
          .borderRadius(12)
          .onClick(() => {
            const resolver = this.cherryResolver;
            this.cherryResolver = undefined;
            this.activeSheet = '';
            if (resolver) resolver(true);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 18, bottom: 24 + this.winBottomInset })
  }

  // --- Sheet 5: Reminder Frequency ---
  @Builder
  private reminderFreqSheet() {
    Column({ space: 8 }) {
      Text('提醒频率')
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.ink'))
        .width('100%')
        .padding({ bottom: 4 })

      ForEach(REMINDER_DAY_PRESETS, (days: number) => {
        Row({ space: 10 }) {
          Text(this.reminderFreqText(days))
            .fontSize(15)
            .fontColor($r('app.color.ink'))
            .layoutWeight(1)
          if (this.cfg.reminderIntervalDays === days) {
            SymbolGlyph($r('sys.symbol.checkmark')).fontSize(17).fontColor([$r('app.color.accent')])
          }
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .borderRadius(12)
        .backgroundColor(this.cfg.reminderIntervalDays === days ? $r('app.color.tint') : $r('app.color.panel'))
        .onClick(() => {
          const next = this.cloneCfg();
          next.reminderIntervalDays = days;
          this.saveCfg(next);
          this.activeSheet = '';
        })
      }, (days: number): string => String(days))

      Row({ space: 8 }) {
        Text('自定义天数')
          .fontSize(14)
          .fontColor($r('app.color.muted'))
        TextInput({ text: this.reminderCustomDaysInput, placeholder: '1 - 365' })
          .type(InputType.Number)
          .layoutWeight(1)
          .height(40)
          .borderRadius(10)
          .backgroundColor($r('app.color.panel'))
          .onChange((v: string) => { this.reminderCustomDaysInput = v; })
        Button('应用')
          .height(38)
          .fontSize(13)
          .fontColor('#FFFFFF')
          .backgroundColor($r('app.color.accent'))
          .borderRadius(10)
          .onClick(() => {
            const parsed = Number(this.reminderCustomDaysInput);
            if (!Number.isFinite(parsed) || parsed < 1 || parsed > 365) {
              this.showToast('请输入 1 到 365 之间的整数', true);
              return;
            }
            const next = this.cloneCfg();
            next.reminderIntervalDays = Math.round(parsed);
            this.saveCfg(next);
            this.activeSheet = '';
          })
      }
      .width('100%')
      .padding({ top: 6 })
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 18, bottom: 24 + this.winBottomInset })
  }

  // --- Sheet 6: Reminder Time ---
  @Builder
  private reminderTimeSheet() {
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
          .onClick(() => { this.reminderHourInput = '9'; this.reminderMinuteInput = '00'; })
        Button('12:00')
          .layoutWeight(1)
          .height(36)
          .fontSize(13)
          .fontColor($r('app.color.ink'))
          .backgroundColor($r('app.color.panel'))
          .borderRadius(10)
          .onClick(() => { this.reminderHourInput = '12'; this.reminderMinuteInput = '00'; })
        Button('20:00')
          .layoutWeight(1)
          .height(36)
          .fontSize(13)
          .fontColor($r('app.color.ink'))
          .backgroundColor($r('app.color.panel'))
          .borderRadius(10)
          .onClick(() => { this.reminderHourInput = '20'; this.reminderMinuteInput = '00'; })
        Button('22:00')
          .layoutWeight(1)
          .height(36)
          .fontSize(13)
          .fontColor($r('app.color.ink'))
          .backgroundColor($r('app.color.panel'))
          .borderRadius(10)
          .onClick(() => { this.reminderHourInput = '22'; this.reminderMinuteInput = '00'; })
      }
      .width('100%')

      Row({ space: 8 }) {
        TextInput({ text: this.reminderHourInput, placeholder: '时 (0-23)' })
          .type(InputType.Number)
          .layoutWeight(1)
          .height(42)
          .borderRadius(10)
          .backgroundColor($r('app.color.panel'))
          .onChange((v: string) => { this.reminderHourInput = v; })
        Text(':')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ink'))
        TextInput({ text: this.reminderMinuteInput, placeholder: '分 (0-59)' })
          .type(InputType.Number)
          .layoutWeight(1)
          .height(42)
          .borderRadius(10)
          .backgroundColor($r('app.color.panel'))
          .onChange((v: string) => { this.reminderMinuteInput = v; })
      }
      .width('100%')

      Row({ space: 10 }) {
        Button('取消')
          .layoutWeight(1)
          .height(42)
          .fontColor($r('app.color.ink'))
          .backgroundColor($r('app.color.panel'))
          .borderRadius(12)
          .onClick(() => { this.activeSheet = ''; })
        Button('保存')
          .layoutWeight(1)
          .height(42)
          .fontColor('#FFFFFF')
          .backgroundColor($r('app.color.accent'))
          .borderRadius(12)
          .onClick(() => {
            const h = Math.max(0, Math.min(23, Math.round(Number(this.reminderHourInput) || 0)));
            const m = Math.max(0, Math.min(59, Math.round(Number(this.reminderMinuteInput) || 0)));
            const next = this.cloneCfg();
            next.reminderMinutesOfDay = h * 60 + m;
            this.saveCfg(next);
            this.activeSheet = '';
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 18, right: 18, top: 18, bottom: 24 + this.winBottomInset })
  }

  // --- Sheet 7: Manage Local Copies (Full Sub-page Equivalent) ---
  @Builder
  private copiesSheet() {
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
        .onClick(() => { this.activeSheet = ''; })
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
              '',
              this.cfg.localCopiesEnabled,
              this.cfg.localCopiesEnabled,
              (v: boolean) => {
                const next = this.cloneCfg();
                next.localCopiesEnabled = v;
                this.saveCfg(next);
              }
            )
            if (this.cfg.localCopiesEnabled) {
              this.navRow(
                $r('sys.symbol.arrow_clockwise'),
                '备份频率',
                '',
                this.copyIntervalText(this.cfg.localCopiesIntervalDays),
                true,
                true,
                () => { this.copiesPicker = this.copiesPicker === 'freq' ? '' : 'freq'; }
              )
              if (this.copiesPicker === 'freq') {
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(COPY_INTERVAL_PRESETS, (d: number) => {
                    Text(this.copyIntervalText(d))
                      .fontSize(12)
                      .fontColor(this.cfg.localCopiesIntervalDays === d ? '#FFFFFF' : $r('app.color.ink'))
                      .backgroundColor(this.cfg.localCopiesIntervalDays === d ? $r('app.color.accent') : $r('app.color.tint'))
                      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                      .borderRadius(12)
                      .margin({ right: 6, bottom: 6 })
                      .onClick(() => {
                        const next = this.cloneCfg();
                        next.localCopiesIntervalDays = d;
                        this.saveCfg(next);
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
                '',
                this.cfg.localCopiesKeepRecent + ' 份',
                true,
                true,
                () => { this.copiesPicker = this.copiesPicker === 'keep' ? '' : 'keep'; }
              )
              if (this.copiesPicker === 'keep') {
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(COPY_KEEP_PRESETS, (cnt: number) => {
                    Text(cnt + ' 份')
                      .fontSize(12)
                      .fontColor(this.cfg.localCopiesKeepRecent === cnt ? '#FFFFFF' : $r('app.color.ink'))
                      .backgroundColor(this.cfg.localCopiesKeepRecent === cnt ? $r('app.color.accent') : $r('app.color.tint'))
                      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                      .borderRadius(12)
                      .margin({ right: 6, bottom: 6 })
                      .onClick(() => {
                        const next = this.cloneCfg();
                        next.localCopiesKeepRecent = cnt;
                        this.saveCfg(next);
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
                '',
                this.cfg.localCopiesKeepWeekly,
                true,
                (v: boolean) => {
                  const next = this.cloneCfg();
                  next.localCopiesKeepWeekly = v;
                  this.saveCfg(next);
                }
              )
              this.switchRow(
                $r('sys.symbol.calendar'),
                '保留每月副本',
                '',
                this.cfg.localCopiesKeepMonthly,
                true,
                (v: boolean) => {
                  const next = this.cloneCfg();
                  next.localCopiesKeepMonthly = v;
                  this.saveCfg(next);
                }
              )
              this.navRow(
                $r('sys.symbol.externaldrive'),
                '占用上限',
                '',
                this.cfg.localCopiesMaxBytes <= 0 ? '不限制' : formatBytesReadable(this.cfg.localCopiesMaxBytes),
                true,
                false,
                () => { this.copiesPicker = this.copiesPicker === 'max' ? '' : 'max'; }
              )
              if (this.copiesPicker === 'max') {
                Flex({ wrap: FlexWrap.Wrap }) {
                  ForEach(COPY_MAX_BYTES_PRESETS, (lim: number) => {
                    Text(lim <= 0 ? '不限制' : formatBytesReadable(lim))
                      .fontSize(12)
                      .fontColor(this.cfg.localCopiesMaxBytes === lim ? '#FFFFFF' : $r('app.color.ink'))
                      .backgroundColor(this.cfg.localCopiesMaxBytes === lim ? $r('app.color.accent') : $r('app.color.tint'))
                      .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                      .borderRadius(12)
                      .margin({ right: 6, bottom: 6 })
                      .onClick(() => {
                        const next = this.cloneCfg();
                        next.localCopiesMaxBytes = lim;
                        this.saveCfg(next);
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
              ? ('上次成功备份：' + this.formatTimeFull(this.cfg.localCopiesLastSuccessAt))
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
            .onClick(() => { this.doTakeCopyNow().catch(() => {}); })

          KelivoSectionHeader({
            titleText: '本地副本 · ' + this.copiesSummaryText(),
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
                  Text(this.formatTimeFull(snap.createdAt))
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
                    .onClick(() => { this.doRestoreCopyConfirm(snap); })
                  Button('导出')
                    .layoutWeight(1)
                    .height(34)
                    .fontSize(13)
                    .fontColor($r('app.color.ink'))
                    .backgroundColor($r('app.color.tint'))
                    .borderRadius(10)
                    .onClick(() => { this.doExportCopy(snap).catch(() => {}); })
                  Button('删除')
                    .layoutWeight(1)
                    .height(34)
                    .fontSize(13)
                    .fontColor('#FFFFFF')
                    .backgroundColor('#D93838')
                    .borderRadius(10)
                    .onClick(() => { this.doDeleteCopyConfirm(snap); })
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
                .onClick(() => { this.toggleCopyPinned(snap); })
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

  // --- Sheet 8: WebDAV Server Settings ---
  @Builder
  private webDavSettingsSheet() {
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
        .onClick(() => { this.saveWebDavForm().catch(() => {}); })
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(17).fontColor([$r('app.color.muted')])
        }
        .width(34)
        .height(34)
        .onClick(() => { this.activeSheet = ''; })
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
            .onClick(() => { this.saveWebDavForm().catch(() => {}); })
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

  // --- Sheet 9: S3 Settings ---
  @Builder
  private s3SettingsSheet() {
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
        .onClick(() => { this.saveS3Form().catch(() => {}); })
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(17).fontColor([$r('app.color.muted')])
        }
        .width(34)
        .height(34)
        .onClick(() => { this.activeSheet = ''; })
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
            .onClick(() => { this.saveS3Form().catch(() => {}); })
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

  // --- Sheet 10: Remote Backups List (WebDAV / S3) ---
  @Builder
  private remoteListSheet() {
    Column() {
      Row({ space: 10 }) {
        Text('远端备份')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
          .layoutWeight(1)
        if (this.remoteLoading) {
          LoadingProgress().width(18).height(18).color($r('app.color.accent'))
        }
        Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
          SymbolGlyph($r('sys.symbol.xmark')).fontSize(17).fontColor([$r('app.color.muted')])
        }
        .width(34)
        .height(34)
        .onClick(() => { this.activeSheet = ''; })
      }
      .width('100%')
      .padding({ left: 18, right: 12, top: 14, bottom: 8 })

      Scroll() {
        Column({ space: 8 }) {
          if (!this.remoteLoading && this.remoteItems.length === 0) {
            Text('暂无备份')
              .fontSize(14)
              .fontColor($r('app.color.muted'))
              .padding({ top: 32, bottom: 32 })
          } else {
            ForEach(this.remoteItems, (item: RemoteBackupEntry) => {
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
                .onClick(() => { this.restoreRemoteItem(item).catch(() => {}); })

                Button({ type: ButtonType.Circle, buttonStyle: ButtonStyleMode.TEXTUAL }) {
                  SymbolGlyph($r('sys.symbol.trash')).fontSize(18).fontColor(['#D93838'])
                }
                .width(38)
                .height(38)
                .onClick(() => { this.confirmDeleteRemoteItem(item); })
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
