//! Usage de Claude via la session du compte claude.ai (cookie sessionKey).

use std::time::Duration;

use serde_json::Value;

use crate::claude::parse_claude_usage;
use crate::http::{self, FetchError, HttpResponse};
use crate::model::AiUsage;

pub const BASE_URL: &str = "https://claude.ai";

const SAFARI_USER_AGENT: &str = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) \
    AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15";

/// Liste les organisations, prend la première, puis lit son usage. Appel bloquant.
pub fn fetch_usage(base_url: &str, session_key: &str, timeout: Duration) -> Result<AiUsage, FetchError> {
    let cookie = format!("sessionKey={session_key}");
    let headers = [
        ("Cookie", cookie.as_str()),
        ("User-Agent", SAFARI_USER_AGENT),
        ("Accept", "application/json"),
    ];

    let organizations = http::get(&format!("{base_url}/api/organizations"), &headers, timeout)?;
    let uuid = organization_uuid(classify(&organizations)?).ok_or(FetchError::Unavailable)?;

    let usage = http::get(&format!("{base_url}{}", usage_path(&uuid)), &headers, timeout)?;
    parse_usage(&usage)
}

/// Classe une réponse de claude.ai : le corps JSON si elle est exploitable,
/// sinon l'erreur correspondante.
pub fn classify(response: &HttpResponse) -> Result<&str, FetchError> {
    // Une page HTML au lieu de JSON : c'est la protection anti-bot.
    if is_html(response) && matches!(response.status, 200 | 403) {
        return Err(FetchError::Blocked);
    }
    match response.status {
        200 => Ok(&response.body),
        401 | 403 => Err(FetchError::Expired),
        429 => Err(FetchError::Blocked),
        _ => Err(FetchError::Unavailable),
    }
}

/// Classe puis lit une réponse de l'URL d'usage (même format que l'API de Claude Code).
pub fn parse_usage(response: &HttpResponse) -> Result<AiUsage, FetchError> {
    parse_claude_usage(classify(response)?).map_err(|_| FetchError::Unavailable)
}

/// Le uuid de la première organisation. Il est refusé s'il contient autre chose
/// que des lettres, des chiffres et des tirets, car il est placé dans une URL.
pub fn organization_uuid(body: &str) -> Option<String> {
    let organizations: Value = serde_json::from_str(body).ok()?;
    let uuid = organizations.get(0)?.get("uuid")?.as_str()?;

    let is_safe = !uuid.is_empty() && uuid.chars().all(|c| c.is_ascii_alphanumeric() || c == '-');
    if is_safe { Some(uuid.to_string()) } else { None }
}

fn usage_path(uuid: &str) -> String {
    format!("/api/organizations/{uuid}/usage")
}

fn is_html(response: &HttpResponse) -> bool {
    let declared = response
        .content_type
        .as_deref()
        .is_some_and(|value| value.to_ascii_lowercase().contains("text/html"));
    let start = response.body.trim_start().get(..5).unwrap_or("").to_ascii_lowercase();
    declared || start == "<!doc" || start == "<html"
}

/// Pour le repli de l'app : à partir de la réponse /api/organizations obtenue
/// dans une page web, donne le chemin de l'URL d'usage, ou rien si elle est
/// inexploitable.
#[uniffi::export]
pub fn claude_web_usage_path(organizations: HttpResponse) -> Option<String> {
    let body = classify(&organizations).ok()?;
    organization_uuid(body).map(|uuid| usage_path(&uuid))
}
