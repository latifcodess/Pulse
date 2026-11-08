//! Point d'entrée du cœur Rust pour l'app Swift.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex, PoisonError};
use std::time::Duration;

use time::OffsetDateTime;

use crate::chatgpt;
use crate::claude::{self, fetch_claude_usage};
use crate::claude_web;
use crate::copilot::{self, TokenError};
use crate::http::{FetchError, HttpResponse};
use crate::model::{AiService, AiState, AiUsage};

/// Adresses et dossiers utilisés. Les tests les remplacent par des serveurs
/// et des dossiers locaux.
#[derive(Debug, Clone)]
pub struct MonitorConfig {
    pub claude_usage_url: String,
    pub claude_web_base_url: String,
    pub chatgpt_usage_url: String,
    pub codex_dir: Option<PathBuf>,
    pub copilot_usage_url: String,
    pub gh_paths: Vec<PathBuf>,
    pub gh_timeout: Duration,
    pub timeout: Duration,
}

impl MonitorConfig {
    pub fn production() -> Self {
        Self {
            claude_usage_url: claude::USAGE_URL.to_string(),
            claude_web_base_url: claude_web::BASE_URL.to_string(),
            chatgpt_usage_url: chatgpt::USAGE_URL.to_string(),
            codex_dir: chatgpt::default_codex_dir(),
            copilot_usage_url: copilot::USAGE_URL.to_string(),
            gh_paths: copilot::GH_PATHS.iter().map(PathBuf::from).collect(),
            gh_timeout: Duration::from_secs(10),
            timeout: Duration::from_secs(10),
        }
    }
}

#[derive(uniffi::Object)]
pub struct AiMonitor {
    config: MonitorConfig,
    /// Dernière réponse valide de chaque service, réaffichée sans réseau.
    last: Mutex<HashMap<AiService, AiUsage>>,
    /// Token de GitHub, gardé en mémoire seulement, pour ne pas relancer gh à
    /// chaque actualisation.
    copilot_token: Mutex<Option<String>>,
}

/// Pourquoi l'usage de Copilot n'a pas pu être récupéré.
enum CopilotError {
    Token(TokenError),
    Fetch(FetchError),
}

#[uniffi::export]
impl AiMonitor {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Self::with_config(MonitorConfig::production())
    }

    /// Usage de Claude avec le token de Claude Code. Appel bloquant, jusqu'à
    /// 10 s par requête. Le token n'est jamais conservé.
    pub fn refresh_claude(&self, access_token: String) -> AiState {
        let result = fetch_claude_usage(&self.config.claude_usage_url, &access_token, self.config.timeout);
        self.state_from(AiService::Claude, result)
    }

    /// Usage de Claude avec le cookie du compte claude.ai. Appel bloquant, deux
    /// requêtes. Le cookie n'est jamais conservé.
    pub fn refresh_claude_web(&self, session_key: String) -> AiState {
        let result = claude_web::fetch_usage(&self.config.claude_web_base_url, &session_key, self.config.timeout);
        self.state_from(AiService::Claude, result)
    }

    /// Repli : lit la réponse d'usage que l'app a obtenue depuis une page web.
    pub fn claude_state_from_web_response(&self, response: HttpResponse) -> AiState {
        self.state_from(AiService::Claude, claude_web::parse_usage(&response))
    }

    /// Usage de ChatGPT avec le compte de Codex CLI. Appel bloquant. Si le token
    /// a expiré, se replie sur les fichiers de session de Codex.
    pub fn refresh_chatgpt(&self) -> AiState {
        let Some(codex_dir) = &self.config.codex_dir else {
            return AiState::NotConnected;
        };
        let Some(auth) = chatgpt::read_auth(codex_dir) else {
            return AiState::NotConnected;
        };

        let now = OffsetDateTime::now_utc().unix_timestamp();
        let result = match chatgpt::fetch_usage(&self.config.chatgpt_usage_url, &auth, self.config.timeout, now) {
            Err(FetchError::Expired) => chatgpt::latest_session_usage(codex_dir).ok_or(FetchError::Expired),
            other => other,
        };
        self.state_from(AiService::ChatGpt, result)
    }

    /// Usage de Copilot avec le token de gh. Appel bloquant.
    pub fn refresh_copilot(&self) -> AiState {
        let mut result = self.fetch_copilot(false);
        if matches!(result, Err(CopilotError::Fetch(FetchError::Expired))) {
            // Le token gardé en mémoire a pu être remplacé : on le redemande à gh.
            result = self.fetch_copilot(true);
        }
        match result {
            Ok(usage) => self.state_from(AiService::Copilot, Ok(usage)),
            Err(CopilotError::Fetch(error)) => self.state_from(AiService::Copilot, Err(error)),
            Err(CopilotError::Token(TokenError::Failed)) => AiState::Unavailable,
            Err(CopilotError::Token(_)) => AiState::NotConnected,
        }
    }
}

impl AiMonitor {
    pub fn with_config(config: MonitorConfig) -> Arc<Self> {
        Arc::new(Self {
            config,
            last: Mutex::new(HashMap::new()),
            copilot_token: Mutex::new(None),
        })
    }

    /// Permet aux tests de viser un serveur local pour l'API de Claude Code.
    pub fn with_endpoint(endpoint: &str, timeout: Duration) -> Arc<Self> {
        Self::with_config(MonitorConfig {
            claude_usage_url: endpoint.to_string(),
            timeout,
            ..MonitorConfig::production()
        })
    }

    /// Permet aux tests de viser des serveurs locaux pour Claude.
    pub fn with_endpoints(endpoint: &str, web_base_url: &str, timeout: Duration) -> Arc<Self> {
        Self::with_config(MonitorConfig {
            claude_usage_url: endpoint.to_string(),
            claude_web_base_url: web_base_url.to_string(),
            timeout,
            ..MonitorConfig::production()
        })
    }

    fn fetch_copilot(&self, fresh_token: bool) -> Result<AiUsage, CopilotError> {
        let token = self.copilot_token(fresh_token).map_err(CopilotError::Token)?;
        copilot::fetch_usage(&self.config.copilot_usage_url, &token, self.config.timeout)
            .map_err(CopilotError::Fetch)
    }

    /// Le token en mémoire, ou un nouveau demandé à gh.
    fn copilot_token(&self, fresh: bool) -> Result<String, TokenError> {
        let mut cached = self.copilot_token.lock().unwrap_or_else(PoisonError::into_inner);
        if !fresh && let Some(token) = cached.as_ref() {
            return Ok(token.clone());
        }
        *cached = None;
        let token = copilot::gh_token(&self.config.gh_paths, self.config.gh_timeout)?;
        *cached = Some(token.clone());
        Ok(token)
    }

    fn state_from(&self, service: AiService, result: Result<AiUsage, FetchError>) -> AiState {
        let now = OffsetDateTime::now_utc().unix_timestamp();
        let mut last = self.last.lock().unwrap_or_else(PoisonError::into_inner);

        match result {
            Ok(usage) => {
                let current = usage.as_of(now);
                last.insert(service, usage);
                AiState::Ok(current)
            }
            Err(FetchError::Offline) => AiState::Offline(last.get(&service).map(|u| u.as_of(now))),
            Err(FetchError::Expired) => AiState::Expired,
            Err(FetchError::Blocked) => AiState::Blocked,
            Err(FetchError::Unavailable) => AiState::Unavailable,
        }
    }
}
