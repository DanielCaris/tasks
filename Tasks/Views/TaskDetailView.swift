import SwiftUI
import SwiftData

struct TaskDetailView: View {
    let task: TaskItem
    @ObservedObject var taskStore: TaskStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var urgency: Int
    @State private var impact: Int
    @State private var effort: Int
    @State private var editableTitle: String
    @State private var editableDescription: String
    @State private var isEditingTitle = false
    @State private var isEditingDescription = false
    @State private var isSavingToJira = false
    @State private var availableTransitions: [TransitionOption] = []
    @State private var isLoadingTransitions = false
    @State private var isTransitioning = false
    @State private var isLoadingSubtasks = false
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
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection(availableHeight: geo.size.height)

                    if task.providerId == JiraProvider.providerId {
                        subtasksSection
                    }
                }
                .padding(24)
            }
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
        .background(.thinMaterial.opacity(0.5))
    }

    private func headerSection(availableHeight: CGFloat = 600) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(task.externalId)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                if let url = task.url {
                    Link(destination: url) {
                        Label("Abrir en Jira", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                }
                Spacer()
                Text(String(format: "%.1f", (Double(urgency) * Double(impact)) / Double(max(effort, 1))))
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }

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

            HStack(spacing: 8) {
                if availableTransitions.isEmpty && !isLoadingTransitions {
                    Label(task.status, systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isLoadingTransitions {
                    ProgressView()
                        .controlSize(.small)
                    Text(task.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Menu {
                        ForEach(availableTransitions) { transition in
                            Button {
                                performTransition(transition)
                            } label: {
                                Text(transition.targetStatusName)
                            }
                            .disabled(isTransitioning)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            if isTransitioning {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "circle.fill")
                                    .font(.caption2)
                            }
                            Text(task.status)
                                .font(.caption)
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                if let assignee = task.assignee {
                    Text("•")
                    Text(assignee)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 16) {
                    StepperView(label: "U", icon: "clock.fill", value: $urgency)
                        .onChange(of: urgency) { _, _ in savePriority() }

                    StepperView(label: "I", icon: "bolt.fill", value: $impact)
                        .onChange(of: impact) { _, _ in savePriority() }

                    StepperView(label: "E", icon: "hammer.fill", value: $effort)
                        .onChange(of: effort) { _, _ in savePriority() }
                }
            }
            .frame(height: 28)
            .task(id: task.taskId) {
                await loadTransitions()
            }

            if task.providerId == JiraProvider.providerId {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Descripción")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                        if !isEditingDescription, (task.descriptionHTML != nil || (task.descriptionText ?? "").isEmpty == false) {
                            Button {
                                isEditingDescription = true
                            } label: {
                                Label("Editar", systemImage: "pencil")
                                    .font(.caption)
                            }
                            .buttonStyle(.link)
                        }
                        Spacer()
                    }

                    if isEditingDescription {
                        TextEditor(text: $editableDescription)
                            .font(.body)
                            .frame(minHeight: 200)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))

                        HStack(spacing: 8) {
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

                            Button("Cancelar") {
                                isEditingDescription = false
                                editableDescription = task.descriptionText ?? ""
                            }
                            .buttonStyle(.bordered)
                        }
                    } else if let html = task.descriptionHTML, !html.isEmpty {
                        RichHTMLView(
                            html: html,
                            baseURL: KeychainHelper.load(key: "jira_url") ?? "",
                            jiraEmail: KeychainHelper.load(key: "jira_email"),
                            jiraToken: KeychainHelper.load(key: "jira_api_token"),
                            colorScheme: colorScheme
                        )
                        .frame(minHeight: 400, maxHeight: max(500, availableHeight - 280), alignment: .topLeading)
                        .background(colorScheme == .dark ? AnyShapeStyle(.regularMaterial.opacity(0.5)) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text(task.descriptionText ?? "Sin descripción")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 200, alignment: .topLeading)
                            .padding(8)
                            .background(colorScheme == .dark ? AnyShapeStyle(.regularMaterial.opacity(0.5)) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: 8))

                        Button {
                            isEditingDescription = true
                        } label: {
                            Label("Editar descripción", systemImage: "pencil")
                                .font(.caption)
                        }
                        .buttonStyle(.link)
                    }
                }
                .padding(.top, 16)
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

    private func loadTransitions() async {
        isLoadingTransitions = true
        availableTransitions = await taskStore.getTransitions(for: task)
        isLoadingTransitions = false
    }

    private func performTransition(_ transition: TransitionOption) {
        guard transition.targetStatusName != task.status else { return }
        isTransitioning = true
        Task {
            await taskStore.transitionTask(task, transitionId: transition.id, newStatus: transition.targetStatusName)
            await loadTransitions() // Caché invalidada tras la transición; recargar para el nuevo status
            isTransitioning = false
        }
    }

    private var subtasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Subtareas")
                    .font(.headline)
                if isLoadingSubtasks {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            let subs = taskStore.subtasks(for: task)
            if subs.isEmpty && !isLoadingSubtasks {
                Text("Sin subtareas")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(subs) { sub in
                        HStack(spacing: 8) {
                            Text(sub.externalId)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .leading)
                            Text(sub.title)
                                .font(.body)
                                .lineLimit(1)
                            Spacer()
                            Text(sub.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let url = sub.url {
                                Link(destination: url) {
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.caption)
                                }
                            }
                        }
                        .padding(8)
                        .liquidGlassSubtaskCard()
                    }
                }
            }
        }
        .task(id: task.taskId) {
            guard task.providerId == JiraProvider.providerId else { return }
            isLoadingSubtasks = true
            _ = await taskStore.fetchSubtasks(for: task)
            isLoadingSubtasks = false
        }
    }

    private func savePriority() {
        taskStore.updatePriority(task: task, urgency: urgency, impact: impact, effort: effort)
    }
}
