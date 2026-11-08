//! Usage de ChatGPT : les limites de Codex, lues avec le compte de Codex CLI.

use std::fs;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

use serde_json::Value;
use time::OffsetDateTime;
use time::format_description::well_known::Rfc3339;

use crate::claude::ParseError;
use crate::http::{self, FetchError};
use crate::model::{AiUsage, UsageWindow};

pub const USAGE_URL: &str = "https://chatgpt.com/backend-api/wham/usage";

/// Nombre maximum de fichiers de session lus pour le repli.
const MAX_SESSION_FILES: usize = 50;

/// Identifiants de Codex, lus dans auth.json et jamais conservés.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CodexAuth {
    pub access_token: String,
    pub account_id: Option<String>,
}

/// Le dossier de Codex : $CODEX_HOME, sinon ~/.codex.
pub fn default_codex_dir() -> Option<PathBuf> {
    if let Some(dir) = std::env::var_os("CODEX_HOME").filter(|dir| !dir.is_empty()) {
        return Some(PathBuf::from(dir));
    }
    std::env::var_os("HOME").map(|home| Path::new(&home).join(".codex"))
}

/// Lit auth.json, en lecture seule. None : Codex n'est pas connecté.
pub fn read_auth(codex_dir: &Path) -> Option<CodexAuth> {
    parse_auth(&fs::read_to_string(codex_dir.join("auth.json")).ok()?)
}

pub fn parse_auth(json: &str) -> Option<CodexAuth> {
    let root: Value = serde_json::from_str(json).ok()?;
    let tokens = root.get("tokens")?;
    let access_token = tokens.get("access_token")?.as_str().filter(|token| !token.is_empty())?;
    let account_id = tokens
        .get("account_id")
        .and_then(Value::as_str)
        .filter(|id| !id.is_empty())
        .map(str::to_string);

    Some(CodexAuth {
        access_token: access_token.to_string(),
        account_id,
    })
}

/// Interroge l'API d'usage. Appel bloquant.
pub fn fetch_usage(url: &str, auth: &CodexAuth, timeout: Duration, now: i64) -> Result<AiUsage, FetchError> {
    let authorization = format!("Bearer {}", auth.access_token);
    let mut headers = vec![
        ("Authorization", authorization.as_str()),
        ("User-Agent", "codex-cli"),
    ];
    if let Some(account_id) = &auth.account_id {
        headers.push(("ChatGPT-Account-Id", account_id));
    }
    let response = http::get(url, &headers, timeout)?;

    match response.status {
        200 => parse_chatgpt_usage(&response.body, now).map_err(|_| FetchError::Unavailable),
        401 | 403 => Err(FetchError::Expired),
        429 => Err(FetchError::Blocked),
        _ => Err(FetchError::Unavailable),
    }
}

/// Lit la réponse de l'API. `now` sert quand seul reset_after_seconds est donné.
pub fn parse_chatgpt_usage(json: &str, now: i64) -> Result<AiUsage, ParseError> {
    let root: Value = match serde_json::from_str(json) {
        Ok(value) => value,
        Err(_) => return Err(ParseError::InvalidJson),
    };

    let windows: Vec<UsageWindow> = [("primary_window", "Session"), ("secondary_window", "Semaine")]
        .iter()
        .filter_map(|(key, fallback_label)| {
            let window = root.get("rate_limit")?.get(key)?;
            let percent = window.get("used_percent")?.as_f64()?;
            let resets_at = window.get("reset_at").and_then(as_seconds).or_else(|| {
                let after = window.get("reset_after_seconds").and_then(as_seconds)?;
                Some(now + after)
            });
            let seconds = window.get("limit_window_seconds").and_then(as_seconds);
            Some(usage_window(window_label(seconds, fallback_label), percent, resets_at))
        })
        .collect();

    if windows.is_empty() {
        return Err(ParseError::NoUsableData);
    }
    Ok(AiUsage { windows })
}

/// Repli : la dernière ligne « rate_limits » des fichiers de session, du plus
/// récent au plus ancien.
pub fn latest_session_usage(codex_dir: &Path) -> Option<AiUsage> {
    let mut files = Vec::new();
    collect_session_files(&codex_dir.join("sessions"), 0, &mut files);
    files.sort_by_key(|(modified, _)| std::cmp::Reverse(*modified));

    files.iter().take(MAX_SESSION_FILES).find_map(|(_, path)| {
        let text = fs::read_to_string(path).ok()?;
        text.lines()
            .rev()
            .filter(|line| line.contains("\"rate_limits\""))
            .find_map(parse_session_line)
    })
}

/// Lit une ligne de session de Codex qui contient « rate_limits ».
pub fn parse_session_line(line: &str) -> Option<AiUsage> {
    let root: Value = serde_json::from_str(line).ok()?;
    let limits = root.pointer("/payload/rate_limits").or_else(|| root.get("rate_limits"))?;
    // Les anciennes versions donnent resets_in_seconds, compté depuis l'heure de la ligne.
    let logged_at = root
        .get("timestamp")
        .and_then(Value::as_str)
        .and_then(|text| OffsetDateTime::parse(text, &Rfc3339).ok())
        .map(|date| date.unix_timestamp());

    let windows: Vec<UsageWindow> = [("primary", "Session"), ("secondary", "Semaine")]
        .iter()
        .filter_map(|(key, fallback_label)| {
            let window = limits.get(key)?;
            let percent = window.get("used_percent")?.as_f64()?;
            let resets_at = window.get("resets_at").and_then(as_seconds).or_else(|| {
                let after = window.get("resets_in_seconds").and_then(as_seconds)?;
                Some(logged_at? + after)
            });
            let seconds = window.get("window_minutes").and_then(as_seconds).map(|minutes| minutes * 60);
            Some(usage_window(window_label(seconds, fallback_label), percent, resets_at))
        })
        .collect();

    if windows.is_empty() { None } else { Some(AiUsage { windows }) }
}

/// Nom d'une limite d'après sa durée : 5 h → « Session (5 h) », 7 jours → « Semaine ».
pub fn window_label(seconds: Option<i64>, fallback: &str) -> String {
    match seconds {
        Some(604_800) => "Semaine".to_string(),
        Some(s) if s > 0 && s < 86_400 && s % 3_600 == 0 => format!("Session ({} h)", s / 3_600),
        Some(s) if s > 0 && s % 86_400 == 0 => format!("{} jours", s / 86_400),
        _ => fallback.to_string(),
    }
}

fn usage_window(label: String, percent: f64, resets_at: Option<i64>) -> UsageWindow {
    UsageWindow {
        label,
        percent: percent.clamp(0.0, 100.0),
        resets_at,
        projected_full_at: None,
    }
}

/// Accepte un entier ou un nombre à virgule.
fn as_seconds(value: &Value) -> Option<i64> {
    value.as_i64().or_else(|| value.as_f64().map(|seconds| seconds as i64))
}

/// Les fichiers .jsonl du dossier et de ses sous-dossiers (année/mois/jour).
fn collect_session_files(dir: &Path, depth: usize, files: &mut Vec<(SystemTime, PathBuf)>) {
    if depth > 4 {
        return;
    }
    let Ok(entries) = fs::read_dir(dir) else { return };
    for entry in entries.flatten() {
        let path = entry.path();
        let Ok(metadata) = entry.metadata() else { continue };
        if metadata.is_dir() {
            collect_session_files(&path, depth + 1, files);
        } else if path.extension().is_some_and(|ext| ext == "jsonl") {
            files.push((metadata.modified().unwrap_or(SystemTime::UNIX_EPOCH), path));
        }
    }
}
