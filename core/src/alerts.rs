//! Les alertes : quand prévenir l'utilisateur. L'app Swift ne fait qu'afficher
//! les notifications que ce moteur lui demande.
//!
//! Chaque alerte se déclenche une seule fois, puis se réarme quand la valeur
//! redescend (ou quand la session redevient valide).

use std::collections::HashMap;
use std::sync::{Arc, Mutex, PoisonError};

use serde_json::{Value, json};

use crate::model::{AiService, AiState, UsageWindow};

/// Ce que surveille une règle.
#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum AlertKind {
    /// La limite n° `window_index` (0 = la 1re) atteint `percent` % utilisé.
    Threshold { window_index: u32, percent: f64 },
    /// Une nouvelle fenêtre démarre alors que la précédente avait dépassé
    /// `after_percent` % : la limite est de nouveau disponible.
    Available { after_percent: f64 },
    /// La connexion a expiré.
    Expired,
    /// Au rythme actuel, une limite sera atteinte dans moins de `minutes`
    /// minutes (voir projection.rs). Une seule fois par fenêtre.
    Projection { minutes: u32 },
}

/// Une règle d'alerte réglée par l'utilisateur.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct AlertRule {
    pub id: String,
    pub enabled: bool,
    /// None : toutes les IA.
    pub service: Option<AiService>,
    pub kind: AlertKind,
}

/// Ce qui s'est passé, pour que l'app rédige la notification.
#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum AlertEventKind {
    Threshold {
        window_label: String,
        percent: f64,
        threshold: f64,
        resets_at: Option<i64>,
    },
    Available {
        window_label: String,
        previous_percent: f64,
    },
    Expired,
    Projection {
        window_label: String,
        percent: f64,
        full_at: i64,
    },
}

/// Une notification à afficher.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct AlertEvent {
    pub rule_id: String,
    pub service: AiService,
    pub kind: AlertEventKind,
}

/// Les alertes proposées au premier lancement.
#[uniffi::export]
pub fn default_alert_rules() -> Vec<AlertRule> {
    let rule = |id: &str, kind| AlertRule {
        id: id.to_string(),
        enabled: true,
        service: None,
        kind,
    };
    vec![
        rule("defaut-1re-limite", AlertKind::Threshold { window_index: 0, percent: 80.0 }),
        rule("defaut-2e-limite", AlertKind::Threshold { window_index: 1, percent: 90.0 }),
        rule("defaut-disponible", AlertKind::Available { after_percent: 80.0 }),
        rule("defaut-expiree", AlertKind::Expired),
        rule("defaut-projection", AlertKind::Projection { minutes: 30 }),
    ]
}

/// Une nouvelle fenêtre est considérée démarrée si la précédente s'est
/// terminée, si l'heure de reset a avancé de plus de ce délai…
const RESET_TOLERANCE_SECONDS: i64 = 60;
/// … ou, sans heure de reset, si le % a baissé d'au moins ce nombre de points.
const DROP_WITHOUT_RESET_TIME: f64 = 20.0;

/// Une alerte déjà déclenchée : elle ne se redéclenche pas tant qu'elle n'est
/// pas réarmée. On garde la règle telle qu'elle était : si l'utilisateur la
/// modifie, l'alerte repart de zéro.
type SlotKey = (String, AiService, u32);

#[derive(Default)]
struct EngineState {
    fired: HashMap<SlotKey, AlertKind>,
    /// Alertes « une fois par fenêtre » déjà envoyées, par limite (libellé).
    /// Elles ne se réarment qu'au début d'une nouvelle fenêtre.
    fired_in_window: HashMap<(String, AiService, String), AlertKind>,
    /// Dernières limites reçues de chaque service (réponses valides seulement).
    last_windows: HashMap<AiService, Vec<UsageWindow>>,
}

#[derive(uniffi::Object)]
pub struct AlertEngine {
    state: Mutex<EngineState>,
}

