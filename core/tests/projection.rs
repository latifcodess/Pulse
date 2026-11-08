use pulse_core::model::{AiService, AiUsage, UsageWindow};
use pulse_core::projection::{UsageHistory, projected_full_at, speed_per_second};

const T0: i64 = 1_794_000_000;
const MIN: i64 = 60;
const HOUR: i64 = 3600;

/// L'exemple de l'explication : 40, 43, 45, 49 % toutes les 10 minutes.
fn example() -> Vec<(i64, f64)> {
    vec![(T0, 40.0), (T0 + 10 * MIN, 43.0), (T0 + 20 * MIN, 45.0), (T0 + 30 * MIN, 49.0)]
}

fn usage(percent: f64, resets_at: Option<i64>) -> AiUsage {
    AiUsage {
        windows: vec![UsageWindow {
            label: "Session".to_string(),
            percent,
            resets_at,
            projected_full_at: None,
        }],
    }
}

// --- Calcul ---

#[test]
fn exemple_chiffre() {
    let speed = speed_per_second(&example()).unwrap();
    // 8 700 / 1 800 000 = 0,004 833 % par seconde, soit 17,4 % par heure.
    assert!((speed - 8_700.0 / 1_800_000.0).abs() < 1e-12);
    assert!((speed * 3600.0 - 17.4).abs() < 1e-9);

    // Il reste 51 % : 51 / 0,004 833 = 10 552 s (2 h 55 min 52 s) après 49 %.
    let now = T0 + 30 * MIN;
    assert_eq!(projected_full_at(&example(), Some(T0 + 4 * HOUR), now), Some(now + 10_552));
}

#[test]
fn moins_de_3_points_donne_none() {
    let now = T0 + 10 * MIN;
    assert_eq!(projected_full_at(&[], None, now), None);
    assert_eq!(projected_full_at(&[(T0, 40.0)], None, now), None);
    assert_eq!(projected_full_at(&[(T0, 40.0), (now, 50.0)], None, now), None);
}

#[test]
fn seules_les_30_dernieres_minutes_comptent() {
    // 3 points, mais le premier a 40 min : il reste 2 points récents.
    let now = T0 + 40 * MIN;
    let samples = [(T0, 10.0), (T0 + 30 * MIN, 40.0), (now, 50.0)];
    assert_eq!(projected_full_at(&samples, None, now), None);

    // Un ancien point très différent ne change pas le résultat.
    let mut with_old = vec![(T0 - 60 * MIN, 0.0)];
    with_old.extend(example());
    let now = T0 + 30 * MIN;
    assert_eq!(projected_full_at(&with_old, None, now), projected_full_at(&example(), None, now));
}

#[test]
fn vitesse_nulle_ou_negative_donne_none() {
    let now = T0 + 20 * MIN;
    let flat = [(T0, 40.0), (T0 + 10 * MIN, 40.0), (now, 40.0)];
    assert_eq!(speed_per_second(&flat), Some(0.0));
    assert_eq!(projected_full_at(&flat, None, now), None);

    let falling = [(T0, 40.0), (T0 + 10 * MIN, 35.0), (now, 30.0)];
    assert!(speed_per_second(&falling).unwrap() < 0.0);
    assert_eq!(projected_full_at(&falling, None, now), None);
}

#[test]
fn toutes_les_mesures_a_la_meme_heure_donne_none() {
    assert_eq!(speed_per_second(&[(T0, 10.0), (T0, 20.0), (T0, 30.0)]), None);
    assert_eq!(projected_full_at(&[(T0, 10.0), (T0, 20.0), (T0, 30.0)], None, T0), None);
}

#[test]
fn plein_apres_le_reset_donne_none() {
    let now = T0 + 30 * MIN;
    let full_at = now + 10_552;
    assert_eq!(projected_full_at(&example(), Some(full_at + 1), now), Some(full_at));
    // Atteint pile au reset, ou après : la limite repart avant, pas d'alerte.
    assert_eq!(projected_full_at(&example(), Some(full_at), now), None);
    assert_eq!(projected_full_at(&example(), Some(now + HOUR), now), None);
}

