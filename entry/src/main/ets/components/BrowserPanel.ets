import { webview } from '@kit.ArkWeb';
import { BrowserAgentManager, BrowserTab } from '../core/BrowserAgent';
import { BrowserBookmark, LocalWorkspace } from '../core/Models';
import { newId } from '../core/Storage';

@Component
export struct BrowserPanel {
  manager: BrowserAgentManager = new BrowserAgentManager();
  @Prop workspaces: LocalWorkspace[] = [];
  @Prop bookmarks: BrowserBookmark[] = [];
  @Prop compactMode: boolean = false;
  @Prop embeddedInNav: boolean = false;

  onSaveBookmarks: (list: BrowserBookmark[]) => Promise<void> = async () => {};
  onExtractToChat: (title: string, text: string) => void = () => {};
  onClose: () => void = () => {};

  @StorageProp('windowTopInsetVp') winTopInset: number = 0;

  @State tabList: BrowserTab[] = [];
  @State activeId: string = '';
  @State addressBarText: string = '';
  @State showBookmarks: boolean = false;
  @State statusTip: string = '';

  aboutToAppear(): void {
    this.syncFromManager();
    this.manager.onTabsChanged = () => {
      this.syncFromManager();
    };
  }

  private syncFromManager(): void {
    this.tabList = this.manager.tabs.slice();
    const act = this.manager.getActiveTab();
    this.activeId = act.id;
    this.addressBarText = act.url;
  }

  private activeTab(): BrowserTab {
    return this.manager.getActiveTab();
  }

  private isCurrentBookmarked(): boolean {
    const cur = this.addressBarText.trim();
    return this.bookmarks.some((b: BrowserBookmark): boolean => b.url === cur);
  }

  private async toggleBookmark(): Promise<void> {
    const tab = this.activeTab();
    const curUrl = this.addressBarText.trim() || tab.url;
    if (curUrl.length === 0 || curUrl === 'about:blank') {
      return;
    }
    if (this.isCurrentBookmarked()) {
      await this.onSaveBookmarks(this.bookmarks.filter((b: BrowserBookmark): boolean => b.url !== curUrl));
      this.statusTip = '已移除书签';
    } else {
      const entry: BrowserBookmark = {
        id: 'bm_' + newId(),
        title: tab.title || curUrl,
        url: curUrl,
        createdAt: Date.now()
      };
      const next: BrowserBookmark[] = [entry, ...this.bookmarks];
      await this.onSaveBookmarks(next);
      this.statusTip = '已加入书签';
    }
  }

  private async goAddress(): Promise<void> {
    const tab = this.activeTab();
    try {
      await this.manager.navigateTab(tab, this.addressBarText, this.workspaces);
      this.syncFromManager();
    } catch (e) {
      this.statusTip = (e as Error).message || String(e);
    }
  }

  private async extractPageToComposer(): Promise<void> {
    const tab = this.activeTab();
    try {
      const res = await this.manager.executeAction(JSON.stringify({ action: 'extract', tab_id: tab.id }), this.workspaces);
      this.onExtractToChat(tab.title || tab.url, res.text);
      this.statusTip = '已提取当前网页正文并填入对话';
    } catch (e) {
      this.statusTip = `提取失败: ${(e as Error).message || String(e)}`;
    }
  }

