use std::io::{Read, Write};
use std::net::TcpListener;
use std::thread::{self, JoinHandle};
use std::time::Duration;

use pulse_core::claude_web::{classify, claude_web_usage_path, organization_uuid};
use pulse_core::http::{FetchError, HttpResponse};
use pulse_core::model::AiState;
use pulse_core::monitor::AiMonitor;

const JSON: Option<&str> = Some("application/json");
const HTML: Option<&str> = Some("text/html; charset=UTF-8");
const HTML_PAGE: &str = "<!DOCTYPE html><html><title>Just a moment...</title></html>";
const USAGE_BODY: &str = r#"{"five_hour": {"utilization": 49.0, "resets_at": "2099-01-01T00:00:00+00:00"}}"#;
const ORGANIZATIONS_BODY: &str = r#"[{"uuid": "abc-123", "name": "Perso"}, {"uuid": "zzz"}]"#;

fn response(status: u16, content_type: Option<&str>, body: &str) -> HttpResponse {
    HttpResponse {
        status,
        content_type: content_type.map(str::to_string),
        body: body.to_string(),
    }
}

// --- Classification des réponses ---

#[test]
fn json_200_est_exploitable() {
    assert_eq!(classify(&response(200, JSON, "{}")), Ok("{}"));
}

#[test]
fn html_200_ou_403_donne_blocked() {
    assert_eq!(classify(&response(200, HTML, HTML_PAGE)), Err(FetchError::Blocked));
    assert_eq!(classify(&response(403, HTML, HTML_PAGE)), Err(FetchError::Blocked));
}

#[test]
fn html_reconnu_meme_sans_content_type() {
    assert_eq!(classify(&response(200, None, HTML_PAGE)), Err(FetchError::Blocked));
    assert_eq!(classify(&response(403, None, "  <html><body></body></html>")), Err(FetchError::Blocked));
}

#[test]
fn json_401_ou_403_donne_expired() {
    let body = r#"{"error": {"type": "permission_error"}}"#;
    assert_eq!(classify(&response(401, JSON, body)), Err(FetchError::Expired));
    assert_eq!(classify(&response(403, JSON, body)), Err(FetchError::Expired));
}

#[test]
fn autres_codes() {
    assert_eq!(classify(&response(429, JSON, "{}")), Err(FetchError::Blocked));
    assert_eq!(classify(&response(500, JSON, "{}")), Err(FetchError::Unavailable));
}

// --- Organisations ---

#[test]
fn uuid_de_la_premiere_organisation() {
    assert_eq!(organization_uuid(ORGANIZATIONS_BODY), Some("abc-123".to_string()));
}

#[test]
fn uuid_absent_ou_dangereux_est_refuse() {
    for body in ["[]", "{}", "pas du json", r#"[{"name": "x"}]"#, r#"[{"uuid": ""}]"#, r#"[{"uuid": "../x?y"}]"#] {
        assert_eq!(organization_uuid(body), None, "corps : {body}");
    }
}

#[test]
fn chemin_d_usage_pour_le_repli() {
    assert_eq!(
        claude_web_usage_path(response(200, JSON, ORGANIZATIONS_BODY)),
        Some("/api/organizations/abc-123/usage".to_string())
    );
    assert_eq!(claude_web_usage_path(response(403, HTML, HTML_PAGE)), None);
}

#[test]
fn repli_lit_la_reponse_d_usage() {
    let monitor = AiMonitor::new();
    let state = monitor.claude_state_from_web_response(response(200, JSON, USAGE_BODY));
    let AiState::Ok(usage) = state else {
        panic!("attendu : Ok, obtenu : {state:?}");
    };
    assert_eq!(usage.windows[0].percent, 49.0);

    let blocked = monitor.claude_state_from_web_response(response(200, HTML, HTML_PAGE));
    assert_eq!(blocked, AiState::Blocked);
}

// --- Flux complet contre un serveur local ---

type Reply = (&'static str, &'static str, &'static str);

/// Serveur local qui sert ces réponses dans l'ordre, une par connexion. Le
/// thread renvoie les requêtes reçues.
fn serve(replies: Vec<Reply>) -> (String, JoinHandle<Vec<String>>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let base_url = format!("http://{}", listener.local_addr().unwrap());
    let handle = thread::spawn(move || {
        replies
            .into_iter()
            .map(|(status, content_type, body)| {
                let (mut stream, _) = listener.accept().unwrap();
                let mut request = Vec::new();
                let mut buffer = [0; 1024];
                while !request.windows(4).any(|end| end == b"\r\n\r\n") {
                    let count = stream.read(&mut buffer).unwrap();
                    request.extend_from_slice(&buffer[..count]);
                }
                let reply = format!(
                    "HTTP/1.1 {status}\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                    body.len()
                );
                stream.write_all(reply.as_bytes()).unwrap();
                String::from_utf8(request).unwrap()
            })
            .collect()
    });
    (base_url, handle)
}

fn monitor_for(base_url: &str) -> std::sync::Arc<AiMonitor> {
    AiMonitor::with_endpoints("http://127.0.0.1:1/", base_url, Duration::from_secs(5))
}

#[test]
fn flux_complet_organisations_puis_usage() {
    let (base_url, handle) = serve(vec![
        ("200 OK", "application/json", ORGANIZATIONS_BODY),
        ("200 OK", "application/json", USAGE_BODY),
    ]);
    let state = monitor_for(&base_url).refresh_claude_web("ma-session".to_string());
    let requests: Vec<String> = handle.join().unwrap().iter().map(|r| r.to_lowercase()).collect();

    let AiState::Ok(usage) = state else {
        panic!("attendu : Ok, obtenu : {state:?}");
    };
    assert_eq!(usage.windows[0].percent, 49.0);

    assert!(requests[0].starts_with("get /api/organizations "));
    assert!(requests[1].starts_with("get /api/organizations/abc-123/usage "));
    for request in &requests {
        assert!(request.contains("cookie: sessionkey=ma-session\r\n"));
        assert!(request.contains("accept: application/json\r\n"));
        assert!(request.contains("user-agent: mozilla/5.0 (macintosh;"));
        assert!(request.contains("safari/"));
    }
}

#[test]
fn flux_complet_bloque_par_l_anti_bot() {
    let (base_url, handle) = serve(vec![("403 Forbidden", "text/html", HTML_PAGE)]);
    assert_eq!(monitor_for(&base_url).refresh_claude_web("s".to_string()), AiState::Blocked);
    handle.join().unwrap();
}

#[test]
fn flux_complet_session_expiree() {
    let (base_url, handle) = serve(vec![("401 Unauthorized", "application/json", "{}")]);
    assert_eq!(monitor_for(&base_url).refresh_claude_web("s".to_string()), AiState::Expired);
    handle.join().unwrap();
}
