import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.mononi", category: "ThemeManager")

enum ThemeManager {
    // MARK: - Appearance

    static func setAppearance(dark: Bool) throws {
        let script = "tell application \"System Events\" to tell appearance preferences to set dark mode to \(dark)"
        let task = Process()
        task.executableURL = URL(filePath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        let errPipe = Pipe()
        task.standardError = errPipe
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown error"
            throw MononiError.appleScriptFailed(errMsg.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        logger.info("Appearance set to \(dark ? "dark" : "light", privacy: .public)")
    }

    // MARK: - Wallpaper

    static func setWallpaper(named name: String) async throws {
        // 1. Try aerial wallpapers from manifest (most common case for video wallpapers)
        if let asset = findAerialAsset(named: name) {
            let videoFile = aerialsDir.appendingPathComponent("videos/\(asset.id).mov")
            if !FileManager.default.fileExists(atPath: videoFile.path) {
                guard let urlString = asset.url, let url = URL(string: urlString) else {
                    throw MononiError.aerialNotDownloaded(name)
                }
                try await downloadAerialVideo(from: url, to: videoFile, name: name)
            }
            try await setAerialWallpaper(assetID: asset.id, name: name)
            return
        }

        // 2. Try static wallpapers in /System/Library/Desktop Pictures/
        if let url = findStaticWallpaper(named: name) {
            try setStaticWallpaper(url)
            return
        }

        throw MononiError.wallpaperNotFound(name)
    }

    // MARK: - Aerial Wallpapers

    private static let aerialsDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials")
    }()

    struct AerialAsset {
        let id: String
        let url: String?
    }

    static func findAerialAsset(named name: String) -> AerialAsset? {
        let manifestFile = aerialsDir.appendingPathComponent("manifest/entries.json")
        guard let data = try? Data(contentsOf: manifestFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]]
        else { return nil }

        guard let asset = assets.first(where: {
            ($0["accessibilityLabel"] as? String)?.lowercased() == name.lowercased()
        }) else { return nil }

        guard let id = asset["id"] as? String else { return nil }

        // Prefer 4K SDR, the most common format
        let url = asset["url-4K-SDR-240FPS"] as? String

        return AerialAsset(id: id, url: url)
    }

    private static func downloadAerialVideo(from url: URL, to destination: URL, name: String) async throws {
        logger.info("Downloading aerial '\(name, privacy: .public)' from \(url.absoluteString, privacy: .public)")
        fputs("Downloading '\(name)'...\n", stderr)

        let (tempURL, response) = try await URLSession.shared.download(from: url)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw MononiError.downloadFailed(name, "HTTP \(code)")
        }

        try FileManager.default.moveItem(at: tempURL, to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)

