#import <Foundation/Foundation.h>
#include "vpn_store.h"
#include "keychain_helper.h"
#include "json_util.h"
#include "url_util.h"
#include <ctime>
#include <fstream>
#include <sstream>
#include <sys/stat.h>

namespace {

const char* const kService = "half-browser-vpn";

std::string appSupportDir() {
    const char* home = getenv("HOME");
    std::string dir = std::string(home ? home : ".") + "/Library/Application Support/Half-Browser";
    mkdir(dir.c_str(), 0755);
    return dir;
}

/// A collision-resistant id. The Android build uses a timestamp plus a random
/// suffix; here the random part is 16 bytes from the system CSPRNG so two
/// profiles created in the same millisecond cannot collide.
std::string newId() {
    unsigned char buf[16];
    arc4random_buf(buf, sizeof(buf));
    static const char* hex = "0123456789abcdef";
    std::string out;
    out.reserve(32);
    for (unsigned char c : buf) {
        out += hex[c >> 4];
        out += hex[c & 0xF];
    }
    return out;
}

long long nowMillis() {
    return (long long)time(nullptr) * 1000;
}

std::string joinList(const std::vector<std::string>& items) {
    std::string out;
    for (size_t i = 0; i < items.size(); ++i) {
        if (i > 0) out += ",";
        out += items[i];
    }
    return out;
}

std::vector<std::string> splitList(const std::string& s) {
    std::vector<std::string> out;
    std::string cur;
    for (char c : s) {
        if (c == ',') {
            if (!cur.empty()) out.push_back(cur);
            cur.clear();
        } else {
            cur += c;
        }
    }
    if (!cur.empty()) out.push_back(cur);
    return out;
}

}  // namespace

VpnStore& VpnStore::instance() {
    static VpnStore inst;
    return inst;
}

VpnStore::VpnStore() {
    indexPath_ = appSupportDir() + "/vpn_profiles.json";
    load();
}

std::vector<VpnProfile> VpnStore::all() const {
    return profiles_;
}

bool VpnStore::empty() const {
    return profiles_.empty();
}

std::string VpnStore::selectedId() const {
    return selectedId_;
}

void VpnStore::setSelectedId(const std::string& id) {
    selectedId_ = id;
    saveIndex();
}

bool VpnStore::find(const std::string& id, VpnProfile& out) const {
    for (const auto& p : profiles_) {
        if (p.id == id) {
            out = p;
            return true;
        }
    }
    return false;
}

bool VpnStore::save(const VpnProfile& profile) {
    if (profile.id.empty() || profile.configText.empty()) return false;

    // The secret goes to the Keychain first; if that fails we must not record
    // a profile whose config can never be read back.
    if (!KeychainSaveSecret(kService, profile.id, profile.configText)) {
        return false;
    }

    VpnProfile stored = profile;
    if (stored.createdAt == 0) stored.createdAt = nowMillis();
    stored.updatedAt = nowMillis();

    bool replaced = false;
    for (auto& p : profiles_) {
        if (p.id == stored.id) {
            p = stored;
            replaced = true;
            break;
        }
    }
    if (!replaced) {
        profiles_.insert(profiles_.begin(), stored);
    }
    saveIndex();
    return true;
}

bool VpnStore::remove(const std::string& id) {
    bool found = false;
    for (size_t i = 0; i < profiles_.size(); ++i) {
        if (profiles_[i].id == id) {
            profiles_.erase(profiles_.begin() + i);
            found = true;
            break;
        }
    }
    if (!found) return false;
    KeychainDeleteSecret(kService, id);
    if (selectedId_ == id) selectedId_.clear();
    saveIndex();
    return true;
}

bool VpnStore::loadConfig(const std::string& id, std::string& out) const {
    return KeychainLoadSecret(kService, id, out);
}

void VpnStore::load() {
    profiles_.clear();
    selectedId_.clear();
    std::ifstream f(indexPath_);
    if (!f.is_open()) return;
    std::stringstream ss;
    ss << f.rdbuf();
    std::string json = ss.str();

    selectedId_ = JsonUtil::getString(json, "selectedId", "");

    std::vector<std::string> objs = JsonUtil::getObjectArray(json, "items");
    for (const auto& o : objs) {
        VpnProfile p;
        p.id = JsonUtil::getString(o, "id");
        p.name = JsonUtil::getString(o, "name");
        p.endpoint = JsonUtil::getString(o, "endpoint");
        p.addresses = splitList(JsonUtil::getString(o, "addresses"));
        p.dns = splitList(JsonUtil::getString(o, "dns"));
        p.createdAt = JsonUtil::getInt(o, "createdAt", 0);
        p.updatedAt = JsonUtil::getInt(o, "updatedAt", 0);
        if (p.id.empty()) continue;
        profiles_.push_back(p);
    }
}

void VpnStore::saveIndex() const {
    std::ostringstream out;
    out << "{\"version\":1,\"selectedId\":\"" << JsonUtil::escape(selectedId_) << "\",\"items\":[";
    for (size_t i = 0; i < profiles_.size(); ++i) {
        const auto& p = profiles_[i];
        if (i > 0) out << ",";
        out << "{\"id\":\"" << JsonUtil::escape(p.id) << "\""
            << ",\"name\":\"" << JsonUtil::escape(p.name) << "\""
            << ",\"endpoint\":\"" << JsonUtil::escape(p.endpoint) << "\""
            << ",\"addresses\":\"" << JsonUtil::escape(joinList(p.addresses)) << "\""
            << ",\"dns\":\"" << JsonUtil::escape(joinList(p.dns)) << "\""
            << ",\"createdAt\":" << p.createdAt
            << ",\"updatedAt\":" << p.updatedAt
            << "}";
    }
    out << "]}";

    // Atomic write: temp file then rename, so a crash cannot truncate the list.
    std::string tmp = indexPath_ + ".tmp";
    {
        std::ofstream f(tmp, std::ios::binary | std::ios::trunc);
        if (!f.is_open()) return;
        f << out.str();
        f.flush();
        if (!f.good()) return;
    }
    rename(tmp.c_str(), indexPath_.c_str());
}
