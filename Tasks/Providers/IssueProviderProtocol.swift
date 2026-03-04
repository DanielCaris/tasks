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
    /// Obtiene un solo issue por ID. Retorna nil si el proveedor no lo soporta.
    func fetchIssue(externalId: String) async throws -> IssueDTO?
    /// Actualiza título y/o descripción en el proveedor remoto. description puede ser String (markdown) o ADF dict.
    /// Retorna el ADF enviado para descripción (para almacenar localmente) o nil.
    func updateIssue(externalId: String, title: String?, description: Any?) async throws -> [String: Any]?
    /// Crea un nuevo issue. Retorna el IssueDTO del issue creado.
    func createIssue(projectKey: String, title: String, description: String?) async throws -> IssueDTO
    /// Crea una subtarea bajo un issue padre. Retorna el IssueDTO de la subtarea creada. nil si no soportado.
    func createSubtask(parentExternalId: String, title: String, description: String?) async throws -> IssueDTO?
    /// Crea una tarea bajo una épica (Epic Link). Retorna el IssueDTO. nil si no soportado.
    func createTaskUnderEpic(epicKey: String, title: String, description: String?) async throws -> IssueDTO?
    /// Lista proyectos disponibles para crear issues.
    func fetchProjects() async throws -> [ProjectOption]
    /// Transiciones de status disponibles para un issue. Retorna vacío si no se soporta.
    func getTransitions(externalId: String) async throws -> [TransitionOption]
    /// Ejecuta una transición (cambio de status) en el proveedor remoto.
    func transitionIssue(externalId: String, transitionId: String) async throws
    /// Elimina un issue en el proveedor remoto. Retorna true si se eliminó. nil/false si no soportado.
    func deleteIssue(externalId: String) async throws -> Bool
}

extension IssueProviderProtocol {
    func fetchIssue(externalId: String) async throws -> IssueDTO? {
        nil
    }

    func updateIssue(externalId: String, title: String?, description: Any?) async throws -> [String: Any]? {
        // Implementación por defecto: no hacer nada (proveedores sin soporte de edición)
        return nil
    }

    func createIssue(projectKey: String, title: String, description: String?) async throws -> IssueDTO {
        fatalError("Este proveedor no soporta crear issues")
    }

    func createSubtask(parentExternalId: String, title: String, description: String?) async throws -> IssueDTO? {
        nil
    }

    func createTaskUnderEpic(epicKey: String, title: String, description: String?) async throws -> IssueDTO? {
        nil
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

    func deleteIssue(externalId: String) async throws -> Bool {
        false
    }
}
