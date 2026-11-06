#import <Foundation/Foundation.h>
#include "settings_store.h"
#include <fstream>
#include <sstream>
#include <sys/stat.h>

SettingsStore& SettingsStore::instance() {
    static SettingsStore inst;
    return inst;
}

SettingsStore::SettingsStore() {
    const char* home = getenv("HOME");
    std::string dir = std::string(home) + "/Library/Application Support/Half-Browser";
    mkdir(dir.c_str(), 0755);
    filePath_ = dir + "/settings.json";
}

std::string SettingsStore::filePath() const { return filePath_; }

static std::string getStr(const std::string& json, const std::string& key, const std::string& def) {
    size_t p = json.find("\"" + key + "\":\"");
    if (p == std::string::npos) return def;
    p += key.size() + 4;
    size_t e = json.find('"', p);
    if (e == std::string::npos) return def;
    return json.substr(p, e - p);
}

static float getFloat(const std::string& json, const std::string& key, float def) {
    size_t p = json.find("\"" + key + "\":");
    if (p == std::string::npos) return def;
    p += key.size() + 3;
    try { return std::stof(json.substr(p, 20)); } catch(...) { return def; }
}

static int getInt(const std::string& json, const std::string& key, int def) {
    size_t p = json.find("\"" + key + "\":");
    if (p == std::string::npos) return def;
    p += key.size() + 3;
    try { return std::stoi(json.substr(p, 20)); } catch(...) { return def; }
}

static bool getBool(const std::string& json, const std::string& key, bool def) {
    size_t p = json.find("\"" + key + "\":");
    if (p == std::string::npos) return def;
    p += key.size() + 3;
    if (json.compare(p, 4, "true") == 0) return true;
    if (json.compare(p, 5, "false") == 0) return false;
    return def;
}

AppSettings SettingsStore::load() {
    AppSettings s;
    std::ifstream f(filePath_);
    if (!f.is_open()) return s;
    std::stringstream ss;
    ss << f.rdbuf();
    std::string json = ss.str();
    f.close();

    s.themeMode = getStr(json, "themeMode", "system");
    s.accentHue = getFloat(json, "accentHue", 222.0f);
    s.accentSaturation = getFloat(json, "accentSaturation", 0.86f);
    s.accentTone = getFloat(json, "accentTone", 0.5f);
    s.uiScale = getFloat(json, "uiScale", 1.0f);
    s.fontScale = getFloat(json, "fontScale", 1.0f);
    s.gridColumns = getInt(json, "gridColumns", 0);
    s.language = getStr(json, "language", "system");
    s.searchEngine = getStr(json, "searchEngine", "duckduckgo");
    s.formLoginEnabled = getBool(json, "formLoginEnabled", true);
    s.fetchBookmarkIcons = getBool(json, "fetchBookmarkIcons", true);
    s.notificationsEnabled = getBool(json, "notificationsEnabled", false);

    // Sanitize (mirrors Android Codecs.sanitize).
    if (s.uiScale < 0.8f) s.uiScale = 0.8f;
    if (s.uiScale > 1.4f) s.uiScale = 1.4f;
    if (s.fontScale < 0.8f) s.fontScale = 0.8f;
    if (s.fontScale > 1.5f) s.fontScale = 1.5f;
    if (s.gridColumns != 0 && s.gridColumns != 3 && s.gridColumns != 4 &&
        s.gridColumns != 5 && s.gridColumns != 6 && s.gridColumns != 8) {
        s.gridColumns = 0;
    }
    if (s.accentSaturation < 0.15f) s.accentSaturation = 0.15f;
    if (s.accentSaturation > 1.0f) s.accentSaturation = 1.0f;
    if (s.accentTone < 0.0f) s.accentTone = 0.0f;
    if (s.accentTone > 1.0f) s.accentTone = 1.0f;
    if (s.accentHue != s.accentHue) s.accentHue = 222.0f; // NaN guard
    while (s.accentHue < 0.0f) s.accentHue += 360.0f;
    while (s.accentHue >= 360.0f) s.accentHue -= 360.0f;
    if (s.themeMode != "system" && s.themeMode != "light" && s.themeMode != "dark") {
        s.themeMode = "system";
    }
    if (s.language != "system" && s.language != "ja" && s.language != "en") {
        s.language = "system";
    }
    return s;
}

void SettingsStore::save(const AppSettings& s) {
    std::ofstream f(filePath_);
    if (!f.is_open()) return;
    f << "{"
      << "\"themeMode\":\"" << s.themeMode << "\","
      << "\"accentHue\":" << s.accentHue << ","
      << "\"accentSaturation\":" << s.accentSaturation << ","
      << "\"accentTone\":" << s.accentTone << ","
      << "\"uiScale\":" << s.uiScale << ","
      << "\"fontScale\":" << s.fontScale << ","
      << "\"gridColumns\":" << s.gridColumns << ","
      << "\"language\":\"" << s.language << "\","
      << "\"searchEngine\":\"" << s.searchEngine << "\","
      << "\"formLoginEnabled\":" << (s.formLoginEnabled ? "true" : "false") << ","
      << "\"fetchBookmarkIcons\":" << (s.fetchBookmarkIcons ? "true" : "false") << ","
      << "\"notificationsEnabled\":" << (s.notificationsEnabled ? "true" : "false")
      << "}";
    f.close();
}
