//! Reachability of a WireGuard session, as opposed to the state of the tunnel
//! device.
//!
//! Ported 1:1 from the Android `core/VpnHealth.kt` (v1.9.0). The rules are pure
//! functions so they are unit-tested without the OS, a network or a tunnel.
//!
//! Why this exists
//! ---------------
//! "The tunnel is up" only says that the TUN device exists and routes are in
//! place. The WireGuard handshake is asynchronous: if the server is down, the
//! UDP port is blocked, or the NAT mapping expired while the machine slept, the
//! tunnel stays "up" while nothing actually flows. The app therefore derives a
//! second, independent signal from the peers' latest handshake time and shows
//! both.

/// Reachability of the tunnel, independent of the device state.
///
/// The declaration order is part of the persisted contract: records store the
/// variant by name, and `TunnelOnly` is appended last so older values keep
/// their meaning.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum VpnReachability {
    /// No tunnel, or the tunnel was never verified.
    Unknown,
    /// A verification is in progress (just after connect, or on resume).
    Verifying,
    /// A handshake completed recently: traffic can flow.
    Healthy,
    /// A handshake succeeded before, but it is older than `HEALTHY_WINDOW_MS`.
    Stale,
    /// No handshake has ever completed and the grace period is over.
    Unreachable,
    /// The OS says our tunnel is still up, but this process cannot read its
    /// handshake time (the tunnel registry lives in another process, or the app
    /// was restarted). Deliberately distinct from `Healthy`: the tunnel exists,
    /// but nothing has proven that traffic flows.
    ///
    /// Appended last so that existing name-based persistence keeps decoding
    /// old values.
    TunnelOnly,
}

impl VpnReachability {
    /// Stable identifier used for persistence and diagnostics.
    pub fn name(self) -> &'static str {
        match self {
            VpnReachability::Unknown => "UNKNOWN",
            VpnReachability::Verifying => "VERIFYING",
            VpnReachability::Healthy => "HEALTHY",
            VpnReachability::Stale => "STALE",
            VpnReachability::Unreachable => "UNREACHABLE",
            VpnReachability::TunnelOnly => "TUNNEL_ONLY",
        }
    }

    /// Parses a persisted name; unknown values fall back to `Unknown` so a
    /// record written by a newer build never breaks an older one.
    pub fn from_name(s: &str) -> VpnReachability {
        match s {
            "VERIFYING" => VpnReachability::Verifying,
            "HEALTHY" => VpnReachability::Healthy,
            "STALE" => VpnReachability::Stale,
            "UNREACHABLE" => VpnReachability::Unreachable,
            "TUNNEL_ONLY" => VpnReachability::TunnelOnly,
            _ => VpnReachability::Unknown,
        }
    }

    /// Every variant in declaration order (mirrors Kotlin `entries`).
    pub fn all() -> [VpnReachability; 6] {
        [
            VpnReachability::Unknown,
            VpnReachability::Verifying,
            VpnReachability::Healthy,
            VpnReachability::Stale,
            VpnReachability::Unreachable,
            VpnReachability::TunnelOnly,
        ]
    }
}

/// A recorded observation of one tunnel session.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct VpnHealthSnapshot {
    pub profile_id: String,
    /// Epoch millis when the tunnel reported UP (0 = unknown).
    pub connected_at: i64,
    /// Epoch millis of the newest peer handshake, 0 = never.
    pub last_handshake_at: i64,
    /// Epoch millis when `last_handshake_at` was read.
    pub checked_at: i64,
}

impl VpnHealthSnapshot {
    pub fn new(profile_id: impl Into<String>, connected_at: i64, last_handshake_at: i64) -> Self {
        Self {
            profile_id: profile_id.into(),
            connected_at,
            last_handshake_at,
            checked_at: 0,
        }
    }

    pub fn has_handshake(&self) -> bool {
        self.last_handshake_at > 0
    }

    /// True when `last_handshake_at` is at or after the tunnel came up.
    pub fn handshake_since_connect(&self) -> bool {
        self.has_handshake() && self.last_handshake_at >= self.connected_at
    }
}

