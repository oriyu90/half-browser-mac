//! Strict WireGuard `wg-quick` configuration parser.
//!
//! Ported 1:1 from the Android `core/VpnConfig.kt` (v1.9.0).
//!
//! Design notes:
//!  - **Reject rather than repair.** A silently "fixed" config can route traffic
//!    somewhere the user did not intend, so every deviation is an error.
//!  - **Bounded.** Input size, line count, peer count and list lengths are
//!    capped so a pasted 50 MB file cannot stall the UI or exhaust memory.
//!  - **No I/O, no OS.** Pure Rust, so the whole rule set is unit-tested.

use std::fmt;

pub const MAX_BYTES: usize = 64 * 1024;
pub const MAX_PEERS: usize = 32;
pub const MAX_LIST_ITEMS: usize = 32;
pub const MAX_NAME_LENGTH: usize = 40;
pub const MIN_MTU: i32 = 576;
pub const MAX_MTU: i32 = 9000;

/// Reasons a configuration is rejected. Each maps to a localized message; the
/// enum keeps the parser free of UI strings so it stays unit-testable.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VpnConfigError {
    Empty,
    TooLarge,
    MissingInterface,
    MissingPeer,
    MissingPrivateKey,
    InvalidPrivateKey,
    MissingPublicKey,
    InvalidPublicKey,
    InvalidPresharedKey,
    MissingEndpoint,
    InvalidEndpoint,
    MissingAllowedIps,
    InvalidAllowedIps,
    InvalidAddress,
    InvalidDns,
    InvalidPort,
    InvalidMtu,
    InvalidKeepalive,
    UnknownKey,
    DuplicateSection,
    MalformedLine,
}

impl VpnConfigError {
    /// Stable identifier used for the localization key and for diagnostics.
    pub fn key(self) -> &'static str {
        match self {
            VpnConfigError::Empty => "empty",
            VpnConfigError::TooLarge => "too_large",
            VpnConfigError::MissingInterface => "missing_interface",
            VpnConfigError::MissingPeer => "missing_peer",
            VpnConfigError::MissingPrivateKey => "missing_private_key",
            VpnConfigError::InvalidPrivateKey => "invalid_private_key",
            VpnConfigError::MissingPublicKey => "missing_public_key",
            VpnConfigError::InvalidPublicKey => "invalid_public_key",
            VpnConfigError::InvalidPresharedKey => "invalid_preshared_key",
            VpnConfigError::MissingEndpoint => "missing_endpoint",
            VpnConfigError::InvalidEndpoint => "invalid_endpoint",
            VpnConfigError::MissingAllowedIps => "missing_allowed_ips",
            VpnConfigError::InvalidAllowedIps => "invalid_allowed_ips",
            VpnConfigError::InvalidAddress => "invalid_address",
            VpnConfigError::InvalidDns => "invalid_dns",
            VpnConfigError::InvalidPort => "invalid_port",
            VpnConfigError::InvalidMtu => "invalid_mtu",
            VpnConfigError::InvalidKeepalive => "invalid_keepalive",
            VpnConfigError::UnknownKey => "unknown_key",
            VpnConfigError::DuplicateSection => "duplicate_section",
            VpnConfigError::MalformedLine => "malformed_line",
        }
    }
}

impl fmt::Display for VpnConfigError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(self.key())
    }
}

/// A parsed peer. Secrets are never surfaced: only whether a preshared key
/// exists, never its value.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedPeer {
    pub public_key: String,
    pub endpoint: String,
    pub allowed_ips: Vec<String>,
    pub persistent_keepalive: Option<i32>,
    pub has_preshared_key: bool,
}

/// Parsed, validated view of a WireGuard configuration.
///
/// Only the fields the app itself needs are surfaced; the authoritative parser
/// is `wg`/`wg-quick`, which re-parses `source` before the tunnel is brought up.
/// This parser exists so the UI can reject a broken profile *before* it is
/// stored, show a useful error, and derive the display fields.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedVpnConfig {
    pub source: String,
    pub addresses: Vec<String>,
    pub dns: Vec<String>,
    pub listen_port: Option<i32>,
    pub mtu: Option<i32>,
    pub peers: Vec<ParsedPeer>,
}

