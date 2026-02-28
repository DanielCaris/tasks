import Foundation

/// Convierte documentos ADF (Atlassian Document Format) a Markdown.
/// Soporta: párrafos, headings, negrita, cursiva, links, listas, blockquotes, code blocks, reglas.
enum ADFToMarkdown {
    /// Convierte un documento ADF (dict) a Markdown.
    static func convert(adf: [String: Any]) -> String {
        guard let content = adf["content"] as? [[String: Any]], !content.isEmpty else {
            return ""
        }
        return content.compactMap { nodeToMarkdown($0) }.joined(separator: "\n\n")
    }

    private static func nodeToMarkdown(_ node: [String: Any]) -> String? {
        guard let type = node["type"] as? String else { return nil }
        let content = node["content"] as? [[String: Any]] ?? []
        let attrs = node["attrs"] as? [String: Any] ?? [:]

        switch type {
        case "doc":
            return content.compactMap { nodeToMarkdown($0) }.joined(separator: "\n\n")

        case "paragraph":
            let inner = content.compactMap { inlineToMarkdown($0) }.joined()
            return inner.isEmpty ? nil : inner

        case "heading":
            let level = attrs["level"] as? Int ?? 1
            let hashes = String(repeating: "#", count: min(max(level, 1), 6))
            let inner = content.compactMap { inlineToMarkdown($0) }.joined()
            return "\(hashes) \(inner)"

        case "bulletList":
            return content.compactMap { listItemToMarkdown($0, prefix: "-") }.joined(separator: "\n")

        case "orderedList":
            var items: [String] = []
            for (idx, item) in content.enumerated() {
                if let md = listItemToMarkdown(item, prefix: "\(idx + 1).") {
                    items.append(md)
                }
            }
            return items.joined(separator: "\n")

        case "listItem":
            let inner = content.compactMap { nodeToMarkdown($0) }.joined(separator: "\n")
            return inner

        case "blockquote":
            let inner = content.compactMap { nodeToMarkdown($0) }.joined(separator: "\n\n")
            return inner.split(separator: "\n").map { "> \($0)" }.joined(separator: "\n")

        case "codeBlock":
            let lang = attrs["language"] as? String ?? ""
            let inner = content.compactMap { inlineToMarkdown($0) }.joined()
            let fence = "```"
            return lang.isEmpty ? "\(fence)\n\(inner)\n\(fence)" : "\(fence)\(lang)\n\(inner)\n\(fence)"

        case "rule":
            return "---"

        case "panel", "expand":
            let inner = content.compactMap { nodeToMarkdown($0) }.joined(separator: "\n\n")
            return inner

        case "table":
            return tableToMarkdown(content: content)

        case "mediaSingle", "mediaGroup":
            return content.compactMap { mediaToMarkdown($0) }.joined(separator: "\n")

        case "media":
            return mediaToMarkdown(node)

        default:
            return content.compactMap { nodeToMarkdown($0) }.joined(separator: "\n\n")
        }
    }

    private static func listItemToMarkdown(_ node: [String: Any], prefix: String) -> String? {
        guard node["type"] as? String == "listItem" else { return nil }
        let content = node["content"] as? [[String: Any]] ?? []
        let inner = content.compactMap { nodeToMarkdown($0) }.joined(separator: "\n")
        return inner.split(separator: "\n").enumerated().map { i, line in
            i == 0 ? "\(prefix) \(line)" : "  \(line)"
        }.joined(separator: "\n")
    }

    private static func inlineToMarkdown(_ node: [String: Any]) -> String? {
        guard let type = node["type"] as? String else { return nil }
        let content = node["content"] as? [[String: Any]] ?? []
        let attrs = node["attrs"] as? [String: Any] ?? [:]
        let marks = node["marks"] as? [[String: Any]] ?? []
        let text = node["text"] as? String ?? ""

        func wrap(_ s: String, marks: [[String: Any]]) -> String {
            var result = s
            for mark in marks.reversed() {
                guard let mt = mark["type"] as? String else { continue }
                let mattrs = mark["attrs"] as? [String: Any] ?? [:]
                switch mt {
                case "strong": result = "**\(result)**"
                case "em": result = "*\(result)*"
                case "underline": break
                case "strike": result = "~~\(result)~~"
                case "code": result = "`\(result)`"
                case "link":
                    let href = mattrs["href"] as? String ?? ""
                    result = "[\(result)](\(href))"
                default: break
                }
            }
            return result
        }

        switch type {
        case "text":
            return text.isEmpty ? nil : wrap(escapeMarkdown(text), marks: marks)

        case "hardBreak":
            return "\n"

        case "emoji":
            let shortName = attrs["shortName"] as? String ?? ""
            return shortName.isEmpty ? "" : shortName

        case "mention":
            let mentionText = attrs["text"] as? String ?? ""
            return mentionText.isEmpty ? "" : "@\(mentionText)"

        case "inlineCard":
            let url = attrs["url"] as? String ?? ""
            return url.isEmpty ? "" : "[\(escapeMarkdown(url))](\(url))"

        default:
            return content.compactMap { inlineToMarkdown($0) }.joined()
        }
    }

    private static func mediaToMarkdown(_ node: [String: Any]) -> String? {
        let attrs = node["attrs"] as? [String: Any] ?? [:]
        let marks = node["marks"] as? [[String: Any]] ?? []
        let alt = attrs["alt"] as? String ?? "image"
        let mediaType = attrs["type"] as? String ?? "file"
        var url = attrs["url"] as? String ?? ""
        if url.isEmpty, mediaType == "link" {
            if let href = marks.first(where: { ($0["type"] as? String) == "link" })
                .flatMap({ $0["attrs"] as? [String: Any] })
                .flatMap({ $0["href"] as? String }) {
                url = href
            }
        }
        var href: String?
        for m in marks {
            if (m["type"] as? String) == "link", let a = m["attrs"] as? [String: Any], let h = a["href"] as? String {
                href = h
                break
            }
        }
        let imgMarkdown = (!url.isEmpty && (url.hasPrefix("http") || url.hasPrefix("https")))
            ? "![\(escapeMarkdown(alt))](\(url))"
            : "![\(escapeMarkdown(alt))]"
        if let h = href, !h.isEmpty {
            return "[\(imgMarkdown)](\(h))"
        }
        return imgMarkdown
    }

    private static func tableToMarkdown(content: [[String: Any]]) -> String {
        var rows: [[String]] = []
        for rowNode in content {
            guard (rowNode["type"] as? String) != nil else { continue }
            let cells = rowNode["content"] as? [[String: Any]] ?? []
            let cellTexts = cells.compactMap { cellNode -> String? in
                let inner = (cellNode["content"] as? [[String: Any]])?.compactMap { inlineToMarkdown($0) }.joined() ?? ""
                return inner.isEmpty ? nil : inner
            }
            if !cellTexts.isEmpty {
                rows.append(cellTexts.map { $0.replacingOccurrences(of: "|", with: "\\|") })
            }
        }
        guard !rows.isEmpty else { return "" }
        let colCount = rows.map(\.count).max() ?? 0
        guard colCount > 0 else { return "" }
        let padded = rows.map { r -> [String] in
            var a = r
            while a.count < colCount { a.append("") }
            return a
        }
        let header = padded[0].joined(separator: " | ")
        let separator = (0..<colCount).map { _ in "---" }.joined(separator: " | ")
        let body = padded.dropFirst().map { $0.joined(separator: " | ") }
        return ([header, separator] + body).joined(separator: "\n")
    }

    private static func escapeMarkdown(_ s: String) -> String {
        s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }
}
