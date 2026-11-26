#!/usr/bin/env bash
set -euo pipefail

REPO="wajipu/koklam-pr-bot"
DATA_DIR="$HOME/.koklam-pr-bot"
LEGACY_DATA_DIR="$HOME/.codex-pr-bot"
APP_DEST="/Applications/KoKLam PR Bot.app"
DAEMON_BIN="$APP_DEST/Contents/MacOS/koklam-pr-botd"
PLIST="$HOME/Library/LaunchAgents/com.wajipu.koklam-pr-bot.plist"

echo "==> Installing / updating KoKLam PR Bot from GitHub Releases ($REPO)..."
if [[ ! -d "$DATA_DIR" && -d "$LEGACY_DATA_DIR" ]]; then
  echo "==> Migrating legacy config from $LEGACY_DATA_DIR to $DATA_DIR..."
  cp -R "$LEGACY_DATA_DIR" "$DATA_DIR"
fi
mkdir -p "$DATA_DIR" "$HOME/Library/LaunchAgents"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

DOWNLOAD_URL="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | python3 -c 'import sys,json; assets=json.load(sys.stdin).get("assets",[]); print(next((a["browser_download_url"] for a in assets if a["name"].endswith(".zip")), ""))' 2>/dev/null || true)"

stop_existing() {
  pkill -x KoKLamPRBot 2>/dev/null || true
  pkill -x CodexPRBot 2>/dev/null || true
  launchctl bootout "gui/$(id -u)/com.wajipu.koklam-pr-bot" 2>/dev/null || true
  launchctl bootout "gui/$(id -u)/com.wajipu.codex-pr-bot" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/com.wajipu.codex-pr-bot.plist"
  rm -rf "/Applications/Codex PR Bot.app"
}

if [[ -n "$DOWNLOAD_URL" ]]; then
  echo "==> Downloading $DOWNLOAD_URL"
  curl -fsSL "$DOWNLOAD_URL" -o "$TMP_DIR/app.zip"
  ditto -x -k "$TMP_DIR/app.zip" "$TMP_DIR/out"
  stop_existing
  rm -rf "$APP_DEST"
  cp -R "$TMP_DIR/out/KoKLam PR Bot.app" "$APP_DEST"
else
  echo "==> Building from local source..."
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  "$SCRIPT_DIR/scripts/build-app.sh" "3.3.0" "$TMP_DIR"
  stop_existing
  rm -rf "$APP_DEST"
  cp -R "$TMP_DIR/KoKLam PR Bot.app" "$APP_DEST"
fi

if [[ ! -f "$DATA_DIR/config.json" ]]; then
  cp "$APP_DEST/Contents/Resources/config.example.json" "$DATA_DIR/config.json"
  echo "==> Created default config at $DATA_DIR/config.json — edit it to add your GitHub repos!"
fi

NODE_BIN_DIR="$(dirname "$(command -v codex 2>/dev/null || echo /opt/homebrew/bin/codex)")"
cat > "$PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.wajipu.koklam-pr-bot</string>
    <key>ProgramArguments</key>
    <array>
        <string>$DAEMON_BIN</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$HOME/.local/bin:$NODE_BIN_DIR:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
        <key>HOME</key>
        <string>$HOME</string>
    </dict>
    <key>KeepAlive</key>
    <true/>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$DATA_DIR/bot.log</string>
    <key>StandardErrorPath</key>
    <string>$DATA_DIR/bot.log</string>
</dict>
</plist>
EOF

sleep 1
launchctl bootstrap "gui/$(id -u)" "$PLIST"
open "$APP_DEST"
echo "==> Done! KoKLam PR Bot (Go + SwiftUI) is running in your macOS menu bar."
