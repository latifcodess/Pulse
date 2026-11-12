#!/usr/bin/env bash
# Build complet avec Xcode : produit build/Pulse.app (universelle, signée ad hoc).
#
# Le projet Xcode est généré depuis project.yml par XcodeGen ; la phase
# « Run Script » du projet compile le cœur Rust et régénère les bindings.
# Prérequis : brew install xcodegen ; rustup target add aarch64-apple-darwin x86_64-apple-darwin
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

echo "==> Génération du projet Xcode (XcodeGen)"
(cd "$ROOT" && xcodegen generate --quiet)

echo "==> Compilation (xcodebuild, Release)"
xcodebuild \
    -project "$ROOT/Pulse.xcodeproj" \
    -scheme Pulse \
    -configuration Release \
    -derivedDataPath "$ROOT/build/DerivedData" \
    -quiet \
    build

rm -rf "$ROOT/build/Pulse.app"
ditto "$ROOT/build/DerivedData/Build/Products/Release/Pulse.app" "$ROOT/build/Pulse.app"
echo "==> Architectures : $(lipo -archs "$ROOT/build/Pulse.app/Contents/MacOS/Pulse")"
echo "==> Terminé : $ROOT/build/Pulse.app"
