import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// 提词器的网页视图：透明底，字色、强调色跟悬浮窗的主题走。
/// 载入后给每一段编上号，把各段的文字交给 Swift（跟读、目录用）；滚动时告诉 Swift 现在读到第几段。
/// 页面走自己的 tyto-doc:// 地址：主页面是转好的 HTML，图片等相对路径从材料所在的文件夹读（只能读这个文件夹里的）。
@MainActor
final class PrompterWeb: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let view: PrompterWebView
    private let pages = PrompterSchemeHandler()
    private let content = WKUserContentController()
    private var style: [String: String] = [:]
    /// 载入完成后要滚到的段（重新载入时保持位置）
    private var pendingBlock: Int?

    var onBlocks: (([PrompterMatch.Block]) -> Void)?
    var onReading: ((Int) -> Void)?
    var onDropFile: ((URL) -> Void)? {
        didSet { view.onDropFile = onDropFile }
    }

    /// 读的位置：离顶上 30% 的那条线。跳到某段时把它放在这条线上，上面还能看到一点前文
    static let readingLine = 0.3

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(pages, forURLScheme: PrompterSchemeHandler.scheme)
        configuration.userContentController = content
        view = PrompterWebView(frame: NSRect(x: 0, y: 0, width: 420, height: 500), configuration: configuration)
        super.init()
        content.add(WeakScriptHandler(self), name: "tyto")
        view.navigationDelegate = self
        view.setValue(false, forKey: "drawsBackground")
        view.underPageBackgroundColor = .clear
        view.allowsMagnification = false
        view.allowsBackForwardNavigationGestures = false
    }

    func load(_ document: PrompterDocument, keeping block: Int?) {
        pages.page = Data(document.html.utf8)
        pages.pagePath = "/" + document.url.lastPathComponent
        pages.folder = document.url.deletingLastPathComponent().standardizedFileURL
        pendingBlock = block
        // 样式写进脚本里，页面一出来就是对的颜色，不闪一下白底黑字
        content.removeAllUserScripts()
        content.addUserScript(WKUserScript(source: Self.script(style: style), injectionTime: .atDocumentEnd,
                                           forMainFrameOnly: true))
        var components = URLComponents()
        components.scheme = PrompterSchemeHandler.scheme
        components.host = "doc"
        components.path = pages.pagePath
        if let url = components.url { view.load(URLRequest(url: url)) }
    }

    func clear() {
        pages.page = Data()
        view.loadHTMLString("", baseURL: nil)
    }

    /// 主题、字色变了：换颜色（不重新载入）
    func apply(theme: OverlayTheme, opacity: Double, fontSize: Double) {
        style = Self.style(theme: theme, opacity: opacity)
        view.pageZoom = fontSize / Self.baseFontSize
        run("window.tyto && tyto.style(\(Self.json(style)))")
    }

    /// 滚到某一段，放在读的位置上。mark：高亮它（跟读、跳转）；只是恢复位置时不高亮
    func go(to block: Int, mark: Bool, smooth: Bool = true) {
        run("window.tyto && tyto.go(\(block), \(mark), \(smooth))")
    }

    func mark(_ block: Int?) {
        run("window.tyto && tyto.mark(\(block ?? -1))")
    }

    private func run(_ script: String) {
        view.evaluateJavaScript(script, completionHandler: nil)
    }

    // MARK: - 网页发来的消息

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "blocks":
            let raw = body["blocks"] as? [[String: Any]] ?? []
            let blocks = raw.enumerated().map { index, item in
                PrompterMatch.Block(index: index, level: item["l"] as? Int ?? 0, text: item["t"] as? String ?? "")
            }
            onBlocks?(blocks)
            if let block = pendingBlock {
                pendingBlock = nil
                go(to: block, mark: false, smooth: false)
            }
        case "reading":
            if let index = body["index"] as? Int { onReading?(index) }
        default:
            break
        }
    }

    // MARK: - 链接：网页链接用浏览器打开，提词器里只留材料本身

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        if url.scheme == PrompterSchemeHandler.scheme || url.scheme == "about" || action.targetFrame?.isMainFrame == false {
            return decisionHandler(.allow)
        }
        if ["http", "https", "mailto"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
        decisionHandler(.cancel)
    }

    // MARK: - 样式

    static let baseFontSize = 17.0

    private static func style(theme: OverlayTheme, opacity: Double) -> [String: String] {
        let ink = theme.ink
        return [
            "--tyto-ink": css(ink),
            "--tyto-dim": css(ink, 0.64),
            "--tyto-rule": css(ink, 0.14),
            "--tyto-code": css(ink, theme.light ? 0.07 : 0.10),
            "--tyto-accent": css(theme.accent),
            "--tyto-link": css(theme.light ? theme.accent : theme.entity),
            "--tyto-current": css(theme.accent, theme.light ? 0.13 : 0.16),
            "--tyto-flash": css(theme.accent, 0.38),
            "--tyto-halo": css(theme.halo, GlassBackground.textShadow(opacity)),
            "--tyto-bg-lum": String(format: "%.4f", luminance(theme.light ? Color.white : theme.tint)),
            "color-scheme": theme.light ? "light" : "dark",
        ]
    }

    private static func css(_ color: Color, _ alpha: Double = 1) -> String {
        let rgb = NSColor(color).usingColorSpace(.sRGB) ?? .white
        return String(format: "rgba(%d, %d, %d, %.3f)", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255),
                      Int(rgb.blueComponent * 255), alpha * rgb.alphaComponent)
    }

    private static func luminance(_ color: Color) -> Double {
        let rgb = NSColor(color).usingColorSpace(.sRGB) ?? .black
        func linear(_ c: CGFloat) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
    }

    private static func json(_ value: [String: String]) -> String {
        (try? JSONSerialization.data(withJSONObject: value)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }

    /// 注入每个页面的脚本：加样式、给段编号、报告读到哪、跳转和高亮。
    /// 别人写的 HTML 里的颜色在玻璃上看不清时（对比度不到 3:1）换成正文颜色；铺满整页的白底去掉
    private static func script(style: [String: String]) -> String {
        """
        (() => {
        if (window.tyto) return;
        const post = (m) => { try { webkit.messageHandlers.tyto.postMessage(m) } catch (e) {} };
        const css = `\(stylesheet)`;
        const sheet = document.createElement('style');
        sheet.id = 'tyto-style';
        sheet.textContent = css;
        (document.head || document.documentElement).appendChild(sheet);
        const root = document.documentElement;
        const LEAF = new Set(['H1','H2','H3','H4','H5','H6','P','LI','PRE','BLOCKQUOTE','TR','DT','DD','FIGCAPTION','CAPTION']);
        const BOX = new Set(['DIV','SECTION','ARTICLE','MAIN','HEADER','FOOTER','ASIDE','BODY']);
        const CELL = new Set(['TD','TH','BR']);
        const SKIP = new Set(['SCRIPT','STYLE','NOSCRIPT','TEMPLATE','SVG']);
        const directText = (el) => { for (const n of el.childNodes) if (n.nodeType === 3 && n.textContent.trim()) return true; return false; };
        const isBlock = (el) => LEAF.has(el.tagName) || (BOX.has(el.tagName) && directText(el));
        const textOf = (el) => {
          let s = '';
          const walk = (node) => {
            for (const n of node.childNodes) {
              if (n.nodeType === 3) s += n.textContent;
              else if (n.nodeType === 1 && !SKIP.has(n.tagName.toUpperCase())) {
                if (isBlock(n)) { s += ' '; continue; }
                walk(n);
                if (CELL.has(n.tagName)) s += ' ';
              }
            }
          };
          walk(el);
          return s.replace(/\\s+/g, ' ').trim();
        };
        let blocks = [];
        let reading = -1;
        const readingLine = () => innerHeight * \(readingLine);
        const index = () => {
          blocks = [];
          const out = [];
          for (const el of document.body.querySelectorAll('*')) {
            if (SKIP.has(el.tagName.toUpperCase()) || !isBlock(el)) continue;
            const t = textOf(el);
            if (!t) continue;
            el.dataset.tb = blocks.length;
            blocks.push(el);
            out.push({ l: /^H[1-6]$/.test(el.tagName) ? +el.tagName[1] : 0, t });
          }
          post({ type: 'blocks', blocks: out });
          reading = -1;
          updateReading();
        };
        const updateReading = () => {
          if (!blocks.length) return;
          const line = readingLine();
          let lo = 0, hi = blocks.length - 1, found = blocks.length - 1;
          while (lo <= hi) {
            const mid = (lo + hi) >> 1;
            if (blocks[mid].getBoundingClientRect().bottom >= line) { found = mid; hi = mid - 1; } else lo = mid + 1;
          }
          if (found !== reading) { reading = found; post({ type: 'reading', index: found }); }
        };
        // 不用 requestAnimationFrame：窗口被挡住时它不跑，读的位置就停在老地方了
        let ticking = false;
        const onScroll = () => { if (!ticking) { ticking = true; setTimeout(() => { ticking = false; updateReading(); }, 60); } };
        addEventListener('scroll', onScroll, { passive: true });
        addEventListener('resize', onScroll);
        const parse = (c) => {
          const m = /rgba?\\(([^)]+)\\)/.exec(c || '');
          if (!m) return null;
          const p = m[1].split(/[\\s,\\/]+/).filter(Boolean).map(Number);
          return { r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1 };
        };
        const lum = (c) => {
          const f = (v) => { v /= 255; return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); };
          return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
        };
        const legible = () => {
          if (document.querySelector('.tyto-doc')) return;
          document.querySelectorAll('.tyto-ink, .tyto-clear').forEach(e => e.classList.remove('tyto-ink', 'tyto-clear'));
          const width = document.body.clientWidth;
          for (const el of document.body.querySelectorAll('*')) {
            const bg = parse(getComputedStyle(el).backgroundColor);
            if (bg && bg.a > 0.5 && el.offsetWidth >= width * 0.85 && el.offsetHeight >= innerHeight * 0.5) el.classList.add('tyto-clear');
          }
          const base = parseFloat(getComputedStyle(root).getPropertyValue('--tyto-bg-lum')) || 0.01;
          for (const el of document.body.querySelectorAll('*')) {
            if (SKIP.has(el.tagName.toUpperCase()) || !directText(el)) continue;
            let own = false;
            for (let n = el; n && n !== document.body; n = n.parentElement) {
              const bg = parse(getComputedStyle(n).backgroundColor);
              if (bg && bg.a > 0.5 && !n.classList.contains('tyto-clear')) { own = true; break; }
            }
            if (own) continue;
            const c = parse(getComputedStyle(el).color);
            if (!c) continue;
            const l = lum(c);
            if ((Math.max(l, base) + 0.05) / (Math.min(l, base) + 0.05) < 3) el.classList.add('tyto-ink');
          }
        };
        const setStyle = (vars) => {
          for (const k in vars) {
            if (k === 'color-scheme') root.style.colorScheme = vars[k]; else root.style.setProperty(k, vars[k]);
          }
          legible();
        };
        const mark = (i) => {
          document.querySelectorAll('.tyto-current').forEach(e => e.classList.remove('tyto-current'));
          if (blocks[i]) blocks[i].classList.add('tyto-current');
        };
        window.tyto = {
          style: setStyle,
          mark,
          go(i, marked, smooth) {
            const el = blocks[i];
            if (!el) return;
            if (marked) {
              mark(i);
              el.classList.remove('tyto-flash');
              void el.offsetWidth;
              el.classList.add('tyto-flash');
            }
            const top = el.getBoundingClientRect().top + scrollY - readingLine() + 4;
            scrollTo({ top: Math.max(0, top), behavior: smooth ? 'smooth' : 'auto' });
          },
        };
        setStyle(\(json(style)));
        index();
        // 网页自己用脚本生成内容时，等它停下来再重新编号
        let timer = null;
        new MutationObserver((list) => {
          if (list.every(r => r.type === 'attributes')) return;
          clearTimeout(timer);
          timer = setTimeout(() => { index(); legible(); }, 600);
        }).observe(document.body, { childList: true, subtree: true, characterData: true });
        })();
        """
    }

    /// 只给 Markdown / 纯文本转出来的页面（.tyto-doc）排版；别人的 HTML 只动背景、留白和看不清的字色
    private static let stylesheet = """
    html, body { background: transparent !important; }
    body {
      margin: 0; color: var(--tyto-ink); text-shadow: 0 0.5px 1.4px var(--tyto-halo);
      -webkit-font-smoothing: antialiased; padding-bottom: 60vh !important;
    }
    .tyto-clear { background: transparent !important; box-shadow: none !important; }
    .tyto-ink { color: var(--tyto-ink) !important; }
    .tyto-doc {
      padding: 12px 22px 0 28px; font: 17px/1.62 -apple-system, "PingFang SC", "Hiragino Sans GB", sans-serif;
      overflow-wrap: anywhere;
    }
    .tyto-doc > :first-child { margin-top: 4px; }
    .tyto-doc h1, .tyto-doc h2, .tyto-doc h3, .tyto-doc h4 { line-height: 1.3; font-weight: 650; margin: 1.3em 0 0.45em; }
    .tyto-doc h1 { font-size: 1.5em; }
    .tyto-doc h2 { font-size: 1.28em; padding-bottom: 0.25em; border-bottom: 1px solid var(--tyto-rule); }
    .tyto-doc h3 { font-size: 1.1em; }
    .tyto-doc h4, .tyto-doc h5, .tyto-doc h6 { font-size: 1em; color: var(--tyto-dim); }
    .tyto-doc p { margin: 0 0 0.75em; }
    .tyto-doc ul, .tyto-doc ol { margin: 0 0 0.75em; padding-left: 1.4em; }
    .tyto-doc li { margin: 0.2em 0; }
    .tyto-doc li::marker { color: var(--tyto-dim); }
    .tyto-doc li > input[type=checkbox] { margin: 0 0.4em 0 -1.3em; vertical-align: -0.1em; }
    .tyto-doc strong { font-weight: 700; }
    .tyto-doc em { font-style: italic; }
    .tyto-doc del { color: var(--tyto-dim); }
    .tyto-doc a { color: var(--tyto-link); text-decoration: none; border-bottom: 1px solid var(--tyto-rule); }
    .tyto-doc blockquote { margin: 0 0 0.75em; padding: 0.1em 0 0.1em 0.9em; border-left: 3px solid var(--tyto-rule); color: var(--tyto-dim); }
    .tyto-doc blockquote p:last-child { margin-bottom: 0; }
    .tyto-doc code { font: 0.88em/1.4 "SF Mono", Menlo, monospace; background: var(--tyto-code); padding: 0.1em 0.35em; border-radius: 5px; }
    .tyto-doc pre { background: var(--tyto-code); padding: 0.7em 0.9em; border-radius: 9px; overflow-x: auto; margin: 0 0 0.75em; }
    .tyto-doc pre code { background: none; padding: 0; }
    .tyto-doc hr { border: 0; border-top: 1px solid var(--tyto-rule); margin: 1.2em 0; }
    .tyto-doc img { max-width: 100%; border-radius: 8px; }
    .tyto-doc table { border-collapse: collapse; margin: 0 0 0.9em; font-size: 0.92em; }
    .tyto-doc th, .tyto-doc td { border: 1px solid var(--tyto-rule); padding: 0.35em 0.6em; vertical-align: top; }
    .tyto-doc th { font-weight: 650; }
    .tyto-current:not(tr) {
      position: relative; background-color: var(--tyto-current) !important; border-radius: 6px;
      box-shadow: 0 0 0 6px var(--tyto-current) !important;
    }
    .tyto-current:not(tr)::before {
      content: ""; position: absolute; left: -13px; top: 1px; bottom: 1px; width: 3px; border-radius: 2px;
      background: var(--tyto-accent);
    }
    tr.tyto-current > * { background-color: var(--tyto-current) !important; }
    .tyto-flash { animation: tyto-flash 1.1s ease-out; }
    @keyframes tyto-flash { from { background-color: var(--tyto-flash); box-shadow: 0 0 0 6px var(--tyto-flash); } }
    ::selection { background: var(--tyto-flash); }
    """
}

