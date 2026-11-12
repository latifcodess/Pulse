#!/usr/bin/env bash
# Image disque d'une version : produit, dans build/release/, Pulse.app,
# Pulse-<version>.dmg et Pulse-<version>.dmg.sha256.
# L'app vient de scripts/build.sh (Xcode, universelle Apple Silicon + Intel).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

RELEASE="$ROOT/build/release"
"$ROOT/scripts/build.sh"

# La version vient de project.yml (MARKETING_VERSION), lue dans l'app construite.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT/build/Pulse.app/Contents/Info.plist")"

rm -rf "$RELEASE"
mkdir -p "$RELEASE"
ditto "$ROOT/build/Pulse.app" "$RELEASE/Pulse.app"

echo "==> Création de l'image disque"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto "$RELEASE/Pulse.app" "$STAGING/Pulse.app"
# Raccourci vers Applications : on installe en glissant l'app dessus.
ln -s /Applications "$STAGING/Applications"
DMG="$RELEASE/Pulse-$VERSION.dmg"
hdiutil create -volname "Pulse" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null

# L'empreinte du DMG. Pulse la télécharge avec la mise à jour et refuse
# d'installer un DMG qui ne lui correspond pas.
(cd "$RELEASE" && shasum -a 256 "Pulse-$VERSION.dmg" > "Pulse-$VERSION.dmg.sha256")

echo "==> Terminé : $DMG"
echo "    Pour publier : release GitHub « v$VERSION », avec le DMG et son fichier .sha256."
