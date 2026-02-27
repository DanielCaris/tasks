import Foundation
import SwiftData

@MainActor
final class TaskStore: ObservableObject {
    private let modelContext: ModelContext
    private var sortTask: Task<Void, Never>?

    @Published var tasks: [TaskItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isMiniViewVisible = false

    private var provider: (any IssueProviderProtocol)?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
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
        Array(tasks.prefix(limit))
    }

    func toggleMiniView() {
        isMiniViewVisible.toggle()
    }
}
