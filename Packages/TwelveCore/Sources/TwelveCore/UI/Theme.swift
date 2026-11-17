#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

// Design tokens shared by the app and its widgets.

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
    static let espresso = Color(hex: 0x30231E)
    static let walnut = Color(hex: 0x49372E)
    static let cream = Color(hex: 0xF5EEE3)
    static let terracotta = Color(hex: 0xCC8062)
    static let gold = Color(hex: 0xD5B47A)
    static let sage = Color(hex: 0xA2B09B)
    static let softInk = Color(hex: 0x282522)

    // Adaptive surfaces. Dark mode is its own palette — a lamp-lit study — not an inversion.
    static let paper = Color(light: 0xF5EEE3, dark: 0x1C1512)
    static let card = Color(light: 0xFCF8F1, dark: 0x2A201B)
    static let cardRaised = Color(light: 0xFFFFFF, dark: 0x35291F)
    static let ink = Color(light: 0x282522, dark: 0xF2EADD)
    static let inkSoft = Color(light: 0x6E6157, dark: 0xB8AB9B)
    static let hairline = Color(light: 0xDDD2C2, dark: 0x45372E)
    /// The dark "feature" surface: espresso by day, a lifted walnut at night.
    static let feature = Color(light: 0x30231E, dark: 0x3A2B23)
    /// Accents tuned for contrast on each background.
    static let accentText = Color(light: 0xA85A3C, dark: 0xE09A7C)
    static let goldText = Color(light: 0x8A6A2C, dark: 0xD5B47A)
    static let sageText = Color(light: 0x5C6E55, dark: 0xB4C2AD)

    /// Resolves a design-token name used in the challenge catalog.
    static func token(_ name: String) -> Color {
        switch name {
        case "terracotta": return .terracotta
        case "gold": return .gold
        case "sage": return .sage
        case "walnut": return .walnut
        default: return .terracotta
        }
    }
}

public extension Font {
    /// The editorial serif (New York) at a text style, so it scales with Dynamic Type.
    static func editorial(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif).weight(weight)
    }

    /// Large display numerals and statements.
    static func numeral(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Small tracked capitals for labels.
    static let label: Font = .system(.caption, design: .default).weight(.semibold)
}

public extension View {
    /// Small-caps style label: tracked, uppercase, quiet.
    func capsLabel(_ color: Color = .inkSoft) -> some View {
        self.font(.label).textCase(.uppercase).tracking(1.4).foregroundStyle(color)
    }
}

/// A faint, static paper grain. Drawn once into a Canvas; no animation.
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
            let count = Int(min(900, (size.width * size.height) / 260))
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

/// The paper background used behind most screens.
public struct PaperBackground: View {
    public init() {}
    public var body: some View {
        Color.paper.overlay(PaperGrain(opacity: 0.045)).ignoresSafeArea()
    }
}
#endif
