# Half-Browser for macOS

A small Chromium browser for macOS, kept in step with the Android build. It can
trust a **self-signed HTTPS** site after showing you the certificate, remember
**HTTP authentication** credentials in the macOS Keychain, and — since 1.9.0 —
handle downloads, page dialogs, in-page find and site-change notifications.

- Author: 折田悠希 / Yuki_Orita
- License: MIT
- Android build: https://github.com/oriyu90/half-browser
- Project site: https://studio-rizi.pages.dev/projects/half-browser/

## What it does

| Feature | Detail |
|---|---|
| Browser | Chromium (CEF 156) with an address bar, back/forward, reload, home, **zoom** (⌘+ / ⌘- / ⌘0) and **find in page** (⌘F). |
| Self-signed HTTPS | Certificate interstitial showing subject, issuer and SHA-256. "Trust Always" pins host + port + certificate SHA-256 (TOFU); a changed certificate warns again. |
| HTTP authentication | Basic/Digest dialog. Credentials are saved in the Keychain for `https` only and filled in automatically next time. |
| Bookmarks | Grid on the home window with monograms and site icons. **UI scale, text scale and column count actually apply.** |
| History | Last 500 pages, merged within 30 minutes, with a searchable window (⌘Y), per-entry delete and clear-all. |
| Downloads | A save panel per download, with a completion notice. |
| Page dialogs | `alert` / `confirm` / `prompt` and the leave-page prompt, rate-limited so a hostile page cannot lock the UI. |
| File attachments | `<input type="file">` opens a native panel, with type filters and multi-select. |
| Site notifications | Bookmarked pages are checked in the background and you are told when the content changes. |
| Theme | System / Light / Dark, plus an accent hue/saturation/brightness. |
| Language | Japanese and English, fully translated (231 keys, enforced by the self-test). |
| Backup | Export/import in the Android `halfbrowser.backup` format, optionally encrypted with PBKDF2-HMAC-SHA256 + AES-256-GCM. |
| Site permissions | Camera, microphone, notifications, location and clipboard decisions stored per origin. |
| Form sign-in | Detects a login form on an HTTPS page, offers to save, and fills saved sign-ins into empty fields (never submits). |
| VPN profiles | Import, validate, store (Keychain), export and show reachability for WireGuard profiles. See the note below. |

## VPN on macOS: what is possible

The Android build ships its own WireGuard tunnel. **macOS does not allow an app
to do that** without a signed Network Extension, which requires a paid Apple
Developer account; running a tunnel as root is the only alternative. Both were
tested on this machine and are unavailable:

- `NEPacketTunnelProvider` exists, but starting a tunnel needs the
  `com.apple.developer.networking.networkextension` entitlement.
- `wg-quick up` requires root (`sudo`), which a GUI app cannot request.
- `wireguard-go` cannot create a TUN device without root
  (`operation not permitted`).

Half-Browser therefore does everything that does not need a tunnel — profile
import and validation with the same strict parser as Android, Keychain storage,
export in the original byte-for-byte form, reachability rules, and wake/network
change detection — and states the limitation in Settings instead of hiding it.
Use the official WireGuard app for the connection itself.

## Build

Requirements: macOS 14+, Xcode 16+, Rust 1.80+, CMake 3.21+, Ninja.

```bash
./scripts/fetch-cef.sh     # downloads the pinned CEF distribution (~130 MB)
./scripts/build.sh         # builds the Rust core and the app, signs it, runs self-tests
./scripts/package-dmg.sh   # creates Half-Browser-<version>-macOS-arm64.dmg
```

`./scripts/build.sh` finishes with a self-test that checks the URL rules, JSON
handling, Japanese/English key parity, the settings round-trip, atomic writes,
the site-watch state machine and the VPN rules — all without a display.

## Layout

```
core/      Rust crate (pure logic: URL rules, trust policy, accent colours,
           backup crypto, history rules, VPN config/tuning/health, JS guard)
cefapp/    Objective-C++ application (CEF host, windows, menus, Keychain)
app/       SwiftUI shell (prototype of the next UI generation)
docs/      Design decisions (ADR), user documentation, release plan
scripts/   fetch-cef.sh / build.sh / package-dmg.sh
```

## Notes

- The app is ad-hoc signed. Gatekeeper will warn on first launch; open it from
  the context menu → Open, or `xattr -d com.apple.quarantine`.
- On first launch macOS asks for permission to use the Keychain item that
  Chromium uses to encrypt cookies. Because each ad-hoc-signed build is a new
  identity, the prompt can reappear after an update; allowing it once per
  download is expected.
- Tabs are not supported (one page at a time), matching the Android build.
- Certificate trust is an in-app pin, not a replacement for CA validation.
- Site Watch runs only while Half-Browser is open: macOS has no background
  scheduler equivalent to Android's WorkManager.
