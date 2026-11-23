import { pasteboard } from '@kit.BasicServicesKit';
import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import {
  InstructionCard,
  QuickPhrase,
  WorldBook,
  WorldBookEntry,
  WorldBookPosition
} from '../core/Models';
import { parseWorldBookImportJson } from '../core/PromptEngine';
import { newId } from '../core/Storage';

@Component
export struct PromptToolsPanel {
  @Prop worldBooks: WorldBook[] = [];
  @Prop instructionCards: InstructionCard[] = [];
  @Prop activeInstructionIds: string[] = [];
  @Prop quickPhrases: QuickPhrase[] = [];
  @Prop embeddedInNav: boolean = false;
  initialTab: number = 0;

  onSaveWorldBooks: (books: WorldBook[]) => Promise<void> = async () => {};
  onSaveInstructionCards: (cards: InstructionCard[], activeIds: string[]) => Promise<void> = async () => {};
  onSaveQuickPhrases: (phrases: QuickPhrase[]) => Promise<void> = async () => {};
  onInsertPhrase: (content: string) => void = () => {};
  onClose: () => void = () => {};

  @StorageProp('immersiveLightEnabled') immersiveLightEnabled: boolean = true;
  @StorageProp('windowTopInsetVp') winTopInset: number = 0;

  @State currentTab: number = 0; // 0: 世界书, 1: 指令卡片, 2: 全局快捷短语
  @State selectedBookId: string = '';
  @State showImportBox: boolean = false;
  @State importJsonText: string = '';
  @State newBookName: string = '';
  @State editingCardId: string = '';
  @State newCardTitle: string = '';
  @State newCardGroup: string = '';
  @State newCardDesc: string = '';
  @State newCardContent: string = '';
  @State newPhraseTitle: string = '';
  @State newPhraseContent: string = '';
  @State statusTip: string = '';

  aboutToAppear(): void {
    if (this.initialTab >= 0 && this.initialTab <= 2) {
      this.currentTab = this.initialTab;
    }
    if (this.worldBooks.length > 0 && this.selectedBookId.length === 0) {
      this.selectedBookId = this.worldBooks[0].id;
    }
  }

  private getSelectedBook(): WorldBook | undefined {
    for (let i = 0; i < this.worldBooks.length; i++) {
      if (this.worldBooks[i].id === this.selectedBookId) {
        return this.worldBooks[i];
      }
    }
    return this.worldBooks.length > 0 ? this.worldBooks[0] : undefined;
  }

  private cloneBook(b: WorldBook): WorldBook {
    return {
      id: b.id,
      name: b.name,
      description: b.description,
      enabled: b.enabled,
      entries: b.entries.map((e): WorldBookEntry => ({
        id: e.id,
        name: e.name,
        keys: e.keys.slice(),
        useRegex: e.useRegex,
        content: e.content,
        position: e.position,
        role: e.role,
        depth: e.depth,
        enabled: e.enabled,
        alwaysActive: e.alwaysActive
      }))
    };
  }

  private async updateBook(updated: WorldBook): Promise<void> {
    const next: WorldBook[] = [];
    for (let i = 0; i < this.worldBooks.length; i++) {
      const b = this.worldBooks[i];
      next.push(b.id === updated.id ? updated : b);
    }
    await this.onSaveWorldBooks(next);
  }

  private async createBook(): Promise<void> {
    const title = this.newBookName.trim().length > 0 ? this.newBookName.trim() : `世界书 ${this.worldBooks.length + 1}`;
    const created: WorldBook = {
      id: 'wb_' + newId(),
      name: title,
      description: '',
      enabled: true,
      entries: [
        {
          id: 'wbe_' + newId(),
          name: '背景设定',
          keys: ['设定', '背景'],
          useRegex: false,
          content: '',
          position: 'after_system',
          role: 'system',
          depth: 1,
          enabled: true,
          alwaysActive: false
        }
      ]
    };
    const next = this.worldBooks.slice();
    next.push(created);
    this.newBookName = '';
    this.selectedBookId = created.id;
    await this.onSaveWorldBooks(next);
    this.statusTip = `已创建世界书: ${title}`;
  }

