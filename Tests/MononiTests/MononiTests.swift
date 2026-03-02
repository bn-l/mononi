import Foundation
import Testing

@testable import mononi

// MARK: - ModeConfig

@Suite("ModeConfig")
struct ModeConfigTests {
    @Test("parses valid HH:MM time")
    func validTime() {
        let mode = ModeConfig(startTime: "14:30", appearance: "dark", wallpaper: "X")
        let c = mode.startComponents
        #expect(c?.hour == 14)
        #expect(c?.minute == 30)
    }

    @Test("parses single-digit hour (H:MM)")
    func singleDigitHour() {
        let mode = ModeConfig(startTime: "6:30", appearance: "light", wallpaper: "X")
        let c = mode.startComponents
        #expect(c?.hour == 6)
        #expect(c?.minute == 30)
    }

    @Test("parses midnight")
    func midnight() {
        let mode = ModeConfig(startTime: "0:00", appearance: "dark", wallpaper: "X")
        let c = mode.startComponents
        #expect(c?.hour == 0)
        #expect(c?.minute == 0)
    }

    @Test("parses 23:59")
    func endOfDay() {
        let mode = ModeConfig(startTime: "23:59", appearance: "dark", wallpaper: "X")
        let c = mode.startComponents
        #expect(c?.hour == 23)
        #expect(c?.minute == 59)
    }

    @Test("returns nil for garbage input")
    func garbageInput() {
        let mode = ModeConfig(startTime: "not-a-time", appearance: "dark", wallpaper: "X")
        #expect(mode.startComponents == nil)
    }

    @Test("returns nil for empty string")
    func emptyString() {
        let mode = ModeConfig(startTime: "", appearance: "dark", wallpaper: "X")
        #expect(mode.startComponents == nil)
    }

    @Test("returns nil for single number")
    func singleNumber() {
        let mode = ModeConfig(startTime: "14", appearance: "dark", wallpaper: "X")
        #expect(mode.startComponents == nil)
    }

    @Test("returns nil for three components")
    func threeComponents() {
        let mode = ModeConfig(startTime: "12:30:45", appearance: "dark", wallpaper: "X")
        #expect(mode.startComponents == nil)
    }
}

// MARK: - Sorted Modes

@Suite("MononiConfig.sortedModes")
struct SortedModesTests {
    @Test("sorts default config by start time ascending")
    func defaultConfigSorting() {
        let sorted = MononiConfig.defaultConfig.sortedModes
        #expect(sorted.count == 4)
        #expect(sorted[0].name == "morning")   // 6:30
        #expect(sorted[1].name == "day")        // 12:00
        #expect(sorted[2].name == "evening")    // 17:30
        #expect(sorted[3].name == "night")      // 21:00
    }

    @Test("filters out modes with invalid times")
    func filtersInvalidModes() {
        let config = MononiConfig(modes: [
            "good": ModeConfig(startTime: "12:00", appearance: "light", wallpaper: "X"),
            "bad": ModeConfig(startTime: "nope", appearance: "dark", wallpaper: "Y"),
        ])
        let sorted = config.sortedModes
        #expect(sorted.count == 1)
        #expect(sorted[0].name == "good")
    }

    @Test("returns empty for config with no valid modes")
    func emptyForAllInvalid() {
        let config = MononiConfig(modes: [
            "a": ModeConfig(startTime: "x", appearance: "light", wallpaper: "X"),
        ])
        #expect(config.sortedModes.isEmpty)
    }

    @Test("handles single mode")
    func singleMode() {
        let config = MononiConfig(modes: [
            "only": ModeConfig(startTime: "15:00", appearance: "dark", wallpaper: "X"),
        ])
        let sorted = config.sortedModes
        #expect(sorted.count == 1)
        #expect(sorted[0].name == "only")
    }
}

// MARK: - Active Mode

@Suite("MononiConfig.activeMode")
struct ActiveModeTests {
    let config = MononiConfig.defaultConfig