impl ParsedVpnConfig {
    pub fn endpoint(&self) -> &str {
        self.peers.first().map(|p| p.endpoint.as_str()).unwrap_or("")
    }

    pub fn allowed_ips(&self) -> Vec<String> {
        self.peers
            .iter()
            .flat_map(|p| p.allowed_ips.iter().cloned())
            .collect()
    }
}

/// Result of parsing: either a validated config or a reason.
pub type VpnConfigResult = Result<ParsedVpnConfig, (VpnConfigError, String)>;

fn err(e: VpnConfigError) -> VpnConfigResult {
    Err((e, String::new()))
}

fn err_detail(e: VpnConfigError, detail: &str) -> VpnConfigResult {
    Err((e, detail.to_string()))
}

/// Plain unsigned decimal ("0", "1", "51820"); rejects "+8", "-0", "008".
fn is_numeric_text(s: &str) -> bool {
    if s.is_empty() {
        return false;
    }
    let bytes = s.as_bytes();
    if bytes[0] == b'0' {
        return bytes.len() == 1;
    }
    bytes.iter().all(|b| b.is_ascii_digit())
}

fn parse_numeric(s: &str) -> Option<i32> {
    if !is_numeric_text(s) {
        return None;
    }
    s.parse::<i32>().ok()
}

/// A WireGuard key is exactly 32 bytes in standard base64 (44 chars, one '=').
/// Anything else would be rejected by the native parser later; rejecting it now
/// gives the user a precise message.
pub fn is_wireguard_key(value: &str) -> bool {
    if value.len() != 44 || !value.ends_with('=') {
        return false;
    }
    let decoded = match base64_decode(value) {
        Some(d) => d,
        None => return false,
    };
    if decoded.len() != 32 {
        return false;
    }
    // Reject a key that is not canonical base64 (e.g. non-zero padding bits),
    // which would otherwise decode to the same bytes with a different text.
    base64_encode(&decoded) == value
}

fn base64_value(c: u8) -> Option<u8> {
    match c {
        b'A'..=b'Z' => Some(c - b'A'),
        b'a'..=b'z' => Some(c - b'a' + 26),
        b'0'..=b'9' => Some(c - b'0' + 52),
        b'+' => Some(62),
        b'/' => Some(63),
        _ => None,
    }
}

fn base64_decode(s: &str) -> Option<Vec<u8>> {
    let bytes = s.as_bytes();
    if bytes.len() % 4 != 0 {
        return None;
    }
    let mut out = Vec::with_capacity(bytes.len() / 4 * 3);
    for chunk in bytes.chunks(4) {
        let mut vals = [0u8; 4];
        let mut pad = 0;
        for (i, &c) in chunk.iter().enumerate() {
            if c == b'=' {
                // Padding is only allowed in the last two positions and the
                // remaining characters must all be padding too.
                if i < 2 {
                    return None;
                }
                pad += 1;
                vals[i] = 0;
            } else {
                if pad > 0 {
                    return None;
                }
                vals[i] = base64_value(c)?;
            }
        }
        let n = (vals[0] as u32) << 18
            | (vals[1] as u32) << 12
            | (vals[2] as u32) << 6
            | (vals[3] as u32);
        out.push((n >> 16) as u8);
        if pad < 2 {
            out.push((n >> 8) as u8);
        }
        if pad < 1 {
            out.push(n as u8);
        }
    }
    Some(out)
}

fn base64_encode(data: &[u8]) -> String {
    const ALPHABET: &[u8; 64] =
        b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity((data.len() + 2) / 3 * 4);
    for chunk in data.chunks(3) {
        let b0 = chunk[0] as u32;
        let b1 = *chunk.get(1).unwrap_or(&0) as u32;
        let b2 = *chunk.get(2).unwrap_or(&0) as u32;
        let n = (b0 << 16) | (b1 << 8) | b2;
        out.push(ALPHABET[((n >> 18) & 63) as usize] as char);
        out.push(ALPHABET[((n >> 12) & 63) as usize] as char);
        if chunk.len() > 1 {
            out.push(ALPHABET[((n >> 6) & 63) as usize] as char);
        } else {
            out.push('=');
        }
        if chunk.len() > 2 {
            out.push(ALPHABET[(n & 63) as usize] as char);
        } else {
            out.push('=');
        }
    }
    out
}

