import SwiftUI
import SwiftData

struct TaskDetailView: View {
    let task: TaskItem
    @ObservedObject var taskStore: TaskStore

    @State private var urgency: Int
    @State private var impact: Int
    @State private var effort: Int
    @State private var editableTitle: String
    @State private var editableDescription: String
    @State private var isEditingTitle = false
    @State private var isSavingToJira = false
    @FocusState private var isTitleFocused: Bool

    init(task: TaskItem, taskStore: TaskStore) {
        self.task = task
        self.taskStore = taskStore
        _urgency = State(initialValue: task.urgency ?? 1)
        _impact = State(initialValue: task.impact ?? 1)
        _effort = State(initialValue: task.effort ?? 1)
        _editableTitle = State(initialValue: task.title)
        _editableDescription = State(initialValue: task.descriptionText ?? "")
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

            Group {
                if isEditingTitle {
                    TextField("Título", text: $editableTitle)
                        .font(.title2)
                        .fontWeight(.medium)
                        .textFieldStyle(.plain)
                        .focused($isTitleFocused)
                        .onSubmit {
                            isEditingTitle = false
                            if editableTitle != task.title { saveToJira() }
                        }
                } else {
                    Text(editableTitle)
                        .font(.title2)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 1) {
                            isEditingTitle = true
                            DispatchQueue.main.async { isTitleFocused = true }
                        }
                }
            }
            .onChange(of: isTitleFocused) { _, focused in
                if !focused {
                    isEditingTitle = false
                    if editableTitle != task.title { saveToJira() }
                }
            }

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

            if task.providerId == JiraProvider.providerId {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Descripción")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $editableDescription)
                        .font(.body)
                        .frame(minHeight: 80, maxHeight: 200)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                    Button {
                        saveToJira()
                    } label: {
                        Label {
                            Text("Guardar en Jira")
                        } icon: {
                            if isSavingToJira {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSavingToJira || !hasEdits)
                }
            }
        }
        .onChange(of: task.title) { _, newValue in
            if editableTitle != newValue { editableTitle = newValue }
        }
        .onChange(of: task.descriptionText) { _, newValue in
            if editableDescription != (newValue ?? "") { editableDescription = newValue ?? "" }
        }
    }

    private var hasEdits: Bool {
        editableTitle != task.title || editableDescription != (task.descriptionText ?? "")
    }

    private func saveToJira() {
        guard hasEdits else { return }
        isSavingToJira = true
        Task {
            await taskStore.updateTaskInProvider(
                task: task,
                title: editableTitle != task.title ? editableTitle : nil,
                description: editableDescription != (task.descriptionText ?? "") ? editableDescription : nil
            )
            isSavingToJira = false
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
