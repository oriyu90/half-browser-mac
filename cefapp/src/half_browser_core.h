#ifndef HALF_BROWSER_CORE_H
#define HALF_BROWSER_CORE_H

/* Generated with cbindgen:0.29.4 */

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

#define DEFAULT_ITERATIONS 120000

#define MIN_PASSPHRASE_LENGTH 8

#define MAX_PASSPHRASE_LENGTH 256

#define HistoryRules_MAX_ENTRIES 500

#define HistoryRules_MERGE_WINDOW_MS ((30 * 60) * 1000)

#define AppSettings_MIN_UI_SCALE 0.8

#define AppSettings_MAX_UI_SCALE 1.4

#define AppSettings_MIN_FONT_SCALE 0.8

#define AppSettings_MAX_FONT_SCALE 1.5

#define AppSettings_MIN_ACCENT_SATURATION 0.0

#define AppSettings_MAX_ACCENT_SATURATION 1.0

#define AppSettings_DEFAULT_ACCENT_HUE 210.0

/**
 * Maximum JS dialogs a single document may show.
 */
#define MAX_DIALOGS_PER_PAGE 12

/**
 * Minimum gap between two JS dialogs, in milliseconds.
 */
#define DIALOG_MIN_INTERVAL_MS 250

/**
 * Maximum `beforeunload` prompts per page; more is treated as a trap.
 */
#define MAX_BEFORE_UNLOAD 2

/**
 * Maximum script-opened windows per page.
 */
#define MAX_SCRIPT_POPUPS 0

#define MAX_BYTES (64 * 1024)

#define MAX_PEERS 32

#define MAX_LIST_ITEMS 32

#define MAX_NAME_LENGTH 40

#define MIN_MTU 576

#define MAX_MTU 9000

/**
 * A handshake is considered fresh for this long. WireGuard re-keys every
 * ~2 minutes, so a healthy idle tunnel still produces handshakes well inside
 * this window.
 */
#define HEALTHY_WINDOW_MS 180000

/**
 * Grace period after UP before "no handshake yet" becomes a failure.
 */
#define HANDSHAKE_GRACE_MS 45000

/**
 * How often the controller re-reads the handshake time while the app is on
 * screen. The healthy window is `HEALTHY_WINDOW_MS`, so this is already finer
 * than the judgement needs; it exists so the badge reacts quickly.
 */
#define POLL_FOREGROUND_MS 10000

/**
 * First interval used while the app is not visible. A healthy tunnel backs off
 * from here towards `POLL_BACKGROUND_MAX_MS`; a broken one keeps polling at
 * this rate.
 */
#define POLL_BACKGROUND_MIN_MS 60000

/**
 * Upper bound of the background back-off.
 */
#define POLL_BACKGROUND_MAX_MS 300000

/**
 * Multiplier applied to the background interval per consecutive healthy check.
 */
#define POLL_BACKOFF_FACTOR 1.5

/**
 * Grace period used right after the network changed. A handshake cannot
 * complete before the new path exists, so the normal 45 s grace would report a
 * false failure and trigger a pointless reconnect.
 */
#define NETWORK_CHANGE_GRACE_MS 10000

/**
 * Minimum gap between two automatic reconnects (prevents reconnect storms).
 */
#define AUTO_RECONNECT_MIN_INTERVAL_MS 30000

/**
 * Caps the exponent so the computation stays bounded for a long session.
 * Shared with the controller, which caps its healthy counter the same way.
 */
#define MAX_BACKOFF_STEPS 16

#define DEFAULT_KEEPALIVE_SECONDS 25

/**
 * Keepalive used when the user turns on the power-saving option. Still inside
 * the range WireGuard documents for NAT traversal, but long enough that a
 * strict firewall can drop an idle mapping, hence opt-in.
 */
#define POWER_SAVER_KEEPALIVE_SECONDS 60

#define DEFAULT_MTU 1280

#define MAX_DNS_SERVERS 3

typedef struct AccentPalette AccentPalette;

typedef struct Encrypted Encrypted;

/**
 * Opaque dialog budget handle.
 */
typedef struct HbDialogBudget HbDialogBudget;

typedef struct HistoryEntry HistoryEntry;

typedef struct TrustDecision TrustDecision;

