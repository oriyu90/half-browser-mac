import SwiftUI

/// macOS native design tokens following HIG.
enum MacTheme {
    // Spacing (8pt grid)
    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing24: CGFloat = 24

    // Corner radii (continuous squircle)
    static let radiusSmall: CGFloat = 5
    static let radiusMedium: CGFloat = 8
    static let radiusLarge: CGFloat = 10

    // Body text on macOS desktop
    static let bodyFontSize: CGFloat = 13

    // Vibrancy materials
    static let sidebarMaterial: Material = .regularMaterial
    static let toolbarMaterial: Material = .bar
}

extension Color {
    /// Semantic colors that adapt to light/dark mode.
    static let hbBackground = Color(nsColor: .windowBackgroundColor)
    static let hbSecondaryBackground = Color(nsColor: .controlBackgroundColor)
    static let hbText = Color(nsColor: .labelColor)
    static let hbSecondaryText = Color(nsColor: .secondaryLabelColor)
    static let hbAccent = Color.accentColor
}