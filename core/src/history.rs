//! Ported from Android `core/History.kt`.

use crate::models::HistoryEntry;
use crate::url_normalizer::UrlNormalizer;

pub struct HistoryRules;

impl HistoryRules {
    pub const MAX_ENTRIES: usize = 500;
    pub const MERGE_WINDOW_MS: i64 = 30 * 60 * 1000;

    pub fn record(
        current: &[HistoryEntry],
        url: &str,
        title: &str,
        now: i64,
    ) -> Vec<HistoryEntry> {
        let normalized = match UrlNormalizer::validate_web_url(url) {
            Some(u) => u,
            None => return current.to_vec(),
        };
        let clean_title: String = title.trim().chars().take(300).collect();

        let existing_index = current.iter().position(|e| {
            UrlNormalizer::canonical_for_compare(&e.url)
                == UrlNormalizer::canonical_for_compare(&normalized)
        });

        let head = if let Some(idx) = existing_index {
            let existing = &current[idx];
            let recent = now - existing.visited_at <= Self::MERGE_WINDOW_MS;
            let updated = HistoryEntry {
                url: normalized.clone(),
                title: if clean_title.is_empty() {
                    existing.title.clone()
                } else {
                    clean_title.clone()
                },
                visited_at: now,
                visit_count: if recent {
                    existing.visit_count
                } else {
                    existing.visit_count + 1
                },
            };
            let mut v = vec![updated];
            for (i, e) in current.iter().enumerate() {
                if i != idx {
                    v.push(e.clone());
                }
            }
            v
        } else {
            let mut v = vec![HistoryEntry {
                url: normalized,
                title: clean_title,
                visited_at: now,
                visit_count: 1,
            }];
            v.extend(current.iter().cloned());
            v
        };

        head.into_iter().take(Self::MAX_ENTRIES).collect()
    }

    pub fn sanitize(current: &[HistoryEntry]) -> Vec<HistoryEntry> {
        let mut seen = std::collections::HashSet::new();
        let mut out = Vec::new();
        for e in current {
            if UrlNormalizer::validate_web_url(&e.url).is_none() {
                continue;
            }
            let key = UrlNormalizer::canonical_for_compare(&e.url);
            if let Some(k) = key {
                if seen.contains(&k) {
                    continue;
                }
                seen.insert(k);
            }
            out.push(e.clone());
            if out.len() >= Self::MAX_ENTRIES {
                break;
            }
        }
        out
    }
}