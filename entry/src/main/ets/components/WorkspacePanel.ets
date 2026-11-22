import { common } from '@kit.AbilityKit';
import { EnvVar, LocalWorkspace } from '../core/Models';
import { forgetKey, newId, storeKey } from '../core/Storage';
import {
  WorkspaceFileItem,
  createSandboxWorkspace,
  deleteWorkspaceItem,
  importPickerFilesToWorkspace,
  listWorkspaceTree,
  readWorkspaceText,
  writeWorkspaceText
} from '../core/WorkspaceTools';
import { KelivoPageHeader } from './KelivoChrome';

@Component
export struct WorkspacePanel {
  @Prop workspaces: LocalWorkspace[] = [];
  @Prop activeWorkspaceId: string = '';
  @Prop envVars: EnvVar[] = [];
  @Prop filesDir: string = '';
  @Prop embeddedInNav: boolean = false;

  onSaveWorkspaces: (list: LocalWorkspace[], activeWsId: string) => Promise<void> = async () => {};
  onSaveEnvVars: (vars: EnvVar[]) => Promise<void> = async () => {};
  onOpenHtmlPreview: (title: string, html: string) => void = () => {};
  onClose: () => void = () => {};

  @StorageProp('windowTopInsetVp') winTopInset: number = 0;

  @State currentTab: number = 0; // 0: 工作区与文件, 1: 环境变量
  @State selectedWsId: string = '';
  @State newWsName: string = '';
  @State files: WorkspaceFileItem[] = [];
  @State editingRelPath: string = '';
  @State editingText: string = '';
  @State newFilePath: string = '';
  @State newEnvKey: string = '';
  @State newEnvVal: string = '';
  @State statusTip: string = '';

  aboutToAppear(): void {
    if (this.activeWorkspaceId.length > 0) {
      this.selectedWsId = this.activeWorkspaceId;
    } else if (this.workspaces.length > 0) {
      this.selectedWsId = this.workspaces[0].id;
    }
    this.reloadFiles().catch(() => {});
  }

  private hostCtx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private currentWs(): LocalWorkspace | undefined {
    return this.workspaces.find((w: LocalWorkspace): boolean => w.id === this.selectedWsId) ?? this.workspaces[0];
  }

  private async reloadFiles(): Promise<void> {
    const ws = this.currentWs();
    if (!ws) {
      this.files = [];
      return;
    }
    this.files = await listWorkspaceTree(ws.rootPath, '', true);
  }

  private async createWorkspace(): Promise<void> {
    if (this.filesDir.length === 0) {
      this.statusTip = '应用沙箱目录未就绪';
      return;
    }
    const id = 'ws_' + newId();
    const label = this.newWsName.trim().length > 0 ? this.newWsName.trim() : `项目工作区 ${this.workspaces.length + 1}`;
    const created = await createSandboxWorkspace(this.filesDir, id, label);
    const next = [...this.workspaces, created];
    this.newWsName = '';
    this.selectedWsId = created.id;
    await this.onSaveWorkspaces(next, created.id);
    await this.reloadFiles();
    this.statusTip = `已创建并绑定工作区：${label}`;
  }

  private async openFile(item: WorkspaceFileItem): Promise<void> {
    const ws = this.currentWs();
    if (!ws || item.isDir) {
      return;
    }
    try {
      const content = await readWorkspaceText(ws.rootPath, item.relPath);
      this.editingRelPath = item.relPath;
      this.editingText = content;
    } catch (e) {
      this.statusTip = `无法读取文本内容: ${(e as Error).message || String(e)}`;
    }
  }

  private async saveEditedFile(): Promise<void> {
    const ws = this.currentWs();
    if (!ws || this.editingRelPath.length === 0) {
      return;
    }
    await writeWorkspaceText(ws.rootPath, this.editingRelPath, this.editingText);
    await this.reloadFiles();
    this.statusTip = `已保存 ${this.editingRelPath}`;
  }

  private async createNewFile(): Promise<void> {
    const ws = this.currentWs();
    const rel = this.newFilePath.trim();
    if (!ws || rel.length === 0) {
      this.statusTip = '请先选择工作区并输入文件名';
      return;
    }
    await writeWorkspaceText(ws.rootPath, rel, '');
    this.newFilePath = '';
    this.editingRelPath = rel;
    this.editingText = '';
    await this.reloadFiles();
    this.statusTip = `已新建文件 ${rel}`;
  }

