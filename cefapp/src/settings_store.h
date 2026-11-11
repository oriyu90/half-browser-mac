#ifndef SETTINGS_STORE_H
#define SETTINGS_STORE_H
#include <string>

struct AppSettings {
    // Defaults mirror the Android AppSettings.DEFAULT so a fresh Mac install
    // looks the same as a fresh Android install.
    std::string themeMode = "system";
    float accentHue = 222.0f;
    float accentSaturation = 0.86f;
    float accentTone = 0.5f;
    float uiScale = 1.0f;
    float fontScale = 1.0f;
    int gridColumns = 0;
    std::string language = "system";
    std::string searchEngine = "duckduckgo";
    bool fetchBookmarkIcons = true;
    bool notificationsEnabled = false;

    // ---- VPN (v1.9.0) ----
    // Mirrors the Android AppSettings fields so a backup moves between the two
    // builds without losing the user's choices. Profile ids are not carried in
    // the backup (profiles contain private keys and stay on the device).
    /// Connect the selected profile when the app launches.
    bool vpnAutoConnect = false;
    /// After the app comes back to the foreground (or a check runs), verify the
    /// tunnel's handshake and reconnect it when it went stale.
    bool vpnAutoReconnect = true;
    /// Send the keepalive every 60 s instead of 25 s (less data, slightly less
    /// robust behind a strict firewall).
    bool vpnPowerSaver = false;

    // ---- Site watch (v1.9.0) ----
    /// Check bookmarked pages in the background and notify on change.
    bool siteWatchEnabled = false;
    /// Minutes between checks (15 / 30 / 60 / 180).
    int siteWatchIntervalMinutes = 60;
    /// Only check while a Wi-Fi interface is the default route.
    bool siteWatchWifiOnly = false;

    // ---- Browser behaviour (v1.9.0) ----
    /// Defence against hostile in-page JavaScript (dialog rate limits,
    /// scripted popups, javascript: navigation).
    bool jsGuardEnabled = true;
    /// Fill saved HTML form logins on https pages. Never submits automatically.
    bool formAutofillEnabled = true;
};

class SettingsStore {
public:
    static SettingsStore& instance();
    AppSettings load();
    void save(const AppSettings& s);
    std::string filePath() const;

    /// Redirect the store at a scratch file (self-test only). Pass nullptr to
    /// restore the real path. Lets the test exercise load()/save() themselves
    /// rather than re-implementing the parsing next to them.
    void setFilePathForTesting(const char* path);

private:
    SettingsStore();
    std::string filePath_;
};
#endif
