//! Mises à jour de Pulse, publiées comme releases GitHub.
//!
//! Une release porte le tag « vX.Y.Z » et deux fichiers :
//! Pulse-X.Y.Z.dmg et Pulse-X.Y.Z.dmg.sha256 (son empreinte SHA-256).
//! Le DMG n'est accepté que si son empreinte correspond.

use std::fs::{self, File};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::time::Duration;

use serde_json::Value;
use sha2::{Digest, Sha256};

use crate::http::{self, FetchError};

/// La dernière release publiée (hors brouillons et préversions).
pub const LATEST_RELEASE_URL: &str = "https://api.github.com/repos/latifcodess/Pulse/releases/latest";

/// Taille maximale acceptée pour un DMG.
const MAX_DOWNLOAD_BYTES: u64 = 200 * 1024 * 1024;

/// Une nouvelle version disponible.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct UpdateInfo {
    /// « 0.2.0 », sans le « v ».
    pub version: String,
    /// Notes de version (texte de la release), peut être vide.
    pub notes: String,
    /// Page de la release sur GitHub.
    pub page_url: String,
    pub dmg_url: String,
    pub sha256_url: String,
}

/// Pourquoi la recherche ou le téléchargement a échoué.
#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum UpdateFailure {
    /// Pas de réseau, ou serveur injoignable.
    Offline,
    /// Aucune release publiée (ou dépôt privé).
    NoRelease,
    /// GitHub limite le nombre de requêtes : réessayer plus tard.
    RateLimited,
    /// La release ne contient pas le DMG et son empreinte, ou est illisible.
    InvalidRelease,
    /// Le DMG téléchargé ne correspond pas à son empreinte : il est supprimé.
    ChecksumMismatch,
    /// Impossible d'écrire le fichier téléchargé.
    WriteFailed,
    /// Autre réponse inattendue du serveur.
    Unavailable,
}

#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum UpdateCheck {
    UpToDate,
    Available { info: UpdateInfo },
    Failed { reason: UpdateFailure },
}

#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum DownloadOutcome {
    /// Le DMG vérifié, prêt à installer.
    Downloaded { path: String },
    Failed { reason: UpdateFailure },
}

/// Cherche une version plus récente que `current_version`. Appel bloquant.
#[uniffi::export]
pub fn check_for_update(current_version: String) -> UpdateCheck {
    check_for_update_at(LATEST_RELEASE_URL, &current_version, Duration::from_secs(10))
}

/// Comme check_for_update, avec une autre adresse (pour les tests).
pub fn check_for_update_at(url: &str, current_version: &str, timeout: Duration) -> UpdateCheck {
    let headers = [
        ("Accept", "application/vnd.github+json"),
        // L'API de GitHub refuse les requêtes sans User-Agent.
        ("User-Agent", "Pulse"),
    ];
    let response = match http::get(url, &headers, timeout) {
        Ok(response) => response,
        Err(FetchError::Offline) => return UpdateCheck::Failed { reason: UpdateFailure::Offline },
        Err(_) => return UpdateCheck::Failed { reason: UpdateFailure::Unavailable },
    };
    let reason = match response.status {
        200 => {
            return match parse_release(&response.body, current_version) {
                Ok(Some(info)) => UpdateCheck::Available { info },
                Ok(None) => UpdateCheck::UpToDate,
                Err(reason) => UpdateCheck::Failed { reason },
            };
        }
        404 => UpdateFailure::NoRelease,
        403 | 429 => UpdateFailure::RateLimited,
        _ => UpdateFailure::Unavailable,
    };
    UpdateCheck::Failed { reason }
}

/// Lit la release. Ok(None) : elle n'est pas plus récente que la version actuelle.
pub fn parse_release(json: &str, current_version: &str) -> Result<Option<UpdateInfo>, UpdateFailure> {
    let root: Value = serde_json::from_str(json).map_err(|_| UpdateFailure::InvalidRelease)?;
    let tag = root.get("tag_name").and_then(Value::as_str).ok_or(UpdateFailure::InvalidRelease)?.trim();
    let version = tag.strip_prefix('v').unwrap_or(tag);
    // Un tag qui n'est pas un numéro de version (« nightly »…) est refusé ici.
    if !is_newer(version, current_version).ok_or(UpdateFailure::InvalidRelease)? {
        return Ok(None);
    }

    let assets = root.get("assets").and_then(Value::as_array).map(Vec::as_slice).unwrap_or_default();
    let asset_url = |suffix: &str| {
        assets.iter().find_map(|asset| {
            let name = asset.get("name")?.as_str()?;
            let url = asset.get("browser_download_url")?.as_str()?;
            // Uniquement en HTTPS.
            (name.ends_with(suffix) && url.starts_with("https://")).then(|| url.to_string())
        })
    };
    // Sans empreinte, le DMG ne pourrait pas être vérifié : la release est refusée.
    let (Some(dmg_url), Some(sha256_url)) = (asset_url(".dmg"), asset_url(".dmg.sha256")) else {
        return Err(UpdateFailure::InvalidRelease);
    };

    Ok(Some(UpdateInfo {
        version: version.to_string(),
        notes: root.get("body").and_then(Value::as_str).unwrap_or_default().trim().to_string(),
        page_url: root.get("html_url").and_then(Value::as_str).unwrap_or_default().to_string(),
        dmg_url,
        sha256_url,
    }))
}

