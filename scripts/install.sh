#!/usr/bin/env bash
set -euo pipefail

REPO="wajipu/codex-pr-bot"
DATA_DIR="$HOME/.codex-pr-bot"
APP_DEST="/Applications/Codex PR Bot.app"
PLIST="$HOME/Library/LaunchAgents/com.wajipu.codex-pr-bot.plist"

echo "==> Installing / updating Codex PR Bot from GitHub Releases ($REPO)..."
mkdir -p "$DATA_DIR" "$HOME/Library/LaunchAgents"

# Download latest release zip if available, otherwise build from local repo
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

DOWNLOAD_URL="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | python3 -c 'import sys,json; assets=json.load(sys.stdin).get("assets",[]); print(next((a["browser_download_url"] for a in assets if a["name"].endswith(".zip")), ""))' 2>/dev/null || true)"

if [[ -n "$DOWNLOAD_URL" ]]; then
  echo "==> Downloading $DOWNLOAD_URL"
  curl -fsSL "$DOWNLOAD_URL" -o "$TMP_DIR/app.zip"
  ditto -x -k "$TMP_DIR/app.zip" "$TMP_DIR/out"
  pkill -x CodexPRBot 2>/dev/null || true
  rm -rf "$APP_DEST"
  cp -R "$TMP_DIR/out/Codex PR Bot.app" "$APP_DEST"
  cp "$APP_DEST/Contents/Resources/server.py" "$DATA_DIR/server.py"
  chmod +x "$DATA_DIR/server.py"
else
  echo "==> No release zip found yet; building from local source..."
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  cp "$SCRIPT_DIR/daemon/server.py" "$DATA_DIR/server.py"
  chmod +x "$DATA_DIR/server.py"
  "$SCRIPT_DIR/scripts/build-app.sh" "1.0.0" "$TMP_DIR"
  pkill -x CodexPRBot 2>/dev/null || true
  rm -rf "$APP_DEST"
  cp -R "$TMP_DIR/Codex PR Bot.app" "$APP_DEST"
fi

if [[ ! -f "$DATA_DIR/config.json" ]]; then
  if [[ -f "$APP_DEST/Contents/Resources/config.example.json" ]]; then
    cp "$APP_DEST/Contents/Resources/config.example.json" "$DATA_DIR/config.json"
  fi
  echo "==> Created default config at $DATA_DIR/config.json — edit it to add your GitHub repos!"
fi

NODE_BIN_DIR="$(dirname "$(command -v codex 2>/dev/null || echo /opt/homebrew/bin/codex)")"
cat > "$PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.wajipu.codex-pr-bot</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>$DATA_DIR/server.py</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$NODE_BIN_DIR:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
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

launchctl bootout "gui/$(id -u)/com.wajipu.codex-pr-bot" 2>/dev/null || true
sleep 1
launchctl bootstrap "gui/$(id -u)" "$PLIST"
open "$APP_DEST"
echo "==> Done! Codex PR Bot is running in your macOS menu bar."
