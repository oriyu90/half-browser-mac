# Half-Browser 1.9.0 for macOS

Brings the macOS build up to the Android 1.9.0 feature set, and fixes the
defects that were found while doing it.

## New

- **Downloads** — a save panel per download and a completion notice.
- **Page dialogs** — `alert`, `confirm`, `prompt` and the leave-page prompt,
  with a rate limit so a hostile page cannot lock the UI.
- **Find in page** (⌘F) and **zoom** (⌘+ / ⌘- / ⌘0).
- **History window** (⌘Y) — search, delete one entry, clear all.
- **File attachments** — `<input type="file">` opens a native panel.
- **Site Watch** — bookmarked pages are checked in the background and you are
  notified when the content changes. The first check records a baseline
  instead of notifying, so switching it on does not fire one alert per bookmark.
- **VPN profiles** — import, validate, store in the Keychain, export and show
  reachability. See the limitation below.
- **Form autofill** — saved sign-ins are filled into empty fields and never
  submitted.

## Fixed

- **Settings could be corrupted.** Keys were matched by substring, so
  `accentHue` could pick up `accentHueExtra`, and the file was written
  non-atomically, so a crash could truncate it. Both fixed.
- **Passwords were written to the browser console.** The form-login script
  reported credentials with `console.log`, which any page script can wrap and
  read. They now travel over a private in-process channel.
- **The WireGuard private key stayed on disk.** The tuned config was never
  deleted after connecting. It is now wiped and removed on disconnect, and
  leftovers from a crash are wiped at startup.
- **Camera and microphone permissions were swapped.**
- **Home went to example.com** instead of the bookmark home, at launch and from
  the Home button.
- **The home grid blocked on the network** — every redraw fetched favicons
  synchronously. It now shows the monogram immediately and fills in the icon
  afterwards.
- **UI scale, text scale and column count did nothing** even though they were
  saved.
- History could record an empty title, and truncation could split a UTF-8
  character. IPv6 endpoints (`[::1]:8443`) broke certificate pinning.
- Keychain reads leaked their Core Foundation objects.

## VPN limitation

macOS does not let an app create its own VPN tunnel without a signed Network
Extension (paid Apple Developer account) or root. Half-Browser therefore
manages and validates your WireGuard profiles and shows whether the tunnel is
reachable, but cannot start the tunnel itself. Use the official WireGuard app
for the connection. This is stated in Settings rather than hidden.

## Install

1. Download `Half-Browser-1.9.0-macOS-arm64.dmg`.
2. Open it and move `halfbrowser_cef.app` to Applications.
3. On first launch, right-click the app and choose **Open** (the build is
   ad-hoc signed, so Gatekeeper asks once).

Requires macOS 14 or later on Apple Silicon.

## Known limitations

- One tab, matching the Android build.
- Certificate trust is an in-app pin, not a replacement for CA validation.
- Site Watch runs only while the app is open (no WorkManager equivalent).
- Client certificates (mTLS) are not supported.
