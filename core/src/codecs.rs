//! Ported from Android `core/Codecs.kt` (JSON codecs).

use crate::models::{AppSettings, Bookmark, BookmarkList, TrustedSiteList};
use crate::url_normalizer::UrlNormalizer;

pub struct Codecs;

impl Codecs {
    pub fn sanitize_settings(s: AppSettings) -> AppSettings {
        let mut s = s;
        s.ui_scale = s.ui_scale.clamp(AppSettings::MIN_UI_SCALE, AppSettings::MAX_UI_SCALE);
        s.font_scale = s.font_scale.clamp(AppSettings::MIN_FONT_SCALE, AppSettings::MAX_FONT_SCALE);
        if !AppSettings::ALLOWED_GRID_COLUMNS.contains(&s.grid_columns) {
            s.grid_columns = 0;
        }
        s.accent_hue = ((s.accent_hue % 360.0) + 360.0) % 360.0;
        s.accent_saturation = s.accent_saturation.clamp(AppSettings::MIN_ACCENT_SATURATION, AppSettings::MAX_ACCENT_SATURATION);
        s.accent_tone = s.accent_tone.clamp(0.0, 1.0);
        s
    }

    pub fn encode_settings(s: &AppSettings) -> String {
        serde_json::to_string(s).unwrap_or_default()
    }

    pub fn decode_settings(raw: Option<&str>) -> AppSettings {
        let raw = match raw {
            Some(r) if !r.trim().is_empty() => r,
            _ => return AppSettings::default(),
        };
        let decoded: Option<AppSettings> = serde_json::from_str(raw).ok();
        Self::sanitize_settings(decoded.unwrap_or_else(AppSettings::default))
    }

    pub fn encode_bookmarks(items: &[Bookmark]) -> String {
        let list = BookmarkList { items: items.to_vec() };
        serde_json::to_string(&list).unwrap_or_default()
    }

    pub fn decode_bookmarks(raw: Option<&str>) -> Vec<Bookmark> {
        let raw = match raw {
            Some(r) if !r.trim().is_empty() => r,
            _ => return vec![],
        };
        let list: Option<BookmarkList> = serde_json::from_str(raw).ok();
        match list {
            Some(l) => l
                .items
                .into_iter()
                .filter(|b| !b.id.is_empty() && UrlNormalizer::validate_web_url(&b.url).is_some())
                .fold(Vec::new(), |mut acc, b| {
                    if !acc.iter().any(|x: &Bookmark| x.id == b.id) {
                        acc.push(b);
                    }
                    acc
                }),
            None => vec![],
        }
    }

    pub fn encode_trusted_sites(items: &[crate::models::TrustedSite]) -> String {
        let list = TrustedSiteList { items: items.to_vec() };
        serde_json::to_string(&list).unwrap_or_default()
    }

    pub fn decode_trusted_sites(raw: Option<&str>) -> Vec<crate::models::TrustedSite> {
        let raw = match raw {
            Some(r) if !r.trim().is_empty() => r,
            _ => return vec![],
        };
        let list: Option<TrustedSiteList> = serde_json::from_str(raw).ok();
        match list {
            Some(l) => l
                .items
                .into_iter()
                .filter(|t| !t.host.is_empty() && !t.fingerprint_sha256.is_empty())
                .fold(Vec::new(), |mut acc, t| {
                    let key = format!("{}:{}", t.host.to_lowercase(), t.port);
                    if !acc.iter().any(|x: &crate::models::TrustedSite| format!("{}:{}", x.host.to_lowercase(), x.port) == key) {
                        acc.push(t);
                    }
                    acc
                }),
            None => vec![],
        }
    }
}