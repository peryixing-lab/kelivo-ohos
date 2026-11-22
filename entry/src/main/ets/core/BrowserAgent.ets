import { webview } from '@kit.ArkWeb';
import { LocalWorkspace } from './Models';
import { newId } from './Storage';
import { ToolExecutionOutput } from './ToolLoop';
import { RegisteredTool } from './ToolRegistry';
import { fetchWebPage } from './WebSearch';
import { readWorkspaceText } from './WorkspaceTools';

export interface BrowserTab {
  id: string;
  title: string;
  url: string;
  htmlContent: string;
  controller: webview.WebviewController;
  attached: boolean;
}

const MAX_BROWSER_TABS = 8;

const BROWSER_ACTIONS_DESC =
  '内置多标签可编程浏览器（最多 8 标签），支持 19 个 action：\n' +
  'open(url) 打开网页或 kelivo://workspace/<wsId>/<relPath>、render(html,title?) 直接渲染 HTML、' +
  'extract() 提取正文、snapshot() 获取可交互 DOM 索引与文本、click(selector/ref) 点击、type(selector/ref,text) 输入、' +
  'select_option(selector/ref,value)、press(key)、scroll(direction/y)、wait(ms)、back/forward/reload、' +
  'evaluate(script)、new_tab(url?)、switch_tab(tab_id)、close_tab(tab_id)、list_tabs、screenshot。';

export function buildBrowserTools(): RegisteredTool[] {
  return [
    {
      declaration: {
        name: 'browser',
        description: BROWSER_ACTIONS_DESC,
        parametersJson:
          '{"type":"object","properties":{' +
          '"action":{"type":"string","enum":["open","render","extract","snapshot","click","type","select_option","press","scroll","wait","back","forward","reload","evaluate","new_tab","switch_tab","close_tab","list_tabs","screenshot"]},' +
          '"url":{"type":"string","description":"目标 URL 或 kelivo://workspace/..."},' +
          '"html":{"type":"string","description":"render 动作的 HTML 内容"},' +
          '"title":{"type":"string","description":"可选标题"},' +
          '"selector":{"type":"string","description":"CSS 选择器或 @N 元素编号"},' +
          '"text":{"type":"string","description":"type 动作输入的文本"},' +
          '"value":{"type":"string","description":"select_option 值"},' +
          '"key":{"type":"string","description":"按键名，如 Enter"},' +
          '"direction":{"type":"string","description":"top/bottom/up/down"},' +
          '"y":{"type":"integer","description":"滚动像素"},' +
          '"ms":{"type":"integer","description":"wait 等待毫秒"},' +
          '"script":{"type":"string","description":"evaluate 要执行的 JS"},' +
          '"tab_id":{"type":"string","description":"目标标签 ID"}' +
          '},"required":["action"]}'
      },
      source: 'browser',
      requiresApproval: false
    }
  ];
}

function unwrapJsString(raw: string): string {
  const trimmed = raw.trim();
  if (trimmed === 'null' || trimmed === 'undefined') {
    return '';
  }
  if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
    try {
      return String(JSON.parse(trimmed));
    } catch (_) {
      return trimmed.slice(1, trimmed.length - 1);
    }
  }
  return trimmed;
}

function jsSelectorExpr(sel: string): string {
  const clean = sel.trim();
  if (clean.startsWith('@') && /^\d+$/.test(clean.slice(1))) {
    const idx = clean.slice(1);
    return `document.querySelector('[data-kelivo-idx="${idx}"]')`;
  }
  return `document.querySelector(${JSON.stringify(clean)})`;
}

export class BrowserAgentManager {
  tabs: BrowserTab[] = [];
  activeTabId: string = '';
  onTabsChanged?: () => void;

  constructor() {
    const first = this.createTabObject('https://duckduckgo.com', '新标签页');
    this.tabs.push(first);
    this.activeTabId = first.id;
  }

  private createTabObject(url: string, title: string): BrowserTab {
    return {
      id: 'tab_' + newId(),
      title,
      url,
      htmlContent: '',
      controller: new webview.WebviewController(),
      attached: false
    };
  }

  private notify(): void {
    if (this.onTabsChanged) {
      this.onTabsChanged();
    }
  }

