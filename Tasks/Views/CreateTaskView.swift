import SwiftUI

struct CreateTaskView: View {
    @ObservedObject var taskStore: TaskStore
    @Environment(\.dismiss) private var dismiss

    @State private var projects: [ProjectOption] = []
    @State private var selectedProjectKey: String?
    @State private var isLoadingProjects = true
    @State private var title = ""
    @State private var description = ""
    @State private var isCreating = false

    private var defaultProjectKey: String? {
        guard let first = taskStore.tasks.first else { return nil }
        let parts = first.externalId.split(separator: "-")
        return parts.first.map(String.init)
    }

    var body: some View {
        Form {
            Section {
                if isLoadingProjects {
                    HStack {
                        Text("Proyecto")
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Text("Cargando proyectos…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Picker("Proyecto", selection: $selectedProjectKey) {
                        Text("Selecciona un proyecto").tag(nil as String?)
                        ForEach(projects) { project in
                            Text("\(project.name) (\(project.key))")
                                .tag(project.key as String?)
                        }
                    }
                }

                TextField("Título", text: $title, prompt: Text("Resumen de la tarea"))
                    .textContentType(.none)
            } header: {
                Text("Nueva tarea en Jira")
            } footer: {
                if !projects.isEmpty {
                    Text("Selecciona el proyecto donde crear la tarea.")
                }
            }

            Section("Descripción") {
                TextEditor(text: $description)
                    .frame(minHeight: 80)
            }

            Section {
                Button {
                    createTask()
                } label: {
                    Label {
                        Text("Crear tarea")
                    } icon: {
                        if isCreating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(isCreating || !isValid)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 420)
        .task {
            await loadProjects()
        }
    }

    private var isValid: Bool {
        selectedProjectKey != nil &&
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func loadProjects() async {
        isLoadingProjects = true
        projects = await taskStore.fetchProjects()
        isLoadingProjects = false
        if selectedProjectKey == nil {
            if let defaultKey = defaultProjectKey, projects.contains(where: { $0.key == defaultKey }) {
                selectedProjectKey = defaultKey
            } else if let first = projects.first {
                selectedProjectKey = first.key
            }
        }
    }

    private func createTask() {
        guard isValid, let projectKey = selectedProjectKey else { return }
        isCreating = true
        Task {
            let taskTitle = title.trimmingCharacters(in: .whitespaces)
            let taskDescription = description.trimmingCharacters(in: .whitespaces)
            let desc = taskDescription.isEmpty ? nil : taskDescription

            if await taskStore.createTaskInProvider(projectKey: projectKey, title: taskTitle, description: desc) != nil {
                dismiss()
            }
            isCreating = false
        }
    }
}
