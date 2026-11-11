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
    // Cache-only. The previous implementation performed a synchronous network
    // request here, and this is called from the collection view's item
    // provider, so every redraw blocked the UI thread on DNS + TCP. Fetching
    // now happens in fetchFaviconAsync; this stays a fast cache lookup.
    std::string cached = cachePath(pageUrl);
    struct stat st;
    if (stat(cached.c_str(), &st) == 0) return cached;
    return "";
}

void FaviconService::fetchFaviconAsync(const std::string& pageUrl, std::function<void(std::string)> done) {
    std::string cached = cachePath(pageUrl);
    struct stat st;
    if (stat(cached.c_str(), &st) == 0) {
        if (done) done(cached);
        return;
    }
    NSString* nsUrl = [NSString stringWithUTF8String:pageUrl.c_str()];
    NSURL* url = nsUrl ? [NSURL URLWithString:nsUrl] : nil;
    if (!url) {
        if (done) done("");
        return;
    }
    NSURL* faviconUrl = [NSURL URLWithString:@"/favicon.ico" relativeToURL:url];
    if (!faviconUrl) {
        if (done) done("");
        return;
    }
    NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL:faviconUrl];
    req.timeoutInterval = 10;
    NSURLSessionDataTask* task = [[NSURLSession sharedSession]
        dataTaskWithRequest:req
          completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
            std::string path;
            if (data.length > 0 && !error) {
                // Reject an HTML error page masquerading as an icon.
                NSHTTPURLResponse* http = (NSHTTPURLResponse*)response;
                BOOL ok = YES;
                if ([http isKindOfClass:[NSHTTPURLResponse class]]) {
                    ok = (http.statusCode >= 200 && http.statusCode < 300);
                }
                if (ok && [data writeToFile:[NSString stringWithUTF8String:cached.c_str()] atomically:YES]) {
                    path = cached;
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (done) done(path);
            });
          }];
    [task resume];
}

std::string FaviconService::monogramFor(const std::string& title) {
    if (title.empty()) return "?";
    // Take the first 1-2 characters. The length of a multi-byte character is
    // read from its lead byte; assuming 3 bytes (as the previous version did)
    // corrupts 2-byte (Latin-1 supplement) and 4-byte (emoji) characters.
    std::string result;
    size_t i = 0;
    int chars = 0;
    while (i < title.size() && chars < 2) {
        unsigned char c = (unsigned char)title[i];
        size_t len;
        if (c < 0x80) {
            len = 1;
        } else if ((c & 0xE0) == 0xC0) {
            len = 2;
        } else if ((c & 0xF0) == 0xE0) {
            len = 3;
        } else if ((c & 0xF8) == 0xF0) {
            len = 4;
        } else {
            // Invalid lead byte: skip it rather than emitting broken UTF-8.
            i++;
            continue;
        }
        if (i + len > title.size()) break;
        if (len == 1) {
            if (isalnum(c)) {
                result += (char)toupper(c);
                chars++;
            }
        } else {
            result += title.substr(i, len);
            chars++;
        }
        i += len;
    }
    if (result.empty()) result = "?";
    return result;
}
