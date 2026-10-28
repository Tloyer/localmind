#!/bin/sh
set -eu
AGENT="$HOME/Library/LaunchAgents/com.localmind.agent.plist"
APP="$HOME/Library/Application Support/LocalMind"
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DATA="$ROOT/data"
launchctl bootout "gui/$(id -u)" "$AGENT" >/dev/null 2>&1 || true
rm -f "$AGENT"
if [ "${1:-}" = "--delete-data" ]; then
  rm -rf "$APP" "$DATA"
  echo "已删除 LocalMind 运行时与个人数据。"
else
  echo "已卸载登录启动项；个人数据保留在：$DATA"
  echo "确认删除全部 LocalMind 数据时运行：$0 --delete-data"
fi
