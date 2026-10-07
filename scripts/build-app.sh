#!/usr/bin/env bash
# Membangun DeskWidgets.app (universal), ad-hoc sign, lalu mengemasnya jadi zip + sha256.
# Pemakaian: scripts/build-app.sh [versi]      contoh: scripts/build-app.sh 0.1.0
# Env: ARCHS="arm64"  untuk build satu arsitektur saja (lebih cepat saat development).
set -euo pipefail

VERSION="${1:-0.1.0}"
ARCHS="${ARCHS:-arm64 x86_64}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/DeskWidgets.app"
NAME="DeskWidgets-v${VERSION}-macos-universal"

cd "$ROOT"
ARCH_FLAGS=()
for a in $ARCHS; do ARCH_FLAGS+=(--arch "$a"); done

echo "==> Build release ($ARCHS)"
swift build -c release "${ARCH_FLAGS[@]}"
BIN="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)/DeskWidgets"

echo "==> Membuat bundle .app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DeskWidgets"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>DeskWidgets</string>
    <key>CFBundleIdentifier</key><string>com.deskwidgets.app</string>
    <key>CFBundleName</key><string>DeskWidgets</string>
    <key>CFBundleDisplayName</key><string>DeskWidgets</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Ikon opsional: letakkan AppIcon.icns di folder Resources/ repo ini.
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
fi

echo "==> Ad-hoc sign"
codesign --force --deep -s - "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Mengemas"
mkdir -p "$DIST"
rm -f "$DIST/$NAME.zip" "$DIST/$NAME.zip.sha256"
ditto -c -k --keepParent "$APP" "$DIST/$NAME.zip"
(cd "$DIST" && shasum -a 256 "$NAME.zip" > "$NAME.zip.sha256")

echo
echo "Selesai:"
echo "  $APP"
echo "  $DIST/$NAME.zip"
echo "  $DIST/$NAME.zip.sha256"
