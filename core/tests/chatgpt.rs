use std::fs;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::thread::{self, JoinHandle};
use std::time::{Duration, SystemTime};

use pulse_core::chatgpt::{
    latest_session_usage, parse_auth, parse_chatgpt_usage, parse_session_line, window_label,
};
use pulse_core::claude::ParseError;
use pulse_core::model::{AiState, AiUsage};
use pulse_core::monitor::{AiMonitor, MonitorConfig};

const NOW: i64 = 1_793_000_000;
const FIXTURE: &str = include_str!("fixtures/chatgpt.json");

fn fixture_codex_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/codex")
}

/// Dossier temporaire propre à un test.
fn temp_dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("pulse-test-{}-{name}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).unwrap();
    dir
}

fn percents(usage: &AiUsage) -> Vec<f64> {
    usage.windows.iter().map(|w| w.percent).collect()
}

// --- Réponse de l'API ---

#[test]
fn cas_normal_donne_session_et_semaine() {
    let usage = parse_chatgpt_usage(FIXTURE, NOW).unwrap();

    assert_eq!(usage.windows.len(), 2);
    assert_eq!(usage.windows[0].label, "Session (5 h)");
    assert_eq!(usage.windows[0].percent, 42.0);
    // reset_at est prioritaire sur reset_after_seconds.
    assert_eq!(usage.windows[0].resets_at, Some(1_794_100_000));

    assert_eq!(usage.windows[1].label, "Semaine");
    assert_eq!(usage.windows[1].percent, 7.5);
    // Sans reset_at : maintenant + reset_after_seconds.
    assert_eq!(usage.windows[1].resets_at, Some(NOW + 86_400));
}

