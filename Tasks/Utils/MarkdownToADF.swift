import Foundation

/// Convierte Markdown a Atlassian Document Format (ADF) para Jira.
/// Soporta: headings, negrita, cursiva, links, code inline/block, listas, blockquotes, reglas.
enum MarkdownToADF {
    /// Convierte una cadena Markdown a documento ADF.
    static func convert(_ markdown: String) -> [String: Any] {
        let lines = markdown.components(separatedBy: "\n")
        var content: [[String: Any]] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Línea vacía → omitir (no crear párrafos vacíos que añaden líneas extra al guardar)
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Heading: # ## ### etc.
            if let level = parseHeadingLevel(trimmed) {
                let (text, _) = parseInline(trimmed.dropFirst(level).trimmingCharacters(in: .whitespaces))
                content.append([
                    "type": "heading",
                    "attrs": ["level": level],
                    "content": text
                ])
                i += 1
                continue
            }

            // Horizontal rule: ---, ***, ___
            if isHorizontalRule(trimmed) {
                content.append(["type": "rule"])
                i += 1
                continue
            }

            // Block-level image: ![alt](url) -> párrafo con enlace (Jira puede rechazar media sin collection)
            if let (alt, imgUrl) = parseBlockImage(trimmed), !imgUrl.isEmpty, imgUrl.hasPrefix("http") {
                content.append([
                    "type": "paragraph",
                    "content": [
                        ["type": "text", "text": alt, "marks": [["type": "link", "attrs": ["href": imgUrl]]]]
                    ]
                ])
                i += 1
                continue
            }

            // Blockquote: > ...
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count {
                    let q = lines[i].trimmingCharacters(in: .whitespaces)
                    guard q.hasPrefix(">") else { break }
                    let inner = q.dropFirst().trimmingCharacters(in: .whitespaces)
                    quoteLines.append(String(inner))
                    i += 1
                }
                let quoteMarkdown = quoteLines.joined(separator: "\n")
                let quoteContent = convert(quoteMarkdown)["content"] as? [[String: Any]] ?? []
                content.append(["type": "blockquote", "content": quoteContent])
                continue
            }

            // Fenced code block: ``` or ```
            if trimmed.hasPrefix("```") {
                let lang = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                if i < lines.count { i += 1 } // skip closing ```
                let code = codeLines.joined(separator: "\n")
                content.append([
                    "type": "codeBlock",
                    "attrs": ["language": lang],
                    "content": [["type": "text", "text": code]]
                ])
                continue
            }

            // Bullet list: - item or * item
            if let bullet = parseBullet(trimmed) {
                var items: [[String: Any]] = []
                while i < lines.count {
                    let l = lines[i]
                    let t = l.trimmingCharacters(in: .whitespaces)
                    guard let b = parseBullet(t), b == bullet else { break }
                    let itemText = t.dropFirst(b).trimmingCharacters(in: .whitespaces)
                    let (inlineContent, _) = parseInline(itemText)
                    items.append([
                        "type": "listItem",
                        "content": [["type": "paragraph", "content": inlineContent]]
                    ])
                    i += 1
                }
                content.append(["type": "bulletList", "content": items])
                continue
            }

            // Ordered list: 1. item
            if let _ = parseOrderedListMarker(trimmed) {
                var items: [[String: Any]] = []
                while i < lines.count {
                    let l = lines[i]
                    let t = l.trimmingCharacters(in: .whitespaces)
                    guard let after = parseOrderedListMarker(t) else { break }
                    let (inlineContent, _) = parseInline(after)
                    items.append([
                        "type": "listItem",
                        "content": [["type": "paragraph", "content": inlineContent]]
                    ])
                    i += 1
                }
                content.append(["type": "orderedList", "content": items])
                continue
            }

