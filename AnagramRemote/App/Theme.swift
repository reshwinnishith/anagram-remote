import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// Design tokens for the Performance UI. Spacing follows an 8 pt grid.
enum Theme {
    static let background = Color(hex: 0x0B0D10)
    static let surface = Color(hex: 0x14181D)
    static let surfaceRaised = Color(hex: 0x1C222A)
    static let border = Color(hex: 0x2A323C)
    static let textPrimary = Color(hex: 0xE8ECF1)
    static let textSecondary = Color(hex: 0x9AA4B1)
    static let connected = Color(hex: 0x2ECC71)
    static let warning = Color(hex: 0xF5A623)
    static let error = Color(hex: 0xFF5A5F)
    static let sceneAccent = Color(hex: 0xFFB020)

    /// Reserved for future per-stomp configuration; unused in Batch A.
    static let stompAccents: [Color] = [0x3DA9FC, 0x7C5CFF, 0xFF5CA8, 0xFF7A45,
                                        0xFFD23F, 0x4ADE80, 0x2DD4BF, 0xC0C7D0].map(Color.init(hex:))

    enum Spacing {
        static let unit: CGFloat = 8
        static let margin: CGFloat = 24
        static let gutter: CGFloat = 16
    }
    static let cardRadius: CGFloat = 16
    /// Minimum size of any live touch target.
    static let minTouch: CGFloat = 60
}

extension View {
    /// Standard card chrome. `dashed` marks placeholder / not-yet-available controls.
    func themedCard(raised: Bool = false, dashed: Bool = false) -> some View {
        background(raised ? Theme.surfaceRaised : Theme.surface,
                   in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.border, style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [6, 5] : [])))
    }
}