/// A handshake is considered fresh for this long. WireGuard re-keys every
/// ~2 minutes, so a healthy idle tunnel still produces handshakes well inside
/// this window.
pub const HEALTHY_WINDOW_MS: i64 = 180_000;

/// Grace period after UP before "no handshake yet" becomes a failure.
pub const HANDSHAKE_GRACE_MS: i64 = 45_000;

/// How often the controller re-reads the handshake time while the app is on
/// screen. The healthy window is `HEALTHY_WINDOW_MS`, so this is already finer
/// than the judgement needs; it exists so the badge reacts quickly.
pub const POLL_FOREGROUND_MS: i64 = 10_000;

/// First interval used while the app is not visible. A healthy tunnel backs off
/// from here towards `POLL_BACKGROUND_MAX_MS`; a broken one keeps polling at
/// this rate.
pub const POLL_BACKGROUND_MIN_MS: i64 = 60_000;

/// Upper bound of the background back-off.
pub const POLL_BACKGROUND_MAX_MS: i64 = 300_000;

/// Multiplier applied to the background interval per consecutive healthy check.
pub const POLL_BACKOFF_FACTOR: f64 = 1.5;

/// Grace period used right after the network changed. A handshake cannot
/// complete before the new path exists, so the normal 45 s grace would report a
/// false failure and trigger a pointless reconnect.
pub const NETWORK_CHANGE_GRACE_MS: i64 = 10_000;

/// Minimum gap between two automatic reconnects (prevents reconnect storms).
pub const AUTO_RECONNECT_MIN_INTERVAL_MS: i64 = 30_000;

/// Caps the exponent so the computation stays bounded for a long session.
/// Shared with the controller, which caps its healthy counter the same way.
pub const MAX_BACKOFF_STEPS: i32 = 16;

/// Classifies a session from its snapshot.
///
/// `grace_start_override` is when the current session effectively restarted for
/// grace purposes (e.g. the moment the network changed). It only moves the
/// *grace* window forward; whether a handshake belongs to this session is still
/// judged against `connected_at`, because a handshake completed after the
/// connect is valid proof even if it happened before the network changed.
pub fn classify(
    snapshot: &VpnHealthSnapshot,
    now: i64,
    grace_start_override: i64,
) -> VpnReachability {
    let connected_at = snapshot.connected_at;
    // Grace is measured from the later of the connect and the override, so a
    // network switch gets a fresh window instead of inheriting an expired one.
    let grace_start = connected_at.max(grace_start_override);
    let grace_age = if grace_start > 0 {
        (now - grace_start).max(0)
    } else {
        i64::MAX
    };
    if snapshot.has_handshake() {
        let handshake_age = (now - snapshot.last_handshake_at).max(0);
        // A handshake that predates this connect (a leftover from the previous
        // session) proves nothing about the current one until a new one
        // arrives; inside the grace period that is "verifying".
        if snapshot.last_handshake_at < connected_at {
            return if grace_age < HANDSHAKE_GRACE_MS {
                VpnReachability::Verifying
            } else {
                VpnReachability::Stale
            };
        }
        // A fresh handshake since connect is authoritative even right after UP:
        // the server is demonstrably reachable.
        if handshake_age <= HEALTHY_WINDOW_MS {
            return VpnReachability::Healthy;
        }
        return VpnReachability::Stale;
    }
    // No handshake at all: stay "verifying" inside the grace period (a slow
    // network can take a few seconds), then report unreachable.
    if grace_age < HANDSHAKE_GRACE_MS {
        VpnReachability::Verifying
    } else {
        VpnReachability::Unreachable
    }
}

/// `classify` without a grace override (the common case).
pub fn classify_now(snapshot: &VpnHealthSnapshot, now: i64) -> VpnReachability {
    classify(snapshot, now, 0)
}

/// True when the tunnel is up but traffic is (probably) not flowing.
pub fn needs_reconnect(reachability: VpnReachability) -> bool {
    matches!(
        reachability,
        VpnReachability::Stale | VpnReachability::Unreachable
    )
}

