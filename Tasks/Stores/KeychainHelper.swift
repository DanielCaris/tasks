import Foundation

/// Almacena credenciales en UserDefaults para evitar los prompts repetidos de Keychain.
/// Para mayor seguridad en producción, considera volver a Keychain con la app firmada.
enum KeychainHelper {
    private static let suite = UserDefaults.standard
    private static let prefix = "com.tasks.jira."

    static func save(key: String, value: String, service: String = "jira") {
        suite.set(value, forKey: prefix + key)
        // Mantener compatibilidad con clave legacy
        if key == "jira_url" {
            suite.set(value, forKey: "jira_url")
        }
    }

    static func load(key: String, service: String = "jira") -> String? {
        suite.string(forKey: prefix + key)
            ?? (key == "jira_url" ? suite.string(forKey: "jira_url") : nil)
    }

    static func delete(key: String, service: String = "jira") {
        suite.removeObject(forKey: prefix + key)
        if key == "jira_url" {
            suite.removeObject(forKey: "jira_url")
        }
    }

    static func saveStatusFilters(_ filters: [String]) {
        suite.set(filters, forKey: prefix + "status_filters")
    }

    static func loadStatusFilters() -> [String] {
        suite.stringArray(forKey: prefix + "status_filters") ?? []
    }

    static func saveSubtaskStatusExclusions(_ exclusions: [String]) {
        suite.set(exclusions, forKey: prefix + "subtask_status_exclusions")
    }

    static func loadSubtaskStatusExclusions() -> [String] {
        suite.stringArray(forKey: prefix + "subtask_status_exclusions") ?? []
    }

    static func saveJQL(_ jql: String) {
        suite.set(jql, forKey: prefix + "jql")
    }

    static func loadJQL() -> String? {
        suite.string(forKey: prefix + "jql")
    }

    static func saveCurrentUserDisplayName(_ name: String) {
        suite.set(name, forKey: prefix + "current_user_display_name")
    }

    static func loadCurrentUserDisplayName() -> String? {
        suite.string(forKey: prefix + "current_user_display_name")
    }

    static func deleteCurrentUserDisplayName() {
        suite.removeObject(forKey: prefix + "current_user_display_name")
    }

    /// Orden de estados por proyecto (para subtareas). Clave: projectKey, valor: [status] ordenados.
    private static let statusOrdersKey = prefix + "status_orders"

    static func saveStatusOrder(projectKey: String, order: [String]) {
        var dict = loadAllStatusOrders()
        dict[projectKey] = order
        suite.set(dict, forKey: statusOrdersKey)
    }

    static func loadStatusOrder(projectKey: String) -> [String] {
        loadAllStatusOrders()[projectKey] ?? []
    }

    private static func loadAllStatusOrders() -> [String: [String]] {
        suite.dictionary(forKey: statusOrdersKey) as? [String: [String]] ?? [:]
    }

    /// Colores por estado (clave: nombre del status, valor: hex RRGGBB).
    private static let statusColorsKey = prefix + "status_colors"

    /// Colores por defecto para estados comunes de Jira (inglés y español).
    static let defaultStatusColors: [String: String] = [
        "To Do": "5C6BC0",
        "Por hacer": "5C6BC0",
        "Open": "5C6BC0",
        "Abierto": "5C6BC0",
        "In Progress": "F9A825",
        "En progreso": "F9A825",
        "In Development": "F9A825",
        "Done": "43A047",
        "Hecho": "43A047",
        "Resolved": "43A047",
        "Resuelto": "43A047",
        "Closed": "43A047",
        "Cerrado": "43A047",
        "Blocked": "E53935",
        "Bloqueado": "E53935",
        "Cancelled": "757575",
        "Canceled": "757575",
        "Cancelado": "757575",
        "Review": "7E57C2",
        "Revisión": "7E57C2",
        "In Review": "7E57C2",
        "Code Review": "7E57C2",
        "Testing": "26C6DA",
        "QA": "26C6DA",
    ]

    static func saveStatusColors(_ colors: [String: String]) {
        suite.set(colors, forKey: statusColorsKey)
    }

    static func loadStatusColors() -> [String: String] {
        suite.dictionary(forKey: statusColorsKey) as? [String: String] ?? [:]
    }

    /// Color efectivo para un estado: primero el guardado por el usuario, luego el por defecto, luego gris.
    static func statusColorHex(for status: String) -> String {
        let saved = loadStatusColors()[status]
        if let hex = saved, !hex.isEmpty { return hex }
        return defaultStatusColors[status] ?? "808080"
    }
}
