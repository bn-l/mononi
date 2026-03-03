import Foundation
import OSLog

private let logger = Logger(subsystem: "com.mononi", category: "Daemon")

@MainActor
enum Daemon {
    private static let pollInterval: Duration = .seconds(300)

    static func run() async throws {
        logger.info("mononi daemon starting, config: \(ConfigManager.configFile.path, privacy: .public)")

        var lastMtime = configFileMtime()
        logger.info("Initial config mtime: \(lastMtime?.description ?? "nil (using defaults)", privacy: .public)")

        var config = try ConfigManager.load()
        logScheduleSummary(config)
        try await applyCurrentMode(config)

        while !Task.isCancelled {
            guard let next = config.nextTransition() else {
                logger.warning("No transitions configured, polling until config changes")
                try await pollUntilConfigChanges(&lastMtime)
                config = reloadConfig(fallback: config)
                logScheduleSummary(config)
                continue
            }

            logger.info("Next: '\(next.name, privacy: .public)' in \(Int(next.fireDate.timeIntervalSinceNow))s at \(next.config.startTime, privacy: .public)")

            // Poll in short intervals — wake on config change or transition time
            var configChanged = false
            while !Task.isCancelled && next.fireDate.timeIntervalSinceNow > 0 {
                try await Task.sleep(for: pollInterval)
                let currentMtime = configFileMtime()
                if currentMtime != lastMtime {
                    lastMtime = currentMtime
                    logger.info("Config file changed, reloading")
                    configChanged = true
                    break
                }
            }

            if !configChanged {
                logger.info("Scheduled transition reached: '\(next.name, privacy: .public)'")
            }

            config = reloadConfig(fallback: config)
            try await applyCurrentMode(config)
        }
    }

    private static func pollUntilConfigChanges(_ lastMtime: inout Date?) async throws {
        while !Task.isCancelled {
            try await Task.sleep(for: pollInterval)
            let currentMtime = configFileMtime()
            if currentMtime != lastMtime {
                lastMtime = currentMtime
                logger.info("Config file changed, reloading")
                return
            }
        }
    }

    private static func reloadConfig(fallback: MononiConfig) -> MononiConfig {
        do {
            return try ConfigManager.load()
        } catch {
            logger.error("Failed to reload config: \(error, privacy: .public), keeping previous")
            return fallback
        }
    }

    private static func configFileMtime() -> Date? {
        try? FileManager.default.attributesOfItem(
            atPath: ConfigManager.configFile.path
        )[.modificationDate] as? Date
    }

    private static func logScheduleSummary(_ config: MononiConfig) {
        let sorted = config.sortedModes
        let summary = sorted.map { "\($0.name)@\($0.config.startTime)" }.joined(separator: ", ")
        logger.info("Schedule: \(summary, privacy: .public)")
        if let active = config.activeMode() {
            logger.info("Active mode: '\(active.name, privacy: .public)' (\(active.config.appearance, privacy: .public), \(active.config.wallpaper, privacy: .public))")
        }
    }

    private static func applyCurrentMode(_ config: MononiConfig) async throws {
        guard let mode = config.activeMode() else {
            logger.warning("No active mode found for current time")
            return
        }

        logger.info("Applying mode '\(mode.name, privacy: .public)': appearance=\(mode.config.appearance, privacy: .public), wallpaper=\(mode.config.wallpaper, privacy: .public)")

        let isDark = mode.config.appearance == "dark"
        do {
            try ThemeManager.setAppearance(dark: isDark)
        } catch {
            logger.error("Failed to set appearance: \(error, privacy: .public)")
        }

        // Let macOS propagate the appearance change before touching wallpaper state
        try await Task.sleep(for: .seconds(1))

        do {
            try ThemeManager.setWallpaper(named: mode.config.wallpaper)
        } catch {
            logger.error("Failed to set wallpaper: \(error, privacy: .public)")
        }
    }
}