/// Decides whether an automatic reconnect should run now.
pub fn should_auto_reconnect(
    reachability: VpnReachability,
    auto_reconnect: bool,
    consent_granted: bool,
    last_auto_reconnect_at: i64,
    now: i64,
) -> bool {
    if !auto_reconnect || !consent_granted {
        return false;
    }
    if !needs_reconnect(reachability) {
        return false;
    }
    if last_auto_reconnect_at > 0 && now - last_auto_reconnect_at < AUTO_RECONNECT_MIN_INTERVAL_MS {
        return false;
    }
    true
}

/// Decides what to publish after a verification pass.
///
/// A tunnel adopted from the OS (`TunnelOnly`) has no readable handshake in this
/// process, so every pass observes `Unknown`. Publishing that would erase the
/// only true fact we have ("the tunnel exists") and, worse, `Unknown` is not a
/// reconnect trigger, so the app would stop verifying entirely. Keep
/// `TunnelOnly` until something more specific is observed.
pub fn publish(observed: VpnReachability, previous: VpnReachability) -> VpnReachability {
    if observed == VpnReachability::Unknown && previous == VpnReachability::TunnelOnly {
        VpnReachability::TunnelOnly
    } else {
        observed
    }
}

/// How long to wait before the next verification pass.
///
/// The cost driver is reading the handshake time: every call runs the `wg`
/// binary (or queries the provider) and parses its output, so it must not run
/// every few seconds while nobody is looking. The judgement only needs
/// `HEALTHY_WINDOW_MS` resolution, which is why the background schedule backs
/// off instead of polling flat out.
///
/// `consecutive_healthy` is the count *after* the observation: 0 means the
/// tunnel is not proven healthy yet, so the fast background rate applies;
/// 1 means one healthy check, which already applies the first back-off step.
pub fn next_poll_delay_ms(
    foreground: bool,
    reachability: VpnReachability,
    consecutive_healthy: i32,
) -> i64 {
    if foreground {
        return POLL_FOREGROUND_MS;
    }
    // A tunnel that is not proven healthy is re-checked at the fast background
    // rate: this is the case where recovery matters.
    if reachability != VpnReachability::Healthy || consecutive_healthy <= 0 {
        return POLL_BACKGROUND_MIN_MS;
    }
    let mut delay = POLL_BACKGROUND_MIN_MS as f64;
    for _ in 0..consecutive_healthy.min(MAX_BACKOFF_STEPS) {
        delay *= POLL_BACKOFF_FACTOR;
        if delay >= POLL_BACKGROUND_MAX_MS as f64 {
            return POLL_BACKGROUND_MAX_MS;
        }
    }
    (delay as i64).clamp(POLL_BACKGROUND_MIN_MS, POLL_BACKGROUND_MAX_MS)
}

/// Chooses the newest handshake time across peers. A multi-peer profile is
/// reachable when any peer has handshaked, so the maximum is the right
/// aggregate.
pub fn newest_handshake<I: IntoIterator<Item = i64>>(times: I) -> i64 {
    times.into_iter().filter(|t| *t > 0).max().unwrap_or(0)
}

/// Parses the output of `wg show <iface> latest-handshakes`.
///
/// Each line is `<peer-public-key>\t<unix-seconds>`; `0` means "never". Returns
/// the newest handshake in epoch **millis** (the unit used everywhere else), or
/// 0 when nothing has handshaked.
pub fn parse_latest_handshakes(output: &str) -> i64 {
    let mut newest = 0i64;
    for line in output.lines() {
        let mut parts = line.split_whitespace();
        let _key = match parts.next() {
            Some(k) => k,
            None => continue,
        };
        let secs = match parts.next().and_then(|s| s.parse::<i64>().ok()) {
            Some(v) => v,
            None => continue,
        };
        if secs > newest {
            newest = secs;
        }
    }
    newest.saturating_mul(1000)
}

/// Persisted, non-secret health history used to answer "was the VPN working
/// when the app was last open?".
///
/// Deliberately contains no keys, addresses, DNS servers or endpoints.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct VpnHealthRecord {
    pub version: i32,
    pub profile_id: String,
    pub connected_at: i64,
    pub last_handshake_at: i64,
    pub checked_at: i64,
    pub reachability: String,
    pub last_auto_reconnect_at: i64,
}

