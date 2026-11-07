//! Cœur de Pulse : réseau, parsing, cache, alertes et projection.

uniffi::setup_scaffolding!();

pub mod claude;
pub mod claude_web;
pub mod http;
pub mod model;
pub mod monitor;
