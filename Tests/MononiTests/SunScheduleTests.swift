import Foundation
import Testing

@testable import mononi

// MARK: - Helpers

/// A Gregorian calendar in a named time zone, so a test does not depend on the machine's zone.
func calendar(_ zone: String) throws -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: zone), "Unknown time zone \(zone)")
    return calendar
}

/// The instant at `time` (H:mm or H:mm:ss) on `day` (yyyy-MM-dd) in `calendar`'s time zone.
func instant(_ day: String, _ time: String = "12:00", in calendar: Calendar) throws -> Date {
    let d = day.split(separator: "-").map { Int($0)! }
    let t = time.split(separator: ":").map { Int($0)! }
    let components = DateComponents(year: d[0], month: d[1], day: d[2], hour: t[0], minute: t[1], second: t.count > 2 ? t[2] : 0)
    return try #require(calendar.date(from: components))
}

/// The default modes following the sun at `location`, with optional offsets by mode name.
func sunConfig(_ location: Location, offsets: [String: Int] = [:]) -> MononiConfig {
    var config = MononiConfig.defaultConfig
    config.location = location
    for (name, offset) in offsets {
        config.modes[name]?.offsetMinutes = offset
    }
    return config
}

let sydney = Location(latitude: -33.8688, longitude: 151.2093)
let london = Location(latitude: 51.5074, longitude: -0.1278)

extension [Transition] {
    func named(_ name: String) throws -> Transition {
        try #require(first { $0.name == name }, "No transition for '\(name)' in \(map(\.name))")
    }
}

// MARK: - Reference times

/// Sun times from Python's astral library (NOAA algorithm), in the city's local time.
struct SunReference: Sendable, CustomTestStringConvertible {
    let city: String
    let latitude: Double
    let longitude: Double
    let zone: String
    let day: String
    let sunrise: String
    let noon: String
    let sunset: String
    let dusk: String

    init(_ city: String, _ latitude: Double, _ longitude: Double, _ zone: String, _ day: String,
         sunrise: String, noon: String, sunset: String, dusk: String) {
        (self.city, self.latitude, self.longitude, self.zone, self.day) = (city, latitude, longitude, zone, day)
        (self.sunrise, self.noon, self.sunset, self.dusk) = (sunrise, noon, sunset, dusk)
    }

    var testDescription: String { "\(city) \(day)" }
}