/// « 0.10.0 » est-il plus récent que « 0.9.2 » ? None si un numéro est illisible.
pub fn is_newer(candidate: &str, current: &str) -> Option<bool> {
    Some(parse_version(candidate)? > parse_version(current)?)
}

/// « 1.2.3 » → [1, 2, 3]. Les numéros manquants valent 0 : « 1.2 » = « 1.2.0 ».
/// Rien d'autre que des chiffres et des points n'est accepté : la version
/// vient de GitHub et sert ensuite de nom de fichier.
pub fn parse_version(text: &str) -> Option<[u64; 3]> {
    let mut parts = [0; 3];
    for (index, part) in text.split('.').enumerate() {
        // Plus de trois numéros : get_mut renvoie None.
        let slot = parts.get_mut(index)?;
        if part.is_empty() || !part.bytes().all(|byte| byte.is_ascii_digit()) {
            return None;
        }
        *slot = part.parse().ok()?;
    }
    Some(parts)
}

/// Télécharge le DMG dans `directory` et vérifie son empreinte. Appel
/// bloquant, jusqu'à 2 min.
#[uniffi::export]
pub fn download_update(info: UpdateInfo, directory: String) -> DownloadOutcome {
    match download_verified(&info, Path::new(&directory), Duration::from_secs(120)) {
        Ok(path) => DownloadOutcome::Downloaded {
            path: path.to_string_lossy().into_owned(),
        },
        Err(reason) => DownloadOutcome::Failed { reason },
    }
}

pub fn download_verified(info: &UpdateInfo, directory: &Path, timeout: Duration) -> Result<PathBuf, UpdateFailure> {
    let agent = download_agent(timeout);

    // L'empreinte : « <64 caractères hexadécimaux>  Pulse-X.Y.Z.dmg » (format de shasum).
    let mut checksum_file = String::new();
    open(&agent, &info.sha256_url)?
        .take(4096)
        .read_to_string(&mut checksum_file)
        .map_err(|_| UpdateFailure::Offline)?;
    let expected = parse_checksum(&checksum_file).ok_or(UpdateFailure::InvalidRelease)?;

    fs::create_dir_all(directory).map_err(|_| UpdateFailure::WriteFailed)?;
    let final_path = directory.join(format!("Pulse-{}.dmg", sanitize(&info.version)));
    let partial_path = final_path.with_extension("dmg.part");

    let result = (|| {
        let mut file = File::create(&partial_path).map_err(|_| UpdateFailure::WriteFailed)?;
        let mut body = open(&agent, &info.dmg_url)?.take(MAX_DOWNLOAD_BYTES);
        let mut hasher = Sha256::new();
        let mut buffer = vec![0; 64 * 1024];
        // On écrit le fichier et on calcule son empreinte au fil de l'eau.
        loop {
            let count = body.read(&mut buffer).map_err(|_| UpdateFailure::Offline)?;
            if count == 0 {
                break;
            }
            file.write_all(&buffer[..count]).map_err(|_| UpdateFailure::WriteFailed)?;
            hasher.update(&buffer[..count]);
        }
        let actual = hex(&hasher.finalize());
        file.sync_all().map_err(|_| UpdateFailure::WriteFailed)?;
        if actual != expected {
            return Err(UpdateFailure::ChecksumMismatch);
        }
        fs::rename(&partial_path, &final_path).map_err(|_| UpdateFailure::WriteFailed)
    })();

    if result.is_err() {
        let _ = fs::remove_file(&partial_path);
    }
    result.map(|()| final_path)
}

/// Les téléchargements de GitHub redirigent vers un autre serveur : on suit
/// les redirections ici (aucun token n'est envoyé), contrairement aux API.
fn download_agent(timeout: Duration) -> ureq::Agent {
    ureq::Agent::config_builder()
        .timeout_global(Some(timeout))
        .http_status_as_error(false)
        .max_redirects(5)
        .build()
        .into()
}

fn open(agent: &ureq::Agent, url: &str) -> Result<impl Read, UpdateFailure> {
    let response = agent
        .get(url)
        .header("User-Agent", "Pulse")
        .call()
        .map_err(|_| UpdateFailure::Offline)?;
    match response.status().as_u16() {
        200 => Ok(response.into_body().into_reader()),
        403 | 429 => Err(UpdateFailure::RateLimited),
        404 => Err(UpdateFailure::InvalidRelease),
        _ => Err(UpdateFailure::Unavailable),
    }
}

/// Le premier mot du fichier, s'il ressemble à une empreinte SHA-256.
pub fn parse_checksum(text: &str) -> Option<String> {
    let word = text.split_whitespace().next()?.to_ascii_lowercase();
    (word.len() == 64 && word.chars().all(|c| c.is_ascii_hexdigit())).then_some(word)
}

/// La version sert de nom de fichier : on n'y garde que chiffres et points.
fn sanitize(version: &str) -> String {
    version.chars().filter(|c| c.is_ascii_digit() || *c == '.').collect()
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}
