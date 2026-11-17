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
                context.fill(path, with: .color(tint.opacity(i % 2 == 0 ? 0.22 : 0.12)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A round postmark with a checkmark: the mark of a completed month.
public struct Postmark: View {
    let size: CGFloat
    let color: Color
    public init(size: CGFloat, color: Color = .espresso) {
        self.size = size
        self.color = color
    }
    public var body: some View {
        ZStack {
            Circle().strokeBorder(color, lineWidth: max(1, size * 0.06))
            Circle().strokeBorder(color.opacity(0.7), style: StrokeStyle(lineWidth: max(0.5, size * 0.025), dash: [size * 0.05, size * 0.05]))
                .padding(size * 0.11)
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(-14))
        .accessibilityHidden(true)
    }
}

/// One collectible month tile. Draws nothing about a challenge that has not
/// been revealed: sealed months show only their number.
public struct MonthStamp: View {
    public let month: Int
    public let state: MonthState
    /// SF Symbol for the revealed challenge. Pass nil for sealed months.
    public let symbol: String?
    public let accent: Color
    public var showsName: Bool

    public init(month: Int, state: MonthState, symbol: String?, accent: Color, showsName: Bool = true) {
        self.month = month
        self.state = state
        self.symbol = symbol
        self.accent = accent
        self.showsName = showsName
    }

    private var revealed: Bool { state == .active || state == .completed || state == .archived }
    private var muted: Bool { state == .archived || state == .beforeJoining }

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let inset = w * 0.09
            ZStack {
                StampShape(notch: w * 0.045)
                    .fill(state == .sealed ? Color.card : Color.cardRaised)
                    .shadow(color: .black.opacity(state == .completed ? 0.16 : 0.07), radius: state == .completed ? 5 : 2, y: 2)

                // Inner panel
                ZStack {
                    Rectangle().fill(panelColor)
                    if revealed && !muted { MotifBlobs(month: month, tint: .cream) }
                    PaperGrain(opacity: 0.06, seed: UInt64(month))
                    if state == .sealed {
                        Rectangle().strokeBorder(Color.inkSoft.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3])).padding(w * 0.04)
                    }
                    VStack(spacing: h * 0.02) {
                        if let symbol, revealed {
                            Image(systemName: symbol)
                                .font(.system(size: w * 0.26, weight: .light))
                                .foregroundStyle(muted ? Color.inkSoft.opacity(0.7) : Color.cream)
                                .frame(height: h * 0.3)
                        } else {
                            Image(systemName: state == .sealed ? "seal" : "minus")
                                .font(.system(size: w * 0.2, weight: .light))
                                .foregroundStyle(Color.inkSoft.opacity(0.55))
                                .frame(height: h * 0.3)
                        }
                        Text(YearCalendar.twoDigit(month))
                            .font(.numeral(w * 0.3, weight: .medium))
                            .foregroundStyle(numeralColor)
                            .minimumScaleFactor(0.5)
                        if showsName {
                            Text(String(YearCalendar.monthName(month).prefix(3)))
                                .font(.system(size: max(7, w * 0.085), weight: .semibold))
                                .textCase(.uppercase)
                                .tracking(1.2)
                                .foregroundStyle(numeralColor.opacity(0.8))
                        }
                    }
                }
                .padding(inset)

                if state == .completed {
                    Postmark(size: w * 0.42, color: .espresso)
                        .background(Circle().fill(Color.cream.opacity(0.85)).padding(w * 0.02))
                        .position(x: w * 0.74, y: h * 0.24)
                }
            }
        }
        .aspectRatio(0.8, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var panelColor: Color {
        switch state {
        case .sealed: return Color.paper
        case .active: return accent
        case .completed: return accent
        case .archived, .beforeJoining: return Color.hairline.opacity(0.6)
        }
    }

    private var numeralColor: Color {
        switch state {
        case .active, .completed: return .espresso
        default: return .inkSoft
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
    public init(completed: Set<Int>, current: Int?, on: Color = .gold, off: Color = Color.cream.opacity(0.22)) {
        self.completed = completed
        self.current = current
        self.on = on
        self.off = off
    }
    public var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = side / 2
            let dot = side * 0.13
            ZStack {
                ForEach(1...12, id: \.self) { m in
                    let angle = Angle.degrees(Double(m - 1) * 30 - 90)
                    let done = completed.contains(m)
                    Group {
                        if done {
                            Circle().fill(on)
                        } else if current == m {
                            Circle().strokeBorder(on, lineWidth: max(1, dot * 0.18))
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
