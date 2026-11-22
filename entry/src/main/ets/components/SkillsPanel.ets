import { common } from '@kit.AbilityKit';
import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { SkillRecord } from '../core/Models';
import { createSkillFromMarkdown, fetchSkillFromUrl, importSkillsFromPicker } from '../core/SkillsManager';

@Component
export struct SkillsPanel {
  @Prop skills: SkillRecord[] = [];
  @Prop embeddedInNav: boolean = false;
  onSaveSkills: (next: SkillRecord[]) => Promise<void> = async () => {};
  onClose: () => void = () => {};

  @StorageProp('immersiveLightEnabled') immersiveLightEnabled: boolean = true;
  @StorageProp('windowTopInsetVp') winTopInset: number = 0;

  @State githubUrl: string = '';
  @State busy: boolean = false;
  @State showCreateBox: boolean = false;
  @State customMd: string = '---\nname: my-skill\ndescription: 描述何时使用该技能\n---\n\n# 操作步骤\n1. ';
  @State previewId: string = '';
  @State statusTip: string = '';

  private hostCtx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private mergeSkillList(incoming: SkillRecord[]): SkillRecord[] {
    const next = this.skills.slice();
    for (let i = 0; i < incoming.length; i++) {
      const sk = incoming[i];
      const idx = next.findIndex((item: SkillRecord): boolean => item.name.toLowerCase() === sk.name.toLowerCase());
      if (idx >= 0) {
        next[idx] = {
          id: next[idx].id,
          name: sk.name,
          description: sk.description,
          markdown: sk.markdown,
          source: sk.source,
          sourceUrl: sk.sourceUrl,
          enabled: true,
          updatedAt: Date.now()
        };
      } else {
        next.push(sk);
      }
    }
    return next;
  }

  private async importFromGithub(): Promise<void> {
    if (this.githubUrl.trim().length === 0) {
      this.statusTip = '请输入 GitHub 仓库或 SKILL.md 链接';
      return;
    }
    this.busy = true;
    this.statusTip = '正在拉取 SKILL.md...';
    try {
      const sk = await fetchSkillFromUrl(this.githubUrl);
      await this.onSaveSkills(this.mergeSkillList([sk]));
      this.githubUrl = '';
      this.statusTip = `已安装 Skill: ${sk.name}`;
    } catch (e) {
      this.statusTip = `拉取失败: ${(e as Error).message || String(e)}`;
    } finally {
      this.busy = false;
    }
  }

  private async importLocal(): Promise<void> {
    this.busy = true;
    try {
      const imported = await importSkillsFromPicker(this.hostCtx());
      if (imported.length > 0) {
        await this.onSaveSkills(this.mergeSkillList(imported));
        this.statusTip = `已导入 ${imported.length} 个 Skill`;
      }
    } catch (e) {
      this.statusTip = `导入失败: ${(e as Error).message || String(e)}`;
    } finally {
      this.busy = false;
    }
  }

  private async saveCustomSkill(): Promise<void> {
    const clean = this.customMd.trim();
    if (clean.length === 0) {
      this.statusTip = '请填写 SKILL.md 内容';
      return;
    }
    const sk = createSkillFromMarkdown(clean, 'local');
    await this.onSaveSkills(this.mergeSkillList([sk]));
    this.showCreateBox = false;
    this.statusTip = `已保存自定义 Skill: ${sk.name}`;
  }