#[test]
fn heure_de_reset_inconnue_garde_la_projection() {
    let now = T0 + 30 * MIN;
    assert_eq!(projected_full_at(&example(), None, now), Some(now + 10_552));
}

#[test]
fn deja_a_100_donne_l_heure_de_la_derniere_mesure() {
    let now = T0 + 20 * MIN;
    let samples = [(T0, 80.0), (T0 + 10 * MIN, 95.0), (now, 100.0)];
    assert_eq!(projected_full_at(&samples, None, now), Some(now));
}

// --- Historique ---

#[test]
fn historique_projection_apres_3_mesures() {
    let mut history = UsageHistory::default();
    let reset = Some(T0 + 4 * HOUR);
    let mut last = None;
    for (time, percent) in example() {
        last = history.record(AiService::Claude, &usage(percent, reset), time).windows[0].projected_full_at;
        if time < T0 + 20 * MIN {
            assert_eq!(last, None, "moins de 3 mesures à {time}");
        }
    }
    assert_eq!(last, Some(T0 + 30 * MIN + 10_552));
}

#[test]
fn historique_vide_au_reset() {
    let mut history = UsageHistory::default();
    let reset = T0 + 25 * MIN;
    for (time, percent) in [(T0, 40.0), (T0 + 10 * MIN, 50.0), (T0 + 20 * MIN, 60.0)] {
        history.record(AiService::Claude, &usage(percent, Some(reset)), time);
    }
    assert_eq!(history.samples(AiService::Claude, "Session").len(), 3);

    // Le reset est passé : le moniteur envoie la limite remise à 0 (voir as_of).
    let after = T0 + 30 * MIN;
    let projected = history.record(AiService::Claude, &usage(40.0, Some(reset)).as_of(after), after);
    assert_eq!(history.samples(AiService::Claude, "Session"), vec![(after, 0.0)]);
    assert_eq!(projected.windows[0].projected_full_at, None);

    // L'heure de reset avance aussi quand une nouvelle fenêtre est annoncée.
    let mut history = UsageHistory::default();
    history.record(AiService::Claude, &usage(70.0, Some(T0 + HOUR)), T0);
    history.record(AiService::Claude, &usage(2.0, Some(T0 + 6 * HOUR)), T0 + MIN);
    assert_eq!(history.samples(AiService::Claude, "Session"), vec![(T0 + MIN, 2.0)]);
}

#[test]
fn historique_limite_a_2_heures() {
    let mut history = UsageHistory::default();
    // Une mesure toutes les 10 min pendant 3 h, sans reset.
    for step in 0..=18 {
        history.record(AiService::Claude, &usage(step as f64, None), T0 + step * 10 * MIN);
    }
    let samples = history.samples(AiService::Claude, "Session");
    let now = T0 + 180 * MIN;
    assert!(samples.iter().all(|(time, _)| *time > now - 2 * HOUR));
    assert_eq!(samples.len(), 12);
}

#[test]
fn meme_seconde_remplace_la_mesure() {
    let mut history = UsageHistory::default();
    history.record(AiService::Claude, &usage(10.0, None), T0);
    history.record(AiService::Claude, &usage(11.0, None), T0);
    assert_eq!(history.samples(AiService::Claude, "Session"), vec![(T0, 11.0)]);
}

#[test]
fn chaque_limite_et_service_a_son_historique() {
    let mut history = UsageHistory::default();
    history.record(AiService::Claude, &usage(10.0, None), T0);
    history.record(AiService::Gemini, &usage(50.0, None), T0);
    assert_eq!(history.samples(AiService::Claude, "Session"), vec![(T0, 10.0)]);
    assert_eq!(history.samples(AiService::Gemini, "Session"), vec![(T0, 50.0)]);
    assert!(history.samples(AiService::Claude, "Semaine").is_empty());
}
