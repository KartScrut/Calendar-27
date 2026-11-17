#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

/// A sky: gradient, soft clouds and a little grain.
/// `.vivid` is the saturated blue used for big moments (welcome, celebrations,
/// featured cards, widgets). `.soft` is the pale sky behind ordinary screens.
public struct SkyBackground: View {
    public enum Style { case vivid, soft }
    let style: Style
    /// Multiplies cloud strength. Lower it where text sits on top.
    let clouds: Double
    @Environment(\.colorScheme) private var scheme

    public init(style: Style = .vivid, clouds: Double = 1) {
        self.style = style
        self.clouds = clouds
    }

    public var body: some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
            Clouds(opacity: cloudOpacity * clouds, seed: style == .vivid ? 7 : 3,
                   band: style == .vivid ? 0...1 : 0...0.4)
            PaperGrain(opacity: style == .vivid ? 0.09 : 0.04, seed: 11)
        }
        .accessibilityHidden(true)
    }

    private var colors: [Color] {
        switch (style, scheme) {
        case (.vivid, .dark): return [Color(hex: 0x0E2A6B), Color(hex: 0x1D49B8), Color(hex: 0x3670DD)]
        // Stays saturated to the bottom so white text reads everywhere.
        case (.vivid, _): return [Color(hex: 0x0B4FE6), Color(hex: 0x2A74FF), Color(hex: 0x4F94FF)]
        case (.soft, .dark): return [Color(hex: 0x10275A), Color(hex: 0x0A1730)]
        default: return [Color(hex: 0xBBDBFF), Color(hex: 0xE2EFFF), Color(hex: 0xF4F9FF)]
        }
    }

    private var cloudOpacity: Double {
        switch (style, scheme) {
        case (.vivid, .dark): return 0.22
        case (.vivid, _): return 0.6
        case (.soft, .dark): return 0.07
        default: return 0.8
        }
    }
}

/// Soft, blurred cumulus clouds, drawn once. Deterministic for a given seed.
public struct Clouds: View {
    let opacity: Double
    let seed: UInt64
    let band: ClosedRange<CGFloat>

    public init(opacity: Double = 0.8, seed: UInt64 = 1, band: ClosedRange<CGFloat> = 0...1) {
        self.opacity = opacity
        self.seed = seed
        self.band = band
    }

    public var body: some View {
        Canvas { context, size in
            var rng = SeededGenerator(seed: seed)
            context.addFilter(.blur(radius: max(6, size.width * 0.025)))
            let count = 5
            for i in 0..<count {
                let along = (CGFloat(i) + CGFloat.random(in: 0.1...0.9, using: &rng)) / CGFloat(count)
                let cy = (band.lowerBound + (band.upperBound - band.lowerBound) * along) * size.height
                let cx = CGFloat.random(in: -0.15...1.15, using: &rng) * size.width
                let w = size.width * CGFloat.random(in: 0.35...0.6, using: &rng)
                for _ in 0..<6 {
                    let dx = CGFloat.random(in: -0.45...0.45, using: &rng) * w
                    let dy = CGFloat.random(in: -0.12...0.06, using: &rng) * w
                    let r = CGFloat.random(in: 0.25...0.5, using: &rng) * w
                    let rect = CGRect(x: cx + dx - r / 2, y: cy + dy - r * 0.35, width: r, height: r * 0.7)
                    context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(opacity)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A glossy foil balloon with an embossed symbol.
public struct FoilBalloon: View {
    let symbol: String
    let deep: Color
    let light: Color
    let size: CGFloat

    public init(symbol: String, month: Int, size: CGFloat) {
        let pair = MonthPalette.colors(month)
        self.symbol = symbol
        self.deep = pair.deep
        self.light = pair.light
        self.size = size
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [light, deep, deep.opacity(0.92)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.75))
            // Crinkled foil seams.
            Circle().inset(by: size * 0.13).stroke(Color.white.opacity(0.22), lineWidth: max(1, size * 0.015))
            Circle()
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.1), .white.opacity(0.5)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: max(1.5, size * 0.05))
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: size * 0.03, y: size * 0.02)
            // Specular highlight.
            Ellipse()
                .fill(Color.white.opacity(0.8))
                .frame(width: size * 0.3, height: size * 0.13)
                .rotationEffect(.degrees(-35))
                .offset(x: -size * 0.2, y: -size * 0.27)
                .blur(radius: size * 0.02)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.22), radius: size * 0.08, y: size * 0.06)
        .accessibilityHidden(true)
    }
}

/// Each month's own bright colour pair. Purely decorative: it reveals
/// nothing about a sealed month's challenge.
public enum MonthPalette {
    private static let pairs: [(UInt32, UInt32)] = [
        (0x3D6BFF, 0x8FD3FF), // January — ice blue
        (0xFF3D8B, 0xFFB0D0), // February — bubblegum
        (0xFF6A1F, 0xFFC15E), // March — tangerine
        (0x14B8A6, 0x99F0DE), // April — lagoon
        (0x8B5CF6, 0xD2C4FF), // May — violet
        (0xF5A300, 0xFFE48A), // June — sunshine
        (0xFF3B5C, 0xFF9EAE), // July — watermelon
        (0x22B455, 0xC8F23C), // August — lime
        (0x2563EB, 0x7DD3FC), // September — sky
        (0xEA580C, 0xFDBA74), // October — pumpkin
        (0x5B4BF0, 0xA5B4FC), // November — indigo
        (0xE11D48, 0xFDA4AF), // December — cranberry
    ]

    public static func colors(_ month: Int) -> (deep: Color, light: Color) {
        let pair = pairs[(max(1, min(12, month)) - 1)]
        return (Color(hex: pair.0), Color(hex: pair.1))
    }
}
#endif
