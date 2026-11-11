use std::collections::HashMap;
use std::fs;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::path::PathBuf;
use std::thread::{self, JoinHandle};
use std::time::Duration;

use pulse_core::update::{
    UpdateCheck, UpdateFailure, UpdateInfo, check_for_update_at, download_verified, is_newer, parse_checksum,
    parse_release, parse_version,
};

const RELEASE: &str = include_str!("fixtures/github_release.json");
/// Empreinte SHA-256 de « contenu du dmg ».
const DMG: &[u8] = b"contenu du dmg";
const DMG_SHA256: &str = "aabdedf4285af137f7b8d687baf807af9c1c5ab3201cc09e4d6cfdfe7c455e75";

fn temp_dir(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("pulse-update-{}-{name}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    dir
}

// --- Versions ---

#[test]
fn comparaison_des_versions() {
    assert_eq!(parse_version("1.2.3"), Some([1, 2, 3]));
    assert_eq!(parse_version("1.2"), Some([1, 2, 0]));
    assert_eq!(parse_version("2"), Some([2, 0, 0]));
    assert_eq!(parse_version("1.2.3.4"), None);
    assert_eq!(parse_version("1.x"), None);
    assert_eq!(parse_version(""), None);
    // Rien d'autre que des chiffres et des points : la version sert de nom de fichier.
    for unsafe_version in ["+1.2.3", " 1.2.3", "1..3", "1.2.", "1.2.3/..", "1.-2.3"] {
        assert_eq!(parse_version(unsafe_version), None, "{unsafe_version}");
    }

    assert_eq!(is_newer("0.2.0", "0.1.0"), Some(true));
    // Comparaison numérique, pas alphabétique.
    assert_eq!(is_newer("0.10.0", "0.9.2"), Some(true));
    assert_eq!(is_newer("0.1.0", "0.1"), Some(false));
    assert_eq!(is_newer("0.1.0", "0.2.0"), Some(false));
    assert_eq!(is_newer("1.0.0-beta", "0.1.0"), None);
}

// --- Release ---

#[test]
fn release_plus_recente() {
    let info = parse_release(RELEASE, "0.1.0").unwrap().unwrap();
    assert_eq!(
        info,
        UpdateInfo {
            version: "0.2.0".to_string(),
            notes: "- Mises à jour intégrées\r\n- Corrections".to_string(),
            page_url: "https://github.com/latifcodess/Pulse/releases/tag/v0.2.0".to_string(),
            dmg_url: "https://github.com/latifcodess/Pulse/releases/download/v0.2.0/Pulse-0.2.0.dmg".to_string(),
            sha256_url: "https://github.com/latifcodess/Pulse/releases/download/v0.2.0/Pulse-0.2.0.dmg.sha256"
                .to_string(),
        }
    );
}

#[test]
fn deja_a_jour() {
    assert_eq!(parse_release(RELEASE, "0.2.0"), Ok(None));
    assert_eq!(parse_release(RELEASE, "0.3.0"), Ok(None));
}

#[test]
fn tag_avec_ou_sans_v_et_espaces() {
    for tag in ["0.2.0", " v0.2.0\\n"] {
        let json = RELEASE.replace("\"tag_name\": \"v0.2.0\"", &format!("\"tag_name\": \"{tag}\""));
        assert_eq!(parse_release(&json, "0.1.0").unwrap().unwrap().version, "0.2.0", "{tag}");
    }
}

#[test]
fn release_invalide() {
    // Sans empreinte, sans DMG, ou en HTTP : refusée.
    let without_checksum = RELEASE.replace("Pulse-0.2.0.dmg.sha256\"", "notes.txt\"");
    let without_dmg = RELEASE.replace("\"Pulse-0.2.0.dmg\"", "\"Pulse.zip\"");
    let http = RELEASE.replace("https://github.com/latifcodess/Pulse/releases/download", "http://exemple.com");
    let bad_tag = RELEASE.replace("v0.2.0\",\n  \"name", "nightly\",\n  \"name");
    for json in [without_checksum, without_dmg, http, bad_tag, "pas du json".to_string(), "{}".to_string()] {
        assert_eq!(parse_release(&json, "0.1.0"), Err(UpdateFailure::InvalidRelease), "{json}");
    }
}

#[test]
fn champs_facultatifs_manquants() {
    let minimal = r#"{"tag_name": "1.0", "assets": [
        {"name": "a.dmg", "browser_download_url": "https://x/a.dmg"},
        {"name": "a.dmg.sha256", "browser_download_url": "https://x/a.dmg.sha256"}
    ]}"#;
    let info = parse_release(minimal, "0.1.0").unwrap().unwrap();
    assert_eq!((info.version.as_str(), info.notes.as_str(), info.page_url.as_str()), ("1.0", "", ""));
}

#[test]
fn lecture_de_l_empreinte() {
    let hash = "AB".repeat(32);
    assert_eq!(parse_checksum(&format!("{hash}  Pulse-0.2.0.dmg\n")), Some("ab".repeat(32)));
    assert_eq!(parse_checksum(&hash), Some("ab".repeat(32)));
    assert_eq!(parse_checksum("abc  Pulse.dmg"), None);
    assert_eq!(parse_checksum(&"zz".repeat(32)), None);
    assert_eq!(parse_checksum(""), None);
}

// --- Réseau, contre un serveur local ---

