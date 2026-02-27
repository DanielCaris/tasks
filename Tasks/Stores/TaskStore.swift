import Foundation
import SwiftData

@MainActor
final class TaskStore: ObservableObject {
    private let modelContext: ModelContext
    private var sortTask: Task<Void, Never>?

    @Published var tasks: [TaskItem] = []
    @Published var selectedStatusFilters: Set<String> = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isMiniViewVisible = false

    private var provider: (any IssueProviderProtocol)?
    private var transitionsCache: [String: [TransitionOption]] = [:]

    /// Tareas filtradas: solo padres (sin parent), y por status si hay filtros.
    var filteredTasks: [TaskItem] {
        let parents = tasks.filter { $0.parentExternalId == nil }
        guard !selectedStatusFilters.isEmpty else { return parents }
        return parents.filter { selectedStatusFilters.contains($0.status) }
    }

    /// Status únicos descubiertos en las tareas actuales.
    var knownStatuses: [String] {
        Array(Set(tasks.map(\.status))).sorted()
    }

    var providerId: String? {
        provider.map { type(of: $0).providerId }
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        selectedStatusFilters = Set(KeychainHelper.loadStatusFilters())
    }

    func setStatusFilters(_ filters: Set<String>) {
        selectedStatusFilters = filters
        KeychainHelper.saveStatusFilters(Array(filters))
    }

    func setProvider(_ provider: any IssueProviderProtocol) {
        self.provider = provider
    }

    func fetchFromProvider() async {
        guard let provider else {
            errorMessage = "No hay proveedor configurado. Configura Jira en Ajustes."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let dtos = try await provider.fetchIssues()
            await mergeWithLocalData(dtos: dtos, providerId: type(of: provider).providerId)
            await loadTasks()
            transitionsCache.removeAll()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
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
        guard let provider else {
            errorMessage = "No hay proveedor configurado. Configura Jira en Ajustes."
            return
        }
        do {
            try await provider.updateIssue(externalId: task.externalId, title: title, description: description)
            if let title {
                task.title = title
            }
            if let description {
                task.descriptionText = description
                task.descriptionHTML = nil  // Tras edición, hasta próxima sync tendremos HTML fresco
            }
            task.lastSyncedAt = Date()
            try? modelContext.save()
        } catch {
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
            errorMessage = error.localizedDescription
            return []
        }
    }

    func invalidateTransitionsCache(for task: TaskItem) {
        transitionsCache.removeValue(forKey: task.taskId)
    }

    func transitionTask(_ task: TaskItem, transitionId: String, newStatus: String) async {
        guard let provider else {
            errorMessage = "No hay proveedor configurado. Configura Jira en Ajustes."
            return
        }
        do {
            try await provider.transitionIssue(externalId: task.externalId, transitionId: transitionId)
            task.status = newStatus
            task.lastSyncedAt = Date()
            invalidateTransitionsCache(for: task)
            try? modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchProjects() async -> [ProjectOption] {
        guard let provider else { return [] }
        do {
            return try await provider.fetchProjects()
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func createTaskInProvider(projectKey: String, title: String, description: String?) async -> TaskItem? {
        guard let provider else {
            errorMessage = "No hay proveedor configurado. Configura Jira en Ajustes."
            return nil
        }
        do {
            let dto = try await provider.createIssue(projectKey: projectKey, title: title, description: description)
            let providerId = type(of: provider).providerId
            await mergeWithLocalData(dtos: [dto], providerId: providerId)
            await loadTasks()
            return tasks.first { $0.externalId == dto.externalId }
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func updatePriority(task: TaskItem, urgency: Int?, impact: Int?, effort: Int?) {
        task.urgency = urgency
        task.impact = impact
        task.effort = effort
        try? modelContext.save()

        sortTask?.cancel()
        sortTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
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
            await mergeWithLocalData(dtos: dtos, providerId: JiraProvider.providerId)
            try? modelContext.save()
            await loadTasks()
            return tasks.filter { $0.parentExternalId == task.externalId }
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    func subtasks(for task: TaskItem) -> [TaskItem] {
        tasks.filter { $0.parentExternalId == task.externalId }
    }
}
