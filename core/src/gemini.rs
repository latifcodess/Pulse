//! Usage de Gemini, avec le compte de Gemini CLI (~/.gemini/oauth_creds.json).
//!
//! Le fichier est lu, jamais modifié : un token renouvelé reste en mémoire.

use std::fs::{self, File};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::{Duration, Instant};

use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use time::OffsetDateTime;
use time::format_description::well_known::Rfc3339;

use crate::claude::ParseError;
use crate::http::{self, FetchError};
use crate::model::{AiUsage, UsageWindow};

pub const TOKEN_URL: &str = "https://oauth2.googleapis.com/token";
pub const API_BASE_URL: &str = "https://cloudcode-pa.googleapis.com/v1internal";

// Identifiants OAuth publics de Gemini CLI, repris de son code source
// (packages/core/src/code_assist/oauth2.ts). Pour une application installée,
// Google indique que ce « secret » n'en est pas un : il est publié avec l'app.
const CLIENT_ID: &str = "681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j.apps.googleusercontent.com";
const CLIENT_SECRET: &str = "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";

/// Marge avant l'expiration : un token qui expire dans moins d'une minute est
/// renouvelé tout de suite.
const EXPIRY_MARGIN_SECONDS: i64 = 60;

/// Le contenu utile de oauth_creds.json.
#[derive(Debug, Clone, PartialEq)]
pub struct GeminiCreds {
    pub access_token: Option<String>,
    pub refresh_token: Option<String>,
    /// Expiration de access_token, en secondes Unix.
    pub expires_at: Option<i64>,
}

impl GeminiCreds {
    /// Le token du fichier, s'il est encore valable. Sans date d'expiration,
    /// on l'essaie quand même : l'API dira s'il est refusé.
    pub fn valid_access_token(&self, now: i64) -> Option<&str> {
        let token = self.access_token.as_deref()?;
        match self.expires_at {
            Some(expires_at) if expires_at <= now + EXPIRY_MARGIN_SECONDS => None,
            _ => Some(token),
        }
    }
}

/// Un token obtenu auprès de Google, gardé en mémoire seulement.
#[derive(Debug, Clone, PartialEq)]
pub struct AccessToken {
    pub token: String,
    /// En secondes Unix.
    pub expires_at: i64,
}

impl AccessToken {
    pub fn is_valid(&self, now: i64) -> bool {
        self.expires_at > now + EXPIRY_MARGIN_SECONDS
    }
}

/// ~/.gemini, le dossier de Gemini CLI.
pub fn default_gemini_dir() -> Option<PathBuf> {
    std::env::var_os("HOME").map(|home| Path::new(&home).join(".gemini"))
}

/// Lit oauth_creds.json, en lecture seule. None : Gemini CLI n'est pas connecté.
pub fn read_creds(gemini_dir: &Path) -> Option<GeminiCreds> {
    parse_creds(&fs::read_to_string(gemini_dir.join("oauth_creds.json")).ok()?)
}

pub fn parse_creds(json: &str) -> Option<GeminiCreds> {
    let root: Value = serde_json::from_str(json).ok()?;
    let text = |key: &str| {
        root.get(key)
            .and_then(Value::as_str)
            .filter(|value| !value.is_empty())
            .map(str::to_string)
    };
    let creds = GeminiCreds {
        access_token: text("access_token"),
        refresh_token: text("refresh_token"),
        // expiry_date est en millisecondes.
        expires_at: root.get("expiry_date").and_then(Value::as_f64).map(|ms| (ms / 1000.0) as i64),
    };
    if creds.access_token.is_none() && creds.refresh_token.is_none() {
        return None;
    }
    Some(creds)
}

/// Demande un nouveau token d'accès à Google. Appel bloquant.
pub fn refresh_access_token(
    url: &str,
    refresh_token: &str,
    timeout: Duration,
    now: i64,
) -> Result<AccessToken, FetchError> {
    let body = http::form_encode(&[
        ("client_id", CLIENT_ID),
        ("client_secret", CLIENT_SECRET),
        ("refresh_token", refresh_token),
        ("grant_type", "refresh_token"),
    ]);
    let headers = [
        ("Content-Type", "application/x-www-form-urlencoded"),
        ("Accept", "application/json"),
    ];
    let response = http::post(url, &headers, &body, timeout)?;

    match response.status {
        200 => parse_token_response(&response.body, now).ok_or(FetchError::Unavailable),
        // invalid_grant : le compte a été déconnecté ou le token révoqué.
        400 | 401 => Err(FetchError::Expired),
        429 => Err(FetchError::Blocked),
        _ => Err(FetchError::Unavailable),
    }
}

