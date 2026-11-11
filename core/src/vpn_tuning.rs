//! Runtime adjustments applied to a profile just before the tunnel is built.
//!
//! Ported 1:1 from the Android `core/VpnTuning.kt` (v1.9.0).
//!
//! The stored profile text is never modified — the settings editor and export
//! keep showing exactly what the user pasted. These adjustments only shape the
//! config handed to the tunnel.
//!
//! Why each one exists
//! -------------------
//!  - **PersistentKeepalive (default 25 s).** Without it an idle tunnel sends
//!    nothing, so a carrier-grade NAT on the client or the server side drops the
//!    UDP mapping after a few minutes and the *next* packet is lost. This is the
//!    most common cause of "the VPN says connected after sleep but nothing
//!    loads". WireGuard's documentation recommends 25 s for peers behind NAT.
//!    A user-supplied non-zero value is kept; a literal `0` (explicitly off) is
//!    replaced too, because an idle browser tunnel without keepalive is exactly
//!    the reported failure mode.
//!  - **MTU (1280).** A profile without MTU inherits the interface MTU, which on
//!    Wi-Fi is usually 1500. Through a PPPoE / WireGuard-over-NAT path that makes
//!    large TLS handshake packets get dropped (pages hang while small requests
//!    succeed). 1280 is the IPv6 minimum, so a missing MTU is filled in with it
//!    and a larger one is lowered to it. A *smaller* user value is left alone.
//!  - **DNS cap (3 servers).** A config naming many public resolvers makes the
//!    system resolver time out one by one, which looks like a dead VPN.

pub const DEFAULT_KEEPALIVE_SECONDS: i32 = 25;

/// Keepalive used when the user turns on the power-saving option. Still inside
/// the range WireGuard documents for NAT traversal, but long enough that a
/// strict firewall can drop an idle mapping, hence opt-in.
pub const POWER_SAVER_KEEPALIVE_SECONDS: i32 = 60;
pub const DEFAULT_MTU: i32 = 1280;
pub const MAX_DNS_SERVERS: usize = 3;

