import XCTest
@testable import Tasks

/// Tests para MarkdownToADF según test-description-markdown.md y el plan de rendering.
/// Cubre todos los elementos de Markdown soportados.
final class MarkdownToADFTests: XCTestCase {

    // MARK: - Headings H1-H6

    func testHeadingH1_producesHeadingNode() {
        let md = "# Título principal"
        let adf = MarkdownToADF.convert(md)
        let content = adf["content"] as? [[String: Any]] ?? []
        let node = content.first { ($0["type"] as? String) == "heading" }
        XCTAssertNotNil(node)
        let attrs = node?["attrs"] as? [String: Any] ?? [:]
        XCTAssertEqual(attrs["level"] as? Int, 1)
    }

    func testHeadingH6_producesHeadingNode() {
        let md = "###### Título H6"
        let adf = MarkdownToADF.convert(md)
        let content = adf["content"] as? [[String: Any]] ?? []
        let node = content.first { ($0["type"] as? String) == "heading" }
        let attrs = node?["attrs"] as? [String: Any] ?? [:]
        XCTAssertEqual(attrs["level"] as? Int, 6)
    }

    // MARK: - Negrita y cursiva

    func testBoldAsterisks_producesStrongMark() {
        let md = "**negrita**"
        let adf = MarkdownToADF.convert(md)
        let (text, marks) = firstTextWithMarks(in: adf)
        XCTAssertEqual(text, "negrita")
        XCTAssertTrue(marks.contains("strong"))
    }

    func testBoldUnderscores_producesStrongMark() {
        let md = "__negrita__"
        let adf = MarkdownToADF.convert(md)
        let (text, marks) = firstTextWithMarks(in: adf)
        XCTAssertEqual(text, "negrita")
        XCTAssertTrue(marks.contains("strong"))
    }

    func testItalicAsterisk_producesEmMark() {
        let md = "*cursiva*"
        let adf = MarkdownToADF.convert(md)
        let (text, marks) = firstTextWithMarks(in: adf)
        XCTAssertEqual(text, "cursiva")
        XCTAssertTrue(marks.contains("em"))
    }

    func testItalicUnderscore_producesEmMark() {
        let md = "_cursiva_"
        let adf = MarkdownToADF.convert(md)
        let (text, marks) = firstTextWithMarks(in: adf)
        XCTAssertEqual(text, "cursiva")
        XCTAssertTrue(marks.contains("em"))
    }

    // MARK: - Código inline y enlaces

    func testInlineCode_producesCodeMark() {
        let md = "`código inline`"
        let adf = MarkdownToADF.convert(md)
        let (text, marks) = firstTextWithMarks(in: adf)
        XCTAssertEqual(text, "código inline")
        XCTAssertTrue(marks.contains("code"))
    }

    func testLink_producesLinkMark() {
        let md = "[Documentación](https://example.com)"
        let adf = MarkdownToADF.convert(md)
        let content = adf["content"] as? [[String: Any]] ?? []
        let para = content.first { ($0["type"] as? String) == "paragraph" }
        let textNode = (para?["content"] as? [[String: Any]])?.first { ($0["type"] as? String) == "text" }
        let marks = textNode?["marks"] as? [[String: Any]] ?? []
        let linkMark = marks.first { ($0["type"] as? String) == "link" }
        XCTAssertNotNil(linkMark)
        let linkAttrs = linkMark?["attrs"] as? [String: Any] ?? [:]
        XCTAssertEqual(linkAttrs["href"] as? String, "https://example.com")
    }

    // MARK: - Listas

    func testBulletList_producesBulletList() {
        let md = """
        - Primer elemento
        - Segundo elemento
        """
        let adf = MarkdownToADF.convert(md)
        let content = adf["content"] as? [[String: Any]] ?? []
        let node = content.first { ($0["type"] as? String) == "bulletList" }
        XCTAssertNotNil(node)
        let items = node?["content"] as? [[String: Any]] ?? []
        XCTAssertEqual(items.count, 2)
    }

    func testOrderedList_producesOrderedList() {
        let md = """
        1. Primer paso
        2. Segundo paso
        """
        let adf = MarkdownToADF.convert(md)
        let content = adf["content"] as? [[String: Any]] ?? []
        let node = content.first { ($0["type"] as? String) == "orderedList" }
        XCTAssertNotNil(node)
        let items = node?["content"] as? [[String: Any]] ?? []
        XCTAssertEqual(items.count, 2)
    }