@Suite("Sun schedule matches reference times")
struct SunReferenceTests {
    static let references = [
        SunReference("Sydney", -33.8688, 151.2093, "Australia/Sydney", "2026-03-28", sunrise: "07:04:13", noon: "13:00:20", sunset: "18:55:53", dusk: "19:21:14"),
        SunReference("Sydney", -33.8688, 151.2093, "Australia/Sydney", "2026-03-29", sunrise: "07:04:58", noon: "13:00:02", sunset: "18:54:32", dusk: "19:19:53"),
        SunReference("Sydney", -33.8688, 151.2093, "Australia/Sydney", "2026-06-21", sunrise: "07:00:11", noon: "11:56:52", sunset: "16:53:35", dusk: "17:21:51"),
        SunReference("Sydney", -33.8688, 151.2093, "Australia/Sydney", "2026-10-15", sunrise: "06:14:33", noon: "12:41:01", sunset: "19:08:01", dusk: "19:34:03"),
        SunReference("Sydney", -33.8688, 151.2093, "Australia/Sydney", "2026-10-25", sunrise: "06:02:39", noon: "12:39:15", sunset: "19:16:21", dusk: "19:42:55"),
        SunReference("Sydney", -33.8688, 151.2093, "Australia/Sydney", "2026-12-21", sunrise: "05:40:53", noon: "12:52:59", sunset: "20:05:11", dusk: "20:34:54"),
        SunReference("Auckland", -36.8485, 174.7633, "Pacific/Auckland", "2026-03-28", sunrise: "07:30:42", noon: "13:26:07", sunset: "19:20:57", dusk: "19:47:15"),
        SunReference("Auckland", -36.8485, 174.7633, "Pacific/Auckland", "2026-03-29", sunrise: "07:31:34", noon: "13:25:49", sunset: "19:19:29", dusk: "19:45:48"),
        SunReference("Auckland", -36.8485, 174.7633, "Pacific/Auckland", "2026-06-21", sunrise: "07:33:55", noon: "12:22:39", sunset: "17:11:24", dusk: "17:40:56"),
        SunReference("Auckland", -36.8485, 174.7633, "Pacific/Auckland", "2026-10-15", sunrise: "06:37:37", noon: "13:06:48", sunset: "19:36:37", dusk: "20:03:41"),
        SunReference("Auckland", -36.8485, 174.7633, "Pacific/Auckland", "2026-10-25", sunrise: "06:24:32", noon: "13:05:02", sunset: "19:46:09", dusk: "20:13:50"),
        SunReference("Auckland", -36.8485, 174.7633, "Pacific/Auckland", "2026-12-21", sunrise: "05:58:15", noon: "13:18:46", sunset: "20:39:19", dusk: "21:10:42"),
        SunReference("Honolulu", 21.3069, -157.8583, "Pacific/Honolulu", "2026-03-28", sunrise: "06:28:03", noon: "12:36:36", sunset: "18:44:55", dusk: "19:07:37"),
        SunReference("Honolulu", 21.3069, -157.8583, "Pacific/Honolulu", "2026-03-29", sunrise: "06:27:08", noon: "12:36:18", sunset: "18:45:14", dusk: "19:07:56"),
        SunReference("Honolulu", 21.3069, -157.8583, "Pacific/Honolulu", "2026-06-21", sunrise: "05:50:36", noon: "12:33:08", sunset: "19:16:05", dusk: "19:41:26"),
        SunReference("Honolulu", 21.3069, -157.8583, "Pacific/Honolulu", "2026-10-15", sunrise: "06:27:23", noon: "12:17:18", sunset: "18:06:30", dusk: "18:29:20"),
        SunReference("Honolulu", 21.3069, -157.8583, "Pacific/Honolulu", "2026-10-25", sunrise: "06:31:25", noon: "12:15:31", sunset: "17:59:08", dusk: "18:22:15"),
        SunReference("Honolulu", 21.3069, -157.8583, "Pacific/Honolulu", "2026-12-21", sunrise: "07:04:48", noon: "12:29:15", sunset: "17:54:38", dusk: "18:19:22"),
        SunReference("London", 51.5074, -0.1278, "Europe/London", "2026-03-28", sunrise: "05:45:24", noon: "12:05:41", sunset: "18:26:43", dusk: "19:01:06"),
        SunReference("London", 51.5074, -0.1278, "Europe/London", "2026-03-29", sunrise: "06:43:07", noon: "13:05:23", sunset: "19:28:24", dusk: "20:02:50"),
        SunReference("London", 51.5074, -0.1278, "Europe/London", "2026-06-21", sunrise: "04:43:27", noon: "13:02:13", sunset: "21:21:12", dusk: "22:09:54"),
        SunReference("London", 51.5074, -0.1278, "Europe/London", "2026-10-15", sunrise: "07:24:38", noon: "12:46:22", sunset: "18:07:02", dusk: "18:41:20"),
        SunReference("London", 51.5074, -0.1278, "Europe/London", "2026-10-25", sunrise: "06:41:52", noon: "11:44:36", sunset: "16:46:25", dusk: "17:21:31"),
        SunReference("London", 51.5074, -0.1278, "Europe/London", "2026-12-21", sunrise: "08:04:06", noon: "11:58:20", sunset: "15:53:03", dusk: "16:34:10"),
        SunReference("Edinburgh", 55.9533, -3.1883, "Europe/London", "2026-03-28", sunrise: "05:54:22", noon: "12:17:56", sunset: "18:42:25", dusk: "19:20:49"),
        SunReference("Edinburgh", 55.9533, -3.1883, "Europe/London", "2026-03-29", sunrise: "06:51:44", noon: "13:17:37", sunset: "19:44:27", dusk: "20:22:57"),
        SunReference("Edinburgh", 55.9533, -3.1883, "Europe/London", "2026-06-21", sunrise: "04:26:43", noon: "13:14:28", sunset: "22:02:25", dusk: "23:06:10"),
        SunReference("Edinburgh", 55.9533, -3.1883, "Europe/London", "2026-10-15", sunrise: "07:44:06", noon: "12:58:37", sunset: "18:11:54", dusk: "18:50:08"),
        SunReference("Edinburgh", 55.9533, -3.1883, "Europe/London", "2026-10-25", sunrise: "07:04:55", noon: "11:56:50", sunset: "16:47:44", dusk: "17:27:03"),
        SunReference("Edinburgh", 55.9533, -3.1883, "Europe/London", "2026-12-21", sunrise: "08:42:29", noon: "12:10:34", sunset: "15:39:09", dusk: "16:27:27"),
    ]

