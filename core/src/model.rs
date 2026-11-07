//! Modèle de données commun à tous les services d'IA.

/// Un service d'IA suivi par Pulse.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, uniffi::Enum)]
pub enum AiService {
    Claude,
    ChatGpt,
    Gemini,
    Copilot,
}

/// Une fenêtre de limite, par exemple « Session (5 h) ».
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct UsageWindow {
    pub label: String,
    /// Pourcentage utilisé, entre 0 et 100.
    pub percent: f64,
    /// Heure de reset en secondes Unix, si elle est connue.
    pub resets_at: Option<i64>,
}

/// L'usage d'un service : une entrée par fenêtre disponible.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct AiUsage {
    pub windows: Vec<UsageWindow>,
}

impl AiUsage {
    /// L'usage vu à l'instant `now` : une limite dont l'heure de reset est passée
    /// repart à 0 %.
    pub fn as_of(&self, now: i64) -> AiUsage {
        let windows = self
            .windows
            .iter()
            .map(|window| match window.resets_at {
                Some(resets_at) if resets_at <= now => UsageWindow {
                    label: window.label.clone(),
                    percent: 0.0,
                    resets_at: None,
                },
                _ => window.clone(),
            })
            .collect();
        AiUsage { windows }
    }
}

/// L'état d'un service, tel que l'app doit l'afficher.
#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum AiState {
    NotConnected,
    Ok(AiUsage),
    /// Pas de réseau : contient la dernière valeur connue, s'il y en a une.
    Offline(Option<AiUsage>),
    Expired,
    Blocked,
    Unavailable,
}
