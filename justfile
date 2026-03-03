name := "mononi"
app_name := "Mononi"
bundle_id := "com.mononi.agent"
version := `rg -o 'version: "([^"]+)"' -r '$1' Sources/Mononi/Mononi.swift`

# List available recipes
default:
    @just --list

# Build release binary and stamp icon
build:
    swift build -c release
    @fileicon set .build/release/{{name}} icon.png >/dev/null

# Run in debug mode
run *ARGS:
    swift run {{name}} {{ARGS}}

# Run tests
test:
    swift test

# Generate .icns from icon.png
[private]
icns:
    #!/usr/bin/env bash
    set -euo pipefail
    dir=".build/icon.iconset"
    mkdir -p "$dir"
    for size in 16 32 128 256 512; do
        sips -z $size $size icon.png --out "$dir/icon_${size}x${size}.png" >/dev/null
        double=$((size * 2))
        sips -z $double $double icon.png --out "$dir/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$dir" -o .build/AppIcon.icns

# Build .app bundle
app: build icns
    #!/usr/bin/env bash
    set -euo pipefail
    contents=".build/{{app_name}}.app/Contents"
    mkdir -p "$contents/MacOS" "$contents/Resources"
    cp .build/release/{{name}} "$contents/MacOS/{{name}}"
    cp .build/AppIcon.icns "$contents/Resources/AppIcon.icns"
    cat > "$contents/Info.plist" << 'PLIST'
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>CFBundleExecutable</key>
        <string>mononi</string>
        <key>CFBundleIconFile</key>
        <string>AppIcon</string>
        <key>CFBundleIdentifier</key>
        <string>com.mononi.agent</string>
        <key>CFBundleName</key>
        <string>Mononi</string>
        <key>CFBundlePackageType</key>
        <string>APPL</string>
        <key>CFBundleVersion</key>
        <string>{{version}}</string>
        <key>CFBundleShortVersionString</key>
        <string>{{version}}</string>
        <key>LSUIElement</key>
        <true/>
    </dict>
    </plist>
    PLIST
    echo "Built {{app_name}}.app → .build/{{app_name}}.app"

# Clean build artifacts
clean:
    swift package clean
