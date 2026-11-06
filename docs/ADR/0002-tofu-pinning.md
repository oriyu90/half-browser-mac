# ADR-0002: Trust-on-first-use pinning scoped to host + port + SHA-256

- Status: Accepted (2026-11-07)
- Related: Android ADR-0002

## Context

A self-signed certificate cannot be validated by the CA store. The app lets the
user trust it explicitly, but the decision must not be blanket "trust anything
for this host forever".

## Decision

- The fingerprint is the **lower-case hex SHA-256 of the DER certificate**
  (`CefX509Certificate::GetDEREncoded` hashed by the Rust core via
  `hb_sha256_hex`).
- A pin is stored in the macOS Keychain keyed by `host:port`.
- Three outcomes:
  - **Trusted** — pin matches: proceed silently.
  - **Unknown** — no pin: interstitial with subject, issuer and fingerprint.
    "Trust Always" stores the pin; "Proceed Once" does not.
  - **Changed** — pin exists but differs: a stronger warning that shows both
    fingerprints. Accepting updates the pin.
- When the DER bytes are unavailable the fingerprint is empty and **"Trust
  Always" is not offered** — only "Proceed Once". This prevents pinning an
  unverifiable value.

## Consequences

- A renewed certificate always requires a fresh decision.
- Deleting a pin (Settings → Security) makes the next visit warn again.
