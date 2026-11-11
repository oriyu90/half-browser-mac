#import <Foundation/Foundation.h>
#include "settings_store.h"
#include "json_util.h"
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

AppSettings SettingsStore::load() {
    AppSettings s;
    std::ifstream f(filePath_);
    if (!f.is_open()) return s;
    std::stringstream ss;
    ss << f.rdbuf();
    std::string json = ss.str();
    f.close();

    // Exact-key lookups (JsonUtil matches `"key":` so "accentHue" can never
    // pick up "accentHueX") with per-field defaults.
    s.themeMode = JsonUtil::getString(json, "themeMode", s.themeMode);
    s.accentHue = (float)JsonUtil::getDouble(json, "accentHue", s.accentHue);
    s.accentSaturation = (float)JsonUtil::getDouble(json, "accentSaturation", s.accentSaturation);
    s.accentTone = (float)JsonUtil::getDouble(json, "accentTone", s.accentTone);
    s.uiScale = (float)JsonUtil::getDouble(json, "uiScale", s.uiScale);
    s.fontScale = (float)JsonUtil::getDouble(json, "fontScale", s.fontScale);
    s.gridColumns = (int)JsonUtil::getInt(json, "gridColumns", s.gridColumns);
    s.language = JsonUtil::getString(json, "language", s.language);
    s.searchEngine = JsonUtil::getString(json, "searchEngine", s.searchEngine);
    s.fetchBookmarkIcons = JsonUtil::getBool(json, "fetchBookmarkIcons", s.fetchBookmarkIcons);
    s.notificationsEnabled = JsonUtil::getBool(json, "notificationsEnabled", s.notificationsEnabled);

    // v1.9.0 settings. "formLoginEnabled" is the pre-1.9 key for the same
    // switch; honour it only when the new key is absent.
    s.vpnAutoConnect = JsonUtil::getBool(json, "vpnAutoConnect", s.vpnAutoConnect);
    s.vpnAutoReconnect = JsonUtil::getBool(json, "vpnAutoReconnect", s.vpnAutoReconnect);
    s.vpnPowerSaver = JsonUtil::getBool(json, "vpnPowerSaver", s.vpnPowerSaver);
    s.siteWatchEnabled = JsonUtil::getBool(json, "siteWatchEnabled", s.siteWatchEnabled);
    s.siteWatchIntervalMinutes = (int)JsonUtil::getInt(json, "siteWatchIntervalMinutes", s.siteWatchIntervalMinutes);
    s.siteWatchWifiOnly = JsonUtil::getBool(json, "siteWatchWifiOnly", s.siteWatchWifiOnly);
    s.jsGuardEnabled = JsonUtil::getBool(json, "jsGuardEnabled", s.jsGuardEnabled);
    s.formAutofillEnabled = JsonUtil::getBool(json, "formAutofillEnabled",
        JsonUtil::getBool(json, "formLoginEnabled", s.formAutofillEnabled));

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
    if (s.siteWatchIntervalMinutes != 15 && s.siteWatchIntervalMinutes != 30 &&
        s.siteWatchIntervalMinutes != 60 && s.siteWatchIntervalMinutes != 180) {
        s.siteWatchIntervalMinutes = 60;
    }
    return s;
}

void SettingsStore::save(const AppSettings& s) {
    std::ostringstream out;
    out << "{"
      << "\"themeMode\":\"" << JsonUtil::escape(s.themeMode) << "\","
      << "\"accentHue\":" << s.accentHue << ","
      << "\"accentSaturation\":" << s.accentSaturation << ","
      << "\"accentTone\":" << s.accentTone << ","
      << "\"uiScale\":" << s.uiScale << ","
      << "\"fontScale\":" << s.fontScale << ","
      << "\"gridColumns\":" << s.gridColumns << ","
      << "\"language\":\"" << JsonUtil::escape(s.language) << "\","
      << "\"searchEngine\":\"" << JsonUtil::escape(s.searchEngine) << "\","
      << "\"fetchBookmarkIcons\":" << (s.fetchBookmarkIcons ? "true" : "false") << ","
      << "\"notificationsEnabled\":" << (s.notificationsEnabled ? "true" : "false") << ","
      << "\"vpnAutoConnect\":" << (s.vpnAutoConnect ? "true" : "false") << ","
      << "\"vpnAutoReconnect\":" << (s.vpnAutoReconnect ? "true" : "false") << ","
      << "\"vpnPowerSaver\":" << (s.vpnPowerSaver ? "true" : "false") << ","
      << "\"siteWatchEnabled\":" << (s.siteWatchEnabled ? "true" : "false") << ","
      << "\"siteWatchIntervalMinutes\":" << s.siteWatchIntervalMinutes << ","
      << "\"siteWatchWifiOnly\":" << (s.siteWatchWifiOnly ? "true" : "false") << ","
      << "\"jsGuardEnabled\":" << (s.jsGuardEnabled ? "true" : "false") << ","
      << "\"formAutofillEnabled\":" << (s.formAutofillEnabled ? "true" : "false")
      << "}";

    // Atomic write: temp file then rename, so a crash mid-write cannot leave a
    // truncated settings.json behind (same scheme as BookmarkStore::save).
    std::string tmp = filePath_ + ".tmp";
    {
        std::ofstream f(tmp, std::ios::binary | std::ios::trunc);
        if (!f.is_open()) return;
        f << out.str();
        f.flush();
        if (!f.good()) return;
    }
    rename(tmp.c_str(), filePath_.c_str());
}