  getActiveTab(): BrowserTab {
    const found = this.tabs.find((t: BrowserTab): boolean => t.id === this.activeTabId);
    if (found) {
      return found;
    }
    if (this.tabs.length === 0) {
      const fresh = this.createTabObject('https://duckduckgo.com', '新标签页');
      this.tabs.push(fresh);
      this.activeTabId = fresh.id;
    }
    return this.tabs[0];
  }

  findTab(tabId?: string): BrowserTab {
    if (tabId && tabId.length > 0) {
      const hit = this.tabs.find((t: BrowserTab): boolean => t.id === tabId);
      if (hit) {
        return hit;
      }
    }
    return this.getActiveTab();
  }

  newTab(url: string = 'https://duckduckgo.com', title: string = '新标签页'): BrowserTab {
    if (this.tabs.length >= MAX_BROWSER_TABS) {
      // Recycle oldest non-active tab cleanly
      const idx = this.tabs.findIndex((t: BrowserTab): boolean => t.id !== this.activeTabId);
      if (idx >= 0) {
        this.tabs.splice(idx, 1);
      }
    }
    const created = this.createTabObject(url, title);
    this.tabs = [...this.tabs, created];
    this.activeTabId = created.id;
    this.notify();
    return created;
  }

  switchTab(tabId: string): boolean {
    const exists = this.tabs.some((t: BrowserTab): boolean => t.id === tabId);
    if (!exists) {
      return false;
    }
    this.activeTabId = tabId;
    this.notify();
    return true;
  }

  closeTab(tabId: string): void {
    if (this.tabs.length <= 1) {
      const only = this.tabs[0];
      only.url = 'about:blank';
      only.title = '空白页';
      only.htmlContent = '';
      if (only.attached) {
        try { only.controller.loadUrl('about:blank'); } catch (_) {}
      }
      this.notify();
      return;
    }
    const remaining = this.tabs.filter((t: BrowserTab): boolean => t.id !== tabId);
    this.tabs = remaining;
    if (this.activeTabId === tabId) {
      this.activeTabId = remaining[remaining.length - 1].id;
    }
    this.notify();
  }

  async navigateTab(tab: BrowserTab, rawUrl: string, workspaces: LocalWorkspace[]): Promise<string> {
    let url = rawUrl.trim();
    if (url.length === 0) {
      return 'URL 不能为空';
    }
    if (url.startsWith('kelivo://workspace/')) {
      const rest = url.slice('kelivo://workspace/'.length);
      const slash = rest.indexOf('/');
      const wsId = slash > 0 ? rest.slice(0, slash) : rest;
      const relPath = slash > 0 ? rest.slice(slash + 1) : 'index.html';
      const ws = workspaces.find((w: LocalWorkspace): boolean => w.id === wsId || w.name === wsId);
      if (!ws) {
        throw new Error(`未找到沙箱工作区: ${wsId}`);
      }
      const content = await readWorkspaceText(ws.rootPath, relPath);
      const html = relPath.toLowerCase().endsWith('.html') || relPath.toLowerCase().endsWith('.htm')
        ? content
        : `<!doctype html><html><body style="font-family:sans-serif;padding:16px"><pre>${content.replace(/</g, '&lt;')}</pre></body></html>`;
      tab.url = url;
      tab.title = relPath;
      tab.htmlContent = html;
      if (tab.attached) {
        tab.controller.loadData(html, 'text/html', 'UTF-8', 'https://kelivo.local/');
      }
      this.notify();
      return `已在浏览器标签加载工作区文件 ${relPath}`;
    }

    if (!/^https?:\/\//i.test(url) && !url.startsWith('about:')) {
      url = url.indexOf('.') >= 0 && url.indexOf(' ') < 0
        ? `https://${url}`
        : `https://duckduckgo.com/?q=${encodeURIComponent(url)}`;
    }
    tab.url = url;
    tab.htmlContent = '';
    if (tab.attached) {
      try {
        tab.controller.loadUrl(url);
      } catch (_) {}
    }
    this.notify();
    return `已导航至 ${url}`;
  }

  renderHtmlInTab(tab: BrowserTab, html: string, title: string = 'HTML 渲染'): void {
    tab.title = title;
    tab.url = 'about:kelivo-render';
    tab.htmlContent = html;
    if (tab.attached) {
      try {
        tab.controller.loadData(html, 'text/html', 'UTF-8', 'https://kelivo.local/');
      } catch (_) {}
    }
    this.notify();
  }