  build() {
    Column({ space: 12 }) {
      if (!this.embeddedInNav) {
        Row() {
          Text('Agent Skills 技能包')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.ink'))
          Blank()
          Button('关闭')
            .type(ButtonType.Normal)
            .height(32)
            .fontSize(12)
            .borderRadius(8)
            .fontColor($r('app.color.ink'))
            .backgroundColor($r('app.color.surface'))
            .onClick(() => this.onClose())
        }
        .width('100%')
      }

      Row({ space: 6 }) {
        TextInput({ text: this.githubUrl, placeholder: '输入 GitHub URL / raw SKILL.md 链接...' })
          .layoutWeight(1)
          .height(38)
          .borderRadius(8)
          .backgroundColor($r('app.color.surface'))
          .onChange((v: string) => {
            this.githubUrl = v;
          })
        Button(this.busy ? '...' : 'GitHub导入')
          .type(ButtonType.Normal)
          .height(38)
          .fontSize(12)
          .borderRadius(8)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor($r('app.color.accent'))
          .enabled(!this.busy)
          .onClick(async () => {
            await this.importFromGithub();
          })
      }
      .width('100%')

      Row({ space: 8 }) {
        Button('导入 .md / .zip')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(34)
          .fontSize(12)
          .borderRadius(8)
          .fontColor($r('app.color.accent'))
          .backgroundColor($r('app.color.tint'))
          .onClick(async () => {
            await this.importLocal();
          })
        Button(this.showCreateBox ? '收起编辑器' : '+ 手动编写 SKILL.md')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(34)
          .fontSize(12)
          .borderRadius(8)
          .fontColor($r('app.color.ink'))
          .backgroundColor($r('app.color.surface'))
          .onClick(() => {
            this.showCreateBox = !this.showCreateBox;
          })
      }
      .width('100%')

      if (this.statusTip.length > 0) {
        Text(this.statusTip)
          .fontSize(12)
          .fontColor($r('app.color.accent'))
      }

      Scroll() {
        Column({ space: 10 }) {
          if (this.showCreateBox) {
            Column({ space: 8 }) {
              TextArea({ text: this.customMd, placeholder: '粘贴或编写包含 YAML frontmatter 的 SKILL.md' })
                .height(150)
                .borderRadius(8)
                .backgroundColor($r('app.color.canvas'))
                .onChange((v: string) => {
                  this.customMd = v;
                })
              Button('保存并启用 Skill')
                .type(ButtonType.Normal)
                .width('100%')
                .height(36)
                .fontSize(12)
                .borderRadius(8)
                .fontColor($r('app.color.on_accent'))
                .backgroundColor($r('app.color.accent'))
                .onClick(async () => {
                  await this.saveCustomSkill();
                })
            }
            .padding(10)
            .backgroundColor($r('app.color.surface'))
            .borderRadius(10)
            .width('100%')
          }

          ForEach(this.skills, (sk: SkillRecord) => {
            Column({ space: 6 }) {
              Row({ space: 8 }) {
                Column({ space: 2 }) {
                  Row({ space: 6 }) {
                    Text(sk.name)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.ink'))
                    Text(sk.source === 'builtin' ? '内置' : (sk.source === 'github' ? 'GitHub' : '本地'))
                      .fontSize(10)
                      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                      .borderRadius(6)
                      .fontColor($r('app.color.accent'))
                      .backgroundColor($r('app.color.tint'))
                  }
                  Text(sk.description)
                    .fontSize(12)
                    .fontColor($r('app.color.muted'))
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: sk.enabled })
                  .onChange(async (v: boolean) => {
                    const next = this.skills.map((item: SkillRecord): SkillRecord => {
                      if (item.id !== sk.id) {
                        return item;
                      }
                      return {
                        id: item.id,
                        name: item.name,
                        description: item.description,
                        markdown: item.markdown,
                        source: item.source,
                        sourceUrl: item.sourceUrl,
                        enabled: v,
                        updatedAt: item.updatedAt
                      };
                    });
                    await this.onSaveSkills(next);
                  })
                  .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
              }
              .width('100%')

              Row({ space: 8 }) {
                Button(this.previewId === sk.id ? '收起正文' : '查看 SKILL.md')
                  .type(ButtonType.Normal)
                  .height(26)
                  .fontSize(11)
                  .borderRadius(6)
                  .fontColor($r('app.color.accent'))
                  .backgroundColor($r('app.color.canvas'))
                  .onClick(() => {
                    this.previewId = this.previewId === sk.id ? '' : sk.id;
                  })
                if (sk.source !== 'builtin') {
                  Button('删除')
                    .type(ButtonType.Normal)
                    .height(26)
                    .fontSize(11)
                    .borderRadius(6)
                    .fontColor($r('app.color.warning'))
                    .backgroundColor($r('app.color.canvas'))
                    .onClick(async () => {
                      await this.onSaveSkills(this.skills.filter((item: SkillRecord): boolean => item.id !== sk.id));
                    })
                }
              }

              if (this.previewId === sk.id) {
                Text(sk.markdown)
                  .fontSize(11)
                  .fontColor($r('app.color.ink'))
                  .padding(8)
                  .backgroundColor($r('app.color.canvas'))
                  .borderRadius(8)
                  .copyOption(CopyOptions.LocalDevice)
                  .width('100%')
              }
            }
            .alignItems(HorizontalAlign.Start)
            .padding(10)
            .backgroundColor($r('app.color.surface'))
            .borderRadius(10)
            .width('100%')
          }, (sk: SkillRecord) => sk.id + '_' + sk.enabled)
        }
        .width('100%')
        .padding({ bottom: 48 })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.Top)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: this.embeddedInNav ? (56 + this.winTopInset + 4) : 16, bottom: 0 })
    .backgroundColor(Color.Transparent)
  }
}
