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

        return try await parseSearchResponse(data: data)
    }

    /// Obtiene las subtareas de un issue padre.
    func fetchSubtasks(parentKey: String) async throws -> [IssueDTO] {
        guard let url = buildSubtasksURL(parentKey: parentKey) else {
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
        return try await parseSearchResponse(data: data, parentKey: parentKey)
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
        guard let url = URL(string: "\(baseURL)/rest/api/3/issue/\(issueKey)?fields=summary,description,status,priority,assignee,created,updated,attachment") else {
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
        let desc = issue.fields.description
        let descriptionText = desc?.plainText
        let attachments = issue.fields.attachment ?? []
        let attachmentMap = buildAttachmentMap(attachments: attachments)
        let imageIds = imageAttachmentIdsInOrder(attachments: attachments)
        let mediaIdToSignedURL = await buildMediaIdToSignedURLMap(attachments: attachments)
        let descriptionHTML = desc?.adfDict.flatMap { ADFToHTML.convert(adf: $0, baseURL: baseURL, attachmentMap: attachmentMap, imageAttachmentIdsInOrder: imageIds, mediaIdToSignedURL: mediaIdToSignedURL) }
        return IssueDTO(
            externalId: issue.key,
            title: issue.fields.summary,
            status: issue.fields.status.name,
            assignee: assigneeName,
            description: descriptionText?.isEmpty == false ? descriptionText : nil,
            descriptionHTML: descriptionHTML?.isEmpty == false ? descriptionHTML : nil,
            parentExternalId: nil,
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

    /// Mapa filename (minúsculas) -> attachmentId para resolver imágenes ADF.
    /// Jira usa UUID en media nodes; el API de attachment/content requiere el ID numérico.
    /// Añadimos claves alternativas porque: 1) media.alt puede estar vacío al pegar imágenes,
    /// 2) Jira nombra "image-YYYYMMDD-HHMMSS.png" pero alt puede ser "image" o "image.png".
    private func buildAttachmentMap(attachments: [JiraAttachment]) -> [String: String] {
        var map: [String: String] = [:]
        for a in attachments where a.filename.map({ !$0.isEmpty }) ?? false {
            let filename = (a.filename ?? "").lowercased()
            if map[filename] == nil { map[filename] = a.id }
            // Quitar patrón -YYYYMMDD-HHMMSS típico de Jira al pegar imágenes
            let stem = filename.replacingOccurrences(of: #"-\d{8}-\d{6}\."#, with: ".", options: .regularExpression)
            if stem != filename, map[stem] == nil { map[stem] = a.id }
        }
        return map
    }

    /// IDs de attachments de imagen en orden, para resolver media nodes con alt vacío (imágenes pegadas).
    private func imageAttachmentIdsInOrder(attachments: [JiraAttachment]) -> [String] {
        let imageExts = ["png", "jpg", "jpeg", "gif", "webp", "svg", "heic", "bmp", "tiff"]
        return attachments.compactMap { a in
            guard let f = a.filename?.lowercased() else { return nil }
            return imageExts.contains(where: { f.hasSuffix(".\($0)") }) ? a.id : nil
        }
    }

    /// Mapeo UUID (Media Services ID) → URL firmada del CDN.
    /// GET /attachment/content/{id} devuelve 303 con Location: .../file/{UUID}/binary?token=...
    /// Usamos la URL firmada directamente como img src (no requiere auth).
    private func buildMediaIdToSignedURLMap(attachments: [JiraAttachment]) async -> [String: String] {
        guard !attachments.isEmpty else { return [:] }
        var result: [String: String] = [:]
        for att in attachments {
            let signedURL: String? = await fetchAttachmentRedirectURL(attachmentId: att.id)
            guard let url = signedURL, let uuid = Self.extractUUIDFromLocation(url) else { continue }
            result[uuid] = url
        }
        return result
    }

    /// Obtiene la URL del redirect (303) usando curl. Credenciales en archivo temporal (0600)
    /// para evitar exponer el token en argumentos del proceso (visible en ps).
    private func fetchAttachmentRedirectURL(attachmentId: String) async -> String? {
        let contentURL = "\(baseURL)/rest/api/3/attachment/content/\(attachmentId)"
        let configDir = FileManager.default.temporaryDirectory
        let configPath = configDir.appendingPathComponent("curl-\(UUID().uuidString).conf")
        let configContent = "user = \"\(email.replacingOccurrences(of: "\"", with: "\\\"")):\(apiToken.replacingOccurrences(of: "\"", with: "\\\""))\"\n"
        defer { try? FileManager.default.removeItem(at: configPath) }
        do {
            try configContent.write(to: configPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configPath.path)
        } catch {
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = ["-s", "-D", "-", "-o", "/dev/null", "-K", configPath.path, contentURL]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let location = output.split(separator: "\n").first { $0.lowercased().hasPrefix("location:") }
                    .map { String($0.dropFirst(9)).trimmingCharacters(in: .whitespaces) }
                continuation.resume(returning: location.flatMap { URL(string: $0) != nil ? $0 : nil })
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    private static func extractUUIDFromLocation(_ location: String) -> String? {
        guard let range = location.range(of: "/file/") else { return nil }
        let after = location[range.upperBound...]
        guard let end = after.firstIndex(of: "/") else { return nil }
        let uuid = String(after[..<end])
        let pattern = #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#
        return uuid.range(of: pattern, options: .regularExpression) != nil ? uuid : nil
    }

    private func buildSearchURL() -> URL? {
        var components = URLComponents(string: "\(baseURL)/rest/api/3/search/jql")
        components?.queryItems = [
            URLQueryItem(name: "jql", value: jql),
            URLQueryItem(name: "maxResults", value: "100"),
            URLQueryItem(name: "fields", value: "summary,description,status,priority,assignee,created,updated,attachment")
        ]
        return components?.url
    }

    private func buildSubtasksURL(parentKey: String) -> URL? {
        var components = URLComponents(string: "\(baseURL)/rest/api/3/search/jql")
        components?.queryItems = [
            URLQueryItem(name: "jql", value: "parent=\(parentKey)"),
            URLQueryItem(name: "maxResults", value: "50"),
            URLQueryItem(name: "fields", value: "summary,status,assignee,priority,created,updated")
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

    private func parseSearchResponse(data: Data, parentKey: String? = nil) async throws -> [IssueDTO] {
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
        var results: [IssueDTO] = []
        for issue in issues {
            let assigneeName = issue.fields.assignee?.displayName
            let url = URL(string: "\(baseURL)/browse/\(issue.key)")
            let createdAt = issue.fields.created
            let updatedAt = issue.fields.updated
            let desc = issue.fields.description
            let descriptionText = desc?.plainText
            let attachments = issue.fields.attachment ?? []
            let attachmentMap = buildAttachmentMap(attachments: attachments)
            let imageIds = imageAttachmentIdsInOrder(attachments: attachments)
            let mediaIdToSignedURL = await buildMediaIdToSignedURLMap(attachments: attachments)
            let descriptionHTML = desc?.adfDict.flatMap { ADFToHTML.convert(adf: $0, baseURL: baseURL, attachmentMap: attachmentMap, imageAttachmentIdsInOrder: imageIds, mediaIdToSignedURL: mediaIdToSignedURL) }
            results.append(IssueDTO(
                externalId: issue.key,
                title: issue.fields.summary,
                status: issue.fields.status.name,
                assignee: assigneeName,
                description: descriptionText?.isEmpty == false ? descriptionText : nil,
                descriptionHTML: descriptionHTML?.isEmpty == false ? descriptionHTML : nil,
                parentExternalId: parentKey,
                url: url,
                priority: issue.fields.priority?.name,
                createdAt: createdAt,
                updatedAt: updatedAt
            ))
        }
        return results
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
    let attachment: [JiraAttachment]?
}

private struct JiraAttachment: Decodable {
    let id: String
    let filename: String?

    enum CodingKeys: String, CodingKey { case id, filename }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? c.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = try c.decode(String.self, forKey: .id)
        }
        filename = try? c.decode(String.self, forKey: .filename)
    }
}

/// Descripción en ADF (Atlassian Document Format). Se decodifica como JSON genérico.
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

    var adfDict: [String: Any]? {
        raw as? [String: Any]
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