fn parse_token_response(json: &str, now: i64) -> Option<AccessToken> {
    let root: Value = serde_json::from_str(json).ok()?;
    let token = root.get("access_token")?.as_str().filter(|token| !token.is_empty())?;
    // Google donne une durée de validité ; une heure si elle manque.
    let expires_in = root.get("expires_in").and_then(Value::as_i64).unwrap_or(3600);
    Some(AccessToken {
        token: token.to_string(),
        expires_at: now + expires_in,
    })
}

/// Le projet Google associé au compte, nécessaire pour lire les quotas.
pub fn load_project(base_url: &str, token: &str, timeout: Duration) -> Result<String, FetchError> {
    // Mêmes métadonnées que Gemini CLI.
    let body = json!({
        "metadata": {
            "ideType": "IDE_UNSPECIFIED",
            "platform": "PLATFORM_UNSPECIFIED",
            "pluginType": "GEMINI",
        }
    });
    let response = post_json(&format!("{base_url}:loadCodeAssist"), token, &body, timeout)?;
    let root: Value = serde_json::from_str(&response).map_err(|_| FetchError::Unavailable)?;
    parse_project(&root).ok_or(FetchError::Unavailable)
}

/// cloudaicompanionProject est une chaîne, ou parfois un objet avec un « id ».
fn parse_project(root: &Value) -> Option<String> {
    let project = root.get("cloudaicompanionProject")?;
    let id = project.as_str().or_else(|| project.get("id")?.as_str())?;
    (!id.is_empty()).then(|| id.to_string())
}

/// Les quotas du compte, une limite par modèle.
pub fn fetch_quota(base_url: &str, token: &str, project: &str, timeout: Duration) -> Result<AiUsage, FetchError> {
    let body = json!({ "project": project });
    let response = post_json(&format!("{base_url}:retrieveUserQuota"), token, &body, timeout)?;
    parse_gemini_quota(&response).map_err(|_| FetchError::Unavailable)
}

fn post_json(url: &str, token: &str, body: &Value, timeout: Duration) -> Result<String, FetchError> {
    let authorization = format!("Bearer {token}");
    let headers = [
        ("Authorization", authorization.as_str()),
        ("Content-Type", "application/json"),
        ("Accept", "application/json"),
    ];
    let response = http::post(url, &headers, &body.to_string(), timeout)?;
    match response.status {
        200 => Ok(response.body),
        401 | 403 => Err(FetchError::Expired),
        429 => Err(FetchError::Blocked),
        _ => Err(FetchError::Unavailable),
    }
}

/// Lit buckets[] : utilisé = (1 − remainingFraction) × 100. Si un modèle
/// apparaît plusieurs fois, on garde la limite la plus entamée.
pub fn parse_gemini_quota(json: &str) -> Result<AiUsage, ParseError> {
    let root: Value = match serde_json::from_str(json) {
        Ok(value) => value,
        Err(_) => return Err(ParseError::InvalidJson),
    };
    let buckets = root.get("buckets").and_then(Value::as_array).map(Vec::as_slice).unwrap_or_default();

    let mut models: Vec<(String, UsageWindow)> = Vec::new();
    for bucket in buckets {
        let Some(model_id) = bucket.get("modelId").and_then(Value::as_str).filter(|id| !id.is_empty()) else {
            continue;
        };
        let Some(remaining) = bucket.get("remainingFraction").and_then(Value::as_f64) else {
            continue;
        };
        let window = UsageWindow {
            label: model_label(model_id),
            percent: ((1.0 - remaining) * 100.0).clamp(0.0, 100.0),
            resets_at: bucket
                .get("resetTime")
                .and_then(Value::as_str)
                .and_then(|text| OffsetDateTime::parse(text, &Rfc3339).ok())
                .map(|date| date.unix_timestamp()),
            projected_full_at: None,
        };
        match models.iter_mut().find(|(id, _)| id == model_id) {
            Some((_, existing)) if existing.percent < window.percent => *existing = window,
            Some(_) => {}
            None => models.push((model_id.to_string(), window)),
        }
    }

    if models.is_empty() {
        return Err(ParseError::NoUsableData);
    }
    Ok(AiUsage {
        windows: models.into_iter().map(|(_, window)| window).collect(),
    })
}

/// « gemini-2.5-flash-lite » → « 2.5 Flash Lite ».
pub fn model_label(model_id: &str) -> String {
    let name = model_id.strip_prefix("gemini-").unwrap_or(model_id);
    let label = name
        .split(['-', '_'])
        .filter(|word| !word.is_empty())
        .map(capitalize)
        .collect::<Vec<_>>()
        .join(" ");
    if label.is_empty() { model_id.to_string() } else { label }
}

fn capitalize(word: &str) -> String {
    let mut chars = word.chars();
    match chars.next() {
        Some(first) => first.to_uppercase().chain(chars).collect(),
        None => String::new(),
    }
}