    func testTaskList_producesTaskList() {
        let md = """
        - [ ] Tarea pendiente
        - [x] Tarea completada
        """
        let adf = MarkdownToADF.convert(md)
        let content = adf["content"] as? [[String: Any]] ?? []
        let node = content.first { ($0["type"] as? String) == "taskList" }
        XCTAssertNotNil(node)
        let items = node?["content"] as? [[String: Any]] ?? []
        XCTAssertEqual(items.count, 2)
        let firstState = (items[0]["attrs"] as? [String: Any])?["state"] as? String
        let secondState = (items[1]["attrs"] as? [String: Any])?["state"] as? String
        XCTAssertEqual(firstState, "TODO")
        XCTAssertEqual(secondState, "DONE")
    }

    // MARK: - Blockquote

    func testBlockquote_producesBlockquoteNode() {
        let md = "> Esta es una cita"
        let adf = MarkdownToADF.convert(md)
        let content = adf["content"] as? [[String: Any]] ?? []
        let node = content.first { ($0["type"] as? String) == "blockquote" }
        XCTAssertNotNil(node)
    }

    // MARK: - Bloques de código

    func testCodeBlock_producesCodeBlockNode() {
        let md = """
        ```swift
        let x = 42
        ```
        """
        let adf = MarkdownToADF.convert(md)
        let content = adf["content"] as? [[String: Any]] ?? []
        let node = content.first { ($0["type"] as? String) == "codeBlock" }
        XCTAssertNotNil(node)
        let attrs = node?["attrs"] as? [String: Any] ?? [:]
        XCTAssertEqual(attrs["language"] as? String, "swift")
    }

    // MARK: - Reglas horizontales (---, ***, ___)

    func testHorizontalRule_underscores_producesRuleNode() {
        let md = "___"
        let adf = MarkdownToADF.convert(md)
        let content = adf["content"] as? [[String: Any]] ?? []
        XCTAssertEqual(content[0]["type"] as? String, "rule")
    }

    func testHorizontalRule_asterisks_producesRuleNode() {
        let md = "***"
        let adf = MarkdownToADF.convert(md)
        let content = adf["content"] as? [[String: Any]] ?? []
        XCTAssertEqual(content[0]["type"] as? String, "rule")
    }

    // MARK: - 1. Imágenes de bloque ![alt](httpUrl) → mediaSingle con media type link

    func testBlockImageWithHttpUrl_producesMediaSingle() {
        let md = "![Logo de ejemplo](https://example.com/image.png)"
        let adf = MarkdownToADF.convert(md)
        let content = adf["content"] as? [[String: Any]] ?? []
        XCTAssertEqual(content.count, 1, "Debe haber un solo nodo")
        let node = content[0]
        XCTAssertEqual(node["type"] as? String, "mediaSingle")
        let inner = node["content"] as? [[String: Any]] ?? []
        XCTAssertEqual(inner.count, 1)
        let media = inner[0]
        XCTAssertEqual(media["type"] as? String, "media")
        let attrs = media["attrs"] as? [String: Any] ?? [:]
        XCTAssertEqual(attrs["type"] as? String, "link")
        XCTAssertEqual(attrs["url"] as? String, "https://example.com/image.png")
        XCTAssertEqual(attrs["alt"] as? String, "Logo de ejemplo")
    }

    func testBlockImageWithHttpsUrl_producesMediaSingle() {
        let md = "![Alt](https://atlassian.com/logo.png)"
        let adf = MarkdownToADF.convert(md)
        let content = adf["content"] as? [[String: Any]] ?? []
        XCTAssertEqual(content[0]["type"] as? String, "mediaSingle")
    }

    // MARK: - 2. Negrita + cursiva ***text*** y ___text___

    func testBoldItalicAsterisks_producesStrongAndEmMarks() {
        let md = "***negrita y cursiva***"
        let adf = MarkdownToADF.convert(md)
        let content = adf["content"] as? [[String: Any]] ?? []
        let para = content.first { ($0["type"] as? String) == "paragraph" }
        XCTAssertNotNil(para)
        let paraContent = para?["content"] as? [[String: Any]] ?? []
        let textNode = paraContent.first { ($0["type"] as? String) == "text" }
        XCTAssertNotNil(textNode)
        let marks = textNode?["marks"] as? [[String: Any]] ?? []
        let markTypes = Set(marks.compactMap { $0["type"] as? String })
        XCTAssertTrue(markTypes.contains("strong"), "Debe tener mark strong")
        XCTAssertTrue(markTypes.contains("em"), "Debe tener mark em")
        XCTAssertEqual(textNode?["text"] as? String, "negrita y cursiva")
    }

