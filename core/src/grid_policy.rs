//! Ported from Android `core/GridColumns` / width bucket logic.

pub struct GridPolicy;

impl GridPolicy {
    /// Compute number of grid columns given available width and requested columns.
    pub fn columns(available_width: f32, requested: i32, min_tile: f32) -> i32 {
        if requested > 0 {
            return requested;
        }
        if available_width <= 0.0 || min_tile <= 0.0 {
            return 3;
        }
        let cols = (available_width / min_tile).floor() as i32;
        cols.clamp(3, 8)
    }

    pub fn width_bucket(width: f32) -> &'static str {
        if width < 600.0 {
            "compact"
        } else if width < 840.0 {
            "medium"
        } else if width < 1200.0 {
            "expanded"
        } else {
            "large"
        }
    }
}