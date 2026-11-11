#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>
#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <CommonCrypto/CommonDigest.h>
#include <sys/stat.h>
#include <algorithm>
#include <cstdio>
#include <fstream>
#include <sstream>

#include "site_watch.h"
#include "bookmarks.h"
#include "json_util.h"
#include "localization.h"
#include "settings_store.h"
#include "url_util.h"

static const char* const kWatchFileVersion = "1";
static const double kWatchTimeoutSeconds = 15.0;
static const char* const kWatchUserAgent = "Half-Browser/1.9.0";
/// Hard ceiling on a single body: a huge page would otherwise be hashed into
/// hundreds of MB of RAM. Pages above this are truncated (still stable).
static const NSUInteger kWatchMaxBodyBytes = 8u * 1024u * 1024u;

/// Notification identifiers are per-URL so a second change to the same site
/// replaces the first banner instead of stacking up.
static NSString* WatchNotificationId(const std::string& url) {
    NSString* s = [NSString stringWithUTF8String:url.c_str()];
    if (!s) return @"half-browser.sitewatch";
    return [@"half-browser.sitewatch." stringByAppendingString:s];
}

// ============================================================
// Pure helpers
// ============================================================

std::string SiteWatch::sha256Hex(const std::string& data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.data(), (CC_LONG)data.size(), digest);
    static const char* hex = "0123456789abcdef";
    std::string out;
    out.reserve(CC_SHA256_DIGEST_LENGTH * 2);
    for (unsigned char c : digest) {
        out += hex[c >> 4];
        out += hex[c & 0xF];
    }
    return out;
}

SiteWatchVerdict SiteWatch::classify(const std::string& previousHash,
                                     const std::string& newHash) {
    if (newHash.empty()) return SiteWatchVerdict::Unchanged;
    if (previousHash.empty()) return SiteWatchVerdict::Baseline;
    return previousHash == newHash ? SiteWatchVerdict::Unchanged : SiteWatchVerdict::Changed;
}

int SiteWatch::sanitizeInterval(int minutes) {
    if (minutes == 15 || minutes == 30 || minutes == 60 || minutes == 180) return minutes;
    return 60;
}

bool SiteWatch::isFetchable(const std::string& url) {
    if (url.size() < 9) return false;
    return url.rfind("https://", 0) == 0 || url.rfind("http://", 0) == 0;
}

std::string SiteWatch::siteName(const std::string& url) {
    std::string host = UrlUtil::displayHost(url);
    if (host.empty()) return url;
    if (host.rfind("www.", 0) == 0 && host.size() > 4) host = host.substr(4);
    return host;
}

bool SiteWatch::wifiAvailable() {
    // en0 is the built-in Wi-Fi interface on every Mac; Thunderbolt/USB
    // adapters show up as en1..en7. We only need "is some Wi-Fi link up",
    // which is all the Wi-Fi-only setting promises.
    struct ifaddrs* list = nullptr;
    if (getifaddrs(&list) != 0) return false;
    bool up = false;
    for (struct ifaddrs* p = list; p; p = p->ifa_next) {
        if (!p->ifa_name) continue;
        if (!(p->ifa_flags & IFF_UP) || (p->ifa_flags & IFF_LOOPBACK)) continue;
        if (p->ifa_addr && p->ifa_addr->sa_family != AF_INET) continue;
        std::string name = p->ifa_name;
        if (name.rfind("en", 0) != 0 || name.size() < 3) continue;
        // en0..en7 only; "en" followed by a digit.
        bool digits = true;
        for (size_t i = 2; i < name.size(); ++i) {
            if (name[i] < '0' || name[i] > '9') digits = false;
        }
        if (!digits) continue;
        up = true;
        break;
    }
    freeifaddrs(list);
    return up;
}

// ============================================================
// Persistence
// ============================================================

