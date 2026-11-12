#!/usr/bin/env bash
# Phase « Run Script » de Xcode (cible PulseCore), avant la compilation :
# compile le cœur Rust (Apple Silicon + Intel) et régénère les bindings UniFFI.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

build_core
generate_bindings target/aarch64-apple-darwin/release/libpulse_core.a
