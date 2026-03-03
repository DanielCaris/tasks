import Foundation
import SwiftData
import SwiftUI

@MainActor
final class TaskStore: ObservableObject {
    private let modelContext: ModelContext
    private var pendingPriorityTasks: [String: Task<Void, Never>] = [:]

    @Published var tasks: [TaskItem] = []
    @Published var selectedStatusFilters: Set<String> = []
    /// Statuses a ocultar en la lista de subtareas. Vacío = mostrar todas.
    @Published var excludedSubtaskStatuses: Set<String> = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isMiniViewVisible = false
    /// Display name del usuario actual en Jira (para ocultar "Asignar a mí" cuando ya está asignado).
    @Published var currentUserDisplayName: String?

    private var provider: (any IssueProviderProtocol)?
    private var transitionsCache: [String: [TransitionOption]] = [:]

    /// Tareas filtradas: solo padres (sin parent), y por status si hay filtros.
    var filteredTasks: [TaskItem] {
        let parents = tasks.filter { $0.parentExternalId == nil }
        guard !selectedStatusFilters.isEmpty else { return parents }
        return parents.filter { selectedStatusFilters.contains($0.status) }
    }

    /// Lista plana para sidebar: padres + subtareas asignadas a mí, ordenada por prioridad.
    var flatSidebarTasks: [TaskItem] {
        let parents = tasks.filter { $0.parentExternalId == nil }
        let subs = tasks.filter { $0.parentExternalId != nil && isAssignedToMe($0) }
        let statusFilter = selectedStatusFilters
        let filteredParents = statusFilter.isEmpty ? parents : parents.filter { statusFilter.contains($0.status) }
        let filteredSubs = statusFilter.isEmpty ? subs : subs.filter { statusFilter.contains($0.status) }
        return (filteredParents + filteredSubs).sorted { $0.priorityScore > $1.priorityScore }
    }

    private func isAssignedToMe(_ task: TaskItem) -> Bool {
        guard let assignee = task.assignee?.trimmingCharacters(in: .whitespaces),
              let current = currentUserDisplayName?.trimmingCharacters(in: .whitespaces),
              !assignee.isEmpty, !current.isEmpty else { return false }
        return assignee.localizedCaseInsensitiveCompare(current) == .orderedSame
    }

    /// Status únicos descubiertos en las tareas actuales.
    var knownStatuses: [String] {
        Array(Set(tasks.map(\.status))).sorted()
    }

    /// Claves de proyecto extraídas de los externalId de las tareas (ej: "PROJ-123" → "PROJ").
    var knownProjectKeys: [String] {
        Array(Set(tasks.compactMap { task in
            task.externalId.split(separator: "-").first.map(String.init)
        })).sorted()
    }

    /// Índice de orden para un status en un proyecto. Mayor índice = va al final.
    func statusSortIndex(for status: String, projectKey: String) -> Int {
        let order = KeychainHelper.loadStatusOrder(projectKey: projectKey)
        return order.firstIndex(of: status) ?? Int.max
    }

    /// Versión de colores; al incrementarse, las vistas que usan statusColor se actualizan.
    @Published private(set) var statusColorsVersion: Int = 0

    /// Color configurado para un estado, o gris por defecto.
    func statusColor(for status: String) -> Color {
        let hex = KeychainHelper.loadStatusColors()[status] ?? "808080"
        return Color(hex: hex)
    }

    func reloadStatusColors() {
        statusColorsVersion += 1
    }

    var providerId: String? {
        provider.map { type(of: $0).providerId }
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        selectedStatusFilters = Set(KeychainHelper.loadStatusFilters())
        excludedSubtaskStatuses = Set(KeychainHelper.loadSubtaskStatusExclusions())
    }

    func setSubtaskStatusExclusions(_ exclusions: Set<String>) {
        excludedSubtaskStatuses = exclusions
        KeychainHelper.saveSubtaskStatusExclusions(Array(exclusions))
    }

    func setStatusFilters(_ filters: Set<String>) {
        selectedStatusFilters = filters
        KeychainHelper.saveStatusFilters(Array(filters))
    }

    func setProvider(_ provider: any IssueProviderProtocol) {
        self.provider = provider
    }

    /// Elimina la caché del display name y fuerza una nueva carga.
    func clearCurrentUserDisplayNameCache() {
        KeychainHelper.deleteCurrentUserDisplayName()
        currentUserDisplayName = nil
        loadCurrentUserDisplayNameIfNeeded()
    }

