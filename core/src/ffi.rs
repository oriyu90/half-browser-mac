//! FFI bridge for C/C++/Swift interop via cbindgen.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

#[repr(C)]
pub struct TrustDecisionFFI {
    pub tag: i32,
}

#[repr(C)]
pub struct AccentPaletteFFI {
    pub primary: u32,
    pub on_primary: u32,
    pub primary_container: u32,
    pub on_primary_container: u32,
    pub secondary: u32,
    pub on_secondary: u32,
    pub secondary_container: u32,
    pub on_secondary_container: u32,
    pub tertiary: u32,
    pub on_tertiary: u32,
    pub tertiary_container: u32,
    pub on_tertiary_container: u32,
}

#[repr(C)]
pub struct EncryptedFFI {
    pub salt: *mut c_char,
    pub iv: *mut c_char,
    pub ciphertext: *mut c_char,
    pub iterations: u32,
}

#[unsafe(no_mangle)]
pub extern "C" fn hb_trust_decide(
    host: *const c_char,
    port: i32,
    fingerprint: *const c_char,
    saved_host: *const c_char,
    saved_port: i32,
    saved_fingerprint: *const c_char,
) -> i32 {
    let host = unsafe { CStr::from_ptr(host).to_str().unwrap_or("") };
    let fingerprint = unsafe { CStr::from_ptr(fingerprint).to_str().unwrap_or("") };
    let saved_host = if saved_host.is_null() {
        None
    } else {
        Some(unsafe { CStr::from_ptr(saved_host).to_str().unwrap_or("") })
    };
    let saved_fingerprint = if saved_fingerprint.is_null() {
        None
    } else {
        Some(unsafe { CStr::from_ptr(saved_fingerprint).to_str().unwrap_or("") })
    };

    let decision = crate::trust_policy::TrustPolicy::decide(
        host, port, fingerprint,
        saved_host, saved_port, saved_fingerprint,
    );
    match decision {
        crate::trust_policy::TrustDecision::Trusted => 0,
        crate::trust_policy::TrustDecision::Unknown => 1,
        crate::trust_policy::TrustDecision::Changed { .. } => 2,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn hb_normalize_url(input: *const c_char, search_template: *const c_char) -> *mut c_char {
    let input = unsafe { CStr::from_ptr(input).to_str().unwrap_or("") };
    let template = unsafe { CStr::from_ptr(search_template).to_str().unwrap_or("") };
    match crate::url_normalizer::UrlNormalizer::to_navigable(input, template) {
        Some(url) => CString::new(url).unwrap().into_raw(),
        None => std::ptr::null_mut(),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn hb_accent_palette(hue: f32, saturation: f32, tone: f32, dark: bool, out: *mut AccentPaletteFFI) {
    let palette = crate::accent_math::AccentMath::palette(hue, saturation, tone, dark);
    unsafe {
        (*out).primary = palette.primary;
        (*out).on_primary = palette.on_primary;
        (*out).primary_container = palette.primary_container;
        (*out).on_primary_container = palette.on_primary_container;
        (*out).secondary = palette.secondary;
        (*out).on_secondary = palette.on_secondary;
        (*out).secondary_container = palette.secondary_container;
        (*out).on_secondary_container = palette.on_secondary_container;
        (*out).tertiary = palette.tertiary;
        (*out).on_tertiary = palette.on_tertiary;
        (*out).tertiary_container = palette.tertiary_container;
        (*out).on_tertiary_container = palette.on_tertiary_container;
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn hb_backup_encrypt(plaintext: *const c_char, passphrase: *const c_char) -> *mut EncryptedFFI {
    let plaintext = unsafe { CStr::from_ptr(plaintext).to_str().unwrap_or("") };
    let passphrase = unsafe { CStr::from_ptr(passphrase).to_bytes() };
    match crate::backup_crypto::BackupCrypto::encrypt(plaintext, passphrase) {
        Some(enc) => {
            let result = Box::new(EncryptedFFI {
                salt: CString::new(enc.salt).unwrap().into_raw(),
                iv: CString::new(enc.iv).unwrap().into_raw(),
                ciphertext: CString::new(enc.ciphertext).unwrap().into_raw(),
                iterations: enc.iterations,
            });
            Box::into_raw(result)
        }
        None => std::ptr::null_mut(),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn hb_backup_decrypt(salt: *const c_char, iv: *const c_char, ciphertext: *const c_char, iterations: u32, passphrase: *const c_char) -> *mut c_char {
    let salt = unsafe { CStr::from_ptr(salt).to_str().unwrap_or("") };
    let iv = unsafe { CStr::from_ptr(iv).to_str().unwrap_or("") };
    let ciphertext = unsafe { CStr::from_ptr(ciphertext).to_str().unwrap_or("") };
    let passphrase = unsafe { CStr::from_ptr(passphrase).to_bytes() };

    let enc = crate::backup_crypto::Encrypted {
        salt: salt.to_string(),
        iv: iv.to_string(),
        ciphertext: ciphertext.to_string(),
        iterations,
    };

    match crate::backup_crypto::BackupCrypto::decrypt(&enc, passphrase) {
        Some(plaintext) => CString::new(plaintext).unwrap().into_raw(),
        None => std::ptr::null_mut(),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn hb_history_record(current_json: *const c_char, url: *const c_char, title: *const c_char, now: i64) -> *mut c_char {
    let current_json = unsafe { CStr::from_ptr(current_json).to_str().unwrap_or("") };
    let url = unsafe { CStr::from_ptr(url).to_str().unwrap_or("") };
    let title = unsafe { CStr::from_ptr(title).to_str().unwrap_or("") };

    let current: Vec<crate::models::HistoryEntry> = serde_json::from_str(current_json).unwrap_or_default();
    let result = crate::history::HistoryRules::record(&current, url, title, now);
    let json = serde_json::to_string(&result).unwrap_or_default();
    CString::new(json).unwrap().into_raw()
}

/// SHA-256 of arbitrary bytes, written as lowercase hex into `out`
/// (must hold at least 65 bytes including the NUL terminator).
#[unsafe(no_mangle)]
pub extern "C" fn hb_sha256_hex(data: *const u8, len: usize, out: *mut c_char) -> bool {
    use sha2::{Digest, Sha256};
    if data.is_null() || out.is_null() {
        return false;
    }
    let bytes = unsafe { std::slice::from_raw_parts(data, len) };
    let digest = Sha256::digest(bytes);
    let hex: String = digest.iter().map(|b| format!("{:02x}", b)).collect();
    let cstr = match CString::new(hex) {
        Ok(c) => c,
        Err(_) => return false,
    };
    unsafe {
        std::ptr::copy_nonoverlapping(cstr.as_ptr(), out, cstr.as_bytes().len() + 1);
    }
    true
}

#[unsafe(no_mangle)]
pub extern "C" fn hb_free_string(s: *mut c_char) {
    if !s.is_null() {
        unsafe { let _ = CString::from_raw(s); }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn hb_free_encrypted(e: *mut EncryptedFFI) {
    if !e.is_null() {
        unsafe {
            if !(*e).salt.is_null() { let _ = CString::from_raw((*e).salt); }
            if !(*e).iv.is_null() { let _ = CString::from_raw((*e).iv); }
            if !(*e).ciphertext.is_null() { let _ = CString::from_raw((*e).ciphertext); }
            let _ = Box::from_raw(e);
        }
    }
}
// ============================================================
// JS dialog budget (ported from Android core/JsGuard.kt)
// ============================================================
//
// A hostile page can call `alert()` in a loop; the dialog is app UI, so without
// a budget the page can freeze the browser. The policy lives in Rust so both
// the in-page shim and the native handler agree on the same limits.

/// Opaque dialog budget handle.
pub struct HbDialogBudget {
    inner: crate::js_guard::DialogBudget,
}

/// Creates a budget with the Android defaults (12 dialogs, 250 ms apart,
/// 2 beforeunload prompts). Free with `hb_dialog_budget_free`.
#[unsafe(no_mangle)]
pub extern "C" fn hb_dialog_budget_new() -> *mut HbDialogBudget {
    Box::into_raw(Box::new(HbDialogBudget {
        inner: crate::js_guard::DialogBudget::default(),
    }))
}

/// Creates a budget with explicit limits (used by tests).
#[unsafe(no_mangle)]
pub extern "C" fn hb_dialog_budget_new_with(
    max_dialogs: i32,
    min_interval_ms: i64,
    max_before_unload: i32,
) -> *mut HbDialogBudget {
    Box::into_raw(Box::new(HbDialogBudget {
        inner: crate::js_guard::DialogBudget::new(max_dialogs, min_interval_ms, max_before_unload),
    }))
}

#[unsafe(no_mangle)]
pub extern "C" fn hb_dialog_budget_free(b: *mut HbDialogBudget) {
    if !b.is_null() {
        unsafe { let _ = Box::from_raw(b); }
    }
}

/// Returns 1 when the dialog may be shown, 0 when it must be suppressed.
/// `now_ms` is the current wall clock in milliseconds.
#[unsafe(no_mangle)]
pub extern "C" fn hb_dialog_budget_allow(b: *mut HbDialogBudget, now_ms: i64) -> i32 {
    if b.is_null() {
        return 1; // fail open: never block the user because of a null handle
    }
    let budget = unsafe { &mut (*b).inner };
    if budget.allow_dialog(now_ms) { 1 } else { 0 }
}

/// Returns 1 when the beforeunload prompt may be shown.
#[unsafe(no_mangle)]
pub extern "C" fn hb_dialog_budget_allow_before_unload(b: *mut HbDialogBudget) -> i32 {
    if b.is_null() {
        return 1;
    }
    let budget = unsafe { &mut (*b).inner };
    if budget.allow_before_unload() { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn hb_dialog_budget_reset(b: *mut HbDialogBudget) {
    if !b.is_null() {
        unsafe { (*b).inner.reset() };
    }
}

/// Number of dialogs suppressed so far (diagnostics).
#[unsafe(no_mangle)]
pub extern "C" fn hb_dialog_budget_blocked(b: *mut HbDialogBudget) -> i32 {
    if b.is_null() {
        return 0;
    }
    unsafe { (*b).inner.blocked_dialogs }
}

/// The document-start JS guard shim. Returns a newly allocated string that the
/// caller must release with `hb_free_string`.
#[unsafe(no_mangle)]
pub extern "C" fn hb_js_guard_script() -> *mut c_char {
    match CString::new(crate::js_guard::js()) {
        Ok(c) => c.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

// ============================================================
// VPN rules (ported from Android core/VpnConfig.kt, VpnTuning.kt, VpnHealth.kt)
// ============================================================

/// Parses a WireGuard config. Returns 0 on success, or the error code.
/// On success `*out_endpoint` receives a newly allocated "host:port" string
/// (release with `hb_free_string`); on failure it receives the detail string.
#[unsafe(no_mangle)]
pub extern "C" fn hb_vpn_parse(
    text: *const c_char,
    out_endpoint: *mut *mut c_char,
    out_error: *mut *mut c_char,
) -> i32 {
    if out_endpoint.is_null() || out_error.is_null() {
        return -1;
    }
    unsafe {
        *out_endpoint = std::ptr::null_mut();
        *out_error = std::ptr::null_mut();
    }
    if text.is_null() {
        return -2;
    }
    let raw = match unsafe { CStr::from_ptr(text) }.to_str() {
        Ok(s) => s,
        Err(_) => return -2,
    };
    match crate::vpn_config::parse(raw) {
        Ok(cfg) => {
            let ep = CString::new(cfg.endpoint()).unwrap_or_default();
            unsafe { *out_endpoint = ep.into_raw() };
            0
        }
        Err((code, detail)) => {
            let d = CString::new(detail).unwrap_or_default();
            unsafe { *out_error = d.into_raw() };
            // 1..N map to VpnConfigError variants in declaration order.
            let idx = code as i32 + 1;
            idx
        }
    }
}

/// Applies the keepalive/MTU/DNS tuning. Returns a newly allocated string
/// (release with `hb_free_string`), or null on invalid input.
#[unsafe(no_mangle)]
pub extern "C" fn hb_vpn_tune(text: *const c_char, keepalive_seconds: i32) -> *mut c_char {
    if text.is_null() {
        return std::ptr::null_mut();
    }
    let raw = match unsafe { CStr::from_ptr(text) }.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };
    match CString::new(crate::vpn_tuning::tune(raw, keepalive_seconds)) {
        Ok(c) => c.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Classifies a session. Returns the reachability code (0..=5) matching
/// `VpnReachability` declaration order, or -1 on a null pointer.
#[unsafe(no_mangle)]
pub extern "C" fn hb_vpn_classify(
    connected_at: i64,
    last_handshake_at: i64,
    now: i64,
    grace_start_override: i64,
) -> i32 {
    let snapshot = crate::vpn_health::VpnHealthSnapshot::new("", connected_at, last_handshake_at);
    let r = crate::vpn_health::classify(&snapshot, now, grace_start_override);
    match r {
        crate::vpn_health::VpnReachability::Unknown => 0,
        crate::vpn_health::VpnReachability::Verifying => 1,
        crate::vpn_health::VpnReachability::Healthy => 2,
        crate::vpn_health::VpnReachability::Stale => 3,
        crate::vpn_health::VpnReachability::Unreachable => 4,
        crate::vpn_health::VpnReachability::TunnelOnly => 5,
    }
}

/// Next poll delay in milliseconds.
#[unsafe(no_mangle)]
pub extern "C" fn hb_vpn_next_poll_delay(
    foreground: bool,
    reachability: i32,
    consecutive_healthy: i32,
) -> i64 {
    let r = match reachability {
        1 => crate::vpn_health::VpnReachability::Verifying,
        2 => crate::vpn_health::VpnReachability::Healthy,
        3 => crate::vpn_health::VpnReachability::Stale,
        4 => crate::vpn_health::VpnReachability::Unreachable,
        5 => crate::vpn_health::VpnReachability::TunnelOnly,
        _ => crate::vpn_health::VpnReachability::Unknown,
    };
    crate::vpn_health::next_poll_delay_ms(foreground, r, consecutive_healthy)
}

/// Parses `wg show <iface> latest-handshakes` output into epoch millis.
#[unsafe(no_mangle)]
pub extern "C" fn hb_vpn_parse_handshakes(output: *const c_char) -> i64 {
    if output.is_null() {
        return 0;
    }
    match unsafe { CStr::from_ptr(output) }.to_str() {
        Ok(s) => crate::vpn_health::parse_latest_handshakes(s),
        Err(_) => 0,
    }
}
