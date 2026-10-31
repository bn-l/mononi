import Foundation
import Testing

@testable import mononi

// MARK: - Errors and warnings

@Suite("Config errors and warnings")
struct ConfigProblemTests {
    @Test("the default config has no errors or warnings")
    func defaultIsClean() {
        #expect(MononiConfig.defaultConfig.errors.isEmpty)
        #expect(MononiConfig.defaultConfig.warnings.isEmpty)
    }

    @Test("an out-of-range latitude and longitude are errors")
    func locationOutOfRange() {
        // Arrange
        var config = MononiConfig.defaultConfig
        config.location = Location(latitude: 95, longitude: -200)

        // Act and assert
        #expect(config.errors == ["Latitude 95.0 is outside -90 to 90.", "Longitude -200.0 is outside -180 to 180."])
        #expect(throws: MononiError.self) { try config.validate() }
    }

    @Test("the limits of latitude and longitude are valid")
    func locationAtLimits() throws {
        var config = MononiConfig.defaultConfig
        config.location = Location(latitude: -90, longitude: 180)
        try config.validate()
    }

    @Test("settings that load but have no effect are warnings")
    func warnings() {
        // Arrange
        var config = MononiConfig.defaultConfig
        config.modes["day"]?.startTime = "25:00"
        config.modes["night"]?.appearance = "dim"
        config.modes["lunch"] = ModeConfig(startTime: "12:30", appearance: "light", wallpaper: "X", offsetMinutes: 10)

        // Act and assert
        #expect(config.errors.isEmpty)
        #expect(config.warnings == [
            "Mode \"day\" has startTime \"25:00\", which is not a time from 0:00 to 23:59.",
            "Mode \"lunch\" has offsetMinutes, but only morning, day, evening and night can have one.",
            "Mode \"night\" has appearance \"dim\". Use light or dark.",
        ])
    }

    @Test("a location with no sun-following mode is a warning")
    func locationWithoutSunModes() {
        let config = MononiConfig(modes: ["lunch": ModeConfig(startTime: "12:30", appearance: "light", wallpaper: "X")], location: sydney)
        #expect(config.warnings == ["A location is set, but no mode is named morning, day or evening, so none follows the sun."])
    }

    @Test("no modes is a warning")
    func noModes() {
        #expect(MononiConfig(modes: [:]).warnings == ["No modes are configured."])
    }
}

// MARK: - Decoding messages

@Suite("Config decoding messages")
struct DecodingMessageTests {
    func message(for json: String) throws -> String {
        do {
            _ = try JSONDecoder().decode(MononiConfig.self, from: Data(json.utf8))
        } catch let error as DecodingError {
            return error.configMessage
        }
        Issue.record("\(json) decoded without an error")
        return ""
    }

    @Test("each kind of decoding error gives one sentence that names the setting", arguments: [
        (#"{"modes": {"day": {"startTime": "12:00", "appearance": "light", "wallpaper": "X", "offsetMinutes": "ten"}}}"#,
         #"In mode "day", "offsetMinutes" should be a whole number."#),
        (#"{"modes": {"day": {"startTime": 12, "appearance": "light", "wallpaper": "X"}}}"#,
         #"In mode "day", "startTime" should be text in quotes."#),
        (#"{"modes": {"day": {"startTime": "12:00", "wallpaper": "X"}}}"#,
         #"Mode "day" is missing "appearance"."#),
        (#"{"modes": {"day": {"startTime": "12:00", "appearance": null, "wallpaper": "X"}}}"#,
         #"In mode "day", "appearance" has no value."#),
        (#"{"location": {"latitude": -33}, "modes": {}}"#,
         #"The location is missing "longitude"."#),
        (#"{"location": {"latitude": "-33", "longitude": 151}, "modes": {}}"#,
         #"In the location, "latitude" should be a number."#),
        (#"{"modes": {"day": 5}}"#,
         #"In the modes, "day" should be an object."#),
        (#"{}"#,
         #"The config is missing "modes"."#),
        (#"[]"#,
         #"The file should contain a JSON object."#),
        (#"{"modes": {"day": {"startTime": "12:00" "appearance": "light"}}}"#,
         #"The file is not valid JSON. Unexpected character '"' in object around line 1, column 41."#),
        (#""#,
         #"The file is not valid JSON. Unexpected end of file."#),
    ])
    func decodingMessage(json: String, expected: String) throws {
        #expect(try message(for: json) == expected)
    }
}

// MARK: - Cities

@Suite("City lookup")
struct CityTests {
    @Test("the built-in list parses every row into a valid location")
    func listParses() {
        #expect(City.all.count == 7342)
        #expect(City.all.allSatisfy { $0.location.errors.isEmpty && !$0.name.isEmpty && !$0.country.isEmpty })
    }

    @Test("a name finds the most populous city first", arguments: [
        ("Sydney", "Sydney, New South Wales, Australia"),
        ("Newcastle", "Newcastle, Tyne and Wear, United Kingdom"),
        ("London", "London, Westminster, United Kingdom"),
        ("Portland", "Portland, Oregon, United States of America"),
        ("Tokyo", "Tokyo, Japan"),
    ])
    func mostPopulousFirst(query: String, expected: String) {
        #expect(City.matching(query).first?.fullName == expected)
    }

    @Test("case and accents are ignored", arguments: [
        ("sydney", "Sydney, New South Wales, Australia"),
        ("SAO PAULO", "São Paulo, Brazil"),
        ("reykjavik", "Reykjavík, Suðurnes, Iceland"),
        ("  Perth  ", "Perth, Western Australia, Australia"),
    ])
    func folding(query: String, expected: String) {
        #expect(City.matching(query).first?.fullName == expected)
    }

    @Test("a region, country or country code after a comma narrows the match", arguments: [
        ("Newcastle, Australia", "Newcastle, New South Wales, Australia"),
        ("Newcastle, new south", "Newcastle, New South Wales, Australia"),
        ("Portland, Maine", "Portland, Maine, United States of America"),
        ("Portland, AU", "Portland, Victoria, Australia"),
        ("Springfield, Missouri", "Springfield, Missouri, United States of America"),
        ("Sydney, Canada", "Sydney, Nova Scotia, Canada"),
        ("London, united states", "London, Kentucky, United States of America"),
    ])
    func qualifier(query: String, expected: String) {
        #expect(City.matching(query).first?.fullName == expected)
    }

    @Test("a name not in the list finds nothing", arguments: ["Atlantis", "", ",", "Sydney, Mars", "Syd"])
    func noMatch(query: String) {
        #expect(City.matching(query).isEmpty)
    }

    @Test("the other cities with the same name are kept, most populous first")
    func otherMatches() {
        let names = City.matching("Sydney").map(\.fullName)
        #expect(names == ["Sydney, New South Wales, Australia", "Sydney, Nova Scotia, Canada"])
    }
}
