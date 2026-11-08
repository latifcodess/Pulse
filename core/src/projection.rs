//! La projection : à quelle heure une limite serait atteinte au rythme actuel.
//!
//! On garde les mesures (heure, %) de la fenêtre en cours, puis on trace la
//! droite qui passe au plus près des mesures des 30 dernières minutes
//! (régression linéaire). Sa pente est la vitesse de consommation.

use std::collections::HashMap;

use crate::alerts::is_new_window;
use crate::model::{AiService, AiUsage, UsageWindow};

/// Durée de l'historique gardé pour chaque limite.
pub const HISTORY_SECONDS: i64 = 2 * 3600;
/// Seules les mesures de cette période servent au calcul de la vitesse.
pub const REGRESSION_SECONDS: i64 = 30 * 60;
/// Nombre minimal de mesures pour calculer une vitesse.
pub const MIN_POINTS: usize = 3;

/// Une mesure : heure (secondes Unix) et % utilisé.
pub type Sample = (i64, f64);

/// L'historique d'une limite, pour la fenêtre en cours.
#[derive(Debug, Default)]
struct WindowHistory {
    /// La dernière valeur reçue, pour reconnaître le début d'une nouvelle fenêtre.
    last: Option<UsageWindow>,
    samples: Vec<Sample>,
}

/// Les historiques de toutes les limites, gardés en mémoire seulement.
#[derive(Debug, Default)]
pub struct UsageHistory {
    windows: HashMap<(AiService, String), WindowHistory>,
}

impl UsageHistory {
    /// Enregistre les nouvelles valeurs d'un service, et renvoie l'usage avec
    /// la projection de chaque limite.
    pub fn record(&mut self, service: AiService, usage: &AiUsage, now: i64) -> AiUsage {
        let windows = usage
            .windows
            .iter()
            .map(|window| {
                let history = self.windows.entry((service, window.label.clone())).or_default();

                // Nouvelle fenêtre : l'historique repart de zéro.
                if let Some(last) = &history.last
                    && is_new_window(last, window, now)
                {
                    history.samples.clear();
                }
                // Plus de 2 h : oublié. Même seconde : remplacé par la nouvelle mesure.
                history.samples.retain(|(time, _)| *time > now - HISTORY_SECONDS && *time < now);
                history.samples.push((now, window.percent));
                history.last = Some(window.clone());

                UsageWindow {
                    projected_full_at: projected_full_at(&history.samples, window.resets_at, now),
                    ..window.clone()
                }
            })
            .collect();
        AiUsage { windows }
    }

    /// Les mesures gardées pour une limite (utile aux tests).
    pub fn samples(&self, service: AiService, label: &str) -> Vec<Sample> {
        self.windows
            .get(&(service, label.to_string()))
            .map(|history| history.samples.clone())
            .unwrap_or_default()
    }
}

/// L'heure à laquelle 100 % serait atteint. None s'il y a moins de 3 mesures
/// dans les 30 dernières minutes, si la vitesse est nulle ou négative, ou si
/// la limite se réinitialise avant.
pub fn projected_full_at(samples: &[Sample], resets_at: Option<i64>, now: i64) -> Option<i64> {
    let recent: Vec<Sample> = samples
        .iter()
        .copied()
        .filter(|(time, _)| *time >= now - REGRESSION_SECONDS)
        .collect();
    if recent.len() < MIN_POINTS {
        return None;
    }
    let speed = speed_per_second(&recent)?;
    if speed <= 0.0 {
        return None;
    }

    // On part de la dernière mesure, pas de la droite : c'est la valeur
    // que l'utilisateur voit.
    let (last_time, last_percent) = *recent.last()?;
    let seconds_left = (100.0 - last_percent).max(0.0) / speed;
    let full_at = last_time + seconds_left.round() as i64;

    match resets_at {
        Some(reset) if full_at >= reset => None,
        _ => Some(full_at),
    }
}

/// La pente de la droite des moindres carrés, en % par seconde :
///
///   pente = Σ (t − t̄)(p − p̄) / Σ (t − t̄)²
///
/// où t̄ et p̄ sont les moyennes des heures et des %. None si toutes les
/// mesures ont la même heure (pas de droite possible).
pub fn speed_per_second(samples: &[Sample]) -> Option<f64> {
    let count = samples.len() as f64;
    // Heures relatives à la première mesure : évite de manipuler des nombres
    // de l'ordre du milliard au carré.
    let origin = samples.first()?.0;
    let times: Vec<f64> = samples.iter().map(|(time, _)| (time - origin) as f64).collect();
    let mean_time = times.iter().sum::<f64>() / count;
    let mean_percent = samples.iter().map(|(_, percent)| percent).sum::<f64>() / count;

    let mut covariance = 0.0;
    let mut variance = 0.0;
    for (time, (_, percent)) in times.iter().zip(samples) {
        covariance += (time - mean_time) * (percent - mean_percent);
        variance += (time - mean_time).powi(2);
    }
    if variance == 0.0 {
        return None;
    }
    Some(covariance / variance)
}