            // Paragraph: collect until blank line or block start (skip lines that are only images)
            var paraLines: [String] = []
            var j = i
            while j < lines.count {
                let l = lines[j]
                let t = l.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { break }
                if parseHeadingLevel(t) != nil { break }
                if isHorizontalRule(t) { break }
                if t.hasPrefix(">") { break }
                if t.hasPrefix("```") { break }
                if parseBullet(t) != nil { break }
                if parseOrderedListMarker(t) != nil { break }
                if parseBlockImage(t) != nil { break }
                paraLines.append(t)
                j += 1
            }
            i = j
            if paraLines.isEmpty {
                i += 1
                continue
            }
            let paraText = paraLines.joined(separator: " ")
            let (inlineContent, _) = parseInline(paraText)
            content.append(["type": "paragraph", "content": inlineContent])
        }

        if content.isEmpty {
            content = [["type": "paragraph", "content": [] as [[String: Any]]]]
        }

        return [
            "type": "doc",
            "version": 1,
            "content": content
        ]
    }

    private static func parseHeadingLevel(_ s: String) -> Int? {
        var i = s.startIndex
        var count = 0
        while i < s.endIndex, s[i] == "#", count < 6 {
            count += 1
            i = s.index(after: i)
        }
        guard count >= 1, count <= 6 else { return nil }
        guard i == s.endIndex || s[i] == " " || s[i] == "\t" else { return nil }
        return count
    }

    private static func isHorizontalRule(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count >= 3 else { return false }
        let c = t.first!
        return (c == "-" || c == "*" || c == "_") && t.allSatisfy { $0 == c }
    }

    private static func parseBullet(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("- ") { return 2 }
        if t.hasPrefix("* ") { return 2 }
        if t.hasPrefix("+ ") { return 2 }
        return nil
    }

    private static func parseBlockImage(_ s: String) -> (String, String)? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("![") else { return nil }
        guard let (alt, url, _) = parseImage(t, from: t.startIndex) else { return nil }
        return (alt, url)
    }

    private static func parseOrderedListMarker(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        var i = t.startIndex
        while i < t.endIndex, t[i].isNumber {
            i = t.index(after: i)
        }
        guard i > t.startIndex else { return nil }
        guard i < t.endIndex, (t[i] == "." || t[i] == ")"), t.index(after: i) <= t.endIndex else { return nil }
        let after = t.index(after: i)
        guard after < t.endIndex, t[after] == " " else { return nil }
        return String(t[t.index(after: after)...])
    }

    /// Parsea un string con inline Markdown y devuelve array de nodos ADF.
    private static func parseInline(_ s: String) -> ([[String: Any]], String.Index) {
        var result: [[String: Any]] = []
        var i = s.startIndex

        while i < s.endIndex {
            // Link: [text](url)
            if s[i] == "[", let end = s.index(i, offsetBy: 1, limitedBy: s.endIndex), end < s.endIndex {
                if let (linkText, url, after) = parseLink(s, from: i) {
                    result.append([
                        "type": "text",
                        "text": linkText,
                        "marks": [["type": "link", "attrs": ["href": url]]]
                    ])
                    i = after
                    continue
                }
            }

            // Image: ![alt](url) - convertimos a enlace (mediaInline/media pueden ser rechazados por Jira)
            if i < s.endIndex, s[i] == "!", let next = s.index(i, offsetBy: 1, limitedBy: s.endIndex), next < s.endIndex, s[next] == "[" {
                if let (alt, url, after) = parseImage(s, from: i) {
                    result.append([
                        "type": "text",
                        "text": "[\(alt)](\(url))",
                        "marks": [["type": "link", "attrs": ["href": url]]]
                    ])
                    i = after
                    continue
                }
            }

            // Inline code: `...`
            if s[i] == "`" {
                if let (code, after) = parseInlineCode(s, from: i) {
                    result.append([
                        "type": "text",
                        "text": code,
                        "marks": [["type": "code"]]
                    ])
                    i = after
                    continue
                }
            }

            // Bold: **text** or __text__
            if s[i] == "*", let next = s.index(i, offsetBy: 1, limitedBy: s.endIndex), next < s.endIndex, s[next] == "*" {
                if let (bold, after) = parseDelimited(s, from: s.index(after: next), open: "**", close: "**") {
                    result.append([
                        "type": "text",
                        "text": bold,
                        "marks": [["type": "strong"]]
                    ])
                    i = after
                    continue
                }
            }
            if s[i] == "_", let next = s.index(i, offsetBy: 1, limitedBy: s.endIndex), next < s.endIndex, s[next] == "_" {
                if let (bold, after) = parseDelimited(s, from: s.index(after: next), open: "__", close: "__") {
                    result.append([
                        "type": "text",
                        "text": bold,
                        "marks": [["type": "strong"]]
                    ])
                    i = after
                    continue
                }
            }

            // Italic: *text* or _text_
            if s[i] == "*" {
                if let (em, after) = parseDelimited(s, from: s.index(after: i), open: "*", close: "*") {
                    result.append([
                        "type": "text",
                        "text": em,
                        "marks": [["type": "em"]]
                    ])
                    i = after
                    continue
                }
            }
            if s[i] == "_" {
                if let (em, after) = parseDelimited(s, from: s.index(after: i), open: "_", close: "_") {
                    result.append([
                        "type": "text",
                        "text": em,
                        "marks": [["type": "em"]]
                    ])
                    i = after
                    continue
                }
            }

            // Plain text (o carácter especial que falló al parsear → consumir como texto para evitar bucle infinito)
            let next = nextSpecialIndex(s, from: i)
            if next == i {
                result.append(["type": "text", "text": String(s[i])])
                i = s.index(after: i)
            } else {
                let plain = String(s[i..<next])
                if !plain.isEmpty {
                    result.append(["type": "text", "text": plain])
                }
                i = next
            }
        }

        return (result, i)
    }

    private static func parseLink(_ s: String, from start: String.Index) -> (String, String, String.Index)? {
        guard s[start] == "[" else { return nil }
        var i = s.index(after: start)
        var text = ""
        while i < s.endIndex, s[i] != "]" {
            if s[i] == "\\" { i = s.index(after: i) }
            if i < s.endIndex, s[i] != "]" { text.append(s[i]) }
            i = s.index(after: i)
        }
        guard i < s.endIndex, s[i] == "]" else { return nil }
        i = s.index(after: i)
        guard i < s.endIndex, s[i] == "(" else { return nil }
        i = s.index(after: i)
        var url = ""
        while i < s.endIndex, s[i] != ")" {
            if s[i] == "\\" { i = s.index(after: i) }
            if i < s.endIndex, s[i] != ")" { url.append(s[i]) }
            i = s.index(after: i)
        }
        guard i < s.endIndex, s[i] == ")" else { return nil }
        return (text, url, s.index(after: i))
    }

    private static func parseImage(_ s: String, from start: String.Index) -> (String, String, String.Index)? {
        guard start < s.endIndex, s[start] == "!", let next = s.index(start, offsetBy: 1, limitedBy: s.endIndex), next < s.endIndex, s[next] == "[" else { return nil }
        guard let (alt, url, after) = parseLink(s, from: next) else { return nil }
        return (alt, url, after)
    }

    private static func parseInlineCode(_ s: String, from start: String.Index) -> (String, String.Index)? {
        guard start < s.endIndex, s[start] == "`" else { return nil }
        var i = s.index(after: start)
        var code = ""
        while i < s.endIndex, s[i] != "`" {
            code.append(s[i])
            i = s.index(after: i)
        }
        guard i < s.endIndex, s[i] == "`" else { return nil }
        return (code, s.index(after: i))
    }

    private static func parseDelimited(_ s: String, from start: String.Index, open: String, close: String) -> (String, String.Index)? {
        var i = start
        var result = ""
        while i < s.endIndex {
            if let end = s.range(of: close, range: i..<s.endIndex) {
                result = String(s[i..<end.lowerBound])
                return (result, end.upperBound)
            }
            result.append(s[i])
            i = s.index(after: i)
        }
        return nil
    }

    private static func nextSpecialIndex(_ s: String, from start: String.Index) -> String.Index {
        var i = start
        while i < s.endIndex {
            let c = s[i]
            if c == "[" || c == "`" || c == "*" || c == "_" || c == "!" { return i }
            i = s.index(after: i)
        }
        return i
    }
}
