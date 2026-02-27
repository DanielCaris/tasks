import SwiftUI
import SwiftData

struct TaskRowView: View {
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.externalId)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    Text(task.title)
                        .font(.body)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if task.priorityScore > 0 {
                    Text(String(format: "%.1f", task.priorityScore))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
            }

            HStack(spacing: 16) {
                StepperView(label: "U", icon: "clock.fill", value: $urgency)
                    .onChange(of: urgency) { _, _ in savePriority() }

                StepperView(label: "I", icon: "bolt.fill", value: $impact)
                    .onChange(of: impact) { _, _ in savePriority() }

                StepperView(label: "E", icon: "hammer.fill", value: $effort)
                    .onChange(of: effort) { _, _ in savePriority() }
            }
        }
        .padding(.vertical, 6)
        .onChange(of: task.urgency) { _, newValue in
            if let v = newValue { urgency = v }
        }
        .onChange(of: task.impact) { _, newValue in
            if let v = newValue { impact = v }
        }
        .onChange(of: task.effort) { _, newValue in
            if let v = newValue { effort = v }
        }
    }

    private func savePriority() {
        taskStore.updatePriority(task: task, urgency: urgency, impact: impact, effort: effort)
    }
}
