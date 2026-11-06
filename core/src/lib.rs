//! Cœur de Pulse : réseau, parsing, cache, alertes et projection.

uniffi::setup_scaffolding!();

pub mod claude;
pub mod model;
pub mod monitor;
