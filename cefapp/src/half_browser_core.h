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

typedef struct AccentPalette AccentPalette;

typedef struct Encrypted Encrypted;

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

#ifdef __cplusplus
}  // extern "C"
#endif  // __cplusplus

#endif  /* HALF_BROWSER_CORE_H */