std::string SiteWatch::serialize(const std::vector<SiteWatchItem>& items, long long lastCheck,
                                 const std::string& lastError) {
    std::ostringstream out;
    out << "{\"version\":" << kWatchFileVersion
        << ",\"lastCheck\":" << lastCheck
        << ",\"lastError\":\"" << JsonUtil::escape(lastError) << "\""
        << ",\"items\":[";
    for (size_t i = 0; i < items.size(); ++i) {
        const SiteWatchItem& it = items[i];
        if (i) out << ",";
        out << "{\"url\":\"" << JsonUtil::escape(it.url) << "\""
            << ",\"hash\":\"" << JsonUtil::escape(it.hash) << "\""
            << ",\"checkedAt\":" << it.checkedAt
            << ",\"title\":\"" << JsonUtil::escape(it.title) << "\"}";
    }
    out << "]}";
    return out.str();
}

bool SiteWatch::parse(const std::string& json, std::vector<SiteWatchItem>& items,
                      long long& lastCheck, std::string& lastError) {
    items.clear();
    lastCheck = 0;
    lastError.clear();
    // An empty or truncated file is a fresh start, not an error.
    if (json.find('{') == std::string::npos) return false;

    lastCheck = JsonUtil::getInt(json, "lastCheck", 0);
    if (lastCheck < 0) lastCheck = 0;
    lastError = JsonUtil::getString(json, "lastError", "");

    // getObjectArray stops at the array's closing bracket and skips string
    // contents, so a stray brace in a title cannot split a record.
    for (const std::string& obj : JsonUtil::getObjectArray(json, "items")) {
        SiteWatchItem it;
        it.url = JsonUtil::getString(obj, "url", "");
        it.hash = JsonUtil::getString(obj, "hash", "");
        it.checkedAt = JsonUtil::getInt(obj, "checkedAt", 0);
        it.title = JsonUtil::getString(obj, "title", "");
        if (it.url.empty()) continue;               // unusable record
        if (!isFetchable(it.url)) continue;         // never fetch file:/javascript:
        if (it.checkedAt < 0) it.checkedAt = 0;
        // A hash must be 64 lowercase hex characters; anything else is treated
        // as "no baseline" so the next check re-takes it instead of notifying
        // against garbage.
        if (it.hash.size() != 64 ||
            it.hash.find_first_not_of("0123456789abcdef") != std::string::npos) {
            it.hash.clear();
        }
        items.push_back(it);
    }
    return true;
}

SiteWatch::SiteWatch() {
    const char* home = getenv("HOME");
    std::string dir = std::string(home ? home : "/tmp") + "/Library/Application Support/Half-Browser";
    mkdir(dir.c_str(), 0755);
    filePath_ = dir + "/site_watch.json";
    tasks_ = (void*)[[NSMutableArray alloc] init];
    load();
}

SiteWatch::~SiteWatch() {
    shutdown();
}

SiteWatch& SiteWatch::instance() {
    static SiteWatch inst;
    return inst;
}

void SiteWatch::setFilePathForTesting(const char* path) {
    if (!path) return;
    filePath_ = path;
    items_.clear();
    lastCheck_ = 0;
    lastError_.clear();
}

void SiteWatch::load() {
    items_.clear();
    lastCheck_ = 0;
    lastError_.clear();
    std::ifstream f(filePath_, std::ios::binary);
    if (!f.is_open()) return;
    std::stringstream ss;
    ss << f.rdbuf();
    f.close();
    std::vector<SiteWatchItem> parsed;
    long long check = 0;
    std::string err;
    parse(ss.str(), parsed, check, err);
    items_ = parsed;
    lastCheck_ = check;
    lastError_ = err;
}

void SiteWatch::save() {
    std::string blob = serialize(items_, lastCheck_, lastError_);
    std::string tmp = filePath_ + ".tmp";
    {
        std::ofstream f(tmp, std::ios::binary | std::ios::trunc);
        if (!f.is_open()) return;
        f << blob;
        f.flush();
        if (!f.good()) return;
    }
    rename(tmp.c_str(), filePath_.c_str());
}

// ============================================================
// Scheduling
// ============================================================

