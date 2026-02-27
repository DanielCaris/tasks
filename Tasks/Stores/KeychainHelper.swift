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

    static func saveJQL(_ jql: String) {
        suite.set(jql, forKey: prefix + "jql")
    }

    static func loadJQL() -> String? {
        suite.string(forKey: prefix + "jql")
    }
}
