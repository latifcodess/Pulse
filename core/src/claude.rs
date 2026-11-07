//! Récupération et parsing de l'usage de Claude.

use std::time::Duration;

use serde_json::Value;
use time::OffsetDateTime;
use time::format_description::well_known::Rfc3339;

use crate::model::{AiUsage, UsageWindow};

/// Adresse de l'API d'usage de Claude.
pub const USAGE_URL: &str = "https://api.anthropic.com/api/oauth/usage";

/// Clé JSON de chaque fenêtre et libellé affiché.
const WINDOWS: [(&str, &str); 2] = [("five_hour", "Session (5 h)"), ("seven_day", "Semaine")];

/// Pourquoi une réponse n'a pas pu donner d'usage.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ParseError {
    /// Le texte reçu n'est pas du JSON.
    InvalidJson,
    /// Le JSON est valide, mais aucune fenêtre n'est exploitable.
    NoUsableData,
}

/// Pourquoi l'usage n'a pas pu être récupéré.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FetchError {
    /// 401 ou 403 : le token n'est plus accepté.
    Expired,
    /// 429 : trop de requêtes.
    Blocked,
    /// Pas de réponse : pas de réseau, serveur injoignable ou délai dépassé.
    Offline,
    /// Le serveur a répondu, mais la réponse est inexploitable.
    Unavailable,
}

/// Interroge l'API d'usage. Cet appel est bloquant : il ne doit pas tourner sur
/// le thread principal de l'app.
pub fn fetch_claude_usage(
    url: &str,
    access_token: &str,
    timeout: Duration,
) -> Result<AiUsage, FetchError> {
    let agent: ureq::Agent = ureq::Agent::config_builder()
        .timeout_global(Some(timeout))
        // Le code HTTP est traité ci-dessous, pas comme une erreur de transport.
        .http_status_as_error(false)
        // Une redirection pourrait envoyer le token vers un autre serveur.
        .max_redirects(0)
        .build()
        .into();

    let mut response = agent
        .get(url)
        .header("Authorization", format!("Bearer {access_token}"))
        .header("anthropic-beta", "oauth-2025-04-20")
        .call()
        .map_err(transport_error)?;

    match response.status().as_u16() {
        200 => {}
        401 | 403 => return Err(FetchError::Expired),
        429 => return Err(FetchError::Blocked),
        _ => return Err(FetchError::Unavailable),
    }

    let bytes = response.body_mut().read_to_vec().map_err(transport_error)?;
    let body = String::from_utf8(bytes).map_err(|_| FetchError::Unavailable)?;
    parse_claude_usage(&body).map_err(|_| FetchError::Unavailable)
}

fn transport_error(error: ureq::Error) -> FetchError {
    match error {
        // Requête ou réponse invalide : le réseau n'y est pour rien.
        ureq::Error::Http(_) | ureq::Error::BadUri(_) | ureq::Error::BodyExceedsLimit(_) => {
            FetchError::Unavailable
        }
        _ => FetchError::Offline,
    }
}

/// Lit la réponse de l'API. Une fenêtre sans pourcentage lisible est ignorée,
/// sans empêcher de lire l'autre.
pub fn parse_claude_usage(json: &str) -> Result<AiUsage, ParseError> {
    let root: Value = match serde_json::from_str(json) {
        Ok(value) => value,
        Err(_) => return Err(ParseError::InvalidJson),
    };

    let windows: Vec<UsageWindow> = WINDOWS
        .iter()
        .filter_map(|(key, label)| parse_window(&root, key, label))
        .collect();

    if windows.is_empty() {
        return Err(ParseError::NoUsableData);
    }
    Ok(AiUsage { windows })
}

fn parse_window(root: &Value, key: &str, label: &str) -> Option<UsageWindow> {
    let window = root.get(key)?;
    let percent = window.get("utilization")?.as_f64()?;

    Some(UsageWindow {
        label: label.to_string(),
        percent: percent.clamp(0.0, 100.0),
        resets_at: parse_resets_at(window),
    })
}

fn parse_resets_at(window: &Value) -> Option<i64> {
    let text = window.get("resets_at")?.as_str()?;
    match OffsetDateTime::parse(text, &Rfc3339) {
        Ok(date) => Some(date.unix_timestamp()),
        Err(_) => None,
    }
}
