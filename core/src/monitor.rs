//! Point d'entrée du cœur Rust pour l'app Swift.

use std::sync::Arc;

use crate::claude::parse_claude_usage;
use crate::model::AiState;

/// Réponse d'exemple, intégrée au binaire le temps qu'il n'y ait pas de réseau.
const CLAUDE_FIXTURE: &str = include_str!("../tests/fixtures/claude.json");

#[derive(uniffi::Object)]
pub struct AiMonitor;

#[uniffi::export]
impl AiMonitor {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self)
    }

    /// Méthode de test : parse la réponse d'exemple de Claude.
    pub fn claude_fixture_state(&self) -> AiState {
        match parse_claude_usage(CLAUDE_FIXTURE) {
            Ok(usage) => AiState::Ok(usage),
            Err(_) => AiState::Unavailable,
        }
    }
}