        logger.info("Downloaded aerial '\(name, privacy: .public)' to \(destination.path, privacy: .public)")
        fputs("Downloaded '\(name)'\n", stderr)
    }

    static let aerialVerifyDelay: Duration = .seconds(1.5)
    static let aerialMaxAttempts = 4

    /// Write the aerial plist, restart WallpaperAgent, then read Index.plist back to confirm
    /// it stuck. A concurrent appearance change makes WallpaperAgent occasionally revert the
    /// file to the previous wallpaper, so on a revert we write and restart again, up to a cap.
    /// The retry races no appearance change (it has long since settled) and reliably holds.
    private static func setAerialWallpaper(assetID: String, name: String) async throws {
        for attempt in 1...aerialMaxAttempts {
            try writeAerialPlist(assetID: assetID)
            restartWallpaperAgent()
            try await Task.sleep(for: aerialVerifyDelay)

            if currentAerialAssetIDs() == [assetID] {
                logger.info("Aerial '\(name, privacy: .public)' applied (id: \(assetID, privacy: .public), attempt \(attempt)/\(aerialMaxAttempts))")
                return
            }
            if attempt < aerialMaxAttempts {
                logger.warning("Aerial '\(name, privacy: .public)' was reverted by WallpaperAgent (attempt \(attempt)/\(aerialMaxAttempts)); retrying")
            }
        }
        logger.error("Aerial '\(name, privacy: .public)' kept being reverted by WallpaperAgent; gave up after \(aerialMaxAttempts) attempts")
        throw MononiError.wallpaperNotApplied(name)
    }

    /// The aerial asset IDs currently referenced by Index.plist across all displays/spaces.
    /// Each lives inside a nested binary-plist blob under Content → Choices → Configuration.
    static func currentAerialAssetIDs() -> Set<String> {
        guard let data = try? Data(contentsOf: wallpaperIndexURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [] }

        var ids = Set<String>()
        func collect(_ entry: Any?) {
            guard let entry = entry as? [String: Any],
                  let content = entry["Content"] as? [String: Any],
                  let choices = content["Choices"] as? [[String: Any]] else { return }
            for choice in choices {
                guard let cfgData = choice["Configuration"] as? Data,
                      let cfg = try? PropertyListSerialization.propertyList(from: cfgData, format: nil) as? [String: Any],
                      let id = cfg["assetID"] as? String else { continue }
                ids.insert(id)
            }
        }
        if let all = plist["AllSpacesAndDisplays"] as? [String: Any] {
            collect(all["Desktop"])
            collect(all["Idle"])
        }
        if let displays = plist["Displays"] as? [String: Any] {
            for value in displays.values {
                let entry = value as? [String: Any]
                collect(entry?["Desktop"])
                collect(entry?["Idle"])
            }
        }
        return ids
    }

    // MARK: - Static Wallpapers (.heic, .madesktop)

    private static let desktopPicturesDir = URL(filePath: "/System/Library/Desktop Pictures")

    private static func findStaticWallpaper(named name: String) -> URL? {
        for ext in ["heic", "madesktop"] {
            let url = desktopPicturesDir.appendingPathComponent("\(name).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private static func setStaticWallpaper(_ url: URL) throws {
        for screen in NSScreen.screens {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
        logger.info("Static wallpaper set: \(url.lastPathComponent, privacy: .public)")
    }

    // MARK: - Plist Manipulation

    static let wallpaperIndexURL: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    }()

    /// Write an aerial wallpaper config to Index.plist using the aerials provider + assetID.
    /// Sets both Desktop and Idle (screensaver) to the same aerial for all displays.
    private static func writeAerialPlist(assetID: String) throws {
        let indexData = try Data(contentsOf: wallpaperIndexURL)
        var plist = try PropertyListSerialization.propertyList(
            from: indexData, options: .mutableContainersAndLeaves, format: nil
        ) as? [String: Any] ?? [:]

        let configData = try PropertyListSerialization.data(
            fromPropertyList: ["assetID": assetID] as [String: Any],
            format: .binary, options: 0
        )
        let optionsData = try PropertyListSerialization.data(
            fromPropertyList: ["values": ["appearance": "automatic"]] as [String: Any],
            format: .binary, options: 0
        )

        let now = Date()
        let choice: [String: Any] = [
            "Configuration": configData,
            "Files": [] as [Any],
            "Provider": "com.apple.wallpaper.choice.aerials",
        ]
        let content: [String: Any] = [
            "Choices": [choice],
            "EncodedOptionValues": optionsData,
        ]

        func makeEntry() -> [String: Any] {
            ["Content": content, "LastSet": now, "LastUse": now]
        }

        // Set AllSpacesAndDisplays
        plist["AllSpacesAndDisplays"] = [
            "Desktop": makeEntry(),
            "Idle": makeEntry(),
            "Type": "individual",
        ] as [String: Any]

        // Update each existing display
        if var displays = plist["Displays"] as? [String: Any] {
            for key in displays.keys {
                displays[key] = [
                    "Desktop": makeEntry(),
                    "Idle": makeEntry(),
                    "Type": "individual",
                ] as [String: Any]
            }
            plist["Displays"] = displays
        }

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .binary, options: 0
        )
        try data.write(to: wallpaperIndexURL)
    }

    static func restartWallpaperAgent() {
        let task = Process()
        task.executableURL = URL(filePath: "/usr/bin/killall")
        task.arguments = ["WallpaperAgent"]
        let errPipe = Pipe()
        task.standardError = errPipe
        do {
            try task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                logger.info("WallpaperAgent restarted")
            } else {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errMsg = String(data: errData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                logger.error("killall WallpaperAgent exited with status \(task.terminationStatus): \(errMsg, privacy: .public)")
            }
        } catch {
            logger.error("Failed to launch killall WallpaperAgent: \(error, privacy: .public)")
        }
    }

    // MARK: - Listing

    static func listAvailableWallpapers() -> [String] {
        var names: [String] = []

        // Static wallpapers
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: desktopPicturesDir, includingPropertiesForKeys: nil
        ) {
            for url in contents {
                let ext = url.pathExtension
                if ext == "heic" || ext == "madesktop" {
                    names.append(url.deletingPathExtension().lastPathComponent)
                }
            }
        }

        // Aerials
        let manifestFile = aerialsDir.appendingPathComponent("manifest/entries.json")
        if let data = try? Data(contentsOf: manifestFile),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let assets = json["assets"] as? [[String: Any]]
        {
            let videosDir = aerialsDir.appendingPathComponent("videos")
            for asset in assets {
                guard let label = asset["accessibilityLabel"] as? String,
                      let id = asset["id"] as? String
                else { continue }
                let videoFile = videosDir.appendingPathComponent("\(id).mov")
                if FileManager.default.fileExists(atPath: videoFile.path) {
                    if !names.contains(label) {
                        names.append(label)
                    }
                }
            }
        }

        return names.sorted()
    }
}

