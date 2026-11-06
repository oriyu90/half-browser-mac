//! Ported from Android `core/AccentMath.kt`.

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct AccentPalette {
    pub primary: u32,
    pub on_primary: u32,
    pub primary_container: u32,
    pub on_primary_container: u32,
    pub secondary: u32,
    pub on_secondary: u32,
    pub secondary_container: u32,
    pub on_secondary_container: u32,
    pub tertiary: u32,
    pub on_tertiary: u32,
    pub tertiary_container: u32,
    pub on_tertiary_container: u32,
}

const WHITE: u32 = 0xFFFFFFFF;
const BLACK: u32 = 0xFF000000;
const SECONDARY_SHIFT: f32 = 30.0;
const TERTIARY_SHIFT: f32 = -32.0;

pub struct AccentMath;

impl AccentMath {
    pub fn normalize_hue(hue: f32) -> f32 {
        if hue.is_nan() || hue.is_infinite() {
            return 210.0;
        }
        let wrapped = ((hue % 360.0) + 360.0) % 360.0;
        if wrapped.is_nan() { 0.0 } else { wrapped }
    }

    pub fn hsl(hue: f32, saturation: f32, lightness: f32) -> u32 {
        let h = Self::normalize_hue(hue) / 60.0;
        let s = saturation.clamp(0.0, 1.0);
        let l = lightness.clamp(0.0, 1.0);
        let c = (1.0 - (2.0 * l - 1.0).abs()) * s;
        let x = c * (1.0 - (h % 2.0 - 1.0).abs());
        let m = l - c / 2.0;
        let hi = h.floor() as i32;
        let (r1, g1, b1) = match hi {
            0 => (c, x, 0.0f32),
            1 => (x, c, 0.0),
            2 => (0.0, c, x),
            3 => (0.0, x, c),
            4 => (x, 0.0, c),
            _ => (c, 0.0, x),
        };
        let r = ((r1 + m) * 255.0 + 0.5).clamp(0.0, 255.0) as u32;
        let g = ((g1 + m) * 255.0 + 0.5).clamp(0.0, 255.0) as u32;
        let b = ((b1 + m) * 255.0 + 0.5).clamp(0.0, 255.0) as u32;
        (0xFF << 24) | (r << 16) | (g << 8) | b
    }

    pub fn luminance(color: u32) -> f64 {
        fn channel(value: u32) -> f64 {
            let c = value as f64 / 255.0;
            if c <= 0.04045 { c / 12.92 } else { ((c + 0.055) / 1.055).powf(2.4) }
        }
        let r = channel((color >> 16) & 0xFF);
        let g = channel((color >> 8) & 0xFF);
        let b = channel(color & 0xFF);
        0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    pub fn contrast_ratio(a: u32, b: u32) -> f64 {
        let la = Self::luminance(a);
        let lb = Self::luminance(b);
        let lighter = la.max(lb);
        let darker = la.min(lb);
        (lighter + 0.05) / (darker + 0.05)
    }

    pub fn readable_on(background: u32) -> u32 {
        let white = Self::contrast_ratio(WHITE, background);
        let black = Self::contrast_ratio(BLACK, background);
        if white >= black { WHITE } else { BLACK }
    }

    pub fn palette(hue: f32, saturation: f32, tone: f32, dark: bool) -> AccentPalette {
        let h = Self::normalize_hue(hue);
        let s = saturation.clamp(0.0, 1.0);
        let t = tone.clamp(0.0, 1.0);
        let lerp = |a: f32, b: f32, f: f32| a + (b - a) * f;

        if dark {
            let primary = Self::hsl(h, s * 0.82, lerp(0.68, 0.84, t));
            let primary_container = Self::hsl(h, s * 0.70, lerp(0.24, 0.32, t));
            let secondary = Self::hsl(h + SECONDARY_SHIFT, s * 0.70, lerp(0.72, 0.86, t));
            let secondary_container = Self::hsl(h + SECONDARY_SHIFT, s * 0.62, lerp(0.24, 0.32, t));
            let tertiary = Self::hsl(h + TERTIARY_SHIFT, s * 0.72, lerp(0.74, 0.88, t));
            let tertiary_container = Self::hsl(h + TERTIARY_SHIFT, s * 0.62, lerp(0.26, 0.34, t));
            AccentPalette {
                primary,
                on_primary: Self::readable_on(primary),
                primary_container,
                on_primary_container: Self::readable_on(primary_container),
                secondary,
                on_secondary: Self::readable_on(secondary),
                secondary_container,
                on_secondary_container: Self::readable_on(secondary_container),
                tertiary,
                on_tertiary: Self::readable_on(tertiary),
                tertiary_container,
                on_tertiary_container: Self::readable_on(tertiary_container),
            }
        } else {
            let primary = Self::hsl(h, s, lerp(0.32, 0.46, t));
            let primary_container = Self::hsl(h, s * 0.55, lerp(0.88, 0.94, t));
            let secondary = Self::hsl(h + SECONDARY_SHIFT, s * 0.80, lerp(0.28, 0.40, t));
            let secondary_container = Self::hsl(h + SECONDARY_SHIFT, s * 0.50, lerp(0.88, 0.94, t));
            let tertiary = Self::hsl(h + TERTIARY_SHIFT, s * 0.82, lerp(0.30, 0.42, t));
            let tertiary_container = Self::hsl(h + TERTIARY_SHIFT, s * 0.50, lerp(0.88, 0.94, t));
            AccentPalette {
                primary,
                on_primary: Self::readable_on(primary),
                primary_container,
                on_primary_container: Self::readable_on(primary_container),
                secondary,
                on_secondary: Self::readable_on(secondary),
                secondary_container,
                on_secondary_container: Self::readable_on(secondary_container),
                tertiary,
                on_tertiary: Self::readable_on(tertiary),
                tertiary_container,
                on_tertiary_container: Self::readable_on(tertiary_container),
            }
        }
    }
}