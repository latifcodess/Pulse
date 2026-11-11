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
- **Mises à jour intégrées** : recherche automatique une fois par jour (ou
  à la demande), puis installation et relance en un clic. Chaque
  téléchargement est vérifié par son empreinte SHA-256.
- Pas d'icône dans le Dock. Interface en français.

## Comment Pulse se connecte

Pulse réutilise les comptes des outils officiels déjà installés sur votre Mac.
**Leurs identifiants sont lus, jamais copiés ni modifiés.**

| IA | Source | Pour se connecter |
|---|---|---|
| Claude | Token de Claude Code (Trousseau), ou votre compte claude.ai | `claude` puis `/login`, ou « Se connecter » dans les Réglages |
| ChatGPT | `~/.codex/auth.json` de Codex CLI | `codex login` |
| Gemini | `~/.gemini/oauth_creds.json` de Gemini CLI | `gemini`, puis « Login with Google » |
| Copilot | `gh auth token` de GitHub CLI | `gh auth login` |

Les seuls secrets que Pulse enregistre lui-même (le cookie de session
claude.ai) sont rangés dans le **Trousseau**. Les tokens renouvelés (Gemini)
ou obtenus de `gh` restent en mémoire. Les préférences (pas secrètes) sont dans
UserDefaults.

> Pulse utilise des API internes, non documentées, de ces services. Elles
> peuvent changer sans préavis : une limite affichée « indisponible » vient
> souvent de là.

## Installation

1. Ouvrez `Pulse-<version>.dmg` et glissez **Pulse** sur **Applications**.
2. Pulse est signé « ad hoc », sans certificat Apple : au premier lancement,
   faites un clic droit sur l'app › **Ouvrir**, puis confirmez. Si macOS
   refuse quand même :

   ```sh
   xattr -dr com.apple.quarantine /Applications/Pulse.app
   ```

3. Acceptez les notifications si vous voulez les alertes.

Configuration requise : macOS 15 ou plus récent, Mac Apple Silicon ou Intel.

## Compilation

### Prérequis

- **Command Line Tools** de Xcode avec Swift 6.3 ou plus récent
  (`xcode-select --install`). Xcode complet n'est pas nécessaire.
- **Rust** via [rustup](https://rustup.rs), avec les deux cibles macOS :

  ```sh
  rustup target add aarch64-apple-darwin x86_64-apple-darwin
  ```

### Commandes

```sh
./scripts/build.sh      # build pour ce Mac      → build/Pulse.app
./scripts/package.sh    # build universel + DMG  → build/release/Pulse-<version>.dmg
cd core && cargo test   # tests du cœur Rust
open build/Pulse.app    # lancer l'app
```

`build.sh` doit être lancé une première fois avant d'ouvrir `app/` dans un
éditeur. C'est lui qui génère les bindings Swift (`app/Sources/PulseCore` et
`app/Sources/pulse_coreFFI`), qui ne sont pas versionnés.

Comme la signature est ad hoc, macOS redemande l'accès au Trousseau après
chaque build : cliquez sur « Toujours autoriser ».

## Publier une nouvelle version

Pulse cherche ses mises à jour dans les releases GitHub de
`latifcodess/Pulse` (le dépôt doit être public).

1. Augmentez `CFBundleShortVersionString` dans `app/Info.plist`
   (par ex. `0.2.0`).
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
│   │   ├── chatgpt.rs       Codex : API d'usage + repli sur les sessions
│   │   ├── gemini.rs        Gemini CLI : OAuth, projet, quotas
│   │   ├── copilot.rs       GitHub CLI : token, quotas
│   │   ├── projection.rs    Historique et régression linéaire
│   │   ├── alerts.rs        Règles d'alerte et moteur de déclenchement
│   │   ├── update.rs        Releases GitHub, téléchargement vérifié
│   │   └── monitor.rs       AiMonitor : point d'entrée exposé à Swift
│   └── tests/               Tests d'intégration et fixtures JSON
├── app/                     Swift 6 : SwiftUI + AppKit
│   └── Sources/
│       ├── Pulse/           L'app (barre des menus, panneau, réglages…)
│       ├── PulseCore/       Bindings Swift générés par UniFFI
│       └── pulse_coreFFI/   En-tête C généré
└── scripts/
    ├── build.sh             Build pour ce Mac
    ├── package.sh           Build universel + DMG
    ├── common.sh            Étapes partagées par les deux scripts
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
  - lit le Trousseau et gère la connexion claude.ai (WebKit) ;
  - affiche l'interface ;
  - envoie les notifications rédigées en français ;
  - enregistre les préférences.

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
  └─ AlertCenter → AlertEngine.evaluate() (Rust) → notifications
```

## Logos

Les logos des IA sont les logos officiels, au format SVG, issus de
[Simple Icons](https://simpleicons.org) (licence CC0). Ils restent des
marques de leurs propriétaires et servent ici uniquement à identifier chaque
service. Pulse n'est affilié ni à Anthropic, ni à OpenAI, ni à Google, ni à
GitHub.
