import ArgumentParser
import Foundation

@main
struct Mononi: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mononi",
        abstract: "Theme scheduler for macOS — morning, noon, and night",
        version: "0.5.0",
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

    /// Prints any problems in the config file to stderr before running the command, so every command reports them.
    static func main() async {
        let problems = ConfigManager.problems()
        if !problems.isEmpty {
            fputs("Problems in \(ConfigManager.configFile.path):\n" + problems.map { "  \($0)\n" }.joined(), stderr)
        }
        await main(nil)
    }
}

/// Loads the config for a command, exiting with status 1 when it cannot load. `Mononi.main` has already
/// printed why, so the reason is not printed a second time.
private func loadConfig(_ load: () throws -> MononiConfig = ConfigManager.load) throws -> MononiConfig {
    do {
        return try load()
    } catch MononiError.configError(_) {
        throw ExitCode.failure
    }
}

// MARK: - Start

struct Start: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Start the mononi daemon"
    )

    func run() async throws {
        try ConfigManager.ensureDefault()
        _ = try loadConfig()

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

        let config = try loadConfig()
        print("Schedule: \(config.basis)")
        let today = config.transitions(on: .now)
        let width = today.map(\.name.count).max() ?? 0
        for transition in today {
            print("  \(transition.name.padding(toLength: width, withPad: " ", startingAt: 0))  \(transition.clockTime)  \(transition.origin)")
        }
        if let active = config.activeMode() {
            print("Active: \(active.name) (\(active.mode.appearance), \(active.mode.wallpaper))")
        }
        if let next = config.nextTransition() {
            print("Next:   \(next.name) at \(next.clockTime)")
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
        let config = try loadConfig()

        if let modeName = mode {
            guard let modeConfig = config.modes[modeName] else {
                throw MononiError.configError("Unknown mode: '\(modeName)'. Available: \(config.modes.keys.sorted().joined(separator: ", "))")
            }
            try await applyMode(name: modeName, config: modeConfig)
        } else {
            guard let active = config.activeMode() else {
                throw MononiError.configError("No mode configured for current time")
            }
            try await applyMode(name: active.name, config: active.mode)
        }
    }

    private func applyMode(name: String, config: ModeConfig) async throws {
        print("Applying '\(name)': \(config.appearance), \(config.wallpaper)")
        try await ThemeApplier.apply(appearance: config.appearance, wallpaper: config.wallpaper)
        print("Done")
    }
}

// MARK: - Config

struct Config_: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "View or modify configuration",
        subcommands: [ConfigShow.self, ConfigSet.self, ConfigLocation.self, ConfigPath.self, ConfigReset.self],
        defaultSubcommand: ConfigShow.self
    )
}

struct ConfigShow: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show current configuration"
    )

    func run() async throws {
        let config = try loadConfig(ConfigManager.read)
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

    @Option(name: .long, parsing: .unconditional, help: "Minutes to move the stage from its sun event when a location is set, from -720 to 720; negative is earlier")
    var offset: Int?

    func validate() throws {
        guard offset == nil || MononiConfig.canOffset(modeName) else {
            throw ValidationError("Only morning, day, evening and night can have an offset, so '\(modeName)' cannot have an offset.")
        }
    }

    func run() async throws {
        var config = try loadConfig(ConfigManager.read)
        var mode = config.modes[modeName] ?? ModeConfig(startTime: "12:00", appearance: "light", wallpaper: "Tahoe Day")

        if let time {
            mode.startTime = time
            guard mode.startComponents != nil else {
                throw MononiError.configError("Invalid time: '\(time)'. Use a time from 0:00 to 23:59, such as 6:30 or 18:00")
            }
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
        if let offset {
            mode.offsetMinutes = offset
        }

        config.modes[modeName] = mode
        try ConfigManager.save(config)
        print("Updated '\(modeName)': time=\(mode.startTime ?? "none"), appearance=\(mode.appearance), wallpaper=\(mode.wallpaper), offset=\(mode.offsetMinutes ?? 0) min")
    }
}

struct ConfigLocation: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "location",
        abstract: "Set where to follow the sun from, or show the current location",
        discussion: """
            With a location set, morning starts at sunrise, day at solar noon and evening at civil dusk, each \
            moved by the mode's offset. Night starts at its start time, or 4 hours after evening without one. \
            Other modes keep their fixed start times.
            """
    )

    @Option(name: .long, help: "A city, optionally followed by a region or country, such as \"Newcastle, Australia\"")
    var city: String?

    @Option(name: .long, parsing: .unconditional, help: "Latitude in degrees, from -90 to 90")
    var latitude: Double?

    @Option(name: .long, parsing: .unconditional, help: "Longitude in degrees, from -180 to 180")
    var longitude: Double?

    @Flag(name: .long, help: "Remove the location and use fixed start times")
    var clear = false

    func validate() throws {
        guard (latitude == nil) == (longitude == nil) else {
            throw ValidationError("Give both --latitude and --longitude.")
        }
        guard [city != nil, latitude != nil, clear].filter(\.self).count <= 1 else {
            throw ValidationError("Use only one of --city, --latitude with --longitude, or --clear.")
        }
    }

    func run() async throws {
        var config = try loadConfig(ConfigManager.read)

        if clear {
            config.location = nil
            try ConfigManager.save(config)
            print("Location removed. Modes use their fixed start times.")
        } else if let latitude, let longitude {
            let location = Location(latitude: latitude, longitude: longitude)
            config.location = location
            try ConfigManager.save(config)
            print("Location set to \(location).")
        } else if let city {
            try setCity(city, in: &config)
        } else if let location = config.location {
            print("Location: \(location)")
        } else {
            print("No location is set. Modes use their fixed start times.")
        }
    }

    private func setCity(_ query: String, in config: inout MononiConfig) throws {
        let matches = City.matching(query)
        guard let city = matches.first else { throw MononiError.cityNotFound(query) }

        config.location = city.location
        try ConfigManager.save(config)
        print("Location set to \(city.fullName) (\(city.location)).")

        let others = matches.dropFirst().prefix(3)
        if let other = others.first {
            print("Other matches: \(others.map(\.fullName).joined(separator: "; ")). Add a region or country to choose one, such as \"\(other.name), \(other.country)\".")
        }
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
