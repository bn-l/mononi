import CoreLocation
import Foundation
import Solar

struct ModeConfig: Codable, Sendable {
    /// Required except for night, which starts four hours after evening without one.
    var startTime: String?
    var appearance: String
    var wallpaper: String
    /// Minutes to move the stage from its sun event, or night from its start; negative is earlier.
    var offsetMinutes: Int?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case startTime, appearance, wallpaper, offsetMinutes
    }

    /// `startTime` as a 24-hour clock time, or nil when it is not one.
    var startComponents: (hour: Int, minute: Int)? {
        guard let parts = startTime?.split(separator: ":") else { return nil }
        guard parts.count == 2,
              let h = Int(parts[0]), (0..<24).contains(h),
              let m = Int(parts[1]), (0..<60).contains(m) else { return nil }
        return (h, m)
    }

    /// `startTime` on the calendar day containing `day`.
    func fixedStart(on day: Date, calendar: Calendar) -> Date? {
        startComponents.flatMap { calendar.date(bySettingHour: $0.hour, minute: $0.minute, second: 0, of: day) }
    }

    /// Settings in this mode that load but are ignored or fail when applied.
    func warnings(named name: String) -> [String] {
        [
            startTime.flatMap { startComponents == nil ? "Mode \"\(name)\" has startTime \"\($0)\", which is not a time from 0:00 to 23:59." : nil },
            startTime == nil && name != MononiConfig.nightName ? "Mode \"\(name)\" has no startTime." : nil,
            ["light", "dark"].contains(appearance)
                ? nil : "Mode \"\(name)\" has appearance \"\(appearance)\". Use light or dark.",
            offsetMinutes != nil && !MononiConfig.canOffset(name)
                ? "Mode \"\(name)\" has offsetMinutes, but only morning, day, evening and night can have one." : nil,
        ].compactMap(\.self)
    }
}

/// Where to follow the sun from, in degrees.
struct Location: Codable, Sendable, Equatable, CustomStringConvertible {
    var latitude: Double
    var longitude: Double

    enum CodingKeys: String, CodingKey, CaseIterable {
        case latitude, longitude
    }

    var description: String { "\(latitude), \(longitude)" }

    /// Values outside the valid range, as sentences.
    var errors: [String] {
        [
            (-90...90).contains(latitude) ? nil : "Latitude \(latitude) is outside -90 to 90.",
            (-180...180).contains(longitude) ? nil : "Longitude \(longitude) is outside -180 to 180.",
        ].compactMap(\.self)
    }

    /// Sun events for the local calendar day containing `day`. Solar computes events for the UTC calendar
    /// day of the date it is given, so local noon in a zone far ahead of UTC (Auckland is UTC+13 in
    /// summer) falls on the previous UTC day and returns the previous day's sunrise. 12:00 UTC on the
    /// local date returns the right day everywhere.
    func solar(on day: Date, calendar: Calendar) -> Solar? {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        var noon = calendar.dateComponents([.year, .month, .day], from: day)
        noon.hour = 12
        return utc.date(from: noon).flatMap {
            Solar(for: $0, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        }
    }
}

/// The modes that follow the sun when a location is set. Night follows evening instead, and a mode with
/// any other name keeps its fixed start time.
enum SolarStage: String, CaseIterable, Sendable {
    case morning, day, evening

    /// The name of the sun event the stage starts at.
    var event: String {
        switch self {
        case .morning: "sunrise"
        case .day: "solar noon"
        case .evening: "civil dusk"
        }
    }

