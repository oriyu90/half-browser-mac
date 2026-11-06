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
    bool formLoginEnabled = true;
    bool fetchBookmarkIcons = true;
    bool notificationsEnabled = false;
};

class SettingsStore {
public:
    static SettingsStore& instance();
    AppSettings load();
    void save(const AppSettings& s);
    std::string filePath() const;

private:
    SettingsStore();
    std::string filePath_;
};
#endif
