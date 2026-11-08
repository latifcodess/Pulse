use pulse_core::alerts::{
    AlertEngine, AlertEvent, AlertEventKind, AlertKind, AlertRule, alert_rules_from_json, alert_rules_to_json,
    default_alert_rules, is_new_window,
};
use pulse_core::model::{AiService, AiState, AiUsage, UsageWindow};

const NOW: i64 = 1_794_000_000;
const HOUR: i64 = 3600;

fn window(label: &str, percent: f64, resets_at: Option<i64>) -> UsageWindow {
    UsageWindow {
        label: label.to_string(),
        percent,
        resets_at,
        projected_full_at: None,
    }
}

/// Un état Ok avec une session et une semaine, qui se réinitialisent dans 2 h et 3 jours.
fn ok(session: f64, week: f64) -> AiState {
    AiState::Ok(AiUsage {
        windows: vec![
            window("Session", session, Some(NOW + 2 * HOUR)),
            window("Semaine", week, Some(NOW + 72 * HOUR)),
        ],
    })
}

fn rule(id: &str, kind: AlertKind) -> AlertRule {
    AlertRule {
        id: id.to_string(),
        enabled: true,
        service: None,
        kind,
    }
}

fn threshold(index: u32, percent: f64) -> AlertRule {
    rule("seuil", AlertKind::Threshold { window_index: index, percent })
}

fn ids(events: &[AlertEvent]) -> Vec<&str> {
    events.iter().map(|e| e.rule_id.as_str()).collect()
}

// --- Seuils ---

#[test]
fn seuil_1re_limite_une_seule_fois_puis_rearme() {
    let engine = AlertEngine::new();
    let rules = vec![threshold(0, 80.0)];
    let eval = |state| engine.evaluate(AiService::Claude, state, rules.clone(), NOW);

    assert!(eval(ok(79.0, 0.0)).is_empty());
    let events = eval(ok(80.0, 0.0));
    assert_eq!(
        events,
        vec![AlertEvent {
            rule_id: "seuil".to_string(),
            service: AiService::Claude,
            kind: AlertEventKind::Threshold {
                window_label: "Session".to_string(),
                percent: 80.0,
                threshold: 80.0,
                resets_at: Some(NOW + 2 * HOUR),
            },
        }]
    );
    // Toujours au-dessus : pas de nouvelle notification.
    assert!(eval(ok(85.0, 0.0)).is_empty());
    assert!(eval(ok(95.0, 0.0)).is_empty());
    // Redescend : l'alerte se réarme, puis se redéclenche.
    assert!(eval(ok(10.0, 0.0)).is_empty());
    assert_eq!(eval(ok(81.0, 0.0)).len(), 1);
}

#[test]
fn seuil_2e_limite() {
    let engine = AlertEngine::new();
    let rules = vec![threshold(1, 90.0)];

    // La 1re limite ne compte pas pour cette règle.
    assert!(engine.evaluate(AiService::Claude, ok(99.0, 89.0), rules.clone(), NOW).is_empty());
    let events = engine.evaluate(AiService::Claude, ok(0.0, 90.5), rules.clone(), NOW);
    assert!(matches!(&events[0].kind, AlertEventKind::Threshold { window_label, .. } if window_label == "Semaine"));
}

#[test]
fn seuil_sur_une_limite_absente_ignore() {
    let engine = AlertEngine::new();
    let state = AiState::Ok(AiUsage {
        windows: vec![window("Session", 99.0, None)],
    });
    assert!(engine.evaluate(AiService::Copilot, state, vec![threshold(1, 50.0)], NOW).is_empty());
}

#[test]
fn chaque_service_a_ses_propres_alertes() {
    let engine = AlertEngine::new();
    let rules = vec![threshold(0, 80.0)];

    assert_eq!(engine.evaluate(AiService::Claude, ok(90.0, 0.0), rules.clone(), NOW).len(), 1);
    assert_eq!(engine.evaluate(AiService::ChatGpt, ok(90.0, 0.0), rules.clone(), NOW).len(), 1);
}

