#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SOURCE="$ROOT/dist/LocalMind.app"
DEST="$HOME/Applications/LocalMind.app"
if [ ! -x "$SOURCE/Contents/MacOS/LocalMind" ]; then
  "$ROOT/scripts/build-app.sh"
fi
mkdir -p "$HOME/Applications"
ditto "$SOURCE" "$DEST"
echo "LocalMind 已安装到：$DEST"
echo "在 Finder → 应用程序中双击 LocalMind 即可启动模型服务和本机窗口。"