    /// When the stage's sun event happens on the day `solar` covers, or nil on a day it does not happen,
    /// as in polar day or night.
    func eventDate(in solar: Solar) -> Date? {
        switch self {
        case .morning: solar.sunrise
        // Solar has no solar noon; the midpoint of sunrise and sunset is within a minute of it.
        case .day: solar.sunrise.flatMap { rise in solar.sunset.map { rise + $0.timeIntervalSince(rise) / 2 } }
        case .evening: solar.civilSunset
        }
    }
}

/// A mode starting at a particular moment.
struct Transition: Sendable {
    enum Source: Sendable, Equatable {
        /// The mode's fixed `startTime`.
        case fixed
        /// The stage's sun event moved by the mode's offset.
        case sun(SolarStage)
        /// The fixed `startTime`, because the stage's sun event does not happen that day.
        case noSunEvent(SolarStage)
        /// Night without a `startTime`: four hours after evening, moved by night's offset.
        case afterEvening
    }

    let name: String
    let mode: ModeConfig
    let date: Date
    let source: Source
    /// The offset in minutes applied to `date`.
    let offset: Int

    private static let clock = Date.VerbatimFormatStyle(
        format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
        timeZone: .current, calendar: .current
    )

    /// The start as a 24-hour time in the current time zone, such as 06:30.
    var clockTime: String { date.formatted(Self.clock) }

    /// Where the start time came from, such as "civil dusk +8 min" or "fixed time".
    var origin: String {
        let base = switch source {
        case .fixed: "fixed time"
        case .sun(let stage): stage.event
        case .noSunEvent(let stage): "fixed time, no \(stage.event) today"
        case .afterEvening: "4 h after evening"
        }
        return offset == 0 ? base : "\(base) \(offset > 0 ? "+" : "")\(offset) min"
    }
}

struct MononiConfig: Codable, Sendable {
    var modes: [String: ModeConfig]
    /// Where to follow the sun from. When set, the modes named in `SolarStage` start at their sun events.
    /// Night always starts at its `startTime`, or four hours after evening without one.
    var location: Location?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case modes, location
    }

    static let defaultConfig = MononiConfig(
        modes: [
            "morning": ModeConfig(startTime: "6:30", appearance: "light", wallpaper: "Tahoe Morning"),
            "day": ModeConfig(startTime: "12:00", appearance: "light", wallpaper: "Tahoe Day"),
            "evening": ModeConfig(startTime: "17:30", appearance: "dark", wallpaper: "Tahoe Evening"),
            "night": ModeConfig(startTime: "21:00", appearance: "dark", wallpaper: "Tahoe Night"),
        ]
    )

    /// How the start times are chosen, such as "follows the sun at -33.8714, 151.2125".
    var basis: String {
        location.map { "follows the sun at \($0)" } ?? "fixed times"
    }

    static let nightName = "night"
    /// How long after evening night starts when night has no `startTime`.
    static let nightAfterEvening: TimeInterval = 4 * 3600

    /// Whether `offsetMinutes` applies to the mode with this name.
    static func canOffset(_ name: String) -> Bool {
        name == nightName || SolarStage(rawValue: name) != nil
    }

    /// The allowed `offsetMinutes`. With night up to 16 hours after evening, twelve hours either way
    /// keeps every stage within the days `transitions(around:calendar:)` searches.
    static let offsetRange = -720...720

    /// One day's transitions, earliest first. Modes whose start time cannot be resolved are left out.
    func transitions(on day: Date, calendar: Calendar = .current) -> [Transition] {
        let solar = location?.solar(on: day, calendar: calendar)
        let others = modes.filter { $0.key != Self.nightName }.compactMap { name, mode -> Transition? in
            let stage = solar == nil ? nil : SolarStage(rawValue: name)
            if let solar, let stage, let event = stage.eventDate(in: solar) {
                let offset = mode.offsetMinutes ?? 0
                return Transition(name: name, mode: mode, date: event + TimeInterval(offset * 60), source: .sun(stage), offset: offset)
            }
            return mode.fixedStart(on: day, calendar: calendar).map {
                Transition(name: name, mode: mode, date: $0, source: stage.map { .noSunEvent($0) } ?? .fixed, offset: 0)
            }
        }
        let evening = others.first { $0.name == SolarStage.evening.rawValue }
        return (others + [night(on: day, after: evening, calendar: calendar)].compactMap(\.self))
            .sorted { ($0.date, $0.name) < ($1.date, $1.name) }
    }

