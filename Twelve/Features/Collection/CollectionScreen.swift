import SwiftUI
import TwelveCore

/// Everything collected so far: stamps, saved discoveries and reflections.
struct CollectionScreen: View {
    @Environment(AppModel.self) private var app
    @State private var reading: DiscoveryCard?

    var body: some View {
        let _ = app.revision
        let stamps = app.store.stamps().filter { $0.year == AppModel.year }
        let saved = app.savedCards
        let reflections = reflectionEntries()

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Collection").font(.editorial(.largeTitle, weight: .medium)).foregroundStyle(Color.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text("Twelve little stories, one at a time.").font(.subheadline).foregroundStyle(Color.inkSoft)
                    }
                    .padding(.top, 12)

                    // Stamps
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel("Stamps · \(stamps.count) of 12")
                        if stamps.isEmpty {
                            PaperCard {
                                EmptyNote(symbol: "seal", title: "Your first stamp is waiting",
                                          message: emptyStampMessage)
                            }
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 14) {
                                ForEach(stamps, id: \.month) { stamp in
                                    let challenge = app.revealedChallenge(month: stamp.month)
                                    Button {
                                        app.sheet = .challenge(month: stamp.month)
                                    } label: {
                                        VStack(spacing: 6) {
                                            MonthStamp(month: stamp.month, state: .completed, symbol: challenge?.symbol,
                                                       accent: challenge.map { Color.token($0.accent) } ?? .gold)
                                            if app.auth.isSignedIn && stamp.verifiedAt == nil {
                                                Label("Waiting to back up", systemImage: "icloud.and.arrow.up")
                                                    .font(.caption2).foregroundStyle(Color.inkSoft)
                                            }
                                        }
                                    }
                                    .buttonStyle(LiftButtonStyle())
                                }
                            }
                        }
                    }

                    // Year in Review
                    reviewCard

                    // Saved discoveries
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel("Saved discoveries · \(saved.count)")
                        if saved.isEmpty {
                            Text("Tap Save on any Spark to keep it here.").font(.subheadline).foregroundStyle(Color.inkSoft)
                        }
                        ForEach(saved) { card in
                            Button {
                                reading = card
                            } label: {
                                PaperCard(padding: 16) {
                                    HStack(spacing: 12) {
                                        Image(systemName: Interests.category(card.category)?.symbol ?? "sparkles")
                                            .font(.title3.weight(.light)).foregroundStyle(Color.accentText).frame(width: 30)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(card.headline).font(.editorial(.headline, weight: .medium)).foregroundStyle(Color.ink)
                                                .multilineTextAlignment(.leading)
                                            Text(Interests.category(card.category)?.name ?? "").font(.caption).foregroundStyle(Color.inkSoft)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.inkSoft)
                                    }
                                }
                            }
                            .buttonStyle(LiftButtonStyle())
                        }
                    }

                    // Reflections
                    VStack(alignment: .leading, spacing: 12) {
                        SectionLabel("Your words · \(reflections.count)")
                        if reflections.isEmpty {
                            Text("Things you write during the year are gathered here, privately.")
                                .font(.subheadline).foregroundStyle(Color.inkSoft)
                        }
                        ForEach(stamps.filter { ($0.reflection ?? "").isEmpty == false }, id: \.month) { stamp in
                            PaperCard(padding: 16) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\(YearCalendar.monthName(stamp.month)) · reflection").capsLabel(.goldText)
                                    Text(stamp.reflection ?? "").font(.editorial(.body)).foregroundStyle(Color.ink)
                                }
                            }
                        }
                        ForEach(reflections.prefix(40), id: \.id) { entry in
                            EntryRow(entry: entry)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .paperScreen()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $reading) { card in
                NavigationStack {
                    SparkArticle(card: card, isToday: false)
                        .paperScreen()
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { reading = nil } } }
                }
            }
        }
    }

    private var emptyStampMessage: String {
        switch app.phase {
        case .prelaunch: return "The first challenge opens on 1 January 2027."
        case .active: return "Complete this month's challenge and it lands here."
        case .ended: return "2027 has closed. Everything you explored is still here."
        }
    }

    @ViewBuilder
    private var reviewCard: some View {
        let available = YearInReviewScreen.isAvailable(app)
        Button {
            if available { app.sheet = .yearInReview }
        } label: {
            FeatureCard {
                HStack(spacing: 16) {
                    TwelveDots(completed: Set(app.store.stamps().map(\.month)), current: app.currentMonth).frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Year in Review").font(.editorial(.title2, weight: .medium)).foregroundStyle(Color.cream)
                        Text(available ? "Look back over what you actually did." : "Opens in December, built only from what you've really done.")
                            .font(.subheadline).foregroundStyle(Color.cream.opacity(0.72)).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: available ? "arrow.right" : "lock").foregroundStyle(Color.gold)
                }
            }
        }
        .buttonStyle(LiftButtonStyle())
        .disabled(!available)
    }

    private func reflectionEntries() -> [ActivityEntry] {
        let kinds: Set<String> = ["observation", "kindness", "moment", "dish", "creative_stage"]
        return app.store.entries().filter { kinds.contains($0.kind) }.reversed()
    }
}
