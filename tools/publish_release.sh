#!/bin/zsh
set -euo pipefail

REPO="Danu-W/Shortirfilewindows"
TAG="${1:-v1.2.0}"
TITLE="Shortir File ${TAG#v}"
ART="/Users/storyties/ShortirFileFlutter/build/release-artifacts"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI belum terpasang. Jalankan dulu: brew install gh"
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "gh belum login. Jalankan dulu: gh auth login"
  exit 1
fi

gh release create "$TAG" \
  "$ART/shortir-file-macos.zip" \
  "$ART/shortir-file-macos.zip.sha256" \
  "$ART/shortir-file-android.apk" \
  "$ART/shortir-file-android.apk.sha256" \
  --repo "$REPO" \
  --title "$TITLE" \
  --notes "Versi ${TAG#v} — Shortir File (macOS + Android).\n\nUnduh: zip macOS untuk macOS, APK untuk Android."

echo "Release $TAG dibuat."
