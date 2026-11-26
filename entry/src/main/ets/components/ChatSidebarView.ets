import { Conversation, Persona } from '../core/Models';
import { formatChatDateGroupLabel, isChatDrawerGroupStart } from '../core/ChatAuxService';
import { ImmersiveMaterialStyle } from '../core/ImmersiveMaterialStyle';
import { SystemMotion } from '../core/SystemMotion';
import { KelivoAvatarBadge } from './KelivoChrome';

@Component
export struct ChatSidebarView {
  @Prop isOverlay: boolean = false;
  @Link drawerGlobalSearch: boolean;
  @Link query: string;
  @Prop personaName: string = '';
  @Prop personaAvatar: string = '';
  @Prop selectedPersonaIdVal: string = '';
  @Prop personas: Persona[] = [];
  @Prop chatListRows: Conversation[] = [];
  @Prop activeConversationId: string = '';
  @Prop generatingChatIds: string[] = [];
  @Prop userName: string = '用户';
  @Prop newChatLabel: string = '新对话';
  @Prop translateToolLabel: string = '翻译';
  @Prop settingsLabel: string = '设置';
  @Prop picking: boolean = false;
  @Prop bottomInset: number = 0;

  @StorageProp('immersiveLightEnabled') immersiveLight: boolean = true;
  @StorageProp('windowTopInsetVp') winTopInset: number = 0;
  @StorageProp('windowLeftInsetVp') winLeftInset: number = 0;

  @State renameId: string = '';
  @State renameText: string = '';
  @State drawerAssistantsExpanded: boolean = false;
  @State drawerEditingUser: boolean = false;
  @State drawerUserNameDraft: string = '';

  onCloseDrawer: () => void = () => {};
  onSelectChat: (chatId: string) => void = () => {};
  onSelectAssistant: (personaId: string) => void = () => {};
  onOpenPersonaDetail: (personaId: string) => void = () => {};
  onOpenPersonas: () => void = () => {};
  onRenameChat: (c: Conversation, titleText: string) => void = () => {};
  onTogglePinChat: (c: Conversation) => void = () => {};
  onDuplicateChat: (c: Conversation) => void = () => {};
  onMoveChatToNextPersona: (c: Conversation) => void = () => {};
  onRemoveChat: (c: Conversation) => void = () => {};
  onSaveUserName: (name: string) => void = () => {};
  onOpenTranslate: () => void = () => {};
  onOpenSettings: () => void = () => {};

