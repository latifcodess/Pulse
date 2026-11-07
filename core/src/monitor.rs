//! Point d'entrée du cœur Rust pour l'app Swift.

use std::sync::{Arc, Mutex, PoisonError};
use std::time::Duration;

use time::OffsetDateTime;

use crate::claude::{USAGE_URL, fetch_claude_usage};
use crate::claude_web;
use crate::http::{FetchError, HttpResponse};
use crate::model::{AiState, AiUsage};

const TIMEOUT: Duration = Duration::from_secs(10);

#[derive(uniffi::Object)]
pub struct AiMonitor {
    endpoint: String,
    web_base_url: String,
    timeout: Duration,
    /// Dernière réponse valide, réaffichée quand il n'y a plus de réseau.
    last_claude: Mutex<Option<AiUsage>>,
}

#[uniffi::export]
impl AiMonitor {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Self::with_endpoints(USAGE_URL, claude_web::BASE_URL, TIMEOUT)
    }

    /// Usage de Claude avec le token de Claude Code. Appel bloquant, jusqu'à
    /// 10 s par requête. Le token n'est jamais conservé.
    pub fn refresh_claude(&self, access_token: String) -> AiState {
        self.state_from(fetch_claude_usage(&self.endpoint, &access_token, self.timeout))
    }

    /// Usage de Claude avec le cookie du compte claude.ai. Appel bloquant, deux
    /// requêtes. Le cookie n'est jamais conservé.
    pub fn refresh_claude_web(&self, session_key: String) -> AiState {
        self.state_from(claude_web::fetch_usage(&self.web_base_url, &session_key, self.timeout))
    }

    /// Repli : lit la réponse d'usage que l'app a obtenue depuis une page web.
    pub fn claude_state_from_web_response(&self, response: HttpResponse) -> AiState {
        self.state_from(claude_web::parse_usage(&response))
    }
}

impl AiMonitor {
    /// Permet aux tests de viser un serveur local pour l'API de Claude Code.
    pub fn with_endpoint(endpoint: &str, timeout: Duration) -> Arc<Self> {
        Self::with_endpoints(endpoint, claude_web::BASE_URL, timeout)
    }

    /// Permet aux tests de viser des serveurs locaux.
    pub fn with_endpoints(endpoint: &str, web_base_url: &str, timeout: Duration) -> Arc<Self> {
        Arc::new(Self {
            endpoint: endpoint.to_string(),
            web_base_url: web_base_url.to_string(),
            timeout,
            last_claude: Mutex::new(None),
        })
    }

    fn state_from(&self, result: Result<AiUsage, FetchError>) -> AiState {
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
