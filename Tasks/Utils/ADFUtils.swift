import Foundation

/// Utilidades para manipular documentos ADF.
enum ADFUtils {
    /// Alterna el estado (TODO↔DONE) del task item en el índice dado. Los índices son planos: 0, 1, 2... para cada taskItem/blockTaskItem en orden.
    /// Retorna el ADF modificado o nil si no se encontró el índice.
    static func toggleTaskItem(at index: Int, in adf: [String: Any]) -> [String: Any]? {
        guard var content = adf["content"] as? [[String: Any]] else { return nil }
        var currentIndex = 0
        if let newContent = toggleTaskItemInContent(content: &content, targetIndex: index, currentIndex: &currentIndex) {
            var result = adf
            result["content"] = newContent
            return result
        }
        return nil
    }

    private static func toggleTaskItemInContent(content: inout [[String: Any]], targetIndex: Int, currentIndex: inout Int) -> [[String: Any]]? {
        for i in content.indices {
            let node = content[i]
            guard let type = node["type"] as? String else { continue }
            if type == "taskItem" || type == "blockTaskItem" {
                if currentIndex == targetIndex {
                    var attrs = (node["attrs"] as? [String: Any]) ?? [:]
                    let state = attrs["state"] as? String ?? "TODO"
                    attrs["state"] = state == "DONE" ? "TODO" : "DONE"
                    var newNode = node
                    newNode["attrs"] = attrs
                    content[i] = newNode
                    return content
                }
                currentIndex += 1
            } else if let childContent = node["content"] as? [[String: Any]] {
                var childContentCopy = childContent
                if let updated = toggleTaskItemInContent(content: &childContentCopy, targetIndex: targetIndex, currentIndex: &currentIndex) {
                    var newNode = node
                    newNode["content"] = updated
                    content[i] = newNode
                    return content
                }
            }
        }
        return nil
    }
}
