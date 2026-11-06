# ADR-0003: Share the Android backup format

- Status: Accepted (2026-11-07)
- Related: Android `core/Backup.kt`, `core/BackupCrypto.kt`

## Context

Users move between a phone and a Mac. A macOS-only format would force manual
re-entry of bookmarks and settings.

## Decision

The macOS exporter writes `{"format":"halfbrowser.backup","version":1,...}`
with the Android field names:

- `settings` — themeMode, uiScale, fontScale, gridColumns, language,
  accentHue, accentSaturation, accentTone, searchEngine, formAutofillEnabled,
  fetchBookmarkIcons
- `bookmarks[]` — id, title, url, glyph, colorSeed, icon, createdAt, updatedAt
- `sitePermissions[]` — origin, kind, granted
- `history[]` — macOS extension; the Android importer ignores unknown fields
- `credentials` — only as an encrypted blob

Encryption reuses the Android scheme string
`pbkdf2-hmac-sha256/aes-256-gcm` with 120,000 iterations, a 16-byte salt and a
12-byte IV, implemented once in the Rust core and shared by both platforms.

## Consequences

- Import is defensive: unknown fields are ignored, URLs are validated, and
  counts are capped (500 bookmarks).
- History is local-only on Android; exporting it from macOS is additive and
  does not break the Android importer.