/// `192.168.1.1/24` style. Strict: no leading zeros, no `+`/`-` prefix.
pub fn is_cidr(value: &str) -> bool {
    let slash = match value.find('/') {
        Some(i) if i > 0 && i != value.len() - 1 => i,
        _ => return false,
    };
    let address = &value[..slash];
    let prefix_text = &value[slash + 1..];
    let prefix = match parse_numeric(prefix_text) {
        Some(p) => p,
        None => return false,
    };
    let max_bits = if is_ipv4(address) {
        32
    } else if is_ipv6(address) {
        128
    } else {
        return false;
    };
    (0..=max_bits).contains(&prefix)
}

/// `host:port`, `[v6]:port`, or `hostname:port`.
pub fn is_endpoint(value: &str) -> bool {
    let trimmed = value.trim();
    if trimmed.is_empty() || trimmed.chars().any(|c| c.is_whitespace()) {
        return false;
    }
    let (host, port_text): (&str, &str) = if let Some(rest) = trimmed.strip_prefix('[') {
        // [v6]:port
        let close = match rest.find(']') {
            Some(i) => i,
            None => return false,
        };
        let host = &rest[..close];
        let after = &rest[close + 1..];
        let port = match after.strip_prefix(':') {
            Some(p) => p,
            None => return false,
        };
        if !is_ipv6(host) {
            return false;
        }
        (host, port)
    } else {
        let colon = match trimmed.rfind(':') {
            Some(i) if i > 0 => i,
            _ => return false,
        };
        let host = &trimmed[..colon];
        let port = &trimmed[colon + 1..];
        if host.contains(':') {
            return false;
        }
        if !is_ipv4(host) && !is_hostname(host) {
            return false;
        }
        (host, port)
    };
    let _ = host;
    match parse_numeric(port_text) {
        Some(p) => (1..=65535).contains(&p),
        None => false,
    }
}

fn is_dns_entry(value: &str) -> bool {
    is_ipv4(value) || is_ipv6(value)
}

pub fn is_ipv4(value: &str) -> bool {
    let parts: Vec<&str> = value.split('.').collect();
    if parts.len() != 4 {
        return false;
    }
    parts.iter().all(|part| {
        !part.is_empty()
            && part.len() <= 3
            && part.bytes().all(|b| b.is_ascii_digit())
            && part.parse::<u32>().map(|n| n <= 255).unwrap_or(false)
            && (part.len() == 1 || !part.starts_with('0'))
    })
}

pub fn is_ipv6(value: &str) -> bool {
    if value.is_empty() || value.len() > 45 {
        return false;
    }
    if !value
        .chars()
        .all(|c| c.is_ascii_hexdigit() || c == ':' || c == '.')
    {
        return false;
    }
    if !value.contains(':') {
        return false;
    }
    // A single "::" at most; groups of 1-4 hex digits otherwise.
    let double_colon = value.find("::");
    if let Some(dc) = double_colon {
        if value[dc + 2..].contains("::") {
            return false;
        }
    }
    let (head, tail): (Vec<&str>, Vec<&str>) = if let Some(dc) = double_colon {
        (
            value[..dc].split(':').filter(|s| !s.is_empty()).collect(),
            value[dc + 2..]
                .split(':')
                .filter(|s| !s.is_empty())
                .collect(),
        )
    } else {
        let head: Vec<&str> = value.split(':').collect();
        // Without "::" the address is exactly 8 groups; an embedded IPv4
        // counts as two, so 6 hex groups + IPv4 (7 parts) is also valid.
        let embedded = head.last().map(|s| s.contains('.')).unwrap_or(false);
        let expected = if embedded { 7 } else { 8 };
        if head.len() != expected {
            return false;
        }
        (head, Vec::new())
    };
    let mut groups: Vec<&str> = head;
    groups.extend(tail);

    // Embedded IPv4 (::ffff:1.2.3.4) occupies the last two 16-bit groups and is
    // allowed only as the last "group".
    let has_embedded_ipv4 = groups.last().map(|s| s.contains('.')).unwrap_or(false);
    for (index, group) in groups.iter().enumerate() {
        if has_embedded_ipv4 && index == groups.len() - 1 {
            continue;
        }
        if group.is_empty() || group.len() > 4 {
            return false;
        }
        if !group.bytes().all(|b| b.is_ascii_hexdigit()) {
            return false;
        }
    }
    if has_embedded_ipv4 {
        let last = value.rsplit(':').next().unwrap_or("");
        if !is_ipv4(last) {
            return false;
        }
    }
    // Group-count budget: an embedded IPv4 counts as two groups.
    let effective = groups.len() + usize::from(has_embedded_ipv4);
    if double_colon.is_some() {
        if has_embedded_ipv4 {
            effective <= 8
        } else {
            groups.len() <= 7
        }
    } else {
        effective == 8
    }
}

