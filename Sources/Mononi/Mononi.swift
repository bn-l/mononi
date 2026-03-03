import ArgumentParser
import Foundation

@main
struct Mononi: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mononi",
        abstract: "Theme scheduler for macOS — morning, noon, and night",
        version: "0.2.0",
        subcommands: [
            Start.self,
            Stop.self,
            Status.self,
            Apply.self,
            Config_.self,
            Wallpapers.self,
            DaemonCmd.self,
        ]
    )
}

// MARK: - Start

struct Start: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start the mononi daemon"
    )

    func run() async throws {
        try ConfigManager.ensureDefault()

        if LaunchAgent.isRunning() {
            print("mononi is already running")
            return
        }

        try LaunchAgent.install()
        try LaunchAgent.load()
        print("mononi daemon started")
        print("Config: \(ConfigManager.configFile.path)")
        print("Logs:   /tmp/mononi.log")
    }
}

// MARK: - Stop

struct Stop: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Stop the mononi daemon"
    )

    func run() async throws {
        guard LaunchAgent.isInstalled else {
            print("mononi is not installed")
            return
        }
        try LaunchAgent.unload()
        try LaunchAgent.remove()
        print("mononi daemon stopped")
    }
}

// MARK: - Status

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show daemon status and current mode"
    )

    func run() async throws {
        let running = LaunchAgent.isRunning()
        print("Daemon: \(running ? "running" : "stopped")")

        let config = try ConfigManager.load()
        if let mode = config.activeMode() {
            print("Active: \(mode.name) (\(mode.config.appearance), \(mode.config.wallpaper))")
        }
        if let next = config.nextTransition() {
            let fmt = DateFormatter()
            fmt.dateFormat = "HH:mm"
            print("Next:   \(next.name) at \(fmt.string(from: next.fireDate))")
        }
    }
}

// MARK: - Apply (immediately apply current mode without daemon)

struct Apply: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Apply the current mode immediately (no daemon needed)"
    )

    @Option(name: .shortAndLong, help: "Apply a specific mode by name instead of auto-detecting")
    var mode: String?

    func run() async throws {
        let config = try ConfigManager.load()

        if let modeName = mode {
            guard let modeConfig = config.modes[modeName] else {
                throw MononiError.configError("Unknown mode: '\(modeName)'. Available: \(config.modes.keys.sorted().joined(separator: ", "))")
            }
            try applyMode(name: modeName, config: modeConfig)
        } else {
            guard let active = config.activeMode() else {
                throw MononiError.configError("No mode configured for current time")
            }
            try applyMode(name: active.name, config: active.config)
        }
    }

    private func applyMode(name: String, config: ModeConfig) throws {
        print("Applying '\(name)': \(config.appearance), \(config.wallpaper)")
        try ThemeManager.setAppearance(dark: config.appearance == "dark")
        try ThemeManager.setWallpaper(named: config.wallpaper)
        print("Done")
    }
}

// MARK: - Config

struct Config_: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "View or modify configuration",
        subcommands: [ConfigShow.self, ConfigSet.self, ConfigPath.self, ConfigReset.self],
        defaultSubcommand: ConfigShow.self
    )
}

struct ConfigShow: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show current configuration"
    )

    func run() async throws {
        let config = try ConfigManager.load()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        print(String(data: data, encoding: .utf8)!)
    }
}

struct ConfigSet: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Set a mode's properties"
    )

    @Argument(help: "Mode name (e.g. morning, day, evening, night)")
    var modeName: String

    @Option(name: .long, help: "Start time in HH:MM format")
    var time: String?

    @Option(name: .long, help: "Appearance: light or dark")
    var appearance: String?

    @Option(name: .long, help: "Wallpaper name")
    var wallpaper: String?

    func run() async throws {
        var config = try ConfigManager.load()
        var mode = config.modes[modeName] ?? ModeConfig(startTime: "12:00", appearance: "light", wallpaper: "Tahoe Day")

        if let time {
            // Validate time format
            let parts = time.split(separator: ":")
            guard parts.count == 2, Int(parts[0]) != nil, Int(parts[1]) != nil else {
                throw MononiError.configError("Invalid time format: '\(time)'. Use H:MM or HH:MM")
            }
            mode.startTime = time
        }
        if let appearance {
            guard appearance == "light" || appearance == "dark" else {
                throw MononiError.configError("Appearance must be 'light' or 'dark'")
            }
            mode.appearance = appearance
        }
        if let wallpaper {
            mode.wallpaper = wallpaper
        }

        config.modes[modeName] = mode
        try ConfigManager.save(config)
        print("Updated '\(modeName)': time=\(mode.startTime), appearance=\(mode.appearance), wallpaper=\(mode.wallpaper)")
    }
}

struct ConfigPath: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "path",
        abstract: "Print the config file path"
    )

    func run() async throws {
        print(ConfigManager.configFile.path)
    }
}

struct ConfigReset: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reset",
        abstract: "Reset configuration to defaults"
    )

    func run() async throws {
        try ConfigManager.save(.defaultConfig)
        print("Config reset to defaults")
    }
}

// MARK: - Wallpapers

struct Wallpapers: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wallpapers",
        abstract: "List available wallpapers"
    )

    func run() async throws {
        let names = ThemeManager.listAvailableWallpapers()
        for name in names {
            print(name)
        }
        print("\n\(names.count) wallpapers available")
    }
}

// MARK: - Daemon (hidden, invoked by launchd)

struct DaemonCmd: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "daemon",
        shouldDisplay: false
    )

    func run() async throws {
        try await Daemon.run()
    }
}
