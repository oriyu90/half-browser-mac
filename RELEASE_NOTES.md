# Half-Browser 1.5.1 for macOS

The Android feature set, ported to macOS on Chromium (CEF 156).

## Highlights

- **Self-signed HTTPS** — the interstitial shows the certificate subject,
  issuer and SHA-256 before you decide. "Trust Always" pins host + port +
  certificate SHA-256; a changed certificate warns again.
- **HTTP authentication** — Basic/Digest dialog, stored in the macOS Keychain
  for `https` only and filled in automatically next time.
- **Bookmarks and history** — grid home window with monograms and site icons;
  500 history entries merged within 30 minutes.
- **Theme and language** — System/Light/Dark, accent hue/saturation/brightness,
  Japanese and English switchable in Settings.
- **Backup** — the Android `halfbrowser.backup` format, optionally encrypted
  with PBKDF2-HMAC-SHA256 + AES-256-GCM.
- **Site permissions** — camera, microphone, notifications, location and
  clipboard decisions stored per origin.
- **Form sign-in** — detects login forms on HTTPS pages and offers to save.

## Install

1. Download `Half-Browser-1.5.1-macOS-arm64.dmg`.
2. Open it and move `halfbrowser_cef.app` to Applications.
3. On first launch, right-click the app and choose **Open** (the build is
   ad-hoc signed, so Gatekeeper asks once).

Requires macOS 14 or later on Apple Silicon.

## Limitations

- One tab, matching the Android build.
- Certificate trust is an in-app pin, not a replacement for CA validation.
- Background site-watch notifications (Android WorkManager) are not ported.
- Client certificates (mTLS) are not supported.