void SiteWatch::applySettings() {
    AppSettings s = SettingsStore::instance().load();
    if (!s.siteWatchEnabled) {
        invalidateTimer();
        running_ = false;
        return;
    }
    running_ = true;
    // Ask for notification permission only now — never at launch — so the
    // system prompt appears in direct response to the user switching the
    // feature on.
    dispatch_async(dispatch_get_main_queue(), ^{
        UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
        [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound)
                              completionHandler:^(BOOL granted, NSError* error) {
            // Nothing to do either way: without permission the change is still
            // recorded and shown in Settings.
            (void)granted;
            (void)error;
        }];
    });
    scheduleTimer();
}

void SiteWatch::scheduleTimer() {
    invalidateTimer();
    if (!running_) return;
    AppSettings s = SettingsStore::instance().load();
    int minutes = sanitizeInterval(s.siteWatchIntervalMinutes);
    // The run loop owns a repeating timer; CFBridgingRetain takes a second
    // reference that invalidateTimer() releases exactly once.
    NSTimer* timer = [NSTimer scheduledTimerWithTimeInterval:(NSTimeInterval)minutes * 60.0
                                                     repeats:YES
                                                       block:^(NSTimer* t) {
        (void)t;
        SiteWatch::instance().beginCycle();
    }];
    timer_ = (void*)CFBridgingRetain(timer);
    // The first cycle runs shortly after enabling so the user sees a result
    // without waiting a full interval.
    int gen = generation_;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        SiteWatch::instance().dispatchCycleIfCurrent(gen);
    });
}

void SiteWatch::invalidateTimer() {
    if (timer_) {
        NSTimer* timer = (__bridge NSTimer*)timer_;
        [timer invalidate];
        CFRelease(timer_);
        timer_ = nullptr;
    }
}

void SiteWatch::shutdown() {
    running_ = false;
    cycleActive_ = false;
    ++generation_;
    invalidateTimer();
    NSMutableArray* pending = (__bridge NSMutableArray*)tasks_;
    for (NSURLSessionTask* t in pending) [t cancel];
    [pending removeAllObjects];
}

void SiteWatch::checkNow() {
    AppSettings s = SettingsStore::instance().load();
    if (!s.siteWatchEnabled) return;
    beginCycle();
}

// ============================================================
// One check cycle
// ============================================================

void SiteWatch::dispatchCycleIfCurrent(int generation) {
    if (generation_ != generation || !running_) return;
    beginCycle();
}

void SiteWatch::dispatchResultIfCurrent(int generation, const std::string& url,
                                        const std::string& body, const std::string& error) {
    if (generation_ != generation) return;  // cycle was cancelled
    handleResult(url, body, error);
}

void SiteWatch::beginCycle() {
    if (!running_ || cycleActive_) return;
    AppSettings s = SettingsStore::instance().load();
    if (!s.siteWatchEnabled) {
        running_ = false;
        invalidateTimer();
        return;
    }
    if (s.siteWatchWifiOnly && !wifiAvailable()) {
        // Not an error: the next tick will try again once a Wi-Fi link is up.
        return;
    }

    // Rebuild the work list from the current bookmarks. Records for URLs that
    // are no longer bookmarked are dropped, so the file cannot grow forever.
    std::vector<Bookmark> marks = BookmarkStore::instance().all();
    std::vector<SiteWatchItem> next;
    for (const Bookmark& b : marks) {
        if (!isFetchable(b.url)) continue;
        SiteWatchItem it;
        it.url = b.url;
        it.title = b.title;
        for (const SiteWatchItem& old : items_) {
            if (old.url == b.url) {
                it.hash = old.hash;
                it.checkedAt = old.checkedAt;
                break;
            }
        }
        next.push_back(it);
    }
    items_ = next;
    save();

    if (items_.empty()) {
        // Nothing to watch is a normal state (the user may have no bookmarks).
        cycleFailures_ = 0;
        lastError_.clear();
        save();
        return;
    }

    cycleActive_ = true;
    cursor_ = 0;
    cycleFailures_ = 0;
    cycleNotified_ = 0;
    fetchNext();
}