impl VpnHealthRecord {
    pub fn empty() -> Self {
        Self {
            version: 1,
            reachability: VpnReachability::Unknown.name().to_string(),
            ..Default::default()
        }
    }

    pub fn to_snapshot(&self) -> VpnHealthSnapshot {
        VpnHealthSnapshot {
            profile_id: self.profile_id.clone(),
            connected_at: self.connected_at,
            last_handshake_at: self.last_handshake_at,
            checked_at: self.checked_at,
        }
    }

    pub fn reachability(&self) -> VpnReachability {
        VpnReachability::from_name(&self.reachability)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const T0: i64 = 1_700_000_000_000;

    fn snapshot(connected_at: i64, handshake_at: i64) -> VpnHealthSnapshot {
        VpnHealthSnapshot {
            profile_id: "p".to_string(),
            connected_at,
            last_handshake_at: handshake_at,
            checked_at: T0,
        }
    }

    // ---------------------------------------------------------- classify

    #[test]
    fn no_handshake_right_after_connect_is_verifying() {
        let s = snapshot(T0, 0);
        assert_eq!(VpnReachability::Verifying, classify_now(&s, T0 + 1_000));
        assert_eq!(VpnReachability::Verifying, classify_now(&s, T0 + 44_000));
    }

    #[test]
    fn no_handshake_after_the_grace_period_is_unreachable() {
        let s = snapshot(T0, 0);
        assert_eq!(VpnReachability::Unreachable, classify_now(&s, T0 + 45_000));
        assert_eq!(
            VpnReachability::Unreachable,
            classify_now(&s, T0 + 600_000)
        );
    }

    #[test]
    fn fresh_handshake_is_healthy() {
        let s = snapshot(T0, T0 + 2_000);
        assert_eq!(VpnReachability::Healthy, classify_now(&s, T0 + 5_000));
        assert_eq!(
            VpnReachability::Healthy,
            classify_now(&s, T0 + 2_000 + 180_000)
        );
    }

    #[test]
    fn old_handshake_is_stale() {
        let s = snapshot(T0, T0 + 2_000);
        assert_eq!(
            VpnReachability::Stale,
            classify_now(&s, T0 + 2_000 + 180_001)
        );
        assert_eq!(VpnReachability::Stale, classify_now(&s, T0 + 3_600_000));
    }

    #[test]
    fn handshake_from_a_previous_session_does_not_prove_the_current_one() {
        let s = snapshot(T0, T0 - 600_000);
        assert_eq!(VpnReachability::Verifying, classify_now(&s, T0 + 1_000));
        assert_eq!(VpnReachability::Stale, classify_now(&s, T0 + 60_000));
    }

    #[test]
    fn clock_going_backwards_never_reports_unreachable() {
        let s = snapshot(T0, 0);
        assert_eq!(VpnReachability::Verifying, classify_now(&s, T0 - 10_000));
    }

    #[test]
    fn unknown_connected_at_is_treated_as_long_elapsed() {
        let s = snapshot(0, 0);
        assert_eq!(VpnReachability::Unreachable, classify_now(&s, T0));
    }

    #[test]
    fn needs_reconnect_only_for_stale_or_unreachable() {
        assert!(needs_reconnect(VpnReachability::Stale));
        assert!(needs_reconnect(VpnReachability::Unreachable));
        assert!(!needs_reconnect(VpnReachability::Healthy));
        assert!(!needs_reconnect(VpnReachability::Verifying));
        assert!(!needs_reconnect(VpnReachability::Unknown));
    }

    #[test]
    fn auto_reconnect_respects_setting_consent_and_cooldown() {
        assert!(!should_auto_reconnect(
            VpnReachability::Stale,
            false,
            true,
            0,
            T0
        ));
        assert!(!should_auto_reconnect(
            VpnReachability::Stale,
            true,
            false,
            0,
            T0
        ));
        assert!(!should_auto_reconnect(
            VpnReachability::Healthy,
            true,
            true,
            0,
            T0
        ));
        assert!(should_auto_reconnect(
            VpnReachability::Stale,
            true,
            true,
            0,
            T0
        ));
        assert!(!should_auto_reconnect(
            VpnReachability::Stale,
            true,
            true,
            T0 - 10_000,
            T0
        ));
        assert!(should_auto_reconnect(
            VpnReachability::Unreachable,
            true,
            true,
            T0 - 30_000,
            T0
        ));
    }

    #[test]
    fn newest_handshake_ignores_zeros() {
        assert_eq!(0, newest_handshake(vec![0, 0]));
        assert_eq!(30, newest_handshake(vec![10, 30, 0, 20]));
        assert_eq!(0, newest_handshake(Vec::<i64>::new()));
    }

    #[test]
    fn snapshot_reports_handshake_since_connect() {
        assert!(snapshot(T0, T0 + 1).handshake_since_connect());
        assert!(!snapshot(T0, T0 - 1).handshake_since_connect());
        assert!(!snapshot(T0, 0).handshake_since_connect());
    }

    #[test]
    fn record_round_trips_to_snapshot() {
        let record = VpnHealthRecord {
            version: 1,
            profile_id: "p".to_string(),
            connected_at: T0,
            last_handshake_at: T0 + 5,
            checked_at: T0 + 9,
            reachability: VpnReachability::Healthy.name().to_string(),
            last_auto_reconnect_at: 0,
        };
        let snapshot = record.to_snapshot();
        assert_eq!("p", snapshot.profile_id);
        assert_eq!(T0 + 5, snapshot.last_handshake_at);
        assert_eq!(T0, snapshot.connected_at);
        assert_eq!(VpnReachability::Healthy, record.reachability());
    }

    // ------------------------------------------------------ poll schedule

    #[test]
    fn foreground_polling_uses_the_fast_interval_regardless_of_health() {
        for reach in VpnReachability::all() {
            assert_eq!(
                POLL_FOREGROUND_MS,
                next_poll_delay_ms(true, reach, 0)
            );
            assert_eq!(
                POLL_FOREGROUND_MS,
                next_poll_delay_ms(true, reach, 50)
            );
        }
    }

    #[test]
    fn background_polling_backs_off_while_the_tunnel_stays_healthy() {
        assert_eq!(
            POLL_BACKGROUND_MIN_MS,
            next_poll_delay_ms(false, VpnReachability::Healthy, 0)
        );
        let first = next_poll_delay_ms(false, VpnReachability::Healthy, 1);
        let second = next_poll_delay_ms(false, VpnReachability::Healthy, 2);
        let third = next_poll_delay_ms(false, VpnReachability::Healthy, 3);
        // One healthy check already applies the first step (60 s * 1.5).
        assert_eq!(
            (POLL_BACKGROUND_MIN_MS as f64 * POLL_BACKOFF_FACTOR) as i64,
            first
        );
        assert!(second > first);
        assert!(third > second);
    }

    #[test]
    fn background_backoff_is_capped() {
        assert_eq!(
            POLL_BACKGROUND_MAX_MS,
            next_poll_delay_ms(false, VpnReachability::Healthy, 100)
        );
    }

    #[test]
    fn background_polling_stays_fast_when_the_tunnel_is_not_healthy() {
        for reach in [
            VpnReachability::Unknown,
            VpnReachability::Verifying,
            VpnReachability::Stale,
            VpnReachability::Unreachable,
            VpnReachability::TunnelOnly,
        ] {
            assert_eq!(
                POLL_BACKGROUND_MIN_MS,
                next_poll_delay_ms(false, reach, 9)
            );
        }
    }

    #[test]
    fn a_broken_tunnel_resets_the_backoff() {
        assert_eq!(
            POLL_BACKGROUND_MIN_MS,
            next_poll_delay_ms(false, VpnReachability::Stale, 0)
        );
    }

    #[test]
    fn every_delay_is_within_the_documented_bounds() {
        for fg in [true, false] {
            for reach in VpnReachability::all() {
                for n in 0..=20 {
                    let d = next_poll_delay_ms(fg, reach, n);
                    assert!(d >= POLL_FOREGROUND_MS, "delay {d} out of range");
                    assert!(d <= POLL_BACKGROUND_MAX_MS, "delay {d} out of range");
                }
            }
        }
    }

    #[test]
    fn tunnel_only_is_appended_last_so_persisted_names_keep_decoding() {
        let all = VpnReachability::all();
        assert_eq!(VpnReachability::Unreachable, all[4]);
        assert_eq!(VpnReachability::TunnelOnly, all[all.len() - 1]);
        // Names round-trip.
        for r in all {
            assert_eq!(r, VpnReachability::from_name(r.name()));
        }
        assert_eq!(VpnReachability::Unknown, VpnReachability::from_name("BOGUS"));
    }

    // ------------------------------------------------------ publish rule

    #[test]
    fn a_tunnel_adopted_from_the_os_keeps_its_state_across_empty_passes() {
        assert_eq!(
            VpnReachability::TunnelOnly,
            publish(VpnReachability::Unknown, VpnReachability::TunnelOnly)
        );
    }

    #[test]
    fn a_real_observation_always_wins_over_the_adopted_state() {
        for observed in [
            VpnReachability::Healthy,
            VpnReachability::Stale,
            VpnReachability::Unreachable,
            VpnReachability::Verifying,
        ] {
            assert_eq!(
                observed,
                publish(observed, VpnReachability::TunnelOnly)
            );
        }
    }

    #[test]
    fn unknown_is_published_when_nothing_was_adopted() {
        for previous in [
            VpnReachability::Unknown,
            VpnReachability::Verifying,
            VpnReachability::Healthy,
            VpnReachability::Stale,
            VpnReachability::Unreachable,
        ] {
            assert_eq!(
                VpnReachability::Unknown,
                publish(VpnReachability::Unknown, previous)
            );
        }
    }

    #[test]
    fn the_shared_backoff_cap_matches_the_controller_counter() {
        assert_eq!(16, MAX_BACKOFF_STEPS);
    }

    // --------------------------------------------- network-change grace

    #[test]
    fn a_network_change_rearms_the_handshake_grace() {
        let connected_at = 1_000_000i64;
        let s = VpnHealthSnapshot::new("p", connected_at, 0);
        assert_eq!(
            VpnReachability::Unreachable,
            classify(&s, connected_at + 60_000, 0)
        );
        assert_eq!(
            VpnReachability::Verifying,
            classify(&s, connected_at + 60_000, connected_at + 55_000)
        );
    }

    #[test]
    fn the_override_never_shortens_an_existing_grace() {
        let connected_at = 1_000_000i64;
        let s = VpnHealthSnapshot::new("p", connected_at, 0);
        assert_eq!(
            VpnReachability::Verifying,
            classify(&s, connected_at + 10_000, 1)
        );
    }

    #[test]
    fn a_fresh_handshake_still_wins_over_the_grace() {
        let now = 1_000_000i64;
        let s = VpnHealthSnapshot::new("p", now - 60_000, now - 5_000);
        assert_eq!(
            VpnReachability::Healthy,
            classify(&s, now, now - 1_000)
        );
    }

    // ------------------------------------------------- wg output parsing

    #[test]
    fn parses_latest_handshakes_output() {
        let out = "\
peerAAA=\t1700000000
peerBBB=\t1700000123
";
        assert_eq!(1_700_000_123_000, parse_latest_handshakes(out));
    }

    #[test]
    fn parses_never_handshaked_as_zero() {
        let out = "peerAAA=\t0\npeerBBB=\t0\n";
        assert_eq!(0, parse_latest_handshakes(out));
    }

    #[test]
    fn tolerates_empty_and_malformed_output() {
        assert_eq!(0, parse_latest_handshakes(""));
        assert_eq!(0, parse_latest_handshakes("garbage"));
        assert_eq!(0, parse_latest_handshakes("key\tnotanumber"));
        assert_eq!(1_700_000_000_000, parse_latest_handshakes("key\t1700000000\nbroken"));
    }
}
