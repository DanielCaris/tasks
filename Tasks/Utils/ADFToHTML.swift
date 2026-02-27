import Foundation

/// Convierte documentos ADF (Atlassian Document Format) de Jira a HTML enriquecido.
/// Soporta: párrafos, negrita, cursiva, links, listas, tablas, code blocks, imágenes, etc.
enum ADFToHTML {
    /// Convierte un documento ADF (dict) a HTML. baseURL para media. attachmentMap: filename -> attachmentId (para imágenes).
    static func convert(adf: [String: Any], baseURL: String, attachmentMap: [String: String] = [:]) -> String {
        guard let content = adf["content"] as? [[String: Any]], !content.isEmpty else {
            return ""
        }
        let html = content.compactMap { nodeToHTML($0, baseURL: baseURL, attachmentMap: attachmentMap) }.joined(separator: "\n")
        return """
        <div class="adf-content" style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; font-size: 14px; line-height: 1.5; color: #333;">
        \(html)
        </div>
        """
    }

    private static func nodeToHTML(_ node: [String: Any], baseURL: String, attachmentMap: [String: String] = [:]) -> String? {
        guard let type = node["type"] as? String else { return nil }
        let content = node["content"] as? [[String: Any]] ?? []
        let attrs = node["attrs"] as? [String: Any] ?? [:]
        let marks = node["marks"] as? [[String: Any]] ?? []

        switch type {
        case "doc":
            return content.compactMap { nodeToHTML($0, baseURL: baseURL, attachmentMap: attachmentMap) }.joined(separator: "\n")

        case "paragraph":
            let inner = content.compactMap { inlineToHTML($0, baseURL: baseURL) }.joined()
            return "<p style='margin: 0 0 0.5em;'>\(inner.isEmpty ? "<br>" : inner)</p>"

        case "heading":
            let level = attrs["level"] as? Int ?? 1
            let tag = "h\(min(max(level, 1), 6))"
            let inner = content.compactMap { inlineToHTML($0, baseURL: baseURL) }.joined()
            return "<\(tag) style='margin: 0.75em 0 0.25em; font-size: \(headingSize(level))em;'>\(inner)</\(tag)>"

        case "bulletList":
            let items = content.compactMap { nodeToHTML($0, baseURL: baseURL, attachmentMap: attachmentMap) }.joined()
            return "<ul style='margin: 0.5em 0; padding-left: 1.5em;'>\(items)</ul>"

        case "orderedList":
            let items = content.compactMap { nodeToHTML($0, baseURL: baseURL, attachmentMap: attachmentMap) }.joined()
            return "<ol style='margin: 0.5em 0; padding-left: 1.5em;'>\(items)</ol>"

        case "listItem":
            let inner = content.compactMap { nodeToHTML($0, baseURL: baseURL, attachmentMap: attachmentMap) }.joined()
            return "<li style='margin: 0.25em 0;'>\(inner)</li>"

        case "blockquote":
            let inner = content.compactMap { nodeToHTML($0, baseURL: baseURL, attachmentMap: attachmentMap) }.joined()
            return "<blockquote style='margin: 0.5em 0; padding-left: 1em; border-left: 4px solid #ccc; color: #666;'>\(inner)</blockquote>"

        case "codeBlock":
            let lang = attrs["language"] as? String ?? ""
            let inner = content.compactMap { inlineToHTML($0, baseURL: baseURL) }.joined()
            let langAttr = lang.isEmpty ? "" : " data-language=\"\(escape(lang))\""
            return "<pre style='margin: 0.5em 0; padding: 12px; background: #f5f5f5; border-radius: 6px; overflow-x: auto; font-family: 'SF Mono', Monaco, monospace; font-size: 13px;'\(langAttr)><code>\(inner)</code></pre>"

        case "rule":
            return "<hr style='margin: 1em 0; border: none; border-top: 1px solid #ddd;'>"

        case "panel":
            let panelType = attrs["panelType"] as? String ?? "info"
            let bg = panelBackground(panelType)
            let inner = content.compactMap { nodeToHTML($0, baseURL: baseURL, attachmentMap: attachmentMap) }.joined()
            return "<div style='margin: 0.5em 0; padding: 12px; background: \(bg); border-radius: 6px;'>\(inner)</div>"

        case "table":
            let inner = content.compactMap { nodeToHTML($0, baseURL: baseURL, attachmentMap: attachmentMap) }.joined()
            return "<table style='border-collapse: collapse; width: 100%; margin: 0.5em 0;'><tbody>\(inner)</tbody></table>"

        case "tableRow":
            let cells = content.compactMap { nodeToHTML($0, baseURL: baseURL, attachmentMap: attachmentMap) }.joined()
            return "<tr>\(cells)</tr>"

        case "tableHeader", "tableCell":
            let cellTag = type == "tableHeader" ? "th" : "td"
            let inner = content.compactMap { nodeToHTML($0, baseURL: baseURL, attachmentMap: attachmentMap) }.joined()
            return "<\(cellTag) style='border: 1px solid #ddd; padding: 8px;'>\(inner)</\(cellTag)>"

        case "mediaSingle", "mediaGroup":
            let mediaHTML = content.compactMap { mediaToHTML($0, baseURL: baseURL, attachmentMap: attachmentMap) }.joined()
            return "<div style='margin: 0.5em 0;'>\(mediaHTML)</div>"

        case "media":
            return mediaToHTML(node, baseURL: baseURL, attachmentMap: attachmentMap)

        case "expand":
            let title = attrs["title"] as? String ?? ""
            let inner = content.compactMap { nodeToHTML($0, baseURL: baseURL, attachmentMap: attachmentMap) }.joined()
            return "<details style='margin: 0.5em 0;'><summary style='cursor: pointer; font-weight: 600;'>\(escape(title.isEmpty ? "▼" : title))</summary><div style='margin-top: 0.5em;'>\(inner)</div></details>"

        default:
            return content.compactMap { nodeToHTML($0, baseURL: baseURL, attachmentMap: attachmentMap) }.joined().isEmpty ? nil : content.compactMap { nodeToHTML($0, baseURL: baseURL, attachmentMap: attachmentMap) }.joined()
        }
    }

