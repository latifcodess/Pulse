use std::fs;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use std::time::Duration;

use pulse_core::claude::ParseError;
use pulse_core::copilot::{TokenError, gh_token, parse_copilot_usage};
use pulse_core::model::{AiState, AiUsage};
use pulse_core::monitor::{AiMonitor, MonitorConfig};

const FIXTURE: &str = include_str!("fixtures/copilot.json");
const RESET_2026_12_01: i64 = 1_796_083_200;

/// Dossier temporaire propre à un test.
fn temp_dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("pulse-copilot-{}-{name}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).unwrap();
    dir
}

/// Un faux « gh » : un script qui note chaque appel dans le fichier « calls ».
fn fake_gh(dir: &Path, body: &str) -> PathBuf {
    let path = dir.join("gh");
    fs::write(&path, format!("#!/bin/sh\necho appel >> \"{}/calls\"\n{body}\n", dir.display())).unwrap();
    fs::set_permissions(&path, fs::Permissions::from_mode(0o755)).unwrap();
    path
}

fn gh_calls(dir: &Path) -> usize {
    fs::read_to_string(dir.join("calls")).map(|text| text.lines().count()).unwrap_or(0)
}

fn percents(usage: &AiUsage) -> Vec<f64> {
    usage.windows.iter().map(|w| w.percent).collect()
}

// --- Réponse de l'API ---

#[test]
fn cas_normal_ignore_les_quotas_illimites() {
    let usage = parse_copilot_usage(FIXTURE).unwrap();

    // « chat » est illimité : il n'apparaît pas.
    assert_eq!(usage.windows.len(), 2);
    assert_eq!(usage.windows[0].label, "Complétions");
    assert_eq!(usage.windows[0].percent, 37.5);
    assert_eq!(usage.windows[1].label, "Requêtes premium");
    assert_eq!(usage.windows[1].percent, 82.0);
    assert_eq!(usage.windows[0].resets_at, Some(RESET_2026_12_01));
}

#[test]
fn champs_manquants() {
    // Pas de date de reset, pas de champ « unlimited ».
    let usage = parse_copilot_usage(r#"{"quota_snapshots": {"chat": {"percent_remaining": 90}}}"#).unwrap();
    assert_eq!(percents(&usage), vec![10.0]);
    assert_eq!(usage.windows[0].resets_at, None);

    // Quota sans pourcentage : ignoré.
    let json = r#"{"quota_snapshots": {"chat": {"remaining": 3}, "completions": {"percent_remaining": 40}}}"#;
    assert_eq!(percents(&parse_copilot_usage(json).unwrap()), vec![60.0]);

    // Date seule, sans heure : minuit UTC.
    let json = r#"{"quota_reset_date": "2026-12-01", "quota_snapshots": {"chat": {"percent_remaining": 0}}}"#;
    assert_eq!(parse_copilot_usage(json).unwrap().windows[0].resets_at, Some(RESET_2026_12_01));
}

#[test]
fn tout_illimite_ou_vide_donne_no_usable_data() {
    let all_unlimited = r#"{"quota_snapshots": {
        "chat": {"percent_remaining": 100, "unlimited": true},
        "premium_interactions": {"percent_remaining": 100, "unlimited": true}
    }}"#;
    for json in [all_unlimited, "{}", r#"{"quota_snapshots": null}"#] {
        assert_eq!(parse_copilot_usage(json), Err(ParseError::NoUsableData));
    }
}

#[test]
fn json_invalide() {
    assert_eq!(parse_copilot_usage("pas du json"), Err(ParseError::InvalidJson));
}

// --- Token via gh ---

#[test]
fn token_lu_et_nettoye() {
    let dir = temp_dir("token");
    let gh = fake_gh(&dir, "echo '  tok-123  '");
    assert_eq!(gh_token(&[gh], Duration::from_secs(5)), Ok("tok-123".to_string()));
}

#[test]
fn premier_gh_executable_trouve() {
    let dir = temp_dir("chemins");
    let gh = fake_gh(&dir, "echo tok");
    let missing = dir.join("absent/gh");
    assert_eq!(gh_token(&[missing, gh], Duration::from_secs(5)), Ok("tok".to_string()));
}

