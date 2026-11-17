#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

/// A postage-stamp outline: a rectangle with perforated (scalloped) edges.
public struct StampShape: Shape {
    public var notch: CGFloat
    public init(notch: CGFloat = 5) { self.notch = notch }

    public func path(in rect: CGRect) -> Path {
        let r = max(1.5, min(notch, min(rect.width, rect.height) / 10))
        var holes = Path()
        func count(_ length: CGFloat) -> Int { max(3, Int((length / (r * 3.1)).rounded())) }
        let nx = count(rect.width), ny = count(rect.height)
        for i in 0..<nx {
            let x = rect.minX + rect.width * (CGFloat(i) + 0.5) / CGFloat(nx)
            holes.addEllipse(in: CGRect(x: x - r, y: rect.minY - r, width: 2 * r, height: 2 * r))
            holes.addEllipse(in: CGRect(x: x - r, y: rect.maxY - r, width: 2 * r, height: 2 * r))
        }
        for i in 0..<ny {
            let y = rect.minY + rect.height * (CGFloat(i) + 0.5) / CGFloat(ny)
            holes.addEllipse(in: CGRect(x: rect.minX - r, y: y - r, width: 2 * r, height: 2 * r))
            holes.addEllipse(in: CGRect(x: rect.maxX - r, y: y - r, width: 2 * r, height: 2 * r))
        }
        return Path(rect).subtracting(holes)
    }
}

