#ifndef VPN_STORE_H
#define VPN_STORE_H

#include <string>
#include <vector>

/// A WireGuard profile.
///
/// The profile is kept as the exact `[Interface]`/`[Peer]` text the user pasted
/// (or generated) plus a few derived, non-secret fields used by the UI. Keeping
/// the original text means an exported profile is byte-for-byte usable with the
/// official WireGuard clients.
///
/// Secrets: `configText` contains the private key and any pre-shared key. It is
/// persisted only through the Keychain (`KeychainSaveSecret`) and is never
/// written to logs, notifications or a web page. The index file on disk holds
/// only the id, name and derived display fields.
struct VpnProfile {
    std::string id;
    std::string name;
    std::string configText;
    /// First peer endpoint as shown in the UI ("vpn.example.com:51820").
    std::string endpoint;
    /// Tunnel addresses of the interface ("10.0.0.2/32"), for the UI only.
    std::vector<std::string> addresses;
    /// DNS servers of the interface, for the UI only.
    std::vector<std::string> dns;
    long long createdAt = 0;
    long long updatedAt = 0;
};

/// Profile storage backed by the Keychain.
///
/// The non-secret index lives in
/// `~/Library/Application Support/Half-Browser/vpn_profiles.json`; each
/// profile's full text is a separate Keychain item under the service
/// `half-browser-vpn`. Profiles are excluded from the backup format, exactly
/// like the Android build.
class VpnStore {
public:
    static VpnStore& instance();

    /// Profiles in display order (newest first). Config text is loaded lazily
    /// by `loadConfig`, so listing never touches the Keychain for every item.
    std::vector<VpnProfile> all() const;

    /// Adds or replaces a profile. Returns false when the config is invalid.
    /// The caller must have validated it (the UI does, via `hb_vpn_parse`).
    bool save(const VpnProfile& profile);

    /// Removes a profile and its Keychain item.
    bool remove(const std::string& id);

    /// Loads the config text for `id` from the Keychain.
    bool loadConfig(const std::string& id, std::string& out) const;

    /// Finds a profile by id (without the config text).
    bool find(const std::string& id, VpnProfile& out) const;

    /// True when at least one profile exists.
    bool empty() const;

    /// The profile the user last selected, or "" when none.
    std::string selectedId() const;
    void setSelectedId(const std::string& id);

private:
    VpnStore();
    void load();
    void saveIndex() const;

    std::vector<VpnProfile> profiles_;
    std::string indexPath_;
    std::string selectedId_;
};

#endif  // VPN_STORE_H
