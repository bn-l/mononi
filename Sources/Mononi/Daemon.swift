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
        try await applyCurrentMode(config)

        while !Task.isCancelled {
            logScheduleSummary(config)
            guard let next = config.nextTransition() else {
                logger.warning("No transitions configured, polling until config changes")
                try await pollUntilConfigChanges(&lastMtime)
                config = reloadConfig(fallback: config)
                continue
            }

            logger.info("Next: '\(next.name, privacy: .public)' in \(Int(next.date.timeIntervalSinceNow))s at \(next.clockTime, privacy: .public) (\(next.origin, privacy: .public))")

            // Poll in short intervals, waking on a config change or at the transition time
            var configChanged = false
            while !Task.isCancelled && next.date.timeIntervalSinceNow > 0 {
                try await Task.sleep(for: min(pollInterval, .seconds(next.date.timeIntervalSinceNow)))
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

    /// Logs today's resolved times, which change daily when the stages follow the sun.
    private static func logScheduleSummary(_ config: MononiConfig) {
        let summary = config.transitions(on: .now).map { "\($0.name)@\($0.clockTime) (\($0.origin))" }.joined(separator: ", ")
        logger.info("Schedule (\(config.basis, privacy: .public)): \(summary, privacy: .public)")
        if let active = config.activeMode() {
            logger.info("Active mode: '\(active.name, privacy: .public)' (\(active.mode.appearance, privacy: .public), \(active.mode.wallpaper, privacy: .public))")
        }
    }

    private static func applyCurrentMode(_ config: MononiConfig) async throws {
        guard let active = config.activeMode() else {
            logger.warning("No active mode found for current time")
            return
        }

        logger.info("Applying mode '\(active.name, privacy: .public)': appearance=\(active.mode.appearance, privacy: .public), wallpaper=\(active.mode.wallpaper, privacy: .public)")

        do {
            try await ThemeApplier.apply(appearance: active.mode.appearance, wallpaper: active.mode.wallpaper)
        } catch {
            logger.error("Failed to apply mode '\(active.name, privacy: .public)': \(error, privacy: .public)")
        }
    }
}
