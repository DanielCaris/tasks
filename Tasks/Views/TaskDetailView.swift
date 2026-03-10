import SwiftUI
import SwiftData
import AppKit

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
    @State private var optimisticDescriptionADF: String? = nil
    @State private var debouncedSaveTask: Task<Void, Never>? = nil
    @State private var descriptionEditMonitor: Any? = nil
    @FocusState private var isTitleFocused: Bool
    @State private var editableLabels: [String] = []
    @State private var newLabelText: String = ""
    @State private var showingSprintPicker = false
    @State private var availableBoards: [BoardOption]? = nil
    @State private var selectedBoardId: Int? = nil
    @State private var availableSprints: [SprintOption]? = nil
    @State private var isLoadingBoards = false
    @State private var isLoadingSprints = false
    @State private var boardSearchText = ""
    @State private var sprintSearchText = ""
    @State private var isCurrentBoardPriority = false
    @State private var sprintCache: [Int: [SprintOption]] = [:]
    @State private var isRefreshingSprints = false

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
                VStack(alignment: .leading, spacing: 0) {
                    headerSection(availableHeight: geo.size.height)

                    Group {
                        if isEditingDescription {
                            Color.clear
                                .frame(height: 24)
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if hasEdits { saveToJira() }
                                    isEditingDescription = false
                                    removeDescriptionBlurMonitor()
                                }
                        } else {
                            Spacer().frame(height: 24)
                        }
                    }

                    if task.providerId == JiraProvider.providerId {
                        subtasksSection()
                    }
                }
                .padding(24)
            }
        }
        .onChange(of: task.taskId) { _, _ in
            // Al cambiar de tarea, resetear estado para evitar descripciones "pegadas" de la anterior
            urgency = task.urgency ?? 1
            impact = task.impact ?? 1
            effort = task.effort ?? 1
            editableTitle = task.title
            editableDescription = Self.initialDescriptionMarkdown(for: task)
            editableLabels = task.labels
            optimisticDescriptionADF = nil
            if isEditingDescription {
                removeDescriptionBlurMonitor()
                isEditingDescription = false
            }
        }
        .onChange(of: task.labels) { _, _ in
            editableLabels = task.labels
        }
        .sheet(isPresented: $showingSprintPicker) {
            sprintPickerSheet
        }
        .task(id: task.taskId) {
            editableLabels = task.labels
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
        .onReceive(NotificationCenter.default.publisher(for: .descriptionBlurSave)) { _ in
            guard isEditingDescription else { return }
            if hasEdits {
                saveToJira()
            }
            isEditingDescription = false
            removeDescriptionBlurMonitor()
        }
    }

    private var isEpic: Bool {
        let t = task.issueType?.lowercased() ?? ""
        return t == "epic" || t == "épica"
    }

    private var addSubtaskSheet: some View {
        let childLabel = isEpic ? "tarea" : "subtarea"
        return Form {
            Section {
                TextField("Título de la \(childLabel)", text: $newSubtaskTitle, prompt: Text("Resumen de la \(childLabel)"))
                    .textContentType(.none)
            } header: {
                Text(isEpic ? "Nueva tarea" : "Nueva subtarea")
            } footer: {
                Text(isEpic ? "La tarea se creará en Jira bajo la épica \(task.externalId)." : "La subtarea se creará en Jira bajo \(task.externalId).")
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
                        Text(isEpic ? "Crear tarea" : "Crear subtarea")
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
                    HStack(spacing: 4) {
                        Image(systemName: taskStore.issueTypeIcon(for: parent))
                            .font(.system(size: 12, weight: .bold))
                        Text(parent.externalId)
                            .font(.headline)
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                Text("›")
                    .font(.headline)
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 4) {
                Image(systemName: taskStore.issueTypeIcon(for: task))
                    .font(.system(size: 12, weight: .bold))
                Text(task.externalId)
                    .font(.headline)
            }
            .foregroundStyle(.secondary)
        }
    }

    private var projectKey: String {
        String(task.externalId.split(separator: "-").first ?? "")
    }

    private func openSprintPicker() {
        showingSprintPicker = true
        boardSearchText = ""
        sprintSearchText = ""
        if let priorityBoardId = KeychainHelper.loadPriorityBoard(projectKey: projectKey), !projectKey.isEmpty {
            selectedBoardId = priorityBoardId
            isCurrentBoardPriority = true
            availableBoards = nil
            
            // Mostrar cache inmediatamente si existe
            if let cached = sprintCache[priorityBoardId] {
                availableSprints = cached
                isLoadingSprints = false
                isRefreshingSprints = true
            } else {
                availableSprints = nil
                isLoadingSprints = true
                isRefreshingSprints = false
            }
            
            isLoadingBoards = true
            
            // SIEMPRE recargar en background para actualizar
            Task {
                let sprints = await taskStore.fetchSprintsForBoard(boardId: priorityBoardId)
                await MainActor.run {
                    availableSprints = sprints
                    sprintCache[priorityBoardId] = sprints
                    isLoadingSprints = false
                    isRefreshingSprints = false
                }
            }
            // Cargar boards en paralelo
            Task {
                let boards = await taskStore.fetchBoards(for: task)
                await MainActor.run {
                    availableBoards = boards
                    isLoadingBoards = false
                }
            }
        } else {
            selectedBoardId = nil
            availableBoards = nil
            availableSprints = nil
            isLoadingBoards = true
            isLoadingSprints = false
            isRefreshingSprints = false
            Task {
                availableBoards = await taskStore.fetchBoards(for: task)
                isLoadingBoards = false
            }
        }
    }

    private var labelsAndSprintRow: some View {
        HStack(spacing: 6) {
            // Sprint: solo para no-épicas (las épicas no tienen sprint en Jira).
            if !isEpic {
                HStack(spacing: 4) {
                    Button {
                        openSprintPicker()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "flag.checkered")
                                .font(.caption2)
                            Text(task.sprint ?? "Agregar sprint")
                                .font(.caption2)
                        }
                    }
                    .buttonStyle(.plain)
                    if let sprint = task.sprint, !sprint.isEmpty {
                        Button {
                            Task { await taskStore.removeFromSprint(task) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Quitar sprint")
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary.opacity(0.8), in: Capsule())
            }
            // Labels después
            ForEach(editableLabels, id: \.self) { label in
                HStack(spacing: 2) {
                    Text(label)
                        .font(.caption2)
                    Button {
                        var updated = editableLabels
                        updated.removeAll { $0 == label }
                        editableLabels = updated
                        Task { await taskStore.updateLabels(task, labels: updated) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary.opacity(0.8), in: Capsule())
            }
            TextField("Agregar label", text: $newLabelText)
                .font(.caption)
                .frame(width: 100)
                .textFieldStyle(.plain)
                .onSubmit {
                    addLabel()
                }
        }
        .padding(.vertical, 6)
    }

    private func addLabel() {
        let label = newLabelText.trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return }
        newLabelText = ""
        var updated = editableLabels
        if !updated.contains(label) {
            updated.append(label)
            editableLabels = updated
            Task { await taskStore.updateLabels(task, labels: updated) }
        }
    }

    private var sprintPickerSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if selectedBoardId != nil {
                    Button {
                        selectedBoardId = nil
                        availableSprints = nil
                        sprintSearchText = ""
                        isLoadingSprints = false
                    } label: {
                        Image(systemName: "chevron.left")
                        Text("Boards")
                    }
                    .buttonStyle(.plain)
                    if let bid = selectedBoardId {
                        Button {
                            if isCurrentBoardPriority {
                                KeychainHelper.clearPriorityBoard(projectKey: projectKey)
                                isCurrentBoardPriority = false
                            } else {
                                KeychainHelper.savePriorityBoard(projectKey: projectKey, boardId: bid)
                                isCurrentBoardPriority = true
                            }
                        } label: {
                            Image(systemName: isCurrentBoardPriority ? "star.fill" : "star")
                                .font(.subheadline)
                                .foregroundStyle(isCurrentBoardPriority ? .yellow : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(isCurrentBoardPriority ? "Quitar board prioritario" : "Marcar como board prioritario")
                    }
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(selectedBoardId == nil ? "Seleccionar board" : "Seleccionar sprint")
                        .font(.title2)
                        .fontWeight(.semibold)
                    if isRefreshingSprints {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Actualizando...")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Button("Cancelar") {
                    showingSprintPicker = false
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom, 20)

            if selectedBoardId == nil {
                // Paso 1: lista de boards
                if isLoadingBoards || availableBoards == nil {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Cargando boards...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if availableBoards?.isEmpty == true {
                    ContentUnavailableView(
                        "Sin boards",
                        systemImage: "rectangle.grid.2x2",
                        description: Text("No hay boards disponibles para este proyecto.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let boards = availableBoards {
                    TextField("Buscar board...", text: $boardSearchText)
                        .textFieldStyle(.roundedBorder)
                        .padding(.bottom, 12)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(boards.filter { boardSearchText.isEmpty || $0.name.localizedCaseInsensitiveContains(boardSearchText) }) { board in
                                Button {
                                    selectedBoardId = board.id
                                    isCurrentBoardPriority = KeychainHelper.loadPriorityBoard(projectKey: projectKey) == board.id
                                    
                                    // Mostrar cache si existe
                                    if let cached = sprintCache[board.id] {
                                        availableSprints = cached
                                        isLoadingSprints = false
                                        isRefreshingSprints = true
                                    } else {
                                        availableSprints = nil
                                        isLoadingSprints = true
                                        isRefreshingSprints = false
                                    }
                                    
                                    // SIEMPRE recargar en background
                                    Task {
                                        let sprints = await taskStore.fetchSprintsForBoard(boardId: board.id)
                                        await MainActor.run {
                                            availableSprints = sprints
                                            sprintCache[board.id] = sprints
                                            isLoadingSprints = false
                                            isRefreshingSprints = false
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "rectangle.grid.2x2")
                                            .font(.title2)
                                            .foregroundStyle(.secondary)
                                        Text(board.name)
                                            .font(.body)
                                            .fontWeight(.medium)
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        if KeychainHelper.loadPriorityBoard(projectKey: projectKey) == board.id {
                                            Image(systemName: "star.fill")
                                                .font(.caption)
                                                .foregroundStyle(.yellow)
                                        }
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } else {
                // Paso 2: sprints del board seleccionado
                if isLoadingSprints || availableSprints == nil {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Cargando sprints...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if availableSprints?.isEmpty == true {
                    ContentUnavailableView(
                        "Sin sprints",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text("Este board no tiene sprints.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let sprints = availableSprints {
                    TextField("Buscar sprint...", text: $sprintSearchText)
                        .textFieldStyle(.roundedBorder)
                        .padding(.bottom, 12)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(sprints.filter { sprintSearchText.isEmpty || $0.name.localizedCaseInsensitiveContains(sprintSearchText) }) { sprint in
                                Button {
                                    let selectedId = sprint.id
                                    let selectedName = sprint.name
                                    showingSprintPicker = false
                                    Task { await taskStore.addToSprint(task, sprintId: selectedId, sprintName: selectedName) }
                                } label: {
                                    HStack(spacing: 12) {
                                        sprintStateIcon(sprint.state)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(sprint.name)
                                                .font(.body)
                                                .fontWeight(.medium)
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            if let state = sprint.state {
                                                Text(sprintStateLabel(state))
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        sprintStateBadge(sprint.state)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 380, height: 340)
    }

    private func sprintStateIcon(_ state: String?) -> some View {
        Group {
            switch state?.lowercased() {
            case "active":
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            case "future":
                Image(systemName: "calendar.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            case "closed":
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            default:
                Image(systemName: "circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sprintStateBadge(_ state: String?) -> some View {
        Group {
            if let state = state {
                Text(sprintStateLabel(state))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(sprintStateColor(state).opacity(0.2), in: Capsule())
                    .foregroundStyle(sprintStateColor(state))
            }
        }
    }

    private func sprintStateLabel(_ state: String) -> String {
        switch state.lowercased() {
        case "active": return "Activo"
        case "future": return "Próximo"
        case "closed": return "Cerrado"
        default: return state
        }
    }

    private func sprintStateColor(_ state: String) -> Color {
        switch state.lowercased() {
        case "active": return .green
        case "future": return .blue
        case "closed": return .secondary
        default: return .secondary
        }
    }

    private func headerSection(availableHeight: CGFloat = 600) -> some View {
        let _ = taskStore.statusColors
        return VStack(alignment: .leading, spacing: 4) {
            if task.providerId == JiraProvider.providerId {
                labelsAndSprintRow
            }
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
                            .foregroundStyle(Color(hex: Color.primary.hexString))
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
                    HStack(spacing: 4) {
                        Circle()
                            .fill(taskStore.statusColor(for: task.status))
                            .frame(width: 10, height: 10)
                        Text(task.status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if isLoadingTransitions {
                    ProgressView()
                        .controlSize(.small)
                    Text(task.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 4) {
                        if isTransitioning {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Circle()
                                .fill(taskStore.statusColor(for: task.status))
                                .frame(width: 10, height: 10)
                        }
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
                            Text(task.status)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
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
                // Si la descripción está vacía, cargarla desde Jira (p. ej. subtareas o caché incompleta)
                if taskHasNoDescription(task) {
                    await taskStore.refreshTask(task)
                }
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
            optimisticDescriptionADF = nil
            if !isEditingDescription { editableDescription = Self.initialDescriptionMarkdown(for: task) }
        }
        .onChange(of: task.descriptionMarkdown) { _, _ in
            if !isEditingDescription { editableDescription = Self.initialDescriptionMarkdown(for: task) }
        }
    }

    private func descriptionSection(availableHeight: CGFloat) -> some View {
        let descHeight = availableHeight * 0.5
        return VStack(alignment: .leading, spacing: 6) {
            Group {
                if isEditingDescription {
                    descriptionEditContent(height: descHeight)
                } else if let html = Self.descriptionHTMLForDisplay(task: task, interactiveCheckboxes: task.descriptionADFJSON != nil, adfOverride: optimisticDescriptionADF), !html.isEmpty {
                    descriptionViewWithHover(height: descHeight) {
                        RichHTMLView(
                            html: html,
                            baseURL: KeychainHelper.load(key: "jira_url") ?? "",
                            jiraEmail: KeychainHelper.load(key: "jira_email"),
                            jiraToken: KeychainHelper.load(key: "jira_api_token"),
                            colorScheme: colorScheme,
                            labelColorHex: Color.primary.hexString,
                            onCheckboxToggle: task.descriptionADFJSON != nil ? { index, _ in
                                handleCheckboxToggleOptimistic(index: index)
                            } : nil,
                            onDoubleClick: {
                                editableDescription = Self.initialDescriptionMarkdown(for: task)
                                isEditingDescription = true
                            }
                        )
                        .id(task.taskId)
                        .frame(maxWidth: .infinity, minHeight: descHeight, maxHeight: descHeight, alignment: .topLeading)
                    }
                } else {
                    descriptionViewWithHover(height: descHeight) {
                        descriptionReadContent(height: descHeight, includeBackground: false)
                    }
                }
            }
            .frame(minHeight: descHeight)
        }
        .padding(.top, 16)
    }

    @ViewBuilder
    private func descriptionViewWithHover<Content: View>(height: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        let bgColor: some ShapeStyle = colorScheme == .dark
            ? AnyShapeStyle(.regularMaterial.opacity(0.5))
            : AnyShapeStyle(Color.clear)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(bgColor)
            content()
        }
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            editableDescription = Self.initialDescriptionMarkdown(for: task)
            isEditingDescription = true
        }
    }

    @ViewBuilder
    private func descriptionEditContent(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $editableDescription)
                .font(.body)
                .fontDesign(.monospaced)
                .frame(minHeight: max(120, height - 20), alignment: .topLeading)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(height: height)
        .onAppear {
            installDescriptionBlurMonitor()
        }
        .onDisappear {
            removeDescriptionBlurMonitor()
        }
    }

    private func installDescriptionBlurMonitor() {
        guard descriptionEditMonitor == nil else { return }
        descriptionEditMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard let window = event.window ?? NSApp.keyWindow,
                  let contentView = window.contentView else { return event }
            let location = contentView.convert(event.locationInWindow, from: nil)
            let clickedView = contentView.hitTest(location)
            // Solo no dismissar si el clic está DENTRO de los bounds de un NSTextView
            if let view = clickedView, isClickInsideTextView(view, locationInContentView: location, contentView: contentView) {
                return event
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .descriptionBlurSave, object: nil)
            }
            return event
        }
    }

    private func isClickInsideTextView(_ clickedView: NSView, locationInContentView: NSPoint, contentView: NSView) -> Bool {
        // Caso 1: el clic fue en el NSTextView o en un subvista suyo
        var v: NSView? = clickedView
        while let current = v {
            if let textView = current as? NSTextView {
                let locInTextView = textView.convert(locationInContentView, from: contentView)
                return textView.bounds.contains(locInTextView)
            }
            v = current.superview
        }
        // Caso 2: el clic fue en un contenedor del editor (ej. NSScrollView) - buscar NSTextView hijos
        if let textView = findTextView(under: clickedView) {
            let locInTextView = textView.convert(locationInContentView, from: contentView)
            return textView.bounds.contains(locInTextView)
        }
        return false
    }

    private func findTextView(under view: NSView) -> NSTextView? {
        if let tv = view as? NSTextView { return tv }
        for subview in view.subviews {
            if let found = findTextView(under: subview) { return found }
        }
        return nil
    }

    private func removeDescriptionBlurMonitor() {
        if let monitor = descriptionEditMonitor {
            NSEvent.removeMonitor(monitor)
            descriptionEditMonitor = nil
        }
    }

    @ViewBuilder
    private func descriptionReadContent(height: CGFloat, includeBackground: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(task.descriptionText ?? "Sin descripción")
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(includeBackground ? (colorScheme == .dark ? AnyShapeStyle(.regularMaterial.opacity(0.5)) : AnyShapeStyle(Color.clear)) : AnyShapeStyle(Color.clear))
                )
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    editableDescription = Self.initialDescriptionMarkdown(for: task)
                    isEditingDescription = true
                }
        }
        .frame(height: height)
    }

    private var hasEdits: Bool {
        editableTitle != task.title || editableDescription != Self.initialDescriptionMarkdown(for: task)
    }

    /// Indica si la tarea no tiene descripción cargada (vacía o nil).
    private func taskHasNoDescription(_ t: TaskItem) -> Bool {
        let hasHTML = (t.descriptionHTML ?? "").isEmpty == false
        let hasADF = (t.descriptionADFJSON ?? "").isEmpty == false
        let hasText = (t.descriptionText ?? "").isEmpty == false
        return !hasHTML && !hasADF && !hasText
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
                Text(isEpic ? "Tareas" : "Subtareas")
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
                        Label(isEpic ? "Agregar tarea" : "Agregar subtarea", systemImage: "plus.circle.fill")
                            .font(.subheadline)
                    }
                    .buttonStyle(.borderless)
                }
            }
            if subs.isEmpty && !isLoadingSubtasks {
                Text(subsRaw.isEmpty
                     ? (isEpic ? "Sin tareas" : "Sin subtareas")
                     : (isEpic ? "Todas las tareas están ocultas por el filtro" : "Todas las subtareas están ocultas por el filtro"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(subs) { sub in
                        Button {
                            onSelectSubtask?(sub)
                        } label: {
                            HStack(spacing: 8) {
                                HStack(spacing: 4) {
                                    Image(systemName: taskStore.issueTypeIcon(for: sub))
                                        .font(.system(size: 11, weight: .bold))
                                    Text(sub.externalId)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }
                                .foregroundStyle(.secondary)
                                .frame(width: 60, alignment: .leading)
                                Text(sub.title)
                                    .font(.body)
                                    .lineLimit(1)
                                Spacer()
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(taskStore.statusColor(for: sub.status))
                                        .frame(width: 10, height: 10)
                                    Text(sub.status)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
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

    private static let checkboxSaveDebounceSeconds: UInt64 = 1_500_000_000

    private func handleCheckboxToggleOptimistic(index: Int) {
        let jsonSource = optimisticDescriptionADF ?? task.descriptionADFJSON
        guard let json = jsonSource,
              let data = json.data(using: .utf8),
              let adf = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modifiedADF = ADFUtils.toggleTaskItem(at: index, in: adf),
              let jsonData = try? JSONSerialization.data(withJSONObject: modifiedADF),
              let jsonStr = String(data: jsonData, encoding: .utf8) else { return }
        optimisticDescriptionADF = jsonStr

        debouncedSaveTask?.cancel()
        let capturedJson = jsonStr
        let capturedTask = task
        debouncedSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.checkboxSaveDebounceSeconds)
            guard !Task.isCancelled else { return }
            guard let j = capturedJson.data(using: .utf8),
                  let a = try? JSONSerialization.jsonObject(with: j) as? [String: Any] else {
                debouncedSaveTask = nil
                return
            }
            let markdown = ADFToMarkdown.convert(adf: a)
            await taskStore.updateTaskInProvider(task: capturedTask, title: nil, description: markdown)
            optimisticDescriptionADF = nil
            debouncedSaveTask = nil
        }
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
    /// interactiveCheckboxes: si true, los checkboxes de taskList son clickeables.
    /// adfOverride: si se proporciona, se usa en lugar de task.descriptionADFJSON (para UI optimista).
    private static func descriptionHTMLForDisplay(task: TaskItem, interactiveCheckboxes: Bool = false, adfOverride: String? = nil) -> String? {
        let jsonSource = adfOverride ?? task.descriptionADFJSON
        if interactiveCheckboxes, let json = jsonSource,
           let data = json.data(using: .utf8),
           let adf = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let baseURL = KeychainHelper.load(key: "jira_url") ?? ""
            return ADFToHTML.convert(adf: adf, baseURL: baseURL, interactiveCheckboxes: true)
        }
        if let html = task.descriptionHTML, !html.isEmpty {
            return html
        }
        if let json = task.descriptionADFJSON,
           let data = json.data(using: .utf8),
           let adf = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let baseURL = KeychainHelper.load(key: "jira_url") ?? ""
            return ADFToHTML.convert(adf: adf, baseURL: baseURL, interactiveCheckboxes: interactiveCheckboxes)
        }
        if let text = task.descriptionText, !text.isEmpty {
            let adf = MarkdownToADF.convert(text)
            let baseURL = KeychainHelper.load(key: "jira_url") ?? ""
            return ADFToHTML.convert(adf: adf, baseURL: baseURL, interactiveCheckboxes: interactiveCheckboxes)
        }
        return nil
    }
}

private extension Notification.Name {
    static let descriptionBlurSave = Notification.Name("descriptionBlurSave")
}
