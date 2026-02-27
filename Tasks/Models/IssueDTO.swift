import Foundation

/// DTO genérico para mapear issues desde cualquier provider (Jira, Linear, etc.)
struct IssueDTO: Identifiable {
    let externalId: String
    let title: String
    let status: String
    let assignee: String?
    let description: String?
    let url: URL?
    let priority: String?
    let createdAt: Date?
    let updatedAt: Date?

    var id: String { externalId }

    init(
        externalId: String,
        title: String,
        status: String,
        assignee: String? = nil,
        description: String? = nil,
        url: URL? = nil,
        priority: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.externalId = externalId
        self.title = title
        self.status = status
        self.assignee = assignee
        self.description = description
        self.url = url
        self.priority = priority
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