  private async removeFile(item: WorkspaceFileItem): Promise<void> {
    const ws = this.currentWs();
    if (!ws) {
      return;
    }
    await deleteWorkspaceItem(ws.rootPath, item.relPath);
    if (this.editingRelPath === item.relPath) {
      this.editingRelPath = '';
      this.editingText = '';
    }
    await this.reloadFiles();
    this.statusTip = `已删除 ${item.relPath}`;
  }

  private async importFiles(): Promise<void> {
    const ws = this.currentWs();
    if (!ws) {
      this.statusTip = '请先创建一个工作区';
      return;
    }
    try {
      const n = await importPickerFilesToWorkspace(this.hostCtx(), ws.rootPath);
      if (n > 0) {
        await this.reloadFiles();
        this.statusTip = `已导入 ${n} 个文件到沙箱工作区`;
      }
    } catch (e) {
      this.statusTip = `导入失败: ${(e as Error).message || String(e)}`;
    }
  }

  private async addEnvVar(): Promise<void> {
    const k = this.newEnvKey.trim();
    const v = this.newEnvVal;
    if (k.length === 0 || v.length === 0) {
      this.statusTip = '请输入变量名和变量值';
      return;
    }
    const ref = 'env_' + newId();
    await storeKey(ref, v);
    const next = this.envVars.filter((item: EnvVar): boolean => item.key !== k);
    next.push({ id: 'ev_' + newId(), key: k, secretRef: ref, masked: true });
    this.newEnvKey = '';
    this.newEnvVal = '';
    await this.onSaveEnvVars(next);
    this.statusTip = `已安全存入系统 Asset 凭据库: ${k}`;
  }

  private async deleteEnvVar(item: EnvVar): Promise<void> {
    await forgetKey(item.secretRef).catch(() => {});
    await this.onSaveEnvVars(this.envVars.filter((e: EnvVar): boolean => e.id !== item.id));
    this.statusTip = `已移除环境变量 ${item.key}`;
  }

  @Builder
  private tabButton(label: string, idx: number) {
    Button(label)
      .type(ButtonType.Normal)
      .height(32)
      .fontSize(12)
      .fontColor(this.currentTab === idx ? $r('app.color.on_accent') : $r('app.color.ink'))
      .backgroundColor(this.currentTab === idx ? $r('app.color.accent') : $r('app.color.surface'))
      .borderRadius(16)
      .padding({ left: 12, right: 12 })
      .onClick(() => {
        this.currentTab = idx;
      })
  }

