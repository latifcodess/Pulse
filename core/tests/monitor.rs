use std::io::{Read, Write};
use std::net::TcpListener;
use std::thread::{self, JoinHandle};
use std::time::Duration;

use pulse_core::model::{AiState, AiUsage};
use pulse_core::monitor::AiMonitor;

const VALID_BODY: &str = r#"{
    "five_hour": {"utilization": 49.0, "resets_at": "2099-01-01T00:00:00+00:00"},
    "seven_day": {"utilization": 12.5, "resets_at": "2099-01-08T00:00:00+00:00"}
}"#;
const TIMEOUT: Duration = Duration::from_secs(5);

/// Serveur local qui répond une seule fois, puis ferme. Le thread renvoie la
/// requête reçue.
fn serve_once(status: &'static str, body: &'static [u8]) -> (String, JoinHandle<String>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}/api/oauth/usage", listener.local_addr().unwrap());
    let handle = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let mut request = Vec::new();
        let mut buffer = [0; 1024];
        while !request.windows(4).any(|end| end == b"\r\n\r\n") {
            let count = stream.read(&mut buffer).unwrap();
            request.extend_from_slice(&buffer[..count]);
        }
        let head = format!(
            "HTTP/1.1 {status}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
            body.len()
        );
        stream.write_all(head.as_bytes()).unwrap();
        stream.write_all(body).unwrap();
        String::from_utf8(request).unwrap()
    });
    (url, handle)
}

fn state_for(status: &'static str, body: &'static [u8]) -> AiState {
    let (url, handle) = serve_once(status, body);
    let state = AiMonitor::with_endpoint(&url, TIMEOUT).refresh_claude("token".to_string());
    handle.join().unwrap();
    state
}

fn session_percent(usage: &AiUsage) -> f64 {
    usage.windows[0].percent
}

#[test]
fn reponse_200_donne_ok_et_envoie_les_bons_en_tetes() {
    let (url, handle) = serve_once("200 OK", VALID_BODY.as_bytes());
    let state = AiMonitor::with_endpoint(&url, TIMEOUT).refresh_claude("mon-token".to_string());
    let request = handle.join().unwrap().to_lowercase();

    let AiState::Ok(usage) = state else {
        panic!("attendu : Ok, obtenu : {state:?}");
    };
    assert_eq!(session_percent(&usage), 49.0);
    assert!(request.starts_with("get /api/oauth/usage "));
    assert!(request.contains("authorization: bearer mon-token\r\n"));
    assert!(request.contains("anthropic-beta: oauth-2025-04-20\r\n"));
}

#[test]
fn codes_401_et_403_donnent_expired() {
    assert_eq!(state_for("401 Unauthorized", b""), AiState::Expired);
    assert_eq!(state_for("403 Forbidden", b""), AiState::Expired);
}

#[test]
fn code_429_donne_blocked() {
    assert_eq!(state_for("429 Too Many Requests", b""), AiState::Blocked);
}

#[test]
fn autres_codes_donnent_unavailable() {
    assert_eq!(state_for("500 Internal Server Error", b""), AiState::Unavailable);
    assert_eq!(state_for("302 Found", b""), AiState::Unavailable);
}

#[test]
fn reponse_illisible_donne_unavailable() {
    assert_eq!(state_for("200 OK", b"pas du json"), AiState::Unavailable);
    assert_eq!(state_for("200 OK", b"{}"), AiState::Unavailable);
    assert_eq!(state_for("200 OK", &[0xff, 0xfe]), AiState::Unavailable);
}

#[test]
fn pas_de_reseau_sans_valeur_connue_donne_offline_vide() {
    // On réserve un port puis on le libère : plus personne n'y écoute.
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}/", listener.local_addr().unwrap());
    drop(listener);

    let state = AiMonitor::with_endpoint(&url, TIMEOUT).refresh_claude("token".to_string());
    assert_eq!(state, AiState::Offline(None));
}

#[test]
fn delai_depasse_donne_offline() {
    // Le serveur accepte la connexion mais ne répond jamais.
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}/", listener.local_addr().unwrap());

    let monitor = AiMonitor::with_endpoint(&url, Duration::from_millis(200));
    assert_eq!(monitor.refresh_claude("token".to_string()), AiState::Offline(None));
}

#[test]
fn pas_de_reseau_garde_la_derniere_valeur() {
    let (url, handle) = serve_once("200 OK", VALID_BODY.as_bytes());
    let monitor = AiMonitor::with_endpoint(&url, TIMEOUT);
    assert!(matches!(monitor.refresh_claude("token".to_string()), AiState::Ok(_)));
    handle.join().unwrap(); // Le serveur est arrêté : le prochain appel échoue.

    let AiState::Offline(Some(usage)) = monitor.refresh_claude("token".to_string()) else {
        panic!("attendu : Offline avec la dernière valeur");
    };
    assert_eq!(session_percent(&usage), 49.0);
}

#[test]
fn reset_passe_repart_a_zero_meme_hors_ligne() {
    // Fenêtre déjà réinitialisée, l'autre pas encore.
    const BODY: &str = r#"{
        "five_hour": {"utilization": 49.0, "resets_at": "2020-01-01T00:00:00+00:00"},
        "seven_day": {"utilization": 12.5, "resets_at": "2099-01-08T00:00:00+00:00"}
    }"#;
    let (url, handle) = serve_once("200 OK", BODY.as_bytes());
    let monitor = AiMonitor::with_endpoint(&url, TIMEOUT);

    let AiState::Ok(usage) = monitor.refresh_claude("token".to_string()) else {
        panic!("attendu : Ok");
    };
    assert_eq!(usage.windows[0].percent, 0.0);
    assert_eq!(usage.windows[0].resets_at, None);
    assert_eq!(usage.windows[1].percent, 12.5);
    handle.join().unwrap();

    let AiState::Offline(Some(usage)) = monitor.refresh_claude("token".to_string()) else {
        panic!("attendu : Offline avec la dernière valeur");
    };
    assert_eq!(usage.windows[0].percent, 0.0);
    assert_eq!(usage.windows[1].percent, 12.5);
}
