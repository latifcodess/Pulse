//! Point d'entrée du cœur Rust pour l'app Swift.

use std::sync::{Arc, Mutex, PoisonError};
use std::time::Duration;

use time::OffsetDateTime;

use crate::claude::{FetchError, USAGE_URL, fetch_claude_usage};
use crate::model::{AiState, AiUsage};

const TIMEOUT: Duration = Duration::from_secs(10);

#[derive(uniffi::Object)]
pub struct AiMonitor {
    endpoint: String,
    timeout: Duration,
    /// Dernière réponse valide, réaffichée quand il n'y a plus de réseau.
    last_claude: Mutex<Option<AiUsage>>,
}

#[uniffi::export]
impl AiMonitor {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Self::with_endpoint(USAGE_URL, TIMEOUT)
    }

    /// Récupère l'usage de Claude. Appel bloquant, jusqu'à 10 s. Le token n'est
    /// utilisé que pour cette requête : il n'est jamais conservé.
    pub fn refresh_claude(&self, access_token: String) -> AiState {
        let result = fetch_claude_usage(&self.endpoint, &access_token, self.timeout);
        let now = OffsetDateTime::now_utc().unix_timestamp();
        let mut last = self
            .last_claude
            .lock()
            .unwrap_or_else(PoisonError::into_inner);

        match result {
            Ok(usage) => {
                let current = usage.as_of(now);
                *last = Some(usage);
                AiState::Ok(current)
            }
            Err(FetchError::Offline) => AiState::Offline(last.as_ref().map(|u| u.as_of(now))),
            Err(FetchError::Expired) => AiState::Expired,
            Err(FetchError::Blocked) => AiState::Blocked,
            Err(FetchError::Unavailable) => AiState::Unavailable,
        }
    }
}

impl AiMonitor {
    /// Permet aux tests de viser un serveur local, avec un délai court.
    pub fn with_endpoint(endpoint: &str, timeout: Duration) -> Arc<Self> {
        Arc::new(Self {
            endpoint: endpoint.to_string(),
            timeout,
            last_claude: Mutex::new(None),
        })
    }
}
