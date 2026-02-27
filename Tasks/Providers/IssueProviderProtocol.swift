import Foundation

/// Protocolo base para proveedores de issues (Jira, Linear, etc.)
protocol IssueProviderProtocol {
    static var providerId: String { get }
    func fetchIssues() async throws -> [IssueDTO]
    /// Actualiza título y/o descripción en el proveedor remoto. Opcional: no todos los proveedores soportan edición.
    func updateIssue(externalId: String, title: String?, description: String?) async throws
    /// Crea un nuevo issue. Retorna el IssueDTO del issue creado.
    func createIssue(projectKey: String, title: String, description: String?) async throws -> IssueDTO
    /// Lista proyectos disponibles para crear issues.
    func fetchProjects() async throws -> [ProjectOption]
}

extension IssueProviderProtocol {
    func updateIssue(externalId: String, title: String?, description: String?) async throws {
        // Implementación por defecto: no hacer nada (proveedores sin soporte de edición)
    }

    func createIssue(projectKey: String, title: String, description: String?) async throws -> IssueDTO {
        fatalError("Este proveedor no soporta crear issues")
    }

    func fetchProjects() async throws -> [ProjectOption] {
        []
    }
}
