<div align="center">

<img src="docs/icon.png" width="128" height="128" alt="Icône de Pulse">

# Pulse

**Tes limites Claude, ChatGPT, Gemini et Copilot, d'un coup d'œil dans la barre des menus.**

[![Dernière version](https://img.shields.io/github/v/release/latifcodess/Pulse?label=version&color=2480E8)](https://github.com/latifcodess/Pulse/releases/latest)
![macOS 15+](https://img.shields.io/badge/macOS-15%2B-1E1E24?logo=apple&logoColor=white)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![Rust](https://img.shields.io/badge/Rust-cœur-000000?logo=rust&logoColor=white)

[**⬇︎ Télécharger**](https://github.com/latifcodess/Pulse/releases/latest) · [Installation](#-installation) · [Fonctionnalités](#-fonctionnalités) · [Réglages](#%EF%B8%8F-réglages) · [Compiler soi-même](#%EF%B8%8F-compiler-depuis-les-sources)

</div>

---

## ✨ Fonctionnalités

- **Tes IA dans la barre des menus**, en trois styles au choix : *Logo + %*, *Anneaux* (le plus compact, idéal avec une encoche) ou *Compact* (seulement l'IA la plus proche de sa limite et l'heure prévue). Regroupées dans un seul élément ou séparées, et masquables tant qu'elles sont sous un seuil. Bleu, puis orange et rouge à l'approche de la limite.
- **Une fenêtre détaillée au clic** : le % de la limite la plus proche, un graphique de la fenêtre en cours avec la projection en pointillés jusqu'à 100 %, une alerte *« Au rythme actuel, tu seras bloqué de 15:32 à 17:00 »*, puis chaque limite avec sa barre, son reset (*« Reset à 17:00 · dans 2 h 05 »*) et sa projection (*« Limite vers 15:32 »* ou *« Tiendra jusqu'au reset »*).
- **Projection** : Pulse mesure ta vitesse de consommation sur les 30 dernières minutes et te dit si la limite sera atteinte avant le reset.
- **Ta couleur** : 12 couleurs au choix (ou n'importe laquelle) pour les pourcentages et les barres sous le seuil orange.
- **Sur l'écran verrouillé** *(expérimental)* : le logo, le % et l'heure prévue de chaque IA, sous l'horloge.
- **Notifications** : limite au-dessus d'un seuil, bientôt atteinte, de nouveau disponible, session expirée. Chaque alerte ne se déclenche qu'une fois.
- **Widgets** pour le bureau et le centre de notifications : petit (une IA, avec son anneau), moyen (les 4 IA) et grand (une IA avec son graphique). Un clic ouvre la fenêtre de l'IA.
- **Deux façons de se connecter** à chaque IA : son outil en ligne de commande déjà installé, ou ton compte directement dans Pulse.
- **Hors ligne**, les dernières valeurs connues restent affichées.
- **Mises à jour automatiques** : Pulse te prévient quand une nouvelle version sort et s'installe en un clic.
- **Discret** : pas d'icône dans le Dock, interface en français.

---

## 📦 Installation

### 1. Télécharger

Télécharge le fichier `Pulse-x.y.z.dmg` depuis la [**dernière release**](https://github.com/latifcodess/Pulse/releases/latest), ouvre-le, puis glisse **Pulse** sur le raccourci **Applications**.

### 2. Autoriser l'app au premier lancement

L'app est signée avec un certificat de développeur, mais **elle n'est pas notarisée par Apple** (ce qui demande un compte développeur payant). Au premier lancement, macOS va donc la bloquer avec un message du type :

> **« Pulse » n'a pas été ouvert**
> Apple n'a pas pu confirmer que « Pulse » ne contient pas de logiciel malveillant…

C'est normal, et ça ne se fait qu'une seule fois. Pour l'autoriser :

1. Clique sur **OK** (ou **Terminé**) pour fermer le message.
2. Ouvre les **Réglages Système** ( › Réglages Système…).
3. Va dans **Confidentialité et sécurité**.
4. **Descends tout en bas** de la page, jusqu'à la section **Sécurité**. Tu y verras la ligne *« Pulse » a été bloqué afin de protéger votre Mac*.
5. Clique sur **Ouvrir quand même**.
6. Confirme avec ton mot de passe ou Touch ID, puis clique encore sur **Ouvrir quand même** dans la fenêtre qui s'affiche.

L'app s'ouvre, et macOS ne posera plus la question.

<details>
<summary>Alternative pour les habitués du Terminal</summary>

Cette commande retire le marqueur « téléchargé depuis Internet » de l'app, ce qui évite le blocage :

```sh
xattr -dr com.apple.quarantine /Applications/Pulse.app
```

</details>

### 3. Connecter tes IA

Tes IA apparaissent dans la barre des menus. Pour chaque IA qui affiche **non connecté**, clique dessus › ⚙️ pour ouvrir ses réglages, puis choisis une **méthode** (voir le tableau ci-dessous).

Accepte aussi les **notifications** quand macOS les propose, si tu veux les alertes.

C'est prêt 🎉

---

## 🤖 IA prises en charge

Pour chaque IA, deux méthodes au choix :

- **l'outil officiel en ligne de commande**, s'il est déjà connecté sur ton Mac : Pulse lit ses identifiants, **sans jamais les copier ni les modifier** ;
- **ton compte, connecté directement dans Pulse**, si tu n'as pas l'outil.

| IA | Avec l'outil en ligne de commande | Avec ton compte dans Pulse |
|---|---|---|
| **Claude** | Claude Code : `claude`, puis `/login` | Compte claude.ai, dans une fenêtre de Pulse |
| **ChatGPT** | Codex CLI : `codex login` | Compte ChatGPT, dans une fenêtre de Pulse (avec ton e-mail) |
| **Gemini** | Gemini CLI : `gemini`, puis « Login with Google » | Compte Google, dans ton navigateur |
| **Copilot** | GitHub CLI : `gh auth login` | Compte GitHub, avec un code à saisir sur github.com |

> 🔒 Les secrets que Pulse enregistre lui-même (cookies de session, tokens des comptes connectés dans Pulse) sont rangés dans le **Trousseau** de macOS, jamais dans un fichier.

---

## 🖱️ Utilisation

| Où tu cliques | Ce qui s'affiche |
|---|---|
| **Une IA** dans la barre des menus | Sa fenêtre : le graphique, ses limites, les heures de reset et la projection |
| **L'élément regroupé** (ou le style Compact) | La fenêtre de l'IA la plus proche de sa limite, avec en haut les logos des autres IA pour passer de l'une à l'autre |
| **N'importe où ailleurs** | Ferme la fenêtre |
| **⟳** dans la fenêtre | Actualise tout de suite |
| **⚙️** dans la fenêtre | Les réglages de cette IA |
| **⏻** dans la fenêtre | Quitte Pulse |
| **Pulse x.y** en bas de la fenêtre | La mise à jour disponible |
| **Un widget** | La fenêtre de son IA |

> 💡 **Ajouter un widget** : clic droit sur le bureau › **Modifier les widgets…**, cherche **Pulse**, puis choisis *« Pulse — une IA »* (petit ou grand) ou *« Pulse — toutes les IA »* (moyen). Pour changer l'IA : clic droit sur le widget › **Modifier**. Les données de plus de 15 min s'y affichent en gris, avec *« Il y a 32 min »*.

> 💡 Sans regroupement, chaque IA a sa propre icône : maintiens **⌘** pour la déplacer dans la barre des menus.

---

## ⚙️ Réglages

Ouvre les réglages avec le bouton ⚙️ de la fenêtre d'une IA. Les changements s'appliquent immédiatement. La barre latérale donne accès à **Général**, **Alertes** et à chaque IA (un point vert indique qu'elle est connectée).

**Général**

| Réglage | Effet |
|---|---|
| **Style dans la barre des menus** | *Logo + %*, *Anneaux* ou *Compact*. |
| **Couleur** | La couleur des pourcentages, barres et anneaux sous le seuil orange : 12 couleurs proposées, ou une couleur personnalisée. |
| **Regrouper les IA dans un seul élément** | Toutes les IA dans un seul élément, ou une icône par IA. |
| **Masquer une IA tant qu'elle est sous** | Jamais, 25 %, 50 % ou 75 % : la barre reste discrète jusqu'à ce que ça compte. |
| **Ouvrir Pulse au démarrage** | Lance Pulse à l'ouverture de la session. |
| **Afficher sur l'écran verrouillé** *(expérimental)* | Le logo, le % et l'heure prévue de chaque IA, sous l'horloge de l'écran verrouillé. Désactivé par défaut ; visible par toute personne devant le Mac. |
| **Mises à jour** | Version installée, recherche automatique, *Rechercher maintenant*. |

**Page de chaque IA**

| Réglage | Effet |
|---|---|
| **Suivre** | Affiche ou retire l'IA. Sans suivi, Pulse ne fait plus aucune requête pour elle. |
| **Connexion** | L'outil en ligne de commande, ou ton compte connecté dans Pulse. Avec l'outil, Pulse indique la commande à lancer pour se connecter ou se déconnecter. |
| **Valeur dans la barre** | La 1re limite (ex. *Session*), la 2e (ex. *Semaine*) ou les deux. |
| **Format** | Le pourcentage utilisé ou restant. |
| **Seuil orange / rouge** | Les seuils de couleur de la barre des menus, de la fenêtre et du widget. |
| **Actualiser toutes les** | De 30 s à 10 min. |

**Alertes** : active, modifie ou ajoute des alertes.

| Alerte | Quand |
|---|---|
| **Limite au-dessus d'un seuil** | La limite choisie dépasse le seuil (80 % et 90 % par défaut). |
| **Limite bientôt atteinte** | Au rythme actuel, la limite sera atteinte dans moins de 30 min. |
| **De nouveau disponible** | Une nouvelle fenêtre commence après une limite presque atteinte. |
| **Session expirée** | La connexion à une IA a expiré. Un clic ouvre ses réglages. |

---

## 🔄 Mises à jour

Pulse vérifie les [releases GitHub](https://github.com/latifcodess/Pulse/releases) :

- **à chaque ouverture de l'app**, y compris au démarrage de la session ;
- **une fois par jour** ensuite ;
- **à la demande**, avec le bouton **Rechercher maintenant** (Réglages › Général).

Quand une nouvelle version existe, une fenêtre affiche les nouveautés et propose trois choix :

- **Installer et relancer** : Pulse télécharge la nouvelle version, vérifie son empreinte, sa signature et sa compatibilité avec ton Mac, se remplace et se rouvre tout seul.
- **Plus tard** : la fenêtre reviendra au prochain lancement.
- **Ignorer cette version** : plus de fenêtre automatique pour cette version.

Les mises à jour installées depuis Pulse ne déclenchent pas le blocage de macOS décrit plus haut.

---

## 🛠️ Compiler depuis les sources

**Prérequis** : macOS 15 ou plus récent, Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) et [Rust](https://rustup.rs) avec les deux cibles macOS :

```sh
rustup target add aarch64-apple-darwin x86_64-apple-darwin
```

Puis :

```sh
git clone https://github.com/latifcodess/Pulse.git
cd Pulse
./scripts/build.sh        # → build/Pulse.app (Apple Silicon + Intel)
open build/Pulse.app
```

`build.sh` génère le projet Xcode, compile le cœur Rust et l'app en Release, puis copie l'app dans `build/`.

```sh
cd core && cargo test     # tests du cœur Rust
```

> Le projet Xcode est généré à partir de [`project.yml`](project.yml). Modifie ce fichier plutôt que les réglages dans Xcode, puis lance `xcodegen generate`. Pour signer avec ton propre compte Apple (il en faut un pour l'App Group du widget), connecte-le dans Xcode › Réglages › Comptes, puis remplace `DEVELOPMENT_TEAM` dans `project.yml` par ton Team ID.

### Publier une nouvelle version

1. Augmente `MARKETING_VERSION` dans [`project.yml`](project.yml).
2. Lance `./scripts/package.sh`. Il augmente tout seul le numéro de build (`CURRENT_PROJECT_VERSION`, le même pour l'app et le widget), vérifie que le widget est bien embarqué avec la même version, la même équipe et le même App Group, puis produit dans `build/release/` le DMG et son empreinte, `Pulse-x.y.z.dmg` et `Pulse-x.y.z.dmg.sha256`.
3. Fais le commit (avec `project.yml`) et le push, puis crée une release GitHub avec le tag **`vx.y.z`**, des notes de version (elles s'affichent dans Pulse) et **les deux fichiers**.

Une release sans fichier `.sha256` est refusée par Pulse. Les brouillons et les préversions sont ignorés.

---

## 🧩 Comment ça marche

```
Pulse.app                      ← app de barre des menus (Swift)
├── Contents/MacOS/Pulse       ← inclut le cœur Rust (réseau, alertes, projection)
└── Contents/PlugIns/
    └── PulseWidget.appex      ← widget (lit seulement les données partagées par l'app)
```

| Dossier | Contenu |
|---|---|
| [`core/`](core) | Cœur en **Rust** : requêtes aux services, lecture tolérante des réponses, projection, moteur d'alertes, mises à jour. Exposé à Swift par [UniFFI](https://mozilla.github.io/uniffi-rs/). |
| [`app/Sources/Pulse/`](app/Sources/Pulse) | App en SwiftUI + AppKit : barre des menus (`NSStatusItem`), fenêtres des IA (`NSPopover`), réglages, notifications, connexions aux comptes |
| [`app/Sources/PulseWidget/`](app/Sources/PulseWidget) | Widget **WidgetKit** : petit, moyen et grand |
| [`app/Sources/Shared/`](app/Sources/Shared) | Composants d'interface communs à l'app et au widget (logo, anneau, barre, graphique de projection, couleurs) et format des données partagées |
| [`design/`](design) | Maquettes de l'interface (HTML), référence pour les couleurs, tailles et espacements |
| [`scripts/`](scripts) | Build, DMG, icône |

- Le **cœur Rust** fait tout ce qui se teste sans interface : il interroge les services, et un champ manquant dans une réponse donne « indisponible », jamais un crash.
- Après chaque actualisation, l'app écrit un petit fichier JSON dans un **App Group** (limites, projection, historique de la fenêtre en cours) ; le widget, **sandboxé**, ne lit que ce fichier, sans réseau ni Trousseau.
- Les points du graphique sont gardés en mémoire pendant que Pulse tourne : après un lancement, la courbe se remplit au fil des actualisations.
- L'ouverture au démarrage repose sur `SMAppService`.
- L'affichage sur l'écran verrouillé utilise des fonctions privées de **SkyLight** (le framework qui parle au WindowServer), comme les apps de type « notch ». Tout ce code est isolé dans [`LockScreenWindow.swift`](app/Sources/Pulse/LockScreenWindow.swift) ; si une de ces fonctions disparaît dans une version de macOS, l'option est simplement grisée.

> ⚠️ Pulse utilise des API internes, non documentées, de ces services. Elles peuvent changer sans préavis : une limite affichée « indisponible » vient souvent de là.

---

## ❓ Dépannage

<details>
<summary><b>Une IA affiche « non connecté »</b></summary>

Ouvre ses réglages (⚙️ dans son panneau) et regarde la **méthode** :

- **Outil en ligne de commande** : l'outil n'est pas installé ou pas connecté. Le panneau indique la commande à lancer dans le Terminal (par ex. `codex login`).
- **Compte** : clique sur **Se connecter…**.

</details>

<details>
<summary><b>Une IA affiche « expiré » ou « indisponible »</b></summary>

- **Expiré** : la connexion n'est plus acceptée. Reconnecte-toi avec l'outil (Claude Code, Codex, `gemini`, `gh auth login`) ou dans les réglages de Pulse.
- **Indisponible** : le service a répondu quelque chose d'inattendu. Réessaie plus tard avec ⟳ ; si ça dure, le service a peut-être changé son API.

</details>

<details>
<summary><b>macOS demande l'accès au Trousseau</b></summary>

Pulse lit le token de Claude Code et ses propres secrets dans le Trousseau. Clique sur **Toujours autoriser** pour ne plus avoir la question.

</details>

<details>
<summary><b>Le widget n'apparaît pas dans la liste</b></summary>

1. Vérifie que Pulse est dans le dossier **Applications** et qu'il a été ouvert au moins une fois.
2. S'il y a plusieurs copies de Pulse sur ton Mac, garde uniquement celle d'Applications.
3. Ferme puis rouvre la galerie des widgets (clic droit sur le bureau › **Modifier les widgets…**).

</details>

<details>
<summary><b>macOS indique que l'app ne peut pas être ouverte</b></summary>

Suis l'étape [Autoriser l'app au premier lancement](#2-autoriser-lapp-au-premier-lancement).

</details>

<details>
<summary><b>Désinstaller l'app</b></summary>

1. Dans Pulse, Réglages › Général : désactive **Ouvrir Pulse au démarrage de la session**, puis clique sur **Quitter Pulse**.
2. Mets **Pulse.app** à la corbeille depuis le dossier Applications.
3. Facultatif : dans l'app **Trousseaux d'accès**, supprime les éléments nommés `ch.latifcodess.pulse` (les comptes connectés dans Pulse).

</details>

---

<div align="center">
<sub>Fait avec ❤️ en Swift et en Rust · Logos via <a href="https://simpleicons.org">Simple Icons</a> · Pulse n'est affilié ni à Anthropic, ni à OpenAI, ni à Google, ni à GitHub.</sub>
</div>
