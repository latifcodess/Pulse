use pulse_core::claude::{ParseError, parse_claude_usage};

#[test]
fn cas_normal_donne_les_deux_fenetres() {
    let usage = parse_claude_usage(include_str!("fixtures/claude.json")).unwrap();

    assert_eq!(usage.windows.len(), 2);

    assert_eq!(usage.windows[0].label, "Session (5 h)");
    assert_eq!(usage.windows[0].percent, 49.0);
    assert_eq!(usage.windows[0].resets_at, Some(1793585400));

    assert_eq!(usage.windows[1].label, "Semaine");
    assert_eq!(usage.windows[1].percent, 12.5);
    assert_eq!(usage.windows[1].resets_at, Some(1794128400));
}

#[test]
fn fenetre_manquante_garde_l_autre() {
    let usage = parse_claude_usage(r#"{"seven_day": {"utilization": 12.5}}"#).unwrap();

    assert_eq!(usage.windows.len(), 1);
    assert_eq!(usage.windows[0].label, "Semaine");
}

#[test]
fn pourcentage_manquant_ignore_la_fenetre() {
    let json = r#"{
        "five_hour": {"resets_at": "2026-11-02T02:10:00+00:00"},
        "seven_day": {"utilization": 12.5}
    }"#;
    let usage = parse_claude_usage(json).unwrap();

    assert_eq!(usage.windows.len(), 1);
    assert_eq!(usage.windows[0].label, "Semaine");
}

#[test]
fn reset_manquant_nul_ou_illisible_donne_none() {
    for resets_at in [r#""#, r#", "resets_at": null"#, r#", "resets_at": "demain""#] {
        let json = format!(r#"{{"five_hour": {{"utilization": 49.0{resets_at}}}}}"#);
        let usage = parse_claude_usage(&json).unwrap();

        assert_eq!(usage.windows[0].percent, 49.0);
        assert_eq!(usage.windows[0].resets_at, None);
    }
}

#[test]
fn pourcentage_hors_limites_est_ramene_entre_0_et_100() {
    let json = r#"{
        "five_hour": {"utilization": 130.0},
        "seven_day": {"utilization": -5.0}
    }"#;
    let usage = parse_claude_usage(json).unwrap();

    assert_eq!(usage.windows[0].percent, 100.0);
    assert_eq!(usage.windows[1].percent, 0.0);
}

#[test]
fn aucune_fenetre_exploitable_donne_no_usable_data() {
    for json in ["{}", "[]", "null", r#"{"five_hour": null}"#, r#"{"five_hour": {"utilization": "49"}}"#] {
        assert_eq!(parse_claude_usage(json), Err(ParseError::NoUsableData));
    }
}

#[test]
fn json_invalide_donne_invalid_json() {
    for json in ["", "pas du json", r#"{"five_hour": "#] {
        assert_eq!(parse_claude_usage(json), Err(ParseError::InvalidJson));
    }
}
