// swift-tools-version: 6.3

import PackageDescription

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
                .unsafeFlags(["-L", Context.packageDirectory + "/../core/target/release"]),
                .linkedLibrary("pulse_core"),
            ]
        ),
        // En-tête C généré, qui décrit à Swift les fonctions de la lib Rust.
        .systemLibrary(name: "pulse_coreFFI"),
    ],
    swiftLanguageModes: [.v6]
)
