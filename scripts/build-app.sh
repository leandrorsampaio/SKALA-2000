#!/usr/bin/env bash
#
# Builds SKALA-2000.app into ./build.
#
#   scripts/build-app.sh            release build
#   scripts/build-app.sh --debug    debug configuration
#
# Signing is ad hoc, which is enough to run on this Mac. SKALA-2000 is distributed
# directly and never sandboxed: it has to read ~/.claude.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="release"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug) CONFIGURATION="debug"; shift ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done

PRODUCT="SKALA-2000"
BUNDLE_ID="${SKALA_BUNDLE_ID:-com.leandrorossisampaio.skala2000}"
VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo 0.1.0)"
BUILD_NUMBER="${SKALA_BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"
APP="$ROOT/build/$PRODUCT.app"

echo "▸ Building ($CONFIGURATION)…"
swift build -c "$CONFIGURATION" --package-path "$ROOT" --product "$PRODUCT"
BIN_PATH="$(swift build -c "$CONFIGURATION" --package-path "$ROOT" --show-bin-path)"

echo "▸ Assembling $PRODUCT.app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/$PRODUCT" "$APP/Contents/MacOS/$PRODUCT"
[[ -f "$ROOT/Resources/AppIcon.icns" ]] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
# The desk's five faces, with their licences. Registered for this process only.
cp -R "$ROOT/Resources/Fonts" "$APP/Contents/Resources/Fonts"
# The hook snippet the Settings window installs, and the scripted day's text.
cp "$ROOT/scripts/claude-hooks.json" "$APP/Contents/Resources/claude-hooks.json"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>          <string>en</string>
    <key>CFBundleExecutable</key>                 <string>$PRODUCT</string>
    <key>CFBundleIdentifier</key>                 <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>      <string>6.0</string>
    <key>CFBundleName</key>                       <string>$PRODUCT</string>
    <key>CFBundleDisplayName</key>                <string>$PRODUCT</string>
    <key>CFBundleIconFile</key>                   <string>AppIcon</string>
    <key>CFBundlePackageType</key>                <string>APPL</string>
    <key>CFBundleShortVersionString</key>         <string>$VERSION</string>
    <key>CFBundleVersion</key>                    <string>$BUILD_NUMBER</string>
    <key>LSApplicationCategoryType</key>          <string>public.app-category.developer-tools</string>
    <key>LSMinimumSystemVersion</key>             <string>14.0</string>
    <key>NSHighResolutionCapable</key>            <true/>
    <key>NSHumanReadableCopyright</key>           <string>Instrument Works No 4 · Dresden · 1972. MIT licensed.</string>
    <key>NSSupportsAutomaticTermination</key>     <false/>
    <key>NSSupportsSuddenTermination</key>        <false/>
</dict>
</plist>
PLIST

echo "▸ Signing (ad hoc)…"
codesign --force --sign - "$APP" >/dev/null 2>&1 \
    || echo "  (ad-hoc signing failed; the app still runs locally)"

echo "✓ $APP"
