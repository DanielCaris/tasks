import SwiftUI

struct SettingsView: View {
    @ObservedObject var taskStore: TaskStore
    @Environment(\.dismiss) private var dismiss

    @State private var jiraURL = ""
    @State private var jiraEmail = ""
    @State private var jiraToken = ""
    @State private var jql = "assignee = currentUser() ORDER BY updated DESC"
    @State private var jqlPreset: JQLPreset = .misTareas
    @State private var hasChanges = false

    private enum JQLPreset: String, CaseIterable {
        case misTareas = "Mis tareas"
        case todasRecientes = "Todas recientes"
        case porProyecto = "Por proyecto"
        case otra = "Otra"

        var query: String? {
            switch self {
            case .misTareas: return "assignee = currentUser() ORDER BY updated DESC"
            case .todasRecientes: return "order by updated DESC"
            case .porProyecto: return "project in projectsLeadByUser() ORDER BY updated DESC"
            case .otra: return nil
            }
        }

        static func from(jql: String) -> JQLPreset {
            let trimmed = jql.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "assignee = currentUser() ORDER BY updated DESC" { return .misTareas }
            if trimmed == "order by updated DESC" { return .todasRecientes }
            if trimmed == "project in projectsLeadByUser() ORDER BY updated DESC" { return .porProyecto }
            return .otra
        }
    }
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testSuccess: Bool?

    var body: some View {
        Form {
            Section {
                TextField("URL base", text: $jiraURL, prompt: Text("https://tu-empresa.atlassian.net"))
                    .textContentType(.URL)
                    .textFieldStyle(.roundedBorder)

                TextField("Email", text: $jiraEmail, prompt: Text("tu@email.com"))
                    .textContentType(.emailAddress)
                    .textFieldStyle(.roundedBorder)

                SecureField("API Token", text: $jiraToken, prompt: Text("Token de Atlassian"))
                    .textFieldStyle(.roundedBorder)

                Picker("Presets", selection: $jqlPreset) {
                    ForEach(JQLPreset.allCases, id: \.self) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: jqlPreset) { _, preset in
                    if let query = preset.query {
                        jql = query
                    }
                }

                TextField("JQL (opcional)", text: $jql, prompt: Text("assignee = currentUser()"), axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: jql) { _, _ in
                        jqlPreset = JQLPreset.from(jql: jql)
                    }
            } header: {
                Text("Jira")
            } footer: {
                Text("Genera un API token en id.atlassian.com → Seguridad → Tokens de API. Usa el mismo email con el que accedes a Jira.")
            }

            Section {
                Button {
                    testConnection()
                } label: {
                    HStack(spacing: 6) {
                        Group {
                            if isTesting {
                                ProgressView().scaleEffect(0.5)
                            } else {
                                Image(systemName: "network")
                            }
                        }
                        .frame(width: 14, height: 14)
                        Text(isTesting ? "Probando..." : "Probar conexión")
                    }
                    .frame(width: 160, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .disabled(!isValid || isTesting)

                if let msg = testMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(testSuccess == true ? .green : .red)
                }

                HStack {
                    Spacer()
                    Button("Cancelar", role: .cancel) {
                        dismiss()
                    }
                    Button("Guardar") {
                        saveAndClose()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 320)
        .onAppear {
            jiraURL = KeychainHelper.load(key: "jira_url") ?? ""
            jiraEmail = KeychainHelper.load(key: "jira_email") ?? ""
            jiraToken = KeychainHelper.load(key: "jira_api_token") ?? ""
            jqlPreset = JQLPreset.from(jql: jql)
            testMessage = nil
            testSuccess = nil
        }
    }

    private func testConnection() {
        testMessage = nil
        testSuccess = nil
        isTesting = true
        let url = jiraURL.trimmingCharacters(in: .whitespaces)
        let email = jiraEmail.trimmingCharacters(in: .whitespaces)
        let provider = JiraProvider(baseURL: url, email: email, apiToken: jiraToken, jql: jql)
        Task {
            do {
                let issues = try await provider.fetchIssues()
                await MainActor.run {
                    testMessage = "Conexión exitosa. Se encontraron \(issues.count) tareas."
                    testSuccess = true
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testMessage = error.localizedDescription
                    testSuccess = false
                    isTesting = false
                }
            }
        }
    }

    private var isValid: Bool {
        !jiraURL.trimmingCharacters(in: .whitespaces).isEmpty &&
        !jiraEmail.trimmingCharacters(in: .whitespaces).isEmpty &&
        !jiraToken.isEmpty
    }

    private func saveAndClose() {
        let url = jiraURL.trimmingCharacters(in: .whitespaces)
        let email = jiraEmail.trimmingCharacters(in: .whitespaces)

        KeychainHelper.save(key: "jira_url", value: url)
        KeychainHelper.save(key: "jira_email", value: email)
        KeychainHelper.save(key: "jira_api_token", value: jiraToken)

        taskStore.setProvider(JiraProvider(
            baseURL: url,
            email: email,
            apiToken: jiraToken,
            jql: jql.isEmpty ? "assignee = currentUser() ORDER BY updated DESC" : jql
        ))

        dismiss()
    }
}
