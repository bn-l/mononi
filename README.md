<p align="center">
  <img src="icon.webp" width="200" alt="mononi" />
</p>

<p align="center">
  Theme scheduler for macOS — <b>mo</b>rning, <b>no</b>on, and <b>ni</b>ght (and evening).
</p>

A Swift CLI daemon that automatically switches your Mac's appearance (light/dark) **and** wallpaper at configured times throughout the day. Ships with defaults for the four Tahoe aerials (e.g. so you can get Tahoe morning when it's morning, day when it's day, and so on).

## Install

```
brew install bn-l/tap/mononi
```

Or build from source:

```
swift build -c release
cp .build/release/mononi /usr/local/bin/
```

## Usage

```
mononi start          # Install and start the launchd daemon
mononi stop           # Stop and uninstall the daemon
mononi status         # Show daemon status and current/next mode
mononi apply          # Apply the current mode immediately (no daemon needed)
mononi apply -m night # Apply a specific mode
mononi wallpapers     # List available wallpapers
mononi config show    # Print current config as JSON
mononi config set evening --time 18:00 --appearance dark --wallpaper "Tahoe Evening"
mononi config location --city "Sydney"                     # Follow the sun at a city
mononi config location --latitude -33.87 --longitude 151.21  # Follow the sun at coordinates
mononi config location --clear                             # Go back to fixed start times
mononi config set evening --offset -15                     # Start evening 15 minutes before sunset
mononi config path    # Print config file location
mononi config reset   # Reset to defaults
```

Every command prints any problems in the config file to stderr before it runs, such as a misspelt key, a value out of range or a wallpaper that does not exist.

## Default config

Stored at `~/.config/mononi/config.json`:

```json
{
  "modes": {
    "morning": { "startTime": "6:30",  "appearance": "light", "wallpaper": "Tahoe Morning" },
    "day":     { "startTime": "12:00", "appearance": "light", "wallpaper": "Tahoe Day" },
    "evening": { "startTime": "17:30", "appearance": "dark",  "wallpaper": "Tahoe Evening" },
    "night":   { "startTime": "21:00", "appearance": "dark",  "wallpaper": "Tahoe Night" }
  }
}
```

## Location aware auto mode

Add a `location` and the four stages follow the sun with daylight saving handled automatically:

| Mode | Starts at |
|------|-----------|
| `morning` | sunrise |
| `day` | solar noon |
| `evening` | sunset |
| `night` | dusk |

`offsetMinutes` moves a stage from its sun event; negative values are earlier. It must be between -720 and 720.

```json
{
  "location": { "latitude": -33.8714, "longitude": 151.2125 },
  "modes": {
    "morning": { "startTime": "6:30",  "offsetMinutes": 15,  "appearance": "light", "wallpaper": "Tahoe Morning" },
    "day":     { "startTime": "12:00", "offsetMinutes": -90, "appearance": "light", "wallpaper": "Tahoe Day" },
    "evening": { "startTime": "17:30",                       "appearance": "dark",  "wallpaper": "Tahoe Evening" },
    "night":   { "startTime": "21:00", "offsetMinutes": 60,  "appearance": "dark",  "wallpaper": "Tahoe Night" }
  }
}
```

- With a location set, these four modes ignore their `startTime`, except as the fallback below. Clearing the location (`mononi config location --clear`) returns every mode to its `startTime`.
- Modes with any other name keep their fixed `startTime`.
- Sun times are exact moments, so a stage keeps its place relative to the sun across a DST change and its clock time moves by an hour, as sunset does. A fixed `startTime` is local clock time; one the clocks skip, such as 2:30 when they go forward, starts at 3:00.
- On days when a sun event does not happen, such as midsummer above about 60° latitude, that stage uses its `startTime`.
- `mononi status` lists today's times and where each came from.

`--city` looks the name up in a built-in list of 7,342 places (fully offline). Add a region, country or country code after a comma when a name is shared, as in `"Newcastle, Australia"` or `"Portland, US"`. Sun times come from [Solar](https://github.com/ceeK/Solar).

## How it works

The daemon runs as a launchd user agent (`com.mononi.agent`). It works out each day's times again after every transition, and on start and at each transition time it:

1. Sets appearance via `osascript` (AppleScript → System Events)
2. Writes the wallpaper selection to `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`
3. Restarts `WallpaperAgent` to pick up the change

### Supported wallpaper types

| Type | Location | Set via |
|------|----------|---------|
| Aerials (video) | `~/Library/Application Support/com.apple.wallpaper/aerials/videos/` | Plist with `com.apple.wallpaper.choice.aerials` provider + `assetID` |
| Static (.heic, .madesktop) | `/System/Library/Desktop Pictures/` | `NSWorkspace.setDesktopImageURL` |

Aerial names are matched against `accessibilityLabel` in the aerials manifest (`entries.json`). The video must be downloaded first (via System Settings > Wallpaper).

## Development notes

See [DEVLOG.md](DEVLOG.md) for the reverse-engineering journey behind programmatic aerial wallpaper switching on macOS Tahoe.