    private static func inlineToHTML(_ node: [String: Any], baseURL: String) -> String? {
        guard let type = node["type"] as? String else { return nil }
        let content = node["content"] as? [[String: Any]] ?? []
        let attrs = node["attrs"] as? [String: Any] ?? [:]
        let marks = node["marks"] as? [[String: Any]] ?? []
        let text = node["text"] as? String ?? ""

        func wrap(_ content: String, marks: [[String: Any]]) -> String {
            var result = content
            for mark in marks.reversed() {
                guard let mt = mark["type"] as? String else { continue }
                let mattrs = mark["attrs"] as? [String: Any] ?? [:]
                switch mt {
                case "strong": result = "<strong>\(result)</strong>"
                case "em": result = "<em>\(result)</em>"
                case "underline": result = "<u>\(result)</u>"
                case "strike": result = "<s>\(result)</s>"
                case "code": result = "<code style='background: #f0f0f0; padding: 2px 4px; border-radius: 3px; font-family: monospace; font-size: 0.9em;'>\(result)</code>"
                case "link":
                    let href = mattrs["href"] as? String ?? "#"
                    let title = mattrs["title"] as? String ?? ""
                    let t = title.isEmpty ? "" : " title=\"\(escape(title))\""
                    result = "<a href=\"\(escape(href))\"\(t) style='color: #0052CC;'>\(result)</a>"
                default: break
                }
            }
            return result
        }

        switch type {
        case "text":
            return text.isEmpty ? nil : wrap(escape(text), marks: marks)

        case "hardBreak":
            return "<br>"

        case "emoji":
            let shortName = attrs["shortName"] as? String ?? ""
            return shortName.isEmpty ? "" : "<span title=\"\(escape(shortName))\">\(escape(emojiFromShortName(shortName)))</span>"

        case "mention":
            let mentionText = attrs["text"] as? String ?? ""
            return mentionText.isEmpty ? "" : "<span style='background: #E3FCEF; padding: 1px 4px; border-radius: 3px;'>@\(escape(mentionText))</span>"

        case "date":
            let timestamp = attrs["timestamp"] as? String ?? ""
            return timestamp.isEmpty ? "" : "<span>\(escape(timestamp))</span>"

        case "inlineCard":
            let url = attrs["url"] as? String ?? ""
            return url.isEmpty ? "" : "<a href=\"\(escape(url))\" style='color: #0052CC;'>\(escape(url))</a>"

        default:
            return content.compactMap { inlineToHTML($0, baseURL: baseURL) }.joined()
        }
    }

