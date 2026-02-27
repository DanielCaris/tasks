import Foundation

/// Protocolo base para proveedores de issues (Jira, Linear, etc.)
protocol IssueProviderProtocol {
    static var providerId: String { get }
    func fetchIssues() async throws -> [IssueDTO]
}
