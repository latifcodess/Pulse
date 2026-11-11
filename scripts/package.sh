#!/usr/bin/env bash
# Build universel (Apple Silicon + Intel) et image disque :
# produit build/release/Pulse.app et build/release/Pulse-<version>.dmg.
#
# Chaque architecture est compilée séparément, puis les deux sont réunies
# avec lipo (pas besoin de Xcode, les Command Line Tools suffisent).
# Prérequis : rustup target add aarch64-apple-darwin x86_64-apple-darwin
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

RELEASE="$ROOT/build/release"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT/app/Info.plist")"
UNIVERSAL_LIB_DIR="$ROOT/core/target/universal/release"

rm -rf "$RELEASE"
mkdir -p "$RELEASE" "$UNIVERSAL_LIB_DIR"

echo "==> Compilation de core/ pour Apple Silicon et Intel"
for target in aarch64-apple-darwin x86_64-apple-darwin; do
    (cd "$ROOT/core" && cargo build --release --target "$target")
done
lipo -create \
    "$ROOT/core/target/aarch64-apple-darwin/release/libpulse_core.a" \
    "$ROOT/core/target/x86_64-apple-darwin/release/libpulse_core.a" \
    -output "$UNIVERSAL_LIB_DIR/libpulse_core.a"

generate_bindings target/aarch64-apple-darwin/release/libpulse_core.a

echo "==> Compilation de app/ pour Apple Silicon et Intel"
# Un dossier de build à part, pour ne pas mélanger avec scripts/build.sh.
SCRATCH="$ROOT/build/.swiftpm-universal"
binaries=()
for arch in arm64 x86_64; do
    (cd "$ROOT/app" && PULSE_CORE_LIB_DIR="$UNIVERSAL_LIB_DIR" \
        swift build -c release --arch "$arch" --scratch-path "$SCRATCH")
    bin_dir="$(cd "$ROOT/app" && PULSE_CORE_LIB_DIR="$UNIVERSAL_LIB_DIR" \
        swift build -c release --arch "$arch" --scratch-path "$SCRATCH" --show-bin-path)"
    binaries+=("$bin_dir/Pulse")
done
lipo -create "${binaries[@]}" -output "$RELEASE/Pulse"

assemble_app "$RELEASE/Pulse" "$RELEASE/Pulse.app"
rm "$RELEASE/Pulse"
echo "==> Architectures : $(lipo -archs "$RELEASE/Pulse.app/Contents/MacOS/Pulse")"

echo "==> Création de l'image disque"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$RELEASE/Pulse.app" "$STAGING/"
# Raccourci vers Applications : on installe en glissant l'app dessus.
ln -s /Applications "$STAGING/Applications"
DMG="$RELEASE/Pulse-$VERSION.dmg"
hdiutil create -volname "Pulse" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null

echo "==> Terminé : $DMG"
