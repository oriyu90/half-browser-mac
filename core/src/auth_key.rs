//! Ported from Android `core/AuthAttemptTracker`-related key scoping.

pub struct AuthKey;

impl AuthKey {
    pub fn of(scheme: &str, host: &str, port: i32, realm: &str) -> String {
        format!("{}://{}:{}|{}", scheme.to_lowercase(), host.trim().to_lowercase(), port, realm.trim())
    }
}