#[uniffi::export]
impl AlertEngine {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            state: Mutex::new(EngineState::default()),
        })
    }

    /// À appeler à chaque nouvel état d'un service. Renvoie les notifications
    /// à afficher. `now` est en secondes Unix.
    pub fn evaluate(&self, service: AiService, state: AiState, rules: Vec<AlertRule>, now: i64) -> Vec<AlertEvent> {
        let mut engine = self.state.lock().unwrap_or_else(PoisonError::into_inner);
        let rules: Vec<&AlertRule> = rules
            .iter()
            .filter(|rule| rule.enabled && rule.service.is_none_or(|s| s == service))
            .collect();
        let mut events = Vec::new();

        match &state {
            AiState::Ok(usage) => {
                let windows = usage.as_of(now).windows;
                let previous = engine.last_windows.insert(service, windows.clone()).unwrap_or_default();
                for rule in &rules {
                    match &rule.kind {
                        AlertKind::Threshold { window_index, percent } => {
                            let Some(window) = windows.get(*window_index as usize) else {
                                continue;
                            };
                            let reached = window.percent >= *percent;
                            if engine.fire_once(rule, service, *window_index, reached) {
                                events.push(event(rule, service, AlertEventKind::Threshold {
                                    window_label: window.label.clone(),
                                    percent: window.percent,
                                    threshold: *percent,
                                    resets_at: window.resets_at,
                                }));
                            }
                        }
                        AlertKind::Available { after_percent } => {
                            for window in &windows {
                                let Some(before) = previous.iter().find(|w| w.label == window.label) else {
                                    continue;
                                };
                                if before.percent > *after_percent && is_new_window(before, window, now) {
                                    events.push(event(rule, service, AlertEventKind::Available {
                                        window_label: window.label.clone(),
                                        previous_percent: before.percent,
                                    }));
                                }
                            }
                        }
                        AlertKind::Projection { minutes } => {
                            for window in &windows {
                                let key = (rule.id.clone(), service, window.label.clone());
                                // Nouvelle fenêtre, ou règle modifiée : l'alerte se réarme.
                                let new_window = previous
                                    .iter()
                                    .find(|w| w.label == window.label)
                                    .is_some_and(|before| is_new_window(before, window, now));
                                if new_window || engine.fired_in_window.get(&key).is_some_and(|k| *k != rule.kind) {
                                    engine.fired_in_window.remove(&key);
                                }
                                let Some(full_at) = window.projected_full_at else {
                                    continue;
                                };
                                let soon = full_at - now <= i64::from(*minutes) * 60;
                                if soon && !engine.fired_in_window.contains_key(&key) {
                                    engine.fired_in_window.insert(key, rule.kind.clone());
                                    events.push(event(rule, service, AlertEventKind::Projection {
                                        window_label: window.label.clone(),
                                        percent: window.percent,
                                        full_at,
                                    }));
                                }
                            }
                        }
                        AlertKind::Expired => {
                            // La session est de nouveau valide : l'alerte se réarme.
                            engine.fire_once(rule, service, 0, false);
                        }
                    }
                }
            }
            AiState::Expired => {
                for rule in rules.iter().filter(|rule| rule.kind == AlertKind::Expired) {
                    if engine.fire_once(rule, service, 0, true) {
                        events.push(event(rule, service, AlertEventKind::Expired));
                    }
                }
            }
            // Hors ligne, bloqué… : pas de donnée fraîche, rien ne change.
            _ => {}
        }
        events
    }
}

impl EngineState {
    /// Vrai si l'alerte doit être envoyée maintenant : la condition est
    /// remplie et l'alerte était armée. Si la condition n'est plus remplie,
    /// l'alerte se réarme.
    fn fire_once(&mut self, rule: &AlertRule, service: AiService, index: u32, condition: bool) -> bool {
        let key = (rule.id.clone(), service, index);
        // Règle modifiée depuis le déclenchement : on repart de zéro.
        if self.fired.get(&key).is_some_and(|kind| *kind != rule.kind) {
            self.fired.remove(&key);
        }
        if !condition {
            self.fired.remove(&key);
            return false;
        }
        if self.fired.contains_key(&key) {
            return false;
        }
        self.fired.insert(key, rule.kind.clone());
        true
    }
}

