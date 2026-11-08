//! Usage de GitHub Copilot, avec le token de GitHub CLI (gh).

use std::io::Read;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant};

use serde_json::Value;
use time::OffsetDateTime;
use time::format_description::well_known::Rfc3339;

use crate::claude::ParseError;
use crate::http::{self, FetchError};
use crate::model::{AiUsage, UsageWindow};

pub const USAGE_URL: &str = "https://api.github.com/copilot_internal/user";

/// Emplacements habituels de gh (Homebrew Apple Silicon, Homebrew Intel, système).
pub const GH_PATHS: [&str; 3] = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"];

/// Clé JSON de chaque quota et libellé affiché.
const QUOTAS: [(&str, &str); 3] = [
    ("chat", "Chat"),
    ("completions", "Complétions"),
    ("premium_interactions", "Requêtes premium"),
];

/// Pourquoi le token n'a pas pu être obtenu.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TokenError {
    /// gh n'est installé à aucun des emplacements connus.
    NotInstalled,
    /// gh a répondu, mais sans token : pas de compte connecté.
    NotLoggedIn,
    /// gh n'a pas pu être lancé, ou n'a pas répondu à temps.
    Failed,
}

/// Lance « gh auth token » et renvoie le token. Rien n'est écrit sur le disque.
pub fn gh_token(gh_paths: &[PathBuf], timeout: Duration) -> Result<String, TokenError> {
    let gh = gh_paths.iter().find(|path| is_executable(path)).ok_or(TokenError::NotInstalled)?;
    let mut child = Command::new(gh)
        .args(["auth", "token"])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|_| TokenError::Failed)?;

    // Attend la fin de gh, sans bloquer plus que `timeout`.
    let deadline = Instant::now() + timeout;
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) if Instant::now() < deadline => thread::sleep(Duration::from_millis(50)),
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(TokenError::Failed);
            }
        }
    };
    if !status.success() {
        return Err(TokenError::NotLoggedIn);
    }

    let mut output = String::new();
    child
        .stdout
        .take()
        .ok_or(TokenError::Failed)?
        .read_to_string(&mut output)
        .map_err(|_| TokenError::Failed)?;
    let token = output.trim();
    if token.is_empty() {
        return Err(TokenError::NotLoggedIn);
    }
    Ok(token.to_string())
}

/// Interroge l'API de Copilot. Appel bloquant.
pub fn fetch_usage(url: &str, token: &str, timeout: Duration) -> Result<AiUsage, FetchError> {
    let authorization = format!("token {token}");
    let headers = [
        ("Authorization", authorization.as_str()),
        ("Accept", "application/json"),
        // L'API de GitHub refuse les requêtes sans User-Agent.
        ("User-Agent", "Pulse"),
    ];
    let response = http::get(url, &headers, timeout)?;

    match response.status {
        200 => parse_copilot_usage(&response.body).map_err(|_| FetchError::Unavailable),
        401 | 403 => Err(FetchError::Expired),
        429 => Err(FetchError::Blocked),
        _ => Err(FetchError::Unavailable),
    }
}

/// Lit la réponse : utilisé = 100 − percent_remaining. Les quotas illimités
/// sont ignorés.
pub fn parse_copilot_usage(json: &str) -> Result<AiUsage, ParseError> {
    let root: Value = match serde_json::from_str(json) {
        Ok(value) => value,
        Err(_) => return Err(ParseError::InvalidJson),
    };
    let resets_at = root
        .get("quota_reset_date_utc")
        .or_else(|| root.get("quota_reset_date"))
        .and_then(Value::as_str)
        .and_then(parse_reset_date);

    let windows: Vec<UsageWindow> = QUOTAS
        .iter()
        .filter_map(|(key, label)| {
            let quota = root.get("quota_snapshots")?.get(key)?;
            if quota.get("unlimited").and_then(Value::as_bool) == Some(true) {
                return None;
            }
            let remaining = quota.get("percent_remaining")?.as_f64()?;
            Some(UsageWindow {
                label: label.to_string(),
                percent: (100.0 - remaining).clamp(0.0, 100.0),
                resets_at,
            })
        })
        .collect();

    if windows.is_empty() {
        return Err(ParseError::NoUsableData);
    }
    Ok(AiUsage { windows })
}

/// « 2026-12-01T00:00:00.000Z », ou une date seule « 2026-12-01 » (minuit UTC).
fn parse_reset_date(text: &str) -> Option<i64> {
    let parsed = OffsetDateTime::parse(text, &Rfc3339)
        .or_else(|_| OffsetDateTime::parse(&format!("{text}T00:00:00Z"), &Rfc3339));
    parsed.ok().map(|date| date.unix_timestamp())
}

fn is_executable(path: &Path) -> bool {
    path.metadata()
        .is_ok_and(|metadata| metadata.is_file() && metadata.permissions().mode() & 0o111 != 0)
}
