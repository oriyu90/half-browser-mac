#import <Foundation/Foundation.h>
#include "site_permissions.h"
#include "json_util.h"
#include "url_util.h"
#include <ctime>
#include <fstream>
#include <sstream>
#include <sys/stat.h>

SitePermissionStore& SitePermissionStore::instance() {
    static SitePermissionStore inst;
    return inst;
}

SitePermissionStore::SitePermissionStore() {
    const char* home = getenv("HOME");
    std::string dir = std::string(home) + "/Library/Application Support/Half-Browser";
    mkdir(dir.c_str(), 0755);
    filePath_ = dir + "/permissions.json";
    load();
}

namespace {
std::string normalizeKind(const std::string& kind) {
    if (kind == "notification") return "notifications";
    if (kind == "media") return "camera";
    return kind;
}
}  // namespace

bool SitePermissionStore::isGranted(const std::string& origin, const std::string& kind) {
    std::string k = normalizeKind(kind);
    for (auto& p : perms_) {
        if (p.origin == origin && p.kind == k) return p.granted;
    }
    return false;
}

void SitePermissionStore::set(const std::string& origin, const std::string& kind, bool granted) {
    std::string k = normalizeKind(kind);
    long long now = (long long)time(nullptr) * 1000;
    for (auto& p : perms_) {
        if (p.origin == origin && p.kind == k) {
            p.granted = granted;
            p.updatedAt = now;
            save();
            return;
        }
    }
    SitePermission p;
    p.origin = origin;
    p.kind = k;
    p.granted = granted;
    p.updatedAt = now;
    perms_.push_back(p);
    save();
}

void SitePermissionStore::reset(const std::string& origin) {
    std::vector<SitePermission> filtered;
    for (auto& p : perms_) {
        if (p.origin != origin) filtered.push_back(p);
    }
    perms_ = filtered;
    save();
}

std::vector<SitePermission> SitePermissionStore::all() const { return perms_; }

void SitePermissionStore::load() {
    perms_.clear();
    std::ifstream f(filePath_);
    if (!f.is_open()) return;
    std::stringstream ss;
    ss << f.rdbuf();
    std::string json = ss.str();

    std::vector<std::string> objs = JsonUtil::getObjectArray(json, "items");
    if (objs.empty()) objs = JsonUtil::getObjectArray(json, "");

    for (const auto& o : objs) {
        SitePermission p;
        p.origin = JsonUtil::getString(o, "origin");
        p.kind = normalizeKind(JsonUtil::getString(o, "kind"));
        p.granted = JsonUtil::getBool(o, "granted", false);
        p.updatedAt = JsonUtil::getInt(o, "updatedAt", 0);
        if (p.origin.empty() || p.kind.empty()) continue;
        if (UrlUtil::origin(p.origin).empty()) continue;
        perms_.push_back(p);
    }
}

void SitePermissionStore::save() {
    std::ostringstream out;
    out << "{\"version\":1,\"items\":[";
    for (size_t i = 0; i < perms_.size(); ++i) {
        const auto& p = perms_[i];
        if (i > 0) out << ",";
        out << "{\"origin\":\"" << JsonUtil::escape(p.origin) << "\""
            << ",\"kind\":\"" << JsonUtil::escape(p.kind) << "\""
            << ",\"granted\":" << (p.granted ? "true" : "false")
            << ",\"updatedAt\":" << p.updatedAt << "}";
    }
    out << "]}";

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
