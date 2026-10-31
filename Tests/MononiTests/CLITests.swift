import Foundation
import Testing

@testable import mononi

/// A temporary home directory for running the real `mononi` binary. `CFFIXED_USER_HOME` moves
/// `homeDirectoryForCurrentUser`, so the binary reads and writes its config here and never touches the
/// real one. Setting `HOME` does not move it.
struct CLIHome {
    struct Run {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private final class BundleMarker {}

    let url = FileManager.default.temporaryDirectory.appendingPathComponent("mononi-e2e-\(UUID().uuidString)")
    var configFile: URL { url.appendingPathComponent(".config/mononi/config.json") }

    /// Static wallpapers live outside the home directory, so a config using them has no wallpaper problems here.
    static let validConfig = """
        {"modes": {
          "morning": {"startTime": "6:30", "appearance": "light", "wallpaper": "Big Sur"},
          "day": {"startTime": "12:00", "appearance": "light", "wallpaper": "Big Sur"},
          "evening": {"startTime": "17:30", "appearance": "dark", "wallpaper": "Big Sur"},
          "night": {"startTime": "21:00", "appearance": "dark", "wallpaper": "Big Sur"}
        }}
        """

    init(config: String = validConfig) throws {
        try #require(ThemeManager.wallpaperExists(named: "Big Sur"), "These tests use the static wallpaper 'Big Sur'")
        try FileManager.default.createDirectory(at: configFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(config.utf8).write(to: configFile)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    func run(_ arguments: String...) throws -> Run {
        try run(arguments: arguments)
    }

    func run(arguments: [String]) throws -> Run {
        let binary = Bundle(for: BundleMarker.self).bundleURL.deletingLastPathComponent().appendingPathComponent("mononi")
        try #require(FileManager.default.isExecutableFile(atPath: binary.path), "No mononi binary at \(binary.path)")

        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(["CFFIXED_USER_HOME": url.path]) { $1 }
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Run(status: process.terminationStatus, stdout: String(decoding: stdout, as: UTF8.self), stderr: String(decoding: stderr, as: UTF8.self))
    }

    func config() throws -> MononiConfig {
        try JSONDecoder().decode(MononiConfig.self, from: Data(contentsOf: configFile))
    }

    func configBytes() throws -> Data {
        try Data(contentsOf: configFile)
    }
}

@Suite("CLI end to end", .serialized)
struct CLITests {
    @Test("setting the location by city stores its coordinates, and status follows the sun")
    func cityLocation() throws {
        // Arrange
        let home = try CLIHome()
        defer { home.remove() }

        // Act
        let set = try home.run("config", "location", "--city", "Newcastle, Australia")
        let status = try home.run("status")

        // Assert
        #expect(set.status == 0, "\(set.stderr)")
        #expect(set.stdout == "Location set to Newcastle, New South Wales, Australia (-32.9295, 151.7702).\n")
        #expect(set.stderr.isEmpty)
        #expect(try home.config().location == Location(latitude: -32.9295, longitude: 151.7702))
        #expect(status.status == 0, "\(status.stderr)")
        #expect(status.stderr.isEmpty)
        #expect(status.stdout.contains("Schedule: follows the sun at -32.9295, 151.7702"))
        for origin in ["sunrise", "solar noon", "civil dusk", "fixed time"] {
            #expect(status.stdout.contains(origin), "status does not list \(origin):\n\(status.stdout)")
        }
    }

    @Test("an ambiguous city name lists the other matches")
    func ambiguousCity() throws {
        let home = try CLIHome()
        defer { home.remove() }

        let run = try home.run("config", "location", "--city", "newcastle")

        #expect(run.status == 0, "\(run.stderr)")
        #expect(run.stdout == """
            Location set to Newcastle, Tyne and Wear, United Kingdom (54.9897, -1.6116).
            Other matches: Newcastle, New South Wales, Australia. Add a region or country to choose one, such as "Newcastle, Australia".

            """)
    }

    @Test("negative coordinates parse and are stored as given")
    func negativeCoordinates() throws {
        let home = try CLIHome()
        defer { home.remove() }

        let run = try home.run("config", "location", "--latitude", "-33.8688", "--longitude", "-151.2093")

        #expect(run.status == 0, "\(run.stderr)")
        #expect(try home.config().location == Location(latitude: -33.8688, longitude: -151.2093))
    }

    @Test("invalid location input exits non-zero and leaves the file unchanged", arguments: [
        ["config", "location", "--latitude", "-91", "--longitude", "0"],
        ["config", "location", "--latitude", "10"],
        ["config", "location", "--city", "Atlantis"],
        ["config", "location", "--city", "Sydney", "--clear"],
        ["config", "set", "lunch", "--offset", "5"],
        ["config", "set", "day", "--offset", "-721"],
        ["config", "set", "day", "--time", "24:00"],
    ])
    func invalidInput(arguments: [String]) throws {
        // Arrange
        let home = try CLIHome()
        defer { home.remove() }
        let before = try home.configBytes()

        // Act
        let process = try home.run(arguments: arguments)

        // Assert
        #expect(process.status != 0)
        #expect(!process.stderr.isEmpty)
        #expect(try home.configBytes() == before)
    }

    @Test("an offset set with config set moves the stage, and status shows it")
    func offset() throws {
        let home = try CLIHome()
        defer { home.remove() }

        _ = try home.run("config", "location", "--city", "Sydney")
        let set = try home.run("config", "set", "evening", "--offset", "-15")
        let status = try home.run("status")

        #expect(set.status == 0, "\(set.stderr)")
        #expect(try home.config().modes["evening"]?.offsetMinutes == -15)
        #expect(status.stdout.contains("civil dusk -15 min"), "\(status.stdout)")
    }

    @Test("clearing the location returns to fixed times")
    func clear() throws {
        let home = try CLIHome()
        defer { home.remove() }

        _ = try home.run("config", "location", "--city", "Sydney")
        let cleared = try home.run("config", "location", "--clear")
        let shown = try home.run("config", "location")
        let status = try home.run("status")

        #expect(cleared.status == 0)
        #expect(try home.config().location == nil)
        #expect(shown.stdout == "No location is set. Modes use their fixed start times.\n")
        #expect(status.stdout.contains("Schedule: fixed times"))
    }

    @Test("a config problem is printed once to stderr for every command", arguments: [
        ["status"], ["wallpapers"], ["config", "path"], ["config", "show"], ["config", "location"], ["--version"],
    ])
    func problemsOnEveryCommand(arguments: [String]) throws {
        // Arrange
        let home = try CLIHome(config: #"{"location": {"latitude": 95, "longitude": 151}, "modes": {"day": {"startTime": "12:00", "appearance": "light", "wallpaper": "Big Sur", "ofsetMinutes": 5}}}"#)
        defer { home.remove() }

        // Act
        let run = try home.run(arguments: arguments)

        // Assert
        #expect(run.stderr == """
            Problems in \(home.configFile.path):
              Mode "day" has an unknown key "ofsetMinutes".
              Latitude 95.0 is outside -90 to 90.

            """)
    }

    @Test("commands that need a valid config exit 1 without repeating the problem", arguments: [["status"], ["apply"], ["start"]])
    func invalidConfigExits(arguments: [String]) throws {
        let home = try CLIHome(config: #"{"modes": {"day": {"startTime": "12:00" "appearance": "light"}}}"#)
        defer { home.remove() }

        let run = try home.run(arguments: arguments)

        #expect(run.status == 1)
        #expect(run.stderr == """
            Problems in \(home.configFile.path):
              The file is not valid JSON. Unexpected character '"' in object around line 1, column 41.

            """)
    }

    @Test("config location can repair an out-of-range latitude")
    func repairLocation() throws {
        let home = try CLIHome(config: #"{"location": {"latitude": 95, "longitude": 151}, "modes": {"day": {"startTime": "12:00", "appearance": "light", "wallpaper": "Big Sur"}}}"#)
        defer { home.remove() }

        let repair = try home.run("config", "location", "--city", "Sydney")
        let status = try home.run("status")

        #expect(repair.status == 0, "\(repair.stderr)")
        #expect(status.status == 0)
        #expect(status.stderr.isEmpty)
    }
}
