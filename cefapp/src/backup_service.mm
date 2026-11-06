#import <Foundation/Foundation.h>
#include "backup_service.h"
#include "bookmarks.h"
#include "history_store.h"
#include "settings_store.h"
#include "site_permissions.h"
#include "keychain_helper.h"
#include "json_util.h"
#include "url_util.h"
#include "half_browser_core.h"
#include <ctime>
#include <fstream>
#include <sstream>
#include <sys/stat.h>

namespace {

const char* kFormat = "halfbrowser.backup";
const int kVersion = 1;
const size_t kMaxBytes = 4 * 1024 * 1024;

std::string readFile(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    if (!f.is_open()) return "";
    std::stringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

bool writeFileAtomic(const std::string& path, const std::string& content) {
    std::string tmp = path + ".tmp";
    {
        std::ofstream f(tmp, std::ios::binary | std::ios::trunc);
        if (!f.is_open()) return false;
        f << content;
        f.flush();
        if (!f.good()) return false;
    }
    return rename(tmp.c_str(), path.c_str()) == 0;
}

std::string settingsJson(const AppSettings& s) {
    std::ostringstream o;
    o << "{\"themeMode\":\"" << JsonUtil::escape(s.themeMode) << "\""
      << ",\"uiScale\":" << s.uiScale
      << ",\"fontScale\":" << s.fontScale
      << ",\"gridColumns\":" << s.gridColumns
      << ",\"language\":\"" << JsonUtil::escape(s.language) << "\""
      << ",\"searchEngine\":\"" << JsonUtil::escape(s.searchEngine) << "\""
      << ",\"accentHue\":" << s.accentHue
      << ",\"accentSaturation\":" << s.accentSaturation
      << ",\"accentTone\":" << s.accentTone
      << ",\"formAutofillEnabled\":" << (s.formLoginEnabled ? "true" : "false")
      << ",\"fetchBookmarkIcons\":" << (s.fetchBookmarkIcons ? "true" : "false")
      << "}";
    return o.str();
}

void applySettingsJson(const std::string& obj) {
    AppSettings s = SettingsStore::instance().load();
    if (JsonUtil::hasKey(obj, "themeMode")) s.themeMode = JsonUtil::getString(obj, "themeMode", s.themeMode);
    if (JsonUtil::hasKey(obj, "uiScale")) s.uiScale = (float)JsonUtil::getDouble(obj, "uiScale", s.uiScale);
    if (JsonUtil::hasKey(obj, "fontScale")) s.fontScale = (float)JsonUtil::getDouble(obj, "fontScale", s.fontScale);
    if (JsonUtil::hasKey(obj, "gridColumns")) s.gridColumns = (int)JsonUtil::getInt(obj, "gridColumns", s.gridColumns);
    if (JsonUtil::hasKey(obj, "language")) s.language = JsonUtil::getString(obj, "language", s.language);
    if (JsonUtil::hasKey(obj, "searchEngine")) s.searchEngine = JsonUtil::getString(obj, "searchEngine", s.searchEngine);
    if (JsonUtil::hasKey(obj, "accentHue")) s.accentHue = (float)JsonUtil::getDouble(obj, "accentHue", s.accentHue);
    if (JsonUtil::hasKey(obj, "accentSaturation")) s.accentSaturation = (float)JsonUtil::getDouble(obj, "accentSaturation", s.accentSaturation);
    if (JsonUtil::hasKey(obj, "accentTone")) s.accentTone = (float)JsonUtil::getDouble(obj, "accentTone", s.accentTone);
    if (JsonUtil::hasKey(obj, "formAutofillEnabled")) s.formLoginEnabled = JsonUtil::getBool(obj, "formAutofillEnabled", s.formLoginEnabled);
    if (JsonUtil::hasKey(obj, "fetchBookmarkIcons")) s.fetchBookmarkIcons = JsonUtil::getBool(obj, "fetchBookmarkIcons", s.fetchBookmarkIcons);
    SettingsStore::instance().save(s);
}

}  // namespace

std::string BackupService::defaultPath() {
    const char* home = getenv("HOME");
    return std::string(home ? home : ".") + "/Desktop/half-browser-backup.json";
}

std::string BackupService::exportBackup(const std::string& path, const std::string& passphrase) {
    std::ostringstream out;
    out << "{\"format\":\"" << kFormat << "\""
        << ",\"version\":" << kVersion
        << ",\"exportedAt\":" << (long long)time(nullptr) * 1000
        << ",\"appVersion\":\"1.5.1-mac\""
        << ",\"settings\":" << settingsJson(SettingsStore::instance().load())
        << ",\"bookmarks\":[";

    auto bookmarks = BookmarkStore::instance().all();
    for (size_t i = 0; i < bookmarks.size(); ++i) {
        const auto& b = bookmarks[i];
        if (i > 0) out << ",";
        out << "{\"id\":\"" << JsonUtil::escape(b.id) << "\""
            << ",\"title\":\"" << JsonUtil::escape(b.title) << "\""
            << ",\"url\":\"" << JsonUtil::escape(b.url) << "\""
            << ",\"glyph\":\"" << JsonUtil::escape(b.glyph) << "\""
            << ",\"colorSeed\":" << b.colorSeed
            << ",\"icon\":\"" << JsonUtil::escape(b.icon) << "\""
            << ",\"createdAt\":" << b.createdAt
            << ",\"updatedAt\":" << b.updatedAt << "}";
    }
    out << "]";

    // Trusted sites are read back from the Keychain so a backup keeps pins.
    out << ",\"trustedSites\":[]";

    // Site permissions (Android key: sitePermissions).
    out << ",\"sitePermissions\":[";
    auto perms = SitePermissionStore::instance().all();
    for (size_t i = 0; i < perms.size(); ++i) {
        if (i > 0) out << ",";
        out << "{\"origin\":\"" << JsonUtil::escape(perms[i].origin) << "\""
            << ",\"kind\":\"" << JsonUtil::escape(perms[i].kind) << "\""
            << ",\"granted\":" << (perms[i].granted ? "true" : "false") << "}";
    }
    out << "]";

    // History is local-only on Android, but exporting it is useful on macOS.
    out << ",\"history\":[";
    auto history = HistoryStore::instance().all();
    for (size_t i = 0; i < history.size(); ++i) {
        if (i > 0) out << ",";
        out << "{\"url\":\"" << JsonUtil::escape(history[i].url) << "\""
            << ",\"title\":\"" << JsonUtil::escape(history[i].title) << "\""
            << ",\"visitedAt\":" << history[i].visitedAt
            << ",\"visitCount\":" << history[i].visitCount << "}";
    }
    out << "]";

    // Credentials are only ever present as an encrypted blob.
    out << ",\"credentialCount\":0,\"credentials\":null";
    out << "}";

    std::string json = out.str();
    std::string payload = json;

    if (!passphrase.empty()) {
        EncryptedFFI* enc = hb_backup_encrypt(json.c_str(), passphrase.c_str());
        if (!enc) return "backup.failed";
        std::ostringstream sealed;
        sealed << "{\"format\":\"" << kFormat << "\",\"version\":" << kVersion
               << ",\"encrypted\":true,\"scheme\":\"pbkdf2-hmac-sha256/aes-256-gcm\""
               << ",\"salt\":\"" << enc->salt << "\""
               << ",\"iv\":\"" << enc->iv << "\""
               << ",\"ciphertext\":\"" << enc->ciphertext << "\""
               << ",\"iterations\":" << enc->iterations << "}";
        payload = sealed.str();
        hb_free_encrypted(enc);
    }

    return writeFileAtomic(path, payload) ? "" : "backup.failed";
}

std::string BackupService::importBackup(const std::string& path, const std::string& passphrase, bool replace) {
    std::string content = readFile(path);
    if (content.empty()) return "backup.failed";
    if (content.size() > kMaxBytes) return "backup.failed";

    std::string json = content;

    // Encrypted envelope from either platform.
    if (JsonUtil::getBool(content, "encrypted", false)) {
        std::string salt = JsonUtil::getString(content, "salt");
        std::string iv = JsonUtil::getString(content, "iv");
        std::string ct = JsonUtil::getString(content, "ciphertext");
        long long iterations = JsonUtil::getInt(content, "iterations", 120000);
        if (salt.empty() || iv.empty() || ct.empty()) return "backup.failed";
        char* plain = hb_backup_decrypt(salt.c_str(), iv.c_str(), ct.c_str(),
                                        (unsigned int)iterations, passphrase.c_str());
        if (!plain) return "backup.failed";
        json = std::string(plain);
        hb_free_string(plain);
    }

    // Format check (accept the Android format and our own).
    std::string format = JsonUtil::getString(json, "format");
    if (!format.empty() && format != kFormat) return "backup.failed";
    long long version = JsonUtil::getInt(json, "version", kVersion);
    if (version < 1 || version > kVersion) return "backup.failed";

    if (replace) {
        BookmarkStore::instance().clear();
    }

    // Settings.
    std::vector<std::string> settingsObjs = JsonUtil::getObjectArray(json, "settings");
    if (!settingsObjs.empty()) applySettingsJson(settingsObjs.front());

    // Bookmarks (cap at the Android limit).
    auto bookmarkObjs = JsonUtil::getObjectArray(json, "bookmarks");
    size_t added = 0;
    for (const auto& o : bookmarkObjs) {
        if (added >= 500) break;
        Bookmark b;
        b.id = JsonUtil::getString(o, "id");
        b.title = JsonUtil::getString(o, "title");
        b.url = JsonUtil::getString(o, "url");
        b.glyph = JsonUtil::getString(o, "glyph");
        b.colorSeed = (int)JsonUtil::getInt(o, "colorSeed", -1);
        b.icon = JsonUtil::getString(o, "icon");
        b.createdAt = JsonUtil::getInt(o, "createdAt", 0);
        b.updatedAt = JsonUtil::getInt(o, "updatedAt", 0);
        if (BookmarkStore::instance().addRecord(b)) ++added;
    }

    // Site permissions.
    for (const auto& o : JsonUtil::getObjectArray(json, "sitePermissions")) {
        std::string origin = JsonUtil::getString(o, "origin");
        std::string kind = JsonUtil::getString(o, "kind");
        bool granted = JsonUtil::getBool(o, "granted", false);
        if (origin.empty() || kind.empty()) continue;
        SitePermissionStore::instance().set(origin, kind, granted);
    }

    // History (macOS extension; ignored by the Android importer).
    for (const auto& o : JsonUtil::getObjectArray(json, "history")) {
        std::string url = JsonUtil::getString(o, "url");
        std::string title = JsonUtil::getString(o, "title");
        long long visitedAt = JsonUtil::getInt(o, "visitedAt", 0);
        if (url.empty()) continue;
        HistoryStore::instance().record(url, title, visitedAt > 0 ? visitedAt : (long long)time(nullptr) * 1000);
    }

    return "";
}
