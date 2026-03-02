import Foundation
import OSLog

private let logger = Logger(subsystem: "com.mononi", category: "Daemon")

@MainActor
enum Daemon {
    static func run() async throws {
        logger.info("mononi daemon starting")

        let config = try ConfigManager.load()
        try applyCurrentMode(config)

        // Schedule transitions in a loop
        while !Task.isCancelled {
            let config = try ConfigManager.load()
            guard let next = config.nextTransition() else {
                logger.error("No transitions configured, sleeping 1h")
                try await Task.sleep(for: .seconds(3600))
                continue
            }

            let delay = next.fireDate.timeIntervalSinceNow
            if delay > 0 {
                logger.info("Next: '\(next.name, privacy: .public)' in \(Int(delay))s at \(next.config.startTime, privacy: .public)")
                try await Task.sleep(for: .seconds(delay))
            }

            // Re-read config in case it changed while sleeping
            let freshConfig = try ConfigManager.load()
            try applyCurrentMode(freshConfig)
        }
    }

    private static func applyCurrentMode(_ config: MononiConfig) throws {
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

        do {
            try ThemeManager.setWallpaper(named: mode.config.wallpaper)
        } catch {
            logger.error("Failed to set wallpaper: \(error, privacy: .public)")
        }
    }
}
