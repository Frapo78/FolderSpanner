#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "La creazione di FolderSpanner.app richiede macOS." >&2
  exit 1
fi

APP_VERSION="${APP_VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "APP_VERSION deve essere X.Y.Z e BUILD_NUMBER numerico." >&2
  exit 1
fi

swift build -c release --product FolderSpanner --arch arm64
BIN_DIR="$(swift build -c release --product FolderSpanner --arch arm64 --show-bin-path)"
EXECUTABLE="$BIN_DIR/FolderSpanner"
test -f "$EXECUTABLE" || { echo "Eseguibile non trovato: $EXECUTABLE" >&2; exit 1; }
if ! lipo -archs "$EXECUTABLE" | grep -qw arm64; then
  echo "L'eseguibile generato non è arm64." >&2
  exit 1
fi

APP="$ROOT/dist/FolderSpanner.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$EXECUTABLE" "$APP/Contents/MacOS/FolderSpanner"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>FolderSpanner</string>
  <key>CFBundleIdentifier</key><string>it.frapo.folder-spanner</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>FolderSpanner</string>
  <key>CFBundleDisplayName</key><string>FolderSpanner</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "App Apple Silicon pronta: $APP (versione $APP_VERSION, build $BUILD_NUMBER)"
