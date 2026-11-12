//! Connexions aux comptes dans Pulse : ChatGPT (session chatgpt.com),
//! Copilot (code GitHub) et Gemini (navigateur + adresse locale).

use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use std::time::Duration;

use pulse_core::chatgpt::parse_web_session;
use pulse_core::copilot::{DeviceLoginStep, parse_copilot_usage, parse_device_code, parse_device_token};
use pulse_core::gemini::{GeminiLogin, GeminiLoginResult, base64_url, parse_query};
use pulse_core::model::AiState;
use pulse_core::monitor::{AiMonitor, MonitorConfig};

const CHATGPT_USAGE: &str = include_str!("fixtures/chatgpt.json");
const COPILOT_USAGE: &str = include_str!("fixtures/copilot.json");

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

/// Serveur local qui sert ces réponses dans l'ordre, une par connexion.
fn serve(replies: Vec<(&'static str, &'static str, &'static str)>) -> (String, JoinHandle<Vec<Request>>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}", listener.local_addr().unwrap());
    let handle = thread::spawn(move || {
        replies
            .into_iter()
            .map(|(status, content_type, body)| {
                let (mut stream, _) = listener.accept().unwrap();
                let request = read_request(&mut stream);
                let reply = format!(
                    "HTTP/1.1 {status}\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                    body.len()
                );
                stream.write_all(reply.as_bytes()).unwrap();
                request
            })
            .collect()
    });
    (url, handle)
}

fn read_request(stream: &mut TcpStream) -> Request {
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
    Request {
        head,
        body: String::from_utf8_lossy(&data[head_end..]).into_owned(),
    }
}

fn monitor(base: &str) -> Arc<AiMonitor> {
    AiMonitor::with_config(MonitorConfig {
        chatgpt_session_url: format!("{base}/api/auth/session"),
        chatgpt_usage_url: format!("{base}/backend-api/wham/usage"),
        copilot_usage_url: format!("{base}/copilot_internal/user"),
        github_device_code_url: format!("{base}/login/device/code"),
        github_device_token_url: format!("{base}/login/oauth/access_token"),
        timeout: Duration::from_secs(5),
        ..MonitorConfig::production()
    })
}

// --- ChatGPT ---

#[test]
fn session_chatgpt_lue() {
    let auth = parse_web_session(r#"{"user": {"id": "u"}, "account": {"id": "acc-1"}, "accessToken": "eyJ.tok"}"#).unwrap();
    assert_eq!(auth.access_token, "eyJ.tok");
    assert_eq!(auth.account_id.as_deref(), Some("acc-1"));
    // Sans compte : le token suffit. Session expirée : « {} ».
    assert_eq!(parse_web_session(r#"{"accessToken": "t"}"#).unwrap().account_id, None);
    for json in ["{}", r#"{"accessToken": ""}"#, "pas du json"] {
        assert_eq!(parse_web_session(json), None, "{json}");
    }
}

#[test]
fn compte_chatgpt_session_puis_usage() {
    let (base, handle) = serve(vec![
        ("200 OK", "application/json", r#"{"accessToken": "eyJ.tok", "account": {"id": "acc-1"}}"#),
        ("200 OK", "application/json", CHATGPT_USAGE),
    ]);
    let state = monitor(&base).refresh_chatgpt_account("__Secure-next-auth.session-token.0=a; __Secure-next-auth.session-token.1=b".into());
    assert!(matches!(state, AiState::Ok(_)), "{state:?}");

    let requests = handle.join().unwrap();
    assert!(requests[0].line().starts_with("get /api/auth/session "));
    assert!(requests[0].has_header("cookie: __Secure-next-auth.session-token.0=a; __Secure-next-auth.session-token.1=b"));
    assert!(requests[1].line().starts_with("get /backend-api/wham/usage "));
    assert!(requests[1].has_header("authorization: Bearer eyJ.tok"));
    assert!(requests[1].has_header("chatgpt-account-id: acc-1"));
}

#[test]
fn compte_chatgpt_session_expiree_ou_bloquee() {
    let (base, handle) = serve(vec![("200 OK", "application/json", "{}")]);
    assert_eq!(monitor(&base).refresh_chatgpt_account("c=1".into()), AiState::Expired);
    handle.join().unwrap();

    let (base, handle) = serve(vec![("200 OK", "text/html; charset=utf-8", "<!doctype html><title>Un instant…</title>")]);
    assert_eq!(monitor(&base).refresh_chatgpt_account("c=1".into()), AiState::Blocked);
    handle.join().unwrap();

    let (base, handle) = serve(vec![("403 Forbidden", "application/json", "{}")]);
    assert_eq!(monitor(&base).refresh_chatgpt_account("c=1".into()), AiState::Expired);
    handle.join().unwrap();
}

// --- Copilot ---

#[test]
fn quota_sans_droit_ignore() {
    // Copilot Free : 0 requête premium incluse, à ne pas afficher « 100 % utilisé ».
    let json = r#"{"quota_reset_date_utc": "2026-12-01T00:00:00.000Z", "quota_snapshots": {
        "chat": {"percent_remaining": 100.0, "unlimited": false, "entitlement": 200},
        "completions": {"percent_remaining": 80.0, "unlimited": false, "entitlement": 2000},
        "premium_interactions": {"percent_remaining": 0.0, "unlimited": false, "entitlement": 0}
    }}"#;
    let labels: Vec<String> = parse_copilot_usage(json).unwrap().windows.into_iter().map(|w| w.label).collect();
    assert_eq!(labels, vec!["Chat", "Complétions"]);
}

#[test]
fn code_github_lu() {
    let code = parse_device_code(
        r#"{"device_code": "dc", "user_code": "85A2-AFB9", "verification_uri": "https://github.com/login/device", "expires_in": 899, "interval": 5}"#,
    )
    .unwrap();
    assert_eq!((code.user_code.as_str(), code.interval, code.expires_in), ("85A2-AFB9", 5, 899));
    // Champs facultatifs manquants, ou adresse non HTTPS : valeurs par défaut.
    let code = parse_device_code(r#"{"device_code": "dc", "user_code": "X", "verification_uri": "http://piege"}"#).unwrap();
    assert_eq!((code.verification_uri.as_str(), code.interval, code.expires_in), ("https://github.com/login/device", 5, 900));
    assert_eq!(parse_device_code(r#"{"user_code": "X"}"#), None);
}

#[test]
fn reponses_de_github_pendant_la_connexion() {
    let cases = [
        (r#"{"access_token": "ghu_abc", "token_type": "bearer"}"#, DeviceLoginStep::Authorized { token: "ghu_abc".into() }),
        (r#"{"error": "authorization_pending"}"#, DeviceLoginStep::Pending),
        (r#"{"error": "slow_down", "interval": 10}"#, DeviceLoginStep::SlowDown),
        (r#"{"error": "expired_token"}"#, DeviceLoginStep::Expired),
        (r#"{"error": "access_denied"}"#, DeviceLoginStep::Denied),
        (r#"{"error": "autre"}"#, DeviceLoginStep::Failed),
        ("pas du json", DeviceLoginStep::Failed),
    ];
    for (json, expected) in cases {
        assert_eq!(parse_device_token(json), expected, "{json}");
    }
}

#[test]
fn connexion_github_puis_usage() {
    let (base, handle) = serve(vec![
        ("200 OK", "application/json", r#"{"device_code": "dc-1", "user_code": "85A2-AFB9", "verification_uri": "https://github.com/login/device", "expires_in": 899, "interval": 5}"#),
        ("200 OK", "application/json", r#"{"error": "authorization_pending"}"#),
        ("200 OK", "application/json", r#"{"access_token": "ghu_abc", "token_type": "bearer"}"#),
        ("200 OK", "application/json", COPILOT_USAGE),
    ]);
    let monitor = monitor(&base);
    let code = monitor.copilot_device_code().unwrap();
    assert_eq!(code.user_code, "85A2-AFB9");
    assert_eq!(monitor.copilot_poll_device(code.device_code.clone()), DeviceLoginStep::Pending);
    let DeviceLoginStep::Authorized { token } = monitor.copilot_poll_device(code.device_code) else {
        panic!("attendu : Authorized");
    };
    assert!(matches!(monitor.refresh_copilot_account(token), AiState::Ok(_)));

    let requests = handle.join().unwrap();
    assert!(requests[0].body.contains("client_id=Iv1.b507a08c87ecfe98"));
    assert!(requests[1].body.contains("device_code=dc-1"));
    assert!(requests[1].body.contains("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code"));
    assert!(requests[3].has_header("authorization: token ghu_abc"));
}

#[test]
fn token_github_refuse_donne_expired() {
    let (base, handle) = serve(vec![("401 Unauthorized", "application/json", "{}")]);
    assert_eq!(monitor(&base).refresh_copilot_account("ghu_old".into()), AiState::Expired);
    handle.join().unwrap();
}

// --- Gemini ---

#[test]
fn base64_url_et_parametres() {
    // Vecteurs de la RFC 4648, sans « = ».
    for (input, expected) in [("", ""), ("f", "Zg"), ("fo", "Zm8"), ("foo", "Zm9v"), ("foob", "Zm9vYg"), ("fooba", "Zm9vYmE")] {
        assert_eq!(base64_url(input.as_bytes()), expected);
    }
    assert_eq!(base64_url(&[0xfb, 0xff]), "-_8");
    let params = parse_query("code=4%2F0Ab_c&state=xyz&scope=a+b&vide=&%aé=1");
    assert_eq!(params[0], ("code".into(), "4/0Ab_c".into()));
    assert_eq!(params[2], ("scope".into(), "a b".into()));
    assert_eq!(params[3], ("vide".into(), String::new()));
    // Un « % » mal formé est gardé tel quel, sans planter.
    assert_eq!(params[4].0, "%aé");
}

/// Prépare une connexion Gemini vers un faux serveur de tokens, et renvoie
/// l'adresse de retour et le « state » de la page de connexion.
fn start_login(token_base: &str) -> (Arc<GeminiLogin>, String, String) {
    let login = GeminiLogin::start("https://accounts.example/auth", &format!("{token_base}/token")).unwrap();
    let url = login.authorization_url();
    let query = url.split_once('?').unwrap().1;
    let params = parse_query(query);
    let get = |key: &str| params.iter().find(|(k, _)| k == key).unwrap().1.clone();
    assert_eq!(get("code_challenge_method"), "S256");
    assert_eq!(get("code_challenge").len(), 43);
    assert_eq!(get("access_type"), "offline");
    (login, get("redirect_uri"), get("state"))
}

/// Le navigateur qui revient de Google sur l'adresse locale.
fn browser_get(url: &str) -> String {
    let rest = url.strip_prefix("http://").unwrap();
    let (host, path) = rest.split_once('/').unwrap();
    let mut stream = TcpStream::connect(host).unwrap();
    write!(stream, "GET /{path} HTTP/1.1\r\nHost: {host}\r\nConnection: close\r\n\r\n").unwrap();
    let mut page = String::new();
    stream.read_to_string(&mut page).unwrap();
    page
}

#[test]
fn connexion_google_reussie() {
    let (base, handle) = serve(vec![("200 OK", "application/json", r#"{"access_token": "ya29.x", "refresh_token": "1//refresh", "expires_in": 3599}"#)]);
    let (login, redirect_uri, state) = start_login(&base);

    let waiter = {
        let login = login.clone();
        thread::spawn(move || login.wait(10))
    };
    thread::sleep(Duration::from_millis(200));
    // Une demande parasite (icône) est ignorée, puis la vraie réponse arrive.
    let host = redirect_uri.trim_end_matches("/oauth2callback");
    assert!(browser_get(&format!("{host}/favicon.ico")).starts_with("HTTP/1.1 404"));
    let page = browser_get(&format!("{redirect_uri}?state={state}&code=4%2F0Ab&scope=x"));
    assert!(page.contains("Pulse est connecté"));

    assert_eq!(waiter.join().unwrap(), GeminiLoginResult::Success { refresh_token: "1//refresh".into() });
    let exchange = &handle.join().unwrap()[0];
    assert!(exchange.body.contains("code=4%2F0Ab"));
    assert!(exchange.body.contains("grant_type=authorization_code"));
    assert!(exchange.body.contains("code_verifier="));
    assert!(exchange.body.contains(&format!("redirect_uri={}", redirect_uri.replace(':', "%3A").replace('/', "%2F"))));
}

#[test]
fn connexion_google_refusee_ou_falsifiee() {
    let (login, redirect_uri, state) = start_login("http://127.0.0.1:1");
    let waiter = {
        let login = login.clone();
        thread::spawn(move || login.wait(10))
    };
    thread::sleep(Duration::from_millis(200));
    browser_get(&format!("{redirect_uri}?state={state}&error=access_denied"));
    assert_eq!(waiter.join().unwrap(), GeminiLoginResult::Denied);

    // Un « state » qui ne vient pas de Pulse : refusé, sans échange de code.
    let (login, redirect_uri, _) = start_login("http://127.0.0.1:1");
    let waiter = {
        let login = login.clone();
        thread::spawn(move || login.wait(10))
    };
    thread::sleep(Duration::from_millis(200));
    browser_get(&format!("{redirect_uri}?state=faux&code=vole"));
    assert_eq!(waiter.join().unwrap(), GeminiLoginResult::Failed);
}

#[test]
fn connexion_google_annulee_ou_trop_longue() {
    let (login, _, _) = start_login("http://127.0.0.1:1");
    let waiter = {
        let login = login.clone();
        thread::spawn(move || login.wait(30))
    };
    thread::sleep(Duration::from_millis(200));
    login.cancel();
    assert_eq!(waiter.join().unwrap(), GeminiLoginResult::Cancelled);

    let (login, _, _) = start_login("http://127.0.0.1:1");
    assert_eq!(login.wait(1), GeminiLoginResult::Cancelled);
}

#[test]
fn compte_google_dans_pulse() {
    let (base, handle) = serve(vec![
        ("200 OK", "application/json", r#"{"access_token": "ya29.neuf", "expires_in": 3599}"#),
        ("200 OK", "application/json", r#"{"cloudaicompanionProject": "p-1"}"#),
        ("200 OK", "application/json", include_str!("fixtures/gemini.json")),
    ]);
    let monitor = AiMonitor::with_config(MonitorConfig {
        google_token_url: format!("{base}/token"),
        gemini_api_base_url: format!("{base}/v1internal"),
        timeout: Duration::from_secs(5),
        ..MonitorConfig::production()
    });
    assert!(matches!(monitor.refresh_gemini_account("1//refresh".into()), AiState::Ok(_)));
    let requests = handle.join().unwrap();
    assert!(requests[0].body.contains("refresh_token=1%2F%2Frefresh"));
    assert!(requests[1].has_header("authorization: Bearer ya29.neuf"));
}
