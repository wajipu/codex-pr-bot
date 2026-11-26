#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-2.0.0}"
OUT_DIR="${2:-dist}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$OUT_DIR"
ABS_OUT_DIR="$(cd "$OUT_DIR" && pwd)"
APP_DIR="$ABS_OUT_DIR/KoKLam PR Bot.app"

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
    <string>KoKLamPRBot</string>
    <key>CFBundleIdentifier</key>
    <string>com.wajipu.koklam-pr-bot</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>KoKLam PR Bot</string>
    <key>CFBundleDisplayName</key>
    <string>KoKLam PR Bot</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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

if [[ -f "$ROOT_DIR/app/AppIcon.png" ]]; then
  echo "==> Generating AppIcon.icns..."
  ICONSET_DIR="$ABS_OUT_DIR/AppIcon.iconset"
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"
  for sz in 16 32 128 256 512; do
    sips -z $sz $sz "$ROOT_DIR/app/AppIcon.png" --out "$ICONSET_DIR/icon_${sz}x${sz}.png" >/dev/null
    sz2=$((sz * 2))
    sips -z $sz2 $sz2 "$ROOT_DIR/app/AppIcon.png" --out "$ICONSET_DIR/icon_${sz}x${sz}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET_DIR"
fi

echo "==> Building Go daemon (koklam-pr-botd)..."
(cd "$ROOT_DIR/daemon" && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o "$APP_DIR/Contents/MacOS/koklam-pr-botd" .)

echo "==> Building SwiftUI menu bar app (KoKLamPRBot)..."
swiftc -O -parse-as-library -framework SwiftUI -framework AppKit -framework UserNotifications \
  "$ROOT_DIR/app/KoKLamPRBot.swift" \
  -o "$APP_DIR/Contents/MacOS/KoKLamPRBot"

codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true
ls -lh "$APP_DIR/Contents/MacOS/"
echo "Built: $APP_DIR (v$VERSION)"
