import SwiftUI
import SwiftData

struct MiniView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @EnvironmentObject private var taskStore: TaskStore
    @Query(sort: \TaskItem.taskId) private var allTasks: [TaskItem]

    private var topTasks: [TaskItem] {
        let sorted = allTasks.sorted { $0.priorityScore > $1.priorityScore }
        return Array(sorted.prefix(5))
    }

    var body: some View {
        VStack(spacing: 0) {
            if topTasks.isEmpty {
                ContentUnavailableView(
                    "Sin tareas",
                    systemImage: "checklist",
                    description: Text("Configura Jira y sincroniza")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(topTasks) { task in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(task.externalId)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if task.priorityScore > 0 {
                                Text(String(format: "%.1f", task.priorityScore))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(task.title)
                            .lineLimit(1)
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 280, minHeight: 180)
        .background(.thinMaterial)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openWindow(id: "main")
                    dismissWindow(id: "mini")
                    taskStore.toggleMiniView()
                } label: {
                    Label("Vista completa", systemImage: "arrow.up.left.and.arrow.down.right")
                }
            }
        }
    }
}