  private async importBookJson(): Promise<void> {
    const raw = this.importJsonText.trim();
    if (raw.length === 0) {
      this.statusTip = '请先粘贴 SillyTavern / Kelivo 世界书 JSON';
      return;
    }
    try {
      const book = parseWorldBookImportJson(raw);
      const next = this.worldBooks.slice();
      next.push(book);
      this.selectedBookId = book.id;
      this.importJsonText = '';
      this.showImportBox = false;
      await this.onSaveWorldBooks(next);
      this.statusTip = `成功导入 ${book.entries.length} 条设定 (${book.name})`;
    } catch (e) {
      this.statusTip = `JSON 解析失败: ${String(e)}`;
    }
  }

  private async copyBookJson(book: WorldBook): Promise<void> {
    try {
      const text = JSON.stringify(book, null, 2);
      await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text));
      this.statusTip = `已复制世界书「${book.name}」JSON 到剪贴板`;
    } catch (e) {
      this.statusTip = `复制失败: ${String(e)}`;
    }
  }

  private cyclePosition(pos: WorldBookPosition): WorldBookPosition {
    if (pos === 'before_system') {
      return 'after_system';
    }
    if (pos === 'after_system') {
      return 'before_last_user';
    }
    if (pos === 'before_last_user') {
      return 'at_depth';
    }
    return 'before_system';
  }

  private positionLabel(pos: WorldBookPosition): string {
    if (pos === 'before_system') {
      return '系统前';
    }
    if (pos === 'before_last_user') {
      return '用户前';
    }
    if (pos === 'at_depth') {
      return '指定深度';
    }
    return '系统后';
  }

  private safeCardTitle(card: InstructionCard): string {
    return typeof card.title === 'string' && card.title.trim().length > 0 ? card.title.trim() : '未命名指令';
  }

  private safeCardDesc(card: InstructionCard): string {
    return typeof card.description === 'string' ? card.description.trim() : '';
  }

  private safeCardGroup(card: InstructionCard): string {
    return typeof card.group === 'string' ? card.group.trim() : '';
  }

  private safeCardContent(card: InstructionCard): string {
    if (typeof card.content === 'string' && card.content.length > 0) {
      return card.content;
    }
    if (typeof card.prompt === 'string') {
      return card.prompt;
    }
    return '';
  }

  private isCardActive(id: string): boolean {
    return Array.isArray(this.activeInstructionIds) && this.activeInstructionIds.indexOf(id) >= 0;
  }

  private startEditCard(card: InstructionCard): void {
    this.editingCardId = card.id;
    this.newCardTitle = this.safeCardTitle(card);
    this.newCardGroup = this.safeCardGroup(card);
    this.newCardDesc = this.safeCardDesc(card);
    this.newCardContent = this.safeCardContent(card);
    this.statusTip = `正在编辑：${this.newCardTitle}`;
  }

  private cancelEditCard(): void {
    this.editingCardId = '';
    this.newCardTitle = '';
    this.newCardGroup = '';
    this.newCardDesc = '';
    this.newCardContent = '';
  }

  private async toggleInstructionCard(id: string): Promise<void> {
    const next = Array.isArray(this.activeInstructionIds) ? this.activeInstructionIds.slice() : [];
    const idx = next.indexOf(id);
    if (idx >= 0) {
      next.splice(idx, 1);
    } else {
      next.push(id);
    }
    await this.onSaveInstructionCards(this.instructionCards, next);
  }

  private async saveCardForm(): Promise<void> {
    const title = this.newCardTitle.trim();
    const content = this.newCardContent.trim();
    if (title.length === 0 || content.length === 0) {
      this.statusTip = '请填写卡片标题和注入内容';
      return;
    }
    const group = this.newCardGroup.trim();
    const desc = this.newCardDesc.trim();
    if (this.editingCardId.length > 0) {
      const nextCards: InstructionCard[] = [];
      for (let i = 0; i < this.instructionCards.length; i++) {
        const cur = this.instructionCards[i];
        if (cur.id === this.editingCardId) {
          nextCards.push({
            id: cur.id,
            title,
            description: desc,
            content,
            builtin: cur.builtin === true,
            group
          });
        } else {
          nextCards.push(cur);
        }
      }
      this.editingCardId = '';
      this.newCardTitle = '';
      this.newCardGroup = '';
      this.newCardDesc = '';
      this.newCardContent = '';
      await this.onSaveInstructionCards(nextCards, this.activeInstructionIds);
      this.statusTip = `已更新指令卡片: ${title}`;
      return;
    }
    const card: InstructionCard = {
      id: 'inst_' + newId(),
      title,
      description: desc,
      content,
      builtin: false,
      group
    };
    const nextCards = this.instructionCards.slice();
    nextCards.push(card);
    const nextActive = Array.isArray(this.activeInstructionIds) ? this.activeInstructionIds.slice() : [];
    nextActive.push(card.id);
    this.newCardTitle = '';
    this.newCardGroup = '';
    this.newCardDesc = '';
    this.newCardContent = '';
    await this.onSaveInstructionCards(nextCards, nextActive);
    this.statusTip = `已添加并激活指令卡片: ${card.title}`;
  }

  private async addGlobalPhrase(): Promise<void> {
    if (this.newPhraseTitle.trim().length === 0 || this.newPhraseContent.trim().length === 0) {
      this.statusTip = '请填写短语标题与内容';
      return;
    }
    const next = this.quickPhrases.slice();
    next.push({
      id: 'qp_' + newId(),
      title: this.newPhraseTitle.trim(),
      content: this.newPhraseContent.trim(),
      scope: 'global'
    });
    this.newPhraseTitle = '';
    this.newPhraseContent = '';
    await this.onSaveQuickPhrases(next);
    this.statusTip = '已添加全局快捷短语';
  }

  @Builder
  private tabBtn(label: string, idx: number) {
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
  private renderWorldBookTab() {
    Column({ space: 10 }) {
      Row({ space: 6 }) {
        TextInput({ text: this.newBookName, placeholder: '新建世界书名称...' })
          .layoutWeight(1)
          .height(38)
          .borderRadius(8)
          .backgroundColor($r('app.color.surface'))
          .onChange((v: string) => {
            this.newBookName = v;
          })
        Button('新建')
          .type(ButtonType.Normal)
          .height(38)
          .fontSize(12)
          .borderRadius(8)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor($r('app.color.accent'))
          .onClick(async () => {
            await this.createBook();
          })
        Button('导入JSON')
          .type(ButtonType.Normal)
          .height(38)
          .fontSize(12)
          .borderRadius(8)
          .fontColor($r('app.color.accent'))
          .backgroundColor($r('app.color.tint'))
          .onClick(() => {
            this.showImportBox = !this.showImportBox;
          })
      }
      .width('100%')

      if (this.showImportBox) {
        Column({ space: 6 }) {
          TextArea({ text: this.importJsonText, placeholder: '粘贴 SillyTavern WorldInfo 或 Kelivo WorldBook JSON...' })
            .height(100)
            .borderRadius(8)
            .backgroundColor($r('app.color.canvas'))
            .onChange((v: string) => {
              this.importJsonText = v;
            })
          Row({ space: 8 }) {
            Button('确认导入')
              .type(ButtonType.Normal)
              .height(34)
              .fontSize(12)
              .borderRadius(8)
              .fontColor($r('app.color.on_accent'))
              .backgroundColor($r('app.color.accent'))
              .onClick(async () => {
                await this.importBookJson();
              })
            Button('取消')
              .type(ButtonType.Normal)
              .height(34)
              .fontSize(12)
              .borderRadius(8)
              .fontColor($r('app.color.ink'))
              .backgroundColor($r('app.color.surface'))
              .onClick(() => {
                this.showImportBox = false;
              })
          }
        }
        .padding(10)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(10)
        .width('100%')
      }

      Scroll() {
        Row({ space: 6 }) {
          ForEach(this.worldBooks, (wb: WorldBook) => {
            Button(`${wb.enabled ? '● ' : '○ '}${wb.name} (${wb.entries.length})`)
              .type(ButtonType.Normal)
              .height(32)
              .fontSize(12)
              .borderRadius(8)
              .fontColor(this.selectedBookId === wb.id ? $r('app.color.on_accent') : $r('app.color.ink'))
              .backgroundColor(this.selectedBookId === wb.id ? $r('app.color.accent') : $r('app.color.surface'))
              .padding({ left: 10, right: 10 })
              .onClick(() => {
                this.selectedBookId = wb.id;
              })
          }, (wb: WorldBook) => wb.id)
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      if (this.getSelectedBook()) {
        Column({ space: 8 }) {
          Row({ space: 6 }) {
            Toggle({ type: ToggleType.Switch, isOn: this.getSelectedBook()!.enabled })
              .onChange(async (v: boolean) => {
                const copy = this.cloneBook(this.getSelectedBook()!);
                copy.enabled = v;
                await this.updateBook(copy);
              })
              .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
            Text(this.getSelectedBook()!.enabled ? '已启用此世界书' : '已停用')
              .fontSize(12)
              .fontColor($r('app.color.ink'))
            Blank()
            Button('复制JSON')
              .type(ButtonType.Normal)
              .height(28)
              .fontSize(11)
              .borderRadius(6)
              .fontColor($r('app.color.accent'))
              .backgroundColor($r('app.color.tint'))
              .onClick(async () => {
                await this.copyBookJson(this.getSelectedBook()!);
              })
            Button('+ 添加条目')
              .type(ButtonType.Normal)
              .height(28)
              .fontSize(11)
              .borderRadius(6)
              .fontColor($r('app.color.on_accent'))
              .backgroundColor($r('app.color.accent'))
              .onClick(async () => {
                const copy = this.cloneBook(this.getSelectedBook()!);
                copy.entries.push({
                  id: 'wbe_' + newId(),
                  name: `设定 ${copy.entries.length + 1}`,
                  keys: [],
                  useRegex: false,
                  content: '',
                  position: 'after_system',
                  role: 'system',
                  depth: 1,
                  enabled: true,
                  alwaysActive: false
                });
                await this.updateBook(copy);
              })
            Button('删除书')
              .type(ButtonType.Normal)
              .height(28)
              .fontSize(11)
              .borderRadius(6)
              .fontColor($r('app.color.warning'))
              .backgroundColor($r('app.color.surface'))
              .onClick(async () => {
                const delId = this.getSelectedBook()!.id;
                const remaining = this.worldBooks.filter((b) => b.id !== delId);
                this.selectedBookId = remaining.length > 0 ? remaining[0].id : '';
                await this.onSaveWorldBooks(remaining);
              })
          }
          .width('100%')

          ForEach(this.getSelectedBook()!.entries, (entry: WorldBookEntry, eIdx: number) => {
            Column({ space: 6 }) {
              Row({ space: 6 }) {
                TextInput({ text: entry.name, placeholder: '条目名称' })
                  .layoutWeight(1)
                  .height(34)
                  .borderRadius(8)
                  .backgroundColor($r('app.color.canvas'))
                  .onChange(async (v: string) => {
                    const copy = this.cloneBook(this.getSelectedBook()!);
                    copy.entries[eIdx].name = v;
                    await this.updateBook(copy);
                  })
                Button(this.positionLabel(entry.position))
                  .type(ButtonType.Normal)
                  .height(28)
                  .fontSize(11)
                  .borderRadius(6)
                  .fontColor($r('app.color.accent'))
                  .backgroundColor($r('app.color.tint'))
                  .onClick(async () => {
                    const copy = this.cloneBook(this.getSelectedBook()!);
                    copy.entries[eIdx].position = this.cyclePosition(entry.position);
                    await this.updateBook(copy);
                  })
                Toggle({ type: ToggleType.Switch, isOn: entry.enabled })
                  .onChange(async (v: boolean) => {
                    const copy = this.cloneBook(this.getSelectedBook()!);
                    copy.entries[eIdx].enabled = v;
                    await this.updateBook(copy);
                  })
                  .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))
                Button('删')
                  .type(ButtonType.Normal)
                  .height(28)
                  .fontSize(11)
                  .fontColor($r('app.color.warning'))
                  .backgroundColor($r('app.color.canvas'))
                  .onClick(async () => {
                    const copy = this.cloneBook(this.getSelectedBook()!);
                    copy.entries.splice(eIdx, 1);
                    await this.updateBook(copy);
                  })
              }
              .width('100%')

              Row({ space: 6 }) {
                TextInput({ text: entry.keys.join(', '), placeholder: '触发关键词 (英文逗号分隔)' })
                  .layoutWeight(1)
                  .height(34)
                  .borderRadius(8)
                  .backgroundColor($r('app.color.canvas'))
                  .onChange(async (v: string) => {
                    const copy = this.cloneBook(this.getSelectedBook()!);
                    copy.entries[eIdx].keys = v.split(',').map((s) => s.trim()).filter((s) => s.length > 0);
                    await this.updateBook(copy);
                  })
                Button(entry.alwaysActive ? '常驻' : '触发')
                  .type(ButtonType.Normal)
                  .height(30)
                  .fontSize(11)
                  .borderRadius(6)
                  .fontColor(entry.alwaysActive ? $r('app.color.on_accent') : $r('app.color.ink'))
                  .backgroundColor(entry.alwaysActive ? $r('app.color.accent') : $r('app.color.canvas'))
                  .onClick(async () => {
                    const copy = this.cloneBook(this.getSelectedBook()!);
                    copy.entries[eIdx].alwaysActive = !entry.alwaysActive;
                    await this.updateBook(copy);
                  })
                Button(entry.useRegex ? '正则' : '文本')
                  .type(ButtonType.Normal)
                  .height(30)
                  .fontSize(11)
                  .borderRadius(6)
                  .fontColor(entry.useRegex ? $r('app.color.accent') : $r('app.color.muted'))
                  .backgroundColor($r('app.color.canvas'))
                  .onClick(async () => {
                    const copy = this.cloneBook(this.getSelectedBook()!);
                    copy.entries[eIdx].useRegex = !entry.useRegex;
                    await this.updateBook(copy);
                  })
              }
              .width('100%')

              TextArea({ text: entry.content, placeholder: '设定内容 (支持 {{user_name}} 等模板变量)...' })
                .height(68)
                .borderRadius(8)
                .backgroundColor($r('app.color.canvas'))
                .onChange(async (v: string) => {
                  const copy = this.cloneBook(this.getSelectedBook()!);
                  copy.entries[eIdx].content = v;
                  await this.updateBook(copy);
                })
            }
            .padding(10)
            .backgroundColor($r('app.color.surface'))
            .borderRadius(10)
            .width('100%')
          }, (entry: WorldBookEntry) => entry.id)
        }
        .width('100%')
      } else {
        Text('暂无世界书，点击上方「新建」或「导入JSON」开始使用。')
          .fontSize(12)
          .fontColor($r('app.color.muted'))
          .padding(16)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private renderInstructionTab() {
    Column({ space: 10 }) {
      Text('激活后的指令卡片会自动拼入系统提示词末尾（可在输入框上方快捷切换）')
        .fontSize(12)
        .fontColor($r('app.color.muted'))

      ForEach(this.instructionCards || [], (card: InstructionCard) => {
        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Column({ space: 3 }) {
              Row({ space: 6 }) {
                Text(`${this.safeCardTitle(card)}${card.builtin ? ' · 内置' : ''}`)
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.ink'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                if (this.safeCardGroup(card).length > 0) {
                  Text(this.safeCardGroup(card))
                    .fontSize(10)
                    .fontColor($r('app.color.accent'))
                    .backgroundColor($r('app.color.tint'))
                    .borderRadius(6)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                }
              }
              .width('100%')

              if (this.safeCardDesc(card).length > 0) {
                Text(this.safeCardDesc(card))
                  .fontSize(11)
                  .fontColor($r('app.color.muted'))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Toggle({ type: ToggleType.Switch, isOn: this.isCardActive(card.id) })
              .onChange(async (isOn: boolean) => {
                if (isOn !== this.isCardActive(card.id)) {
                  await this.toggleInstructionCard(card.id);
                }
              })
              .systemMaterial(ImmersiveMaterialStyle.controlMaterial(this.immersiveLightEnabled))

            Button('编辑')
              .type(ButtonType.Normal)
              .height(28)
              .fontSize(11)
              .borderRadius(6)
              .fontColor($r('app.color.accent'))
              .backgroundColor($r('app.color.tint'))
              .onClick(() => {
                this.startEditCard(card);
              })

            if (!card.builtin) {
              Button('删')
                .type(ButtonType.Normal)
                .height(28)
                .fontSize(11)
                .borderRadius(6)
                .fontColor($r('app.color.warning'))
                .backgroundColor($r('app.color.canvas'))
                .onClick(async () => {
                  const nextCards = this.instructionCards.filter((c) => c.id !== card.id);
                  const nextActive = (this.activeInstructionIds || []).filter((id) => id !== card.id);
                  if (this.editingCardId === card.id) {
                    this.cancelEditCard();
                  }
                  await this.onSaveInstructionCards(nextCards, nextActive);
                })
            }
          }
          .width('100%')

          if (this.safeCardContent(card).trim().length > 0) {
            Text(this.safeCardContent(card).trim())
              .fontSize(12)
              .fontColor($r('app.color.muted'))
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
        }
        .padding(10)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(10)
        .width('100%')
        .onClick(() => {
          this.startEditCard(card);
        })
      }, (card: InstructionCard, idx: number) =>
        `${card.id || 'ic_' + idx}_${this.safeCardTitle(card)}_${this.safeCardGroup(card)}_${this.safeCardDesc(card).length}_${this.safeCardContent(card).slice(0, 24)}_${this.safeCardContent(card).length}_${this.isCardActive(card.id) ? 1 : 0}`)

      Column({ space: 6 }) {
        Text(this.editingCardId.length > 0 ? '编辑指令卡片' : '新建自定义指令卡片')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
        TextInput({ text: this.newCardTitle, placeholder: '标题（例如：技术架构评审模式）' })
          .height(36)
          .borderRadius(8)
          .backgroundColor($r('app.color.canvas'))
          .onChange((v: string) => {
            this.newCardTitle = v;
          })
        TextInput({ text: this.newCardGroup, placeholder: '分组（可选）' })
          .height(36)
          .borderRadius(8)
          .backgroundColor($r('app.color.canvas'))
          .onChange((v: string) => {
            this.newCardGroup = v;
          })
        TextInput({ text: this.newCardDesc, placeholder: '简短说明（可选）' })
          .height(36)
          .borderRadius(8)
          .backgroundColor($r('app.color.canvas'))
          .onChange((v: string) => {
            this.newCardDesc = v;
          })
        TextArea({ text: this.newCardContent, placeholder: '注入指令正文...' })
          .height(96)
          .borderRadius(8)
          .backgroundColor($r('app.color.canvas'))
          .onChange((v: string) => {
            this.newCardContent = v;
          })
        Row({ space: 8 }) {
          Button(this.editingCardId.length > 0 ? '保存修改' : '添加并激活')
            .type(ButtonType.Normal)
            .height(36)
            .fontSize(12)
            .borderRadius(8)
            .layoutWeight(1)
            .fontColor($r('app.color.on_accent'))
            .backgroundColor($r('app.color.accent'))
            .onClick(async () => {
              await this.saveCardForm();
            })
          if (this.editingCardId.length > 0) {
            Button('取消编辑')
              .type(ButtonType.Normal)
              .height(36)
              .fontSize(12)
              .borderRadius(8)
              .fontColor($r('app.color.ink'))
              .backgroundColor($r('app.color.canvas'))
              .onClick(() => {
                this.cancelEditCard();
                this.statusTip = '';
              })
          }
        }
        .width('100%')
      }
      .padding(10)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(10)
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private renderQuickPhraseTab() {
    Column({ space: 10 }) {
      Text('点击「插入」可将短语填入当前对话输入框')
        .fontSize(12)
        .fontColor($r('app.color.muted'))

      ForEach(this.quickPhrases, (qp: QuickPhrase) => {
        Column({ space: 6 }) {
          Row({ space: 6 }) {
            Text(qp.title)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))
              .layoutWeight(1)
            Button('插入')
              .type(ButtonType.Normal)
              .height(28)
              .fontSize(11)
              .borderRadius(6)
              .fontColor($r('app.color.on_accent'))
              .backgroundColor($r('app.color.accent'))
              .onClick(() => {
                this.onInsertPhrase(qp.content);
                this.onClose();
              })
            Button('删')
              .type(ButtonType.Normal)
              .height(28)
              .fontSize(11)
              .fontColor($r('app.color.warning'))
              .backgroundColor($r('app.color.canvas'))
              .onClick(async () => {
                await this.onSaveQuickPhrases(this.quickPhrases.filter((item) => item.id !== qp.id));
              })
          }
          .width('100%')
          Text(qp.content)
            .fontSize(12)
            .fontColor($r('app.color.muted'))
        }
        .padding(10)
        .backgroundColor($r('app.color.surface'))
        .borderRadius(10)
        .width('100%')
      }, (qp: QuickPhrase) => qp.id)

      Column({ space: 6 }) {
        Text('添加全局快捷短语')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
        TextInput({ text: this.newPhraseTitle, placeholder: '短语标签' })
          .height(36)
          .borderRadius(8)
          .backgroundColor($r('app.color.canvas'))
          .onChange((v: string) => {
            this.newPhraseTitle = v;
          })
        TextArea({ text: this.newPhraseContent, placeholder: '完整短语模板...' })
          .height(68)
          .borderRadius(8)
          .backgroundColor($r('app.color.canvas'))
          .onChange((v: string) => {
            this.newPhraseContent = v;
          })
        Button('添加短语')
          .type(ButtonType.Normal)
          .height(36)
          .fontSize(12)
          .borderRadius(8)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor($r('app.color.accent'))
          .onClick(async () => {
            await this.addGlobalPhrase();
          })
      }
      .padding(10)
      .backgroundColor($r('app.color.surface'))
      .borderRadius(10)
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  build() {
    Column({ space: 12 }) {
      if (!this.embeddedInNav) {
        Row() {
          Text('世界书 · 指令卡 · 快捷短语')
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.ink'))
          Blank()
          Button('完成')
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

      Row({ space: 8 }) {
        this.tabBtn('世界书', 0)
        this.tabBtn('指令卡片', 1)
        this.tabBtn('快捷短语', 2)
      }
      .width('100%')

      if (this.statusTip.length > 0) {
        Text(this.statusTip)
          .fontSize(12)
          .fontColor($r('app.color.accent'))
      }

      Scroll() {
        Column({ space: 10 }) {
          if (this.currentTab === 0) {
            this.renderWorldBookTab()
          } else if (this.currentTab === 1) {
            this.renderInstructionTab()
          } else {
            this.renderQuickPhraseTab()
          }
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
