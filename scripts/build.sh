#!/usr/bin/env bash
# Build complet : produit build/Pulse.app, signé ad hoc.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/Pulse.app"

echo "==> Compilation de core/ (Rust)"
(cd "$ROOT/core" && cargo build --release)

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
