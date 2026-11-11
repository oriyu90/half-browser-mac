#import <Cocoa/Cocoa.h>
#include "vpn_controller.h"
#include "vpn_store.h"
#include "settings_store.h"
#include "localization.h"
#include "half_browser_core.h"
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <dispatch/dispatch.h>
#include <string>
#include <sys/stat.h>

namespace {

int64_t nowMillis() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

/// Runs a command and captures stdout. Returns false when it could not run.
bool runCapture(const std::string& cmd, std::string& out) {
    FILE* p = popen(cmd.c_str(), "r");
    if (!p) return false;
    char buf[512];
    out.clear();
    while (fgets(buf, sizeof(buf), p)) {
        out += buf;
    }
    int status = pclose(p);
    return status == 0;
}

/// True when `name` is an executable file somewhere on PATH.
bool whichExists(const char* name) {
    const char* path = getenv("PATH");
    if (!path) return false;
    std::string paths(path);
    size_t start = 0;
    while (start <= paths.size()) {
        size_t end = paths.find(':', start);
        std::string dir = paths.substr(start, end == std::string::npos ? std::string::npos : end - start);
        if (!dir.empty()) {
            std::string candidate = dir + "/" + name;
            struct stat st;
            if (stat(candidate.c_str(), &st) == 0 && (st.st_mode & S_IXUSR)) return true;
        }
        if (end == std::string::npos) break;
        start = end + 1;
    }
    return false;
}

/// The interface name this app uses (must match the Rust `tunnel_name_for`
/// contract: `hb` + up to 12 alphanumerics).
std::string interfaceFor(const std::string& profileId) {
    std::string compact;
    for (char c : profileId) {
        if (isalnum((unsigned char)c) && compact.size() < 12) compact += c;
    }
    return "hb" + compact;
}

/// Where the tuned config is written before `wg-quick up`.
std::string configPathFor(const std::string& profileId) {
    const char* home = getenv("HOME");
    std::string dir = std::string(home ? home : ".") + "/Library/Application Support/Half-Browser/vpn";
    mkdir(dir.c_str(), 0700);
    return dir + "/" + interfaceFor(profileId) + ".conf";
}

}  // namespace

VpnController& VpnController::instance() {
    static VpnController inst;
    return inst;
}

VpnController::VpnController() {
    // Restore the last selected profile so the UI can show it immediately.
    activeProfileId_ = VpnStore::instance().selectedId();
}

int64_t VpnController::nowMillis() const {
    return ::nowMillis();
}

bool VpnController::autoReconnectEnabled() const {
    return SettingsStore::instance().load().vpnAutoReconnect;
}

bool VpnController::powerSaverEnabled() const {
    return SettingsStore::instance().load().vpnPowerSaver;
}

VpnController::Availability VpnController::availability() {
    if (availabilityProbed_) return availability_;
    availabilityProbed_ = true;

    // An in-app tunnel would need NetworkExtension + a paid developer account.
    // We never attempt that; the question is only whether `wg-quick` can drive
    // the official userspace tunnel for us.
    if (!whichExists("wg-quick") || !whichExists("wg")) {
        availability_ = Availability::ToolsMissing;
        return availability_;
    }
    // wg-quick refuses to run without root. We cannot prompt for a password
    // from a GUI app, so report it honestly instead of failing at connect time.
    if (geteuid() != 0) {
        availability_ = Availability::NeedsRoot;
        return availability_;
    }
    availability_ = Availability::Ready;
    return availability_;
}

std::string VpnController::availabilityDetail() {
    switch (availability()) {
        case Availability::Ready:
            return L("vpn.avail.ready");
        case Availability::ToolsMissing:
            return L("vpn.avail.tools_missing");
        case Availability::NeedsRoot:
            return L("vpn.avail.needs_root");
        case Availability::Unsupported:
        default:
            return L("vpn.avail.unsupported");
    }
}

bool VpnController::canConnect() {
    return availability() == Availability::Ready;
}

std::string VpnController::connect(const std::string& profileId) {
    if (profileId.empty()) return "vpn.error.no_profile";
    if (!canConnect()) {
        // Never pretend: report why, and let the UI show the explanation.
        return availability() == Availability::ToolsMissing ? "vpn.error.tools_missing"
             : availability() == Availability::NeedsRoot    ? "vpn.error.needs_root"
                                                            : "vpn.error.unsupported";
    }

    std::string config;
    if (!VpnStore::instance().loadConfig(profileId, config)) {
        return "vpn.error.config_unreadable";
    }

    // Apply the same runtime tuning as Android (keepalive / MTU / DNS) so the
    // stored text stays untouched but the tunnel gets the robust values.
    int keepalive = powerSaverEnabled() ? 60 : 25;
    std::string tuned;
    {
        char* tunedC = hb_vpn_tune(config.c_str(), keepalive);
        if (!tunedC) return "vpn.error.config_unreadable";
        tuned = tunedC;
        hb_free_string(tunedC);
    }

    std::string path = configPathFor(profileId);
    {
        FILE* f = fopen(path.c_str(), "w");
        if (!f) return "vpn.error.write_failed";
        fwrite(tuned.data(), 1, tuned.size(), f);
        fclose(f);
        // The file holds a private key: owner-only.
        chmod(path.c_str(), 0600);
    }

    state_ = VpnConnState::Connecting;
    notify();

    std::string out;
    bool ok = runCapture("wg-quick up '" + path + "' 2>&1", out);
    if (!ok) {
        state_ = VpnConnState::Disconnected;
        reach_ = VpnReach::Unknown;
        notify();
        return "vpn.error.connect_failed";
    }

    activeProfileId_ = profileId;
    VpnStore::instance().setSelectedId(profileId);
    connectedAt_ = nowMillis();
    lastHandshakeAt_ = 0;
    graceStartOverride_ = 0;
    consecutiveHealthy_ = 0;
    state_ = VpnConnState::Connected;
    reach_ = VpnReach::Verifying;
    notify();
    scheduleNextPoll();
    return "";
}

