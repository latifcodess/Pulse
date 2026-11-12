// swift-tools-version: 6.3

import PackageDescription

// Ce Package.swift ne sert plus qu'à l'éditeur (SourceKit, VS Code) : l'app
// se compile avec le projet Xcode (project.yml). Dossier de libpulse_core.a :
// la lib universelle produite par scripts/build-core.sh.
let coreLibDir = Context.environment["PULSE_CORE_LIB_DIR"]
    ?? Context.packageDirectory + "/../core/target/universal/release"

let package = Package(
    name: "Pulse",
    platforms: [.macOS(.v15)],
    targets: [
        // L'app, avec le format du fichier partagé avec le widget.
        .executableTarget(name: "Pulse", dependencies: ["PulseCore"], path: "Sources", sources: ["Pulse", "Shared"]),
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
