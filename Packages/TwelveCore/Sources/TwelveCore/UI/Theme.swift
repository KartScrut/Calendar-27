#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

// Design tokens shared by the app and its widgets.
// The look: a bright sky with clouds and film grain, white cards, glossy
// foil-balloon accents, and pops of lime, hot pink and electric blue.

public extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// A colour that adapts to the light and dark appearances.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }

    // Fixed brand colours.
    /// Deepest navy, for text on bright fills.
    static let night = Color(hex: 0x0B1B3A)
    /// Electric blue.
    static let ocean = Color(hex: 0x1F5BFF)
    /// Mid sky blue.
    static let sky = Color(hex: 0x4DA3FF)
    /// Pure white: text and shapes on the sky.
    static let cloud = Color(hex: 0xFFFFFF)
    /// Hot pink: the primary accent (rings, toggles, highlights).
    static let pop = Color(hex: 0xFF4D7E)
    /// Lime: achievement, completion, the main button.
    static let lime = Color(hex: 0xC8F23C)
    /// Fresh green: calm confirmation.
    static let mint = Color(hex: 0x2BD47D)
    /// Purple sparkle.
    static let grape = Color(hex: 0x9B5CFF)
    /// Sunshine yellow.
    static let sunny = Color(hex: 0xFFC83D)
    static let softInk = Color(hex: 0x0E1B2E)

    // Adaptive surfaces. Dark mode is a night sky, not an inversion.
    static let paper = Color(light: 0xEAF4FF, dark: 0x0A1730)
    static let card = Color(light: 0xFFFFFF, dark: 0x13254A)
    static let cardRaised = Color(light: 0xFFFFFF, dark: 0x1A3060)
    static let ink = Color(light: 0x0E1B2E, dark: 0xF4F8FF)
    static let inkSoft = Color(light: 0x5B6B82, dark: 0xA9B8D0)
    static let hairline = Color(light: 0xD8E6F7, dark: 0x24406E)
    static let skyPale = Color(light: 0xD3E7FF, dark: 0x183262)
    /// Selected and featured fills.
    static let feature = Color(light: 0x2F6BFF, dark: 0x2A5BE0)
    /// Accent-coloured text with enough contrast on light and dark surfaces.
    static let accentText = Color(light: 0x1F56E8, dark: 0x8DB6FF)
    static let limeText = Color(light: 0x3F7A08, dark: 0xD4F75A)
    static let mintText = Color(light: 0x0F7A43, dark: 0x6EE7A0)
    static let popText = Color(light: 0xD92B5C, dark: 0xFF8FB0)

    /// Resolves a design-token name used in the challenge catalog.
    static func token(_ name: String) -> Color {
        switch name {
        case "terracotta", "pop": return .pop
        case "gold", "lime": return .lime
        case "sage", "mint": return .mint
        case "walnut", "ocean": return .ocean
        default: return .pop
        }
    }
}

public extension Font {
    /// Display type: SF Rounded, a little heavier than asked for, so headings
    /// feel bold and friendly. Scales with Dynamic Type.
    static func editorial(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .rounded).weight(punchy(weight))
    }

    /// Large display numerals.
    static func numeral(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: punchy(weight), design: .rounded)
    }

    /// Small tracked capitals for labels.
    static let label: Font = .system(.caption, design: .rounded).weight(.bold)

    private static func punchy(_ weight: Font.Weight) -> Font.Weight {
        if weight == .regular || weight == .light || weight == .thin || weight == .ultraLight { return .medium }
        if weight == .medium { return .bold }
        if weight == .semibold { return .heavy }
        return weight
    }
}

public extension View {
    /// Small-caps style label: tracked, uppercase.
    func capsLabel(_ color: Color = .inkSoft) -> some View {
        self.font(.label).textCase(.uppercase).tracking(1.2).foregroundStyle(color)
    }
}

/// A faint, static film grain. Drawn once into a Canvas; no animation.
public struct PaperGrain: View {
    let opacity: Double
    let seed: UInt64
    public init(opacity: Double = 0.05, seed: UInt64 = 27) {
        self.opacity = opacity
        self.seed = seed
    }
    public var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            var rng = SeededGenerator(seed: seed)
            let count = Int(min(1400, (size.width * size.height) / 180))
            for _ in 0..<max(count, 0) {
                let x = CGFloat.random(in: 0...max(size.width, 1), using: &rng)
                let y = CGFloat.random(in: 0...max(size.height, 1), using: &rng)
                let r = CGFloat.random(in: 0.3...1.1, using: &rng)
                let dark = Bool.random(using: &rng)
                context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)),
                             with: .color((dark ? Color.black : Color.white).opacity(opacity * Double.random(in: 0.4...1, using: &rng))))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The background behind most screens: a soft, light sky.
public struct PaperBackground: View {
    public init() {}
    public var body: some View {
        SkyBackground(style: .soft).ignoresSafeArea()
    }
}
#endif
