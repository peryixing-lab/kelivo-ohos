import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { ensureDir } from '../core/AttachmentStore';

export type RichPreviewKind = 'html' | 'svg' | 'mermaid' | 'plantuml' | 'math' | 'markdown';

class AppHtmlBridge {
  private baseDir: string;

  constructor(baseDir: string) {
    this.baseDir = baseDir;
  }

  private safePath(rel: string): string {
    const clean = rel.replace(/^\/+/, '').replace(/\.\./g, '');
    if (!clean || !/\.(json|txt|md|csv)$/i.test(clean)) {
      throw new Error('仅支持 .json/.txt/.md/.csv 文件');
    }
    return this.baseDir + '/' + clean;
  }

  readJsonSync(rel: string, fallbackJson: string): string {
    try {
      const target = this.safePath(rel);
      if (!fs.accessSync(target)) return fallbackJson;
      return fs.readTextSync(target);
    } catch (_) {
      return fallbackJson;
    }
  }

  saveJsonSync(rel: string, payloadJson: string): boolean {
    try {
      if (payloadJson.length > 2 * 1024 * 1024) return false;
      const target = this.safePath(rel);
      const dir = target.slice(0, target.lastIndexOf('/'));
      if (!fs.accessSync(dir)) fs.mkdirSync(dir, true);
      const file = fs.openSync(target, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        const bytes = util.TextEncoder.create().encodeInto(payloadJson);
        fs.writeSync(file.fd, bytes.buffer);
      } finally {
        fs.closeSync(file);
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}

function escapeHtmlAttr(raw: string): string {
  return raw
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function buildPreviewHtml(kind: RichPreviewKind, content: string, hasAppBridge: boolean): string {
  const bridgeShim = hasAppBridge ?
    '<script>window.kelivo={readJson:async function(p,d){return JSON.parse(kelivoNative.readJsonSync(p,JSON.stringify(d)));},' +
    'saveJson:async function(p,v){return kelivoNative.saveJsonSync(p,JSON.stringify(v));}};</script>' : '';

  if (kind === 'html') {
    if (/<html/i.test(content)) {
      return bridgeShim + content;
    }
    return '<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">' +
      '<style>body{font-family:sans-serif;padding:16px;margin:0;color:#1a1b21;background:#ffffff;}</style>' +
      bridgeShim + '</head><body>' + content + '</body></html>';
  }
  if (kind === 'svg') {
    return '<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">' +
      '<style>body{margin:0;padding:16px;display:flex;justify-content:center;align-items:center;min-height:90vh;background:#fff;}svg{max-width:100%;height:auto;}</style>' +
      '</head><body>' + content + '</body></html>';
  }
  if (kind === 'mermaid') {
    const escaped = escapeHtmlAttr(content);
    return '<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">' +
      '<style>body{margin:0;padding:16px;font-family:sans-serif;background:#fff;color:#1a1b21;}pre{white-space:pre-wrap;background:#f5f6fa;padding:12px;border-radius:8px;}</style>' +
      '</head><body><div class="mermaid" id="m">' + escaped + '</div>' +
      '<pre id="fb" style="display:none">' + escaped + '</pre>' +
      '<script src="https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js" onerror="document.getElementById(\'fb\').style.display=\'block\'"></script>' +
      '<script>if(window.mermaid){mermaid.initialize({startOnLoad:true,theme:"default"});}else{document.getElementById("fb").style.display="block";}</script>' +
      '</body></html>';
  }
  if (kind === 'math') {
    const escaped = JSON.stringify(content);
    return '<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">' +
      '<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.css">' +
      '<style>body{margin:0;padding:24px;font-size:20px;display:flex;justify-content:center;align-items:center;min-height:60vh;background:#fff;color:#1a1b21;}pre{white-space:pre-wrap;font-size:15px;}</style>' +
      '</head><body><div id="out"></div>' +
      '<script src="https://cdn.jsdelivr.net/npm/katex@0.16.11/dist/katex.min.js"></script>' +
      '<script>var src=' + escaped + ';var el=document.getElementById("out");' +
      'if(window.katex){try{katex.render(src,el,{displayMode:true,throwOnError:false});}catch(e){el.textContent=src;}}else{el.innerHTML="<pre>"+src+"</pre>";}</script>' +
      '</body></html>';
  }
  if (kind === 'markdown') {
    const escaped = JSON.stringify(content);
    return '<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">' +
      '<style>body{margin:0;padding:20px 18px;font-family:-apple-system,BlinkMacSystemFont,sans-serif;font-size:16px;line-height:1.75;color:#1a1b21;background:#fff;word-wrap:break-word;}' +
      'h1,h2,h3{margin:18px 0 8px;line-height:1.35;}p{margin:8px 0;}' +
      'blockquote{margin:10px 0;padding:6px 12px;border-left:3px solid #6b7280;background:#f5f6fa;border-radius:4px;color:#4b5563;}' +
      'pre{background:#f5f6fa;padding:12px;border-radius:8px;overflow-x:auto;font-size:13px;line-height:1.5;}' +
      'code{background:#f1f3f7;padding:2px 5px;border-radius:4px;font-size:14px;}pre code{background:transparent;padding:0;}' +
      'ul,ol{margin:8px 0;padding-left:22px;}li{margin:4px 0;}hr{border:none;border-top:1px solid #e5e7eb;margin:16px 0;}' +
      'a{color:#2563eb;text-decoration:none;}</style></head><body><div id="md"></div><script>' +
      'function esc(s){return s.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");}' +
      'function inline(s){return esc(s).replace(/`([^`]+)`/g,"<code>$1</code>").replace(/\\*\\*([^*]+)\\*\\*/g,"<strong>$1</strong>").replace(/\\*([^*]+)\\*/g,"<em>$1</em>").replace(/\\[([^\\]]+)\\]\\((https?:\\/\\/[^)]+)\\)/g,"<a href=\\"$2\\">$1</a>");}' +
      'var lines=' + escaped + '.split(/\\r?\\n/),out=[],inCode=false,codeBuf=[];' +
      'for(var i=0;i<lines.length;i++){var l=lines[i];if(l.indexOf("```")===0){if(inCode){out.push("<pre><code>"+esc(codeBuf.join("\\n"))+"</code></pre>");codeBuf=[];inCode=false;}else{inCode=true;}continue;}' +
      'if(inCode){codeBuf.push(l);continue;}if(/^---+$/.test(l.trim())){out.push("<hr>");continue;}' +
      'if(l.indexOf("### ")===0){out.push("<h3>"+inline(l.slice(4))+"</h3>");continue;}if(l.indexOf("## ")===0){out.push("<h2>"+inline(l.slice(3))+"</h2>");continue;}if(l.indexOf("# ")===0){out.push("<h1>"+inline(l.slice(2))+"</h1>");continue;}' +
      'if(l.indexOf("> ")===0){out.push("<blockquote>"+inline(l.slice(2))+"</blockquote>");continue;}' +
      'if(/^[-*]\\s+/.test(l)){out.push("<ul><li>"+inline(l.replace(/^[-*]\\s+/,""))+"</li></ul>");continue;}' +
      'if(/^\\d+\\.\\s+/.test(l)){out.push("<ol><li>"+inline(l.replace(/^\\d+\\.\\s+/,""))+"</li></ol>");continue;}' +
      'if(l.trim().length===0){out.push("");}else{out.push("<p>"+inline(l)+"</p>");}}' +
      'if(inCode){out.push("<pre><code>"+esc(codeBuf.join("\\n"))+"</code></pre>");}' +
      'document.getElementById("md").innerHTML=out.join("").replace(/<\\/ul><ul>/g,"").replace(/<\\/ol><ol>/g,"");' +
      '</script></body></html>';
  }
  // PlantUML preview (fallback text + Kroki SVG rendering)
  const escaped = JSON.stringify(content);
  return '<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">' +
    '<style>body{margin:0;padding:16px;font-family:sans-serif;background:#fff;}pre{background:#f5f6fa;padding:12px;border-radius:8px;white-space:pre-wrap;}</style>' +
    '</head><body><div id="p">正在加载 PlantUML 图表…</div><pre id="raw"></pre>' +
    '<script>var src=' + escaped + ';document.getElementById("raw").textContent=src;' +
    'fetch("https://kroki.io/plantuml/svg",{method:"POST",headers:{"Content-Type":"text/plain"},body:src})' +
    '.then(function(r){if(!r.ok)throw new Error(r.status);return r.text();})' +
    '.then(function(svg){document.getElementById("p").innerHTML=svg;})' +
    '.catch(function(){document.getElementById("p").textContent="离线或服务不可用，已展示源码：";});</script>' +
    '</body></html>';
}

@Component
export struct RichPreviewSheet {
  previewTitle: string = '内容预览';
  previewKind: RichPreviewKind = 'html';
  sourceCode: string = '';
  appDataKey: string = '';
  onClose: () => void = () => {};
  @State showSource: boolean = false;
  private controller: webview.WebviewController = new webview.WebviewController();
  private bridge?: AppHtmlBridge;
  private loaded: boolean = false;

  aboutToAppear(): void {
    if (this.appDataKey) {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const dir = ctx.filesDir + '/app_data/' + this.appDataKey.replace(/[^a-zA-Z0-9_-]/g, '_');
      ensureDir(dir).catch(() => {});
      this.bridge = new AppHtmlBridge(dir);
    }
  }

  private renderWeb(): void {
    if (this.loaded) return;
    this.loaded = true;
    const html = buildPreviewHtml(this.previewKind, this.sourceCode, !!this.bridge);
    try {
      this.controller.loadData(html, 'text/html', 'UTF-8', 'https://kelivo.local/');
    } catch (_) {}
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Button('关闭').backgroundColor(Color.Transparent).fontColor($r('app.color.accent')).onClick(() => this.onClose())
        Text(this.previewTitle).fontSize(18).fontWeight(FontWeight.Bold).fontColor($r('app.color.ink'))
          .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Button(this.showSource ? '渲染视图' : '源码').height(32).fontSize(13)
          .backgroundColor($r('app.color.panel')).fontColor($r('app.color.ink'))
          .onClick(() => { this.showSource = !this.showSource; })
      }.width('100%').height(58).padding({ left: 8, right: 12 })

      if (this.showSource) {
        Scroll() {
          Text(this.sourceCode).fontFamily('monospace').fontSize(13).lineHeight(20)
            .fontColor($r('app.color.ink')).copyOption(CopyOptions.LocalDevice)
            .padding(16).width('100%')
        }.layoutWeight(1).width('100%')
      } else {
        Web({ src: 'about:blank', controller: this.controller })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .javaScriptProxy(this.bridge ? {
            object: this.bridge,
            name: 'kelivoNative',
            methodList: ['readJsonSync', 'saveJsonSync'],
            controller: this.controller
          } : {
            object: new Object(),
            name: 'kelivoNoop',
            methodList: [],
            controller: this.controller
          })
          .onPageEnd(() => { this.renderWeb(); })
          .layoutWeight(1)
          .width('100%')
      }
    }.width('100%').height('100%').backgroundColor(Color.Transparent)
  }
}
