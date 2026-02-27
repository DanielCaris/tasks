import Foundation

/// Implementación del protocolo IssueProvider para Jira Cloud.
final class JiraProvider: IssueProviderProtocol {
    static let providerId = "jira"

    private let baseURL: String
    private let email: String
    private let apiToken: String
    private let jql: String

    init(baseURL: String, email: String, apiToken: String, jql: String = "assignee = currentUser() AND status != Done ORDER BY updated DESC") {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.email = email
        self.apiToken = apiToken
        self.jql = jql
    }

    func fetchIssues() async throws -> [IssueDTO] {
        guard let url = buildSearchURL() else {
            throw JiraError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let credentials = "\(email):\(apiToken)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            throw JiraError.invalidCredentials
        }
        let base64Credentials = credentialsData.base64EncodedString()
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw JiraError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorBody = String(data: data, encoding: .utf8) {
                throw JiraError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
            }
            throw JiraError.apiError(statusCode: httpResponse.statusCode, message: "Unknown error")
        }

        return try parseSearchResponse(data: data)
    }

    private func buildSearchURL() -> URL? {
        var components = URLComponents(string: "\(baseURL)/rest/api/3/search")
        components?.queryItems = [
            URLQueryItem(name: "jql", value: jql),
            URLQueryItem(name: "maxResults", value: "100"),
            URLQueryItem(name: "fields", value: "summary,status,priority,assignee,created,updated")
        ]
        return components?.url
    }

    private func parseSearchResponse(data: Data) throws -> [IssueDTO] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) { return date }
            // Jira sometimes uses +0000 without colon
            let fixed = dateString.replacingOccurrences(of: "+0000", with: "+00:00")
                .replacingOccurrences(of: "-0000", with: "-00:00")
            if let date = formatter.date(from: fixed) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(dateString)")
        }

        let response = try decoder.decode(JiraSearchResponse.self, from: data)
        return response.issues.map { issue in
            let assigneeName = issue.fields.assignee?.displayName
            let url = URL(string: "\(baseURL)/browse/\(issue.key)")
            let createdAt = issue.fields.created
            let updatedAt = issue.fields.updated
            return IssueDTO(
                externalId: issue.key,
                title: issue.fields.summary,
                status: issue.fields.status.name,
                assignee: assigneeName,
                url: url,
                priority: issue.fields.priority?.name,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }
}

// MARK: - Jira API Response Models

private struct JiraSearchResponse: Decodable {
    let issues: [JiraIssue]
}

private struct JiraIssue: Decodable {
    let key: String
    let fields: JiraIssueFields
}

private struct JiraIssueFields: Decodable {
    let summary: String
    let status: JiraStatus
    let priority: JiraPriority?
    let assignee: JiraUser?
    let created: Date?
    let updated: Date?
}

private struct JiraStatus: Decodable {
    let name: String
}

private struct JiraPriority: Decodable {
    let name: String
}

private struct JiraUser: Decodable {
    let displayName: String?
}

// MARK: - Errors

enum JiraError: LocalizedError {
    case invalidURL
    case invalidCredentials
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL de Jira inválida"
        case .invalidCredentials: return "Credenciales inválidas"
        case .invalidResponse: return "Respuesta inválida del servidor"
        case .apiError(let code, let msg): return "Jira API error (\(code)): \(msg)"
        }
    }
}
