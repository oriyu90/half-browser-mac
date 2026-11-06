//! Ported from Android `core/UrlNormalizer.kt`.

use regex::Regex;
use url::Url;

pub struct UrlNormalizer;

const ALLOWED_SCHEMES: [&str; 2] = ["http", "https"];

impl UrlNormalizer {
    pub fn to_navigable(input: &str, search_template: &str) -> Option<String> {
        let trimmed = input.trim();
        if trimmed.is_empty() {
            return None;
        }
        if trimmed.contains(' ') {
            return Some(Self::search_url(trimmed, search_template));
        }

        // host-like check
        if Self::host_like(trimmed) {
            return Self::validate_web_url(&format!("https://{}", trimmed));
        }

        // scheme check
        let scheme_re = Regex::new(r"^([a-zA-Z][a-zA-Z0-9+.-]*):").unwrap();
        if let Some(caps) = scheme_re.captures(trimmed) {
            let scheme = caps.get(1).unwrap().as_str().to_lowercase();
            if !ALLOWED_SCHEMES.contains(&scheme.as_str()) {
                return None;
            }
            return Self::validate_web_url(trimmed);
        }

        // bare word -> search
        Some(Self::search_url(trimmed, search_template))
    }

    pub fn normalize_for_bookmark(input: &str) -> Option<String> {
        let trimmed = input.trim();
        if trimmed.is_empty() {
            return None;
        }
        let lower = trimmed.to_lowercase();
        if lower.starts_with("http://") || lower.starts_with("https://") {
            return Self::validate_web_url(trimmed);
        }
        if Self::host_like(trimmed) {
            return Self::validate_web_url(&format!("https://{}", trimmed));
        }
        None
    }

    pub fn validate_web_url(url: &str) -> Option<String> {
        let candidate = url.trim();
        if candidate.is_empty() {
            return None;
        }
        let parsed = Url::parse(candidate).ok()?;
        let scheme = parsed.scheme().to_lowercase();
        if !ALLOWED_SCHEMES.contains(&scheme.as_str()) {
            return None;
        }
        let host = parsed.host_str()?;
        if host.trim().is_empty() {
            return None;
        }
        // reject user@host
        if parsed.username() != "" {
            return None;
        }
        Some(parsed.to_string())
    }

    pub fn canonical_for_compare(url: &str) -> Option<String> {
        let validated = Self::validate_web_url(url)?;
        let parsed = Url::parse(&validated).ok()?;
        let scheme = parsed.scheme().to_lowercase();
        let host = parsed.host_str()?.to_lowercase();
        let port = parsed.port();
        let default_port = (scheme == "https" && port == Some(443))
            || (scheme == "http" && port == Some(80));
        let port_part = match port {
            None => String::new(),
            Some(_) if default_port => String::new(),
            Some(p) => format!(":{}", p),
        };
        let mut path = parsed.path().to_string();
        if path.is_empty() {
            path = "/".to_string();
        }
        if path.len() > 1 && path.ends_with('/') {
            path.pop();
        }
        let query = parsed.query().map(|q| format!("?{}", q)).unwrap_or_default();
        Some(format!("{}://{}{}{}{}", scheme, host, port_part, path, query))
    }

    pub fn display_host(url: &str) -> Option<String> {
        let validated = Self::validate_web_url(url)?;
        let parsed = Url::parse(&validated).ok()?;
        parsed.host_str().map(|s| s.to_string())
    }

    pub fn search_url(query: &str, search_template: &str) -> String {
        let encoded = urlencoding::encode(query);
        search_template.replace("%s", &encoded)
    }

    fn host_like(s: &str) -> bool {
        let pattern = r"(?i)^(localhost|\d{1,3}(\.\d{1,3}){3}|[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+)(:\d{1,5})?([/?#].*)?$";
        let re = Regex::new(pattern).unwrap();
        re.is_match(s)
    }
}

// Need urlencoding crate. Add to Cargo.toml.
// Actually implement simple percent-encoding here to avoid extra dep.
mod urlencoding {
    pub fn encode(s: &str) -> String {
        let mut out = String::new();
        for b in s.bytes() {
            match b {
                b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                    out.push(b as char);
                }
                b' ' => out.push_str("%20"),
                _ => out.push_str(&format!("%{:02X}", b)),
            }
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::UrlNormalizer;

    #[test]
    fn to_navigable_blank() {
        assert_eq!(UrlNormalizer::to_navigable("", "https://duckduckgo.com/?q=%s"), None);
    }

    #[test]
    fn to_navigable_host() {
        assert_eq!(
            UrlNormalizer::to_navigable("example.com", "https://duckduckgo.com/?q=%s"),
            Some("https://example.com/".to_string())
        );
    }

    #[test]
    fn to_navigable_rejects_javascript() {
        assert_eq!(
            UrlNormalizer::to_navigable("javascript:alert(1)", "https://duckduckgo.com/?q=%s"),
            None
        );
    }

    #[test]
    fn canonical_for_compare_strips_trailing_slash() {
        assert_eq!(
            UrlNormalizer::canonical_for_compare("https://example.com/foo/"),
            Some("https://example.com/foo".to_string())
        );
    }

    #[test]
    fn search_url_encodes() {
        let u = UrlNormalizer::search_url("hello world", "https://duckduckgo.com/?q=%s");
        assert!(u.contains("hello%20world"));
    }
}