    // Auckland is UTC+13 in its summer. If the local date were not converted to Solar's UTC day,
    // its stages would land a whole day early and these comparisons would be off by 86,400 s.
    @Test("each stage starts within 3 minutes of its reference sun time", arguments: references)
    func matchesReference(_ reference: SunReference) throws {
        // Arrange
        let cal = try calendar(reference.zone)
        let config = sunConfig(Location(latitude: reference.latitude, longitude: reference.longitude))

        // Act
        let today = config.transitions(on: try instant(reference.day, in: cal), calendar: cal)

        // Assert
        for (name, time) in [("morning", reference.sunrise), ("day", reference.noon), ("evening", reference.sunset), ("night", reference.dusk)] {
            let transition = try today.named(name)
            #expect(transition.source == .sun(SolarStage(rawValue: name)!))
            let error = abs(transition.date.timeIntervalSince(try instant(reference.day, time, in: cal)))
            #expect(error <= 180, "\(name) starts \(Int(error)) s from the reference \(time)")
        }
    }
}

// MARK: - DST

struct DSTChange: Sendable, CustomTestStringConvertible {
    let zone: String
    let location: Location
    let before: String
    let after: String
    /// How far the local clock time of sunset moves, in minutes.
    let clockShift: Int

    var testDescription: String { "\(zone) \(before) to \(after)" }
}

@Suite("Sun schedule across DST changes")
struct SunDSTTests {
    static let changes = [
        DSTChange(zone: "Europe/London", location: london, before: "2026-03-28", after: "2026-03-29", clockShift: 60),
        DSTChange(zone: "Europe/London", location: london, before: "2026-10-24", after: "2026-10-25", clockShift: -60),
        DSTChange(zone: "Australia/Sydney", location: sydney, before: "2026-04-04", after: "2026-04-05", clockShift: -60),
        DSTChange(zone: "Australia/Sydney", location: sydney, before: "2026-10-03", after: "2026-10-04", clockShift: 60),
    ]

    @Test("local sunset moves by an hour while the instant moves by a few minutes", arguments: changes)
    func sunsetAcrossChange(_ change: DSTChange) throws {
        // Arrange
        let cal = try calendar(change.zone)
        let config = sunConfig(change.location)

        // Act
        let first = try config.transitions(on: try instant(change.before, in: cal), calendar: cal).named("evening")
        let second = try config.transitions(on: try instant(change.after, in: cal), calendar: cal).named("evening")

        // Assert
        func clockMinutes(_ date: Date) -> Int {
            let c = cal.dateComponents([.hour, .minute], from: date)
            return c.hour! * 60 + c.minute!
        }
        let clockMove = clockMinutes(second.date) - clockMinutes(first.date)
        #expect(abs(clockMove - change.clockShift) <= 5, "Local sunset moved \(clockMove) min")
        let instantMove = second.date.timeIntervalSince(first.date) - 86_400
        #expect(abs(instantMove) <= 300, "Sunset moved \(Int(instantMove)) s beyond a day")
    }

    @Test("the night the clocks go forward, night stays active and morning comes at that day's sunrise")
    func acrossSpringForward() throws {
        // Arrange
        let cal = try calendar("Europe/London")
        let config = sunConfig(london)
        let beforeChange = try instant("2026-03-29", "00:30", in: cal) // 01:00 GMT becomes 02:00 BST

        // Act
        let active = config.activeMode(at: beforeChange, calendar: cal)
        let next = try #require(config.nextTransition(after: beforeChange, calendar: cal))

        // Assert
        #expect(active?.name == "night")
        #expect(next.name == "morning")
        #expect(next.date == (try config.transitions(on: beforeChange, calendar: cal).named("morning")).date)
        #expect(cal.component(.hour, from: next.date) == 6, "Sunrise on 2026-03-29 is at 06:43 BST")
    }

    @Test("the night the clocks go back, morning comes at that day's sunrise")
    func acrossFallBack() throws {
        // Arrange
        let cal = try calendar("Australia/Sydney")
        let config = sunConfig(sydney)
        let beforeChange = try instant("2026-04-05", "01:30", in: cal) // 03:00 AEDT becomes 02:00 AEST

        // Act
        let next = try #require(config.nextTransition(after: beforeChange, calendar: cal))

        // Assert
        #expect(next.name == "morning")
        #expect(next.date == (try config.transitions(on: beforeChange, calendar: cal).named("morning")).date)
        #expect(cal.component(.hour, from: next.date) == 6, "Sunrise on 2026-04-05 is at about 06:10 AEST")
    }