/// Soft organic shapes behind a month's motif, unique to each month.
struct MotifBlobs: View {
    let month: Int
    let tint: Color
    var body: some View {
        Canvas { context, size in
            var rng = SeededGenerator(seed: UInt64(month) &* 7919)
            for i in 0..<4 {
                let w = size.width * CGFloat.random(in: 0.35...0.7, using: &rng)
                let h = size.height * CGFloat.random(in: 0.3...0.6, using: &rng)
                let x = CGFloat.random(in: -0.1...0.7, using: &rng) * size.width
                let y = CGFloat.random(in: -0.1...0.7, using: &rng) * size.height
                var path = Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h))
                path = path.applying(CGAffineTransform(rotationAngle: CGFloat.random(in: -0.5...0.5, using: &rng)))
                context.fill(path, with: .color(tint.opacity(i % 2 == 0 ? 0.2 : 0.1)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A diagonal band of light, so fills look glossy.
struct Sheen: View {
    var body: some View {
        LinearGradient(stops: [.init(color: .white.opacity(0), location: 0.2),
                               .init(color: .white.opacity(0.38), location: 0.36),
                               .init(color: .white.opacity(0), location: 0.52)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The lime "done" badge pressed onto a completed month.
public struct Postmark: View {
    let size: CGFloat
    let color: Color
    public init(size: CGFloat, color: Color = .lime) {
        self.size = size
        self.color = color
    }
    public var body: some View {
        ZStack {
            Circle().fill(color)
            Circle().fill(LinearGradient(colors: [.white.opacity(0.55), .clear], startPoint: .top, endPoint: .center))
                .padding(size * 0.08)
            Circle().strokeBorder(Color.white, lineWidth: max(1.5, size * 0.09))
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.44, weight: .black, design: .rounded))
                .foregroundStyle(Color.night)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(-10))
        .shadow(color: .black.opacity(0.25), radius: size * 0.08, y: size * 0.05)
        .accessibilityHidden(true)
    }
}

/// One collectible month tile: a glossy, brightly coloured stamp. Draws
/// nothing about a challenge that has not been revealed: sealed months show
/// only their number.
public struct MonthStamp: View {
    public let month: Int
    public let state: MonthState
    /// SF Symbol for the revealed challenge. Pass nil for sealed months.
    public let symbol: String?
    /// Kept for compatibility; each month now has its own palette.
    public let accent: Color
    public var showsName: Bool

    public init(month: Int, state: MonthState, symbol: String?, accent: Color, showsName: Bool = true) {
        self.month = month
        self.state = state
        self.symbol = symbol
        self.accent = accent
        self.showsName = showsName
    }

    private var bright: Bool { state == .active || state == .completed }
    private var muted: Bool { state == .archived || state == .beforeJoining }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let palette = MonthPalette.colors(month)
            ZStack {
                StampShape(notch: w * 0.045)
                    .fill(Color.cardRaised)
                    .shadow(color: (bright ? palette.deep : Color.black).opacity(state == .completed ? 0.4 : (bright ? 0.25 : 0.1)),
                            radius: state == .completed ? 9 : 4, y: 4)

                ZStack {
                    panel(palette)
                    if bright {
                        MotifBlobs(month: month, tint: .white)
                        Sheen()
                    }
                    PaperGrain(opacity: 0.07, seed: UInt64(month))
                    if state == .sealed {
                        RoundedRectangle(cornerRadius: w * 0.05, style: .continuous)
                            .strokeBorder(Color.accentText.opacity(0.35), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                            .padding(w * 0.04)
                    }
                    VStack(spacing: h * 0.015) {
                        Image(systemName: iconName)
                            .font(.system(size: w * (bright ? 0.26 : 0.2), weight: .bold, design: .rounded))
                            .foregroundStyle(bright ? Color.white : Color.inkSoft.opacity(0.6))
                            .shadow(color: .black.opacity(bright ? 0.2 : 0), radius: 2, y: 1)
                            .frame(height: h * 0.3)
                        Text(YearCalendar.twoDigit(month))
                            .font(.system(size: w * 0.32, weight: .heavy, design: .rounded))
                            .foregroundStyle(bright ? Color.white : Color.inkSoft)
                            .shadow(color: .black.opacity(bright ? 0.18 : 0), radius: 2, y: 1)
                            .minimumScaleFactor(0.5)
                        if showsName {
                            Text(String(YearCalendar.monthName(month).prefix(3)))
                                .font(.system(size: max(7, w * 0.09), weight: .heavy, design: .rounded))
                                .textCase(.uppercase)
                                .tracking(1.1)
                                .foregroundStyle(bright ? Color.white.opacity(0.92) : Color.inkSoft.opacity(0.8))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: w * 0.06, style: .continuous))
                .padding(w * 0.08)

                if state == .completed {
                    Postmark(size: w * 0.38)
                        .position(x: w * 0.8, y: h * 0.16)
                }
            }
        }
        .aspectRatio(0.8, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var iconName: String {
        if bright { return symbol ?? "gift.fill" }
        return state == .sealed ? "lock.fill" : "minus"
    }

    @ViewBuilder
    private func panel(_ palette: (deep: Color, light: Color)) -> some View {
        if bright {
            LinearGradient(colors: [palette.light, palette.deep], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else if state == .sealed {
            LinearGradient(colors: [Color.skyPale, Color.paper], startPoint: .top, endPoint: .bottom)
        } else {
            Color.hairline.opacity(0.7)
        }
    }

    private var accessibilityText: String {
        let name = YearCalendar.monthName(month)
        switch state {
        case .sealed: return "\(name), sealed"
        case .active: return "\(name), in progress"
        case .completed: return "\(name), completed"
        case .archived: return "\(name), archived"
        case .beforeJoining: return "\(name), before you joined"
        }
    }
}

/// Twelve small marks showing the year at a glance. Used in widgets.
public struct TwelveDots: View {
    let completed: Set<Int>
    let current: Int?
    let on: Color
    let off: Color
    public init(completed: Set<Int>, current: Int?, on: Color = .lime, off: Color = Color.white.opacity(0.3)) {
        self.completed = completed
        self.current = current
        self.on = on
        self.off = off
    }
    public var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = side / 2
            let dot = side * 0.14
            ZStack {
                ForEach(1...12, id: \.self) { m in
                    let angle = Angle.degrees(Double(m - 1) * 30 - 90)
                    let done = completed.contains(m)
                    Group {
                        if done {
                            Circle().fill(on)
                        } else if current == m {
                            Circle().strokeBorder(on, lineWidth: max(1, dot * 0.2))
                        } else {
                            Circle().fill(off)
                        }
                    }
                    .frame(width: dot, height: dot)
                    .offset(x: CGFloat(cos(angle.radians)) * (radius - dot / 2),
                            y: CGFloat(sin(angle.radians)) * (radius - dot / 2))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
#endif