    /// Carga el display name del usuario actual (Jira). Usa caché si existe y refresca en background.
    func loadCurrentUserDisplayNameIfNeeded() {
        guard provider is JiraProvider else { return }
        // Usar caché inmediatamente para no bloquear la UI
        if let cached = KeychainHelper.loadCurrentUserDisplayName(), !cached.isEmpty {
            currentUserDisplayName = cached
        }
        // Refrescar en background
        Task {
            guard let jira = provider as? JiraProvider else { return }
            if let name = try? await jira.fetchCurrentUserDisplayName(), !name.isEmpty {
                await MainActor.run {
                    currentUserDisplayName = name
                    KeychainHelper.saveCurrentUserDisplayName(name)
                }
            }
        }
    }

    func fetchFromProvider() async {
        guard let provider else {
            let msg = "No hay proveedor configurado. Configura Jira en Ajustes."
            AppLog.error(msg, context: "fetchFromProvider")
            errorMessage = msg
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let dtos = try await provider.fetchIssues()
            await mergeWithLocalData(dtos: dtos, providerId: type(of: provider).providerId)
            await loadTasks()
            transitionsCache.removeAll()
            if let jira = provider as? JiraProvider,
               let name = try? await jira.fetchCurrentUserDisplayName(), !name.isEmpty {
                currentUserDisplayName = name
                KeychainHelper.saveCurrentUserDisplayName(name)
            }
        } catch {
            AppLog.error(error.localizedDescription, context: "fetchFromProvider")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Recarga solo la tarea indicada desde el proveedor (sin actualizar el resto).
    func refreshTask(_ task: TaskItem) async {
        guard let provider else {
            let msg = "No hay proveedor configurado. Configura Jira en Ajustes."
            AppLog.error(msg, context: "refreshTask")
            errorMessage = msg
            return
        }
        do {
            guard let dto = try await provider.fetchIssue(externalId: task.externalId) else { return }
            await mergeWithLocalData(dtos: [dto], providerId: type(of: provider).providerId)
            try? modelContext.save()
            await loadTasks()
        } catch {
            AppLog.error(error.localizedDescription, context: "refreshTask(\(task.externalId))")
            errorMessage = error.localizedDescription
        }
    }

    private func mergeWithLocalData(dtos: [IssueDTO], providerId: String) async {
        for dto in dtos {
            let taskId = "\(providerId):\(dto.externalId)"
            let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate<TaskItem> { $0.taskId == taskId })

            if let existing = try? modelContext.fetch(descriptor).first {
                existing.title = dto.title
                existing.status = dto.status
                existing.assignee = dto.assignee
                existing.descriptionText = dto.description
                existing.descriptionHTML = dto.descriptionHTML
                existing.descriptionADFJSON = dto.descriptionADFJSON
                existing.descriptionMarkdown = nil
                existing.parentExternalId = dto.parentExternalId
                existing.url = dto.url
                existing.priority = dto.priority
                existing.lastSyncedAt = Date()
            } else {
                let task = TaskItem(
                    providerId: providerId,
                    externalId: dto.externalId,
                    title: dto.title,
                    status: dto.status,
                    assignee: dto.assignee,
                    description: dto.description,
                    descriptionHTML: dto.descriptionHTML,
                    descriptionADFJSON: dto.descriptionADFJSON,
                    parentExternalId: dto.parentExternalId,
                    url: dto.url,
                    priority: dto.priority
                )
                modelContext.insert(task)
            }
        }
        try? modelContext.save()
    }

    func loadTasks() async {
        let descriptor = FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.taskId)])
        tasks = (try? modelContext.fetch(descriptor)) ?? []
        sortByPriority()
    }

    func sortByPriority() {
        tasks.sort { $0.priorityScore > $1.priorityScore }
    }

    func updateTaskInProvider(task: TaskItem, title: String?, description: String?) async {
        errorMessage = nil
        print("[Tasks] updateTaskInProvider: \(task.externalId), title=\(title != nil), desc=\(description != nil)")
        guard let provider else {
            let msg = "No hay proveedor configurado. Configura Jira en Ajustes."
            AppLog.error(msg, context: "updateTaskInProvider")
            errorMessage = msg
            return
        }
        do {
            // Convertir Markdown→ADF; si hay ADF original, preservar nodos media (imágenes de Jira)
            let originalADF: [String: Any]? = task.descriptionADFJSON.flatMap { json in
                (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
            }
            let descriptionADF: Any? = description.map { MarkdownToADF.convert($0, originalADF: originalADF) }
            print("[Tasks] updateTaskInProvider: llamando provider.updateIssue...")
            let adfSent = try await provider.updateIssue(externalId: task.externalId, title: title, description: descriptionADF)
            print("[Tasks] updateTaskInProvider: API OK, actualizando modelo local")
            if let title {
                task.title = title
            }
            if let description {
                task.descriptionText = description
                task.descriptionMarkdown = description
                if let adf = adfSent,
                   let jsonData = try? JSONSerialization.data(withJSONObject: adf),
                   let jsonStr = String(data: jsonData, encoding: .utf8) {
                    task.descriptionADFJSON = jsonStr
                } else {
                    task.descriptionHTML = nil
                    task.descriptionADFJSON = nil
                }
            }
            // Re-fetch el issue para obtener descriptionHTML con imágenes resueltas (attachmentMap, signed URLs).
            // ADFToHTML sin esos datos genera jira-image://uuid que falla (la API espera attachment ID numérico).
            // Importante: preservar description que acabamos de enviar; el GET puede devolver datos stale por latencia.
            let savedMarkdown = task.descriptionMarkdown
            let savedADF = task.descriptionADFJSON
            let savedText = task.descriptionText
            if let dto = try? await provider.fetchIssue(externalId: task.externalId) {
                await mergeWithLocalData(dtos: [dto], providerId: type(of: provider).providerId)
                task.descriptionMarkdown = savedMarkdown
                task.descriptionADFJSON = savedADF
                task.descriptionText = savedText
            }
            task.lastSyncedAt = Date()
            try? modelContext.save()
            print("[Tasks] updateTaskInProvider: guardado completado")
        } catch {
            AppLog.error(error.localizedDescription, context: "updateTaskInProvider(\(task.externalId))")
            errorMessage = error.localizedDescription
        }
    }

    func getTransitions(for task: TaskItem) async -> [TransitionOption] {
        guard let provider else { return [] }
        let key = task.taskId
        if let cached = transitionsCache[key] {
            return cached
        }
        do {
            let transitions = try await provider.getTransitions(externalId: task.externalId)
            transitionsCache[key] = transitions
            return transitions
        } catch {
            AppLog.error(error.localizedDescription, context: "getTransitions(\(task.externalId))")
            errorMessage = error.localizedDescription
            return []
        }
    }

    func invalidateTransitionsCache(for task: TaskItem) {
        transitionsCache.removeValue(forKey: task.taskId)
    }

    func transitionTask(_ task: TaskItem, transitionId: String, newStatus: String) async {
        guard let provider else {
            let msg = "No hay proveedor configurado. Configura Jira en Ajustes."
            AppLog.error(msg, context: "transitionTask")
            errorMessage = msg
            return
        }
        do {
            try await provider.transitionIssue(externalId: task.externalId, transitionId: transitionId)
            task.status = newStatus
            task.lastSyncedAt = Date()
            invalidateTransitionsCache(for: task)
            try? modelContext.save()
        } catch {
            AppLog.error(error.localizedDescription, context: "transitionTask(\(task.externalId))")
            errorMessage = error.localizedDescription
        }
    }

    func fetchProjects() async -> [ProjectOption] {
        guard let provider else { return [] }
        do {
            return try await provider.fetchProjects()
        } catch {
            AppLog.error(error.localizedDescription, context: "fetchProjects")
            errorMessage = error.localizedDescription
            return []
        }
    }

    func createTaskInProvider(projectKey: String, title: String, description: String?) async -> TaskItem? {
        guard let provider else {
            let msg = "No hay proveedor configurado. Configura Jira en Ajustes."
            AppLog.error(msg, context: "createTaskInProvider")
            errorMessage = msg
            return nil
        }
        do {
            let dto = try await provider.createIssue(projectKey: projectKey, title: title, description: description)
            let providerId = type(of: provider).providerId
            await mergeWithLocalData(dtos: [dto], providerId: providerId)
            await loadTasks()
            return tasks.first { $0.externalId == dto.externalId }
        } catch {
            AppLog.error(error.localizedDescription, context: "createTaskInProvider")
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func createSubtask(for parentTask: TaskItem, title: String, description: String?) async -> TaskItem? {
        guard let provider else {
            let msg = "No hay proveedor configurado. Configura Jira en Ajustes."
            AppLog.error(msg, context: "createSubtask")
            errorMessage = msg
            return nil
        }
        do {
            guard let dto = try await provider.createSubtask(parentExternalId: parentTask.externalId, title: title, description: description) else {
                let msg = "Este proveedor no soporta crear subtareas."
                AppLog.error(msg, context: "createSubtask")
                errorMessage = msg
                return nil
            }
            let providerId = type(of: provider).providerId
            await mergeWithLocalData(dtos: [dto], providerId: providerId)
            try? modelContext.save()
            await loadTasks()
            return tasks.first { $0.externalId == dto.externalId }
        } catch {
            AppLog.error(error.localizedDescription, context: "createSubtask(parent:\(parentTask.externalId))")
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func updatePriority(task: TaskItem, urgency: Int?, impact: Int?, effort: Int?) {
        let taskId = task.taskId
        let u = urgency
        let i = impact
        let e = effort

        pendingPriorityTasks[taskId]?.cancel()
        pendingPriorityTasks[taskId] = Task {
            try? await Task.sleep(for: .milliseconds(1000))
            guard !Task.isCancelled else { return }
            pendingPriorityTasks.removeValue(forKey: taskId)
            task.urgency = u
            task.impact = i
            task.effort = e
            try? modelContext.save()
            sortByPriority()
        }
    }

    func topTasks(limit: Int = 5) -> [TaskItem] {
        Array(filteredTasks.prefix(limit))
    }

    func toggleMiniView() {
        isMiniViewVisible.toggle()
    }

    func fetchSubtasks(for task: TaskItem) async -> [TaskItem] {
        guard let provider = provider as? JiraProvider else { return [] }
        do {
            let dtos = try await provider.fetchSubtasks(parentKey: task.externalId)
            let existingIds = Set(tasks.map(\.taskId))
            await mergeWithLocalData(dtos: dtos, providerId: JiraProvider.providerId)
            try? modelContext.save()
            // Añadir solo las nuevas subtareas al array, sin reemplazar todo.
            // Evita que loadTasks() cause que el parent desaparezca del sidebar.
            let parentId = task.externalId
            let descriptor = FetchDescriptor<TaskItem>(
                predicate: #Predicate<TaskItem> { $0.parentExternalId == parentId },
                sortBy: [SortDescriptor(\.taskId)]
            )
            let newSubtasks = (try? modelContext.fetch(descriptor)) ?? []
            for sub in newSubtasks where !existingIds.contains(sub.taskId) {
                tasks.append(sub)
            }
            sortByPriority()
            return tasks.filter { $0.parentExternalId == task.externalId }
        } catch {
            AppLog.error(error.localizedDescription, context: "fetchSubtasks(\(task.externalId))")
            errorMessage = error.localizedDescription
            return []
        }
    }

    func subtasks(for task: TaskItem) -> [TaskItem] {
        tasks.filter { $0.parentExternalId == task.externalId }
    }

    /// Subtareas asignadas al usuario actual y que cumplen los filtros de estado.
    func subtasksAssignedToMe(for task: TaskItem) -> [TaskItem] {
        let subs = subtasks(for: task)
        guard let current = currentUserDisplayName?.trimmingCharacters(in: .whitespaces),
              !current.isEmpty else { return [] }
        var result = subs.filter { sub in
            guard let assignee = sub.assignee?.trimmingCharacters(in: .whitespaces),
                  !assignee.isEmpty else { return false }
            return assignee.localizedCaseInsensitiveCompare(current) == .orderedSame
        }
        if !selectedStatusFilters.isEmpty {
            result = result.filter { selectedStatusFilters.contains($0.status) }
        }
        return result
    }

    /// Todas las subtareas asignadas a mí (de cualquier padre), con filtros de estado.
    func allSubtasksAssignedToMe() -> [TaskItem] {
        let subs = tasks.filter { $0.parentExternalId != nil }
        guard let current = currentUserDisplayName?.trimmingCharacters(in: .whitespaces),
              !current.isEmpty else { return [] }
        var result = subs.filter { sub in
            guard let assignee = sub.assignee?.trimmingCharacters(in: .whitespaces),
                  !assignee.isEmpty else { return false }
            return assignee.localizedCaseInsensitiveCompare(current) == .orderedSame
        }
        if !selectedStatusFilters.isEmpty {
            result = result.filter { selectedStatusFilters.contains($0.status) }
        }
        return result
    }

    /// Asigna la tarea al usuario actual en Jira. Solo soportado por JiraProvider.
    func assignToMe(_ task: TaskItem) async {
        guard let provider = provider as? JiraProvider else {
            errorMessage = "Asignar a mí solo está disponible con Jira."
            return
        }
        do {
            try await provider.assignToMe(issueKey: task.externalId)
            await refreshTask(task)
        } catch {
            AppLog.error(error.localizedDescription, context: "assignToMe(\(task.externalId))")
            errorMessage = error.localizedDescription
        }
    }

    func deleteSubtask(_ subtask: TaskItem) async {
        guard let provider else {
            let msg = "No hay proveedor configurado. Configura Jira en Ajustes."
            AppLog.error(msg, context: "deleteSubtask")
            errorMessage = msg
            return
        }
        let parentExternalId = subtask.parentExternalId
        let externalId = subtask.externalId
        // UI optimista: eliminar localmente primero
        modelContext.delete(subtask)
        try? modelContext.save()
        await loadTasks()
        // Luego borrar en el proveedor; si falla, re-sincronizar
        do {
            guard try await provider.deleteIssue(externalId: externalId) else { return }
        } catch {
            AppLog.error(error.localizedDescription, context: "deleteSubtask(\(externalId))")
            errorMessage = error.localizedDescription
            if let parentId = parentExternalId,
               let parent = tasks.first(where: { $0.externalId == parentId }) {
                _ = await fetchSubtasks(for: parent)
            }
        }
    }
}