#[test]
fn regle_limitee_a_un_service() {
    let engine = AlertEngine::new();
    let mut only_gemini = threshold(0, 50.0);
    only_gemini.service = Some(AiService::Gemini);

    assert!(engine.evaluate(AiService::Claude, ok(90.0, 0.0), vec![only_gemini.clone()], NOW).is_empty());
    assert_eq!(engine.evaluate(AiService::Gemini, ok(90.0, 0.0), vec![only_gemini], NOW).len(), 1);
}

#[test]
fn regle_desactivee_ne_declenche_rien() {
    let engine = AlertEngine::new();
    let mut disabled = threshold(0, 50.0);
    disabled.enabled = false;
    assert!(engine.evaluate(AiService::Claude, ok(90.0, 0.0), vec![disabled], NOW).is_empty());
}

#[test]
fn regle_modifiee_repart_de_zero() {
    let engine = AlertEngine::new();
    assert_eq!(engine.evaluate(AiService::Claude, ok(85.0, 0.0), vec![threshold(0, 80.0)], NOW).len(), 1);
    // Même identifiant, seuil abaissé : déjà au-dessus, l'alerte part tout de suite.
    assert_eq!(engine.evaluate(AiService::Claude, ok(85.0, 0.0), vec![threshold(0, 70.0)], NOW).len(), 1);
    assert!(engine.evaluate(AiService::Claude, ok(86.0, 0.0), vec![threshold(0, 70.0)], NOW).is_empty());
}

#[test]
fn hors_ligne_ou_bloque_ne_change_rien() {
    let engine = AlertEngine::new();
    let rules = vec![threshold(0, 80.0)];
    assert_eq!(engine.evaluate(AiService::Claude, ok(85.0, 0.0), rules.clone(), NOW).len(), 1);

    // Les valeurs hors ligne sont anciennes : elles ne réarment pas l'alerte.
    let stale = AiState::Offline(Some(AiUsage {
        windows: vec![window("Session", 5.0, None)],
    }));
    for state in [stale, AiState::Blocked, AiState::Unavailable, AiState::NotConnected] {
        assert!(engine.evaluate(AiService::Claude, state, rules.clone(), NOW).is_empty());
    }
    assert!(engine.evaluate(AiService::Claude, ok(85.0, 0.0), rules, NOW).is_empty());
}

// --- De nouveau disponible ---

fn available() -> AlertRule {
    rule("dispo", AlertKind::Available { after_percent: 80.0 })
}

#[test]
fn disponible_quand_la_fenetre_se_termine_apres_80() {
    let engine = AlertEngine::new();
    let rules = vec![available()];
    let session = |percent, resets_at| AiState::Ok(AiUsage {
        windows: vec![window("Session", percent, resets_at)],
    });

    assert!(engine.evaluate(AiService::Claude, session(95.0, Some(NOW + HOUR)), rules.clone(), NOW).is_empty());
    // Une heure plus tard, la fenêtre est terminée : nouvelle fenêtre.
    let later = NOW + HOUR;
    let events = engine.evaluate(AiService::Claude, session(2.0, Some(later + 5 * HOUR)), rules.clone(), later);
    assert_eq!(
        events[0].kind,
        AlertEventKind::Available {
            window_label: "Session".to_string(),
            previous_percent: 95.0,
        }
    );
    // Une seule fois.
    assert!(engine.evaluate(AiService::Claude, session(3.0, Some(later + 5 * HOUR)), rules, later + 60).is_empty());
}

#[test]
fn pas_disponible_si_la_fenetre_precedente_etait_sous_80() {
    let engine = AlertEngine::new();
    let rules = vec![available()];
    let session = |percent, resets_at| AiState::Ok(AiUsage {
        windows: vec![window("Session", percent, resets_at)],
    });

    engine.evaluate(AiService::Claude, session(80.0, Some(NOW + HOUR)), rules.clone(), NOW);
    let later = NOW + 2 * HOUR;
    assert!(engine.evaluate(AiService::Claude, session(0.0, None), rules, later).is_empty());
}

#[test]
fn disponible_pour_chaque_limite_concernee() {
    let engine = AlertEngine::new();
    let rules = vec![available()];
    engine.evaluate(AiService::Claude, ok(90.0, 85.0), rules.clone(), NOW);

    // Trois jours plus tard, les deux fenêtres ont redémarré.
    let later = NOW + 73 * HOUR;
    let events = engine.evaluate(AiService::Claude, ok(0.0, 0.0), rules, later);
    assert_eq!(ids(&events), vec!["dispo", "dispo"]);
}