/// Serveur local : chaque chemin a sa réponse (statut, en-têtes, corps).
/// S'arrête après `count` requêtes et renvoie les chemins demandés.
fn serve(routes: Vec<(&'static str, &'static str, String, Vec<u8>)>, count: usize) -> (String, JoinHandle<Vec<String>>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let routes: HashMap<_, _> = routes.into_iter().map(|(path, status, headers, body)| (path, (status, headers, body))).collect();
    let handle = thread::spawn(move || {
        (0..count)
            .map(|_| {
                let (mut stream, _) = listener.accept().unwrap();
                let mut request = Vec::new();
                let mut buffer = [0; 1024];
                while !request.windows(4).any(|end| end == b"\r\n\r\n") {
                    let read = stream.read(&mut buffer).unwrap();
                    request.extend_from_slice(&buffer[..read]);
                }
                let request = String::from_utf8_lossy(&request).into_owned();
                let path = request.split_whitespace().nth(1).unwrap_or("").to_string();
                let (status, headers, body) = routes.get(path.as_str()).cloned().unwrap_or(("404 Not Found", String::new(), Vec::new()));
                let head = format!("HTTP/1.1 {status}\r\n{headers}Content-Length: {}\r\nConnection: close\r\n\r\n", body.len());
                stream.write_all(head.as_bytes()).unwrap();
                stream.write_all(&body).unwrap();
                path
            })
            .collect()
    });
    (base, handle)
}

fn info(base: &str) -> UpdateInfo {
    UpdateInfo {
        version: "0.2.0".to_string(),
        notes: String::new(),
        page_url: String::new(),
        dmg_url: format!("{base}/download/Pulse-0.2.0.dmg"),
        sha256_url: format!("{base}/download/Pulse-0.2.0.dmg.sha256"),
    }
}

#[test]
fn recherche_contre_github() {
    let (base, handle) = serve(vec![("/latest", "200 OK", String::new(), RELEASE.as_bytes().to_vec())], 1);
    let check = check_for_update_at(&format!("{base}/latest"), "0.1.0", Duration::from_secs(5));
    assert!(matches!(check, UpdateCheck::Available { info } if info.version == "0.2.0"));
    handle.join().unwrap();

    let (base, handle) = serve(vec![("/latest", "200 OK", String::new(), RELEASE.as_bytes().to_vec())], 1);
    assert_eq!(check_for_update_at(&format!("{base}/latest"), "0.2.0", Duration::from_secs(5)), UpdateCheck::UpToDate);
    handle.join().unwrap();
}

#[test]
fn erreurs_de_recherche() {
    let failed = |reason| UpdateCheck::Failed { reason };
    // 404 : aucune release, ou dépôt privé.
    let (base, handle) = serve(vec![], 1);
    assert_eq!(check_for_update_at(&format!("{base}/latest"), "0.1.0", Duration::from_secs(5)), failed(UpdateFailure::NoRelease));
    handle.join().unwrap();

    let (base, handle) = serve(vec![("/latest", "403 Forbidden", String::new(), b"{}".to_vec())], 1);
    assert_eq!(check_for_update_at(&format!("{base}/latest"), "0.1.0", Duration::from_secs(5)), failed(UpdateFailure::RateLimited));
    handle.join().unwrap();

    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}/latest", listener.local_addr().unwrap());
    drop(listener);
    assert_eq!(check_for_update_at(&url, "0.1.0", Duration::from_secs(5)), failed(UpdateFailure::Offline));
}

#[test]
fn telechargement_verifie_avec_redirection() {
    let dir = temp_dir("ok");
    let checksum = format!("{DMG_SHA256}  Pulse-0.2.0.dmg\n").into_bytes();
    let (base, handle) = serve(
        vec![
            ("/download/Pulse-0.2.0.dmg.sha256", "200 OK", String::new(), checksum),
            // GitHub redirige les téléchargements vers un autre serveur.
            ("/download/Pulse-0.2.0.dmg", "302 Found", "Location: /cdn/Pulse-0.2.0.dmg\r\n".to_string(), Vec::new()),
            ("/cdn/Pulse-0.2.0.dmg", "200 OK", String::new(), DMG.to_vec()),
        ],
        3,
    );

    let path = download_verified(&info(&base), &dir, Duration::from_secs(5)).unwrap();
    assert_eq!(path, dir.join("Pulse-0.2.0.dmg"));
    assert_eq!(fs::read(&path).unwrap(), DMG);
    assert_eq!(handle.join().unwrap().len(), 3);
}

#[test]
fn empreinte_differente_supprime_le_fichier() {
    let dir = temp_dir("corrompu");
    let checksum = format!("{}  Pulse-0.2.0.dmg\n", "0".repeat(64)).into_bytes();
    let (base, handle) = serve(
        vec![
            ("/download/Pulse-0.2.0.dmg.sha256", "200 OK", String::new(), checksum),
            ("/download/Pulse-0.2.0.dmg", "200 OK", String::new(), DMG.to_vec()),
        ],
        2,
    );

    assert_eq!(download_verified(&info(&base), &dir, Duration::from_secs(5)), Err(UpdateFailure::ChecksumMismatch));
    handle.join().unwrap();
    // Ni le DMG, ni le fichier partiel ne restent.
    assert_eq!(fs::read_dir(&dir).unwrap().count(), 0);
}

#[test]
fn empreinte_illisible_ou_absente() {
    let dir = temp_dir("sans-empreinte");
    let (base, handle) = serve(vec![("/download/Pulse-0.2.0.dmg.sha256", "200 OK", String::new(), b"pas une empreinte".to_vec())], 1);
    assert_eq!(download_verified(&info(&base), &dir, Duration::from_secs(5)), Err(UpdateFailure::InvalidRelease));
    handle.join().unwrap();

    let (base, handle) = serve(vec![], 1);
    assert_eq!(download_verified(&info(&base), &dir, Duration::from_secs(5)), Err(UpdateFailure::InvalidRelease));
    handle.join().unwrap();
}
