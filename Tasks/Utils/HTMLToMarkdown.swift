import Foundation

/// Convierte HTML simple a Markdown como fallback cuando no hay ADF.
/// Extrae enlaces, imágenes y texto básico.
enum HTMLToMarkdown {
    static func convert(_ html: String) -> String {
        var result = html

        // Procesar imágenes ANTES que enlaces (pueden estar dentro de <a>)
        // <img src="url" alt="alt" ...> - extraer src y alt
        let imgPattern = #"<img[^>]+src\s*=\s*["']([^"']+)["'][^>]*(?:alt\s*=\s*["']([^"']*)["'])?[^>]*>"#
        result = replace(pattern: imgPattern, in: result) { match in
            let src = match[1]
            let alt = match.count > 2 ? match[2] : ""
            let altText = alt.isEmpty ? "image" : alt
            if src.hasPrefix("http") || src.hasPrefix("https") {
                return "![\(altText)](\(src))"
            }
            return "![\(altText)]"
        }

        // <a href="url">text</a> -> [text](url)
        let linkPattern = #"<a\s+[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)</a>"#
        result = replace(pattern: linkPattern, in: result) { match in
            let url = match[1]
            let text = stripTags(match[2])
            return "[\(text)](\(url))"
        }

        // <p>...</p> -> texto + doble newline
        result = result.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
        result = result.replacingOccurrences(of: "<p[^>]*>", with: "", options: .regularExpression)

        // <br> -> newline
        result = result.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)

        // <strong>, <b> -> **text**
        result = replaceTagPair(result, open: "strong", close: "strong") { "**\($0)**" }
        result = replaceTagPair(result, open: "b", close: "b") { "**\($0)**" }

        // <em>, <i> -> *text*
        result = replaceTagPair(result, open: "em", close: "em") { "*\($0)*" }
        result = replaceTagPair(result, open: "i", close: "i") { "*\($0)*" }

        // <code> -> `text`
        result = replaceTagPair(result, open: "code", close: "code") { "`\($0)`" }

        // Resto: quitar tags
        result = stripTags(result)

        // Limpiar espacios y líneas vacías múltiples
        result = result
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        result = result.replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripTags(_ s: String) -> String {
        var result = s
        while let start = result.range(of: "<", options: .literal),
              let end = result.range(of: ">", options: .literal, range: start.upperBound..<result.endIndex) {
            result.removeSubrange(start.lowerBound..<end.upperBound)
        }
        return result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }

    private static func replace(pattern: String, in string: String, transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return string
        }
        var result = string
        let range = NSRange(result.startIndex..<result.endIndex, in: result)
        let matches = regex.matches(in: result, options: [], range: range)
        for match in matches.reversed() {
            var groups: [String] = []
            for i in 0..<match.numberOfRanges {
                if let r = Range(match.range(at: i), in: result) {
                    groups.append(String(result[r]))
                } else {
                    groups.append("")
                }
            }
            let replacement = transform(groups)
            if let r = Range(match.range(at: 0), in: result) {
                result.replaceSubrange(r, with: replacement)
            }
        }
        return result
    }

    private static func replaceTagPair(_ string: String, open: String, close: String, transform: (String) -> String) -> String {
        let pattern = "<\(open)[^>]*>([\\s\\S]*?)</\(close)>"
        return replace(pattern: pattern, in: string) { match in
            transform(stripTags(match[1]))
        }
    }
}