// MARK: - Applying a Mode

/// The two side effects that applying a mode performs. Injectable so a test can
/// record the order they run in instead of changing the real appearance and wallpaper.
protocol ThemeEffects: Sendable {
    func setAppearance(dark: Bool) throws
    func setWallpaper(named name: String) async throws
}

struct LiveThemeEffects: ThemeEffects {
    func setAppearance(dark: Bool) throws { try ThemeManager.setAppearance(dark: dark) }
    func setWallpaper(named name: String) async throws { try await ThemeManager.setWallpaper(named: name) }
}

/// Applies an appearance and a wallpaper together. The appearance is set first, on purpose:
/// setting the wallpaper writes Index.plist and then verifies-and-retries against
/// WallpaperAgent reverting it, and the appearance change is the only thing that triggers a
/// revert. Running the wallpaper step after the appearance change lets that retry loop see
/// — and recover from — any revert. Flip the order and the revert would land unguarded.
enum ThemeApplier {
    static func apply(
        appearance: String,
        wallpaper: String,
        using effects: any ThemeEffects = LiveThemeEffects()
    ) async throws {
        try effects.setAppearance(dark: appearance == "dark")
        try await effects.setWallpaper(named: wallpaper)
    }
}

enum MononiError: Error, CustomStringConvertible {
    case appleScriptFailed(String)
    case wallpaperNotFound(String)
    case aerialNotDownloaded(String)
    case downloadFailed(String, String)
    case wallpaperNotApplied(String)
    case configError(String)

    var description: String {
        switch self {
        case .appleScriptFailed(let msg): "AppleScript error: \(msg)"
        case .wallpaperNotFound(let name): "Wallpaper not found: '\(name)'"
        case .aerialNotDownloaded(let name): "Aerial '\(name)' exists in manifest but video is not downloaded and no download URL is available. Re-download it in System Settings > Wallpaper."
        case .downloadFailed(let name, let reason): "Failed to download aerial '\(name)': \(reason)"
        case .wallpaperNotApplied(let name): "Applied wallpaper '\(name)' but WallpaperAgent kept reverting it; gave up after \(ThemeManager.aerialMaxAttempts) attempts"
        case .configError(let msg): "Config error: \(msg)"
        }
    }
}
