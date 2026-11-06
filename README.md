# Half-Browser for macOS

A small Chromium browser for macOS. Like the Android build it can trust a
**self-signed HTTPS** site after showing the certificate, and it can remember
**HTTP authentication** credentials in the macOS Keychain.

- Author: 折田悠希 / Yuki_Orita
- License: MIT
- Android build: https://github.com/oriyu90/half-browser
- Project site: https://studio-rizi.pages.dev/projects/half-browser/

## What it does

| Feature | Detail |
|---|---|
| Browser | Chromium (CEF 156 / Chromium 120) with an address bar, back/forward, reload and home. |
| Self-signed HTTPS | Certificate interstitial showing subject, issuer and SHA-256. "Trust Always" pins host + port + certificate SHA-256 (TOFU); a changed certificate warns again. |
| HTTP authentication | Basic/Digest dialog. Credentials are saved in the Keychain for `https` only and filled in automatically next time. |
| Bookmarks | Grid on the home window, deterministic monograms, site icons, edit/delete. |
| History | Last 500 pages, merged within 30 minutes, clearable. |
| Theme | System / Light / Dark, plus an accent hue/saturation/brightness. |
| Language | Japanese and English, switchable in Settings. |
| Backup | Export/import in the Android `halfbrowser.backup` format, optionally encrypted with PBKDF2-HMAC-SHA256 + AES-256-GCM. |
| Site permissions | Camera, microphone, notifications, location and clipboard decisions stored per origin. |
| Form sign-in | Detects a login form on an HTTPS page and offers to save the credentials. |

## Build

Requirements: macOS 14+, Xcode 16+ (Swift 6), Rust 1.80+, CMake 3.21+, Ninja.

```bash
./scripts/fetch-cef.sh     # downloads the pinned CEF distribution (~130 MB)
./scripts/build.sh         # builds the Rust core and the app, signs it, runs self-tests
./scripts/package-dmg.sh   # creates Half-Browser-1.5.1-macOS-arm64.dmg
```

## Layout

```
core/      Rust crate (pure logic: URL rules, trust policy, accent colours,
           backup crypto, history rules) exported to C via cbindgen
cefapp/    Objective-C++ application (CEF host, windows, menus, Keychain)
app/       SwiftUI shell (prototype of the next UI generation)
docs/      Design decisions (ADR), user documentation
scripts/   fetch-cef.sh / build.sh / package-dmg.sh
```

## Notes

- The app is ad-hoc signed. Gatekeeper will warn on first launch; open it from
  the context menu → Open, or `xattr -d com.apple.quarantine`.
- Tabs are not supported (one page at a time), matching the Android build.
- Certificate trust is an in-app pin, not a replacement for CA validation.