  build() {
    Column({ space: 6 }) {
      Row({ space: 6 }) {
        if (!this.embeddedInNav) {
          Text('内置浏览器')
            .fontSize(this.compactMode ? 15 : 18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.ink'))
        }
        Blank()
        Button('提取到对话')
          .type(ButtonType.Normal)
          .height(28)
          .fontSize(11)
          .borderRadius(8)
          .fontColor($r('app.color.accent'))
          .backgroundColor($r('app.color.tint'))
          .onClick(async () => {
            await this.extractPageToComposer();
          })
        Button(this.showBookmarks ? '网页' : `书签(${this.bookmarks.length})`)
          .type(ButtonType.Normal)
          .height(28)
          .fontSize(11)
          .borderRadius(8)
          .fontColor($r('app.color.ink'))
          .backgroundColor($r('app.color.surface'))
          .onClick(() => {
            this.showBookmarks = !this.showBookmarks;
          })
        if (!this.embeddedInNav) {
          Button('关闭')
            .type(ButtonType.Normal)
            .height(28)
            .fontSize(11)
            .borderRadius(8)
            .fontColor($r('app.color.ink'))
            .backgroundColor($r('app.color.surface'))
            .onClick(() => this.onClose())
        }
      }
      .width('100%')

      Scroll() {
        Row({ space: 6 }) {
          ForEach(this.tabList, (tab: BrowserTab) => {
            Row({ space: 4 }) {
              Text(tab.title || tab.url)
                .fontSize(11)
                .maxLines(1)
                .constraintSize({ maxWidth: 110 })
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .fontColor(this.activeId === tab.id ? $r('app.color.on_accent') : $r('app.color.ink'))
              if (this.tabList.length > 1) {
                Text('×')
                  .fontSize(12)
                  .fontColor(this.activeId === tab.id ? $r('app.color.on_accent') : $r('app.color.muted'))
                  .padding({ left: 2, right: 2 })
                  .onClick(() => {
                    this.manager.closeTab(tab.id);
                    this.syncFromManager();
                  })
              }
            }
            .height(28)
            .padding({ left: 10, right: 8 })
            .borderRadius(8)
            .backgroundColor(this.activeId === tab.id ? $r('app.color.accent') : $r('app.color.surface'))
            .onClick(() => {
              this.manager.switchTab(tab.id);
              this.syncFromManager();
            })
          }, (tab: BrowserTab) => tab.id + '_' + tab.title)

          Button('+')
            .type(ButtonType.Normal)
            .width(28)
            .height(28)
            .fontSize(14)
            .borderRadius(8)
            .fontColor($r('app.color.accent'))
            .backgroundColor($r('app.color.tint'))
            .onClick(() => {
              this.manager.newTab('https://duckduckgo.com', '新标签页');
              this.syncFromManager();
            })
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      Row({ space: 4 }) {
        Button('←')
          .type(ButtonType.Normal)
          .width(30)
          .height(32)
          .fontSize(13)
          .borderRadius(8)
          .fontColor($r('app.color.ink'))
          .backgroundColor($r('app.color.surface'))
          .onClick(() => {
            try { this.activeTab().controller.backward(); } catch (_) {}
          })
        Button('→')
          .type(ButtonType.Normal)
          .width(30)
          .height(32)
          .fontSize(13)
          .borderRadius(8)
          .fontColor($r('app.color.ink'))
          .backgroundColor($r('app.color.surface'))
          .onClick(() => {
            try { this.activeTab().controller.forward(); } catch (_) {}
          })
        Button('↻')
          .type(ButtonType.Normal)
          .width(30)
          .height(32)
          .fontSize(13)
          .borderRadius(8)
          .fontColor($r('app.color.ink'))
          .backgroundColor($r('app.color.surface'))
          .onClick(() => {
            try { this.activeTab().controller.refresh(); } catch (_) {}
          })
        TextInput({ text: this.addressBarText, placeholder: '输入网址或 kelivo://workspace/...' })
          .layoutWeight(1)
          .height(34)
          .fontSize(12)
          .borderRadius(8)
          .backgroundColor($r('app.color.surface'))
          .onChange((v: string) => {
            this.addressBarText = v;
          })
          .onSubmit(async () => {
            await this.goAddress();
          })
        Button('前往')
          .type(ButtonType.Normal)
          .height(32)
          .fontSize(11)
          .borderRadius(8)
          .fontColor($r('app.color.on_accent'))
          .backgroundColor($r('app.color.accent'))
          .onClick(async () => {
            await this.goAddress();
          })
        Button(this.isCurrentBookmarked() ? '★' : '☆')
          .type(ButtonType.Normal)
          .width(32)
          .height(32)
          .fontSize(14)
          .borderRadius(8)
          .fontColor($r('app.color.accent'))
          .backgroundColor($r('app.color.surface'))
          .onClick(async () => {
            await this.toggleBookmark();
          })
      }
      .width('100%')

      if (this.statusTip.length > 0) {
        Text(this.statusTip)
          .fontSize(11)
          .fontColor($r('app.color.accent'))
      }

      if (this.showBookmarks) {
        List({ space: 6 }) {
          ForEach(this.bookmarks, (bm: BrowserBookmark) => {
            ListItem() {
              Row({ space: 8 }) {
                Column({ space: 2 }) {
                  Text(bm.title)
                    .fontSize(13)
                    .fontColor($r('app.color.ink'))
                  Text(bm.url)
                    .fontSize(11)
                    .fontColor($r('app.color.muted'))
                    .maxLines(1)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                .onClick(async () => {
                  this.addressBarText = bm.url;
                  this.showBookmarks = false;
                  await this.goAddress();
                })

                Button('删')
                  .type(ButtonType.Normal)
                  .height(26)
                  .fontSize(11)
                  .fontColor($r('app.color.warning'))
                  .backgroundColor($r('app.color.canvas'))
                  .onClick(async () => {
                    await this.onSaveBookmarks(this.bookmarks.filter((item: BrowserBookmark): boolean => item.id !== bm.id));
                  })
              }
              .padding(10)
              .backgroundColor($r('app.color.surface'))
              .borderRadius(10)
              .width('100%')
            }
          }, (bm: BrowserBookmark) => bm.id)
        }
        .layoutWeight(1)
        .width('100%')
      } else {
        Stack() {
          ForEach(this.tabList, (tab: BrowserTab) => {
            Web({
              src: tab.htmlContent.length > 0 ? 'about:blank' : tab.url,
              controller: tab.controller
            })
              .javaScriptAccess(true)
              .domStorageAccess(true)
              .onControllerAttached(() => {
                tab.attached = true;
                if (tab.htmlContent.length > 0) {
                  try {
                    tab.controller.loadData(tab.htmlContent, 'text/html', 'UTF-8', 'https://kelivo.local/');
                  } catch (_) {}
                }
              })
              .onPageBegin((ev) => {
                if (ev.url && !ev.url.startsWith('https://kelivo.local/')) {
                  tab.url = ev.url;
                  if (tab.id === this.activeId) {
                    this.addressBarText = ev.url;
                  }
                }
              })
              .onTitleReceive((ev) => {
                if (ev.title && ev.title.length > 0) {
                  tab.title = ev.title;
                  this.tabList = this.manager.tabs.slice();
                }
              })
              .width('100%')
              .height('100%')
              .visibility(tab.id === this.activeId ? Visibility.Visible : Visibility.Hidden)
          }, (tab: BrowserTab) => tab.id)
        }
        .layoutWeight(1)
        .width('100%')
        .borderRadius(10)
        .clip(true)
      }
    }
    .width('100%')
    .height('100%')
    .padding({
      top: this.embeddedInNav ? (56 + this.winTopInset + 4) : (this.compactMode ? 10 : 14),
      left: this.compactMode ? 10 : 14,
      right: this.compactMode ? 10 : 14,
      bottom: this.compactMode ? 10 : 32
    })
    .backgroundColor(Color.Transparent)
  }
}
