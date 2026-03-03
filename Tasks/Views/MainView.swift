import SwiftUI
import SwiftData

struct MainView: View {
    @EnvironmentObject private var taskStore: TaskStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var selectedTaskId: String?
    @State private var showingSettings = false
    @State private var showingCreateTask = false

    /// Sidebar lee directo de SwiftData: evita que mutaciones de taskStore.tasks
    /// (fetchSubtasks, sortByPriority, etc.) hagan desaparecer items.
    @Query(filter: #Predicate<TaskItem> { $0.parentExternalId == nil }, sort: \TaskItem.taskId)
    private var parentTasksFromDB: [TaskItem]

    private var sidebarTasks: [TaskItem] {
        let filtered = taskStore.selectedStatusFilters.isEmpty
            ? parentTasksFromDB
            : parentTasksFromDB.filter { taskStore.selectedStatusFilters.contains($0.status) }
        return filtered.sorted { $0.priorityScore > $1.priorityScore }
    }

    /// Lista plana: padres + subtareas asignadas a mí, ordenada por prioridad (una subtask puede estar arriba del padre).
    private var flatSidebarTasks: [TaskItem] {
        let parents = sidebarTasks
        let subs = taskStore.allSubtasksAssignedToMe()
        return (parents + subs).sorted { $0.priorityScore > $1.priorityScore }
    }

    private var selectedTask: TaskItem? {
        guard let id = selectedTaskId else { return nil }
        return flatSidebarTasks.first { $0.taskId == id }
            ?? taskStore.tasks.first { $0.taskId == id }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTaskId) {
                Section("Tareas") {
                    ForEach(flatSidebarTasks, id: \.taskId) { task in
                        TaskRowView(task: task, taskStore: taskStore)
                            .tag(task.taskId)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 260, ideal: 300)
        } detail: {
            if let task = selectedTask {
                TaskDetailView(task: task, taskStore: taskStore, onSelectSubtask: { selectedTaskId = $0.taskId }, onSelectParent: { selectedTaskId = $0.taskId })
                .id(task.taskId)
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
                    showingCreateTask = true
                } label: {
                    Label("Nueva tarea", systemImage: "plus")
                }
                .disabled(taskStore.providerId != JiraProvider.providerId)

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
        .sheet(isPresented: $showingCreateTask) {
            CreateTaskView(taskStore: taskStore)
        }
        .overlay(alignment: .bottomLeading) {
            if let message = taskStore.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
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
                dismissWindow(id: "main")
            } else {
                dismissWindow(id: "mini")
            }
        }
    }

    private func setupProviderIfNeeded() {
        let url = KeychainHelper.load(key: "jira_url")
        let email = KeychainHelper.load(key: "jira_email") ?? UserDefaults.standard.string(forKey: "jira_email")
        let token = KeychainHelper.load(key: "jira_api_token")

        if let url, let email, let token, !token.isEmpty {
            let jql = KeychainHelper.loadJQL() ?? "assignee = currentUser() ORDER BY updated DESC"
            taskStore.setProvider(JiraProvider(baseURL: url, email: email, apiToken: token, jql: jql))
            Task {
                if taskStore.tasks.isEmpty {
                    await taskStore.fetchFromProvider()
                } else {
                    await taskStore.loadCurrentUserDisplayNameIfNeeded()
                }
            }
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