typedef struct AccentPaletteFFI {
  uint32_t primary;
  uint32_t on_primary;
  uint32_t primary_container;
  uint32_t on_primary_container;
  uint32_t secondary;
  uint32_t on_secondary;
  uint32_t secondary_container;
  uint32_t on_secondary_container;
  uint32_t tertiary;
  uint32_t on_tertiary;
  uint32_t tertiary_container;
  uint32_t on_tertiary_container;
} AccentPaletteFFI;

typedef struct EncryptedFFI {
  char *salt;
  char *iv;
  char *ciphertext;
  uint32_t iterations;
} EncryptedFFI;

#define AppSettings_ALLOWED_GRID_COLUMNS { 0, 3, 4, 5, 6, 8, }

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

int32_t hb_trust_decide(const char *host,
                        int32_t port,
                        const char *fingerprint,
                        const char *saved_host,
                        int32_t saved_port,
                        const char *saved_fingerprint);

char *hb_normalize_url(const char *input, const char *search_template);

void hb_accent_palette(float hue,
                       float saturation,
                       float tone,
                       bool dark,
                       struct AccentPaletteFFI *out);

struct EncryptedFFI *hb_backup_encrypt(const char *plaintext, const char *passphrase);

char *hb_backup_decrypt(const char *salt,
                        const char *iv,
                        const char *ciphertext,
                        uint32_t iterations,
                        const char *passphrase);

char *hb_history_record(const char *current_json, const char *url, const char *title, int64_t now);

/**
 * SHA-256 of arbitrary bytes, written as lowercase hex into `out`
 * (must hold at least 65 bytes including the NUL terminator).
 */
bool hb_sha256_hex(const uint8_t *data, uintptr_t len, char *out);

void hb_free_string(char *s);

void hb_free_encrypted(struct EncryptedFFI *e);

/**
 * Creates a budget with the Android defaults (12 dialogs, 250 ms apart,
 * 2 beforeunload prompts). Free with `hb_dialog_budget_free`.
 */
struct HbDialogBudget *hb_dialog_budget_new(void);

/**
 * Creates a budget with explicit limits (used by tests).
 */
struct HbDialogBudget *hb_dialog_budget_new_with(int32_t max_dialogs,
                                                 int64_t min_interval_ms,
                                                 int32_t max_before_unload);

void hb_dialog_budget_free(struct HbDialogBudget *b);

/**
 * Returns 1 when the dialog may be shown, 0 when it must be suppressed.
 * `now_ms` is the current wall clock in milliseconds.
 */
int32_t hb_dialog_budget_allow(struct HbDialogBudget *b, int64_t now_ms);

/**
 * Returns 1 when the beforeunload prompt may be shown.
 */
int32_t hb_dialog_budget_allow_before_unload(struct HbDialogBudget *b);

void hb_dialog_budget_reset(struct HbDialogBudget *b);

/**
 * Number of dialogs suppressed so far (diagnostics).
 */
int32_t hb_dialog_budget_blocked(struct HbDialogBudget *b);

/**
 * The document-start JS guard shim. Returns a newly allocated string that the
 * caller must release with `hb_free_string`.
 */
char *hb_js_guard_script(void);

/**
 * Parses a WireGuard config. Returns 0 on success, or the error code.
 * On success `*out_endpoint` receives a newly allocated "host:port" string
 * (release with `hb_free_string`); on failure it receives the detail string.
 */
int32_t hb_vpn_parse(const char *text, char **out_endpoint, char **out_error);

/**
 * Applies the keepalive/MTU/DNS tuning. Returns a newly allocated string
 * (release with `hb_free_string`), or null on invalid input.
 */
char *hb_vpn_tune(const char *text, int32_t keepalive_seconds);

/**
 * Classifies a session. Returns the reachability code (0..=5) matching
 * `VpnReachability` declaration order, or -1 on a null pointer.
 */
int32_t hb_vpn_classify(int64_t connected_at,
                        int64_t last_handshake_at,
                        int64_t now,
                        int64_t grace_start_override);

/**
 * Next poll delay in milliseconds.
 */
int64_t hb_vpn_next_poll_delay(bool foreground, int32_t reachability, int32_t consecutive_healthy);

/**
 * Parses `wg show <iface> latest-handshakes` output into epoch millis.
 */
int64_t hb_vpn_parse_handshakes(const char *output);

#ifdef __cplusplus
}  // extern "C"
#endif  // __cplusplus

#endif  /* HALF_BROWSER_CORE_H */
