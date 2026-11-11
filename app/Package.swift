// swift-tools-version: 6.3

import PackageDescription

// Dossier de libpulse_core.a : celui de « cargo build --release », ou celui
// indiqué par scripts/package.sh pour le build universel.
let coreLibDir = Context.environment["PULSE_CORE_LIB_DIR"]
    ?? Context.packageDirectory + "/../core/target/release"

let package = Package(
    name: "Pulse",
    platforms: [.macOS(.v15)],
    targets: [
        // L'app.
        .executableTarget(name: "Pulse", dependencies: ["PulseCore"]),
        // Bindings Swift générés par scripts/build.sh, liés à la lib statique Rust.
        .target(
            name: "PulseCore",
            dependencies: ["pulse_coreFFI"],
            linkerSettings: [
                .unsafeFlags(["-L", coreLibDir]),
                .linkedLibrary("pulse_core"),
            ]
        ),
        // En-tête C généré, qui décrit à Swift les fonctions de la lib Rust.
        .systemLibrary(name: "pulse_coreFFI"),
    ],
    swiftLanguageModes: [.v6]
)
