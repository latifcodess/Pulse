#!/usr/bin/env bash
# Phase « Run Script » de Xcode (cible Pulse) : génère l'icône de l'app.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

make_icon