#[test]
fn detection_d_une_nouvelle_fenetre() {
    let before = window("S", 90.0, Some(NOW + HOUR));
    // Même fenêtre, heure de reset recalculée à quelques secondes près.
    assert!(!is_new_window(&before, &window("S", 92.0, Some(NOW + HOUR + 5)), NOW));
    // L'heure de reset a avancé de plusieurs heures.
    assert!(is_new_window(&before, &window("S", 1.0, Some(NOW + 6 * HOUR)), NOW));
    // La fenêtre précédente est terminée.
    assert!(is_new_window(&before, &window("S", 0.0, None), NOW + HOUR));
    // Sans heure de reset : forte baisse seulement.
    let no_time = window("S", 90.0, None);
    assert!(!is_new_window(&no_time, &window("S", 85.0, None), NOW));
    assert!(is_new_window(&no_time, &window("S", 10.0, None), NOW));
}

// --- Session expirée ---

#[test]
fn expiree_une_fois_puis_rearmee_quand_la_session_revient() {
    let engine = AlertEngine::new();
    let rules = vec![rule("exp", AlertKind::Expired)];
    let eval = |state| engine.evaluate(AiService::ChatGpt, state, rules.clone(), NOW);

    assert_eq!(eval(AiState::Expired)[0].kind, AlertEventKind::Expired);
    assert!(eval(AiState::Expired).is_empty());
    // Hors ligne entre-temps : toujours pas de nouvelle notification.
    assert!(eval(AiState::Offline(None)).is_empty());
    assert!(eval(AiState::Expired).is_empty());
    // La session redevient valide, puis expire à nouveau.
    assert!(eval(ok(10.0, 0.0)).is_empty());
    assert_eq!(eval(AiState::Expired).len(), 1);
}

#[test]
fn non_connecte_n_est_pas_expire() {
    let engine = AlertEngine::new();
    let rules = vec![rule("exp", AlertKind::Expired)];
    assert!(engine.evaluate(AiService::Gemini, AiState::NotConnected, rules, NOW).is_empty());
}

// --- Règles par défaut et enregistrement ---

#[test]
fn regles_par_defaut() {
    let rules = default_alert_rules();
    let kinds: Vec<AlertKind> = rules.iter().map(|r| r.kind.clone()).collect();
    assert_eq!(
        kinds,
        vec![
            AlertKind::Threshold { window_index: 0, percent: 80.0 },
            AlertKind::Threshold { window_index: 1, percent: 90.0 },
            AlertKind::Available { after_percent: 80.0 },
            AlertKind::Expired,
            AlertKind::Projection { minutes: 30 },
        ]
    );
    assert!(rules.iter().all(|r| r.enabled && r.service.is_none()));
}

#[test]
fn json_aller_retour() {
    let mut rules = default_alert_rules();
    rules[1].enabled = false;
    rules.push(AlertRule {
        id: "perso".to_string(),
        enabled: true,
        service: Some(AiService::ChatGpt),
        kind: AlertKind::Threshold { window_index: 2, percent: 55.0 },
    });
    assert_eq!(alert_rules_from_json(alert_rules_to_json(rules.clone())), rules);
    // Liste vide : l'utilisateur a tout supprimé, on ne remet pas les défauts.
    assert_eq!(alert_rules_from_json("[]".to_string()), vec![]);
}

#[test]
fn json_tolerant() {
    // Illisible : règles par défaut.
    assert_eq!(alert_rules_from_json("pas du json".to_string()), default_alert_rules());
    assert_eq!(alert_rules_from_json("{}".to_string()), default_alert_rules());

    // Règles invalides ignorées, valeurs hors bornes ramenées dans les bornes.
    let json = r#"[
        {"id": "a", "kind": "threshold", "percent": 150},
        {"id": "b", "kind": "inconnu"},
        {"kind": "expired"},
        {"id": "c", "kind": "available"},
        {"id": "d", "kind": "expired", "service": "inconnu"},
        {"id": "e", "kind": "expired", "service": "gemini", "enabled": false}
    ]"#;
    let rules = alert_rules_from_json(json.to_string());
    assert_eq!(ids_of(&rules), vec!["a", "e"]);
    assert_eq!(rules[0].kind, AlertKind::Threshold { window_index: 0, percent: 100.0 });
    assert!(rules[0].enabled);
    assert_eq!(rules[1].service, Some(AiService::Gemini));
    assert!(!rules[1].enabled);
}

