import Foundation
import SwiftData

/// Modelo unificado para tareas, identificado por providerId + externalId.
/// Almacena datos del issue remoto más priorización local (urgencia, impacto, esfuerzo).
@Model
final class TaskItem {
    @Attribute(.unique) var taskId: String  // "providerId:externalId"
    var providerId: String
    var externalId: String
    var title: String
    var status: String
    var assignee: String?
    var descriptionText: String?
    var descriptionHTML: String?  // Contenido enriquecido (imágenes, links, formato) desde Jira ADF
    var urlString: String?
    var priority: String?
    var urgency: Int?
    var impact: Int?
    var effort: Int?
    var lastSyncedAt: Date?

    init(
        providerId: String,
        externalId: String,
        title: String,
        status: String,
        assignee: String? = nil,
        description: String? = nil,
        descriptionHTML: String? = nil,
        url: URL? = nil,
        priority: String? = nil,
        urgency: Int? = nil,
        impact: Int? = nil,
        effort: Int? = nil
    ) {
        self.taskId = "\(providerId):\(externalId)"
        self.providerId = providerId
        self.externalId = externalId
        self.title = title
        self.status = status
        self.assignee = assignee
        self.descriptionText = description
        self.descriptionHTML = descriptionHTML
        self.urlString = url?.absoluteString
        self.priority = priority
        self.urgency = urgency
        self.impact = impact
        self.effort = effort
        self.lastSyncedAt = Date()
    }

    var url: URL? {
        get { urlString.flatMap { URL(string: $0) } }
        set { urlString = newValue?.absoluteString }
    }

    /// Score de prioridad: (Urgencia × Impacto) / Esfuerzo. Mayor = más prioritario.
    var priorityScore: Double {
        let u = Double(urgency ?? 1)
        let i = Double(impact ?? 1)
        let e = Double(max(effort ?? 1, 1))
        return (u * i) / e
    }
}
