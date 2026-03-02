import Foundation

struct ModeConfig: Codable, Sendable {
    var startTime: String
    var appearance: String
    var wallpaper: String

    var startComponents: (hour: Int, minute: Int)? {
        let parts = startTime.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]),
              let m = Int(parts[1]) else { return nil }
        return (h, m)
    }
}

struct MononiConfig: Codable, Sendable {
    var modes: [String: ModeConfig]

    static let defaultConfig = MononiConfig(
        modes: [
            "morning": ModeConfig(startTime: "6:30", appearance: "light", wallpaper: "Tahoe Morning"),
            "day": ModeConfig(startTime: "12:00", appearance: "light", wallpaper: "Tahoe Day"),
            "evening": ModeConfig(startTime: "17:30", appearance: "dark", wallpaper: "Tahoe Evening"),
            "night": ModeConfig(startTime: "21:00", appearance: "dark", wallpaper: "Tahoe Night"),
        ]
    )

    /// Modes sorted by start time ascending
    var sortedModes: [(name: String, config: ModeConfig)] {
        modes.compactMap { name, config in
            guard config.startComponents != nil else { return nil }
            return (name, config)
        }
        .sorted {
            let a = $0.config.startComponents!
            let b = $1.config.startComponents!
            return a.hour * 60 + a.minute < b.hour * 60 + b.minute
        }
    }

    /// Which mode should be active right now?
    func activeMode(at date: Date = .now) -> (name: String, config: ModeConfig)? {
        let cal = Calendar.current
        let nowMinutes = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        let sorted = sortedModes
        guard !sorted.isEmpty else { return nil }

        // Walk backwards — find the latest mode whose start time <= now
        var active = sorted.last!
        for mode in sorted {
            let c = mode.config.startComponents!
            if c.hour * 60 + c.minute <= nowMinutes {
                active = mode
            }
        }
        return active
    }

    /// Next mode transition time after `date`, returns (mode, fire date)
    func nextTransition(after date: Date = .now) -> (name: String, config: ModeConfig, fireDate: Date)? {
        let cal = Calendar.current
        let nowMinutes = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        let sorted = sortedModes
        guard !sorted.isEmpty else { return nil }

        // Find the next mode whose start time is after now
        for mode in sorted {
            let c = mode.config.startComponents!
            let modeMinutes = c.hour * 60 + c.minute
            if modeMinutes > nowMinutes {
                var comps = cal.dateComponents([.year, .month, .day], from: date)
                comps.hour = c.hour
                comps.minute = c.minute
                comps.second = 0
                if let fireDate = cal.date(from: comps) {
                    return (mode.name, mode.config, fireDate)
                }
            }
        }

        // Wrap around to tomorrow's first mode
        let first = sorted.first!
        let c = first.config.startComponents!
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        comps.hour = c.hour
        comps.minute = c.minute
        comps.second = 0
        if let tomorrow = cal.date(from: comps).flatMap({ cal.date(byAdding: .day, value: 1, to: $0) }) {
            return (first.name, first.config, tomorrow)
        }
        return nil
    }
}

enum ConfigManager {
    static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/mononi")
    static let configFile = configDir.appendingPathComponent("config.json")

    static func load() throws -> MononiConfig {
        guard FileManager.default.fileExists(atPath: configFile.path) else {
            return .defaultConfig
        }
        let data = try Data(contentsOf: configFile)
        return try JSONDecoder().decode(MononiConfig.self, from: data)
    }

    static func save(_ config: MononiConfig) throws {
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configFile)
    }

    static func ensureDefault() throws {
        guard !FileManager.default.fileExists(atPath: configFile.path) else { return }
        try save(.defaultConfig)
    }
}
