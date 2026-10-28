#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
python3 "$ROOT/scripts/package-ui.py"
APP="$HOME/Library/Application Support/LocalMind"
DATA="$ROOT/data"
AGENTS="$HOME/Library/LaunchAgents"
PYTHON=$(command -v python3)
launchctl bootout "gui/$(id -u)" "$AGENTS/com.localmind.agent.plist" >/dev/null 2>&1 || true
mkdir -p "$APP/bin" "$APP/logs" "$AGENTS"
swiftc -parse-as-library "$ROOT/native/Capture.swift" -O -o "$APP/bin/localmind-capture"
if [ ! -f "$DATA/localmind.sqlite3" ] && [ -f "$APP/localmind.sqlite3" ]; then
  mkdir -p "$DATA/screenshots"
  cp "$APP/localmind.sqlite3" "$DATA/localmind.sqlite3"
  if [ -f "$APP/localmind.sqlite3-wal" ]; then cp "$APP/localmind.sqlite3-wal" "$DATA/localmind.sqlite3-wal"; fi
  if [ -d "$APP/screenshots" ]; then ditto "$APP/screenshots" "$DATA/screenshots"; fi
  echo "旧数据已迁移到：$DATA"
fi
mkdir -p "$DATA"
cat > "$AGENTS/com.localmind.agent.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.localmind.agent</string>
<key>ProgramArguments</key><array><string>$PYTHON</string><string>$ROOT/localmind/server.py</string></array>
<key>EnvironmentVariables</key><dict><key>LOCALMIND_ROOT</key><string>$ROOT</string><key>LOCALMIND_DATA_DIR</key><string>$DATA</string><key>LOCALMIND_CAPTURE_BIN</key><string>$APP/bin/localmind-capture</string></dict>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>StandardOutPath</key><string>$APP/logs/launchd.out.log</string>
<key>StandardErrorPath</key><string>$APP/logs/launchd.err.log</string>
<key>WorkingDirectory</key><string>$ROOT</string>
</dict></plist>
EOF
launchctl bootstrap "gui/$(id -u)" "$AGENTS/com.localmind.agent.plist"
echo "LocalMind 已注册。访问 http://127.0.0.1:8787"
echo "个人数据目录：$DATA"
echo "首次截图请在网页中确认，并在系统设置授予屏幕录制权限。"
