import SwiftUI
import TwelveCore

/// Today's Spark, presented like a page from a small magazine.
struct SparkScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let card = app.spark {
                    SparkArticle(card: card, isToday: true)
                } else {
                    EmptyNote(symbol: "sparkles", title: "No Spark right now", message: "A new discovery arrives each day of 2027.")
                }
            }
            .paperScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
        }
    }
}

/// A full discovery card: headline, body, source, one optional interaction,
/// Save, and Not interested.
struct SparkArticle: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let card: DiscoveryCard
    /// Saved cards can be re-read, but only today's card earns points.
    let isToday: Bool

    @State private var chosen: Int?
    @State private var confirmDismiss = false

    var body: some View {
        let _ = app.revision
        let record = app.store.interaction(cardID: card.id)
        let answered = record?.answeredAt != nil
        let saved = record?.saved ?? false
        let category = Interests.category(card.category)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    if let category { Tag(text: category.name, systemImage: category.symbol, tint: .mintText) }
                    Spacer()
                    Text(isToday ? "Today's Spark" : "Saved").capsLabel(.accentText)
                }

                // A small procedural illustration: unique to each card, never a stock photo.
                SparkIllustration(seed: card.id, symbol: category?.symbol ?? "sparkles")
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

                Text(card.headline)
                    .font(.editorial(.largeTitle, weight: .medium))
                    .foregroundStyle(Color.ink)
                    .accessibilityAddTraits(.isHeader)

                Text(card.body)
                    .font(.editorial(.body))
                    .foregroundStyle(Color.ink)
                    .lineSpacing(6)

                if let url = URL(string: card.sourceURL) {
                    Link(destination: url) {
                        HStack(spacing: 6) {
                            Image(systemName: "book.pages")
                            Text("Source: \(card.sourceTitle)").multilineTextAlignment(.leading)
                            Image(systemName: "arrow.up.right").font(.caption2)
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Color.accentText)
                    }
                    .accessibilityHint("Opens the source in your browser")
                }

                Divider().overlay(Color.hairline)

                if let quiz = card.quiz {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel("One question")
                        Text(quiz.question).font(.editorial(.title3, weight: .medium)).foregroundStyle(Color.ink)
                        ForEach(Array(quiz.options.enumerated()), id: \.offset) { i, option in
                            let reveal = chosen != nil || answered
                            let isRight = i == quiz.answer
                            Button {
                                guard chosen == nil, !answered else { return }
                                chosen = i
                                let right = app.answer(card, option: i)
                                if right { Haptics.success() } else { Haptics.warning() }
                            } label: {
                                HStack {
                                    Text(option).font(.body.weight(.medium)).multilineTextAlignment(.leading)
                                    Spacer()
                                    if reveal && isRight { Image(systemName: "checkmark.circle.fill").accessibilityLabel("Correct answer") }
                                    if chosen == i && !isRight { Image(systemName: "xmark.circle").accessibilityLabel("Your answer") }
                                }
                                .foregroundStyle(Color.ink)
                                .padding(16)
                                .background(reveal && isRight ? Color.mint.opacity(0.4) : (chosen == i ? Color.pop.opacity(0.2) : Color.card),
                                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.hairline))
                            }
                            .buttonStyle(LiftButtonStyle())
                            .disabled(reveal)
                        }
                        if answered {
                            Label(chosen == nil ? "You've answered this one." : (chosen == quiz.answer ? "That's right." : "Not quite — the answer is marked above."),
                                  systemImage: "sparkle")
                                .font(.footnote.weight(.semibold)).foregroundStyle(Color.mintText)
                        }
                    }
                } else if let prompt = card.prompt {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel("Try this")
                        Text(prompt).font(.editorial(.title3, weight: .medium)).foregroundStyle(Color.ink)
                        if answered {
                            Label("Done", systemImage: "checkmark.circle.fill").font(.footnote.weight(.semibold)).foregroundStyle(Color.mintText)
                        } else {
                            SecondaryButton(title: "I tried it", systemImage: "checkmark") {
                                app.acknowledge(card)
                                Haptics.success()
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        app.toggleSaved(card)
                        Haptics.tap()
                    } label: {
                        Label(saved ? "Saved" : "Save", systemImage: saved ? "bookmark.fill" : "bookmark")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.glass)
                    if isToday {
                        Button {
                            confirmDismiss = true
                        } label: {
                            Label("Not interested", systemImage: "hand.thumbsdown")
                                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 36)
                        }
                        .buttonStyle(.glass)
                    }
                }
                .padding(.top, 4)

                Text("Reading is its own reward. Answering earns \(Points.sparkInteraction) discovery points, once.")
                    .font(.caption).foregroundStyle(Color.inkSoft)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 36)
        }
        .onAppear {
            // Opening a card marks it as seen, so it isn't chosen again.
            _ = app.interaction(for: card)
        }
        .confirmationDialog("Hide this Spark?", isPresented: $confirmDismiss, titleVisibility: .visible) {
            Button("Show me something else") {
                app.dismiss(card)
                chosen = nil
                if app.spark == nil { dismiss() }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("You won't see this one again, and we'll pick another for today.")
        }
    }
}

/// Sky-and-balloon artwork generated from the card's id: a big balloon with
/// the category's symbol and two smaller ones, in colours chosen by the id.
struct SparkIllustration: View {
    let seed: String
    let symbol: String

    var body: some View {
        var rng = SeededGenerator(string: seed)
        let months = (0..<3).map { _ in Int.random(in: 1...12, using: &rng) }
        let tilt = Double.random(in: -12...12, using: &rng)
        return ZStack {
            SkyBackground(style: .vivid)
            GeometryReader { geo in
                FoilBalloon(symbol: symbol, month: months[0], size: min(geo.size.height * 0.72, 120))
                    .rotationEffect(.degrees(tilt))
                    .position(x: geo.size.width * 0.5, y: geo.size.height * 0.52)
                FoilBalloon(symbol: "sparkles", month: months[1], size: 42)
                    .rotationEffect(.degrees(-14))
                    .position(x: geo.size.width * 0.16, y: geo.size.height * 0.3)
                FoilBalloon(symbol: "star.fill", month: months[2], size: 36)
                    .rotationEffect(.degrees(12))
                    .position(x: geo.size.width * 0.85, y: geo.size.height * 0.68)
            }
        }
        .environment(\.colorScheme, .light)
        .accessibilityHidden(true)
    }
}
