#ifndef FAVICON_SERVICE_H
#define FAVICON_SERVICE_H
#include <functional>
#include <string>

class FaviconService {
public:
    // Returns cached favicon path or empty if not cached
    static std::string cachePath(const std::string& url);
    /// Cache-only lookup (never blocks). Returns "" when not cached.
    static std::string fetchFavicon(const std::string& pageUrl);
    /// Downloads /favicon.ico off the main thread, then calls `done` on the
    /// main thread with the cached path (or "" on failure).
    static void fetchFaviconAsync(const std::string& pageUrl, std::function<void(std::string)> done);
    static std::string cacheDir();
    static std::string monogramFor(const std::string& title);
};
#endif