#[test]
fn erreurs_de_gh() {
    let dir = temp_dir("erreurs");
    assert_eq!(gh_token(&[dir.join("absent")], Duration::from_secs(5)), Err(TokenError::NotInstalled));

    let not_logged_in = fake_gh(&temp_dir("deconnecte"), "echo 'not logged in' >&2; exit 1");
    assert_eq!(gh_token(&[not_logged_in], Duration::from_secs(5)), Err(TokenError::NotLoggedIn));

    let empty = fake_gh(&temp_dir("vide"), "exit 0");
    assert_eq!(gh_token(&[empty], Duration::from_secs(5)), Err(TokenError::NotLoggedIn));

    let slow = fake_gh(&temp_dir("lent"), "sleep 5; echo tok");
    assert_eq!(gh_token(&[slow], Duration::from_millis(200)), Err(TokenError::Failed));
}

// --- Flux complet contre un serveur local ---

/// Serveur local qui sert ces réponses dans l'ordre, une par connexion.
fn serve(replies: Vec<(&'static str, &'static str)>) -> (String, JoinHandle<Vec<String>>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}/copilot_internal/user", listener.local_addr().unwrap());
    let handle = thread::spawn(move || {
        replies
            .into_iter()
            .map(|(status, body)| {
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
            })
            .collect()
    });
    (url, handle)
}

fn monitor(url: &str, gh: PathBuf) -> Arc<AiMonitor> {
    AiMonitor::with_config(MonitorConfig {
        copilot_usage_url: url.to_string(),
        gh_paths: vec![gh],
        gh_timeout: Duration::from_secs(5),
        timeout: Duration::from_secs(5),
        ..MonitorConfig::production()
    })
}

#[test]
fn reponse_200_en_tetes_et_token_garde_en_memoire() {
    let dir = temp_dir("flux-ok");
    let (url, handle) = serve(vec![("200 OK", FIXTURE), ("200 OK", FIXTURE)]);
    let monitor = monitor(&url, fake_gh(&dir, "echo tok-123"));

    assert!(matches!(monitor.refresh_copilot(), AiState::Ok(_)));
    let AiState::Ok(usage) = monitor.refresh_copilot() else {
        panic!("attendu : Ok");
    };
    assert_eq!(percents(&usage), vec![37.5, 82.0]);

    let requests = handle.join().unwrap();
    let request = requests[0].to_lowercase();
    assert!(request.starts_with("get /copilot_internal/user "));
    assert!(request.contains("authorization: token tok-123\r\n"));
    // Deux actualisations, un seul appel à gh.
    assert_eq!(gh_calls(&dir), 1);
}

#[test]
fn token_refuse_redemande_a_gh_puis_reussit() {
    let dir = temp_dir("flux-retry");
    let (url, handle) = serve(vec![("401 Unauthorized", "{}"), ("200 OK", FIXTURE)]);

    assert!(matches!(monitor(&url, fake_gh(&dir, "echo tok")).refresh_copilot(), AiState::Ok(_)));
    handle.join().unwrap();
    assert_eq!(gh_calls(&dir), 2);
}

#[test]
fn token_refuse_deux_fois_donne_expired() {
    let dir = temp_dir("flux-expire");
    let (url, handle) = serve(vec![("401 Unauthorized", "{}"), ("401 Unauthorized", "{}")]);

    assert_eq!(monitor(&url, fake_gh(&dir, "echo tok")).refresh_copilot(), AiState::Expired);
    handle.join().unwrap();
}

#[test]
fn sans_gh_ou_sans_compte_donne_not_connected() {
    let dir = temp_dir("flux-sans-gh");
    assert_eq!(monitor("http://127.0.0.1:1/", dir.join("absent")).refresh_copilot(), AiState::NotConnected);

    let not_logged_in = fake_gh(&dir, "exit 1");
    assert_eq!(monitor("http://127.0.0.1:1/", not_logged_in).refresh_copilot(), AiState::NotConnected);
}

#[test]
fn pas_de_reseau_donne_offline() {
    let dir = temp_dir("flux-offline");
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}/", listener.local_addr().unwrap());
    drop(listener);

    assert_eq!(monitor(&url, fake_gh(&dir, "echo tok")).refresh_copilot(), AiState::Offline(None));
}
