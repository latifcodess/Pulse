use std::fs;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use std::time::Duration;

use pulse_core::claude::ParseError;
use pulse_core::gemini::{GeminiCreds, model_label, parse_creds, parse_gemini_quota, read_creds};
use pulse_core::model::{AiState, AiUsage};
use pulse_core::monitor::{AiMonitor, MonitorConfig};

const QUOTA: &str = include_str!("fixtures/gemini.json");
const CREDS_EXPIRED: &str = include_str!("fixtures/gemini/oauth_creds.json");
const RESET_2026_11_09: i64 = 1_794_182_400;
const RESET_2026_11_08_1830: i64 = 1_794_162_600;
const PROJECT: &str = r#"{"currentTier": {"id": "free-tier"}, "cloudaicompanionProject": "projet-test-123"}"#;
const TOKEN: &str = r#"{"access_token": "ya29.token-renouvele", "expires_in": 3599, "token_type": "Bearer"}"#;

fn temp_dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("pulse-gemini-{}-{name}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).unwrap();
    dir
}

/// Un dossier ~/.gemini avec ce oauth_creds.json.
fn gemini_dir(name: &str, creds: &str) -> PathBuf {
    let dir = temp_dir(name);
    fs::write(dir.join("oauth_creds.json"), creds).unwrap();
    dir
}

/// Identifiants dont le token du fichier est encore valable (expire en 2100).
fn valid_creds() -> String {
    CREDS_EXPIRED.replace("1700000000000", "4102444800000")
}

fn percents(usage: &AiUsage) -> Vec<f64> {
    usage.windows.iter().map(|w| w.percent).collect()
}

// --- Réponse de retrieveUserQuota ---

#[test]
fn cas_normal_une_limite_par_modele() {
    let usage = parse_gemini_quota(QUOTA).unwrap();
    let labels: Vec<&str> = usage.windows.iter().map(|w| w.label.as_str()).collect();

    // gemini-2.5-pro apparaît deux fois : on garde la limite la plus entamée.
    assert_eq!(labels, vec!["2.5 Pro", "2.5 Flash", "2.5 Flash Lite"]);
    let rounded: Vec<f64> = percents(&usage).iter().map(|p| (p * 10.0).round() / 10.0).collect();
    assert_eq!(rounded, vec![75.0, 10.0, 0.0]);
    assert_eq!(usage.windows[0].resets_at, Some(RESET_2026_11_09));
    assert_eq!(usage.windows[1].resets_at, Some(RESET_2026_11_08_1830));
}

#[test]
fn champs_manquants() {
    // Pas de date de reset : la limite est gardée, sans heure.
    let usage = parse_gemini_quota(r#"{"buckets": [{"modelId": "gemini-2.5-pro", "remainingFraction": 0.5}]}"#).unwrap();
    assert_eq!(percents(&usage), vec![50.0]);
    assert_eq!(usage.windows[0].resets_at, None);

    // Bucket sans modèle ou sans fraction : ignoré. Date illisible : sans heure.
    let json = r#"{"buckets": [
        {"remainingFraction": 0.1},
        {"modelId": "gemini-2.5-flash"},
        {"modelId": "gemini-2.5-pro", "remainingFraction": 0.8, "resetTime": "demain"}
    ]}"#;
    let usage = parse_gemini_quota(json).unwrap();
    assert_eq!(usage.windows.len(), 1);
    assert_eq!(usage.windows[0].resets_at, None);
}

#[test]
fn pas_de_bucket_donne_no_usable_data() {
    for json in ["{}", r#"{"buckets": []}"#, r#"{"buckets": null}"#, r#"{"buckets": [{}]}"#] {
        assert_eq!(parse_gemini_quota(json), Err(ParseError::NoUsableData));
    }
}

#[test]
fn json_invalide() {
    assert_eq!(parse_gemini_quota("<html>"), Err(ParseError::InvalidJson));
}

#[test]
fn libelles_des_modeles() {
    assert_eq!(model_label("gemini-2.5-pro"), "2.5 Pro");
    assert_eq!(model_label("gemini-3-pro-preview"), "3 Pro Preview");
    assert_eq!(model_label("gemini-2.0-flash_vertex"), "2.0 Flash Vertex");
    assert_eq!(model_label("autre-modele"), "Autre Modele");
    assert_eq!(model_label("gemini-"), "gemini-");
}

// --- oauth_creds.json ---