fn event(rule: &AlertRule, service: AiService, kind: AlertEventKind) -> AlertEvent {
    AlertEvent {
        rule_id: rule.id.clone(),
        service,
        kind,
    }
}

/// La limite `after` appartient-elle à une nouvelle fenêtre par rapport à `before` ?
pub fn is_new_window(before: &UsageWindow, after: &UsageWindow, now: i64) -> bool {
    match (before.resets_at, after.resets_at) {
        // La fenêtre précédente est terminée.
        (Some(previous), _) if previous <= now => true,
        // L'heure de reset a avancé : une nouvelle fenêtre a commencé.
        (Some(previous), Some(next)) => next > previous + RESET_TOLERANCE_SECONDS,
        // Sans heure de reset : seule une forte baisse l'indique.
        _ => after.percent + DROP_WITHOUT_RESET_TIME <= before.percent,
    }
}

// --- Enregistrement des règles (JSON, rangé dans les préférences par l'app) ---

/// Les règles en JSON, pour les préférences de l'app.
#[uniffi::export]
pub fn alert_rules_to_json(rules: Vec<AlertRule>) -> String {
    let items: Vec<Value> = rules
        .iter()
        .map(|rule| {
            let mut item = json!({
                "id": rule.id,
                "enabled": rule.enabled,
                "service": rule.service.map(service_key),
            });
            match &rule.kind {
                AlertKind::Threshold { window_index, percent } => {
                    item["kind"] = json!("threshold");
                    item["window"] = json!(window_index);
                    item["percent"] = json!(percent);
                }
                AlertKind::Available { after_percent } => {
                    item["kind"] = json!("available");
                    item["percent"] = json!(after_percent);
                }
                AlertKind::Expired => item["kind"] = json!("expired"),
                AlertKind::Projection { minutes } => {
                    item["kind"] = json!("projection");
                    item["minutes"] = json!(minutes);
                }
            }
            item
        })
        .collect();
    Value::Array(items).to_string()
}

/// Relit les règles. JSON illisible : les règles par défaut. Règle illisible :
/// ignorée, les autres sont gardées.
#[uniffi::export]
pub fn alert_rules_from_json(json: String) -> Vec<AlertRule> {
    let Ok(Value::Array(items)) = serde_json::from_str::<Value>(&json) else {
        return default_alert_rules();
    };
    items.iter().filter_map(parse_rule).collect()
}

fn parse_rule(item: &Value) -> Option<AlertRule> {
    let id = item.get("id")?.as_str().filter(|id| !id.is_empty())?.to_string();
    let percent = || item.get("percent").and_then(Value::as_f64).map(|p| p.clamp(1.0, 100.0));
    let kind = match item.get("kind")?.as_str()? {
        "threshold" => AlertKind::Threshold {
            window_index: item.get("window").and_then(Value::as_u64).unwrap_or(0).min(9) as u32,
            percent: percent()?,
        },
        "available" => AlertKind::Available { after_percent: percent()? },
        "expired" => AlertKind::Expired,
        "projection" => AlertKind::Projection {
            minutes: item.get("minutes").and_then(Value::as_u64).unwrap_or(30).clamp(1, 24 * 60) as u32,
        },
        _ => return None,
    };
    let service = match item.get("service") {
        None | Some(Value::Null) => None,
        // Un service inconnu : la règle est ignorée plutôt qu'appliquée à toutes les IA.
        Some(value) => Some(service_from_key(value.as_str()?)?),
    };
    Some(AlertRule {
        id,
        enabled: item.get("enabled").and_then(Value::as_bool).unwrap_or(true),
        service,
        kind,
    })
}

fn service_key(service: AiService) -> &'static str {
    match service {
        AiService::Claude => "claude",
        AiService::ChatGpt => "chatgpt",
        AiService::Gemini => "gemini",
        AiService::Copilot => "copilot",
    }
}

fn service_from_key(key: &str) -> Option<AiService> {
    [AiService::Claude, AiService::ChatGpt, AiService::Gemini, AiService::Copilot]
        .into_iter()
        .find(|service| service_key(*service) == key)
}
