#import <Foundation/Foundation.h>
#include "bookmarks.h"
#include "json_util.h"
#include "url_util.h"
#include <algorithm>
#include <cctype>
#include <ctime>
#include <fstream>
#include <sstream>
#include <sys/stat.h>
#include <sys/types.h>

namespace {

std::string appSupportDir() {
    const char* home = getenv("HOME");
    std::string dir = std::string(home ? home : ".") + "/Library/Application Support/Half-Browser";
    mkdir(dir.c_str(), 0755);
    return dir;
}

// 16 random bytes as hex. IDs are opaque strings on load, so this stays
// compatible with the old "<time>-<random>" form while making a collision
// inside the same second (even the same millisecond) negligible.
std::string newId() {
    unsigned char bytes[16];
    arc4random_buf(bytes, sizeof(bytes));
    static const char* hex = "0123456789abcdef";
    std::string out;
    out.reserve(sizeof(bytes) * 2);
    for (unsigned char b : bytes) {
        out += hex[b >> 4];
        out += hex[b & 0x0F];
    }
    return out;
}

}  // namespace

BookmarkStore& BookmarkStore::instance() {
    static BookmarkStore inst;
    return inst;
}

BookmarkStore::BookmarkStore() {
    filePath_ = appSupportDir() + "/bookmarks.json";
    load();
}

std::string BookmarkStore::iconsDir() const {
    std::string dir = appSupportDir() + "/bookmark_icons";
    mkdir(dir.c_str(), 0755);
    return dir;
}

bool BookmarkStore::add(const std::string& title, const std::string& url) {
    std::string validated = UrlUtil::validateWebUrl(url);
    if (validated.empty()) return false;

    std::string canonical = UrlUtil::canonicalForCompare(validated);
    for (const auto& b : bookmarks_) {
        if (UrlUtil::canonicalForCompare(b.url) == canonical) return false;
    }

    Bookmark b;
    b.id = newId();
    b.title = title.empty() ? UrlUtil::displayHost(validated) : title;
    b.url = validated;
    b.createdAt = (long long)time(nullptr) * 1000;
    b.updatedAt = b.createdAt;
    bookmarks_.insert(bookmarks_.begin(), b);
    save();
    return true;
}

bool BookmarkStore::addRecord(const Bookmark& record) {
    std::string validated = UrlUtil::validateWebUrl(record.url);
    if (validated.empty()) return false;
    std::string canonical = UrlUtil::canonicalForCompare(validated);
    for (const auto& b : bookmarks_) {
        if (UrlUtil::canonicalForCompare(b.url) == canonical) return false;
    }
    Bookmark b = record;
    if (b.id.empty()) b.id = newId();
    b.url = validated;
    if (b.title.empty()) b.title = UrlUtil::displayHost(validated);
    if (b.createdAt == 0) b.createdAt = (long long)time(nullptr) * 1000;
    if (b.updatedAt == 0) b.updatedAt = b.createdAt;
    bookmarks_.insert(bookmarks_.begin(), b);
    save();
    return true;
}

bool BookmarkStore::remove(const std::string& url) {
    std::string canonical = UrlUtil::canonicalForCompare(url);
    size_t before = bookmarks_.size();
    bookmarks_.erase(std::remove_if(bookmarks_.begin(), bookmarks_.end(),
        [&](const Bookmark& b) { return UrlUtil::canonicalForCompare(b.url) == canonical; }),
        bookmarks_.end());
    if (bookmarks_.size() == before) return false;
    save();
    return true;
}

bool BookmarkStore::removeById(const std::string& id) {
    size_t before = bookmarks_.size();
    bookmarks_.erase(std::remove_if(bookmarks_.begin(), bookmarks_.end(),
        [&](const Bookmark& b) { return b.id == id; }),
        bookmarks_.end());
    if (bookmarks_.size() == before) return false;
    save();
    return true;
}