fn ids_of(rules: &[AlertRule]) -> Vec<&str> {
    rules.iter().map(|r| r.id.as_str()).collect()
}

// --- Projection ---

fn projection_rule(minutes: u32) -> AlertRule {
    rule("proj", AlertKind::Projection { minutes })
}

/// Une session à `percent`, réinitialisée à `resets_at`, pleine à `full_at`.
fn projected(percent: f64, resets_at: i64, full_at: Option<i64>) -> AiState {
    AiState::Ok(AiUsage {
        windows: vec![UsageWindow {
            label: "Session".to_string(),
            percent,
            resets_at: Some(resets_at),
            projected_full_at: full_at,
        }],
    })
}

#[test]
fn projection_moins_de_30_min() {
    let engine = AlertEngine::new();
    let rules = vec![projection_rule(30)];
    let reset = NOW + 2 * HOUR;

    // Plein dans 31 min : trop loin.
    assert!(engine.evaluate(AiService::Claude, projected(70.0, reset, Some(NOW + 31 * 60)), rules.clone(), NOW).is_empty());
    // Plein dans 30 min : notification.
    let events = engine.evaluate(AiService::Claude, projected(75.0, reset, Some(NOW + 30 * 60)), rules.clone(), NOW);
    assert_eq!(
        events[0].kind,
        AlertEventKind::Projection {
            window_label: "Session".to_string(),
            percent: 75.0,
            full_at: NOW + 30 * 60,
        }
    );
}

#[test]
fn projection_absente_ne_declenche_rien() {
    let engine = AlertEngine::new();
    let state = projected(99.0, NOW + HOUR, None);
    assert!(engine.evaluate(AiService::Claude, state, vec![projection_rule(30)], NOW).is_empty());
}

#[test]
fn projection_une_seule_fois_par_fenetre() {
    let engine = AlertEngine::new();
    let rules = vec![projection_rule(30)];
    let reset = NOW + 2 * HOUR;
    let eval = |state, now| engine.evaluate(AiService::Claude, state, rules.clone(), now);

    assert_eq!(eval(projected(80.0, reset, Some(NOW + 20 * 60)), NOW).len(), 1);
    assert!(eval(projected(85.0, reset, Some(NOW + 15 * 60)), NOW + 60).is_empty());
    // La consommation ralentit (plus de projection), puis repart : même fenêtre, pas de rappel.
    assert!(eval(projected(85.0, reset, None), NOW + 120).is_empty());
    assert!(eval(projected(88.0, reset, Some(NOW + 600)), NOW + 180).is_empty());

    // Nouvelle fenêtre : l'alerte est réarmée.
    let later = reset + 60;
    let new_reset = reset + 5 * HOUR;
    assert!(eval(projected(1.0, new_reset, None), later).is_empty());
    assert_eq!(eval(projected(70.0, new_reset, Some(later + 600)), later + 60).len(), 1);
}

#[test]
fn projection_delai_personnalise() {
    let engine = AlertEngine::new();
    let state = projected(50.0, NOW + 3 * HOUR, Some(NOW + 50 * 60));
    assert!(engine.evaluate(AiService::Claude, state.clone(), vec![projection_rule(30)], NOW).is_empty());
    // Délai porté à 60 min : la règle a changé, elle se déclenche.
    assert_eq!(engine.evaluate(AiService::Claude, state, vec![projection_rule(60)], NOW).len(), 1);
}

#[test]
fn projection_en_json() {
    let rules = vec![projection_rule(45)];
    assert_eq!(alert_rules_from_json(alert_rules_to_json(rules.clone())), rules);
    // Délai absent : 30 min.
    let parsed = alert_rules_from_json(r#"[{"id": "p", "kind": "projection"}]"#.to_string());
    assert_eq!(parsed[0].kind, AlertKind::Projection { minutes: 30 });
}
