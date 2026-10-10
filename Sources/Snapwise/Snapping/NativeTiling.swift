import Foundation

/// macOS has its own drag-to-edge tiling since macOS 15. Left on, it reacts to the same drags as Snapwise
/// and the two fight over the window.
enum NativeTiling {
    private static let domain = "com.apple.WindowManager"
    private static let keys = ["EnableTilingByEdgeDrag", "EnableTopTilingByEdgeDrag"]

    static var isEnabled: Bool {
        let defaults = UserDefaults(suiteName: domain)
        // A missing key means the system default, which is on.
        return keys.contains { defaults?.object(forKey: $0) as? Bool ?? true }
    }

    /// Same switches as System Settings › Desktop & Dock › "Drag windows to screen edges to tile".
    static func setEnabled(_ enabled: Bool) {
        for key in keys {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            task.arguments = ["write", domain, key, "-bool", enabled ? "true" : "false"]
            try? task.run()
            task.waitUntilExit()
        }
    }
}