bool BookmarkStore::update(const std::string& id, const std::string& title, const std::string& url) {
    std::string validated = UrlUtil::validateWebUrl(url);
    if (validated.empty()) return false;
    for (auto& b : bookmarks_) {
        if (b.id != id) continue;
        b.title = title.empty() ? UrlUtil::displayHost(validated) : title;
        b.url = validated;
        b.updatedAt = (long long)time(nullptr) * 1000;
        save();
        return true;
    }
    return false;
}

bool BookmarkStore::find(const std::string& url, Bookmark& out) const {
    std::string canonical = UrlUtil::canonicalForCompare(url);
    for (const auto& b : bookmarks_) {
        if (UrlUtil::canonicalForCompare(b.url) == canonical) {
            out = b;
            return true;
        }
    }
    return false;
}

void BookmarkStore::clear() {
    bookmarks_.clear();
    save();
}

void BookmarkStore::load() {
    bookmarks_.clear();
    std::ifstream f(filePath_);
    if (!f.is_open()) return;
    std::stringstream ss;
    ss << f.rdbuf();
    std::string json = ss.str();

    // Accept both the Android envelope {"version":1,"items":[...]} and a bare array.
    std::vector<std::string> objs = JsonUtil::getObjectArray(json, "items");
    if (objs.empty()) objs = JsonUtil::getObjectArray(json, "");

    for (const auto& o : objs) {
        Bookmark b;
        b.id = JsonUtil::getString(o, "id");
        b.title = JsonUtil::getString(o, "title");
        b.url = JsonUtil::getString(o, "url");
        b.glyph = JsonUtil::getString(o, "glyph");
        b.colorSeed = (int)JsonUtil::getInt(o, "colorSeed", -1);
        b.icon = JsonUtil::getString(o, "icon");
        b.createdAt = JsonUtil::getInt(o, "createdAt", 0);
        b.updatedAt = JsonUtil::getInt(o, "updatedAt", 0);
        if (b.url.empty()) continue;
        if (b.id.empty()) b.id = newId();
        if (b.title.empty()) b.title = UrlUtil::displayHost(b.url);
        bookmarks_.push_back(b);
    }
}

void BookmarkStore::save() {
    std::ostringstream out;
    out << "{\"version\":1,\"items\":[";
    for (size_t i = 0; i < bookmarks_.size(); ++i) {
        const auto& b = bookmarks_[i];
        if (i > 0) out << ",";
        out << "{\"id\":\"" << JsonUtil::escape(b.id) << "\""
            << ",\"title\":\"" << JsonUtil::escape(b.title) << "\""
            << ",\"url\":\"" << JsonUtil::escape(b.url) << "\""
            << ",\"glyph\":\"" << JsonUtil::escape(b.glyph) << "\""
            << ",\"colorSeed\":" << b.colorSeed
            << ",\"icon\":\"" << JsonUtil::escape(b.icon) << "\""
            << ",\"createdAt\":" << b.createdAt
            << ",\"updatedAt\":" << b.updatedAt
            << "}";
    }
    out << "]}";

    // Atomic write: temp file then rename, so a crash cannot truncate the list.
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

std::string BookmarkStore::monogram(const Bookmark& b) {
    if (!b.glyph.empty()) return b.glyph;
    std::string source = b.title;
    if (source.empty()) source = UrlUtil::displayHost(b.url);
    std::string out;
    size_t i = 0;
    while (i < source.size() && out.size() < 2) {
        unsigned char c = source[i];
        if (c < 0x80) {
            if (isalnum(c)) out += (char)toupper(c);
            i += 1;
        } else {
            size_t len = (c >= 0xF0) ? 4 : (c >= 0xE0) ? 3 : 2;
            out += source.substr(i, len);
            i += len;
        }
    }
    if (out.empty()) out = "?";
    return out;
}

int BookmarkStore::colorIndex(const Bookmark& b) {
    if (b.colorSeed >= 0) return b.colorSeed % 8;
    unsigned long long h = 1469598103934665603ULL;
    for (unsigned char c : b.url) {
        h ^= c;
        h *= 1099511628211ULL;
    }
    return (int)(h % 8);
}
