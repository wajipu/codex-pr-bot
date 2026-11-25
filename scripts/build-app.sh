#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-2.0.0}"
OUT_DIR="${2:-dist}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$OUT_DIR"
ABS_OUT_DIR="$(cd "$OUT_DIR" && pwd)"
APP_DIR="$ABS_OUT_DIR/Codex PR Bot.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cat > "$APP_DIR/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>CodexPRBot</string>
    <key>CFBundleIdentifier</key>
    <string>com.wajipu.codex-pr-bot</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Codex PR Bot</string>
    <key>CFBundleDisplayName</key>
    <string>Codex PR Bot</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
</dict>
</plist>
EOF

cp "$ROOT_DIR/config.example.json" "$APP_DIR/Contents/Resources/config.example.json"

echo "==> Building Go daemon (codex-pr-botd)..."
(cd "$ROOT_DIR/daemon" && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o "$APP_DIR/Contents/MacOS/codex-pr-botd" .)

echo "==> Building SwiftUI menu bar app (CodexPRBot)..."
swiftc -O -parse-as-library -framework SwiftUI -framework AppKit -framework UserNotifications \
  "$ROOT_DIR/app/CodexPRBot.swift" \
  -o "$APP_DIR/Contents/MacOS/CodexPRBot"

codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true
ls -lh "$APP_DIR/Contents/MacOS/"
echo "Built: $APP_DIR (v$VERSION)"