  @Builder
  private renderFilesTab() {
    Column({ space: 10 }) {
      Row({ space: 6 }) {
        TextInput({ text: this.newWsName, placeholder: '新建沙箱工作区名称...' })
          .layoutWeight(1)
          .height(38)
          .borderRadius(8)
          .backgroundColor($r('app.color.surface'))
          .onChange((v: string) => {
            this.newWsName = v;
          })
        Button('新建工作区')
          .type(ButtonType.Normal)
          .height(38)
          .fontSize(12)
          .borderRadius(8)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor($r('app.color.accent'))
          .onClick(async () => {
            await this.createWorkspace();
          })
      }
      .width('100%')

      Scroll() {
        Row({ space: 6 }) {
          ForEach(this.workspaces, (ws: LocalWorkspace) => {
            Button(`${ws.id === this.activeWorkspaceId ? '● ' : ''}${ws.name}`)
              .type(ButtonType.Normal)
              .height(32)
              .fontSize(12)
              .borderRadius(8)
              .fontColor(this.selectedWsId === ws.id ? $r('app.color.on_accent') : $r('app.color.ink'))
              .backgroundColor(this.selectedWsId === ws.id ? $r('app.color.accent') : $r('app.color.surface'))
              .onClick(async () => {
                this.selectedWsId = ws.id;
                this.editingRelPath = '';
                this.editingText = '';
                await this.reloadFiles();
              })
          }, (ws: LocalWorkspace) => ws.id)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      if (this.currentWs()) {
        Column({ space: 8 }) {
          Row({ space: 6 }) {
            Button(this.activeWorkspaceId === this.currentWs()!.id ? '✓ 当前对话已绑定' : '绑定到当前对话')
              .type(ButtonType.Normal)
              .height(30)
              .fontSize(11)
              .borderRadius(8)
              .fontColor(this.activeWorkspaceId === this.currentWs()!.id ? $r('app.color.on_accent') : $r('app.color.accent'))
              .backgroundColor(this.activeWorkspaceId === this.currentWs()!.id ? $r('app.color.accent') : $r('app.color.tint'))
              .onClick(async () => {
                const nextId = this.activeWorkspaceId === this.currentWs()!.id ? '' : this.currentWs()!.id;
                await this.onSaveWorkspaces(this.workspaces, nextId);
                this.statusTip = nextId ? `当前对话已绑定工作区 ${this.currentWs()!.name}` : '已解除绑定';
              })
            Button('导入本地文件')
              .type(ButtonType.Normal)
              .height(30)
              .fontSize(11)
              .borderRadius(8)
              .fontColor($r('app.color.ink'))
              .backgroundColor($r('app.color.surface'))
              .onClick(async () => {
                await this.importFiles();
              })
            Blank()
            Button('刷新')
              .type(ButtonType.Normal)
              .height(30)
              .fontSize(11)
              .borderRadius(8)
              .fontColor($r('app.color.ink'))
              .backgroundColor($r('app.color.surface'))
              .onClick(async () => {
                await this.reloadFiles();
              })
          }
          .width('100%')

          Row({ space: 6 }) {
            TextInput({ text: this.newFilePath, placeholder: '新建文件路径 (如 notes/plan.md)' })
              .layoutWeight(1)
              .height(36)
              .borderRadius(8)
              .backgroundColor($r('app.color.surface'))
              .onChange((v: string) => {
                this.newFilePath = v;
              })
            Button('创建文件')
              .type(ButtonType.Normal)
              .height(36)
              .fontSize(12)
              .borderRadius(8)
              .fontColor($r('app.color.accent'))
              .backgroundColor($r('app.color.tint'))
              .onClick(async () => {
                await this.createNewFile();
              })
          }
          .width('100%')

          if (this.editingRelPath.length > 0) {
            Column({ space: 6 }) {
              Row({ space: 6 }) {
                Text(`编辑：${this.editingRelPath}`)
                  .fontSize(12)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.accent'))
                  .layoutWeight(1)
                if (this.editingRelPath.toLowerCase().endsWith('.html') || this.editingRelPath.toLowerCase().endsWith('.htm')) {
                  Button('预览HTML')
                    .type(ButtonType.Normal)
                    .height(26)
                    .fontSize(11)
                    .borderRadius(6)
                    .fontColor($r('app.color.ink'))
                    .backgroundColor($r('app.color.canvas'))
                    .onClick(() => {
                      this.onOpenHtmlPreview(this.editingRelPath, this.editingText);
                    })
                }
                Button('保存')
                  .type(ButtonType.Normal)
                  .height(26)
                  .fontSize(11)
                  .borderRadius(6)
                  .fontColor($r('app.color.on_accent'))
                  .backgroundColor($r('app.color.accent'))
                  .onClick(async () => {
                    await this.saveEditedFile();
                  })
                Button('收起')
                  .type(ButtonType.Normal)
                  .height(26)
                  .fontSize(11)
                  .borderRadius(6)
                  .fontColor($r('app.color.muted'))
                  .backgroundColor($r('app.color.canvas'))
                  .onClick(() => {
                    this.editingRelPath = '';
                    this.editingText = '';
                  })
              }
              .width('100%')

              TextArea({ text: this.editingText, placeholder: '文件内容...' })
                .height(170)
                .borderRadius(8)
                .backgroundColor($r('app.color.canvas'))
                .onChange((v: string) => {
                  this.editingText = v;
                })
            }
            .padding(10)
            .backgroundColor($r('app.color.surface'))
            .borderRadius(10)
            .width('100%')
          }

          if (this.files.length === 0) {
            Text('工作区暂无文件，可新建、从系统选择导入或由 AI 工具写入。')
              .fontSize(12)
              .fontColor($r('app.color.muted'))
              .padding(12)
          } else {
            ForEach(this.files, (item: WorkspaceFileItem) => {
              Row({ space: 8 }) {
                Text(item.isDir ? '📂' : '📄')
                  .fontSize(15)
                Column({ space: 2 }) {
                  Text(item.relPath)
                    .fontSize(13)
                    .fontColor($r('app.color.ink'))
                  Text(item.isDir ? '目录' : `${item.sizeBytes} B`)
                    .fontSize(10)
                    .fontColor($r('app.color.muted'))
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                .onClick(async () => {
                  await this.openFile(item);
                })

                if (!item.isDir) {
                  Button('打开')
                    .type(ButtonType.Normal)
                    .height(26)
                    .fontSize(11)
                    .borderRadius(6)
                    .fontColor($r('app.color.accent'))
                    .backgroundColor($r('app.color.tint'))
                    .onClick(async () => {
                      await this.openFile(item);
                    })
                }
                Button('删')
                  .type(ButtonType.Normal)
                  .height(26)
                  .fontSize(11)
                  .borderRadius(6)
                  .fontColor($r('app.color.warning'))
                  .backgroundColor($r('app.color.canvas'))
                  .onClick(async () => {
                    await this.removeFile(item);
                  })
              }
              .padding(10)
              .backgroundColor($r('app.color.surface'))
              .borderRadius(10)
              .width('100%')
            }, (item: WorkspaceFileItem) => item.relPath + '_' + item.sizeBytes)
          }
        }
        .width('100%')
      } else {
        Text('尚无本地沙箱工作区，请在上方输入名称并创建。受系统沙箱隔离保护，AI 仅能访问已绑定的工作区目录。')
          .fontSize(12)
          .fontColor($r('app.color.muted'))
          .padding(12)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private renderEnvVarsTab() {
    Column({ space: 10 }) {
      Text('环境变量加密存储于 HarmonyOS Asset Store，工具返回结果中的敏感值会自动脱敏为 ***。')
        .fontSize(12)
        .fontColor($r('app.color.muted'))

      Column({ space: 6 }) {
        TextInput({ text: this.newEnvKey, placeholder: '变量名（如 GITHUB_TOKEN）' })
          .height(38)
          .borderRadius(8)
          .backgroundColor($r('app.color.canvas'))
          .onChange((v: string) => {
            this.newEnvKey = v;
          })
        TextInput({ text: this.newEnvVal, placeholder: '敏感变量值...' })
          .height(38)
          .type(InputType.Password)
          .borderRadius(8)
          .backgroundColor($r('app.color.canvas'))
          .onChange((v: string) => {
            this.newEnvVal = v;
          })
        Button('保存环境变量')
          .type(ButtonType.Normal)
          .height(36)
          .fontSize(12)
          .borderRadius(8)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor($r('app.color.accent'))
          .onClick(async () => {
            await this.addEnvVar();
          })
      }
      .padding(10)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(10)
      .width('100%')

      ForEach(this.envVars, (ev: EnvVar) => {
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text(ev.key)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))
            Text('••••••••（已在输出中启用自动脱敏）')
              .fontSize(11)
              .fontColor($r('app.color.muted'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button('删除')
            .type(ButtonType.Normal)
            .height(28)
            .fontSize(11)
            .fontColor($r('app.color.warning'))
            .backgroundColor($r('app.color.canvas'))
            .onClick(async () => {
              await this.deleteEnvVar(ev);
            })
        }
        .padding(10)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(10)
        .width('100%')
      }, (ev: EnvVar) => ev.id)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  build() {
    Column({ space: 10 }) {
      if (!this.embeddedInNav) {
        KelivoPageHeader({
          titleText: '本地沙箱工作区',
          showBack: true,
          onBack: () => { this.onClose(); }
        })
      }

      Row({ space: 8 }) {
        this.tabButton('沙箱文件', 0)
        this.tabButton('环境变量', 1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: this.embeddedInNav ? (56 + this.winTopInset + 4) : 0 })

      if (this.statusTip.length > 0) {
        Text(this.statusTip)
          .fontSize(12)
          .fontColor($r('app.color.accent'))
          .padding({ left: 16, right: 16 })
          .width('100%')
      }

      Scroll() {
        Column({ space: 10 }) {
          if (this.currentTab === 0) {
            this.renderFilesTab()
          } else {
            this.renderEnvVarsTab()
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 48 })
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
