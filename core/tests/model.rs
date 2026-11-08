use pulse_core::model::{AiUsage, UsageWindow};

fn usage(percent: f64, resets_at: Option<i64>) -> AiUsage {
    AiUsage {
        windows: vec![UsageWindow {
            label: "Session (5 h)".to_string(),
            percent,
            resets_at,
            projected_full_at: None,
        }],
    }
}

#[test]
fn reset_a_venir_ne_change_rien() {
    assert_eq!(usage(49.0, Some(101)).as_of(100), usage(49.0, Some(101)));
}

#[test]
fn reset_atteint_ou_passe_repart_a_zero() {
    assert_eq!(usage(49.0, Some(100)).as_of(100), usage(0.0, None));
    assert_eq!(usage(49.0, Some(99)).as_of(100), usage(0.0, None));
}

#[test]
fn heure_de_reset_inconnue_ne_change_rien() {
    assert_eq!(usage(49.0, None).as_of(100), usage(49.0, None));
}