  private async runDomScript(tab: BrowserTab, script: string): Promise<string> {
    if (!tab.attached) {
      throw new Error('浏览器视图尚未挂载，请先切换到「内置浏览器」标签页或平板侧边栏视图');
    }
    const raw = await tab.controller.runJavaScript(script);
    return unwrapJsString(raw);
  }

  async executeAction(argsJson: string, workspaces: LocalWorkspace[]): Promise<ToolExecutionOutput> {
    let args: Record<string, Object> = {};
    try {
      args = JSON.parse(argsJson || '{}') as Record<string, Object>;
    } catch (_) {
      return { text: '参数 JSON 解析失败', isError: true };
    }
    const action = String(args['action'] || '').trim();
    const tabId = typeof args['tab_id'] === 'string' ? (args['tab_id'] as string) : undefined;
    const tab = this.findTab(tabId);

    try {
      if (action === 'list_tabs') {
        const lines = this.tabs.map((t: BrowserTab, i: number): string =>
          `${i + 1}. id=${t.id} ${t.id === this.activeTabId ? '[当前]' : ''} | ${t.title || '无标题'} | ${t.url}`
        );
        return { text: lines.join('\n') };
      }

      if (action === 'new_tab') {
        const url = typeof args['url'] === 'string' ? (args['url'] as string) : 'https://duckduckgo.com';
        const title = typeof args['title'] === 'string' ? (args['title'] as string) : '新标签页';
        const created = this.newTab(url, title);
        await this.navigateTab(created, url, workspaces);
        return { text: `已新建并切换到标签 ${created.id} -> ${created.url}` };
      }

      if (action === 'switch_tab') {
        if (!tabId || !this.switchTab(tabId)) {
          return { text: `未找到标签页 ${tabId || ''}`, isError: true };
        }
        return { text: `已切换到标签 ${tabId}` };
      }

      if (action === 'close_tab') {
        const targetId = tabId || this.activeTabId;
        this.closeTab(targetId);
        return { text: `已关闭标签 ${targetId}` };
      }

      if (action === 'open') {
        const url = String(args['url'] || '');
        const msg = await this.navigateTab(tab, url, workspaces);
        if (!tab.attached && /^https?:\/\//i.test(tab.url)) {
          const preview = await fetchWebPage(tab.url, 4000, 0);
          return { text: `${msg}\n（浏览器视图后台预抓正文摘要）\n${preview}` };
        }
        return { text: msg };
      }

      if (action === 'render') {
        const html = String(args['html'] || '');
        const title = typeof args['title'] === 'string' ? (args['title'] as string) : '动态预览';
        this.renderHtmlInTab(tab, html, title);
        return { text: `已在内置浏览器标签 ${tab.id} 渲染 ${html.length} 字符 HTML` };
      }

      if (action === 'back') {
        if (!tab.attached) return { text: '浏览器视图尚未打开', isError: true };
        tab.controller.backward();
        return { text: '已执行后退' };
      }

      if (action === 'forward') {
        if (!tab.attached) return { text: '浏览器视图尚未打开', isError: true };
        tab.controller.forward();
        return { text: '已执行前进' };
      }

      if (action === 'reload') {
        if (!tab.attached) return { text: '浏览器视图尚未打开', isError: true };
        tab.controller.refresh();
        return { text: '已刷新当前页面' };
      }

      if (action === 'wait') {
        const ms = Math.min(8000, Math.max(100, Number(args['ms'] || 1000)));
        await new Promise<void>((resolve) => {
          setTimeout(() => resolve(), ms);
        });
        return { text: `已等待 ${ms} ms` };
      }

      if (action === 'extract') {
        if (!tab.attached && /^https?:\/\//i.test(tab.url)) {
          const txt = await fetchWebPage(tab.url, 12000, 0);
          return { text: txt };
        }
        const js =
          `(function(){` +
          `const title = document.title || '';` +
          `const url = location.href;` +
          `const bodyText = (document.body && document.body.innerText || '').slice(0, 12000);` +
          `return JSON.stringify({title, url, text: bodyText});` +
          `})()`;
        return { text: await this.runDomScript(tab, js) };
      }

      if (action === 'snapshot') {
        const js =
          `(function(){` +
          `const els = Array.from(document.querySelectorAll('a,button,input,textarea,select,[role=button]')).slice(0, 80);` +
          `const items = els.map((el, i) => {` +
          `  el.setAttribute('data-kelivo-idx', String(i + 1));` +
          `  const txt = (el.innerText || el.value || el.getAttribute('aria-label') || el.getAttribute('placeholder') || '').replace(/\\s+/g,' ').trim().slice(0,60);` +
          `  return '@' + (i + 1) + ' <' + el.tagName.toLowerCase() + '> ' + txt;` +
          `});` +
          `return 'Title: ' + document.title + '\\nURL: ' + location.href + '\\nElements:\\n' + items.join('\\n') + '\\n\\nText:\\n' + (document.body ? document.body.innerText.slice(0, 3000) : '');` +
          `})()`;
        return { text: await this.runDomScript(tab, js) };
      }

      if (action === 'click') {
        const sel = String(args['selector'] || '');
        const js =
          `(function(){const el=${jsSelectorExpr(sel)};if(!el)return 'ELEMENT_NOT_FOUND';el.scrollIntoView({block:'center'});el.click();return 'CLICKED';})()`;
        const res = await this.runDomScript(tab, js);
        if (res === 'ELEMENT_NOT_FOUND') {
          return { text: `未找到元素: ${sel}`, isError: true };
        }
        return { text: `已点击 ${sel}` };
      }

      if (action === 'type') {
        const sel = String(args['selector'] || '');
        const val = String(args['text'] ?? '');
        const js =
          `(function(){const el=${jsSelectorExpr(sel)};if(!el)return 'ELEMENT_NOT_FOUND';el.focus();el.value=${JSON.stringify(val)};el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));return 'TYPED';})()`;
        const res = await this.runDomScript(tab, js);
        if (res === 'ELEMENT_NOT_FOUND') {
          return { text: `未找到输入框: ${sel}`, isError: true };
        }
        return { text: `已向 ${sel} 输入内容` };
      }

      if (action === 'select_option') {
        const sel = String(args['selector'] || '');
        const val = String(args['value'] ?? '');
        const js =
          `(function(){const el=${jsSelectorExpr(sel)};if(!el)return 'ELEMENT_NOT_FOUND';el.value=${JSON.stringify(val)};el.dispatchEvent(new Event('change',{bubbles:true}));return 'SELECTED';})()`;
        const res = await this.runDomScript(tab, js);
        if (res === 'ELEMENT_NOT_FOUND') {
          return { text: `未找到下拉框: ${sel}`, isError: true };
        }
        return { text: `已选择 ${val}` };
      }

      if (action === 'press') {
        const key = String(args['key'] || 'Enter');
        const js =
          `(function(){const target=document.activeElement||document.body;target.dispatchEvent(new KeyboardEvent('keydown',{key:${JSON.stringify(key)},bubbles:true}));if(${JSON.stringify(key)}==='Enter'&&target.form&&target.form.requestSubmit){target.form.requestSubmit();}return 'PRESSED';})()`;
        await this.runDomScript(tab, js);
        return { text: `已按下 ${key}` };
      }

      if (action === 'scroll') {
        const dir = String(args['direction'] || 'down');
        const dy = typeof args['y'] === 'number' ? (args['y'] as number) : (dir === 'up' ? -500 : 500);
        const js = dir === 'top'
          ? `window.scrollTo(0, 0);'TOP'`
          : (dir === 'bottom' ? `window.scrollTo(0, document.body.scrollHeight);'BOTTOM'` : `window.scrollBy(0, ${dy});'SCROLLED'`);
        await this.runDomScript(tab, js);
        return { text: `已滚动页面 (${dir})` };
      }

      if (action === 'evaluate') {
        const script = String(args['script'] || '');
        const res = await this.runDomScript(tab, script);
        return { text: res || '(脚本无返回值)' };
      }

      if (action === 'screenshot') {
        const js =
          `(function(){return JSON.stringify({url:location.href,title:document.title,width:window.innerWidth,height:window.innerHeight,scrollY:window.scrollY});})()`;
        const meta = await this.runDomScript(tab, js);
        return { text: `当前视口快照状态: ${meta}` };
      }

      return { text: `未知浏览器动作: ${action}`, isError: true };
    } catch (e) {
      return { text: `浏览器操作失败: ${(e as Error).message || String(e)}`, isError: true };
    }
  }
}
