import SwiftUI
import SwiftData

/// Criterios de ordenación para subtareas.
enum SubtaskSortOrder: String, CaseIterable {
    case statusCustom = "Orden por estado"
    case externalIdAsc = "ID ascendente"
    case externalIdDesc = "ID descendente"
    case titleAsc = "Título A–Z"
    case titleDesc = "Título Z–A"
    case statusAsc = "Estado A–Z"
    case statusDesc = "Estado Z–A"

    /// Orden para mostrar en el menú (statusCustom primero).
    static var menuOrder: [SubtaskSortOrder] {
        [.statusCustom, .externalIdAsc, .externalIdDesc, .titleAsc, .titleDesc, .statusAsc, .statusDesc]
    }
}

struct TaskDetailView: View {
    let task: TaskItem
    @ObservedObject var taskStore: TaskStore
    /// Callback para navegar a una subtarea al hacer clic en ella.
    var onSelectSubtask: ((TaskItem) -> Void)?
    /// Callback para volver a la tarea padre (cuando se está viendo una subtarea).
    var onSelectParent: ((TaskItem) -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    @State private var subtaskSortOrder: SubtaskSortOrder = .statusCustom
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
    @State private var isAssigningToMe = false
    @FocusState private var isTitleFocused: Bool

    init(task: TaskItem, taskStore: TaskStore, onSelectSubtask: ((TaskItem) -> Void)? = nil, onSelectParent: ((TaskItem) -> Void)? = nil) {
        self.task = task
        self.taskStore = taskStore
        self.onSelectSubtask = onSelectSubtask
        self.onSelectParent = onSelectParent
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
                        subtasksSection()
                    }
                }
                .padding(24)
            }
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

    private var breadcrumbView: some View {
        HStack(spacing: 6) {
            if task.parentExternalId != nil, let onSelectParent, let parent = taskStore.tasks.first(where: { $0.externalId == task.parentExternalId }) {
                Button {
                    onSelectParent(parent)
                } label: {
                    Text(parent.externalId)
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                Text("›")
                    .font(.headline)
                    .foregroundStyle(.tertiary)
            }
            Text(task.externalId)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private func headerSection(availableHeight: CGFloat = 600) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                breadcrumbView
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

                if task.providerId == JiraProvider.providerId,
                   !isAssignedToCurrentUser {
                    Button {
                        Task { await assignToMe() }
                    } label: {
                        if isAssigningToMe {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Asignar a mí", systemImage: "person.badge.plus")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isAssigningToMe)
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
                descriptionSection(availableHeight: availableHeight)
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

    private func descriptionSection(availableHeight: CGFloat) -> some View {
        let descHeight = availableHeight * 0.5
        return VStack(alignment: .leading, spacing: 6) {
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

            Group {
                if isEditingDescription {
                    descriptionEditContent(height: descHeight)
                } else if let html = Self.descriptionHTMLForDisplay(task: task), !html.isEmpty {
                    RichHTMLView(
                        html: html,
                        baseURL: KeychainHelper.load(key: "jira_url") ?? "",
                        jiraEmail: KeychainHelper.load(key: "jira_email"),
                        jiraToken: KeychainHelper.load(key: "jira_api_token"),
                        colorScheme: colorScheme
                    )
                    .frame(maxWidth: .infinity, minHeight: descHeight, maxHeight: descHeight, alignment: .topLeading)
                    .background(colorScheme == .dark ? AnyShapeStyle(.regularMaterial.opacity(0.5)) : AnyShapeStyle(Color.clear), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    descriptionReadContent(height: descHeight)
                }
            }
            .frame(minHeight: descHeight)
        }
        .padding(.top, 16)
    }

    @ViewBuilder
    private func descriptionEditContent(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Puedes usar Markdown: **negrita**, *cursiva*, [enlaces](url), listas, etc.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            TextEditor(text: $editableDescription)
                .font(.body)
                .fontDesign(.monospaced)
                .frame(minHeight: max(120, height - 76), alignment: .topLeading)
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
        }
        .frame(height: height)
    }

    @ViewBuilder
    private func descriptionReadContent(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.descriptionText ?? "Sin descripción")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        .frame(height: height)
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

    private var isAssignedToCurrentUser: Bool {
        guard let assignee = task.assignee?.trimmingCharacters(in: .whitespaces),
              let current = taskStore.currentUserDisplayName?.trimmingCharacters(in: .whitespaces),
              !assignee.isEmpty, !current.isEmpty else { return false }
        return assignee.localizedCaseInsensitiveCompare(current) == .orderedSame
    }

    private func assignToMe() async {
        isAssigningToMe = true
        await taskStore.assignToMe(task)
        isAssigningToMe = false
    }

    private func subtasksSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let subsRaw = taskStore.subtasks(for: task)
            let subsFiltered = subsRaw.filter { !taskStore.excludedSubtaskStatuses.contains($0.status) }
            let subs = sortedSubtasks(subsFiltered)
            HStack(alignment: .center, spacing: 8) {
                Text("Subtareas")
                    .font(.headline)
                if isLoadingSubtasks {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                if !subsRaw.isEmpty {
                    Menu {
                        ForEach(SubtaskSortOrder.menuOrder, id: \.self) { order in
                            Button {
                                subtaskSortOrder = order
                            } label: {
                                HStack {
                                    Text(order.rawValue)
                                    if subtaskSortOrder == order {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Label("Ordenar", systemImage: "arrow.up.arrow.down.circle")
                                .font(.subheadline)
                            Text("·")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(subtaskSortOrder.rawValue)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .menuStyle(.borderlessButton)

                    Menu {
                        ForEach(availableSubtaskStatusesToExclude, id: \.self) { status in
                            Button(status) {
                                var next = taskStore.excludedSubtaskStatuses
                                next.insert(status)
                                taskStore.setSubtaskStatusExclusions(next)
                            }
                        }
                        if availableSubtaskStatusesToExclude.isEmpty && !taskStore.knownStatuses.isEmpty {
                            Text("Todos agregados")
                                .disabled(true)
                        }
                    } label: {
                        Label("Excluir", systemImage: "line.3.horizontal.decrease.circle")
                            .font(.subheadline)
                    }
                    .menuStyle(.borderlessButton)
                    .disabled(availableSubtaskStatusesToExclude.isEmpty && !taskStore.knownStatuses.isEmpty)

                    FlowLayout(spacing: 6) {
                        ForEach(Array(taskStore.excludedSubtaskStatuses).sorted(), id: \.self) { status in
                            StatusPill(label: status) {
                                var next = taskStore.excludedSubtaskStatuses
                                next.remove(status)
                                taskStore.setSubtaskStatusExclusions(next)
                            }
                        }
                    }
                }
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
            if subs.isEmpty && !isLoadingSubtasks {
                VStack(alignment: .leading, spacing: 8) {
                    Text(subsRaw.isEmpty ? "Sin subtareas" : "Todas las subtareas están ocultas por el filtro")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if task.parentExternalId == nil {
                        Button {
                            newSubtaskTitle = ""
                            newSubtaskDescription = ""
                            showingAddSubtask = true
                        } label: {
                            Label("Agregar subtarea", systemImage: "plus.circle.fill")
                                .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(subs) { sub in
                        Button {
                            onSelectSubtask?(sub)
                        } label: {
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
                                    .buttonStyle(.plain)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        .liquidGlassSubtaskCard()
                        .contextMenu {
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
            }
        }
        .task(id: task.taskId) {
            guard task.providerId == JiraProvider.providerId else { return }
            isLoadingSubtasks = true
            _ = await taskStore.fetchSubtasks(for: task)
            isLoadingSubtasks = false
        }
    }

    private var availableSubtaskStatusesToExclude: [String] {
        let all = taskStore.knownStatuses
        return all.filter { !taskStore.excludedSubtaskStatuses.contains($0) }
    }

    private func sortedSubtasks(_ items: [TaskItem]) -> [TaskItem] {
        switch subtaskSortOrder {
        case .externalIdAsc:
            return items.sorted { $0.externalId.localizedCompare($1.externalId) == .orderedAscending }
        case .externalIdDesc:
            return items.sorted { $0.externalId.localizedCompare($1.externalId) == .orderedDescending }
        case .titleAsc:
            return items.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .titleDesc:
            return items.sorted { $0.title.localizedCompare($1.title) == .orderedDescending }
        case .statusAsc:
            return items.sorted { $0.status.localizedCompare($1.status) == .orderedAscending }
        case .statusDesc:
            return items.sorted { $0.status.localizedCompare($1.status) == .orderedDescending }
        case .statusCustom:
            let projectKey = task.externalId.split(separator: "-").first.map(String.init) ?? ""
            return items.sorted { a, b in
                let ia = taskStore.statusSortIndex(for: a.status, projectKey: projectKey)
                let ib = taskStore.statusSortIndex(for: b.status, projectKey: projectKey)
                if ia != ib { return ia < ib }
                return a.priorityScore > b.priorityScore
            }
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