    func testBoldItalicUnderscores_producesStrongAndEmMarks() {
        let md = "___todo combinado___"
        let adf = MarkdownToADF.convert(md)
        let content = adf["content"] as? [[String: Any]] ?? []
        let para = content.first { ($0["type"] as? String) == "paragraph" }
        let paraContent = para?["content"] as? [[String: Any]] ?? []
        let textNode = paraContent.first { ($0["type"] as? String) == "text" }
        let marks = textNode?["marks"] as? [[String: Any]] ?? []
        let markTypes = Set(marks.compactMap { $0["type"] as? String })
        XCTAssertTrue(markTypes.contains("strong"))
        XCTAssertTrue(markTypes.contains("em"))
        XCTAssertEqual(textNode?["text"] as? String, "todo combinado")
    }

    // MARK: - 3. Strikethrough ~~text~~

    func testStrikethrough_producesStrikeMark() {
        let md = "Texto ~~tachado~~ normal"
        let adf = MarkdownToADF.convert(md)
        let content = adf["content"] as? [[String: Any]] ?? []
        let para = content.first { ($0["type"] as? String) == "paragraph" }
        let paraContent = para?["content"] as? [[String: Any]] ?? []
        let strikeNode = paraContent.first { node in
            guard (node["type"] as? String) == "text" else { return false }
            let marks = node["marks"] as? [[String: Any]] ?? []
            return marks.contains { ($0["type"] as? String) == "strike" }
        }
        XCTAssertNotNil(strikeNode)
        XCTAssertEqual(strikeNode?["text"] as? String, "tachado")
    }

    // MARK: - Round-trip: ADF → Markdown → ADF

    func testBlockImageRoundTrip_preservesStructure() {
        let md = "![Logo](https://example.com/img.png)"
        let adf = MarkdownToADF.convert(md)
        let backToMd = ADFToMarkdown.convert(adf: adf)
        XCTAssertTrue(backToMd.contains("![Logo]"))
        XCTAssertTrue(backToMd.contains("https://example.com/img.png"))
    }

    func testBoldItalicRoundTrip_preservesFormatting() {
        let md = "***texto***"
        let adf = MarkdownToADF.convert(md)
        let backToMd = ADFToMarkdown.convert(adf: adf)
        XCTAssertTrue(backToMd.contains("***texto***"), "Round-trip debe preservar ***texto***")
    }

    func testStrikethroughRoundTrip_preservesFormatting() {
        let md = "~~tachado~~"
        let adf = MarkdownToADF.convert(md)
        let backToMd = ADFToMarkdown.convert(adf: adf)
        XCTAssertTrue(backToMd.contains("~~tachado~~"))
    }

    // MARK: - Reglas horizontales (ya corregidas)

    func testHorizontalRule_producesRuleNode() {
        let md = "---"
        let adf = MarkdownToADF.convert(md)
        let content = adf["content"] as? [[String: Any]] ?? []
        XCTAssertEqual(content.count, 1)
        XCTAssertEqual(content[0]["type"] as? String, "rule")
    }

    // MARK: - Blockquote con lista anidada

    func testBlockquoteWithNestedList_producesNestedStructure() {
        let md = """
        > Cita con lista:
        > - Item uno
        > - Item dos
        """
        let adf = MarkdownToADF.convert(md)
        let content = adf["content"] as? [[String: Any]] ?? []
        let blockquote = content.first { ($0["type"] as? String) == "blockquote" }
        XCTAssertNotNil(blockquote)
        let inner = blockquote?["content"] as? [[String: Any]] ?? []
        let bulletList = inner.first { ($0["type"] as? String) == "bulletList" }
        XCTAssertNotNil(bulletList)
    }

    // MARK: - Helpers

    private func firstTextWithMarks(in adf: [String: Any]) -> (text: String, marks: Set<String>) {
        let content = adf["content"] as? [[String: Any]] ?? []
        let para = content.first { ($0["type"] as? String) == "paragraph" }
        let textNode = (para?["content"] as? [[String: Any]])?.first { ($0["type"] as? String) == "text" }
        let text = textNode?["text"] as? String ?? ""
        let marks = Set((textNode?["marks"] as? [[String: Any]] ?? []).compactMap { $0["type"] as? String })
        return (text, marks)
    }
}
