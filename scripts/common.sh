# Étapes communes à build.sh et package.sh. À inclure avec « source ».

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Compile aussi le code C des dépendances Rust pour la même cible que l'app.
export MACOSX_DEPLOYMENT_TARGET=15.0

# Génère les bindings Swift à partir d'une lib statique Rust.
# Usage : generate_bindings <chemin de libpulse_core.a>
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

    rm -rf "$swift_dir" "$ffi_dir"
    mkdir -p "$swift_dir" "$ffi_dir"
    mv "$generated/pulse_core.swift" "$swift_dir/"
    mv "$generated/pulse_coreFFI.h" "$ffi_dir/"
    # SwiftPM attend exactement le nom module.modulemap.
    mv "$generated/pulse_coreFFI.modulemap" "$ffi_dir/module.modulemap"
    rm -rf "$generated"
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

# Assemble et signe (ad hoc) l'app à partir d'un exécutable.
# Usage : assemble_app <exécutable> <chemin de Pulse.app>
assemble_app() {
    local binary="$1"
    local app="$2"
    make_icon

    echo "==> Assemblage de $(basename "$app")"
    rm -rf "$app"
    mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
    cp "$binary" "$app/Contents/MacOS/Pulse"
    cp "$ROOT/app/Info.plist" "$app/Contents/Info.plist"
    cp "$ROOT/build/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"

    echo "==> Signature ad hoc"
    codesign --force --sign - "$app"
}
