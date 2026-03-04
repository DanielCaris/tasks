import Foundation

/// Opción de proyecto para crear issues (clave + nombre).
struct ProjectOption: Identifiable {
    let key: String
    let name: String
    var id: String { key }
}

/// Opción de board para seleccionar de qué equipo/board cargar sprints.
struct BoardOption: Identifiable {
    let id: Int
    let name: String
}

/// Opción de sprint para asignar a un issue.
struct SprintOption: Identifiable {
    let id: Int
    let name: String
    let state: String?  // "active", "closed", "future"
}

/// DTO genérico para mapear issues desde cualquier provider (Jira, Linear, etc.)
struct IssueDTO: Identifiable {
    let externalId: String
    let title: String
    let status: String
    let assignee: String?
    let description: String?
    let descriptionHTML: String?  // Contenido enriquecido desde Jira ADF (imágenes, links, etc.)
    let descriptionADFJSON: String?  // ADF crudo para edición Markdown bidireccional
    let parentExternalId: String?  // Si es subtarea, clave del issue padre
    let url: URL?
    let priority: String?
    let issueType: String?  // "Epic", "Task", "Story", "Sub-task", etc.
    let createdAt: Date?
    let updatedAt: Date?
    let labels: [String]?
    let sprint: String?

    var id: String { externalId }

    init(
        externalId: String,
        title: String,
        status: String,
        assignee: String? = nil,
        description: String? = nil,
        descriptionHTML: String? = nil,
        descriptionADFJSON: String? = nil,
        parentExternalId: String? = nil,
        url: URL? = nil,
        priority: String? = nil,
        issueType: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        labels: [String]? = nil,
        sprint: String? = nil
    ) {
        self.externalId = externalId
        self.title = title
        self.status = status
        self.assignee = assignee
        self.description = description
        self.descriptionHTML = descriptionHTML
        self.descriptionADFJSON = descriptionADFJSON
        self.parentExternalId = parentExternalId
        self.url = url
        self.priority = priority
        self.issueType = issueType
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.labels = labels
        self.sprint = sprint
    }
}
