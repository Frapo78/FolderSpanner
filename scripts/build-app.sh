#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "La creazione di FolderSpanner.app richiede macOS." >&2
  exit 1
fi

APP_VERSION="${APP_VERSION:-0.2.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "APP_VERSION deve essere X.Y.Z e BUILD_NUMBER numerico." >&2
  exit 1
fi

python3 scripts/check-localizations.py
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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$EXECUTABLE" "$APP/Contents/MacOS/FolderSpanner"

# Native bundle localization is required for SwiftUI and Foundation messages.
for folder in "$ROOT"/Sources/FolderSpannerCore/Resources/*.lproj; do
  test -d "$folder" || { echo "Localizations are missing" >&2; exit 1; }
  cp -R "$folder" "$APP/Contents/Resources/"
done
for language in it en de fr es zh-Hans ja; do
  test -s "$APP/Contents/Resources/$language.lproj/Localizable.strings" || { echo "Missing translation: $language" >&2; exit 1; }
done

# Generate the real PNG bitmap and macOS ICNS without third-party dependencies.
ICON="$APP/Contents/Resources/FolderSpanner-1024.png"
swift scripts/generate-icon.swift "$ICON"
ICONSET="$ROOT/dist/FolderSpanner.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -s format png -z "$size" "$size" "$ICON" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -s format png -z "$retina" "$retina" "$ICON" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"
SOURCE_SHA="${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo local)}"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>FolderSpanner</string>
  <key>CFBundleIdentifier</key><string>it.frapo.folder-spanner</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>FolderSpanner</string>
  <key>CFBundleDevelopmentRegion</key><string>it</string>
  <key>CFBundleDisplayName</key><string>FolderSpanner</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>FSGitSHA</key><string>$SOURCE_SHA</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

plutil -lint "$APP/Contents/Info.plist"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
echo "App Apple Silicon pronta: $APP (versione $APP_VERSION, build $BUILD_NUMBER)"
