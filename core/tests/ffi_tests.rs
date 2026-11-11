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

// ============================================================
// FFI boundary tests: the C surface must behave like the Rust rules.
// ============================================================
use half_browser_core::ffi;
use std::ffi::{CStr, CString};

#[test]
fn ffi_dialog_budget_enforces_the_limit() {
    let b = ffi::hb_dialog_budget_new();
    assert!(!b.is_null());
    // 12 dialogs allowed, each 250 ms apart.
    for i in 0..12i64 {
        assert_eq!(1, ffi::hb_dialog_budget_allow(b, 1_000_000 + i * 250), "dialog {i}");
    }
    assert_eq!(0, ffi::hb_dialog_budget_allow(b, 1_000_000 + 12 * 250));
    assert_eq!(1, ffi::hb_dialog_budget_blocked(b));
    ffi::hb_dialog_budget_reset(b);
    assert_eq!(0, ffi::hb_dialog_budget_blocked(b));
    assert_eq!(1, ffi::hb_dialog_budget_allow(b, 9_000_000));
    ffi::hb_dialog_budget_free(b);
}

#[test]
fn ffi_dialog_budget_null_is_fail_open() {
    // A null handle must never suppress a dialog: failing open is the safe
    // direction for a UI budget.
    assert_eq!(1, ffi::hb_dialog_budget_allow(std::ptr::null_mut(), 0));
    assert_eq!(1, ffi::hb_dialog_budget_allow_before_unload(std::ptr::null_mut()));
    assert_eq!(0, ffi::hb_dialog_budget_blocked(std::ptr::null_mut()));
    ffi::hb_dialog_budget_free(std::ptr::null_mut());
}

#[test]
fn ffi_js_guard_script_round_trips() {
    let p = ffi::hb_js_guard_script();
    assert!(!p.is_null());
    let s = unsafe { CStr::from_ptr(p) }.to_str().unwrap().to_string();
    assert!(s.starts_with("(function ()"));
    assert!(s.contains("__hbJsGuardInstalled"));
    ffi::hb_free_string(p);
}

#[test]
fn ffi_vpn_parse_reports_success_and_endpoint() {
    let cfg = "[Interface]\nPrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\nAddress = 10.0.0.2/32\n\n[Peer]\nPublicKey = ERERERERERERERERERERERERERERERERERERERERERE=\nEndpoint = vpn.example.com:51820\nAllowedIPs = 0.0.0.0/0\n";
    let c = CString::new(cfg).unwrap();
    let mut ep: *mut std::os::raw::c_char = std::ptr::null_mut();
    let mut err: *mut std::os::raw::c_char = std::ptr::null_mut();
    let code = ffi::hb_vpn_parse(c.as_ptr(), &mut ep, &mut err);
    assert_eq!(0, code);
    assert!(!ep.is_null());
    let s = unsafe { CStr::from_ptr(ep) }.to_str().unwrap().to_string();
    assert_eq!("vpn.example.com:51820", s);
    ffi::hb_free_string(ep);
    if !err.is_null() {
        ffi::hb_free_string(err);
    }
}

#[test]
fn ffi_vpn_parse_reports_errors_without_crashing() {
    let mut ep: *mut std::os::raw::c_char = std::ptr::null_mut();
    let mut err: *mut std::os::raw::c_char = std::ptr::null_mut();
    // Null input.
    assert_eq!(-2, ffi::hb_vpn_parse(std::ptr::null(), &mut ep, &mut err));
    // Empty config.
    let c = CString::new("").unwrap();
    let code = ffi::hb_vpn_parse(c.as_ptr(), &mut ep, &mut err);
    assert!(code > 0, "expected an error code, got {code}");
    assert!(ep.is_null());
    if !err.is_null() {
        ffi::hb_free_string(err);
    }
    // Null out-pointers must be refused, not dereferenced.
    assert_eq!(-1, ffi::hb_vpn_parse(c.as_ptr(), std::ptr::null_mut(), std::ptr::null_mut()));
}

#[test]
fn ffi_vpn_tune_and_classify() {
    let cfg = "[Interface]\nPrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n\n[Peer]\nPublicKey = ERERERERERERERERERERERERERERERERERERERERERE=\nEndpoint = a.example:1\nAllowedIPs = 0.0.0.0/0\n";
    let c = CString::new(cfg).unwrap();
    let out = ffi::hb_vpn_tune(c.as_ptr(), 25);
    assert!(!out.is_null());
    let s = unsafe { CStr::from_ptr(out) }.to_str().unwrap().to_string();
    assert!(s.contains("PersistentKeepalive = 25"));
    assert!(s.contains("MTU = 1280"));
    ffi::hb_free_string(out);
    assert!(ffi::hb_vpn_tune(std::ptr::null(), 25).is_null());

    // classify: no handshake, well past grace -> Unreachable(4)
    assert_eq!(4, ffi::hb_vpn_classify(1_000_000, 0, 1_000_000 + 60_000, 0));
    // inside grace -> Verifying(1)
    assert_eq!(1, ffi::hb_vpn_classify(1_000_000, 0, 1_000_000 + 1_000, 0));
    // fresh handshake -> Healthy(2)
    assert_eq!(2, ffi::hb_vpn_classify(1_000_000, 1_000_000 + 1_000, 1_000_000 + 5_000, 0));
}

#[test]
fn ffi_vpn_parse_handshakes() {
    let out = CString::new("a=\t1700000000\nb=\t1700000500\n").unwrap();
    assert_eq!(1_700_000_500_000, ffi::hb_vpn_parse_handshakes(out.as_ptr()));
    assert_eq!(0, ffi::hb_vpn_parse_handshakes(std::ptr::null()));
}

#[test]
fn ffi_vpn_next_poll_delay_matches_the_rules() {
    // Foreground is always the fast interval.
    assert_eq!(10_000, ffi::hb_vpn_next_poll_delay(true, 2, 99));
    // Background, healthy, first step.
    assert_eq!(90_000, ffi::hb_vpn_next_poll_delay(false, 2, 1));
    // Background, not healthy, stays fast.
    assert_eq!(60_000, ffi::hb_vpn_next_poll_delay(false, 3, 9));
}
