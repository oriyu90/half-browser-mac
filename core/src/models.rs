//! Data models ported from Android `core/Models.kt`.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Bookmark {
    pub id: String,
    pub title: String,
    pub url: String,
    pub monogram: String,
    pub monogram_color: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct TrustedSite {
    pub host: String,
    pub port: i32,
    pub fingerprint_sha256: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct HistoryEntry {
    pub url: String,
    pub title: String,
    pub visited_at: i64,
    pub visit_count: i32,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct HistoryList {
    pub version: i32,
    pub items: Vec<HistoryEntry>,
}

impl Default for HistoryList {
    fn default() -> Self {
        Self { version: 1, items: vec![] }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum ThemeMode {
    System,
    Light,
    Dark,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum LanguageMode {
    System,
    Ja,
    En,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct AppSettings {
    pub theme_mode: ThemeMode,
    pub ui_scale: f32,
    pub font_scale: f32,
    pub grid_columns: i32,
    pub language: LanguageMode,
    pub accent_hue: f32,
    pub accent_saturation: f32,
    pub accent_tone: f32,
    pub search_engine: String,
}

impl AppSettings {
    pub const MIN_UI_SCALE: f32 = 0.8;
    pub const MAX_UI_SCALE: f32 = 1.4;
    pub const MIN_FONT_SCALE: f32 = 0.8;
    pub const MAX_FONT_SCALE: f32 = 1.5;
    pub const MIN_ACCENT_SATURATION: f32 = 0.0;
    pub const MAX_ACCENT_SATURATION: f32 = 1.0;
    pub const ALLOWED_GRID_COLUMNS: [i32; 6] = [0, 3, 4, 5, 6, 8];
    pub const DEFAULT_ACCENT_HUE: f32 = 210.0;

    pub fn default() -> Self {
        Self {
            theme_mode: ThemeMode::System,
            ui_scale: 1.0,
            font_scale: 1.0,
            grid_columns: 0,
            language: LanguageMode::System,
            accent_hue: Self::DEFAULT_ACCENT_HUE,
            accent_saturation: 0.8,
            accent_tone: 0.5,
            search_engine: "duckduckgo".to_string(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SiteWatch {
    pub bookmark_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SiteWatchSettings {
    pub interval_minutes: i32,
    pub last_run_result: String,
}

impl Default for SiteWatchSettings {
    fn default() -> Self {
        Self { interval_minutes: 60, last_run_result: String::new() }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SitePermissionGrant {
    pub origin: String,
    pub kind: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct BookmarkList {
    pub items: Vec<Bookmark>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct TrustedSiteList {
    pub items: Vec<TrustedSite>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SiteWatchList {
    pub items: Vec<SiteWatch>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SitePermissionList {
    pub items: Vec<SitePermissionGrant>,
}