// --- Connexion au compte Google dans Pulse ---
//
// Google refuse les connexions dans une fenêtre web intégrée : on ouvre la
// page de connexion dans le navigateur, et Pulse attend la réponse sur une
// adresse locale (127.0.0.1), comme Gemini CLI. Le refresh_token obtenu est
// rangé dans le Trousseau par l'app.

pub const AUTH_URL: &str = "https://accounts.google.com/o/oauth2/v2/auth";

/// Les mêmes autorisations que Gemini CLI.
const SCOPES: &str = "https://www.googleapis.com/auth/cloud-platform \
    https://www.googleapis.com/auth/userinfo.email \
    https://www.googleapis.com/auth/userinfo.profile";

#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum GeminiLoginResult {
    Success { refresh_token: String },
    /// L'utilisateur a refusé sur la page de Google.
    Denied,
    /// Pas de réponse dans le délai, ou connexion annulée dans Pulse.
    Cancelled,
    /// Réponse invalide, ou échange du code refusé.
    Failed,
}

/// Une connexion en cours : une adresse locale qui attend la réponse de Google.
#[derive(uniffi::Object)]
pub struct GeminiLogin {
    listener: TcpListener,
    verifier: String,
    state: String,
    redirect_uri: String,
    authorization_url: String,
    token_url: String,
    cancelled: AtomicBool,
}

/// Prépare une connexion. None si aucune adresse locale n'a pu être ouverte.
#[uniffi::export]
pub fn gemini_login_start() -> Option<Arc<GeminiLogin>> {
    GeminiLogin::start(AUTH_URL, TOKEN_URL)
}

impl GeminiLogin {
    pub fn start(auth_url: &str, token_url: &str) -> Option<Arc<Self>> {
        let listener = TcpListener::bind("127.0.0.1:0").ok()?;
        listener.set_nonblocking(true).ok()?;
        let port = listener.local_addr().ok()?.port();
        let redirect_uri = format!("http://127.0.0.1:{port}/oauth2callback");
        // PKCE : seul ce programme connaît `verifier`, dont Google ne reçoit
        // que l'empreinte. Un code intercepté ne sert donc à rien.
        let verifier = base64_url(&random_bytes(32)?);
        let challenge = base64_url(&Sha256::digest(verifier.as_bytes()));
        let state = base64_url(&random_bytes(16)?);
        let query = http::form_encode(&[
            ("client_id", CLIENT_ID),
            ("redirect_uri", &redirect_uri),
            ("response_type", "code"),
            ("scope", SCOPES),
            ("access_type", "offline"),
            // Toujours afficher le consentement : sinon Google ne redonne pas de refresh_token.
            ("prompt", "consent"),
            ("code_challenge", &challenge),
            ("code_challenge_method", "S256"),
            ("state", &state),
        ]);
        Some(Arc::new(Self {
            listener,
            verifier,
            state,
            redirect_uri,
            authorization_url: format!("{auth_url}?{query}"),
            token_url: token_url.to_string(),
            cancelled: AtomicBool::new(false),
        }))
    }
}

#[uniffi::export]
impl GeminiLogin {
    /// La page de connexion Google, à ouvrir dans le navigateur.
    pub fn authorization_url(&self) -> String {
        self.authorization_url.clone()
    }

    /// Arrête l'attente (fenêtre fermée par l'utilisateur).
    pub fn cancel(&self) {
        self.cancelled.store(true, Ordering::Relaxed);
    }

    /// Attend la réponse de Google, puis échange le code contre un
    /// refresh_token. Appel bloquant, jusqu'à `timeout_seconds`.
    pub fn wait(&self, timeout_seconds: u32) -> GeminiLoginResult {
        let deadline = Instant::now() + Duration::from_secs(u64::from(timeout_seconds));
        while Instant::now() < deadline && !self.cancelled.load(Ordering::Relaxed) {
            let Ok((stream, _)) = self.listener.accept() else {
                thread::sleep(Duration::from_millis(100));
                continue;
            };
            if let Some(result) = self.handle(stream) {
                return result;
            }
        }
        GeminiLoginResult::Cancelled
    }
}

