import SwiftUI
import SwiftData

struct TaskDetailView: View {
    let task: TaskItem
    @ObservedObject var taskStore: TaskStore

    @State private var urgency: Int
    @State private var impact: Int
    @State private var effort: Int

    init(task: TaskItem, taskStore: TaskStore) {
        self.task = task
        self.taskStore = taskStore
        _urgency = State(initialValue: task.urgency ?? 1)
        _impact = State(initialValue: task.impact ?? 1)
        _effort = State(initialValue: task.effort ?? 1)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection

                prioritySection

                if let url = task.url {
                    Link(destination: url) {
                        Label("Abrir en Jira", systemImage: "arrow.up.right.square")
                    }
                }
            }
            .padding(24)
        }
        .background(.thinMaterial.opacity(0.5))
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.externalId)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(task.title)
                .font(.title2)
                .fontWeight(.medium)

            HStack {
                Label(task.status, systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let assignee = task.assignee {
                    Text("•")
                    Text(assignee)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Priorización")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                prioritySlider(label: "Urgencia", value: $urgency, icon: "bolt.fill")
                prioritySlider(label: "Impacto", value: $impact, icon: "star.fill")
                prioritySlider(label: "Esfuerzo", value: $effort, icon: "clock.fill")
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

            Text("Score: \(String(format: "%.1f", (Double(urgency) * Double(impact)) / Double(max(effort, 1))))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .onChange(of: urgency) { _, _ in savePriority() }
        .onChange(of: impact) { _, _ in savePriority() }
        .onChange(of: effort) { _, _ in savePriority() }
    }

    private func prioritySlider(label: String, value: Binding<Int>, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .frame(width: 80, alignment: .leading)
            Slider(value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Int($0.rounded()) }
            ), in: 1...5, step: 1)
            Text("\(value.wrappedValue)")
                .frame(width: 20)
                .font(.caption.monospacedDigit())
        }
    }

    private func savePriority() {
        taskStore.updatePriority(task: task, urgency: urgency, impact: impact, effort: effort)
    }
}
