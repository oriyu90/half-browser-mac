#ifndef SITE_WATCH_H
#define SITE_WATCH_H
#include <string>
#include <vector>

/// One watched page. `hash` is the SHA-256 (lowercase hex) of the body the
/// last successful check downloaded; an empty hash means "baseline not taken
/// yet" — the first successful fetch only records the baseline and never
/// notifies, so enabling the feature does not fire one alert per bookmark.
struct SiteWatchItem {
    std::string url;
    std::string hash;
    long long checkedAt = 0;  // Unix epoch milliseconds
    std::string title;
};

/// Result of comparing a freshly computed hash against the stored one.
enum class SiteWatchVerdict {
    Unchanged,   // same hash, nothing to do
    Changed,     // hash differs and a baseline existed -> notify
    Baseline,    // no previous hash -> store it, do not notify
};

/// Site Watch: the macOS stand-in for Android's WorkManager job.
///
/// macOS has no background scheduler that survives the app being quit, so the
/// checks run from an NSTimer while the app is open (the UI says so with
/// `watch.foreground_only`). Fetches are asynchronous NSURLSession tasks, so
/// the main thread is never blocked. Every entry point is defensive: a
/// network failure, a corrupt JSON file or an empty bookmark list must not
/// crash the app.
class SiteWatch {
public:
    static SiteWatch& instance();

    /// Start or stop the timer to match the saved settings. Safe to call
    /// repeatedly (e.g. after every settings change).
    void applySettings();
    /// Re-read settings and run one check cycle right now (used when the user
    /// switches the feature on so the first result arrives promptly).
    void checkNow();
    /// Stop the timer and drop pending callbacks (called on app termination).
    void shutdown();

    bool isRunning() const { return running_; }

    // ---- Persistence (site_watch.json) -----------------------------------
    std::string filePath() const { return filePath_; }
    std::vector<SiteWatchItem> items() const { return items_; }
    /// Last successful check across all items (epoch ms, 0 = never).
    long long lastCheckMillis() const { return lastCheck_; }
    /// Last error message (empty = none). Cleared by a fully successful cycle.
    std::string lastError() const { return lastError_; }

    /// Serialize the state to the version-1 JSON document.
    static std::string serialize(const std::vector<SiteWatchItem>& items, long long lastCheck,
                                 const std::string& lastError);
    /// Parse a version-1 document. Never throws; malformed input yields the
    /// records that could be recovered (possibly none) and never a crash.
    static bool parse(const std::string& json, std::vector<SiteWatchItem>& items,
                      long long& lastCheck, std::string& lastError);
    /// Load from `filePath_`. A missing or corrupt file leaves the state empty.
    void load();
    /// Atomic write (temp file + rename) of the current state.
    void save();

    // ---- Pure helpers (unit-testable, no I/O) ----------------------------
    /// Lowercase hex SHA-256 of `data`.
    static std::string sha256Hex(const std::string& data);
    /// Compare a fresh hash with the stored one.
    static SiteWatchVerdict classify(const std::string& previousHash,
                                     const std::string& newHash);
    /// Clamp an interval to the values the settings UI offers.
    static int sanitizeInterval(int minutes);
    /// True when `url` is worth fetching (http/https only).
    static bool isFetchable(const std::string& url);
    /// True when a Wi-Fi interface (en0..en3) is up. Used by the
    /// `siteWatchWifiOnly` setting; a device with no Wi-Fi hardware at all
    /// reports false, which is the conservative answer.
    static bool wifiAvailable();
    /// Human readable site name for a URL (the host, without "www.").
    static std::string siteName(const std::string& url);

    // ---- Self-test hooks -------------------------------------------------
    /// Point the store at a scratch file (self-test only). nullptr restores
    /// the real path.
    void setFilePathForTesting(const char* path);
    /// Generation stamp used to discard callbacks from a cancelled cycle.
    int generation() const { return generation_; }
    /// Main-queue entry points used by the timer and the session callbacks.
    /// They are public because an Objective-C block cannot reach a private
    /// C++ member; they are not meant for callers outside this file.
    void dispatchCycleIfCurrent(int generation);
    void dispatchResultIfCurrent(int generation, const std::string& url,
                                 const std::string& body, const std::string& error);

private:
    SiteWatch();
    ~SiteWatch();
    SiteWatch(const SiteWatch&) = delete;
    SiteWatch& operator=(const SiteWatch&) = delete;

    void scheduleTimer();
    void invalidateTimer();
    void beginCycle();
    void fetchNext();
    void handleResult(const std::string& url, const std::string& body,
                      const std::string& error);
    void finishCycle();

    std::vector<SiteWatchItem> items_;
    std::string filePath_;
    long long lastCheck_ = 0;
    std::string lastError_;
    bool running_ = false;
    bool cycleActive_ = false;
    size_t cursor_ = 0;
    int cycleFailures_ = 0;
    int cycleNotified_ = 0;
    /// Generation counter: callbacks from a cancelled cycle carry an older
    /// generation and are ignored, so a shutdown cannot resurrect the timer.
    int generation_ = 0;
    /// Opaque NSTimer; kept as void* so the header stays ObjC-free.
    void* timer_ = nullptr;
    /// Opaque NSMutableArray of in-flight NSURLSessionTask.
    void* tasks_ = nullptr;
};

#endif  // SITE_WATCH_H