    func today(hour: Int, minute: Int) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return Calendar.current.date(from: comps)!
    }

    @Test("returns night before first mode (before 6:30)")
    func beforeFirstMode() {
        let active = config.activeMode(at: today(hour: 3, minute: 0))
        #expect(active?.name == "night")
    }

    @Test("returns morning at exactly 6:30")
    func exactlyMorning() {
        let active = config.activeMode(at: today(hour: 6, minute: 30))
        #expect(active?.name == "morning")
    }

    @Test("returns morning mid-morning")
    func midMorning() {
        let active = config.activeMode(at: today(hour: 9, minute: 15))
        #expect(active?.name == "morning")
    }

    @Test("returns day at exactly noon")
    func exactlyNoon() {
        let active = config.activeMode(at: today(hour: 12, minute: 0))
        #expect(active?.name == "day")
    }

    @Test("returns day in the afternoon")
    func afternoon() {
        let active = config.activeMode(at: today(hour: 15, minute: 0))
        #expect(active?.name == "day")
    }

    @Test("returns evening at 17:30")
    func exactlyEvening() {
        let active = config.activeMode(at: today(hour: 17, minute: 30))
        #expect(active?.name == "evening")
    }

    @Test("returns night at 21:00")
    func exactlyNight() {
        let active = config.activeMode(at: today(hour: 21, minute: 0))
        #expect(active?.name == "night")
    }

    @Test("returns night at 23:59")
    func lateNight() {
        let active = config.activeMode(at: today(hour: 23, minute: 59))
        #expect(active?.name == "night")
    }

    @Test("returns night at midnight")
    func midnight() {
        let active = config.activeMode(at: today(hour: 0, minute: 0))
        #expect(active?.name == "night")
    }

    @Test("returns nil for empty config")
    func emptyConfig() {
        let empty = MononiConfig(modes: [:])
        #expect(empty.activeMode() == nil)
    }

    @Test("single mode is always active")
    func singleModeAlwaysActive() {
        let single = MononiConfig(modes: [
            "always": ModeConfig(startTime: "0:00", appearance: "dark", wallpaper: "X"),
        ])
        #expect(single.activeMode(at: today(hour: 14, minute: 0))?.name == "always")
        #expect(single.activeMode(at: today(hour: 0, minute: 0))?.name == "always")
        #expect(single.activeMode(at: today(hour: 23, minute: 59))?.name == "always")
    }

    @Test("mode at 0:00 is active before any other mode starts")
    func midnightModeActive() {
        let cfg = MononiConfig(modes: [
            "night": ModeConfig(startTime: "0:00", appearance: "dark", wallpaper: "X"),
            "day": ModeConfig(startTime: "8:00", appearance: "light", wallpaper: "Y"),
        ])
        #expect(cfg.activeMode(at: today(hour: 3, minute: 0))?.name == "night")
        #expect(cfg.activeMode(at: today(hour: 8, minute: 0))?.name == "day")
    }

    @Test("one-minute-apart modes resolve correctly")
    func adjacentModes() {
        let cfg = MononiConfig(modes: [
            "a": ModeConfig(startTime: "12:00", appearance: "light", wallpaper: "X"),
            "b": ModeConfig(startTime: "12:01", appearance: "dark", wallpaper: "Y"),
        ])
        #expect(cfg.activeMode(at: today(hour: 12, minute: 0))?.name == "a")
        #expect(cfg.activeMode(at: today(hour: 12, minute: 1))?.name == "b")
    }
}

// MARK: - Next Transition

@Suite("MononiConfig.nextTransition")
struct NextTransitionTests {
    let config = MononiConfig.defaultConfig

