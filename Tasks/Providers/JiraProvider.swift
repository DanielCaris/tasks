import Foundation

/// Implementación del protocolo IssueProvider para Jira Cloud.
final class JiraProvider: IssueProviderProtocol {
    static let providerId = "jira"

    private let baseURL: String
    private let email: String
    private let apiToken: String
    private let jql: String

    init(baseURL: String, email: String, apiToken: String, jql: String = "assignee = currentUser() ORDER BY updated DESC") {
        var url = baseURL.trimmingCharacters(in: .whitespaces)
        url = url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "https://" + url
        }
        self.baseURL = url
        self.email = email.trimmingCharacters(in: .whitespaces)
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
            let message = parseJiraError(data: data, statusCode: httpResponse.statusCode)
            throw JiraError.apiError(statusCode: httpResponse.statusCode, message: message)
        }

        return try parseSearchResponse(data: data)
    }

    func fetchProjects() async throws -> [ProjectOption] {
        guard let url = URL(string: "\(baseURL)/rest/api/3/project") else {
            throw JiraError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let credentials = "\(email):\(apiToken)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            throw JiraError.invalidCredentials
        }
        request.setValue("Basic \(credentialsData.base64EncodedString())", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw JiraError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = parseJiraError(data: data, statusCode: httpResponse.statusCode)
            throw JiraError.apiError(statusCode: httpResponse.statusCode, message: message)
        }

        struct JiraProject: Decodable {
            let key: String
            let name: String
        }
        let projects = try JSONDecoder().decode([JiraProject].self, from: data)
        return projects.map { ProjectOption(key: $0.key, name: $0.name) }
    }

    func updateIssue(externalId: String, title: String?, description: String?) async throws {
        guard let url = URL(string: "\(baseURL)/rest/api/3/issue/\(externalId)") else {
            throw JiraError.invalidURL
        }

        var fields: [String: Any] = [:]
        if let title { fields["summary"] = title }
        if let description { fields["description"] = plainTextToADF(description) }

        guard !fields.isEmpty else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let credentials = "\(email):\(apiToken)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            throw JiraError.invalidCredentials
        }
        request.setValue("Basic \(credentialsData.base64EncodedString())", forHTTPHeaderField: "Authorization")

        request.httpBody = try JSONSerialization.data(withJSONObject: ["fields": fields])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw JiraError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = parseJiraError(data: data, statusCode: httpResponse.statusCode)
            throw JiraError.apiError(statusCode: httpResponse.statusCode, message: message)
        }
    }

    func getTransitions(externalId: String) async throws -> [TransitionOption] {
        guard let url = URL(string: "\(baseURL)/rest/api/3/issue/\(externalId)/transitions") else {
            throw JiraError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let credentials = "\(email):\(apiToken)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            throw JiraError.invalidCredentials
        }
        request.setValue("Basic \(credentialsData.base64EncodedString())", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw JiraError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = parseJiraError(data: data, statusCode: httpResponse.statusCode)
            throw JiraError.apiError(statusCode: httpResponse.statusCode, message: message)
        }

        struct TransitionsResponse: Decodable {
            let transitions: [JiraTransition]
        }
        struct JiraTransition: Decodable {
            let id: String
            let name: String
            let to: JiraTransitionTo

            enum CodingKeys: String, CodingKey { case id, name, to }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                if let intId = try? c.decode(Int.self, forKey: .id) {
                    id = String(intId)
                } else {
                    id = try c.decode(String.self, forKey: .id)
                }
                name = try c.decode(String.self, forKey: .name)
                to = try c.decode(JiraTransitionTo.self, forKey: .to)
            }
        }
        struct JiraTransitionTo: Decodable {
            let name: String
        }

        let decoder = JSONDecoder()
        let res = try decoder.decode(TransitionsResponse.self, from: data)
        return res.transitions.map { TransitionOption(id: $0.id, targetStatusName: $0.to.name) }
    }

    func transitionIssue(externalId: String, transitionId: String) async throws {
        guard let url = URL(string: "\(baseURL)/rest/api/3/issue/\(externalId)/transitions") else {
            throw JiraError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let credentials = "\(email):\(apiToken)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            throw JiraError.invalidCredentials
        }
        request.setValue("Basic \(credentialsData.base64EncodedString())", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = ["transition": ["id": transitionId]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw JiraError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = parseJiraError(data: data, statusCode: httpResponse.statusCode)
            throw JiraError.apiError(statusCode: httpResponse.statusCode, message: message)
        }
    }

    func createIssue(projectKey: String, title: String, description: String?) async throws -> IssueDTO {
        guard let url = URL(string: "\(baseURL)/rest/api/3/issue") else {
            throw JiraError.invalidURL
        }

        var fields: [String: Any] = [
            "project": ["key": projectKey.uppercased()],
            "summary": title,
            "issuetype": ["name": "Task"]
        ]
        if let description, !description.isEmpty {
            fields["description"] = plainTextToADF(description)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let credentials = "\(email):\(apiToken)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            throw JiraError.invalidCredentials
        }
        request.setValue("Basic \(credentialsData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["fields": fields])

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw JiraError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = parseJiraError(data: data, statusCode: httpResponse.statusCode)
            throw JiraError.apiError(statusCode: httpResponse.statusCode, message: message)
        }

        struct CreateResponse: Decodable {
            let key: String
        }
        let createResponse = try JSONDecoder().decode(CreateResponse.self, from: data)
        return try await fetchIssue(issueKey: createResponse.key)
    }

    private func fetchIssue(issueKey: String) async throws -> IssueDTO {
        guard let url = URL(string: "\(baseURL)/rest/api/3/issue/\(issueKey)") else {
            throw JiraError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let credentials = "\(email):\(apiToken)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            throw JiraError.invalidCredentials
        }
        request.setValue("Basic \(credentialsData.base64EncodedString())", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw JiraError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = parseJiraError(data: data, statusCode: httpResponse.statusCode)
            throw JiraError.apiError(statusCode: httpResponse.statusCode, message: message)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: dateString) { return date }
            let fixed = dateString.replacingOccurrences(of: "+0000", with: "+00:00")
                .replacingOccurrences(of: "-0000", with: "-00:00")
            if let date = formatter.date(from: fixed) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(dateString)")
        }
        let issue = try decoder.decode(JiraIssue.self, from: data)
        let assigneeName = issue.fields.assignee?.displayName
        let browseURL = URL(string: "\(baseURL)/browse/\(issue.key)")
        let descriptionText = issue.fields.description?.plainText
        return IssueDTO(
            externalId: issue.key,
            title: issue.fields.summary,
            status: issue.fields.status.name,
            assignee: assigneeName,
            description: descriptionText?.isEmpty == false ? descriptionText : nil,
            url: browseURL,
            priority: issue.fields.priority?.name,
            createdAt: issue.fields.created,
            updatedAt: issue.fields.updated
        )
    }

    /// Convierte texto plano a Atlassian Document Format para la descripción de Jira.
    private func plainTextToADF(_ text: String) -> [String: Any] {
        let paragraphs = text.components(separatedBy: .newlines)
        let content: [[String: Any]] = paragraphs.map { line in
            [
                "type": "paragraph",
                "content": [["type": "text", "text": line]]
            ]
        }
        return [
            "type": "doc",
            "version": 1,
            "content": content.isEmpty ? [["type": "paragraph", "content": []]] : content
        ]
    }

    private func buildSearchURL() -> URL? {
        // Usar el nuevo endpoint /search/jql (el antiguo /search devuelve 410 Gone)
        var components = URLComponents(string: "\(baseURL)/rest/api/3/search/jql")
        components?.queryItems = [
            URLQueryItem(name: "jql", value: jql),
            URLQueryItem(name: "maxResults", value: "100"),
            URLQueryItem(name: "fields", value: "summary,description,status,priority,assignee,created,updated")
        ]
        return components?.url
    }

    private func parseJiraError(data: Data, statusCode: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let messages = json["errorMessages"] as? [String], !messages.isEmpty {
                return messages.joined(separator: ". ")
            }
            if let errors = json["errors"] as? [String: String], !errors.isEmpty {
                return errors.map { "\($0.key): \($0.value)" }.joined(separator: ". ")
            }
        }
        if let raw = String(data: data, encoding: .utf8), raw.count < 500 {
            return raw
        }
        switch statusCode {
        case 401: return "No autorizado. Verifica que el email y el API token sean correctos. Genera un nuevo token en: https://id.atlassian.com/manage-profile/security/api-tokens"
        case 403: return "Acceso denegado. El token puede estar expirado o revocado."
        case 404: return "URL no encontrada. Verifica que la URL sea correcta (ej: https://tu-empresa.atlassian.net)"
        default: return "Error \(statusCode)"
        }
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

        // Soportar "issues" (legacy) y "values" (nuevo endpoint)
        let issues: [JiraIssue]
        if let response = try? decoder.decode(JiraSearchResponse.self, from: data) {
            issues = response.issues
        } else if let response = try? decoder.decode(JiraSearchResponseValues.self, from: data) {
            issues = response.values
        } else {
            throw JiraError.invalidResponse
        }
        return issues.map { issue in
            let assigneeName = issue.fields.assignee?.displayName
            let url = URL(string: "\(baseURL)/browse/\(issue.key)")
            let createdAt = issue.fields.created
            let updatedAt = issue.fields.updated
            let descriptionText = issue.fields.description?.plainText
            return IssueDTO(
                externalId: issue.key,
                title: issue.fields.summary,
                status: issue.fields.status.name,
                assignee: assigneeName,
                description: descriptionText?.isEmpty == false ? descriptionText : nil,
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

private struct JiraSearchResponseValues: Decodable {
    let values: [JiraIssue]
}

private struct JiraIssue: Decodable {
    let key: String
    let fields: JiraIssueFields
}

private struct JiraIssueFields: Decodable {
    let summary: String
    let description: JiraDescription?
    let status: JiraStatus
    let priority: JiraPriority?
    let assignee: JiraUser?
    let created: Date?
    let updated: Date?
}

/// Descripción en ADF (Atlassian Document Format). Se decodifica como JSON genérico para extraer texto.
private struct JiraDescription: Decodable {
    let raw: Any?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        raw = (try? container.decode(AnyCodable.self))?.value
    }

    var plainText: String {
        guard let dict = raw as? [String: Any],
              let content = dict["content"] as? [[String: Any]] else { return "" }
        return content.compactMap { extractText(from: $0) }.joined(separator: "\n")
    }

    private func extractText(from node: [String: Any]) -> String? {
        if let text = node["text"] as? String { return text }
        guard let children = node["content"] as? [[String: Any]] else { return nil }
        return children.compactMap { extractText(from: $0) }.joined()
    }
}

private struct AnyCodable: Decodable {
    let value: Any
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let v = try? container.decode(String.self) { value = v }
        else if let v = try? container.decode(Double.self) { value = v }
        else if let v = try? container.decode(Bool.self) { value = v }
        else if let v = try? container.decode([AnyCodable].self) { value = v.map { $0.value } }
        else if let v = try? container.decode([String: AnyCodable].self) { value = v.mapValues { $0.value } }
        else { value = NSNull() }
    }
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
        case .invalidResponse: return "Formato de respuesta de Jira no reconocido"
        case .apiError(let code, let msg): return "Jira API error (\(code)): \(msg)"
        }
    }
}
