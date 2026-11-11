//! Cœur de Pulse : réseau, parsing, cache, alertes et projection.

uniffi::setup_scaffolding!();

pub mod alerts;
pub mod chatgpt;
pub mod claude;
pub mod claude_web;
pub mod copilot;
pub mod gemini;
pub mod http;
pub mod model;
pub mod monitor;
pub mod projection;
pub mod update;