pub fn is_hostname(value: &str) -> bool {
    if value.is_empty() || value.len() > 253 {
        return false;
    }
    let trimmed = value.trim_end_matches('.');
    if trimmed.is_empty() {
        return false;
    }
    trimmed.split('.').all(|label| {
        !label.is_empty()
            && label.len() <= 63
            && label
                .chars()
                .next()
                .map(|c| c.is_alphanumeric())
                .unwrap_or(false)
            && label
                .chars()
                .last()
                .map(|c| c.is_alphanumeric())
                .unwrap_or(false)
            && label
                .chars()
                .all(|c| c.is_alphanumeric() || c == '-' || c == '_')
    })
}

fn split_list(value: &str) -> Vec<String> {
    value
        .split(',')
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect()
}

/// Normalizes line endings and strips a UTF-8 BOM. A config pasted from a
/// Windows editor or an exported file otherwise fails on a stray `\r`.
pub fn normalize(raw: &str) -> String {
    raw.trim_start_matches('\u{FEFF}')
        .replace("\r\n", "\n")
        .replace('\r', "\n")
        .trim()
        .to_string()
}

/// Keys accepted in `[Interface]`: exactly the set the official wg-quick
/// understands, plus the scope keys the Android library maps to
/// `addAllowedApplication`/`addDisallowedApplication`. Amnezia/future keys are
/// rejected with `UnknownKey`: wg-quick does not support them and silently
/// ignoring them would mislead the user.
const INTERFACE_KEYS: &[&str] = &[
    "privatekey",
    "address",
    "dns",
    "listenport",
    "mtu",
    "excludedapplications",
    "includedapplications",
];

const PEER_KEYS: &[&str] = &[
    "publickey",
    "presharedkey",
    "allowedips",
    "endpoint",
    "persistentkeepalive",
];

#[derive(Default)]
struct MutablePeer {
    public_key: String,
    endpoint: String,
    allowed_ips: Vec<String>,
    keepalive: Option<i32>,
    has_preshared_key: bool,
}

