import SwiftUI
import SwiftData

@main
struct TasksApp: App {
    private static let sharedModelContainer: ModelContainer = {
        let schema = Schema([TaskItem.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    private static let taskStore = TaskStore(modelContext: sharedModelContainer.mainContext)

    var body: some Scene {
        WindowGroup(id: "main") {
            MainView()
                .modelContainer(Self.sharedModelContainer)
                .environmentObject(Self.taskStore)
        }
        .windowStyle(.automatic)
        .defaultSize(width: 900, height: 600)

        WindowGroup(id: "mini") {
            MiniView()
                .modelContainer(Self.sharedModelContainer)
                .environmentObject(Self.taskStore)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)
        .defaultSize(width: 320, height: 240)
        .windowLevel(.floating)
    }
}
