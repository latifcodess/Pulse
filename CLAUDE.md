# Pulse

App macOS de barre des menus qui affiche le % utilisé des limites IA
(Claude, ChatGPT, Gemini, Copilot), avec heure de reset et projection.

## Structure
- core/ : Rust, bibliothèque pulse_core (réseau, parsing, cache, alertes, projection), exposée à Swift via UniFFI
- app/ : Swift 6, SwiftUI + AppKit, macOS 15+, sans icône dans le Dock
- scripts/build.sh : build complet → build/Pulse.app
- Tests : cd core && cargo test

## Règles
- Interface en français.
- Je débute en Rust et en Swift : après chaque tâche, explique en 5 lignes max ce que tu as fait et pourquoi.
- Secrets uniquement dans le Trousseau, jamais dans UserDefaults ni dans un fichier.
- Les identifiants des outils CLI (Claude Code, Codex, Gemini CLI, gh) sont lus, jamais copiés ni modifiés.
- Le parsing des réponses est tolérant : un champ manquant donne « indisponible », jamais un crash.