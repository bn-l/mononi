# Development log: setting video wallpapers on macOS Tahoe

This section documents the research process for figuring out how to programmatically switch aerial/video wallpapers on macOS 26 (Tahoe). There is no public API for this and almost no documentation. Everything here was discovered through reverse engineering.

## Attempt 1: NSAppleScript — appearance only

AppleScript can toggle dark mode:

```applescript
tell application "System Events" to tell appearance preferences to set dark mode to true
```

But `desktop picture` in Finder/System Events only works with image files. Passing a `.mov` path silently fails or sets "missing value". AppleScript cannot set video wallpapers.

**Also:** running `NSAppleScript` in-process (via `NSAppleScript(source:).executeAndReturnError`) took **32 seconds** due to the overhead of initializing the Apple Event bridge inside the process. Switching to subprocess `osascript -e "..."` reduced this to **~0.1s**.

## Attempt 2: NSWorkspace.setDesktopImageURL — static only

```swift
try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
```

Works for `.heic` and `.madesktop` files. Does nothing useful with `.mov` files — the desktop goes blank or reverts.

## Attempt 3: writing Index.plist with videoFile configuration — wrong wallpaper

macOS Sonoma+ stores wallpaper config in:
```
~/Library/Application Support/com.apple.wallpaper/Store/Index.plist
```

The plist has a nested structure with `Configuration` (embedded binary plist), `Provider`, and `Files` per choice. I tried constructing a "Linked" configuration (matching the Sequoia screensaver+wallpaper linked mode) with:

```swift
// Configuration binary plist
["type": "videoFile", "url": ["relative": videoURL.absoluteString]]
// Provider
"com.apple.wallpaper.choice.sequoia"
```

Then `killall WallpaperAgent` to reload.

**Result:** The wallpaper changed, but to the **Sequoia default** — not the specific aerial I requested. The `Configuration` data was being serialized as empty (`<data></data>`) in the final plist. Even after fixing the serialization, the `.sequoia` provider ignores the configuration and just shows its default.

## Attempt 4: inspecting the working plist — everything is empty

After manually setting "Tahoe Day" via System Settings, I dumped Index.plist with Python:

```
Provider=com.apple.wallpaper.choice.sequoia, Config len=0  (Idle/screensaver)
Provider=default, Config len=0                                (Desktop)
```

The `Configuration` data is legitimately **0 bytes** for the current OS default wallpaper. The plist doesn't encode *which* specific aerial is selected — at least not for the Sequoia hero wallpapers.

I searched `defaults`, `~/Library/Preferences/`, `ByHost/`, wallpaper extension containers (`~/Library/Containers/com.apple.wallpaper.extension.*`), and even `grep -r` across the entire `~/Library/` for the Tahoe Day asset UUID. Nothing. The extension containers were empty directories.

## Attempt 5: the "snapshot" approach — works but requires manual setup

Projects like [MacOS_Dynamic_Aerial](https://github.com/postrou/MacOS_Dynamic_Aerial) solve this by having users:
1. Manually set each wallpaper in System Settings
2. `cp ~/Library/.../Index.plist ~/.aerial/Tahoe-Morning.plist`
3. To switch: copy the profile back and `killall WallpaperAgent`

This works because the full system state gets captured. But requiring 4 manual steps before the tool works is poor UX.

## The solution: aerials provider + assetID

A [StackExchange answer](https://apple.stackexchange.com/questions/481147) about identifying aerials revealed that the `Configuration` binary plist for the **aerials** provider contains an `assetID` field:

```
Provider = com.apple.wallpaper.choice.aerials
Configuration = bplist... {"assetID": "shuffle-all-aerials"}
```

And a separate answer showed specific aerials use the actual UUID:

```
assetID = "100858D2-FE01-4B70-8E2D-3FCF20AFE6B5"
```

The asset IDs come from the aerials manifest at:
```
~/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json
```

Each asset has an `accessibilityLabel` (e.g. "Tahoe Evening") and an `id` (UUID). The downloaded videos live at:
```
~/Library/Application Support/com.apple.wallpaper/aerials/videos/<UUID>.mov
```

So the working approach is:

1. Look up the aerial by `accessibilityLabel` in `entries.json`
2. Get its UUID
3. Create a binary plist: `{"assetID": "<UUID>"}`
4. Write it as the `Configuration` in Index.plist with `Provider: "com.apple.wallpaper.choice.aerials"`
5. Set both `Desktop` and `Idle` sections (wallpaper + screensaver)
6. `killall WallpaperAgent`

```python
# The proof-of-concept that confirmed it works
config_data = plistlib.dumps({"assetID": asset_id}, fmt=plistlib.FMT_BINARY)
choice = {
    "Configuration": config_data,
    "Files": [],
    "Provider": "com.apple.wallpaper.choice.aerials",
}
```

This switches both wallpaper and screensaver to the specified aerial in **~0.1 seconds**.

## Key differences from what didn't work

| | Broken | Working |
|---|--------|---------|
| Provider | `com.apple.wallpaper.choice.sequoia` | `com.apple.wallpaper.choice.aerials` |
| Configuration | `{"type": "videoFile", "url": ...}` or empty | `{"assetID": "<UUID>"}` |
| Plist structure | "Linked" type with AllSpacesAndDisplays | "individual" type with Desktop + Idle per display |

The `.sequoia` provider is for the OS-default hero wallpaper and ignores configuration. The `.aerials` provider is the general-purpose aerial system that respects `assetID`.

## Other things that don't work (saved you the trouble)

- **Shortcuts app**: only supports photos, not videos
- **Configuration Profiles** (`override-picture-path`): images only; `.mov` paths produce a pale blue fallback
- **Automator**: no wallpaper action; "Watch Me Do" is brittle mouse-recording
- **`defaults write`**: the old `com.apple.desktop` domain is dead; `desktoppicture.db` is abandoned since Sonoma
- **WallpaperAerialsExtension XPC**: undocumented protocol, no useful headers to work with
- **PyObjC / private frameworks**: without documentation on the XPC interface, there's nothing to call

## Resources

- [MacOS_Dynamic_Aerial](https://github.com/postrou/MacOS_Dynamic_Aerial) — snapshot-swap approach for Tahoe aerials
- [PaperSaver](https://github.com/AerialScreensaver/PaperSaver) — Swift library for static wallpaper/screensaver plist manipulation
- [WallpaperInfo](https://github.com/bgreenlee/WallpaperInfo) — identifies current aerial via `lsof` on WallpaperVideoExtension
- [Blog: macOS 26 Tahoe dynamic video wallpapers](https://blog.hloth.dev/tahoe-dynamic-video-wallpapers/) — documents all the dead ends
- [Deploying wallpaper in Sonoma](https://macadmin.fraserhess.com/2023/10/07/deploying-a-default-wallpaper-in-macos-sonoma/) — Index.plist structure for enterprise deployment
- [StackExchange: identify current aerial](https://apple.stackexchange.com/questions/481147) — revealed the `assetID` Configuration format
