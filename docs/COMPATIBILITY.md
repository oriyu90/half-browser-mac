# Android ↔ macOS compatibility

## Data files

| Item | Android | macOS | Compatible |
|---|---|---|---|
| Bookmarks | `bookmarks.json` `{"version":1,"items":[...]}` | same envelope + same fields | Yes |
| Trusted sites | `trusted_sites.json` | Keychain (`half-browser-trust`, account `host:port`) | Backup only |
| Credentials | EncryptedSharedPreferences | Keychain (`half-browser-credentials`) | Backup only |
| Settings | `settings.json` | `settings.json` (same keys) | Yes |
| History | local only | `history.json` (same envelope) | macOS → Android ignored |
| Site permissions | `site_permissions.json` | `permissions.json` (`notifications`/`camera`/`microphone`/`location`) | Yes |
| Backup | `halfbrowser.backup` v1 | same format, same crypto | Yes |

## Behaviour parity

| Behaviour | Android | macOS |
|---|---|---|
| Reject `javascript:` / `file:` / `intent:` in the address bar | Yes | Yes (`UrlUtil::toNavigable`) |
| Bare host → `https://` | Yes | Yes |
| Spaces → search with the configured engine | Yes | Yes (Google, DuckDuckGo, Brave, Ecosia, Kagi, Mojeek) |
| Default accent | hue 222, saturation 0.86 | same |
| Grid columns | 0/3/4/5/6/8 | same |
| UI scale / font scale limits | 0.8–1.4 / 0.8–1.5 | same |
| Save credentials on http | Never | Never |
| History merge window | 30 min, max 500 | same |
| History dedupe | canonical URL | same |

## Known gaps

- **Tabs**: one page on both platforms.
- **Site watch notifications** (Android WorkManager): not ported.
- **Home-screen shortcuts**: replaced by the macOS Bookmarks menu.
- **File/camera attachments**: CEF file dialogs are not wired yet.
- **mTLS client certificates**: not supported on either platform.
