//! Defence against hostile in-page JavaScript.
//!
//! Ported 1:1 from the Android `core/JsGuard.kt` (v1.9.0).
//!
//! Threat model
//! ------------
//! A page the user visits (or an injected third-party ad/iframe on it) is
//! untrusted code. The attacks that actually work against an embedded browser
//! are not "run JS" — the page already runs JS by design — but these:
//!
//!  1. **Dialog spam / UI lock-out.** `while(true) alert(1)`, chained
//!     `confirm()` or a `beforeunload` handler that makes leaving impossible.
//!     The dialog is app UI, so the page can otherwise freeze the browser.
//!  2. **Navigation hijacking.** `location = 'javascript:...'`, meta-refresh
//!     loops, and redirects to an attacker origin used as a phishing step.
//!  3. **Popup storms.** `window.open` in a loop, or windows opened without a
//!     user gesture.
//!  4. **Tampering with the app's own shims**, so that compatibility and
//!     notification polyfills behave unexpectedly.
//!
//! What this module does
//! ---------------------
//! [`JS`] is injected at document start (before any page script) and:
//!  - rate-limits `alert`/`confirm`/`prompt` and `beforeunload` prompts;
//!  - blocks script-driven `window.open` and `javascript:` navigations via
//!    `Location.assign`/`replace`;
//!  - makes the app's own globals non-writable so a page cannot replace them;
//!  - reports every block to a counters object the app can read for diagnostics.
//!
//! What it deliberately does **not** do
//! ------------------------------------
//!  - It never blocks `alert` outright: a page that legitimately needs a dialog
//!    still gets one. Only *abuse* (rate) is stopped.
//!  - It never changes page content, cookies or storage.
//!  - It cannot stop `location = 'javascript:...'` assignment: `Location`'s
//!    accessor is not overwritable from a document-start script. The native
//!    [`DialogBudget`] is the final line of defence.

/// Maximum JS dialogs a single document may show.
pub const MAX_DIALOGS_PER_PAGE: i32 = 12;

/// Minimum gap between two JS dialogs, in milliseconds.
pub const DIALOG_MIN_INTERVAL_MS: i64 = 250;

/// Maximum `beforeunload` prompts per page; more is treated as a trap.
pub const MAX_BEFORE_UNLOAD: i32 = 2;

/// Maximum script-opened windows per page.
pub const MAX_SCRIPT_POPUPS: i32 = 0;

/// Name of the counters object installed on `window`.
pub const COUNTERS_NAME: &str = "__hbJsGuard";

