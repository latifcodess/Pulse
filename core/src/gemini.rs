//! Usage de Gemini, avec le compte de Gemini CLI (~/.gemini/oauth_creds.json).
//!
//! Le fichier est lu, jamais modifié : un token renouvelé reste en mémoire.

use std::fs;
use std::path::{Path, PathBuf};
use std::time::Duration;

use serde_json::{Value, json};
use time::OffsetDateTime;
use time::format_description::well_known::Rfc3339;

use crate::claude::ParseError;
use crate::http::{self, FetchError};
use crate::model::{AiUsage, UsageWindow};

pub const TOKEN_URL: &str = "https://oauth2.googleapis.com/token";
pub const API_BASE_URL: &str = "https://cloudcode-pa.googleapis.com/v1internal";

// Identifiants OAuth publics de Gemini CLI, repris de son code source
// (packages/core/src/code_assist/oauth2.ts). Pour une application installée,
// Google indique que ce « secret » n'en est pas un : il est publié avec l'app.
const CLIENT_ID: &str = "681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j.apps.googleusercontent.com";
const CLIENT_SECRET: &str = "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";

/// Marge avant l'expiration : un token qui expire dans moins d'une minute est
/// renouvelé tout de suite.
const EXPIRY_MARGIN_SECONDS: i64 = 60;

/// Le contenu utile de oauth_creds.json.
#[derive(Debug, Clone, PartialEq)]
pub struct GeminiCreds {
    pub access_token: Option<String>,
    pub refresh_token: Option<String>,
    /// Expiration de access_token, en secondes Unix.
    pub expires_at: Option<i64>,
}

impl GeminiCreds {
    /// Le token du fichier, s'il est encore valable. Sans date d'expiration,
    /// on l'essaie quand même : l'API dira s'il est refusé.
    pub fn valid_access_token(&self, now: i64) -> Option<&str> {
        let token = self.access_token.as_deref()?;
        match self.expires_at {
            Some(expires_at) if expires_at <= now + EXPIRY_MARGIN_SECONDS => None,
            _ => Some(token),
        }
    }
}

/// Un token obtenu auprès de Google, gardé en mémoire seulement.
#[derive(Debug, Clone, PartialEq)]
pub struct AccessToken {
    pub token: String,
    /// En secondes Unix.
    pub expires_at: i64,
}

impl AccessToken {
    pub fn is_valid(&self, now: i64) -> bool {
        self.expires_at > now + EXPIRY_MARGIN_SECONDS
    }
}

/// ~/.gemini, le dossier de Gemini CLI.
pub fn default_gemini_dir() -> Option<PathBuf> {
    std::env::var_os("HOME").map(|home| Path::new(&home).join(".gemini"))
}

/// Lit oauth_creds.json, en lecture seule. None : Gemini CLI n'est pas connecté.
pub fn read_creds(gemini_dir: &Path) -> Option<GeminiCreds> {
    parse_creds(&fs::read_to_string(gemini_dir.join("oauth_creds.json")).ok()?)
}

pub fn parse_creds(json: &str) -> Option<GeminiCreds> {
    let root: Value = serde_json::from_str(json).ok()?;
    let text = |key: &str| {
        root.get(key)
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
            .map(str::to_string)
    };
    let creds = GeminiCreds {
        access_token: text("access_token"),
        refresh_token: text("refresh_token"),
        // expiry_date est en millisecondes.
        expires_at: root.get("expiry_date").and_then(Value::as_f64).map(|ms| (ms / 1000.0) as i64),
    };
    if creds.access_token.is_none() && creds.refresh_token.is_none() {
        return None;
    }
    Some(creds)
}

/// Demande un nouveau token d'accès à Google. Appel bloquant.
pub fn refresh_access_token(
    url: &str,
    refresh_token: &str,
    timeout: Duration,
    now: i64,
) -> Result<AccessToken, FetchError> {
    let body = form_encode(&[
        ("client_id", CLIENT_ID),
        ("client_secret", CLIENT_SECRET),
        ("refresh_token", refresh_token),
        ("grant_type", "refresh_token"),
    ]);
    let headers = [
        ("Content-Type", "application/x-www-form-urlencoded"),
        ("Accept", "application/json"),
    ];
    let response = http::post(url, &headers, &body, timeout)?;

    match response.status {
        200 => parse_token_response(&response.body, now).ok_or(FetchError::Unavailable),
        // invalid_grant : le compte a été déconnecté ou le token révoqué.
        400 | 401 => Err(FetchError::Expired),
        429 => Err(FetchError::Blocked),
        _ => Err(FetchError::Unavailable),
    }
}

fn parse_token_response(json: &str, now: i64) -> Option<AccessToken> {
    let root: Value = serde_json::from_str(json).ok()?;
    let token = root.get("access_token")?.as_str().filter(|token| !token.is_empty())?;
    // Google donne une durée de validité ; une heure si elle manque.
    let expires_in = root.get("expires_in").and_then(Value::as_i64).unwrap_or(3600);
    Some(AccessToken {
        token: token.to_string(),
        expires_at: now + expires_in,
    })
}

