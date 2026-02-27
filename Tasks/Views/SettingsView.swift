import SwiftUI

struct SettingsView: View {
    @ObservedObject var taskStore: TaskStore
    @Environment(\.dismiss) private var dismiss

    @State private var jiraURL = ""
    @State private var jiraEmail = ""
    @State private var jiraToken = ""
    @State private var jql = "assignee = currentUser() ORDER BY updated DESC"
    @State private var hasChanges = false
    @State private var isTesting = false
    @State private var testMessage: String?

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

                TextField("JQL (opcional)", text: $jql, prompt: Text("assignee = currentUser()"), axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 8) {
                    Text("Presets:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button("Mis tareas") { jql = "assignee = currentUser() ORDER BY updated DESC" }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                    Button("Todas recientes") { jql = "order by updated DESC" }
                        .buttonStyle(.borderless)
                        .font(.caption2)
                    Button("Por proyecto") { jql = "project in projectsLeadByUser() ORDER BY updated DESC" }
                        .buttonStyle(.borderless)
                        .font(.caption2)
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
                    if isTesting {
                        ProgressView().scaleEffect(0.8)
                        Text("Probando...")
                    } else {
                        Label("Probar conexión", systemImage: "network")
                    }
                }
                .disabled(!isValid || isTesting)

                if let msg = testMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(msg.contains("éxito") ? .green : .red)
                }

                Button("Guardar") {
                    saveAndClose()
                }
                .disabled(!isValid)

                Button("Cancelar", role: .cancel) {
                    dismiss()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 320)
        .onAppear {
            jiraURL = KeychainHelper.load(key: "jira_url") ?? ""
            jiraEmail = KeychainHelper.load(key: "jira_email") ?? ""
            jiraToken = KeychainHelper.load(key: "jira_api_token") ?? ""
            testMessage = nil
        }
    }

    private func testConnection() {
        testMessage = nil
        isTesting = true
        let url = jiraURL.trimmingCharacters(in: .whitespaces)
        let email = jiraEmail.trimmingCharacters(in: .whitespaces)
        let provider = JiraProvider(baseURL: url, email: email, apiToken: jiraToken, jql: jql)
        Task {
            do {
                let issues = try await provider.fetchIssues()
                await MainActor.run {
                    testMessage = "Conexión exitosa. Se encontraron \(issues.count) tareas."
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testMessage = error.localizedDescription
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
