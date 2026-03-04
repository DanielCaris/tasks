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

    /// Obtiene las subtareas/hijos de un issue padre. Si isEpic, usa "Epic Link" en JQL.
    func fetchSubtasks(parentKey: String, isEpic: Bool = false) async throws -> [IssueDTO] {
        guard let url = buildSubtasksURL(parentKey: parentKey, isEpic: isEpic) else {
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
        return try await parseSearchResponse(data: data, parentKey: parentKey, forceParentKey: isEpic)
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

    func updateIssue(externalId: String, title: String?, description: Any?) async throws -> [String: Any]? {
        print("[Tasks] JiraProvider.updateIssue: \(externalId)")
        guard let url = URL(string: "\(baseURL)/rest/api/3/issue/\(externalId)") else {
            print("[Tasks] JiraProvider.updateIssue: URL inválida")
            throw JiraError.invalidURL
        }

        var fields: [String: Any] = [:]
        var adfSent: [String: Any]?
        if let title { fields["summary"] = title }
        if let description {
            let adf: [String: Any]
            if let dict = description as? [String: Any] {
                adf = dict
                print("[Tasks] JiraProvider.updateIssue: usando ADF proporcionado")
            } else if let markdown = description as? String {
                print("[Tasks] JiraProvider.updateIssue: convirtiendo Markdown→ADF...")
                adf = MarkdownToADF.convert(markdown)
                print("[Tasks] JiraProvider.updateIssue: ADF generado")
            } else {
                print("[Tasks] JiraProvider.updateIssue: tipo de descripción no soportado")
                adfSent = nil
                return nil
            }
            fields["description"] = adf
            adfSent = adf
        }

        guard !fields.isEmpty else {
            print("[Tasks] JiraProvider.updateIssue: fields vacío, omitiendo")
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let credentials = "\(email):\(apiToken)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            print("[Tasks] JiraProvider.updateIssue: credenciales inválidas")
            throw JiraError.invalidCredentials
        }
        request.setValue("Basic \(credentialsData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        request.httpBody = try JSONSerialization.data(withJSONObject: ["fields": fields])
        print("[Tasks] JiraProvider.updateIssue: enviando PUT...")

        let (data, response) = try await URLSession.shared.data(for: request)
        print("[Tasks] JiraProvider.updateIssue: respuesta recibida")

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[Tasks] JiraProvider.updateIssue: respuesta no HTTP")
            throw JiraError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = parseJiraError(data: data, statusCode: httpResponse.statusCode)
            print("[Tasks] JiraProvider.updateIssue: HTTP \(httpResponse.statusCode) - \(message)")
            throw JiraError.apiError(statusCode: httpResponse.statusCode, message: message)
        }
        print("[Tasks] JiraProvider.updateIssue: OK")
        return adfSent
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
            fields["description"] = MarkdownToADF.convert(description)
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
        return try await fetchIssueInternal(issueKey: createResponse.key)
    }

    func createSubtask(parentExternalId: String, title: String, description: String?) async throws -> IssueDTO? {
        let projectKey = parentExternalId.split(separator: "-").first.map(String.init) ?? ""
        guard !projectKey.isEmpty else { throw JiraError.apiError(statusCode: 400, message: "Clave de proyecto inválida") }

        let subtaskIssuetype = try await fetchSubtaskIssueType(projectKey: projectKey.uppercased())

        guard let url = URL(string: "\(baseURL)/rest/api/3/issue") else {
            throw JiraError.invalidURL
        }

        var fields: [String: Any] = [
            "project": ["key": projectKey.uppercased()],
            "parent": ["key": parentExternalId],
            "summary": title,
            "issuetype": subtaskIssuetype
        ]
        if let description, !description.isEmpty {
            fields["description"] = MarkdownToADF.convert(description)
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

        struct CreateSubtaskResponse: Decodable {
            let key: String
        }
        let createResponse = try JSONDecoder().decode(CreateSubtaskResponse.self, from: data)
        let dto = try await fetchIssueInternal(issueKey: createResponse.key)
        return IssueDTO(
            externalId: dto.externalId,
            title: dto.title,
            status: dto.status,
            assignee: dto.assignee,
            description: dto.description,
            descriptionHTML: dto.descriptionHTML,
            descriptionADFJSON: dto.descriptionADFJSON,
            parentExternalId: parentExternalId,
            url: dto.url,
            priority: dto.priority,
            issueType: dto.issueType,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }

    /// Crea una tarea (Task) bajo una épica. Usa Epic Link si existe; si no, intenta parent (proyectos team-managed).
    func createTaskUnderEpic(epicKey: String, title: String, description: String?) async throws -> IssueDTO? {
        let projectKey = epicKey.split(separator: "-").first.map(String.init) ?? ""
        guard !projectKey.isEmpty else { throw JiraError.apiError(statusCode: 400, message: "Clave de proyecto inválida") }

        guard let url = URL(string: "\(baseURL)/rest/api/3/issue") else {
            throw JiraError.invalidURL
        }

        var fields: [String: Any] = [
            "project": ["key": projectKey.uppercased()],
            "summary": title,
            "issuetype": ["name": "Task"]
        ]
        if let epicLinkFieldId = try await fetchEpicLinkFieldId() {
            fields[epicLinkFieldId] = epicKey
        } else {
            // Fallback: proyectos team-managed usan parent para la jerarquía de épicas
            AppLog.warning("Epic Link no encontrado; intentando con parent (proyectos team-managed)", context: "createTaskUnderEpic")
            fields["parent"] = ["key": epicKey]
        }
        if let description, !description.isEmpty {
            fields["description"] = MarkdownToADF.convert(description)
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
        let dto = try await fetchIssueInternal(issueKey: createResponse.key)
        return IssueDTO(
            externalId: dto.externalId,
            title: dto.title,
            status: dto.status,
            assignee: dto.assignee,
            description: dto.description,
            descriptionHTML: dto.descriptionHTML,
            descriptionADFJSON: dto.descriptionADFJSON,
            parentExternalId: epicKey,
            url: dto.url,
            priority: dto.priority,
            issueType: dto.issueType,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt
        )
    }

    /// Obtiene el ID del campo Epic Link (customfield_XXXXX) desde la API de campos.
    /// Busca por schema (epic-link) o por nombre "Epic Link".
    private func fetchEpicLinkFieldId() async throws -> String? {
        guard let url = URL(string: "\(baseURL)/rest/api/3/field") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let credentials = "\(email):\(apiToken)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            return nil
        }
        request.setValue("Basic \(credentialsData.base64EncodedString())", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            return nil
        }

        guard let fields = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        for field in fields {
            guard let id = field["id"] as? String,
                  id.hasPrefix("customfield_") else {
                continue
            }
            // 1. Buscar por schema (epic-link)
            if let schema = field["schema"] as? [String: Any],
               let custom = schema["custom"] as? String,
               (custom.contains("epic-link") || custom.contains("epiclink")) {
                return id
            }
            // 2. Fallback: buscar por nombre "Epic Link" (o "Epic link", "Enlace de épica", etc.)
            if let name = field["name"] as? String {
                let n = name.lowercased()
                if (n.contains("epic") && n.contains("link")) || (n.contains("épica") && n.contains("enlace")) {
                    return id
                }
            }
        }
        return nil
    }

    func fetchIssue(externalId: String) async throws -> IssueDTO? {
        try await fetchIssueInternal(issueKey: externalId)
    }

    /// Asigna el issue al usuario actual (quien hace la petición).
    func assignToMe(issueKey: String) async throws {
        let accountId = try await fetchCurrentUserAccountId()
        guard let url = URL(string: "\(baseURL)/rest/api/3/issue/\(issueKey)") else {
            throw JiraError.invalidURL
        }
        let body: [String: Any] = ["fields": ["assignee": ["accountId": accountId]]]
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let credentials = "\(email):\(apiToken)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            throw JiraError.invalidCredentials
        }
        request.setValue("Basic \(credentialsData.base64EncodedString())", forHTTPHeaderField: "Authorization")
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

    /// Actualiza los labels de un issue (reemplaza todos).
    func updateIssueLabels(externalId: String, labels: [String]) async throws {
        guard let url = URL(string: "\(baseURL)/rest/api/3/issue/\(externalId)") else {
            throw JiraError.invalidURL
        }
        let body: [String: Any] = ["fields": ["labels": labels]]
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let credentials = "\(email):\(apiToken)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            throw JiraError.invalidCredentials
        }
        request.setValue("Basic \(credentialsData.base64EncodedString())", forHTTPHeaderField: "Authorization")
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

    /// Obtiene boards disponibles para un proyecto (Scrum primero, fallback sin tipo). Últimos 50 por ID.
    func fetchBoards(projectKey: String) async throws -> [BoardOption] {
        let credentials = "\(email):\(apiToken)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            throw JiraError.invalidCredentials
        }
        let authHeader = "Basic \(credentialsData.base64EncodedString())"

        struct BoardsResponse: Decodable {
            let values: [BoardItem]?
        }
        struct BoardItem: Decodable {
            let id: Int
            let name: String
            let type: String?
        }

        let maxBoards = 50
        guard let countURL = URL(string: "\(baseURL)/rest/agile/1.0/board?projectKeyOrId=\(projectKey)&type=scrum&maxResults=1&startAt=0") else {
            throw JiraError.invalidURL
        }
        var request = URLRequest(url: countURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        let (countData, _) = try await URLSession.shared.data(for: request)
        struct CountResponse: Decodable { let total: Int? }
        let total = (try? JSONDecoder().decode(CountResponse.self, from: countData))?.total ?? 0
        let startAt = max(0, total - maxBoards)

        guard let url = URL(string: "\(baseURL)/rest/agile/1.0/board?projectKeyOrId=\(projectKey)&type=scrum&maxResults=\(maxBoards)&startAt=\(startAt)") else {
            throw JiraError.invalidURL
        }
        request.url = url
        let (boardsData, _) = try await URLSession.shared.data(for: request)
        var boards = try JSONDecoder().decode(BoardsResponse.self, from: boardsData)

        if boards.values?.isEmpty != false {
            guard let fallbackCountURL = URL(string: "\(baseURL)/rest/agile/1.0/board?projectKeyOrId=\(projectKey)&maxResults=1&startAt=0") else {
                return []
            }
            request.url = fallbackCountURL
            let (fcData, _) = try await URLSession.shared.data(for: request)
            let fallbackTotal = (try? JSONDecoder().decode(CountResponse.self, from: fcData))?.total ?? 0
            let fallbackStartAt = max(0, fallbackTotal - maxBoards)
            guard let fallbackURL = URL(string: "\(baseURL)/rest/agile/1.0/board?projectKeyOrId=\(projectKey)&maxResults=\(maxBoards)&startAt=\(fallbackStartAt)") else {
                return []
            }
            request.url = fallbackURL
            let (fallbackData, _) = try await URLSession.shared.data(for: request)
            boards = try JSONDecoder().decode(BoardsResponse.self, from: fallbackData)
        }

        var items = boards.values ?? []
        items.sort { $0.id > $1.id }
        return items.map { BoardOption(id: $0.id, name: $0.name) }
    }

    /// Obtiene sprints de un board específico.
    func fetchSprintsForBoard(boardId: Int) async throws -> [SprintOption] {
        let credentials = "\(email):\(apiToken)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            throw JiraError.invalidCredentials
        }
        let authHeader = "Basic \(credentialsData.base64EncodedString())"
        return try await fetchSprintsForBoardInternal(boardId: boardId, authHeader: authHeader)
    }

    private func fetchSprintsForBoardInternal(boardId: Int, authHeader: String) async throws -> [SprintOption] {
        struct SprintsResponse: Decodable {
            let values: [SprintItem]?
            let total: Int?
        }
        struct SprintItem: Decodable {
            let id: Int
            let name: String
            let state: String?
        }

        guard let totalURL = URL(string: "\(baseURL)/rest/agile/1.0/board/\(boardId)/sprint?state=active,future&maxResults=1&startAt=0") else {
            throw JiraError.invalidURL
        }
        var request = URLRequest(url: totalURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")

        let (totalData, totalResp) = try await URLSession.shared.data(for: request)
        let totalStatus = (totalResp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(totalStatus) else {
            throw JiraError.apiError(statusCode: totalStatus, message: "Board no soporta sprints")
        }
        let totalResponse = try JSONDecoder().decode(SprintsResponse.self, from: totalData)
        let total = totalResponse.total ?? 0
        let maxSprints = 30
        let startAt = max(0, total - maxSprints)
        guard let sprintsURL = URL(string: "\(baseURL)/rest/agile/1.0/board/\(boardId)/sprint?state=active,future&maxResults=\(maxSprints)&startAt=\(startAt)") else {
            throw JiraError.invalidURL
        }
        request.url = sprintsURL
        let (sprintsData, sprintResponse) = try await URLSession.shared.data(for: request)
        let sprintStatus = (sprintResponse as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(sprintStatus) else {
            throw JiraError.apiError(statusCode: sprintStatus, message: "Error al obtener sprints")
        }
        let sprints = try JSONDecoder().decode(SprintsResponse.self, from: sprintsData)
        let items = (sprints.values ?? []).prefix(maxSprints)
        return items.map { SprintOption(id: $0.id, name: $0.name, state: $0.state) }
    }

    /// Obtiene sprints para un proyecto (primer board con sprints). Mantiene compatibilidad.
    func fetchSprints(projectKey: String) async throws -> [SprintOption] {
        let boards = try await fetchBoards(projectKey: projectKey)
        let credentials = "\(email):\(apiToken)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            throw JiraError.invalidCredentials
        }
        let authHeader = "Basic \(credentialsData.base64EncodedString())"
        for board in boards {
            if let sprints = try? await fetchSprintsForBoardInternal(boardId: board.id, authHeader: authHeader), !sprints.isEmpty {
                return sprints
            }
        }
        return []
    }

    /// Añade un issue a un sprint (Agile API).
    func addIssueToSprint(issueKey: String, sprintId: Int) async throws {
        guard let url = URL(string: "\(baseURL)/rest/agile/1.0/sprint/\(sprintId)/issue") else {
            throw JiraError.invalidURL
        }
        let body: [String: Any] = ["issues": [issueKey]]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let credentials = "\(email):\(apiToken)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            throw JiraError.invalidCredentials
        }
        request.setValue("Basic \(credentialsData.base64EncodedString())", forHTTPHeaderField: "Authorization")
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

    private func fetchCurrentUserAccountId() async throws -> String {
        guard let url = URL(string: "\(baseURL)/rest/api/3/myself") else {
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
        struct MyselfResponse: Decodable {
            let accountId: String
            let displayName: String?
        }
        let myself = try JSONDecoder().decode(MyselfResponse.self, from: data)
        return myself.accountId
    }

    /// Obtiene el displayName del usuario actual para comparar con assignee.
    func fetchCurrentUserDisplayName() async throws -> String? {
        guard let url = URL(string: "\(baseURL)/rest/api/3/myself") else {
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
        struct MyselfResponse: Decodable {
            let displayName: String?
        }
        let myself = try JSONDecoder().decode(MyselfResponse.self, from: data)
        return myself.displayName
    }

    func deleteIssue(externalId: String) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/rest/api/3/issue/\(externalId)") else {
            throw JiraError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
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
        return true
    }

    private func fetchIssueInternal(issueKey: String) async throws -> IssueDTO {
        guard let url = URL(string: "\(baseURL)/rest/api/3/issue/\(issueKey)?fields=summary,description,status,priority,assignee,created,updated,attachment,issuetype,labels,customfield_10020") else {
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
        let descriptionADFJSON = desc?.adfDict.flatMap { (try? JSONSerialization.data(withJSONObject: $0)).flatMap { String(data: $0, encoding: .utf8) } }
        let labels = issue.fields.labels?.isEmpty == false ? issue.fields.labels : nil
        let sprint = issue.fields.sprintName
        return IssueDTO(
            externalId: issue.key,
            title: issue.fields.summary,
            status: issue.fields.status.name,
            assignee: assigneeName,
            description: descriptionText?.isEmpty == false ? descriptionText : nil,
            descriptionHTML: descriptionHTML?.isEmpty == false ? descriptionHTML : nil,
            descriptionADFJSON: descriptionADFJSON,
            parentExternalId: nil,
            url: browseURL,
            priority: issue.fields.priority?.name,
            issueType: issue.fields.issuetype?.name,
            createdAt: issue.fields.created,
            updatedAt: issue.fields.updated,
            labels: labels,
            sprint: sprint
        )
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
            URLQueryItem(name: "fields", value: "summary,description,status,priority,assignee,created,updated,attachment,parent,issuetype,labels,customfield_10020")
        ]
        return components?.url
    }

    /// Obtiene el issuetype de subtarea para el proyecto (id o name) desde createmeta.
    /// El nombre varía entre instancias: "Sub-task", "Subtask", etc.
    private func fetchSubtaskIssueType(projectKey: String) async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)/rest/api/3/issue/createmeta?projectKeys=\(projectKey)&expand=projects.issuetypes") else {
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

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projects = json["projects"] as? [[String: Any]] else {
            AppLog.warning("createmeta: formato de respuesta inesperado", context: "fetchSubtaskIssueType")
            return ["name": "Sub-task"]
        }

        for project in projects {
            guard let issuetypes = project["issuetypes"] as? [[String: Any]] else { continue }
            for it in issuetypes {
                let subtask = (it["subtask"] as? Bool) ?? false
                guard subtask else { continue }
                if let id = it["id"] as? String {
                    return ["id": id]
                }
                if let id = it["id"] as? Int {
                    return ["id": String(id)]
                }
                if let name = it["name"] as? String {
                    return ["name": name]
                }
            }
        }

        AppLog.warning("createmeta: no se encontró issuetype subtask, usando 'Sub-task'", context: "fetchSubtaskIssueType")
        return ["name": "Sub-task"]
    }

    private func buildSubtasksURL(parentKey: String, isEpic: Bool = false) -> URL? {
        var components = URLComponents(string: "\(baseURL)/rest/api/3/search/jql")
        let jql = isEpic ? "\"Epic Link\" = \(parentKey)" : "parent = \(parentKey)"
        components?.queryItems = [
            URLQueryItem(name: "jql", value: jql),
            URLQueryItem(name: "maxResults", value: "50"),
            URLQueryItem(name: "fields", value: "summary,description,status,assignee,priority,created,updated,attachment,issuetype,parent,labels,customfield_10020")
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

    private func parseSearchResponse(data: Data, parentKey: String? = nil, forceParentKey: Bool = false) async throws -> [IssueDTO] {
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
            let descriptionADFJSON = desc?.adfDict.flatMap { (try? JSONSerialization.data(withJSONObject: $0)).flatMap { String(data: $0, encoding: .utf8) } }
            let resolvedParent: String? = forceParentKey ? parentKey : (parentKey ?? issue.fields.parent?.key)
            let labels = issue.fields.labels?.isEmpty == false ? issue.fields.labels : nil
            let sprint = issue.fields.sprintName
            results.append(IssueDTO(
                externalId: issue.key,
                title: issue.fields.summary,
                status: issue.fields.status.name,
                assignee: assigneeName,
                description: descriptionText?.isEmpty == false ? descriptionText : nil,
                descriptionHTML: descriptionHTML?.isEmpty == false ? descriptionHTML : nil,
                descriptionADFJSON: descriptionADFJSON,
                parentExternalId: resolvedParent,
                url: url,
                priority: issue.fields.priority?.name,
                issueType: issue.fields.issuetype?.name,
                createdAt: createdAt,
                updatedAt: updatedAt,
                labels: labels,
                sprint: sprint
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
    let issuetype: JiraIssueType?
    let created: Date?
    let updated: Date?
    let attachment: [JiraAttachment]?
    let parent: JiraParent?
    let labels: [String]?
    /// Sprint field (customfield_10020 en Jira Software Cloud). Array de objetos con "name".
    let customfield_10020: [JiraSprintInfo]?

    /// Nombre del sprint activo (primer elemento del array).
    var sprintName: String? {
        customfield_10020?.first?.name
    }
}

private struct JiraSprintInfo: Decodable {
    let name: String?
}

private struct JiraIssueType: Decodable {
    let name: String
}

private struct JiraParent: Decodable {
    let key: String
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
