#import <Foundation/Foundation.h>
#include "history_store.h"
#include "json_util.h"
#include "url_util.h"
#include <fstream>
#include <sstream>
#include <sys/stat.h>
#include <sys/types.h>
#include <ctime>

HistoryStore& HistoryStore::instance() {
    static HistoryStore inst;
    return inst;
}

HistoryStore::HistoryStore() {
    const char* home = getenv("HOME");
    std::string dir = std::string(home) + "/Library/Application Support/Half-Browser";
    mkdir(dir.c_str(), 0755);
    filePath_ = dir + "/history.json";
    load();
}

void HistoryStore::record(const std::string& url, const std::string& title, long long now) {
    // Only web URLs are recorded (mirrors Android HistoryRules).
    std::string normalized = UrlUtil::validateWebUrl(url);
    if (normalized.empty()) return;
    std::string canonical = UrlUtil::canonicalForCompare(normalized);

    // Check if the same page is already present (canonical compare).
    int existingIndex = -1;
    for (size_t i = 0; i < entries_.size(); i++) {
        if (UrlUtil::canonicalForCompare(entries_[i].url) == canonical) {
            existingIndex = (int)i;
            break;
        }
    }

    if (existingIndex >= 0) {
        auto& existing = entries_[existingIndex];
        bool recent = (now - existing.visitedAt) <= MERGE_WINDOW_MS;
        existing.title = title.empty() ? existing.title : title;
        existing.visitedAt = now;
        if (!recent) existing.visitCount++;
        // Move to front
        HistoryEntry updated = existing;
        updated.url = normalized;
        entries_.erase(entries_.begin() + existingIndex);
        entries_.insert(entries_.begin(), updated);
    } else {
        HistoryEntry entry;
        entry.url = normalized;
        entry.title = title.substr(0, 300);
        entry.visitedAt = now;
        entry.visitCount = 1;
        entries_.insert(entries_.begin(), entry);
    }

    // Trim to MAX_ENTRIES
    if ((int)entries_.size() > MAX_ENTRIES) {
        entries_.resize(MAX_ENTRIES);
    }
    save();
}

std::vector<HistoryEntry> HistoryStore::all() const {
    return entries_;
}

void HistoryStore::clear() {
    entries_.clear();
    save();
}

void HistoryStore::load() {
    entries_.clear();
    std::ifstream f(filePath_);
    if (!f.is_open()) return;
    std::stringstream ss;
    ss << f.rdbuf();
    std::string json = ss.str();

    std::vector<std::string> objs = JsonUtil::getObjectArray(json, "items");
    if (objs.empty()) objs = JsonUtil::getObjectArray(json, "");

    for (const auto& o : objs) {
        HistoryEntry e;
        e.url = JsonUtil::getString(o, "url");
        e.title = JsonUtil::getString(o, "title");
        e.visitedAt = JsonUtil::getInt(o, "visitedAt", 0);
        e.visitCount = (int)JsonUtil::getInt(o, "visitCount", 1);
        if (e.url.empty()) continue;
        if (UrlUtil::validateWebUrl(e.url).empty()) continue;
        entries_.push_back(e);
        if ((int)entries_.size() >= MAX_ENTRIES) break;
    }
}

void HistoryStore::save() {
    std::ostringstream out;
    out << "{\"version\":1,\"items\":[";
    for (size_t i = 0; i < entries_.size(); ++i) {
        const auto& e = entries_[i];
        if (i > 0) out << ",";
        out << "{\"url\":\"" << JsonUtil::escape(e.url) << "\""
            << ",\"title\":\"" << JsonUtil::escape(e.title) << "\""
            << ",\"visitedAt\":" << e.visitedAt
            << ",\"visitCount\":" << e.visitCount << "}";
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