#[test]
fn champs_manquants() {
    // Pas de fenêtre secondaire, pas de durée, pas de reset.
    let usage = parse_chatgpt_usage(r#"{"rate_limit": {"primary_window": {"used_percent": 12}}}"#, NOW).unwrap();
    assert_eq!(usage.windows.len(), 1);
    assert_eq!(usage.windows[0].label, "Session");
    assert_eq!(usage.windows[0].resets_at, None);

    // Fenêtre sans pourcentage : ignorée.
    let json = r#"{"rate_limit": {"primary_window": {"reset_at": 1}, "secondary_window": {"used_percent": 3}}}"#;
    assert_eq!(percents(&parse_chatgpt_usage(json, NOW).unwrap()), vec![3.0]);

    for json in ["{}", r#"{"rate_limit": null}"#, r#"{"rate_limit": {"primary_window": null}}"#] {
        assert_eq!(parse_chatgpt_usage(json, NOW), Err(ParseError::NoUsableData));
    }
}

#[test]
fn json_invalide() {
    assert_eq!(parse_chatgpt_usage("pas du json", NOW), Err(ParseError::InvalidJson));
}

#[test]
fn noms_des_limites() {
    assert_eq!(window_label(Some(18_000), "x"), "Session (5 h)");
    assert_eq!(window_label(Some(604_800), "x"), "Semaine");
    assert_eq!(window_label(Some(2_592_000), "x"), "30 jours");
    assert_eq!(window_label(Some(1_234), "x"), "x");
    assert_eq!(window_label(None, "x"), "x");
}

// --- auth.json ---

#[test]
fn auth_normal() {
    let auth = parse_auth(&fs::read_to_string(fixture_codex_dir().join("auth.json")).unwrap()).unwrap();
    assert_eq!(auth.access_token, "faux-access-token");
    assert_eq!(auth.account_id.as_deref(), Some("compte-test"));
}

#[test]
fn auth_incomplet() {
    let sans_compte = parse_auth(r#"{"tokens": {"access_token": "t"}}"#).unwrap();
    assert_eq!(sans_compte.account_id, None);

    for json in ["", "{}", r#"{"tokens": null}"#, r#"{"tokens": {"access_token": ""}}"#, r#"{"OPENAI_API_KEY": "sk"}"#] {
        assert_eq!(parse_auth(json), None, "json : {json}");
    }
}

// --- Fichiers de session ---

#[test]
fn ligne_de_session() {
    let line = r#"{"timestamp":"2026-11-01T10:00:00Z","payload":{"rate_limits":{"primary":{"used_percent":25.0,"window_minutes":300,"resets_at":2000},"secondary":{"used_percent":5,"window_minutes":10080,"resets_in_seconds":60}}}}"#;
    let usage = parse_session_line(line).unwrap();

    assert_eq!(usage.windows[0].label, "Session (5 h)");
    assert_eq!(usage.windows[0].resets_at, Some(2000));
    assert_eq!(usage.windows[1].label, "Semaine");
    // resets_in_seconds est compté depuis l'heure de la ligne (1 793 527 200).
    assert_eq!(usage.windows[1].resets_at, Some(1_793_527_200 + 60));

    assert_eq!(parse_session_line(r#"{"payload":{"rate_limits":null}}"#), None);
    assert_eq!(parse_session_line("pas du json"), None);
}

#[test]
fn derniere_ligne_rate_limits() {
    let usage = latest_session_usage(&fixture_codex_dir()).unwrap();
    assert_eq!(percents(&usage), vec![25.0, 5.0]);
}

#[test]
fn fichier_le_plus_recent_d_abord() {
    let dir = temp_dir("recent");
    let sessions = dir.join("sessions/2026/11/02");
    fs::create_dir_all(&sessions).unwrap();
    let line = |percent: f64| {
        format!(r#"{{"payload":{{"rate_limits":{{"primary":{{"used_percent":{percent},"window_minutes":300}}}}}}}}"#)
    };
    // Le nom « z » est trié après « a », mais c'est le fichier le plus ancien.
    fs::write(sessions.join("z-ancien.jsonl"), line(11.0)).unwrap();
    fs::write(sessions.join("a-recent.jsonl"), line(22.0)).unwrap();
    let old = SystemTime::now() - Duration::from_secs(3600);
    fs::File::options().write(true).open(sessions.join("z-ancien.jsonl")).unwrap().set_modified(old).unwrap();

    assert_eq!(percents(&latest_session_usage(&dir).unwrap()), vec![22.0]);
    assert_eq!(latest_session_usage(&temp_dir("vide")), None);
    let _ = fs::remove_dir_all(dir);
}

// --- Flux complet contre un serveur local ---

fn serve_once(status: &'static str, body: &'static str) -> (String, JoinHandle<String>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}/backend-api/wham/usage", listener.local_addr().unwrap());
    let handle = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let mut request = Vec::new();
        let mut buffer = [0; 1024];
        while !request.windows(4).any(|end| end == b"\r\n\r\n") {
            let count = stream.read(&mut buffer).unwrap();
            request.extend_from_slice(&buffer[..count]);
        }
        let reply = format!(
            "HTTP/1.1 {status}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
            body.len()
        );
        stream.write_all(reply.as_bytes()).unwrap();
        String::from_utf8(request).unwrap()
    });
    (url, handle)
}

fn monitor(url: &str, codex_dir: PathBuf) -> std::sync::Arc<AiMonitor> {
    AiMonitor::with_config(MonitorConfig {
        chatgpt_usage_url: url.to_string(),
        codex_dir: Some(codex_dir),
        timeout: Duration::from_secs(5),
        ..MonitorConfig::production()
    })
}

#[test]
fn reponse_200_et_en_tetes() {
    let (url, handle) = serve_once("200 OK", FIXTURE);
    let state = monitor(&url, fixture_codex_dir()).refresh_chatgpt();
    let request = handle.join().unwrap().to_lowercase();

    let AiState::Ok(usage) = state else {
        panic!("attendu : Ok, obtenu : {state:?}");
    };
    assert_eq!(usage.windows[0].label, "Session (5 h)");
    assert!(request.starts_with("get /backend-api/wham/usage "));
    assert!(request.contains("authorization: bearer faux-access-token\r\n"));
    assert!(request.contains("chatgpt-account-id: compte-test\r\n"));
    assert!(request.contains("user-agent: codex-cli\r\n"));
}

#[test]
fn token_expire_repli_sur_les_sessions() {
    let (url, handle) = serve_once("401 Unauthorized", "{}");
    let state = monitor(&url, fixture_codex_dir()).refresh_chatgpt();
    handle.join().unwrap();

    let AiState::Ok(usage) = state else {
        panic!("attendu : Ok depuis les sessions, obtenu : {state:?}");
    };
    assert_eq!(percents(&usage), vec![25.0, 5.0]);
}

#[test]
fn token_expire_sans_session_donne_expired() {
    let dir = temp_dir("sans-session");
    fs::copy(fixture_codex_dir().join("auth.json"), dir.join("auth.json")).unwrap();

    let (url, handle) = serve_once("403 Forbidden", "{}");
    assert_eq!(monitor(&url, dir.clone()).refresh_chatgpt(), AiState::Expired);
    handle.join().unwrap();
    let _ = fs::remove_dir_all(dir);
}

#[test]
fn sans_auth_json_donne_not_connected() {
    let state = monitor("http://127.0.0.1:1/", temp_dir("sans-auth")).refresh_chatgpt();
    assert_eq!(state, AiState::NotConnected);
}

#[test]
fn pas_de_reseau_donne_offline() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}/", listener.local_addr().unwrap());
    drop(listener);

    assert_eq!(monitor(&url, fixture_codex_dir()).refresh_chatgpt(), AiState::Offline(None));
}
