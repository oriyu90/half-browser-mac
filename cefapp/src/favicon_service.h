#ifndef FAVICON_SERVICE_H
#define FAVICON_SERVICE_H
#include <string>

class FaviconService {
public:
    // Returns cached favicon path or empty if not cached
    static std::string cachePath(const std::string& url);
    static std::string fetchFavicon(const std::string& pageUrl);
    static std::string cacheDir();
    static std::string monogramFor(const std::string& title);
};
#endif