impl GeminiLogin {
    /// Traite une requête reçue sur l'adresse locale. None : ce n'était pas la
    /// réponse de Google (par ex. une demande d'icône du navigateur).
    fn handle(&self, mut stream: TcpStream) -> Option<GeminiLoginResult> {
        let _ = stream.set_nonblocking(false);
        let _ = stream.set_read_timeout(Some(Duration::from_secs(5)));
        let mut buffer = [0; 8192];
        let count = stream.read(&mut buffer).ok()?;
        let request = String::from_utf8_lossy(&buffer[..count]);
        let target = request.lines().next()?.split_whitespace().nth(1)?.to_string();

        let Some(query) = target.strip_prefix("/oauth2callback?") else {
            respond(&mut stream, "404 Not Found", "");
            return None;
        };
        let params = parse_query(query);
        let param = |key: &str| params.iter().find(|(name, _)| name == key).map(|(_, value)| value.as_str());

        // Une réponse qui ne vient pas de notre demande est refusée.
        if param("state") != Some(self.state.as_str()) {
            respond(&mut stream, "400 Bad Request", "La connexion n'a pas pu être vérifiée. Recommencez depuis Pulse.");
            return Some(GeminiLoginResult::Failed);
        }
        if param("error").is_some() {
            respond(&mut stream, "200 OK", "Connexion annulée. Vous pouvez fermer cet onglet.");
            return Some(GeminiLoginResult::Denied);
        }
        let Some(code) = param("code") else {
            respond(&mut stream, "400 Bad Request", "Réponse de Google incomplète. Recommencez depuis Pulse.");
            return Some(GeminiLoginResult::Failed);
        };

        let result = self.exchange(code);
        let message = match result {
            GeminiLoginResult::Success { .. } => "Pulse est connecté à votre compte Google. Vous pouvez fermer cet onglet.",
            _ => "La connexion a échoué. Recommencez depuis Pulse.",
        };
        respond(&mut stream, "200 OK", message);
        Some(result)
    }

    fn exchange(&self, code: &str) -> GeminiLoginResult {
        let body = http::form_encode(&[
            ("code", code),
            ("client_id", CLIENT_ID),
            ("client_secret", CLIENT_SECRET),
            ("redirect_uri", &self.redirect_uri),
            ("grant_type", "authorization_code"),
            ("code_verifier", &self.verifier),
        ]);
        let headers = [
            ("Content-Type", "application/x-www-form-urlencoded"),
            ("Accept", "application/json"),
        ];
        let Ok(response) = http::post(&self.token_url, &headers, &body, Duration::from_secs(15)) else {
            return GeminiLoginResult::Failed;
        };
        let refresh_token = serde_json::from_str::<Value>(&response.body)
            .ok()
            .filter(|_| response.status == 200)
            .and_then(|root| root.get("refresh_token")?.as_str().map(str::to_string))
            .filter(|token| !token.is_empty());
        match refresh_token {
            Some(refresh_token) => GeminiLoginResult::Success { refresh_token },
            None => GeminiLoginResult::Failed,
        }
    }
}

/// Répond au navigateur avec une petite page en français.
fn respond(stream: &mut TcpStream, status: &str, message: &str) {
    let body = format!(
        "<!doctype html><meta charset=\"utf-8\"><title>Pulse</title>\
         <body style=\"font-family:-apple-system,sans-serif;text-align:center;margin-top:20vh\">\
         <h1>Pulse</h1><p>{message}</p></body>"
    );
    let reply = format!(
        "HTTP/1.1 {status}\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    let _ = stream.write_all(reply.as_bytes());
}

/// « a=1&b=x%20y » → [("a", "1"), ("b", "x y")].
pub fn parse_query(query: &str) -> Vec<(String, String)> {
    query
        .split('&')
        .filter(|pair| !pair.is_empty())
        .map(|pair| {
            let (key, value) = pair.split_once('=').unwrap_or((pair, ""));
            (percent_decode(key), percent_decode(value))
        })
        .collect()
}

fn percent_decode(text: &str) -> String {
    let hex = |byte: u8| (byte as char).to_digit(16);
    let bytes = text.as_bytes();
    let mut decoded = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        let byte = bytes[index];
        // On lit les octets un par un : aucun risque de couper un caractère accentué.
        match (byte, bytes.get(index + 1).copied().and_then(hex), bytes.get(index + 2).copied().and_then(hex)) {
            (b'%', Some(high), Some(low)) => {
                decoded.push((high * 16 + low) as u8);
                index += 3;
            }
            (b'+', _, _) => {
                decoded.push(b' ');
                index += 1;
            }
            _ => {
                decoded.push(byte);
                index += 1;
            }
        }
    }
    String::from_utf8_lossy(&decoded).into_owned()
}

/// Des octets aléatoires fournis par macOS.
fn random_bytes(count: usize) -> Option<Vec<u8>> {
    let mut bytes = vec![0; count];
    File::open("/dev/urandom").ok()?.read_exact(&mut bytes).ok()?;
    Some(bytes)
}

/// Base64 « URL » sans « = » final (RFC 4648 §5), utilisé par PKCE.
pub fn base64_url(bytes: &[u8]) -> String {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    let mut output = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let value = chunk.iter().enumerate().fold(0u32, |acc, (i, byte)| acc | u32::from(*byte) << (16 - 8 * i));
        for position in 0..=chunk.len() {
            output.push(ALPHABET[(value >> (18 - 6 * position) & 0x3f) as usize] as char);
        }
    }
    output
}
