import Foundation

/// Protocolo base para proveedores de issues (Jira, Linear, etc.)
protocol IssueProviderProtocol {
    static var providerId: String { get }
    func fetchIssues() async throws -> [IssueDTO]
    /// Actualiza título y/o descripción en el proveedor remoto. Opcional: no todos los proveedores soportan edición.
    func updateIssue(externalId: String, title: String?, description: String?) async throws
}

extension IssueProviderProtocol {
    func updateIssue(externalId: String, title: String?, description: String?) async throws {
        // Implementación por defecto: no hacer nada (proveedores sin soporte de edición)
    }
}
