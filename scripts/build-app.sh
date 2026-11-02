#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Questo script crea un'app macOS e richiede un Mac." >&2
  exit 1
fi

swift build -c release --product FolderSpanner --arch arm64
APP="$ROOT/dist/FolderSpanner.app"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/.build/arm64-apple-macosx/release/FolderSpanner" "$APP/Contents/MacOS/FolderSpanner"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>FolderSpanner</string>
  <key>CFBundleIdentifier</key><string>it.frapo.folder-spanner</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>FolderSpanner</string>
  <key>CFBundleDisplayName</key><string>FolderSpanner</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - --timestamp=none "$APP"
echo "App pronta: $APP"
