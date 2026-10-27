import Foundation
import Markdown

/// 提词器读的一份材料。Markdown、纯文本转成 HTML；HTML 原样用（样式由提词器的网页视图统一加）。
struct PrompterDocument: Equatable {
    enum Kind: Equatable {
        case markdown
        case html
        case text
    }

    let url: URL
    let kind: Kind
    /// 网页视图要显示的整页 HTML
    let html: String
    let modified: Date?

    var name: String { url.lastPathComponent }

    static let kinds: [String: Kind] = [
        "md": .markdown, "markdown": .markdown, "mdown": .markdown, "mkd": .markdown,
        "html": .html, "htm": .html, "xhtml": .html,
        "txt": .text, "text": .text,
    ]

    static func canOpen(_ url: URL) -> Bool { kinds[url.pathExtension.lowercased()] != nil }

    static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    static func load(_ url: URL) throws -> PrompterDocument {
        let data = try Data(contentsOf: url)
        let source = decode(data)
        let kind = kinds[url.pathExtension.lowercased()] ?? .text
        let html = switch kind {
        case .markdown: page(HTMLFormatter.format(stripFrontMatter(source)), title: url.lastPathComponent)
        case .text: page(textHTML(source), title: url.lastPathComponent)
        case .html: source
        }
        return PrompterDocument(url: url, kind: kind, html: html, modified: modificationDate(of: url))
    }

    /// 先按 UTF-8 读；不是的话多半是 Windows 上存的中文（GB18030）
    static func decode(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        let gb = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        return String(data: data, encoding: gb) ?? String(decoding: data, as: UTF8.self)
    }

    /// Obsidian 这类笔记开头的 YAML 属性（--- 包起来的一段）不显示
    static func stripFrontMatter(_ source: String) -> String {
        let lines = source.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return source }
        return lines[(end + 1)...].joined(separator: "\n")
    }

    /// 纯文本：空行分段，段里的换行保留
    static func textHTML(_ source: String) -> String {
        source.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .newlines) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { "<p>\(escape($0).replacingOccurrences(of: "\n", with: "<br>"))</p>" }
            .joined(separator: "\n")
    }

    static func page(_ body: String, title: String) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8"><title>\(escape(title))</title></head>
        <body><article class="tyto-doc">
        \(body)
        </article></body></html>
        """
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