  build() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Row({ space: 8 }) {
          Button({ type: ButtonType.Circle }) {
            SymbolGlyph(this.drawerGlobalSearch ? $r('sys.symbol.externaldrive') : $r('sys.symbol.magnifyingglass'))
              .fontSize(16)
              .fontColor([this.drawerGlobalSearch ? $r('app.color.accent') : $r('app.color.muted')])
          }
          .width(30)
          .height(30)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText(this.drawerGlobalSearch ? '切换为当前助手检索' : '切换为全局会话检索')
          .onClick(() => { this.drawerGlobalSearch = !this.drawerGlobalSearch; })

          TextInput({
            text: this.query,
            placeholder: this.drawerGlobalSearch ? '搜索所有会话...' : `搜索 ${this.personaName}...`
          })
            .id('historySearch')
            .layoutWeight(1)
            .height(36)
            .padding(0)
            .fontSize(13)
            .backgroundColor(Color.Transparent)
            .onChange((v: string) => { this.query = v; })

          if (this.query.length > 0) {
            Button({ type: ButtonType.Circle }) {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(12)
                .fontColor([$r('app.color.muted')])
            }
            .width(24)
            .height(24)
            .padding(0)
            .backgroundColor(Color.Transparent)
            .onClick(() => { this.query = ''; })
          }
        }
        .layoutWeight(1)
        .height(40)
        .padding({ left: 8, right: 8 })
        .borderRadius(20)
        .backgroundColor($r('app.color.surface'))

        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.square_and_pencil'))
            .fontSize(17)
            .fontColor([$r('app.color.ink')])
        }
        .width(40)
        .height(40)
        .padding(0)
        .backgroundColor($r('app.color.surface'))
        .accessibilityText(this.newChatLabel)
        .onClick(() => {
          this.onCloseDrawer();
          this.onSelectChat('');
        })
      }
      .width('100%')

      Row({ space: 10 }) {
        KelivoAvatarBadge({
          brandId: '',
          avatarText: this.personaAvatar,
          fallbackLetter: this.personaName,
          badgeSize: 32
        })
        Text(this.personaName)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        SymbolGlyph(this.drawerAssistantsExpanded ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down'))
          .fontSize(15)
          .fontColor([$r('app.color.muted')])
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 8, bottom: 8 })
      .borderRadius(12)
      .backgroundColor(this.drawerAssistantsExpanded ? $r('app.color.surface') : Color.Transparent)
      .onClick(() => { this.drawerAssistantsExpanded = !this.drawerAssistantsExpanded; })

      if (this.drawerAssistantsExpanded) {
        Column({ space: 4 }) {
          ForEach(this.personas, (pItem: Persona) => {
            Row({ space: 8 }) {
              KelivoAvatarBadge({
                brandId: '',
                avatarText: pItem.avatar || '',
                fallbackLetter: pItem.name,
                badgeSize: 26
              })
              Text(pItem.name)
                .fontSize(14)
                .fontColor(pItem.id === this.selectedPersonaIdVal ? $r('app.color.accent') : $r('app.color.ink'))
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (pItem.id === this.selectedPersonaIdVal) {
                SymbolGlyph($r('sys.symbol.checkmark'))
                  .fontSize(14)
                  .fontColor([$r('app.color.accent')])
              }
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph($r('sys.symbol.square_and_pencil'))
                  .fontSize(14)
                  .fontColor([$r('app.color.muted')])
              }
              .width(28)
              .height(28)
              .padding(0)
              .backgroundColor(Color.Transparent)
              .accessibilityText(`编辑 ${pItem.name}`)
              .onClick(() => {
                this.drawerAssistantsExpanded = false;
                this.onOpenPersonaDetail(pItem.id);
              })
            }
            .width('100%')
            .padding({ left: 10, right: 8, top: 6, bottom: 6 })
            .borderRadius(10)
            .backgroundColor(pItem.id === this.selectedPersonaIdVal ? $r('app.color.tint') : Color.Transparent)
            .onClick(() => {
              this.onSelectAssistant(pItem.id);
            })
          }, (pItem: Persona) => `da-${pItem.id}-${pItem.name}`)

          Row({ space: 6 }) {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(14)
              .fontColor([$r('app.color.accent')])
            Text('管理助手与提示词')
              .fontSize(13)
              .fontColor($r('app.color.accent'))
          }
          .width('100%')
          .padding({ left: 10, right: 10, top: 8, bottom: 6 })
          .onClick(() => {
            this.drawerAssistantsExpanded = false;
            this.onOpenPersonas();
          })
        }
        .width('100%')
        .padding(6)
        .borderRadius(12)
        .backgroundColor($r('app.color.surface'))
      }

      List({ space: 4 }) {
        ForEach(this.chatListRows, (c: Conversation, ci: number) => {
          ListItem() {
            Column({ space: 2 }) {
              if (isChatDrawerGroupStart(this.chatListRows, ci)) {
                Text(formatChatDateGroupLabel(c))
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.muted'))
                  .padding({ left: 8, top: ci === 0 ? 2 : 8, bottom: 2 })
                  .width('100%')
              }
              Row() {
                if (this.renameId === c.id) {
                  TextInput({ text: this.renameText, placeholder: '对话名称' }).layoutWeight(1).maxLength(120)
                    .onChange((v: string) => { this.renameText = v; })
                  Button('保存')
                    .height(30)
                    .fontSize(12)
                    .onClick(() => {
                      this.onRenameChat(c, this.renameText.trim());
                      this.renameId = '';
                    })
                  Button({ type: ButtonType.Circle }) {
                    SymbolGlyph($r('sys.symbol.xmark')).fontSize(20).fontColor([$r('app.color.ink')])
                  }
                  .width(40)
                  .height(40)
                  .backgroundColor(Color.Transparent)
                  .accessibilityText('取消重命名')
                  .onClick(() => { this.renameId = ''; })
                } else {
                  Row({ space: 6 }) {
                    if (c.pinned) {
                      SymbolGlyph($r('sys.symbol.pin'))
                        .fontSize(13)
                        .fontColor([$r('app.color.accent')])
                    }
                    Text((c.ephemeral ? '🕶 ' : '') + c.title)
                      .fontSize(14)
                      .fontWeight(c.id === this.activeConversationId ? FontWeight.Medium : FontWeight.Normal)
                      .fontColor($r('app.color.ink'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                    if (this.generatingChatIds.includes(c.id)) {
                      LoadingProgress()
                        .width(14)
                        .height(14)
                        .color($r('app.color.accent'))
                    }
                  }
                  .layoutWeight(1)
                  .padding({ left: 10, right: 4, top: 11, bottom: 11 })
                  .onClick(() => {
                    this.onCloseDrawer();
                    this.onSelectChat(c.id);
                  })

                  Button({ type: ButtonType.Circle }) {
                    SymbolGlyph($r('sys.symbol.ellipsis_circle'))
                      .fontSize(16)
                      .fontColor([$r('app.color.muted')])
                  }
                  .height(34)
                  .width(34)
                  .padding(0)
                  .backgroundColor(Color.Transparent)
                  .accessibilityText('管理对话')
                  .bindMenu([
                    { value: c.pinned ? '取消置顶' : '置顶', action: () => { this.onTogglePinChat(c); } },
                    { value: '重命名', action: () => { this.renameText = c.title; this.renameId = c.id; } },
                    { value: '复制对话', action: () => { this.onDuplicateChat(c); } },
                    { value: '迁移至下一助手', action: () => { this.onMoveChatToNextPersona(c); } },
                    { value: '删除对话', action: () => { this.onRemoveChat(c); } }
                  ], ImmersiveMaterialStyle.menuOptions(this.immersiveLight))
                }
              }
              .width('100%')
              .borderRadius(12)
              .backgroundColor(c.id === this.activeConversationId ? $r('app.color.tint') : Color.Transparent)
            }
            .width('100%')
          }
        }, (c: Conversation) => `${c.id}_${c.title}_${c.updated}_${c.messages.length}_${!!c.pinned}_${c.id === this.activeConversationId}_${c.id === this.renameId}_${this.generatingChatIds.includes(c.id)}`)

        if (!this.chatListRows.length) {
          ListItem() {
            Text(this.query ? '没有匹配的对话' : '发送第一条消息后，对话会保存在这里。')
              .padding({ left: 10, top: 14 })
              .fontSize(13)
              .fontColor($r('app.color.muted'))
          }
        }
      }
      .width('100%')
      .layoutWeight(1)

      if (this.drawerEditingUser) {
        Row({ space: 6 }) {
          TextInput({ text: this.drawerUserNameDraft, placeholder: '输入昵称' })
            .layoutWeight(1)
            .height(34)
            .fontSize(13)
            .onChange((v: string) => { this.drawerUserNameDraft = v; })
          Button('确定')
            .height(32)
            .fontSize(12)
            .onClick(() => {
              const trimmed = this.drawerUserNameDraft.trim();
              if (trimmed) {
                this.onSaveUserName(trimmed);
              }
              this.drawerEditingUser = false;
            })
        }
        .width('100%')
        .padding({ top: 4 })
      } else {
        Row({ space: 8 }) {
          KelivoAvatarBadge({
            brandId: '',
            avatarText: '',
            fallbackLetter: this.userName || '用户',
            badgeSize: 32
          })
          Text(this.userName || '用户')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .onClick(() => {
              this.drawerUserNameDraft = this.userName || '用户';
              this.drawerEditingUser = true;
            })

          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.translate'))
              .fontSize(19)
              .fontColor([$r('app.color.ink')])
          }
          .width(38)
          .height(38)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText(this.translateToolLabel)
          .onClick(() => { this.onOpenTranslate(); })

          Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.gearshape'))
              .fontSize(19)
              .fontColor([$r('app.color.ink')])
          }
          .width(38)
          .height(38)
          .padding(0)
          .backgroundColor(Color.Transparent)
          .accessibilityText(this.settingsLabel)
          .onClick(() => { this.onOpenSettings(); })
        }
        .width('100%')
        .padding({ top: 4 })
      }
    }
    .padding({
      top: this.winTopInset + 6,
      left: 14 + (this.isOverlay ? this.winLeftInset : 0),
      right: 14,
      bottom: Math.max(12, this.bottomInset + 8)
    })
    .width(this.isOverlay ? '100%' : 285)
    .height('100%')
    .backgroundColor(this.isOverlay ? $r('app.color.surface') : $r('app.color.panel'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .enabled(!this.picking)
  }
}

@Component
export struct ChatDrawerOverlay {
  @StorageProp('reduceMotionEnabled') reduceMotion: boolean = false;
  @BuilderParam sidebarContent: () => void;
  onDismiss: () => void = () => {};

  build() {
    Row() {
      Column() {
        this.sidebarContent()
      }
      .width('78%')
      .constraintSize({ maxWidth: 335 })
      .height('100%')
      .transition(SystemMotion.drawerPanelTransition(this.reduceMotion))

      Column()
        .layoutWeight(1)
        .height('100%')
        .onClick(() => { this.onDismiss(); })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#4D000000')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .transition(SystemMotion.drawerScrimTransition(this.reduceMotion))
  }
}
