#!/usr/bin/env bash
#
# Builds SKALA-2000.app and packs it for direct distribution: a zip and a disk image in
# ./build. Ad hoc signed; Developer ID signing and notarization come later.
#
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(cat "$ROOT/VERSION")"
"$ROOT/scripts/build-app.sh"
cd "$ROOT/build"
rm -f "SKALA-2000-$VERSION.zip" "SKALA-2000-$VERSION.dmg"
ditto -c -k --keepParent SKALA-2000.app "SKALA-2000-$VERSION.zip"
STAGE="$(mktemp -d)"
cp -R SKALA-2000.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "SKALA-2000 $VERSION" -srcfolder "$STAGE" -ov -format UDZO "SKALA-2000-$VERSION.dmg"
rm -rf "$STAGE"
echo "✓ build/SKALA-2000-$VERSION.zip"
echo "✓ build/SKALA-2000-$VERSION.dmg"
