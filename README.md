# Pulse

Pulse est une petite app pour la barre des menus de macOS. Elle affiche, pour
chaque IA que vous utilisez, le pourcentage déjà consommé de vos limites
d'usage, l'heure de leur réinitialisation, et une projection : à ce rythme,
la limite sera-t-elle atteinte avant le reset ?

IA prises en charge : **Claude**, **ChatGPT** (Codex), **Gemini** et
**GitHub Copilot**.

## Fonctionnalités

- **Une puce par IA** dans la barre des menus, avec son logo et son
  pourcentage, en orange puis en rouge à l'approche de la limite.
- **Un panneau détaillé** au clic : chaque limite avec sa barre de
  progression, l'heure de réinitialisation (« Réinitialisé à 17:00 · dans
  2 h 15 ») et la projection (« Limite atteinte vers 15:40 » ou « Tiendra
  jusqu'au reset »).
- **Projection** : la vitesse de consommation est calculée par régression
  linéaire sur les 30 dernières minutes.
- **Notifications macOS** :
  - limite au-dessus d'un seuil ;
  - de nouveau disponible après le reset ;
  - session expirée ;
  - limite bientôt atteinte (projection).

  Chaque alerte ne se déclenche qu'une fois, puis se réarme.
- **Réglages** :
  - **par IA** : suivi, valeur affichée (1re limite, 2e ou les deux, en
    utilisé ou en restant), intervalle d'actualisation (30 s à 10 min), seuils
    de couleur, aperçu de la puce ;
  - **onglet Alertes** : modifier les alertes ou en ajouter ;
  - **ouverture au démarrage**.
- **Hors ligne** : les dernières valeurs connues restent affichées.
- **Widgets** pour le bureau et le centre de notifications : petit (une IA,
  au choix) et moyen (toutes les IA suivies). Les données de plus de 15 min
  sont affichées en grisé.
- **Mises à jour intégrées** : au lancement de Pulse, une fenêtre annonce
  les nouvelles versions ; installation et relance en un clic. Chaque
  téléchargement est vérifié par son empreinte SHA-256.
- Pas d'icône dans le Dock. Interface en français.

## Comment Pulse se connecte

Pour chaque IA, deux méthodes au choix (Réglages › onglet de l'IA ›
Méthode) :

- **l'outil officiel en ligne de commande**, déjà connecté sur votre Mac :
  Pulse lit ses identifiants, **sans jamais les copier ni les modifier** ;
- **un compte connecté directement dans Pulse**.

| IA | Outil en ligne de commande | Compte dans Pulse |
|---|---|---|
| Claude | Claude Code (`claude`, puis `/login`) | Compte claude.ai, dans une fenêtre de Pulse |
| ChatGPT | Codex CLI (`codex login`) | Compte ChatGPT, dans une fenêtre de Pulse (avec votre e-mail) |
| Gemini | Gemini CLI (`gemini`) | Compte Google, dans votre navigateur |
| Copilot | GitHub CLI (`gh auth login`) | Compte GitHub, avec un code à saisir sur github.com |

Les secrets que Pulse enregistre lui-même (cookies de session, tokens des
comptes connectés dans Pulse) sont rangés dans le **Trousseau**. Les
préférences, qui ne sont pas secrètes, sont dans UserDefaults.

> Pulse utilise des API internes, non documentées, de ces services. Elles
> peuvent changer sans préavis : une limite affichée « indisponible » vient
> souvent de là.

## Installation

1. Téléchargez `Pulse-<version>.dmg` depuis les
   [releases](https://github.com/latifcodess/Pulse/releases), ouvrez-le et
   glissez **Pulse** sur **Applications**.
2. Lancez Pulse depuis le dossier Applications.
3. Acceptez les notifications si vous voulez les alertes.

Configuration requise : macOS 15 ou plus récent, Mac Apple Silicon ou Intel.

### Si Pulse ne s'ouvre pas

Pulse n'est pas notarisé par Apple : il est signé avec un compte développeur
gratuit, pas avec un certificat « Developer ID ». Au premier lancement, macOS
peut donc afficher « Apple ne peut pas vérifier que Pulse ne contient pas de
logiciel malveillant ». Pour l'autoriser :

1. Cliquez sur **Terminé** dans ce message.
2. Ouvrez **Réglages Système › Confidentialité et sécurité**.
3. Descendez jusqu'à la section **Sécurité** : le message « Pulse a été
   bloqué… » s'y affiche. Cliquez sur **Ouvrir quand même**.
4. Confirmez avec votre mot de passe (ou Touch ID), puis cliquez sur
   **Ouvrir**.

Il suffit de le faire une fois. Les mises à jour installées depuis Pulse ne
le redemandent pas.

Autre solution, dans le Terminal :

```sh
xattr -dr com.apple.quarantine /Applications/Pulse.app
```

### Ajouter le widget

Clic droit sur le bureau › **Modifier les widgets…**, cherchez **Pulse**,
puis choisissez « Pulse — une IA » ou « Pulse — toutes les IA ». Pour
changer l'IA du petit widget : clic droit dessus › **Modifier**.

## Compilation

### Prérequis

- **Xcode** (Swift 6.3 ou plus récent).
- **XcodeGen**, qui génère le projet Xcode depuis `project.yml` :
  `brew install xcodegen`.
- **Rust** via [rustup](https://rustup.rs), avec les deux cibles macOS :

  ```sh
  rustup target add aarch64-apple-darwin x86_64-apple-darwin
  ```

### Commandes

```sh
./scripts/build.sh      # build universel avec Xcode → build/Pulse.app
./scripts/package.sh    # build + DMG               → build/release/Pulse-<version>.dmg
cd core && cargo test   # tests du cœur Rust
open build/Pulse.app    # lancer l'app
```

Pour travailler dans Xcode : `xcodegen generate`, puis ouvrez
`Pulse.xcodeproj` (généré, non versionné : modifiez `project.yml`, pas le
projet). À chaque build, la phase « Cœur Rust et bindings UniFFI » compile
`core/` pour Apple Silicon et Intel (`scripts/build-core.sh`) et régénère
les bindings Swift (`app/Sources/PulseCore` et `app/Sources/pulse_coreFFI`,
non versionnés).

`app/Package.swift` ne sert plus qu'à l'éditeur (SourceKit dans VS Code).

Pulse est signé avec un compte Apple (gratuit) : l'App Group partagé avec le
widget l'exige. Pour compiler avec votre propre compte, connectez-le dans
Xcode › Réglages › Comptes, puis remplacez `DEVELOPMENT_TEAM` dans
`project.yml` par votre Team ID.

## Publier une nouvelle version

Pulse cherche ses mises à jour dans les releases GitHub de
`latifcodess/Pulse` (le dépôt doit être public).

1. Augmentez `MARKETING_VERSION` (et `CURRENT_PROJECT_VERSION`) dans
   `project.yml`, par ex. `0.2.0` : c'est la version de l'app et du widget.
2. Lancez `./scripts/package.sh`. Il produit dans `build/release/` le DMG
   et son empreinte : `Pulse-0.2.0.dmg` et `Pulse-0.2.0.dmg.sha256`.
3. Sur GitHub, créez une release avec le tag **`v0.2.0`**, des notes de
   version (elles s'affichent dans Pulse) et **les deux fichiers**.

Une release sans fichier `.sha256` est refusée. Les brouillons et les
préversions sont ignorés.

## Architecture

```
Pulse/
├── core/                    Rust : bibliothèque pulse_core
│   ├── src/
│   │   ├── model.rs         AiService, UsageWindow, AiUsage, AiState
│   │   ├── http.rs          GET/POST bloquants (ureq), erreurs communes
│   │   ├── claude.rs        API d'usage de Claude Code
│   │   ├── claude_web.rs    Compte claude.ai (cookie de session)
│   │   ├── chatgpt.rs       Codex ou compte ChatGPT : API d'usage
│   │   ├── gemini.rs        Gemini CLI ou compte Google : OAuth, quotas
│   │   ├── copilot.rs       GitHub CLI ou compte GitHub : token, quotas
│   │   ├── projection.rs    Historique et régression linéaire
│   │   ├── alerts.rs        Règles d'alerte et moteur de déclenchement
│   │   ├── update.rs        Releases GitHub, téléchargement vérifié
│   │   └── monitor.rs       AiMonitor : point d'entrée exposé à Swift
│   └── tests/               Tests d'intégration et fixtures JSON
├── app/                     Swift 6 : SwiftUI + AppKit
│   └── Sources/
│       ├── Pulse/           L'app (barre des menus, panneau, réglages…)
│       ├── PulseWidget/     Le widget (WidgetKit)
│       ├── Shared/          Format du fichier partagé app ↔ widget
│       ├── PulseCore/       Bindings Swift générés par UniFFI
│       └── pulse_coreFFI/   En-tête C généré
├── project.yml              Projet Xcode (XcodeGen)
└── scripts/
    ├── build.sh             Build universel avec Xcode
    ├── package.sh           Build + DMG
    ├── build-core.sh        Phase Xcode : cœur Rust + bindings UniFFI
    ├── build-icon.sh        Phase Xcode : icône de l'app
    ├── common.sh            Étapes partagées par les scripts
    └── make-icon.swift      Génère l'icône de l'app
```

### Répartition des rôles

- **Le cœur Rust** fait tout ce qui se teste sans interface :
  - les requêtes réseau et la lecture tolérante des réponses (un champ
    manquant donne « indisponible », jamais un crash) ;
  - la gestion des tokens, l'historique et la projection ;
  - la décision d'envoyer une alerte.

  Il est compilé en bibliothèque statique, puis exposé à Swift par
  [UniFFI](https://mozilla.github.io/uniffi-rs/).
- **L'app Swift** :
  - lit le Trousseau et gère les connexions aux comptes ;
  - affiche l'interface ;
  - envoie les notifications rédigées en français ;
  - enregistre les préférences ;
  - écrit, après chaque actualisation, le fichier lu par le widget (dans le
    conteneur de l'App Group).
- **Le widget** ne lit que ce fichier : ni réseau, ni Trousseau.

  Les appels Rust sont bloquants : Swift les lance hors du thread principal
  (`Task.detached`).

### Flux d'une actualisation

```
UsageModel (Swift, toutes les N s)
  └─ AiMonitor.refresh_<ia>() (Rust)
       ├─ lit les identifiants de l'outil CLI
       ├─ interroge l'API, lit la réponse   → AiUsage
       ├─ UsageHistory.record()             → projected_full_at
       └─ renvoie un AiState (Ok, Offline, Expired, Blocked…)
  ├─ met à jour la puce et le panneau
  ├─ AlertCenter → AlertEngine.evaluate() (Rust) → notifications
  └─ WidgetExporter → widget.json → le widget se redessine
```

## Logos

Les logos des IA sont les logos officiels, au format SVG, issus de
[Simple Icons](https://simpleicons.org) (licence CC0). Ils restent des
marques de leurs propriétaires et servent ici uniquement à identifier chaque
service. Pulse n'est affilié ni à Anthropic, ni à OpenAI, ni à Google, ni à
GitHub.
