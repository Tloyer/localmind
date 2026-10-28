#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
python3 "$ROOT/scripts/package-ui.py"
APP="$ROOT/dist/LocalMind.app"
CONTENTS="$APP/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
if [ -f "$ROOT/assets/LocalMind.icns" ]; then
  cp "$ROOT/assets/LocalMind.icns" "$CONTENTS/Resources/LocalMind.icns"
fi
cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>LocalMind</string>
<key>CFBundleDisplayName</key><string>LocalMind 本地记忆</string>
<key>CFBundleIdentifier</key><string>com.localmind.desktop</string>
<key>CFBundleVersion</key><string>0.2.0</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>LocalMind</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
<key>LocalMindRoot</key><string>$ROOT</string>
</dict></plist>
EOF
clang -fobjc-arc -O2 \
  -framework Cocoa -framework WebKit \
  "$ROOT/native/LocalMindApp.m" \
  -o "$CONTENTS/MacOS/LocalMind"
chmod +x "$CONTENTS/MacOS/LocalMind"
plutil -lint "$CONTENTS/Info.plist"
echo "已构建：$APP"