/// The document-start script.
///
/// Every wrapped function keeps its `toString()` looking native, so a page that
/// feature-detects the browser does not branch on the guard. All state lives in
/// a closure; nothing is exposed except the read-only counters.
pub fn js() -> String {
    // The template is kept byte-identical to the Android shim so both platforms
    // behave the same; the limits are interpolated from the constants above.
    let template = r#"
(function () {
  'use strict';
  var W = window;
  if (W.__hbJsGuardInstalled) return;
  try {
    Object.defineProperty(W, '__hbJsGuardInstalled', { value: true, configurable: false, writable: false });
  } catch (e) { return; }

  var counters = { dialogs: 0, dialogsBlocked: 0, beforeUnloadBlocked: 0, popupsBlocked: 0, jsUrlBlocked: 0 };
  try {
    Object.defineProperty(W, '__hbJsGuard', {
      value: Object.freeze({
        read: function () { return JSON.parse(JSON.stringify(counters)); }
      }),
      configurable: false, writable: false, enumerable: false
    });
  } catch (e) {}

  var dialogCount = 0;
  var lastDialogAt = 0;
  var beforeUnloadCount = 0;
  var popupCount = 0;
  var MAX_DIALOGS = __MAX_DIALOGS__;
  var MIN_INTERVAL = __MIN_INTERVAL__;
  var MAX_BEFORE_UNLOAD = __MAX_BEFORE_UNLOAD__;
  var MAX_POPUPS = __MAX_POPUPS__;

  function native(fn, name, length) {
    try {
      Object.defineProperty(fn, 'name', { value: name, configurable: true });
      Object.defineProperty(fn, 'length', { value: length, configurable: true });
      Object.defineProperty(fn, 'toString', {
        value: function () { return 'function ' + name + '() { [native code] }'; },
        configurable: true, writable: true
      });
    } catch (e) {}
    return fn;
  }

  function allowDialog() {
    var now = Date.now();
    if (dialogCount >= MAX_DIALOGS || (lastDialogAt && now - lastDialogAt < MIN_INTERVAL)) {
      counters.dialogsBlocked++;
      return false;
    }
    dialogCount++;
    lastDialogAt = now;
    counters.dialogs++;
    return true;
  }

  // --- dialogs -------------------------------------------------------------
  try {
    var nativeAlert = W.alert;
    var nativeConfirm = W.confirm;
    var nativePrompt = W.prompt;
    if (typeof nativeAlert === 'function') {
      W.alert = native(function (message) {
        if (!allowDialog()) return undefined;
        return nativeAlert.call(W, message);
      }, 'alert', 0);
    }
    if (typeof nativeConfirm === 'function') {
      W.confirm = native(function (message) {
        if (!allowDialog()) return false;
        return nativeConfirm.call(W, message);
      }, 'confirm', 0);
    }
    if (typeof nativePrompt === 'function') {
      W.prompt = native(function (message, defaultValue) {
        if (!allowDialog()) return null;
        return nativePrompt.call(W, message, defaultValue);
      }, 'prompt', 0);
    }
  } catch (e) {}

  // --- beforeunload trap ---------------------------------------------------
  try {
    var nativeAdd = EventTarget.prototype.addEventListener;
    EventTarget.prototype.addEventListener = native(function (type, listener, options) {
      if (String(type).toLowerCase() === 'beforeunload') {
        beforeUnloadCount++;
        if (beforeUnloadCount > MAX_BEFORE_UNLOAD) {
          counters.beforeUnloadBlocked++;
          return undefined;
        }
      }
      return nativeAdd.call(this, type, listener, options);
    }, 'addEventListener', 2);
  } catch (e) {}
  try {
    var storedBeforeUnload = null;
    Object.defineProperty(W, 'onbeforeunload', {
      configurable: true,
      enumerable: true,
      get: function () { return storedBeforeUnload; },
      set: function (value) {
        if (value != null) {
          beforeUnloadCount++;
          if (beforeUnloadCount > MAX_BEFORE_UNLOAD) {
            counters.beforeUnloadBlocked++;
            storedBeforeUnload = null;
            return;
          }
        }
        storedBeforeUnload = value;
      }
    });
  } catch (e) {}

  // --- popups --------------------------------------------------------------
  try {
    var nativeOpen = W.open;
    if (typeof nativeOpen === 'function') {
      W.open = native(function (url, target, features) {
        var gesture = false;
        try { gesture = !!(navigator.userActivation && navigator.userActivation.isActive); } catch (e) {}
        if (!gesture && popupCount >= MAX_POPUPS) {
          popupCount++;
          counters.popupsBlocked++;
          return null;
        }
        popupCount++;
        return nativeOpen.call(W, url, target, features);
      }, 'open', 3);
    }
  } catch (e) {}

  // --- javascript: navigation ---------------------------------------------
  try {
    var nativeReplace = Location.prototype.replace;
    var nativeAssign = Location.prototype.assign;
    var isJsUrl = function (value) {
      try { return String(value).replace(/^[\s\u0000-\u001f]+/, '').toLowerCase().indexOf('javascript:') === 0; } catch (e) { return false; }
    };
    if (typeof nativeReplace === 'function') {
      Location.prototype.replace = native(function (url) {
        if (isJsUrl(url)) { counters.jsUrlBlocked++; return undefined; }
        return nativeReplace.call(this, url);
      }, 'replace', 1);
    }
    if (typeof nativeAssign === 'function') {
      Location.prototype.assign = native(function (url) {
        if (isJsUrl(url)) { counters.jsUrlBlocked++; return undefined; }
        return nativeAssign.call(this, url);
      }, 'assign', 1);
    }
  } catch (e) {}

  // --- protect the app's own globals --------------------------------------
  try {
    var protect = function (name) {
      try {
        var descriptor = Object.getOwnPropertyDescriptor(W, name);
        if (descriptor && descriptor.configurable) {
          if ('value' in descriptor) {
            Object.defineProperty(W, name, {
              value: descriptor.value,
              writable: false,
              enumerable: descriptor.enumerable,
              configurable: false
            });
          } else {
            Object.defineProperty(W, name, {
              get: descriptor.get,
              set: undefined,
              enumerable: descriptor.enumerable,
              configurable: false
            });
          }
        }
      } catch (e) {}
    };
    protect('HalfBrowserNotify');
  } catch (e) {}
})();
"#;
    template
        .replace("__MAX_DIALOGS__", &MAX_DIALOGS_PER_PAGE.to_string())
        .replace("__MIN_INTERVAL__", &DIALOG_MIN_INTERVAL_MS.to_string())
        .replace("__MAX_BEFORE_UNLOAD__", &MAX_BEFORE_UNLOAD.to_string())
        .replace("__MAX_POPUPS__", &MAX_SCRIPT_POPUPS.to_string())
        .trim()
        .to_string()
}

