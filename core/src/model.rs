//! Modèle de données commun à tous les services d'IA.

/// Un service d'IA suivi par Pulse.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
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

/// L'état d'un service, tel que l'app doit l'afficher.
#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum AiState {
    NotConnected,
    Ok(AiUsage),
    Offline,
    Expired,
    Blocked,
    Unavailable,
}
