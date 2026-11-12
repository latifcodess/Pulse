# Étapes communes aux scripts de Pulse. À inclure avec « source ».

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Compile aussi le code C des dépendances Rust pour la même cible que l'app.
export MACOSX_DEPLOYMENT_TARGET=15.0
# Xcode lance ses scripts avec un PATH minimal : on ajoute cargo (rustup) et Homebrew.
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

# La lib statique universelle (Apple Silicon + Intel), liée à l'app.
UNIVERSAL_LIB_DIR="$ROOT/core/target/universal/release"

# Compile le cœur Rust pour les deux architectures, puis les réunit avec lipo.
# Prérequis : rustup target add aarch64-apple-darwin x86_64-apple-darwin
build_core() {
    echo "==> Compilation de core/ pour Apple Silicon et Intel"
    for target in aarch64-apple-darwin x86_64-apple-darwin; do
        (cd "$ROOT/core" && cargo build --release --target "$target")
    done
    mkdir -p "$UNIVERSAL_LIB_DIR"
    lipo -create \
        "$ROOT/core/target/aarch64-apple-darwin/release/libpulse_core.a" \
        "$ROOT/core/target/x86_64-apple-darwin/release/libpulse_core.a" \
        -output "$UNIVERSAL_LIB_DIR/libpulse_core.a"
}

# Génère les bindings Swift à partir d'une lib statique Rust. Un fichier
# n'est réécrit que s'il a changé : sinon Xcode recompilerait tout à chaque build.
# Usage : generate_bindings <chemin de libpulse_core.a, relatif à core/>
generate_bindings() {
    local library="$1"
    local swift_dir="$ROOT/app/Sources/PulseCore"
    local ffi_dir="$ROOT/app/Sources/pulse_coreFFI"
    local generated
    generated="$(mktemp -d)"

    echo "==> Génération des bindings Swift"
    (cd "$ROOT/core" && cargo run --release --quiet --bin uniffi-bindgen -- generate \
        --library "$library" \
        --language swift \
        --out-dir "$generated")

    mkdir -p "$swift_dir" "$ffi_dir"
    update_file "$generated/pulse_core.swift" "$swift_dir/pulse_core.swift"
    update_file "$generated/pulse_coreFFI.h" "$ffi_dir/pulse_coreFFI.h"
    # Le compilateur attend exactement le nom module.modulemap.
    update_file "$generated/pulse_coreFFI.modulemap" "$ffi_dir/module.modulemap"
    rm -rf "$generated"
}

# Copie $1 vers $2, seulement si le contenu diffère.
update_file() {
    cmp -s "$1" "$2" || cp "$1" "$2"
}

# Génère build/AppIcon.icns, seulement si le script de l'icône a changé.
make_icon() {
    local icon="$ROOT/build/AppIcon.icns"
    if [[ ! -f "$icon" || "$ROOT/scripts/make-icon.swift" -nt "$icon" ]]; then
        echo "==> Génération de l'icône"
        mkdir -p "$ROOT/build"
        swift "$ROOT/scripts/make-icon.swift" "$icon" >/dev/null
    fi
}
