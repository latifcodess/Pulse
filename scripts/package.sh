#!/usr/bin/env bash
# Image disque d'une version : produit, dans build/release/, Pulse.app,
# Pulse-<version>.dmg et Pulse-<version>.dmg.sha256.
# L'app vient de scripts/build.sh (Xcode, universelle Apple Silicon + Intel).
#
# Chaque appel augmente le numéro de build (CURRENT_PROJECT_VERSION dans
# project.yml), commun à l'app et au widget : macOS sait ainsi que le widget
# a changé et ne garde pas l'ancien. Pense à commiter project.yml ensuite.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

RELEASE="$ROOT/build/release"
PROJECT="$ROOT/project.yml"

# --- Numéro de build ---------------------------------------------------------
CURRENT_BUILD="$(sed -nE 's/^ *CURRENT_PROJECT_VERSION: *"?([0-9]+)"?.*/\1/p' "$PROJECT" | head -1)"
if [[ -z "$CURRENT_BUILD" ]]; then
    echo "erreur : CURRENT_PROJECT_VERSION introuvable dans project.yml" >&2
    exit 1
fi
NEW_BUILD=$((CURRENT_BUILD + 1))
sed -i '' -E "s/^( *CURRENT_PROJECT_VERSION: *)\"?[0-9]+\"?/\1\"$NEW_BUILD\"/" "$PROJECT"
echo "==> Numéro de build : $CURRENT_BUILD → $NEW_BUILD"

"$ROOT/scripts/build.sh"

APP="$ROOT/build/Pulse.app"
WIDGET="$APP/Contents/PlugIns/PulseWidget.appex"

# --- Vérification du widget embarqué -------------------------------------------
plist() { /usr/libexec/PlistBuddy -c "Print $2" "$1/Contents/Info.plist" 2>/dev/null || true; }
team() { codesign -dv "$1" 2>&1 | sed -n 's/^TeamIdentifier=//p'; }
# Le premier App Group des entitlements (la clé contient des points : pas de plutil -extract).
group() { codesign -d --entitlements :- "$1" 2>/dev/null | grep -A2 "application-groups" | sed -nE 's/.*<string>(.*)<\/string>.*/\1/p' | head -1; }

fail() { echo "erreur : $1" >&2; exit 1; }
[[ -d "$WIDGET" ]] || fail "PulseWidget.appex absent de Pulse.app/Contents/PlugIns"
VERSION="$(plist "$APP" CFBundleShortVersionString)"
[[ "$(plist "$WIDGET" CFBundleShortVersionString)" == "$VERSION" ]] || fail "version du widget ≠ version de l'app ($VERSION)"
[[ "$(plist "$APP" CFBundleVersion)" == "$NEW_BUILD" ]] || fail "build de l'app ≠ $NEW_BUILD"
[[ "$(plist "$WIDGET" CFBundleVersion)" == "$NEW_BUILD" ]] || fail "build du widget ≠ $NEW_BUILD"
[[ -n "$(team "$APP")" && "$(team "$APP")" == "$(team "$WIDGET")" ]] || fail "l'app et le widget ne sont pas signés par la même équipe"
[[ -n "$(group "$APP")" && "$(group "$APP")" == "$(group "$WIDGET")" ]] || fail "l'app et le widget n'ont pas le même App Group"
echo "==> Widget vérifié : $VERSION ($NEW_BUILD), équipe $(team "$APP"), App Group $(group "$APP")"

# --- Image disque --------------------------------------------------------------
rm -rf "$RELEASE"
mkdir -p "$RELEASE"
ditto "$APP" "$RELEASE/Pulse.app"

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
echo "    Commite project.yml (build $NEW_BUILD), puis publie la release GitHub « v$VERSION » avec le DMG et son fichier .sha256."