/// Parses and validates a WireGuard configuration.
pub fn parse(raw: &str) -> VpnConfigResult {
    // Pre-normalization raw-length guard: normalize()/line handling on a
    // multi-MB paste would allocate heavily before the byte check below.
    if raw.len() > MAX_BYTES * 4 {
        return err(VpnConfigError::TooLarge);
    }
    let text = normalize(raw);
    if text.is_empty() {
        return err(VpnConfigError::Empty);
    }
    if text.len() > MAX_BYTES {
        return err(VpnConfigError::TooLarge);
    }

    let mut section: Option<&str> = None;
    let mut saw_interface = false;
    let mut saw_peer = false;
    let mut private_key: Option<String> = None;
    let mut addresses: Vec<String> = Vec::new();
    let mut dns: Vec<String> = Vec::new();
    let mut listen_port: Option<i32> = None;
    let mut mtu: Option<i32> = None;
    let mut peers: Vec<MutablePeer> = Vec::new();

    for raw_line in text.lines() {
        let line = raw_line
            .split('#')
            .next()
            .unwrap_or("")
            .split(';')
            .next()
            .unwrap_or("")
            .trim();
        if line.is_empty() {
            continue;
        }
        if line.starts_with('[') {
            match line.to_lowercase().as_str() {
                "[interface]" => {
                    if saw_interface {
                        return err_detail(VpnConfigError::DuplicateSection, "[Interface]");
                    }
                    saw_interface = true;
                    section = Some("interface");
                }
                "[peer]" => {
                    if peers.len() >= MAX_PEERS {
                        return err_detail(VpnConfigError::TooLarge, "peers");
                    }
                    saw_peer = true;
                    section = Some("peer");
                    peers.push(MutablePeer::default());
                }
                _ => return err_detail(VpnConfigError::UnknownKey, line),
            }
            continue;
        }
        let eq = match line.find('=') {
            Some(i) if i > 0 => i,
            _ => return err_detail(VpnConfigError::MalformedLine, line),
        };
        let key = line[..eq].trim().to_lowercase();
        let value = line[eq + 1..].trim();
        match section {
            Some("interface") => match key.as_str() {
                "privatekey" => {
                    if private_key.is_some() {
                        return err_detail(
                            VpnConfigError::MalformedLine,
                            "duplicate PrivateKey",
                        );
                    }
                    if !is_wireguard_key(value) {
                        return err(VpnConfigError::InvalidPrivateKey);
                    }
                    private_key = Some(value.to_string());
                }
                "address" => {
                    let list = split_list(value);
                    if list.is_empty() || !list.iter().all(|v| is_cidr(v)) {
                        return err_detail(VpnConfigError::InvalidAddress, value);
                    }
                    if addresses.len() + list.len() > MAX_LIST_ITEMS {
                        return err_detail(VpnConfigError::TooLarge, "Address");
                    }
                    addresses.extend(list);
                }
                "dns" => {
                    let list = split_list(value);
                    if list.is_empty() || !list.iter().all(|v| is_dns_entry(v)) {
                        return err_detail(VpnConfigError::InvalidDns, value);
                    }
                    if dns.len() + list.len() > MAX_LIST_ITEMS {
                        return err_detail(VpnConfigError::TooLarge, "DNS");
                    }
                    dns.extend(list);
                }
                "listenport" => match parse_numeric(value) {
                    Some(p) if (1..=65535).contains(&p) => listen_port = Some(p),
                    _ => return err_detail(VpnConfigError::InvalidPort, value),
                },
                "mtu" => match parse_numeric(value) {
                    Some(p) if (MIN_MTU..=MAX_MTU).contains(&p) => mtu = Some(p),
                    _ => return err_detail(VpnConfigError::InvalidMtu, value),
                },
                k if INTERFACE_KEYS.contains(&k) => {}
                _ => return err_detail(VpnConfigError::UnknownKey, &key),
            },
            Some("peer") => {
                let peer = match peers.last_mut() {
                    Some(p) => p,
                    None => return err_detail(VpnConfigError::MalformedLine, line),
                };
                match key.as_str() {
                    "publickey" => {
                        if !is_wireguard_key(value) {
                            return err(VpnConfigError::InvalidPublicKey);
                        }
                        peer.public_key = value.to_string();
                    }
                    "presharedkey" => {
                        if !is_wireguard_key(value) {
                            return err(VpnConfigError::InvalidPresharedKey);
                        }
                        peer.has_preshared_key = true;
                    }
                    "allowedips" => {
                        let list = split_list(value);
                        if list.is_empty() || !list.iter().all(|v| is_cidr(v)) {
                            return err_detail(VpnConfigError::InvalidAllowedIps, value);
                        }
                        if peer.allowed_ips.len() + list.len() > MAX_LIST_ITEMS {
                            return err_detail(VpnConfigError::TooLarge, "AllowedIPs");
                        }
                        peer.allowed_ips.extend(list);
                    }
                    "endpoint" => {
                        if !is_endpoint(value) {
                            return err_detail(VpnConfigError::InvalidEndpoint, value);
                        }
                        peer.endpoint = value.to_string();
                    }
                    "persistentkeepalive" => match parse_numeric(value) {
                        Some(k) if (0..=65535).contains(&k) => peer.keepalive = Some(k),
                        _ => return err_detail(VpnConfigError::InvalidKeepalive, value),
                    },
                    k if PEER_KEYS.contains(&k) => {}
                    _ => return err_detail(VpnConfigError::UnknownKey, &key),
                }
            }
            _ => return err_detail(VpnConfigError::MalformedLine, line),
        }
    }

    if !saw_interface {
        return err(VpnConfigError::MissingInterface);
    }
    if private_key.is_none() {
        return err(VpnConfigError::MissingPrivateKey);
    }
    if !saw_peer || peers.is_empty() {
        return err(VpnConfigError::MissingPeer);
    }

    let mut parsed_peers = Vec::with_capacity(peers.len());
    for peer in peers {
        if peer.public_key.is_empty() {
            return err(VpnConfigError::MissingPublicKey);
        }
        if peer.allowed_ips.is_empty() {
            return err(VpnConfigError::MissingAllowedIps);
        }
        // An endpoint is optional in WireGuard (a server-side peer), but a
        // client profile that cannot dial anyone is useless in this app.
        if peer.endpoint.is_empty() {
            return err(VpnConfigError::MissingEndpoint);
        }
        parsed_peers.push(ParsedPeer {
            public_key: peer.public_key,
            endpoint: peer.endpoint,
            allowed_ips: peer.allowed_ips,
            persistent_keepalive: peer.keepalive,
            has_preshared_key: peer.has_preshared_key,
        });
    }

    Ok(ParsedVpnConfig {
        source: text,
        addresses,
        dns,
        listen_port,
        mtu,
        peers: parsed_peers,
    })
}