    @Test("a fixed start time that the clocks skip still starts that day")
    func skippedFixedTime() throws {
        // Arrange
        let cal = try calendar("Australia/Sydney")
        let config = MononiConfig(modes: [
            "early": ModeConfig(startTime: "2:30", appearance: "dark", wallpaper: "X"),
            "later": ModeConfig(startTime: "12:00", appearance: "light", wallpaper: "Y"),
        ])
        let day = try instant("2026-10-04", in: cal) // 02:00 AEST becomes 03:00 AEDT

        // Act
        let early = try config.transitions(on: day, calendar: cal).named("early")

        // Assert
        #expect(cal.isDate(early.date, inSameDayAs: day))
        #expect(cal.component(.hour, from: early.date) == 3)
    }
}

// MARK: - Polar days and fixed modes

@Suite("Sun schedule fallbacks")
struct SunFallbackTests {
    @Test("every stage uses its fixed start time on days its sun event does not happen", arguments: ["2026-06-21", "2026-12-21"])
    func polarDay(day: String) throws {
        // Arrange
        let cal = try calendar("Arctic/Longyearbyen")
        let config = sunConfig(Location(latitude: 78.2232, longitude: 15.6267))
        let date = try instant(day, in: cal)

        // Act
        let transitions = config.transitions(on: date, calendar: cal)

        // Assert
        #expect(transitions.map(\.name) == ["morning", "day", "evening", "night"])
        for transition in transitions {
            let stage = try #require(SolarStage(rawValue: transition.name))
            #expect(transition.source == .noSunEvent(stage))
            #expect(transition.date == transition.mode.fixedStart(on: date, calendar: cal))
        }
        #expect(transitions.first?.origin == "fixed time, no sunrise today")
    }

    @Test("a mode with another name keeps its fixed start time when a location is set")
    func otherModeStaysFixed() throws {
        // Arrange
        let cal = try calendar("Australia/Sydney")
        var config = sunConfig(sydney)
        config.modes["lunch"] = ModeConfig(startTime: "12:30", appearance: "light", wallpaper: "X")
        let day = try instant("2026-10-15", in: cal)

        // Act
        let lunch = try config.transitions(on: day, calendar: cal).named("lunch")

        // Assert
        #expect(lunch.source == .fixed)
        #expect(lunch.date == (try instant("2026-10-15", "12:30", in: cal)))
    }

    @Test("without a location every mode uses its fixed start time")
    func noLocation() throws {
        let cal = try calendar("Australia/Sydney")
        let transitions = MononiConfig.defaultConfig.transitions(on: try instant("2026-10-15", in: cal), calendar: cal)
        #expect(transitions.allSatisfy { $0.source == .fixed })
        #expect(transitions.map(\.origin) == Array(repeating: "fixed time", count: 4))
    }

    @Test("the JSON of the current config file loads to the same fixed schedule")
    func currentConfigFile() throws {
        // Arrange
        let json = """
            {
              "modes" : {
                "morning" : { "appearance" : "light", "startTime" : "6:30", "wallpaper" : "Tahoe Morning" },
                "day" : { "appearance" : "light", "startTime" : "11:00", "wallpaper" : "Tahoe Day" },
                "evening" : { "appearance" : "dark", "startTime" : "19:15", "wallpaper" : "Tahoe Evening" },
                "night" : { "appearance" : "dark", "startTime" : "21:00", "wallpaper" : "Tahoe Night" }
              }
            }
            """
        let cal = try calendar("Australia/Sydney")

        // Act
        let config = try JSONDecoder().decode(MononiConfig.self, from: Data(json.utf8))
        let transitions = config.transitions(on: try instant("2026-10-15", in: cal), calendar: cal)

        // Assert
        #expect(config.location == nil)
        #expect(config.errors.isEmpty)
        #expect(config.warnings.isEmpty)
        #expect(transitions.map(\.name) == ["morning", "day", "evening", "night"])
        #expect(try transitions.map(\.date) == ["6:30", "11:00", "19:15", "21:00"].map { try instant("2026-10-15", $0, in: cal) })
    }
}

// MARK: - Offsets

