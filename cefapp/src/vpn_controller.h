#ifndef VPN_CONTROLLER_H
#define VPN_CONTROLLER_H

#include <string>
#include <functional>

/// Connection state of the WireGuard tunnel as far as this app can observe it.
enum class VpnConnState {
    Disconnected,
    Connecting,
    Connected,
};

/// Reachability of the tunnel, independent of the device state.
/// Values match the Rust `VpnReachability` declaration order so the FFI
/// classification can be stored directly.
enum class VpnReach {
    Unknown = 0,
    Verifying = 1,
    Healthy = 2,
    Stale = 3,
    Unreachable = 4,
    TunnelOnly = 5,
};

/// Drives the WireGuard tunnel on macOS.
///
/// Why this is not the Android implementation
/// ------------------------------------------
/// Android ships `wireguard-go` inside the app and creates a `VpnService`
/// tunnel, so the app owns the tunnel end to end. macOS does not allow that:
/// a tunnel needs either a signed Network Extension (paid Apple Developer
/// account + entitlement) or root. This class therefore *drives* the official
/// `wg-quick` when it is available and reports honestly when it is not, rather
/// than pretending to connect.
///
/// Everything that does not need a tunnel is still implemented: the
/// reachability rules, the polling schedule, resume-after-sleep verification
/// and the network-change grace. Those are the parts that fix "the VPN says
/// connected but nothing loads".
class VpnController {
public:
    /// Why a connect attempt could not proceed.
    enum class Availability {
        /// `wg-quick` is on PATH and the user can run it.
        Ready,
        /// `wg-quick` is not installed.
        ToolsMissing,
        /// `wg-quick` exists but needs root (the normal case).
        NeedsRoot,
        /// macOS forbids an in-app tunnel without a signed system extension.
        Unsupported,
    };

    static VpnController& instance();

    /// Probes the environment once and caches the result.
    Availability availability();
    /// A localized explanation of `availability()`.
    std::string availabilityDetail();

    /// True when the app can actually bring a tunnel up itself.
    bool canConnect();

    VpnConnState state() const { return state_; }
    VpnReach reachability() const { return reach_; }
    std::string activeProfileId() const { return activeProfileId_; }

    /// Connects `profileId`. Returns "" on success or an error key.
    std::string connect(const std::string& profileId);
    /// Disconnects the active tunnel.
    void disconnect();

    /// Re-reads the handshake time and republishes the reachability.
    void verifyNow();
    /// Called when the app becomes visible (foreground) again.
    void onAppForeground();
    /// Called when the app is hidden (background).
    void onAppBackground();
    /// Called when the system wakes from sleep: the NAT mapping may be gone.
    void onSystemWake();
    /// Called when the default network changed (Wi-Fi <-> Ethernet, etc.).
    void onNetworkChanged();
    /// Called when the display locks/unlocks (the macOS analogue of
    /// Android's ACTION_SCREEN_OFF).
    void onScreenLocked(bool locked);

    /// Starts/stops the visibility-aware poll timer. Safe to call repeatedly.
    void startMonitoring();
    void stopMonitoring();

    /// Invoked on the main thread whenever state or reachability changes.
    std::function<void()> onUpdate;

    /// True when automatic reconnect is enabled in settings.
    bool autoReconnectEnabled() const;
    /// True when the power-saving keepalive should be used.
    bool powerSaverEnabled() const;

private:
    VpnController();
    void scheduleNextPoll();
    void publish(VpnReach observed);
    int64_t nowMillis() const;
    int64_t readHandshakeMillis() const;
    bool foreground_ = true;
    bool screenLocked_ = false;
    bool monitoring_ = false;
    int consecutiveHealthy_ = 0;
    int64_t connectedAt_ = 0;
    int64_t lastHandshakeAt_ = 0;
    int64_t graceStartOverride_ = 0;
    int64_t lastAutoReconnectAt_ = 0;
    VpnConnState state_ = VpnConnState::Disconnected;
    VpnReach reach_ = VpnReach::Unknown;
    std::string activeProfileId_;
    /// Path of the tuned config currently handed to wg-quick (empty when none).
    std::string activeConfigPath_;
    Availability availability_ = Availability::Unsupported;
    bool availabilityProbed_ = false;
    void* timer_ = nullptr;  // dispatch_source_t
    void notify();
};

#endif  // VPN_CONTROLLER_H
