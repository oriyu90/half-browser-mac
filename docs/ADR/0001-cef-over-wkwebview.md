# ADR-0001: Use CEF (Chromium) instead of WKWebView

- Status: Accepted (2026-11-07)
- Related: Android ADR-0001 (WebView)

## Context

The Android build uses Android System WebView because it exposes
`onReceivedSslError` and `onReceivedHttpAuthRequest`, which the app needs to
show its own certificate interstitial and to fill saved HTTP credentials.

On macOS the two candidates are:

1. **WKWebView** — system WebKit, small binary, updated by the OS.
2. **CEF** — embedded Chromium, ~130 MB of framework, updated with the app.

WKWebView cannot intercept certificate errors (`WKNavigationDelegate` has no
equivalent of `onReceivedSslError`) and cannot supply HTTP credentials for a
challenge without a `URLSession` round trip. Both are requirements.

## Decision

Use **CEF 156 (Chromium 120)** embedded in the app bundle.

## Consequences

- Certificate interstitial and HTTP auth work the same way as on Android
  (`CefRequestHandler::OnCertificateError`, `GetAuthCredentials`).
- The app is ~150 MB compressed and must ship its own Chromium updates.
- Multi-process: the bundle contains `halfbrowser_cef Helper(.app)` variants
  which must be signed together with the main bundle.
- The Rust core stays free of CEF types so it can be reused by a future
  SwiftUI shell.
