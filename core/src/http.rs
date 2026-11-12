//! Requête HTTP GET commune aux différentes sources.

use std::time::Duration;

/// Pourquoi l'usage n'a pas pu être récupéré.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FetchError {
    /// Le token ou la session n'est plus accepté.
    Expired,
    /// Trop de requêtes, ou protection anti-bot.
    Blocked,
    /// Pas de réponse : pas de réseau, serveur injoignable ou délai dépassé.
    Offline,
    /// Le serveur a répondu, mais la réponse est inexploitable.
    Unavailable,
}

/// Une réponse HTTP brute. Swift en construit aussi, avec ce qu'il récupère
/// depuis une page web.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct HttpResponse {
    pub status: u16,
    pub content_type: Option<String>,
    pub body: String,
}

/// GET bloquant : il ne doit pas tourner sur le thread principal de l'app.
/// Tout code HTTP renvoie Ok : c'est à l'appelant de l'interpréter.
pub fn get(url: &str, headers: &[(&str, &str)], timeout: Duration) -> Result<HttpResponse, FetchError> {
    let mut request = agent(timeout).get(url);
    for (name, value) in headers {
        request = request.header(*name, *value);
    }
    read_response(request.call())
}

/// POST bloquant, avec un corps déjà encodé (JSON ou formulaire) : le
/// Content-Type est à donner dans `headers`.
pub fn post(url: &str, headers: &[(&str, &str)], body: &str, timeout: Duration) -> Result<HttpResponse, FetchError> {
    let mut request = agent(timeout).post(url);
    for (name, value) in headers {
        request = request.header(*name, *value);
    }
    read_response(request.send(body))
}

fn agent(timeout: Duration) -> ureq::Agent {
    ureq::Agent::config_builder()
        .timeout_global(Some(timeout))
        .http_status_as_error(false)
        // Une redirection pourrait envoyer le token vers un autre serveur.
        .max_redirects(0)
        .build()
        .into()
}

fn read_response(result: Result<ureq::http::Response<ureq::Body>, ureq::Error>) -> Result<HttpResponse, FetchError> {
    let mut response = result.map_err(transport_error)?;
    let status = response.status().as_u16();
    let content_type = response
        .headers()
        .get("content-type")
        .and_then(|value| value.to_str().ok())
        .map(str::to_string);
    let bytes = response.body_mut().read_to_vec().map_err(transport_error)?;

    Ok(HttpResponse {
        status,
        content_type,
        body: String::from_utf8_lossy(&bytes).into_owned(),
    })
}

fn transport_error(error: ureq::Error) -> FetchError {
    match error {
        // Requête ou réponse invalide : le réseau n'y est pour rien.
        ureq::Error::Http(_) | ureq::Error::BadUri(_) | ureq::Error::BodyExceedsLimit(_) => {
            FetchError::Unavailable
        }
        _ => FetchError::Offline,
    }
}

/// Encode un formulaire : lettres, chiffres et « -._~ » tels quels, le reste
/// en %XX.
pub fn form_encode(pairs: &[(&str, &str)]) -> String {
    let encode = |text: &str| -> String {
        text.bytes()
            .map(|byte| match byte {
                b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'.' | b'_' | b'~' => (byte as char).to_string(),
                _ => format!("%{byte:02X}"),
            })
            .collect()
    };
    pairs
        .iter()
        .map(|(key, value)| format!("{}={}", encode(key), encode(value)))
        .collect::<Vec<_>>()
        .join("&")
}
