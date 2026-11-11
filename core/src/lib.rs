//! Pure-logic core for Half-Browser (macOS port).
//!
//! Ported from the Android `core/` package (`com.yukiorita.halfbrowser.core`).
//! This crate has NO OS dependencies: no AppKit, no CEF, no Keychain.
//! All functions are deterministic and unit-testable.

pub mod url_normalizer;
pub mod trust_policy;
pub mod accent_math;
pub mod backup_crypto;
pub mod history;
pub mod codecs;
pub mod grid_policy;
pub mod auth_key;
pub mod credential_key;
pub mod models;
pub mod vpn_config;
pub mod vpn_health;
pub mod vpn_tuning;
pub mod ffi;