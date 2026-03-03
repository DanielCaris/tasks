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
    @State private var isRefreshingTask = false
    @State private var showingAddSubtask = false
    @State private var newSubtaskTitle = ""
    @State private var newSubtaskDescription = ""
    @State private var isCreatingSubtask = false
    @FocusState private var isTitleFocused: Bool

    init(task: TaskItem, taskStore: TaskStore) {
        self.task = task
        self.taskStore = taskStore
        _urgency = State(initialValue: task.urgency ?? 1)
        _impact = State(initialValue: task.impact ?? 1)
        _effort = State(initialValue: task.effort ?? 1)
        _editableTitle = State(initialValue: task.title)
        _editableDescription = State(initialValue: Self.initialDescriptionMarkdown(for: task))
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
        .sheet(isPresented: $showingAddSubtask) {
            addSubtaskSheet
        }
    }

    private var addSubtaskSheet: some View {
        Form {
            Section {
                TextField("Título de la subtarea", text: $newSubtaskTitle, prompt: Text("Resumen de la subtarea"))
                    .textContentType(.none)
            } header: {
                Text("Nueva subtarea")
            } footer: {
                Text("La subtarea se creará en Jira bajo \(task.externalId).")
            }

            Section("Descripción") {
                TextEditor(text: $newSubtaskDescription)
                    .font(.body)
                    .fontDesign(.monospaced)
                    .frame(minHeight: 60)
            }

            Section {
                Button {
                    createSubtask()
                } label: {
                    Label {
                        Text("Crear subtarea")
                    } icon: {
                        if isCreatingSubtask {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(isCreatingSubtask || newSubtaskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 320)
    }

    private func createSubtask() {
        let title = newSubtaskTitle.trimmingCharacters(in: .whitespaces)
        let description = newSubtaskDescription.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        isCreatingSubtask = true
        Task {
            if await taskStore.createSubtask(for: task, title: title, description: description.isEmpty ? nil : description) != nil {
                showingAddSubtask = false
            }
            isCreatingSubtask = false
        }
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
                if task.providerId == JiraProvider.providerId {
                    Button {
                        Task { await refreshCurrentTask() }
                    } label: {
                        if isRefreshingTask {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Actualizar", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.borderless)
                    .disabled(isRefreshingTask)
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
                        if !isEditingDescription, (task.descriptionHTML != nil || task.descriptionADFJSON != nil || (task.descriptionText ?? "").isEmpty == false) {
                            Button {
                                editableDescription = Self.initialDescriptionMarkdown(for: task)
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
                        Text("Puedes usar Markdown: **negrita**, *cursiva*, [enlaces](url), listas, etc.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                        TextEditor(text: $editableDescription)
                            .font(.body)
                            .fontDesign(.monospaced)
                            .frame(minHeight: 400, maxHeight: max(500, availableHeight - 280), alignment: .topLeading)
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
                                editableDescription = Self.initialDescriptionMarkdown(for: task)
                            }
                            .buttonStyle(.bordered)
                        }
                    } else if let html = Self.descriptionHTMLForDisplay(task: task), !html.isEmpty {
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
                            editableDescription = Self.initialDescriptionMarkdown(for: task)
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
        .onChange(of: task.descriptionText) { _, _ in
            if !isEditingDescription { editableDescription = Self.initialDescriptionMarkdown(for: task) }
        }
        .onChange(of: task.descriptionADFJSON) { _, _ in
            if !isEditingDescription { editableDescription = Self.initialDescriptionMarkdown(for: task) }
        }
        .onChange(of: task.descriptionMarkdown) { _, _ in
            if !isEditingDescription { editableDescription = Self.initialDescriptionMarkdown(for: task) }
        }
    }

    private var hasEdits: Bool {
        editableTitle != task.title || editableDescription != Self.initialDescriptionMarkdown(for: task)
    }

    private func saveToJira() {
        guard hasEdits else {
            print("[Tasks] saveToJira: sin cambios, omitiendo")
            return
        }
        print("[Tasks] saveToJira: iniciando guardado para \(task.externalId)")
        isSavingToJira = true
        Task {
            defer {
                isSavingToJira = false
                print("[Tasks] saveToJira: finalizado (spinner off)")
            }
            await taskStore.updateTaskInProvider(
                task: task,
                title: editableTitle != task.title ? editableTitle : nil,
                description: editableDescription != Self.initialDescriptionMarkdown(for: task) ? editableDescription : nil
            )
            if (taskStore.errorMessage ?? "").isEmpty {
                isEditingDescription = false
            }
        }
    }

    private func refreshCurrentTask() async {
        isRefreshingTask = true
        defer { isRefreshingTask = false }
        await taskStore.refreshTask(task)
        if (taskStore.errorMessage ?? "").isEmpty {
            editableTitle = task.title
            editableDescription = Self.initialDescriptionMarkdown(for: task)
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
                Spacer()
                if task.parentExternalId == nil {
                    Button {
                        newSubtaskTitle = ""
                        newSubtaskDescription = ""
                        showingAddSubtask = true
                    } label: {
                        Label("Agregar subtarea", systemImage: "plus.circle.fill")
                            .font(.subheadline)
                    }
                    .buttonStyle(.borderless)
                }
            }
            let subs = taskStore.subtasks(for: task)
            if subs.isEmpty && !isLoadingSubtasks {
                Text("Sin subtareas")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                List {
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
                        .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task {
                                    await taskStore.deleteSubtask(sub)
                                }
                            } label: {
                                Label("Eliminar", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(minHeight: CGFloat(max(subs.count, 1)) * 44)
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

    private static func initialDescriptionMarkdown(for task: TaskItem) -> String {
        if let md = task.descriptionMarkdown, !md.isEmpty {
            return md
        }
        if let json = task.descriptionADFJSON,
           let data = json.data(using: .utf8),
           let adf = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return ADFToMarkdown.convert(adf: adf)
        }
        if let html = task.descriptionHTML, !html.isEmpty {
            return HTMLToMarkdown.convert(html)
        }
        return task.descriptionText ?? ""
    }

    /// HTML para mostrar la descripción renderizada (Markdown/ADF → HTML).
    private static func descriptionHTMLForDisplay(task: TaskItem) -> String? {
        if let html = task.descriptionHTML, !html.isEmpty {
            return html
        }
        if let json = task.descriptionADFJSON,
           let data = json.data(using: .utf8),
           let adf = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let baseURL = KeychainHelper.load(key: "jira_url") ?? ""
            return ADFToHTML.convert(adf: adf, baseURL: baseURL)
        }
        if let text = task.descriptionText, !text.isEmpty {
            let adf = MarkdownToADF.convert(text)
            let baseURL = KeychainHelper.load(key: "jira_url") ?? ""
            return ADFToHTML.convert(adf: adf, baseURL: baseURL)
        }
        return nil
    }
}