#[test]
fn identifiants_lus() {
    let creds = parse_creds(CREDS_EXPIRED).unwrap();
    assert_eq!(
        creds,
        GeminiCreds {
            access_token: Some("ya29.faux-token-du-fichier".to_string()),
            refresh_token: Some("1//faux-refresh+token/test".to_string()),
            expires_at: Some(1_700_000_000),
        }
    );
    // Expiré en 2023.
    assert_eq!(creds.valid_access_token(1_794_000_000), None);
    assert!(parse_creds(&valid_creds()).unwrap().valid_access_token(1_794_000_000).is_some());
}

#[test]
fn identifiants_incomplets() {
    // Un seul des deux tokens suffit ; aucun, ou pas du JSON : non connecté.
    assert!(parse_creds(r#"{"refresh_token": "r"}"#).is_some());
    assert_eq!(parse_creds(r#"{"access_token": "a"}"#).unwrap().expires_at, None);
    assert_eq!(parse_creds(r#"{"access_token": "", "scope": "x"}"#), None);
    assert_eq!(parse_creds("pas du json"), None);
    assert_eq!(read_creds(&temp_dir("vide")), None);
}

// --- Flux complet contre un serveur local ---

struct Request {
    head: String,
    body: String,
}

impl Request {
    fn line(&self) -> String {
        self.head.lines().next().unwrap_or_default().to_lowercase()
    }
    fn has_header(&self, header: &str) -> bool {
        self.head.to_lowercase().contains(&format!("\r\n{}\r\n", header.to_lowercase()))
    }
}

/// Serveur local qui sert ces réponses dans l'ordre, une par connexion, et
/// renvoie les requêtes reçues (en-têtes et corps).
fn serve(replies: Vec<(&'static str, &'static str)>) -> (String, JoinHandle<Vec<Request>>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let handle = thread::spawn(move || {
        replies
            .into_iter()
            .map(|(status, body)| {
                let (mut stream, _) = listener.accept().unwrap();
                let mut data = Vec::new();
                let mut buffer = [0; 4096];
                let head_end = loop {
                    if let Some(end) = data.windows(4).position(|w| w == b"\r\n\r\n") {
                        break end + 4;
                    }
                    let count = stream.read(&mut buffer).unwrap();
                    data.extend_from_slice(&buffer[..count]);
                };
                let head = String::from_utf8_lossy(&data[..head_end]).into_owned();
                let length = head
                    .lines()
                    .find_map(|line| line.to_lowercase().strip_prefix("content-length:").map(|v| v.trim().to_string()))
                    .and_then(|v| v.parse::<usize>().ok())
                    .unwrap_or(0);
                while data.len() < head_end + length {
                    let count = stream.read(&mut buffer).unwrap();
                    data.extend_from_slice(&buffer[..count]);
                }
                let reply = format!(
                    "HTTP/1.1 {status}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                    body.len()
                );
                stream.write_all(reply.as_bytes()).unwrap();
                Request {
                    head,
                    body: String::from_utf8_lossy(&data[head_end..]).into_owned(),
                }
            })
            .collect()
    });
    (url, handle)
}

fn monitor(url: &str, gemini_dir: &Path) -> Arc<AiMonitor> {
    AiMonitor::with_config(MonitorConfig {
        gemini_dir: Some(gemini_dir.to_path_buf()),
        google_token_url: format!("{url}/token"),
        gemini_api_base_url: format!("{url}/v1internal"),
        timeout: Duration::from_secs(5),
        ..MonitorConfig::production()
    })
}

#[test]
fn token_du_fichier_valable_projet_puis_quotas() {
    let dir = gemini_dir("valable", &valid_creds());
    let (url, handle) = serve(vec![("200 OK", PROJECT), ("200 OK", QUOTA)]);

    let AiState::Ok(usage) = monitor(&url, &dir).refresh_gemini() else {
        panic!("attendu : Ok");
    };
    assert_eq!(usage.windows.len(), 3);

    let requests = handle.join().unwrap();
    assert!(requests[0].line().starts_with("post /v1internal:loadcodeassist "));
    assert!(requests[0].has_header("authorization: Bearer ya29.faux-token-du-fichier"));
    assert!(requests[0].body.contains(r#""pluginType":"GEMINI""#));
    assert!(requests[1].line().starts_with("post /v1internal:retrieveuserquota "));
    assert_eq!(requests[1].body, r#"{"project":"projet-test-123"}"#);
}

#[test]
fn token_expire_renouvele_en_memoire_sans_toucher_au_fichier() {
    let dir = gemini_dir("expire", CREDS_EXPIRED);
    let (url, handle) = serve(vec![
        ("200 OK", TOKEN),
        ("200 OK", PROJECT),
        ("200 OK", QUOTA),
        // Deuxième actualisation : le token renouvelé est réutilisé.
        ("200 OK", PROJECT),
        ("200 OK", QUOTA),
    ]);
    let monitor = monitor(&url, &dir);

    assert!(matches!(monitor.refresh_gemini(), AiState::Ok(_)));
    assert!(matches!(monitor.refresh_gemini(), AiState::Ok(_)));

    let requests = handle.join().unwrap();
    let token_request = &requests[0];
    assert!(token_request.line().starts_with("post /token "));
    assert!(token_request.has_header("content-type: application/x-www-form-urlencoded"));
    let form = &token_request.body;
    assert!(form.contains("grant_type=refresh_token"));
    assert!(form.contains("refresh_token=1%2F%2Ffaux-refresh%2Btoken%2Ftest"));
    assert!(form.contains("client_id=681255809395-"));
    for request in &requests[1..] {
        assert!(request.has_header("authorization: Bearer ya29.token-renouvele"));
    }
    // Le fichier de Gemini CLI est intact.
    assert_eq!(fs::read_to_string(dir.join("oauth_creds.json")).unwrap(), CREDS_EXPIRED);
}

#[test]
fn token_du_fichier_refuse_renouvele_puis_reussit() {
    let dir = gemini_dir("refuse", &valid_creds());
    let (url, handle) = serve(vec![
        ("401 Unauthorized", "{}"),
        ("200 OK", TOKEN),
        ("200 OK", PROJECT),
        ("200 OK", QUOTA),
    ]);

    assert!(matches!(monitor(&url, &dir).refresh_gemini(), AiState::Ok(_)));
    let requests = handle.join().unwrap();
    assert!(requests[1].line().starts_with("post /token "));
}

#[test]
fn renouvellement_refuse_donne_expired() {
    let dir = gemini_dir("revoque", CREDS_EXPIRED);
    let (url, handle) = serve(vec![("400 Bad Request", r#"{"error": "invalid_grant"}"#)]);

    assert_eq!(monitor(&url, &dir).refresh_gemini(), AiState::Expired);
    handle.join().unwrap();
}

#[test]
fn token_expire_sans_refresh_token_donne_expired() {
    let dir = gemini_dir("sans-refresh", r#"{"access_token": "a", "expiry_date": 1700000000000}"#);
    assert_eq!(monitor("http://127.0.0.1:1", &dir).refresh_gemini(), AiState::Expired);
}

#[test]
fn sans_projet_donne_unavailable() {
    let dir = gemini_dir("sans-projet", &valid_creds());
    let (url, handle) = serve(vec![("200 OK", r#"{"currentTier": {"id": "free-tier"}}"#)]);

    assert_eq!(monitor(&url, &dir).refresh_gemini(), AiState::Unavailable);
    handle.join().unwrap();
}

#[test]
fn projet_sous_forme_d_objet() {
    let dir = gemini_dir("projet-objet", &valid_creds());
    let (url, handle) = serve(vec![("200 OK", r#"{"cloudaicompanionProject": {"id": "p-42"}}"#), ("200 OK", QUOTA)]);

    assert!(matches!(monitor(&url, &dir).refresh_gemini(), AiState::Ok(_)));
    assert_eq!(handle.join().unwrap()[1].body, r#"{"project":"p-42"}"#);
}

#[test]
fn quota_429_donne_blocked() {
    let dir = gemini_dir("429", &valid_creds());
    let (url, handle) = serve(vec![("200 OK", PROJECT), ("429 Too Many Requests", "{}")]);

    assert_eq!(monitor(&url, &dir).refresh_gemini(), AiState::Blocked);
    handle.join().unwrap();
}

#[test]
fn sans_fichier_donne_not_connected() {
    assert_eq!(monitor("http://127.0.0.1:1", &temp_dir("absent")).refresh_gemini(), AiState::NotConnected);
}

#[test]
fn pas_de_reseau_donne_offline() {
    let dir = gemini_dir("offline", &valid_creds());
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    drop(listener);

    assert_eq!(monitor(&url, &dir).refresh_gemini(), AiState::Offline(None));
}
