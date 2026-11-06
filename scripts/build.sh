#!/usr/bin/env bash
# Build complet : produit build/Pulse.app, signé ad hoc.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Pulse.app"
SWIFT_DIR="$ROOT/app/Sources/PulseCore"
FFI_DIR="$ROOT/app/Sources/pulse_coreFFI"

echo "==> Compilation de core/ (lib statique Rust)"
(cd "$ROOT/core" && cargo build --release)

echo "==> Génération des bindings Swift"
GENERATED="$(mktemp -d)"
trap 'rm -rf "$GENERATED"' EXIT
(cd "$ROOT/core" && cargo run --release --quiet --bin uniffi-bindgen -- generate \
    --library target/release/libpulse_core.a \
    --language swift \
    --out-dir "$GENERATED")

rm -rf "$SWIFT_DIR" "$FFI_DIR"
mkdir -p "$SWIFT_DIR" "$FFI_DIR"
mv "$GENERATED/pulse_core.swift" "$SWIFT_DIR/"
mv "$GENERATED/pulse_coreFFI.h" "$FFI_DIR/"
# SwiftPM attend exactement le nom module.modulemap.
mv "$GENERATED/pulse_coreFFI.modulemap" "$FFI_DIR/module.modulemap"

echo "==> Compilation de app/ (Swift)"
(cd "$ROOT/app" && swift build -c release)
BIN_DIR="$(cd "$ROOT/app" && swift build -c release --show-bin-path)"

echo "==> Assemblage de Pulse.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/Pulse" "$APP/Contents/MacOS/Pulse"
cp "$ROOT/app/Info.plist" "$APP/Contents/Info.plist"

echo "==> Signature ad hoc"
codesign --force --sign - "$APP"

echo "==> Terminé : $APP"