void VpnController::disconnect() {
    if (activeProfileId_.empty()) {
        state_ = VpnConnState::Disconnected;
        reach_ = VpnReach::Unknown;
        notify();
        return;
    }
    if (canConnect()) {
        std::string out;
        runCapture("wg-quick down '" + configPathFor(activeProfileId_) + "' 2>&1", out);
    }
    state_ = VpnConnState::Disconnected;
    reach_ = VpnReach::Unknown;
    connectedAt_ = 0;
    lastHandshakeAt_ = 0;
    consecutiveHealthy_ = 0;
    notify();
}

int64_t VpnController::readHandshakeMillis() const {
    if (activeProfileId_.empty()) return 0;
    std::string out;
    std::string cmd = "wg show " + interfaceFor(activeProfileId_) + " latest-handshakes 2>/dev/null";
    if (!runCapture(cmd, out)) return 0;
    return hb_vpn_parse_handshakes(out.c_str());
}

void VpnController::publish(VpnReach observed) {
    // Keep TUNNEL_ONLY across empty passes (Android publish rule).
    if (observed == VpnReach::Unknown && reach_ == VpnReach::TunnelOnly) {
        return;
    }
    reach_ = observed;
}

void VpnController::verifyNow() {
    if (state_ != VpnConnState::Connected) return;

    int64_t hs = readHandshakeMillis();
    if (hs > lastHandshakeAt_) lastHandshakeAt_ = hs;

    int code = hb_vpn_classify(connectedAt_, lastHandshakeAt_, nowMillis(), graceStartOverride_);
    VpnReach observed = (VpnReach)code;
    publish(observed);

    if (reach_ == VpnReach::Healthy) {
        if (consecutiveHealthy_ < 16) consecutiveHealthy_++;
    } else {
        consecutiveHealthy_ = 0;
    }

    // Automatic reconnect: the tunnel is up but traffic is not flowing.
    if ((reach_ == VpnReach::Stale || reach_ == VpnReach::Unreachable) &&
        autoReconnectEnabled() && canConnect()) {
        int64_t now = nowMillis();
        if (lastAutoReconnectAt_ == 0 || now - lastAutoReconnectAt_ >= 30000) {
            lastAutoReconnectAt_ = now;
            std::string id = activeProfileId_;
            disconnect();
            connect(id);
            return;
        }
    }
    notify();
    scheduleNextPoll();
}

void VpnController::scheduleNextPoll() {
    if (!monitoring_ || state_ != VpnConnState::Connected) return;

    bool visible = foreground_ && !screenLocked_;
    int64_t delayMs = hb_vpn_next_poll_delay(visible, (int)reach_, consecutiveHealthy_);

    if (timer_) {
        dispatch_source_cancel((dispatch_source_t)timer_);
        dispatch_release((dispatch_source_t)timer_);
        timer_ = nullptr;
    }
    dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                 dispatch_get_main_queue());
    uint64_t nanos = (uint64_t)delayMs * NSEC_PER_MSEC;
    dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, (int64_t)nanos), DISPATCH_TIME_FOREVER, 50 * NSEC_PER_MSEC);
    // One-shot: verifyNow() reschedules with the delay the rules computed.
    dispatch_source_set_event_handler(t, ^{
        verifyNow();
    });
    dispatch_resume(t);
    timer_ = t;
}

void VpnController::startMonitoring() {
    if (monitoring_) return;
    monitoring_ = true;
    if (state_ == VpnConnState::Connected) {
        verifyNow();
    }
}

void VpnController::stopMonitoring() {
    monitoring_ = false;
    if (timer_) {
        dispatch_source_cancel((dispatch_source_t)timer_);
        dispatch_release((dispatch_source_t)timer_);
        timer_ = nullptr;
    }
}

void VpnController::onAppForeground() {
    foreground_ = true;
    // Coming back to the app is exactly when a stale NAT mapping shows up.
    if (state_ == VpnConnState::Connected) {
        verifyNow();
    }
}

void VpnController::onAppBackground() {
    foreground_ = false;
    scheduleNextPoll();
}

void VpnController::onSystemWake() {
    // After sleep the NAT mapping may be gone even though the interface stayed
    // up: give the handshake a fresh grace window before judging it.
    graceStartOverride_ = nowMillis();
    consecutiveHealthy_ = 0;
    if (state_ == VpnConnState::Connected) {
        verifyNow();
    }
}

void VpnController::onNetworkChanged() {
    // A handshake cannot complete before the new path exists, so the normal
    // grace would report a false failure and trigger a pointless reconnect.
    graceStartOverride_ = nowMillis();
    consecutiveHealthy_ = 0;
    if (state_ == VpnConnState::Connected) {
        verifyNow();
    }
}

void VpnController::onScreenLocked(bool locked) {
    screenLocked_ = locked;
    scheduleNextPoll();
}

void VpnController::notify() {
    if (!onUpdate) return;
    auto cb = onUpdate;
    dispatch_async(dispatch_get_main_queue(), ^{
        cb();
    });
}
