import SwiftUI
import SwiftData

@main
struct TasksApp: App {
    private static let sharedModelContainer: ModelContainer = {
        let schema = Schema([TaskItem.self])
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeURL = appSupport.appendingPathComponent("default.store")
        let config = ModelConfiguration(url: storeURL)

        func makeContainer() throws -> ModelContainer {
            try ModelContainer(for: schema, configurations: [config])
        }

        do {
            return try makeContainer()
        } catch {
            // Recuperación: si la base de datos está corrupta, eliminar y reintentar
            AppLog.error("ModelContainer falló: \(error.localizedDescription). Intentando recuperar...", context: "TasksApp")
            let storePath = storeURL.path
            try? FileManager.default.removeItem(atPath: storePath + "-shm")
            try? FileManager.default.removeItem(atPath: storePath + "-wal")
            try? FileManager.default.removeItem(at: storeURL)
            do {
                return try makeContainer()
            } catch {
                AppLog.error("Recuperación fallida: \(error.localizedDescription)", context: "TasksApp")
                fatalError("Could not create ModelContainer: \(error)")
            }
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
