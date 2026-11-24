import SwiftUI
import UIKit

/// Ember's visual language: warm cream surfaces, an ember-orange accent, rounded type.
enum Theme {
    static let ember = Color(light: 0xE2541B, dark: 0xFF6A2B)
    static let emberDeep = Color(light: 0xB83A0E, dark: 0xE2541B)
    static let amber = Color(light: 0xF6A33B, dark: 0xFFB454)
    static let glow = Color(light: 0xFFE3CC, dark: 0x4A2615)

    static let background = Color(light: 0xFBF6EF, dark: 0x14100D)
    static let surface = Color(light: 0xFFFFFF, dark: 0x221B16)
    static let surfaceMuted = Color(light: 0xF4EADF, dark: 0x2C231D)
    static let ink = Color(light: 0x2B1D14, dark: 0xF6EEE6)
    static let inkSoft = Color(light: 0x7A6656, dark: 0xB7A595)
    static let line = Color(light: 0xEADCCD, dark: 0x3A2F27)

    static let good = Color(light: 0x2E9E6A, dark: 0x4CC58C)
    static let warn = Color(light: 0xD98A0B, dark: 0xF2B544)
    static let calm = Color(light: 0x3C7BD9, dark: 0x6CA2F0)

    static let emberGradient = LinearGradient(colors: [amber, ember, emberDeep],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)
    static let warmGlow = RadialGradient(colors: [glow.opacity(0.9), background.opacity(0)],
                                         center: .topTrailing, startRadius: 10, endRadius: 420)

    static let radius: CGFloat = 22
    static let radiusSmall: CGFloat = 14

    static func color(for category: MovementCategory) -> Color {
        switch category {
        case .push: return Color(light: 0xE2541B, dark: 0xFF6A2B)
        case .squat: return Color(light: 0xD9820B, dark: 0xF2A23B)
        case .hinge: return Color(light: 0xB8456B, dark: 0xE06A92)
        case .core: return Color(light: 0x5B6CD9, dark: 0x8A98F0)
        case .mobility: return Color(light: 0x2E9E8A, dark: 0x4CC5B0)
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }

    /// A colour that adapts to light / dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}

extension Font {
    static func ember(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