void SiteWatch::fetchNext() {
    if (!cycleActive_) return;
    if (cursor_ >= items_.size()) {
        finishCycle();
        return;
    }
    const std::string url = items_[cursor_].url;
    ++cursor_;

    NSURL* nsurl = [NSURL URLWithString:[NSString stringWithUTF8String:url.c_str()]];
    if (!nsurl) {
        handleResult(url, "", "invalid URL");
        return;
    }

    NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL:nsurl];
    [req setTimeoutInterval:kWatchTimeoutSeconds];
    [req setHTTPMethod:@"GET"];
    [req setValue:[NSString stringWithUTF8String:kWatchUserAgent] forHTTPHeaderField:@"User-Agent"];
    [req setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
    // Follow redirects (the default policy), but never let a stale cached
    // response hide a change.

    NSURLSessionConfiguration* cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = kWatchTimeoutSeconds;
    cfg.timeoutIntervalForResource = kWatchTimeoutSeconds;
    cfg.HTTPMaximumConnectionsPerHost = 2;
    cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
    NSURLSession* session = [NSURLSession sessionWithConfiguration:cfg];

    int gen = generation_;
    NSURLSessionDataTask* task = [session dataTaskWithRequest:req
                                           completionHandler:^(NSData* data, NSURLResponse* response,
                                                               NSError* error) {
        // Runs on a background queue. Copy everything we need before hopping
        // to the main queue; `data`/`error` belong to the session.
        std::string body;
        std::string err;
        if (error) {
            err = [[error localizedDescription] UTF8String] ?: "network error";
        } else if (data) {
            NSUInteger len = [data length];
            if (len > kWatchMaxBodyBytes) len = kWatchMaxBodyBytes;
            body.assign((const char*)[data bytes], len);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            SiteWatch::instance().dispatchResultIfCurrent(gen, url, body, err);
        });
    }];
    NSMutableArray* pending = (__bridge NSMutableArray*)tasks_;
    [pending addObject:task];
    [task resume];
}

void SiteWatch::handleResult(const std::string& url, const std::string& body,
                             const std::string& error) {
    if (!cycleActive_) return;

    SiteWatchItem* item = nullptr;
    for (SiteWatchItem& it : items_) {
        if (it.url == url) {
            item = &it;
            break;
        }
    }

    if (!error.empty()) {
        ++cycleFailures_;
        lastError_ = error;
        if (item) {
            // Keep the old hash: a transient failure must not look like a
            // change on the next successful check.
            item->checkedAt = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
        }
        save();
        fetchNext();
        return;
    }

    std::string newHash = sha256Hex(body);
    SiteWatchVerdict verdict = item ? classify(item->hash, newHash) : SiteWatchVerdict::Unchanged;
    if (item) {
        item->hash = newHash;
        item->checkedAt = (long long)([[NSDate date] timeIntervalSince1970] * 1000.0);
        lastCheck_ = item->checkedAt;
    }

    if (verdict == SiteWatchVerdict::Changed) {
        ++cycleNotified_;
        std::string name = siteName(url);
        NSString* title = [NSString stringWithUTF8String:L("watch.notify_title").c_str()];
        NSString* bodyFmt = [NSString stringWithUTF8String:L("watch.notify_body").c_str()];
        NSString* text = [NSString stringWithFormat:bodyFmt,
                          [NSString stringWithUTF8String:name.c_str()]];
        UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
        content.title = title;
        content.body = text;
        content.sound = [UNNotificationSound defaultSound];
        UNNotificationRequest* req = [UNNotificationRequest requestWithIdentifier:WatchNotificationId(url)
                                                                          content:content
                                                                          trigger:nil];
        [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:req
                                                               withCompletionHandler:^(NSError* e) {
            (void)e;
        }];
    }
    save();
    fetchNext();
}

void SiteWatch::finishCycle() {
    cycleActive_ = false;
    if (cycleFailures_ == 0) lastError_.clear();
    save();
    NSMutableArray* pending = (__bridge NSMutableArray*)tasks_;
    [pending removeAllObjects];
}
