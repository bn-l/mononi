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

    static func setWallpaper(named name: String) throws {
        // 1. Try aerial wallpapers from manifest (most common case for video wallpapers)
        if let assetID = findAerialAssetID(named: name) {
            try setAerialWallpaper(assetID: assetID, name: name)
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

    private static func findAerialAssetID(named name: String) -> String? {
        let manifestFile = aerialsDir.appendingPathComponent("manifest/entries.json")
        guard let data = try? Data(contentsOf: manifestFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let assets = json["assets"] as? [[String: Any]]
        else { return nil }

        guard let asset = assets.first(where: {
            ($0["accessibilityLabel"] as? String)?.lowercased() == name.lowercased()
        }) else { return nil }

        guard let id = asset["id"] as? String else { return nil }

        let videoFile = aerialsDir.appendingPathComponent("videos/\(id).mov")
        guard FileManager.default.fileExists(atPath: videoFile.path) else {
            logger.warning("Aerial '\(name, privacy: .public)' found in manifest but video not downloaded (id: \(id, privacy: .public))")
            return nil
        }

        return id
    }

    private static func setAerialWallpaper(assetID: String, name: String) throws {
        try writeAerialPlist(assetID: assetID)
        restartWallpaperAgent()
        logger.info("Aerial wallpaper set: \(name, privacy: .public) (id: \(assetID, privacy: .public))")
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

    private static let wallpaperIndexURL: URL = {
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

    private static func restartWallpaperAgent() {
        let task = Process()
        task.executableURL = URL(filePath: "/usr/bin/killall")
        task.arguments = ["WallpaperAgent"]
        try? task.run()
        task.waitUntilExit()
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

enum MononiError: Error, CustomStringConvertible {
    case appleScriptFailed(String)
    case wallpaperNotFound(String)
    case configError(String)

    var description: String {
        switch self {
        case .appleScriptFailed(let msg): "AppleScript error: \(msg)"
        case .wallpaperNotFound(let name): "Wallpaper not found: '\(name)'"
        case .configError(let msg): "Config error: \(msg)"
        }
    }
}