/// 网页视图本身：把材料文件拖进来就换成它（不让网页自己打开那个文件）；没拿到焦点时第一下点击也算数
final class PrompterWebView: WKWebView {
    var onDropFile: ((URL) -> Void)?

    private func droppedFile(_ info: NSDraggingInfo) -> URL? {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                       options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return urls?.first(where: PrompterDocument.canOpen)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedFile(sender) != nil ? .copy : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        droppedFile(sender) != nil ? .copy : super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let url = droppedFile(sender) {
            onDropFile?(url)
            return true
        }
        return super.performDragOperation(sender)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// tyto-doc://doc/<文件名> 是转好的页面；别的路径从材料所在文件夹里读，读不到文件夹外面
@MainActor
final class PrompterSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "tyto-doc"
    var page = Data()
    var pagePath = "/"
    var folder: URL?

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        let path = url.path(percentEncoded: false)
        if path == pagePath {
            return reply(task, url: url, data: page, mime: "text/html", encoding: "utf-8")
        }
        guard let folder else { return task.didFailWithError(URLError(.fileDoesNotExist)) }
        let file = folder.appending(path: String(path.drop(while: { $0 == "/" }))).standardizedFileURL
        guard file.path.hasPrefix(folder.path + "/"), let data = try? Data(contentsOf: file) else {
            return task.didFailWithError(URLError(.fileDoesNotExist))
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        reply(task, url: url, data: data, mime: mime, encoding: nil)
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}

    private func reply(_ task: any WKURLSchemeTask, url: URL, data: Data, mime: String, encoding: String?) {
        task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: encoding))
        task.didReceive(data)
        task.didFinish()
    }
}

/// WKUserContentController 会强引用消息处理者；隔一层弱引用，网页视图和 PrompterWeb 才能一起释放
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: (any WKScriptMessageHandler)?

    init(_ target: any WKScriptMessageHandler) { self.target = target }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}
