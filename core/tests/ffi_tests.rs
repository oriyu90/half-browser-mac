//! Integration tests for the core logic that the C FFI surface delegates to.

use half_browser_core::accent_math::AccentMath;
use half_browser_core::backup_crypto::BackupCrypto;
use half_browser_core::history::HistoryRules;
use half_browser_core::models::HistoryEntry;
use half_browser_core::trust_policy::{TrustDecision, TrustPolicy};
use half_browser_core::url_normalizer::UrlNormalizer;

const DDG: &str = "https://duckduckgo.com/?q=%s";

#[test]
fn trust_decide_unknown_without_pin() {
    let d = TrustPolicy::decide("example.com", 443, "abc", None, 0, None);
    assert_eq!(d, TrustDecision::Unknown);
}

#[test]
fn trust_decide_trusted_on_match() {
    let d = TrustPolicy::decide("example.com", 443, "AB:CD", Some("example.com"), 443, Some("abcd"));
    assert_eq!(d, TrustDecision::Trusted);
}

#[test]
fn trust_decide_changed_on_mismatch() {
    let d = TrustPolicy::decide("example.com", 443, "ffff", Some("example.com"), 443, Some("abcd"));
    assert!(matches!(d, TrustDecision::Changed { .. }));
}

#[test]
fn trust_decide_port_mismatch_is_unknown() {
    let d = TrustPolicy::decide("example.com", 8443, "abcd", Some("example.com"), 443, Some("abcd"));
    assert_eq!(d, TrustDecision::Unknown);
}

#[test]
fn normalize_url_host_like() {
    assert_eq!(
        UrlNormalizer::to_navigable("example.com", DDG),
        Some("https://example.com/".to_string())
    );
}

#[test]
fn normalize_url_search() {
    let u = UrlNormalizer::to_navigable("hello world", DDG).unwrap();
    assert!(u.starts_with("https://duckduckgo.com/?q=hello"));
}

#[test]
fn normalize_url_rejects_javascript() {
    assert_eq!(UrlNormalizer::to_navigable("javascript:alert(1)", DDG), None);
}

#[test]
fn accent_palette_contrast_is_readable() {
    let p = AccentMath::palette(210.0, 0.8, 0.5, true);
    assert!(AccentMath::contrast_ratio(p.primary, p.on_primary) >= 4.5);
    let l = AccentMath::palette(30.0, 0.9, 0.5, false);
    assert!(AccentMath::contrast_ratio(l.primary, l.on_primary) >= 4.5);
}

#[test]
fn backup_roundtrip() {
    let pass = b"correct horse battery";
    let enc = BackupCrypto::encrypt("{\"a\":1}", pass).expect("encrypt");
    let dec = BackupCrypto::decrypt(&enc, pass).expect("decrypt");
    assert_eq!(dec, "{\"a\":1}");
}

#[test]
fn backup_wrong_passphrase_fails() {
    let enc = BackupCrypto::encrypt("secret", b"correct horse battery").unwrap();
    assert!(BackupCrypto::decrypt(&enc, b"wrong passphrase!").is_none());
}

#[test]
fn backup_short_passphrase_rejected() {
    assert!(BackupCrypto::encrypt("secret", b"short").is_none());
}

#[test]
fn history_merges_recent_visit() {
    let now = 1_000_000i64;
    let first = HistoryRules::record(&[], "https://example.com/a", "A", now);
    assert_eq!(first.len(), 1);
    assert_eq!(first[0].visit_count, 1);

    let second = HistoryRules::record(&first, "https://example.com/a", "A", now + 1000);
    assert_eq!(second.len(), 1, "recent visit must merge");
    assert_eq!(second[0].visit_count, 1);
}

#[test]
fn history_counts_old_visit() {
    let now = 10_000_000i64;
    let first = HistoryRules::record(&[], "https://example.com/a", "A", now);
    let later = HistoryRules::record(&first, "https://example.com/a", "A", now + 60 * 60 * 1000);
    assert_eq!(later[0].visit_count, 2);
}

#[test]
fn history_rejects_non_web_url() {
    let r = HistoryRules::record(&[], "file:///etc/passwd", "x", 0);
    assert!(r.is_empty());
}

#[test]
fn history_caps_at_max() {
    let mut entries: Vec<HistoryEntry> = Vec::new();
    for i in 0..(HistoryRules::MAX_ENTRIES + 50) {
        entries = HistoryRules::record(&entries, &format!("https://example.com/{}", i), "t", i as i64);
    }
    assert_eq!(entries.len(), HistoryRules::MAX_ENTRIES);
}
