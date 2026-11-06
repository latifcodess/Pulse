//! Parsing de la réponse de l'API d'usage de Claude.

use serde_json::Value;
use time::OffsetDateTime;
use time::format_description::well_known::Rfc3339;

use crate::model::{AiUsage, UsageWindow};

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