    func today(hour: Int, minute: Int) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return Calendar.current.date(from: comps)!
    }

    @Test("next after 3:00 is morning at 6:30")
    func earlyMorning() {
        let next = config.nextTransition(after: today(hour: 3, minute: 0))
        #expect(next?.name == "morning")
        let comps = Calendar.current.dateComponents([.hour, .minute], from: next!.fireDate)
        #expect(comps.hour == 6)
        #expect(comps.minute == 30)
    }

    @Test("next after 6:30 is day at 12:00")
    func afterMorning() {
        let next = config.nextTransition(after: today(hour: 6, minute: 30))
        #expect(next?.name == "day")
    }

    @Test("next after 12:00 is evening at 17:30")
    func afterNoon() {
        let next = config.nextTransition(after: today(hour: 12, minute: 0))
        #expect(next?.name == "evening")
    }

    @Test("next after 21:00 wraps to tomorrow morning")
    func wrapAround() {
        let now = today(hour: 21, minute: 0)
        let next = config.nextTransition(after: now)
        #expect(next?.name == "morning")
        // Fire date should be tomorrow
        let nowDay = Calendar.current.component(.day, from: now)
        let fireDay = Calendar.current.component(.day, from: next!.fireDate)
        #expect(fireDay != nowDay)
        #expect(next!.fireDate > now)
    }

    @Test("next after 23:59 wraps to tomorrow morning")
    func lateNightWrap() {
        let now = today(hour: 23, minute: 59)
        let next = config.nextTransition(after: now)
        #expect(next?.name == "morning")
    }

    @Test("returns nil for empty config")
    func emptyConfig() {
        let empty = MononiConfig(modes: [:])
        #expect(empty.nextTransition() == nil)
    }

    @Test("single mode wraps to itself tomorrow")
    func singleModeWraps() {
        let single = MononiConfig(modes: [
            "only": ModeConfig(startTime: "12:00", appearance: "light", wallpaper: "X"),
        ])
        let now = today(hour: 14, minute: 0)
        let next = single.nextTransition(after: now)
        #expect(next?.name == "only")
        let nowDay = Calendar.current.component(.day, from: now)
        let fireDay = Calendar.current.component(.day, from: next!.fireDate)
        #expect(fireDay != nowDay)
        #expect(next!.fireDate > now)
    }

    @Test("fire date is today when next mode is later today")
    func fireDateIsToday() {
        let now = today(hour: 10, minute: 0)
        let next = config.nextTransition(after: now)
        #expect(next?.name == "day")
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: now)
        let fireComps = Calendar.current.dateComponents([.year, .month, .day], from: next!.fireDate)
        #expect(comps.day == fireComps.day)
    }

    @Test("next transition just before a boundary returns that boundary")
    func justBeforeBoundary() {
        let next = config.nextTransition(after: today(hour: 11, minute: 59))
        #expect(next?.name == "day")
    }
}

// MARK: - Config Serialization

@Suite("Config serialization")
struct ConfigSerializationTests {
    @Test("round-trip encode/decode preserves default config")
    func roundTrip() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(MononiConfig.defaultConfig)
        let decoded = try JSONDecoder().decode(MononiConfig.self, from: data)

        #expect(decoded.modes.count == 4)
        #expect(decoded.modes["morning"]?.startTime == "6:30")
        #expect(decoded.modes["morning"]?.appearance == "light")
        #expect(decoded.modes["morning"]?.wallpaper == "Tahoe Morning")
        #expect(decoded.modes["day"]?.startTime == "12:00")
        #expect(decoded.modes["evening"]?.startTime == "17:30")
        #expect(decoded.modes["evening"]?.appearance == "dark")
        #expect(decoded.modes["night"]?.startTime == "21:00")
        #expect(decoded.modes["night"]?.wallpaper == "Tahoe Night")
    }

    @Test("decodes from raw JSON string")
    func decodesRawJSON() throws {
        let json = """
            {"modes":{"custom":{"startTime":"8:00","appearance":"light","wallpaper":"Test"}}}
            """
        let config = try JSONDecoder().decode(MononiConfig.self, from: json.data(using: .utf8)!)
        #expect(config.modes.count == 1)
        #expect(config.modes["custom"]?.startTime == "8:00")
    }

    @Test("decodes empty modes")
    func decodesEmptyModes() throws {
        let json = """
            {"modes":{}}
            """
        let config = try JSONDecoder().decode(MononiConfig.self, from: json.data(using: .utf8)!)
        #expect(config.modes.isEmpty)
    }
}

// MARK: - ConfigManager (filesystem)

