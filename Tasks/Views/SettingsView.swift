import SwiftUI

struct SettingsView: View {
    @ObservedObject var taskStore: TaskStore
    @Environment(\.dismiss) private var dismiss

    @State private var jiraURL = ""
    @State private var jiraEmail = ""
    @State private var jiraToken = ""
    @State private var jql = "assignee = currentUser() AND status != Done ORDER BY updated DESC"
    @State private var hasChanges = false

    var body: some View {
        Form {
            Section("Jira") {
                TextField("URL base", text: $jiraURL)
                    .textContentType(.URL)
                    .textFieldStyle(.roundedBorder)

                TextField("Email", text: $jiraEmail)
                    .textContentType(.emailAddress)
                    .textFieldStyle(.roundedBorder)

                SecureField("API Token", text: $jiraToken)
                    .textFieldStyle(.roundedBorder)

                TextField("JQL (opcional)", text: $jql, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
            }

            Section {
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
            jiraURL = KeychainHelper.load(key: "jira_url") ?? UserDefaults.standard.string(forKey: "jira_url") ?? ""
            jiraEmail = KeychainHelper.load(key: "jira_email") ?? ""
            jiraToken = KeychainHelper.load(key: "jira_api_token") ?? ""
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
        UserDefaults.standard.set(url, forKey: "jira_url")
        KeychainHelper.save(key: "jira_email", value: email)
        KeychainHelper.save(key: "jira_api_token", value: jiraToken)

        taskStore.setProvider(JiraProvider(
            baseURL: url,
            email: email,
            apiToken: jiraToken,
            jql: jql.isEmpty ? "assignee = currentUser() AND status != Done ORDER BY updated DESC" : jql
        ))

        dismiss()
    }
}