    private static func mediaToHTML(_ node: [String: Any], baseURL: String, attachmentMap: [String: String] = [:]) -> String? {
        let attrs = node["attrs"] as? [String: Any] ?? [:]
        let marks = node["marks"] as? [[String: Any]] ?? []
        let mediaId = attrs["id"] as? String ?? ""
        let mediaType = attrs["type"] as? String ?? "file"
        let alt = attrs["alt"] as? String ?? "imagen"
        // Jira ADF media usa UUID; el API espera id numérico. Mapeamos por filename (alt), case-insensitive.
        let attachmentId = attachmentMap[alt.lowercased()] ?? attachmentMap[alt] ?? mediaId
        let width = attrs["width"] as? Int ?? 400
        let height = attrs["height"] as? Int ?? 300

        var href: String?
        for m in marks {
            if (m["type"] as? String) == "link", let a = m["attrs"] as? [String: Any], let h = a["href"] as? String {
                href = h
                break
            }
        }

        // Para type "link" a veces hay URL en attrs; para "file" usamos el endpoint de Jira (requiere auth en navegador)
        let imgURL: String
        if mediaType == "link", let url = attrs["url"] as? String ?? href {
            imgURL = url
        } else if !mediaId.isEmpty {
            let base = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            imgURL = "\(base)/rest/api/3/attachment/content/\(mediaId)"
        } else {
            return nil
        }

        // type "link": URL externa. type "file": jira-image:// con attachmentId real (mapeado por filename)
        let imgSrc: String
        if mediaType == "link", let url = attrs["url"] as? String ?? href, url.hasPrefix("http") {
            imgSrc = url
        } else if !attachmentId.isEmpty {
            imgSrc = "jira-image://\(attachmentId)"
        } else if !mediaId.isEmpty {
            // Fallback: probar con mediaId por si coincide con attachment id
            imgSrc = "jira-image://\(mediaId)"
        } else {
            return nil
        }
        let linkWrap = href != nil ? "<a href=\"\(escape(href!))\" target=\"_blank\">" : ""
        let linkEnd = href != nil ? "</a>" : ""
        let browseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(linkWrap)<img src=\"\(escape(imgSrc))\" alt=\"\(escape(alt))\" width=\"\(min(width, 600))\" style='max-width:100%;height:auto;border-radius:4px;' data-fallback=\"\(escape(browseURL))\" />\(linkEnd)"
    }

    private static func taskBrowseURL(baseURL: String) -> String {
        baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func headingSize(_ level: Int) -> Double {
        switch level {
        case 1: return 1.25
        case 2: return 1.1
        case 3: return 1.0
        default: return 0.9
        }
    }

    private static func panelBackground(_ type: String) -> String {
        switch type {
        case "info": return "#deebff"
        case "note": return "#eae6ff"
        case "success": return "#d3fcef"
        case "warning": return "#fffae6"
        case "error": return "#ffebe6"
        default: return "#f4f5f7"
        }
    }

    private static func emojiFromShortName(_ name: String) -> String {
        let map: [String: String] = [
            ":smile:": "😊", ":sad:": "😢", ":+1:": "👍", ":-1:": "👎", ":heart:": "❤️",
            ":check:": "✅", ":x:": "❌", ":warning:": "⚠️", ":bulb:": "💡"
        ]
        return map[name] ?? name
    }

    private static func escape(_ s: String) -> String {
        s
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
