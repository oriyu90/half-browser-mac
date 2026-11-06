#ifndef SITE_PERMISSIONS_H
#define SITE_PERMISSIONS_H
#include <string>
#include <vector>

struct SitePermission {
    std::string origin;   // scheme://host[:port]
    std::string kind;     // notifications | camera | microphone | location
    bool granted = false;
    long long updatedAt = 0;
};

class SitePermissionStore {
public:
    static SitePermissionStore& instance();
    bool isGranted(const std::string& origin, const std::string& kind);
    void set(const std::string& origin, const std::string& kind, bool granted);
    void reset(const std::string& origin);
    std::vector<SitePermission> all() const;
    void load();
    void save();

private:
    SitePermissionStore();
    std::vector<SitePermission> perms_;
    std::string filePath_;
};
#endif
