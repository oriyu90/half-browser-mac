//! Ported from Android `core/TrustPolicy.kt`.

#[derive(Debug, Clone, PartialEq)]
pub enum TrustDecision {
    Trusted,
    Unknown,
    Changed { previous_host: String, previous_port: i32, previous_fingerprint: String },
}

pub struct TrustPolicy;

impl TrustPolicy {
    pub fn normalize_fingerprint(raw: &str) -> String {
        raw.to_lowercase().replace(':', "").replace(' ', "").trim().to_string()
    }

    pub fn format_fingerprint(normalized: &str) -> String {
        let hex = Self::normalize_fingerprint(normalized);
        if hex.len() != 64 {
            return normalized.to_string();
        }
        let chars: Vec<char> = hex.chars().collect();
        chars
            .chunks(2)
            .map(|c| c.iter().collect::<String>().to_uppercase())
            .collect::<Vec<_>>()
            .join(":")
    }

    pub fn decide(
        host: &str,
        port: i32,
        fingerprint_sha256: &str,
        saved_host: Option<&str>,
        saved_port: i32,
        saved_fingerprint: Option<&str>,
    ) -> TrustDecision {
        let normalized_host = host.trim().to_lowercase();
        let _normalized_fp = Self::normalize_fingerprint(fingerprint_sha256);
        match (saved_host, saved_fingerprint) {
            (Some(sh), Some(sf)) if sh.trim().to_lowercase() == normalized_host => {
                if saved_port != 0 && port != 0 && saved_port != port {
                    return TrustDecision::Unknown;
                }
                if Self::normalize_fingerprint(sf) == Self::normalize_fingerprint(fingerprint_sha256) {
                    TrustDecision::Trusted
                } else {
                    TrustDecision::Changed {
                        previous_host: sh.to_string(),
                        previous_port: saved_port,
                        previous_fingerprint: sf.to_string(),
                    }
                }
            }
            _ => TrustDecision::Unknown,
        }
    }

    pub fn can_pin(primary_error: i32) -> bool {
        primary_error == 3 // SSL_UNTRUSTED
    }
}