/// Returns the same config with keepalive / MTU / DNS adjusted.
///
/// `keepalive_seconds` is clamped to 1..=65535.
pub fn tune(config_text: &str, keepalive_seconds: i32) -> String {
    let keepalive = keepalive_seconds.clamp(1, 65_535);
    let normalized = config_text.replace("\r\n", "\n").replace('\r', "\n");
    let lines: Vec<&str> = normalized.split('\n').collect();
    let mut out: Vec<String> = Vec::with_capacity(lines.len() + 4);
    let mut section = String::new();
    let mut saw_mtu = false;
    // Index in `out` where a missing MTU should be inserted (end of the
    // [Interface] body). -1 means "not inside [Interface] yet".
    let mut interface_insert_at: i64 = -1;
    // True while the current peer has not yet emitted a keepalive line.
    let mut peer_needs_keepalive = false;

    fn close_peer(out: &mut Vec<String>, needs: &mut bool, keepalive: i32) {
        if *needs {
            out.push(format!("PersistentKeepalive = {keepalive}"));
            *needs = false;
        }
    }

    for line in lines {
        let trimmed = line.trim();
        if trimmed.starts_with('[') && trimmed.ends_with(']') {
            close_peer(&mut out, &mut peer_needs_keepalive, keepalive);
            section = trimmed.to_lowercase();
            // Remember where the [Interface] body ends: a missing MTU is
            // inserted there (after the blank separator), never in a peer.
            if section == "[interface]" {
                interface_insert_at = -1;
            }
            if section == "[peer]" {
                peer_needs_keepalive = true;
            }
            out.push(line.to_string());
            continue;
        }
        let key = trimmed
            .split('=')
            .next()
            .unwrap_or("")
            .trim()
            .to_lowercase();
        let value = trimmed.splitn(2, '=').nth(1).unwrap_or("").trim();
        if section == "[interface]" && key == "dns" {
            let entries: Vec<&str> = value
                .split(',')
                .map(|s| s.trim())
                .filter(|s| !s.is_empty())
                .collect();
            let kept: Vec<&str> = entries.iter().take(MAX_DNS_SERVERS).copied().collect();
            // An empty `DNS =` line is kept verbatim: dropping it would silently
            // change which resolver the system uses (the interface default),
            // which is not this function's job.
            if kept.is_empty() {
                out.push(line.to_string());
            } else {
                out.push(format!("DNS = {}", kept.join(", ")));
            }
        } else if section == "[interface]" && key == "mtu" {
            saw_mtu = true;
            let parsed = value.parse::<i32>().ok();
            if let Some(m) = parsed {
                if m > DEFAULT_MTU {
                    out.push(format!("MTU = {DEFAULT_MTU}"));
                } else {
                    out.push(line.to_string());
                }
            } else {
                out.push(line.to_string());
            }
        } else if section == "[peer]" && key == "persistentkeepalive" {
            if value == "0" {
                out.push(format!("PersistentKeepalive = {keepalive}"));
            } else {
                out.push(line.to_string());
            }
            peer_needs_keepalive = false;
        } else {
            out.push(line.to_string());
        }
        // The insertion point is the end of the [Interface] body, so it must
        // follow every line that belongs to that section (blank separators
        // included) and stop growing once the next section starts.
        if section == "[interface]" {
            interface_insert_at = out.len() as i64;
        }
    }
    close_peer(&mut out, &mut peer_needs_keepalive, keepalive);

    if !saw_mtu {
        // The parser guarantees an [Interface] section, so the index is valid;
        // guard anyway so a malformed input can never panic here.
        let at = interface_insert_at.clamp(0, out.len() as i64) as usize;
        out.insert(at, format!("MTU = {DEFAULT_MTU}"));
    }
    out.join("\n")
}

/// `tune` with the default keepalive.
pub fn tune_default(config_text: &str) -> String {
    tune(config_text, DEFAULT_KEEPALIVE_SECONDS)
}

#[cfg(test)]
mod tests {
    use super::*;

    const KEY_A: &str = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    const KEY_B: &str = "ERERERERERERERERERERERERERERERERERERERERERE=";

    fn base() -> String {
        format!("[Interface]\nPrivateKey = {KEY_A}\nAddress = 10.0.0.2/32\n\n[Peer]\nPublicKey = {KEY_B}\nEndpoint = a.example:1\nAllowedIPs = 0.0.0.0/0\n")
    }

    #[test]
    fn inserts_default_keepalive_when_missing() {
        let out = tune_default(&base());
        assert!(out.contains("PersistentKeepalive = 25"), "got:\n{out}");
    }

    #[test]
    fn keeps_an_explicit_nonzero_keepalive() {
        let cfg = format!("{}PersistentKeepalive = 15\n", base());
        let out = tune_default(&cfg);
        assert!(out.contains("PersistentKeepalive = 15"), "got:\n{out}");
        assert!(!out.contains("PersistentKeepalive = 25"));
    }

    #[test]
    fn replaces_an_explicit_zero_keepalive() {
        let cfg = format!("{}PersistentKeepalive = 0\n", base());
        let out = tune_default(&cfg);
        assert!(out.contains("PersistentKeepalive = 25"), "got:\n{out}");
        assert!(!out.contains("PersistentKeepalive = 0"));
    }

    #[test]
    fn power_saver_uses_sixty_seconds() {
        let out = tune(&base(), POWER_SAVER_KEEPALIVE_SECONDS);
        assert!(out.contains("PersistentKeepalive = 60"), "got:\n{out}");
    }

