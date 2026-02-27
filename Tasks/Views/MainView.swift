import SwiftUI
import SwiftData

struct MainView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var selectedTask: TaskItem?
    @State private var showingSettings = false

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTask) {
                ForEach(taskStore.tasks) { task in
                    TaskRowView(task: task)
                        .tag(task)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 260)
        } detail: {
            if let task = selectedTask {
                TaskDetailView(task: task, taskStore: taskStore)
            } else {
                ContentUnavailableView(
                    "Selecciona una tarea",
                    systemImage: "checklist",
                    description: Text("Elige una tarea de la lista para ver detalles y priorizar")
                )
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await taskStore.fetchFromProvider() }
                } label: {
                    Label("Actualizar", systemImage: "arrow.clockwise")
                }
                .disabled(taskStore.isLoading)

                Button {
                    taskStore.toggleMiniView()
                } label: {
                    Label(
                        taskStore.isMiniViewVisible ? "Ocultar mini vista" : "Mostrar mini vista",
                        systemImage: taskStore.isMiniViewVisible ? "rectangle.on.rectangle.angled" : "rectangle.on.rectangle.angled"
                    )
                }

                Button {
                    showingSettings = true
                } label: {
                    Label("Ajustes", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(taskStore: taskStore)
        }
        .overlay(alignment: .bottomLeading) {
            if let message = taskStore.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.caption)
                        .lineLimit(2)
                    Spacer()
                    Button("Cerrar") {
                        taskStore.errorMessage = nil
                    }
                    .buttonStyle(.borderless)
                }
                .padding(12)
                .frame(maxWidth: 400)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: taskStore.errorMessage != nil)
        .task {
            await taskStore.loadTasks()
            setupProviderIfNeeded()
        }
        .onChange(of: taskStore.isMiniViewVisible) { _, visible in
            if visible {
                openWindow(id: "mini")
            } else {
                dismissWindow(id: "mini")
            }
        }
    }

    private func setupProviderIfNeeded() {
        guard taskStore.tasks.isEmpty else { return }
        let url = KeychainHelper.load(key: "jira_url") ?? UserDefaults.standard.string(forKey: "jira_url")
        let email = KeychainHelper.load(key: "jira_email") ?? UserDefaults.standard.string(forKey: "jira_email")
        let token = KeychainHelper.load(key: "jira_api_token")

        if let url, let email, let token, !token.isEmpty {
            taskStore.setProvider(JiraProvider(baseURL: url, email: email, apiToken: token))
            Task { await taskStore.fetchFromProvider() }
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: TaskItem.self, configurations: config)
    let store = TaskStore(modelContext: container.mainContext)
    MainView()
        .modelContainer(container)
        .environmentObject(store)
}
