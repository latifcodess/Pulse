#!/usr/bin/env bash
# Build complet pour ce Mac : produit build/Pulse.app, signé ad hoc.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

echo "==> Compilation de core/ (lib statique Rust)"
(cd "$ROOT/core" && cargo build --release)

generate_bindings target/release/libpulse_core.a

echo "==> Compilation de app/ (Swift)"
(cd "$ROOT/app" && swift build -c release)
BIN_DIR="$(cd "$ROOT/app" && swift build -c release --show-bin-path)"

assemble_app "$BIN_DIR/Pulse" "$ROOT/build/Pulse.app"
echo "==> Terminé : $ROOT/build/Pulse.app"
