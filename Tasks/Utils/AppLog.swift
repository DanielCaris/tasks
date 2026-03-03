import Foundation
import os.log

/// Logger centralizado para la app. Los errores se escriben a stdout (visible en terminal)
/// y a os_log (persisten en Console.app y Xcode).
enum AppLog {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.tasks.app", category: "Tasks")

    /// Registra un error. Aparece en terminal (make run-attached) y en Console.app.
    static func error(_ message: String, context: String = "") {
        let full = context.isEmpty ? message : "[\(context)] \(message)"
        print("[Tasks] ERROR: \(full)")
        logger.error("\(full, privacy: .public)")
    }

    /// Registra un warning.
    static func warning(_ message: String, context: String = "") {
        let full = context.isEmpty ? message : "[\(context)] \(message)"
        print("[Tasks] WARN: \(full)")
        logger.warning("\(full, privacy: .public)")
    }

    /// Registra info (solo en modo debug).
    static func info(_ message: String, context: String = "") {
        let full = context.isEmpty ? message : "[\(context)] \(message)"
        #if DEBUG
        print("[Tasks] \(full)")
        #endif
        logger.info("\(full, privacy: .public)")
    }
}
