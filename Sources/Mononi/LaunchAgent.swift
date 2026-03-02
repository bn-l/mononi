import Foundation

enum LaunchAgent {
    static let label = "com.mononi.agent"

    static let plistURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }()

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static var executablePath: String {
        ProcessInfo.processInfo.arguments[0]
    }

    static func install() throws {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath, "daemon"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardOutPath": "/tmp/mononi.log",
            "StandardErrorPath": "/tmp/mononi.err",
        ]

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0
        )

        let dir = plistURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: plistURL)
    }

    static func load() throws {
        let task = Process()
        task.executableURL = URL(filePath: "/bin/launchctl")
        task.arguments = ["load", plistURL.path]
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw MononiError.configError("launchctl load failed with status \(task.terminationStatus)")
        }
    }

    static func unload() throws {
        let task = Process()
        task.executableURL = URL(filePath: "/bin/launchctl")
        task.arguments = ["unload", plistURL.path]
        try task.run()
        task.waitUntilExit()
        // Don't check status — unload fails if not loaded, which is fine
    }

    static func remove() throws {
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    static func isRunning() -> Bool {
        let task = Process()
        task.executableURL = URL(filePath: "/bin/launchctl")
        task.arguments = ["list", label]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try? task.run()
        task.waitUntilExit()
        return task.terminationStatus == 0
    }
}
