import SwiftUI
import TwelveCore

/// Glossy balloons drifting around the edges of a big moment (welcome,
/// celebration). They use generic symbols only, so nothing about a sealed
/// challenge is hinted at. They hold still when Reduce Motion is on.
struct FloatingBalloons: View {
    private struct Item {
        let symbol: String
        let month: Int
        let size: CGFloat
        let x: CGFloat
        let y: CGFloat
        let tilt: Double
    }

    private let items: [Item] = [
        Item(symbol: "star.fill", month: 6, size: 78, x: 0.13, y: 0.09, tilt: -12),
        Item(symbol: "heart.fill", month: 2, size: 64, x: 0.87, y: 0.13, tilt: 14),
        Item(symbol: "sparkles", month: 5, size: 56, x: 0.92, y: 0.42, tilt: -8),
        Item(symbol: "music.note", month: 4, size: 52, x: 0.07, y: 0.44, tilt: 10),
        Item(symbol: "trophy.fill", month: 3, size: 60, x: 0.86, y: 0.6, tilt: 12),
        Item(symbol: "leaf.fill", month: 8, size: 48, x: 0.1, y: 0.62, tilt: -14),
    ]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bob = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(items.indices, id: \.self) { i in
                    let item = items[i]
                    FoilBalloon(symbol: item.symbol, month: item.month, size: item.size)
                        .rotationEffect(.degrees(item.tilt))
                        .offset(y: bob ? -7 : 7)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 2.2 + Double(i) * 0.35).repeatForever(autoreverses: true),
                                   value: bob)
                        .position(x: item.x * geo.size.width, y: item.y * geo.size.height)
                }
            }
        }
        .onAppear { if !reduceMotion { bob = true } }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