/// Le projet Google associé au compte, nécessaire pour lire les quotas.
pub fn load_project(base_url: &str, token: &str, timeout: Duration) -> Result<String, FetchError> {
    // Mêmes métadonnées que Gemini CLI.
    let body = json!({
        "metadata": {
            "ideType": "IDE_UNSPECIFIED",
            "platform": "PLATFORM_UNSPECIFIED",
            "pluginType": "GEMINI",
        }
    });
    let response = post_json(&format!("{base_url}:loadCodeAssist"), token, &body, timeout)?;
    let root: Value = serde_json::from_str(&response).map_err(|_| FetchError::Unavailable)?;
    parse_project(&root).ok_or(FetchError::Unavailable)
}

/// cloudaicompanionProject est une chaîne, ou parfois un objet avec un « id ».
fn parse_project(root: &Value) -> Option<String> {
    let project = root.get("cloudaicompanionProject")?;
    let id = project.as_str().or_else(|| project.get("id")?.as_str())?;
    (!id.is_empty()).then(|| id.to_string())
}

/// Les quotas du compte, une limite par modèle.
pub fn fetch_quota(base_url: &str, token: &str, project: &str, timeout: Duration) -> Result<AiUsage, FetchError> {
    let body = json!({ "project": project });
    let response = post_json(&format!("{base_url}:retrieveUserQuota"), token, &body, timeout)?;
    parse_gemini_quota(&response).map_err(|_| FetchError::Unavailable)
}

fn post_json(url: &str, token: &str, body: &Value, timeout: Duration) -> Result<String, FetchError> {
    let authorization = format!("Bearer {token}");
    let headers = [
        ("Authorization", authorization.as_str()),
        ("Content-Type", "application/json"),
        ("Accept", "application/json"),
    ];
    let response = http::post(url, &headers, &body.to_string(), timeout)?;
    match response.status {
        200 => Ok(response.body),
        401 | 403 => Err(FetchError::Expired),
        429 => Err(FetchError::Blocked),
        _ => Err(FetchError::Unavailable),
    }
}

/// Lit buckets[] : utilisé = (1 − remainingFraction) × 100. Si un modèle
/// apparaît plusieurs fois, on garde la limite la plus entamée.
pub fn parse_gemini_quota(json: &str) -> Result<AiUsage, ParseError> {
    let root: Value = match serde_json::from_str(json) {
        Ok(value) => value,
        Err(_) => return Err(ParseError::InvalidJson),
    };
    let buckets = root.get("buckets").and_then(Value::as_array).map(Vec::as_slice).unwrap_or_default();

    let mut models: Vec<(String, UsageWindow)> = Vec::new();
    for bucket in buckets {
        let Some(model_id) = bucket.get("modelId").and_then(Value::as_str).filter(|id| !id.is_empty()) else {
            continue;
        };
        let Some(remaining) = bucket.get("remainingFraction").and_then(Value::as_f64) else {
            continue;
        };
        let window = UsageWindow {
            label: model_label(model_id),
            percent: ((1.0 - remaining) * 100.0).clamp(0.0, 100.0),
            resets_at: bucket
                .get("resetTime")
                .and_then(Value::as_str)
                .and_then(|text| OffsetDateTime::parse(text, &Rfc3339).ok())
                .map(|date| date.unix_timestamp()),
        };
        match models.iter_mut().find(|(id, _)| id == model_id) {
            Some((_, existing)) if existing.percent < window.percent => *existing = window,
            Some(_) => {}
            None => models.push((model_id.to_string(), window)),
        }
    }

    if models.is_empty() {
        return Err(ParseError::NoUsableData);
    }
    Ok(AiUsage {
        windows: models.into_iter().map(|(_, window)| window).collect(),
    })
}

/// « gemini-2.5-flash-lite » → « 2.5 Flash Lite ».
pub fn model_label(model_id: &str) -> String {
    let name = model_id.strip_prefix("gemini-").unwrap_or(model_id);
    let label = name
        .split(['-', '_'])
        .filter(|word| !word.is_empty())
        .map(capitalize)
        .collect::<Vec<_>>()
        .join(" ");
    if label.is_empty() { model_id.to_string() } else { label }
}

fn capitalize(word: &str) -> String {
    let mut chars = word.chars();
    match chars.next() {
        Some(first) => first.to_uppercase().chain(chars).collect(),
        None => String::new(),
    }
}

/// Encode un formulaire : lettres, chiffres et « -._~ » tels quels, le reste
/// en %XX.
fn form_encode(pairs: &[(&str, &str)]) -> String {
    let encode = |text: &str| -> String {
        text.bytes()
            .map(|byte| match byte {
                b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => (byte as char).to_string(),
                _ => format!("%{byte:02X}"),
            })
            .collect()
    };
    pairs
        .iter()
        .map(|(key, value)| format!("{}={}", encode(key), encode(value)))
        .collect::<Vec<_>>()
        .join("&")
}