    #[test]
    fn keepalive_is_clamped() {
        let out = tune(&base(), 0);
        assert!(out.contains("PersistentKeepalive = 1"), "got:\n{out}");
        let out = tune(&base(), 100_000);
        assert!(out.contains("PersistentKeepalive = 65535"), "got:\n{out}");
    }

    #[test]
    fn inserts_default_mtu_when_missing() {
        let out = tune_default(&base());
        assert!(out.contains("MTU = 1280"), "got:\n{out}");
    }

    #[test]
    fn lowers_a_large_mtu() {
        let cfg = format!("[Interface]\nPrivateKey = {KEY_A}\nMTU = 1420\n\n[Peer]\nPublicKey = {KEY_B}\nEndpoint = a.example:1\nAllowedIPs = 0.0.0.0/0\n");
        let out = tune_default(&cfg);
        assert!(out.contains("MTU = 1280"), "got:\n{out}");
        assert!(!out.contains("MTU = 1420"));
    }

    #[test]
    fn keeps_a_smaller_mtu() {
        let cfg = format!("[Interface]\nPrivateKey = {KEY_A}\nMTU = 1000\n\n[Peer]\nPublicKey = {KEY_B}\nEndpoint = a.example:1\nAllowedIPs = 0.0.0.0/0\n");
        let out = tune_default(&cfg);
        assert!(out.contains("MTU = 1000"), "got:\n{out}");
        assert!(!out.contains("MTU = 1280"));
    }

    #[test]
    fn caps_dns_to_three_servers() {
        let cfg = format!("[Interface]\nPrivateKey = {KEY_A}\nDNS = 1.1.1.1, 8.8.8.8, 9.9.9.9, 1.0.0.1\n\n[Peer]\nPublicKey = {KEY_B}\nEndpoint = a.example:1\nAllowedIPs = 0.0.0.0/0\n");
        let out = tune_default(&cfg);
        assert!(out.contains("DNS = 1.1.1.1, 8.8.8.8, 9.9.9.9"), "got:\n{out}");
        assert!(!out.contains("1.0.0.1"));
    }

    #[test]
    fn preserves_an_empty_dns_line() {
        let cfg = format!("[Interface]\nPrivateKey = {KEY_A}\nDNS =\n\n[Peer]\nPublicKey = {KEY_B}\nEndpoint = a.example:1\nAllowedIPs = 0.0.0.0/0\n");
        let out = tune_default(&cfg);
        assert!(out.contains("DNS ="), "got:\n{out}");
    }

    #[test]
    fn mtu_is_inserted_inside_interface_not_in_peer() {
        let out = tune_default(&base());
        let mtu_pos = out.find("MTU = 1280").expect("mtu");
        let peer_pos = out.find("[Peer]").expect("peer");
        assert!(mtu_pos < peer_pos, "MTU must precede [Peer]:\n{out}");
    }

    #[test]
    fn handles_crlf_input() {
        let cfg = base().replace('\n', "\r\n");
        let out = tune_default(&cfg);
        assert!(!out.contains('\r'));
        assert!(out.contains("PersistentKeepalive = 25"));
    }

    #[test]
    fn adds_keepalive_to_every_peer() {
        let cfg = format!("[Interface]\nPrivateKey = {KEY_A}\n\n[Peer]\nPublicKey = {KEY_B}\nEndpoint = a.example:1\nAllowedIPs = 0.0.0.0/0\n[Peer]\nPublicKey = {KEY_B}\nEndpoint = b.example:2\nAllowedIPs = 10.0.0.0/24\n");
        let out = tune_default(&cfg);
        assert_eq!(2, out.matches("PersistentKeepalive = 25").count(), "got:\n{out}");
    }

    #[test]
    fn tuned_output_still_parses() {
        let out = tune_default(&base());
        let parsed = crate::vpn_config::parse(&out).expect("tuned config must parse");
        assert_eq!(Some(1280), parsed.mtu);
        assert_eq!(Some(25), parsed.peers[0].persistent_keepalive);
    }
}