/// Native twin of the in-page dialog policy, used by the JS dialog handler.
///
/// The native handler is authoritative: the shim can be bypassed by a page that
/// saves a reference before the shim installs, but the browser callback cannot.
/// Keeping both means a bypass still hits the native limit.
#[derive(Debug, Clone)]
pub struct DialogBudget {
    max_dialogs: i32,
    min_interval_ms: i64,
    max_before_unload: i32,
    dialogs: i32,
    before_unload: i32,
    last_at: i64,
    pub blocked_dialogs: i32,
    pub blocked_before_unload: i32,
}

impl Default for DialogBudget {
    fn default() -> Self {
        Self::new(
            MAX_DIALOGS_PER_PAGE,
            DIALOG_MIN_INTERVAL_MS,
            MAX_BEFORE_UNLOAD,
        )
    }
}

impl DialogBudget {
    pub fn new(max_dialogs: i32, min_interval_ms: i64, max_before_unload: i32) -> Self {
        Self {
            max_dialogs,
            min_interval_ms,
            max_before_unload,
            dialogs: 0,
            before_unload: 0,
            last_at: 0,
            blocked_dialogs: 0,
            blocked_before_unload: 0,
        }
    }

    /// True when the dialog may be shown; false when it must be suppressed.
    pub fn allow_dialog(&mut self, now: i64) -> bool {
        if self.max_dialogs <= 0 || self.dialogs >= self.max_dialogs {
            self.blocked_dialogs += 1;
            return false;
        }
        if self.last_at != 0 && now - self.last_at < self.min_interval_ms {
            self.blocked_dialogs += 1;
            return false;
        }
        self.dialogs += 1;
        self.last_at = now;
        true
    }

    pub fn allow_before_unload(&mut self) -> bool {
        if self.max_before_unload <= 0 || self.before_unload >= self.max_before_unload {
            self.blocked_before_unload += 1;
            return false;
        }
        self.before_unload += 1;
        true
    }