@Suite("ConfigManager")
struct ConfigManagerTests {
    /// Use a temporary directory to avoid touching the real config
    @Test("save and load round-trip")
    func saveLoadRoundTrip() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mononi-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Write directly to a temp path and read back
        let config = MononiConfig(modes: [
            "test": ModeConfig(startTime: "9:00", appearance: "dark", wallpaper: "TestWP"),
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let file = tmpDir.appendingPathComponent("config.json")
        try encoder.encode(config).write(to: file)

        let data = try Data(contentsOf: file)
        let loaded = try JSONDecoder().decode(MononiConfig.self, from: data)
        #expect(loaded.modes["test"]?.startTime == "9:00")
        #expect(loaded.modes["test"]?.wallpaper == "TestWP")
    }
}

// MARK: - Default Config Sanity

@Suite("Default config sanity")
struct DefaultConfigSanityTests {
    @Test("default config has 4 modes")
    func hasFourModes() {
        #expect(MononiConfig.defaultConfig.modes.count == 4)
    }

    @Test("all default modes have valid start times")
    func allTimesValid() {
        for (name, mode) in MononiConfig.defaultConfig.modes {
            #expect(mode.startComponents != nil, "Mode '\(name)' has invalid startTime '\(mode.startTime)'")
        }
    }

    @Test("all default appearances are light or dark")
    func validAppearances() {
        for (name, mode) in MononiConfig.defaultConfig.modes {
            #expect(
                mode.appearance == "light" || mode.appearance == "dark",
                "Mode '\(name)' has invalid appearance '\(mode.appearance)'"
            )
        }
    }

    @Test("default mode times are in chronological order")
    func chronologicalOrder() {
        let sorted = MononiConfig.defaultConfig.sortedModes
        for i in 1..<sorted.count {
            let prev = sorted[i - 1].config.startComponents!
            let curr = sorted[i].config.startComponents!
            let prevMins = prev.hour * 60 + prev.minute
            let currMins = curr.hour * 60 + curr.minute
            #expect(currMins > prevMins, "Mode '\(sorted[i].name)' is not after '\(sorted[i - 1].name)'")
        }
    }

    @Test("morning and day are light, evening and night are dark")
    func lightDarkSplit() {
        let modes = MononiConfig.defaultConfig.modes
        #expect(modes["morning"]?.appearance == "light")
        #expect(modes["day"]?.appearance == "light")
        #expect(modes["evening"]?.appearance == "dark")
        #expect(modes["night"]?.appearance == "dark")
    }

    @Test("each default mode has a distinct Tahoe wallpaper")
    func distinctWallpapers() {
        let wallpapers = MononiConfig.defaultConfig.modes.values.map(\.wallpaper)
        #expect(Set(wallpapers).count == 4)
        for wp in wallpapers {
            #expect(wp.hasPrefix("Tahoe"), "Wallpaper '\(wp)' doesn't start with 'Tahoe'")
        }
    }
}

// MARK: - MononiError

@Suite("MononiError")
struct MononiErrorTests {
    @Test("appleScriptFailed description")
    func appleScript() {
        let err = MononiError.appleScriptFailed("boom")
        #expect(err.description == "AppleScript error: boom")
    }

    @Test("wallpaperNotFound description")
    func wallpaperNotFound() {
        let err = MononiError.wallpaperNotFound("Nope")
        #expect(err.description == "Wallpaper not found: 'Nope'")
    }

    @Test("configError description")
    func configError() {
        let err = MononiError.configError("bad")
        #expect(err.description == "Config error: bad")
    }
}

// MARK: - LaunchAgent constants

@Suite("LaunchAgent")
struct LaunchAgentTests {
    @Test("label is com.mononi.agent")
    func label() {
        #expect(LaunchAgent.label == "com.mononi.agent")
    }

    @Test("plist URL is in ~/Library/LaunchAgents/")
    func plistPath() {
        let path = LaunchAgent.plistURL.path
        #expect(path.contains("Library/LaunchAgents/com.mononi.agent.plist"))
    }
}