    /// Night at its `startTime`, or four hours after `evening` without one, moved by night's offset.
    private func night(on day: Date, after evening: Transition?, calendar: Calendar) -> Transition? {
        guard let mode = modes[Self.nightName] else { return nil }
        let offset = mode.offsetMinutes ?? 0
        let start: (Date, Transition.Source)? = mode.startTime == nil
            ? evening.map { ($0.date + Self.nightAfterEvening, .afterEvening) }
            : mode.fixedStart(on: day, calendar: calendar).map { ($0, .fixed) }
        return start.map { Transition(name: Self.nightName, mode: mode, date: $0.0 + TimeInterval(offset * 60), source: $0.1, offset: offset) }
    }

    /// The transitions from three days before `date` to three days after, earliest first. A stage lands
    /// at most 12 hours before its day and night at most 52 hours after the start of its day, so this
    /// always includes the transitions either side of `date`.
    private func transitions(around date: Date, calendar: Calendar) -> [Transition] {
        (-3...3).compactMap { calendar.date(byAdding: .day, value: $0, to: date) }
            .flatMap { transitions(on: $0, calendar: calendar) }
            .sorted { ($0.date, $0.name) < ($1.date, $1.name) }
    }

    /// The transition that started the mode active at `date`.
    func activeMode(at date: Date = .now, calendar: Calendar = .current) -> Transition? {
        transitions(around: date, calendar: calendar).last { $0.date <= date }
    }

    /// The first transition after `date`.
    func nextTransition(after date: Date = .now, calendar: Calendar = .current) -> Transition? {
        transitions(around: date, calendar: calendar).first { $0.date > date }
    }

    /// Values the schedule cannot use. `ConfigManager` refuses to load or save a config with any of these.
    var errors: [String] {
        (location?.errors ?? []) + modes.sorted { $0.key < $1.key }.compactMap { name, mode in
            mode.offsetMinutes.flatMap {
                Self.offsetRange.contains($0) ? nil
                    : "Mode \"\(name)\" has offsetMinutes \($0), outside \(Self.offsetRange.lowerBound) to \(Self.offsetRange.upperBound)."
            }
        }
    }

    /// Settings that load but are ignored or fail when applied.
    var warnings: [String] {
        let followsSun = modes.keys.contains { SolarStage(rawValue: $0) != nil }
        return [
            modes.isEmpty ? "No modes are configured." : nil,
            location != nil && !modes.isEmpty && !followsSun
                ? "A location is set, but no mode is named morning, day or evening, so none follows the sun." : nil,
        ].compactMap(\.self) + modes.sorted { $0.key < $1.key }.flatMap { $0.value.warnings(named: $0.key) }
    }

    func validate() throws {
        guard errors.isEmpty else { throw MononiError.configError(errors.joined(separator: " ")) }
    }
}

enum ConfigManager {
    static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/mononi")
    static let configFile = configDir.appendingPathComponent("config.json")

    /// The config as written, or the defaults when there is no file. It skips the range checks so that
    /// `config set` and `config location` can repair an out-of-range value.
    static func read() throws -> MononiConfig {
        try fileData().map(decode) ?? .defaultConfig
    }

    /// The config, refusing values the schedule cannot use.
    static func load() throws -> MononiConfig {
        let config = try read()
        try config.validate()
        return config
    }