    pub fn reset(&mut self) {
        self.dialogs = 0;
        self.before_unload = 0;
        self.last_at = 0;
        self.blocked_dialogs = 0;
        self.blocked_before_unload = 0;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn budget_allows_up_to_the_limit() {
        let mut b = DialogBudget::default();
        let mut now = 1_000_000i64;
        for i in 0..MAX_DIALOGS_PER_PAGE {
            assert!(b.allow_dialog(now), "dialog {i} should be allowed");
            now += DIALOG_MIN_INTERVAL_MS;
        }
        assert!(!b.allow_dialog(now), "over the limit must be blocked");
        assert_eq!(1, b.blocked_dialogs);
    }

    #[test]
    fn budget_enforces_the_minimum_interval() {
        let mut b = DialogBudget::default();
        assert!(b.allow_dialog(1_000));
        assert!(!b.allow_dialog(1_000 + DIALOG_MIN_INTERVAL_MS - 1));
        assert!(b.allow_dialog(1_000 + DIALOG_MIN_INTERVAL_MS));
    }

    #[test]
    fn before_unload_is_capped() {
        let mut b = DialogBudget::default();
        for _ in 0..MAX_BEFORE_UNLOAD {
            assert!(b.allow_before_unload());
        }
        assert!(!b.allow_before_unload());
        assert_eq!(1, b.blocked_before_unload);
    }

    #[test]
    fn reset_clears_counters() {
        let mut b = DialogBudget::default();
        b.allow_dialog(1_000);
        b.allow_dialog(1_001);
        b.reset();
        assert_eq!(0, b.blocked_dialogs);
        assert!(b.allow_dialog(1_002));
    }

    #[test]
    fn a_zero_limit_blocks_everything() {
        let mut b = DialogBudget::new(0, 0, 0);
        assert!(!b.allow_dialog(1));
        assert!(!b.allow_before_unload());
    }

    #[test]
    fn js_embeds_the_limits() {
        let s = js();
        assert!(s.contains(&format!("var MAX_DIALOGS = {MAX_DIALOGS_PER_PAGE};")));
        assert!(s.contains(&format!("var MIN_INTERVAL = {DIALOG_MIN_INTERVAL_MS};")));
        assert!(s.contains(&format!("var MAX_BEFORE_UNLOAD = {MAX_BEFORE_UNLOAD};")));
        assert!(s.contains(&format!("var MAX_POPUPS = {MAX_SCRIPT_POPUPS};")));
        // No placeholder survived.
        assert!(!s.contains("__MAX_"));
        assert!(!s.contains("__MIN_"));
    }

    #[test]
    fn js_has_the_expected_shape() {
        let s = js();
        assert!(s.starts_with("(function ()"));
        assert!(s.ends_with("})();"));
        // The guard must be idempotent and must not leak a mutable API.
        assert!(s.contains("__hbJsGuardInstalled"));
        assert!(s.contains("Object.freeze"));
        // Every defence block is present.
        for needle in [
            "W.alert = native(",
            "W.confirm = native(",
            "W.prompt = native(",
            "EventTarget.prototype.addEventListener = native(",
            "W.open = native(",
            "Location.prototype.replace = native(",
            "Location.prototype.assign = native(",
            "protect('HalfBrowserNotify')",
        ] {
            assert!(s.contains(needle), "missing {needle}");
        }
    }

    #[test]
    fn js_parses_as_javascript() {
        // A real parser is the only reliable syntax check (a brace counter is
        // fooled by regex literals and strings). Skipped when node is absent so
        // the crate still builds on machines without it.
        let node = ["/opt/homebrew/bin/node", "/usr/local/bin/node", "node"]
            .iter()
            .find(|p| std::path::Path::new(p).exists() || **p == "node");
        let node = match node {
            Some(n) => *n,
            None => return,
        };
        let dir = std::env::temp_dir().join("hb_jsguard_test");
        std::fs::create_dir_all(&dir).ok();
        let file = dir.join("guard.js");
        if std::fs::write(&file, js()).is_err() {
            return;
        }
        let out = std::process::Command::new(node)
            .arg("--check")
            .arg(&file)
            .output();
        match out {
            Ok(o) => {
                assert!(
                    o.status.success(),
                    "node --check failed: {}",
                    String::from_utf8_lossy(&o.stderr)
                );
            }
            Err(_) => {} // node not executable; skip
        }
    }
}
