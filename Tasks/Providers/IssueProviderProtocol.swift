import Foundation

/// Opción de transición de status (p. ej. para cambiar de "To Do" a "In Progress").
struct TransitionOption: Identifiable {
    let id: String
    let targetStatusName: String
}

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
    /// Transiciones de status disponibles para un issue. Retorna vacío si no se soporta.
    func getTransitions(externalId: String) async throws -> [TransitionOption]
    /// Ejecuta una transición (cambio de status) en el proveedor remoto.
    func transitionIssue(externalId: String, transitionId: String) async throws
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

    func getTransitions(externalId: String) async throws -> [TransitionOption] {
        []
    }

    func transitionIssue(externalId: String, transitionId: String) async throws {
        // No-op por defecto
    }
}