    static func save(_ config: MononiConfig) throws {
        try config.validate()
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

    /// Everything wrong with the config file, as sentences. Empty when the file is fine or does not exist.
    static func problems() -> [String] {
        do {
            guard let data = try fileData() else { return [] }
            let config = try decode(data)
            let missingWallpapers = config.modes.sorted { $0.key < $1.key }
                .filter { !ThemeManager.wallpaperExists(named: $0.value.wallpaper) }
                .map { "Mode \"\($0.key)\" uses wallpaper \"\($0.value.wallpaper)\", which was not found. Run \"mononi wallpapers\" for the list." }
            return try unknownKeys(in: data) + config.errors + config.warnings + missingWallpapers
        } catch MononiError.configError(let message) {
            return [message]
        } catch {
            return [error.localizedDescription]
        }
    }

    /// The file's contents, or nil when there is no file.
    private static func fileData() throws -> Data? {
        guard FileManager.default.fileExists(atPath: configFile.path) else { return nil }
        do {
            return try Data(contentsOf: configFile)
        } catch {
            throw MononiError.configError("The file could not be read: \(error.localizedDescription)")
        }
    }

    private static func decode(_ data: Data) throws -> MononiConfig {
        do {
            return try JSONDecoder().decode(MononiConfig.self, from: data)
        } catch let error as DecodingError {
            throw MononiError.configError(error.configMessage)
        }
    }

    /// Keys that no setting uses, such as a misspelt "ofsetMinutes". JSONDecoder skips these without an error.
    private static func unknownKeys(in data: Data) throws -> [String] {
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        func unknown<Keys: CodingKey & CaseIterable>(_ object: Any?, _: Keys.Type) -> [String] {
            guard let object = object as? [String: Any] else { return [] }
            return Set(object.keys).subtracting(Keys.allCases.map(\.stringValue)).sorted()
        }
        let modes = (root?["modes"] as? [String: Any] ?? [:]).sorted { $0.key < $1.key }
        return unknown(root, MononiConfig.CodingKeys.self).map { "The config has an unknown key \"\($0)\"." }
            + unknown(root?["location"], Location.CodingKeys.self).map { "The location has an unknown key \"\($0)\"." }
            + modes.flatMap { name, mode in
                unknown(mode, ModeConfig.CodingKeys.self).map { "Mode \"\(name)\" has an unknown key \"\($0)\"." }
            }
    }
}

extension DecodingError {
    /// The error as one sentence about the config file.
    var configMessage: String {
        switch self {
        case .dataCorrupted(let context):
            let detail = (context.underlyingError as NSError?)?.userInfo[NSDebugDescriptionErrorKey] as? String
            let sentence = detail ?? context.debugDescription
            return "The file is not valid JSON. \(sentence)\(sentence.hasSuffix(".") ? "" : ".")"
        case .keyNotFound(let key, let context):
            let place = Self.place(context.codingPath)
            return "\(place.prefix(1).uppercased())\(place.dropFirst()) is missing \"\(key.stringValue)\"."
        case .valueNotFound(_, let context):
            guard let key = context.codingPath.last else { return "The file is empty." }
            return "In \(Self.place(context.codingPath.dropLast())), \"\(key.stringValue)\" has no value."
        case .typeMismatch(let type, let context):
            guard let key = context.codingPath.last else { return "The file should contain a JSON object." }
            return "In \(Self.place(context.codingPath.dropLast())), \"\(key.stringValue)\" should be \(Self.kind(type))."
        @unknown default:
            return "\(self)"
        }
    }

    /// The part of the config a coding path points to, such as `mode "day"`.
    private static func place(_ path: some Collection<any CodingKey>) -> String {
        switch path.map(\.stringValue) {
        case []: "the config"
        case ["location"]: "the location"
        case ["modes"]: "the modes"
        case let keys where keys.count == 2 && keys[0] == "modes": "mode \"\(keys[1])\""
        case let keys: keys.joined(separator: ".")
        }
    }

    private static func kind(_ type: Any.Type) -> String {
        switch type {
        case is Int.Type: "a whole number"
        case is Double.Type: "a number"
        case is String.Type: "text in quotes"
        default: "an object"
        }
    }
}
