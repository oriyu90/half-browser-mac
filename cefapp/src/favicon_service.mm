#import <Cocoa/Cocoa.h>
#include "favicon_service.h"
#include <sys/stat.h>
#include <fstream>
#include <sstream>
#include <ctime>

static std::string hashUrl(const std::string& url) {
    // Simple FNV-1a hash for cache key
    unsigned long long h = 14695981039346656037ULL;
    for (char c : url) { h ^= (unsigned char)c; h *= 1099511628211ULL; }
    std::ostringstream ss;
    ss << std::hex << h;
    return ss.str();
}

std::string FaviconService::cacheDir() {
    const char* home = getenv("HOME");
    std::string dir = std::string(home) + "/Library/Application Support/Half-Browser/favicons";
    mkdir(dir.c_str(), 0755);
    return dir;
}

std::string FaviconService::cachePath(const std::string& url) {
    return cacheDir() + "/" + hashUrl(url) + ".png";
}

std::string FaviconService::fetchFavicon(const std::string& pageUrl) {
    std::string cached = cachePath(pageUrl);
    struct stat st;
    if (stat(cached.c_str(), &st) == 0) return cached;

    // Try to fetch /favicon.ico
    NSString* nsUrl = [NSString stringWithUTF8String:pageUrl.c_str()];
    NSURL* url = [NSURL URLWithString:nsUrl];
    if (!url) return "";
    NSURL* faviconUrl = [NSURL URLWithString:@"/favicon.ico" relativeToURL:url];
    NSData* data = [NSData dataWithContentsOfURL:faviconUrl options:0 error:nil];
    if (!data || data.length == 0) return "";
    [data writeToFile:[NSString stringWithUTF8String:cached.c_str()] atomically:YES];
    return cached;
}

std::string FaviconService::monogramFor(const std::string& title) {
    if (title.empty()) return "?";
    // Take first 1-2 characters
    std::string result;
    size_t i = 0;
    while (i < title.size() && result.size() < 2) {
        unsigned char c = title[i];
        if (c < 0x80) {
            if (isalnum(c)) result += toupper(c);
            i++;
        } else {
            result += title.substr(i, 3);
            i += 3;
        }
    }
    if (result.empty()) result = "?";
    return result;
}
