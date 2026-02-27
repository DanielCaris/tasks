import SwiftUI
import SwiftData

@main
struct TasksApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([TaskItem.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup(id: "main") {
            MainView()
                .modelContainer(sharedModelContainer)
                .environmentObject(TaskStore(modelContext: sharedModelContainer.mainContext))
        }
        .windowStyle(.automatic)
        .defaultSize(width: 900, height: 600)

        WindowGroup(id: "mini") {
            MiniView()
                .modelContainer(sharedModelContainer)
        }
        .windowStyle(.automatic)
        .windowResizability(.contentSize)
        .defaultSize(width: 320, height: 240)
        .windowLevel(.floating)
    }
}