@Suite("Offsets")
struct OffsetTests {
    @Test("an offset moves its stage by exactly that many minutes, earlier or later")
    func offsetMovesStage() throws {
        // Arrange
        let cal = try calendar("Australia/Sydney")
        let day = try instant("2026-10-15", in: cal)

        // Act
        let plain = sunConfig(sydney).transitions(on: day, calendar: cal)
        let moved = sunConfig(sydney, offsets: ["morning": 16, "day": -100]).transitions(on: day, calendar: cal)

        // Assert
        #expect(try moved.named("morning").date.timeIntervalSince(plain.named("morning").date) == 16 * 60)
        #expect(try moved.named("day").date.timeIntervalSince(plain.named("day").date) == -100 * 60)
        #expect(try moved.named("evening").date == plain.named("evening").date)
        #expect(try moved.named("morning").origin == "sunrise +16 min")
        #expect(try moved.named("day").origin == "solar noon -100 min")
        #expect(try moved.named("evening").origin == "sunset")
        #expect(try moved.named("night").origin == "civil dusk")
    }

    @Test("an offset can push night past midnight, and evening stays active until then")
    func nightPastMidnight() throws {
        // Arrange
        let cal = try calendar("Australia/Sydney")
        let config = sunConfig(sydney, offsets: ["night": 300]) // civil dusk 19:34 + 5 h = 00:34

        // Act
        let night = try config.transitions(on: try instant("2026-10-15", in: cal), calendar: cal).named("night")

        // Assert
        #expect(cal.component(.day, from: night.date) == 16)
        #expect(config.nextTransition(after: try instant("2026-10-15", "23:00", in: cal), calendar: cal)?.name == "night")
        #expect(config.activeMode(at: try instant("2026-10-16", "00:10", in: cal), calendar: cal)?.name == "evening")
        #expect(config.activeMode(at: try instant("2026-10-16", "00:50", in: cal), calendar: cal)?.name == "night")
    }

    @Test("offsets that swap two stages change their order and which one is active")
    func swappedStages() throws {
        // Arrange
        let cal = try calendar("Australia/Sydney")
        let config = sunConfig(sydney, offsets: ["evening": 60, "night": -30]) // evening 20:08, night 19:04

        // Act
        let names = config.transitions(on: try instant("2026-10-15", in: cal), calendar: cal).map(\.name)

        // Assert
        #expect(names == ["morning", "day", "night", "evening"])
        #expect(config.activeMode(at: try instant("2026-10-15", "19:30", in: cal), calendar: cal)?.name == "night")
        #expect(config.activeMode(at: try instant("2026-10-15", "20:30", in: cal), calendar: cal)?.name == "evening")
    }

    @Test("a single stage offset by the full 12 hours is always found", arguments: [720, -720])
    func extremeOffset(offset: Int) throws {
        // Arrange
        let cal = try calendar("Europe/London")
        let config = MononiConfig(
            modes: ["night": ModeConfig(startTime: "21:00", appearance: "dark", wallpaper: "X", offsetMinutes: offset)],
            location: Location(latitude: 60, longitude: -0.1278)
        )

        // Act and assert
        for hour in stride(from: 0, to: 24, by: 3) {
            let date = try instant("2026-06-21", "\(hour):00", in: cal)
            let active = try #require(config.activeMode(at: date, calendar: cal), "No active mode at \(hour):00")
            let next = try #require(config.nextTransition(after: date, calendar: cal), "No next transition at \(hour):00")
            #expect(active.date <= date)
            #expect(next.date > date)
            #expect(next.date.timeIntervalSince(active.date) < 2 * 86_400)
        }
    }

    @Test("offsets outside -720 to 720 make the config invalid", arguments: [721, -721, 10_000])
    func outOfRange(offset: Int) {
        let config = sunConfig(sydney, offsets: ["day": offset])
        #expect(config.errors == ["Mode \"day\" has offsetMinutes \(offset), outside -720 to 720."])
        #expect(throws: MononiError.self) { try config.validate() }
    }

    @Test("offsets of exactly -720 and 720 are valid")
    func atLimits() throws {
        try sunConfig(sydney, offsets: ["morning": -720, "night": 720]).validate()
    }
}

// MARK: - Start time parsing

@Suite("ModeConfig start time range")
struct StartTimeRangeTests {
    @Test("rejects hours and minutes outside a 24-hour clock", arguments: ["24:00", "12:60", "-1:00", "25:00", "6:75"])
    func outOfRange(time: String) {
        #expect(ModeConfig(startTime: time, appearance: "dark", wallpaper: "X").startComponents == nil)
    }

    @Test("accepts a leading zero")
    func leadingZero() {
        let c = ModeConfig(startTime: "06:05", appearance: "dark", wallpaper: "X").startComponents
        #expect(c?.hour == 6)
        #expect(c?.minute == 5)
    }
}
