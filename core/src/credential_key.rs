//! Ported from Android `core/CredentialKey.kt`.

pub struct CredentialKey;

impl CredentialKey {
    pub fn of(scheme: &str, host: &str, port: i32, realm: &str) -> String {
        format!("{}://{}:{}|{}", scheme.to_lowercase(), host.trim().to_lowercase(), port, realm.trim())
    }
}