/// Naming rules for a profile. The tunnel name handed to WireGuard must match
/// `[a-zA-Z0-9_=+.-]{1,15}`; the display name is free text, so a safe tunnel
/// name is derived from the profile id instead of the user's text.
pub fn is_valid_tunnel_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= 15
        && name
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '=' | '+' | '.' | '-'))
}

pub fn sanitize_display_name(raw: &str, fallback: &str) -> String {
    let cleaned: String = raw
        .chars()
        .filter(|c| (*c as u32) >= 0x20 && (*c as u32) != 0x7f)
        .collect();
    let cleaned: String = cleaned.trim().chars().take(MAX_NAME_LENGTH).collect();
    if cleaned.is_empty() {
        fallback.to_string()
    } else {
        cleaned
    }
}

pub fn tunnel_name_for(profile_id: &str) -> String {
    let compact: String = profile_id
        .chars()
        .filter(|c| c.is_alphanumeric())
        .take(12)
        .collect();
    let name = format!("hb{compact}");
    if is_valid_tunnel_name(&name) {
        name
    } else {
        "hbvpn".to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const KEY_A: &str = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    const KEY_B: &str = "ERERERERERERERERERERERERERERERERERERERERERE=";

    fn good() -> String {
        format!(
            "[Interface]\nPrivateKey = {KEY_A}\nAddress = 10.0.0.2/32\nDNS = 1.1.1.1\n\n[Peer]\nPublicKey = {KEY_B}\nEndpoint = vpn.example.com:51820\nAllowedIPs = 0.0.0.0/0\n"
        )
    }

    #[test]
    fn parses_a_valid_config() {
        let c = parse(&good()).expect("should parse");
        assert_eq!(vec!["10.0.0.2/32"], c.addresses);
        assert_eq!(vec!["1.1.1.1"], c.dns);
        assert_eq!("vpn.example.com:51820", c.endpoint());
        assert_eq!(1, c.peers.len());
        assert_eq!(vec!["0.0.0.0/0"], c.peers[0].allowed_ips);
        assert!(!c.peers[0].has_preshared_key);
    }

    #[test]
    fn rejects_empty() {
        assert_eq!(Some(VpnConfigError::Empty), parse("").err().map(|e| e.0));
        assert_eq!(
            Some(VpnConfigError::Empty),
            parse("   \n\n  ").err().map(|e| e.0)
        );
    }

    #[test]
    fn rejects_missing_sections() {
        assert_eq!(
            Some(VpnConfigError::MissingInterface),
            parse(&format!("[Peer]\nPublicKey = {KEY_B}\n"))
                .err()
                .map(|e| e.0)
        );
        assert_eq!(
            Some(VpnConfigError::MissingPeer),
            parse(&format!("[Interface]\nPrivateKey = {KEY_A}\n"))
                .err()
                .map(|e| e.0)
        );
    }

    #[test]
    fn rejects_bad_keys() {
        assert_eq!(
            Some(VpnConfigError::InvalidPrivateKey),
            parse("[Interface]\nPrivateKey = short\n[Peer]\n")
                .err()
                .map(|e| e.0)
        );
        // 44 chars but not canonical base64.
        let bad = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAB=";
        assert_eq!(
            Some(VpnConfigError::InvalidPrivateKey),
            parse(&format!("[Interface]\nPrivateKey = {bad}\n[Peer]\n"))
                .err()
                .map(|e| e.0)
        );
    }

    #[test]
    fn rejects_unknown_keys() {
        let cfg = format!("[Interface]\nPrivateKey = {KEY_A}\nJc = 3\n[Peer]\n");
        assert_eq!(
            Some(VpnConfigError::UnknownKey),
            parse(&cfg).err().map(|e| e.0)
        );
    }

    #[test]
    fn rejects_duplicate_interface() {
        let cfg = format!("[Interface]\nPrivateKey = {KEY_A}\n[Interface]\n");
        assert_eq!(
            Some(VpnConfigError::DuplicateSection),
            parse(&cfg).err().map(|e| e.0)
        );
    }

    #[test]
    fn rejects_bad_endpoint() {
        for ep in ["", "hostonly", "host:0", "host:70000", "host:+8", "a b:80"] {
            let cfg = format!(
                "[Interface]\nPrivateKey = {KEY_A}\n[Peer]\nPublicKey = {KEY_B}\nEndpoint = {ep}\nAllowedIPs = 0.0.0.0/0\n"
            );
            let got = parse(&cfg).err().map(|e| e.0);
            assert!(
                got == Some(VpnConfigError::InvalidEndpoint)
                    || got == Some(VpnConfigError::MissingEndpoint),
                "endpoint {ep:?} gave {got:?}"
            );
        }
    }

    #[test]
    fn accepts_ipv6_endpoint() {
        let cfg = format!(
            "[Interface]\nPrivateKey = {KEY_A}\n[Peer]\nPublicKey = {KEY_B}\nEndpoint = [::1]:51820\nAllowedIPs = ::/0\n"
        );
        let c = parse(&cfg).expect("ipv6 endpoint");
        assert_eq!("[::1]:51820", c.endpoint());
    }

    #[test]
    fn rejects_missing_allowed_ips() {
        let cfg = format!(
            "[Interface]\nPrivateKey = {KEY_A}\n[Peer]\nPublicKey = {KEY_B}\nEndpoint = a.example:1\n"
        );
        assert_eq!(
            Some(VpnConfigError::MissingAllowedIps),
            parse(&cfg).err().map(|e| e.0)
        );
    }

    #[test]
    fn strips_bom_and_crlf() {
        let raw = format!("\u{FEFF}[Interface]\r\nPrivateKey = {KEY_A}\r\n[Peer]\r\nPublicKey = {KEY_B}\r\nEndpoint = a.example:1\r\nAllowedIPs = 0.0.0.0/0\r\n");
        let c = parse(&raw).expect("crlf config");
        assert!(!c.source.contains('\r'));
    }

    #[test]
    fn ignores_comments() {
        let cfg = format!(
            "# a comment\n[Interface]\nPrivateKey = {KEY_A} ; inline\n[Peer]\nPublicKey = {KEY_B}\nEndpoint = a.example:1\nAllowedIPs = 0.0.0.0/0\n"
        );
        assert!(parse(&cfg).is_ok());
    }

    #[test]
    fn rejects_oversized_input() {
        let big = "x".repeat(MAX_BYTES * 4 + 1);
        assert_eq!(
            Some(VpnConfigError::TooLarge),
            parse(&big).err().map(|e| e.0)
        );
    }

    #[test]
    fn rejects_too_many_peers() {
        let mut cfg = format!("[Interface]\nPrivateKey = {KEY_A}\n");
        for _ in 0..(MAX_PEERS + 1) {
            cfg.push_str(&format!(
                "[Peer]\nPublicKey = {KEY_B}\nEndpoint = a.example:1\nAllowedIPs = 0.0.0.0/0\n"
            ));
        }
        assert_eq!(
            Some(VpnConfigError::TooLarge),
            parse(&cfg).err().map(|e| e.0)
        );
    }

    #[test]
    fn preshared_key_is_detected_but_never_surfaced() {
        let cfg = format!(
            "[Interface]\nPrivateKey = {KEY_A}\n[Peer]\nPublicKey = {KEY_B}\nPresharedKey = {KEY_A}\nEndpoint = a.example:1\nAllowedIPs = 0.0.0.0/0\n"
        );
        let c = parse(&cfg).expect("psk config");
        assert!(c.peers[0].has_preshared_key);
        // The parsed struct has no field holding the PSK value.
        let dbg = format!("{:?}", c.peers[0]);
        assert!(!dbg.contains(KEY_A));
    }

    // ------------------------------------------------------- validators

    #[test]
    fn cidr_rules() {
        assert!(is_cidr("0.0.0.0/0"));
        assert!(is_cidr("10.0.0.2/32"));
        assert!(is_cidr("::/0"));
        assert!(is_cidr("fd00::1/128"));
        assert!(!is_cidr("10.0.0.2"));
        assert!(!is_cidr("10.0.0.2/33"));
        assert!(!is_cidr("10.0.0.2/+8"));
        assert!(!is_cidr("10.0.0.2/-0"));
        assert!(!is_cidr("010.0.0.2/32"));
        assert!(!is_cidr("/32"));
        assert!(!is_cidr("10.0.0.2/"));
    }

    #[test]
    fn ipv4_rules() {
        assert!(is_ipv4("1.2.3.4"));
        assert!(is_ipv4("0.0.0.0"));
        assert!(!is_ipv4("1.2.3"));
        assert!(!is_ipv4("1.2.3.256"));
        assert!(!is_ipv4("01.2.3.4"));
        assert!(!is_ipv4("1.2.3.4.5"));
    }

    #[test]
    fn ipv6_rules() {
        assert!(is_ipv6("::"));
        assert!(is_ipv6("::1"));
        assert!(is_ipv6("2001:db8::1"));
        assert!(is_ipv6("::ffff:1.2.3.4"));
        assert!(is_ipv6("2001:db8:0:0:0:0:0:1"));
        assert!(!is_ipv6("2001:db8::1::2"));
        assert!(!is_ipv6("12345::1"));
        assert!(!is_ipv6("gggg::1"));
        assert!(!is_ipv6("no-colons"));
    }

    #[test]
    fn hostname_rules() {
        assert!(is_hostname("vpn.example.com"));
        assert!(is_hostname("a"));
        assert!(is_hostname("my_host.local"));
        assert!(!is_hostname("-bad.example"));
        assert!(!is_hostname("bad-.example"));
        assert!(!is_hostname(""));
        assert!(!is_hostname(&"a".repeat(64)));
    }

    #[test]
    fn wireguard_key_rules() {
        assert!(is_wireguard_key(KEY_A));
        assert!(!is_wireguard_key(""));
        assert!(!is_wireguard_key("short"));
        // Wrong length.
        assert!(!is_wireguard_key("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="));
        // Not base64.
        assert!(!is_wireguard_key("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!="));
    }

    #[test]
    fn base64_round_trips() {
        for len in 0..8usize {
            let data: Vec<u8> = (0..len).map(|i| (i * 37 + 11) as u8).collect();
            let enc = base64_encode(&data);
            assert_eq!(Some(data), base64_decode(&enc), "len {len}");
        }
    }

    // ----------------------------------------------------------- naming

    #[test]
    fn tunnel_names_are_valid() {
        let n = tunnel_name_for("1700000000-123456");
        assert!(is_valid_tunnel_name(&n), "got {n}");
        assert!(n.starts_with("hb"));
        // A pathological id still yields a *valid* tunnel name. "hb" is
        // already valid (1-15 chars), so the fallback is not needed here; the
        // contract is validity, not a particular string.
        let n2 = tunnel_name_for("!!!");
        assert!(is_valid_tunnel_name(&n2), "got {n2}");
        // An empty id also yields the valid "hb" name; the fallback exists
        // only for a derived name that would be invalid.
        assert_eq!("hb", tunnel_name_for(""));
    }

    #[test]
    fn display_name_is_sanitized() {
        assert_eq!("hello", sanitize_display_name("  hello  ", "fallback"));
        assert_eq!("fallback", sanitize_display_name("   ", "fallback"));
        assert_eq!("fallback", sanitize_display_name("", "fallback"));
        let long = sanitize_display_name(&"a".repeat(100), "fb");
        assert_eq!(MAX_NAME_LENGTH, long.chars().count());
        // Control characters are stripped.
        assert_eq!("ab", sanitize_display_name("a\u{0007}b", "fb"));
    }
}
