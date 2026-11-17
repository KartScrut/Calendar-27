import SwiftUI
import TwelveCore

/// A recap built only from what the person actually logged. Nothing is
/// invented, and nothing is shared unless they choose it.
struct YearInReviewScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var included: Set<String> = []
    @State private var includeName = false
    @State private var shareImage: Image?

    /// Available from December, and after the year has ended.
    static func isAvailable(_ app: AppModel) -> Bool {
        switch app.phase {
        case .prelaunch: return false
        case .active(let month, _): return month == 12
        case .ended: return true
        }
    }

    struct Fact: Identifiable, Hashable {
        let id: String
        let value: String
        let label: String
    }

    /// Every figure here is counted from stored activity.
    static func facts(_ app: AppModel) -> [Fact] {
        let entries = app.store.entries()
        func count(_ kind: String) -> Int { entries.filter { $0.kind == kind }.count }
        func sum(_ kind: String) -> Double { entries.filter { $0.kind == kind }.reduce(0) { $0 + $1.amount } }
        var out: [Fact] = []
        let months = app.summary.monthsCompleted
        if months > 0 { out.append(Fact(id: "months", value: "\(months)", label: months == 1 ? "month completed" : "months completed")) }
        if app.summary.bestStreak > 1 { out.append(Fact(id: "streak", value: "\(app.summary.bestStreak)", label: "months in a row")) }
        let observations = count("observation")
        if observations > 0 { out.append(Fact(id: "observation", value: "\(observations)", label: observations == 1 ? "thing noticed" : "things noticed")) }
        let puzzles = app.store.sudokuSaves().filter { $0.solvedAt != nil }.count
        if puzzles > 0 { out.append(Fact(id: "sudoku", value: "\(puzzles)", label: puzzles == 1 ? "Sudoku solved" : "Sudokus solved")) }
        let plank = Int(sum("plank") / 60)
        if plank > 0 { out.append(Fact(id: "plank", value: "\(plank)", label: "minutes of planking")) }
        let photos = count("photo")
        if photos > 0 { out.append(Fact(id: "photo", value: "\(photos)", label: photos == 1 ? "everyday detail photographed" : "everyday details photographed")) }
        let pages = Int(sum("reading"))
        if pages > 0 { out.append(Fact(id: "reading", value: "\(pages)", label: "pages read")) }
        let words = Set(entries.filter { $0.kind == "word_learned" }.compactMap(\.ref)).count
        if words > 0 { out.append(Fact(id: "words", value: "\(words)", label: words == 1 ? "new word learned" : "new words learned")) }
        let kindness = count("kindness")
        if kindness > 0 { out.append(Fact(id: "kindness", value: "\(kindness)", label: kindness == 1 ? "act of kindness" : "acts of kindness")) }
        let dishes = count("dish")
        if dishes > 0 { out.append(Fact(id: "dish", value: "\(dishes)", label: dishes == 1 ? "new dish made" : "new dishes made")) }
        let walk = Int(sum("walk") / 60)
        if walk > 0 { out.append(Fact(id: "walk", value: "\(walk)", label: "minutes walked on purpose")) }
        let focus = entries.filter { $0.kind == "focus" && $0.amount >= 600 }.count
        if focus > 0 { out.append(Fact(id: "focus", value: "\(focus)", label: focus == 1 ? "focused session" : "focused sessions")) }
        let sparks = app.store.interactions().filter { $0.answeredAt != nil }.count
        if sparks > 0 { out.append(Fact(id: "sparks", value: "\(sparks)", label: sparks == 1 ? "discovery explored" : "discoveries explored")) }
        return out
    }

    var body: some View {
        let facts = Self.facts(app)
        let moments = app.store.entries().filter { $0.kind == "moment" }
        let chosen = facts.filter { included.contains($0.id) }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("2027").capsLabel(.accentText)
                        Text("Your year, as it happened")
                            .font(.editorial(.largeTitle, weight: .medium)).foregroundStyle(Color.ink)
                        Text("Everything below comes from what you logged. Nothing has been added or guessed.")
                            .font(.subheadline).foregroundStyle(Color.inkSoft)
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                        ForEach(1...12, id: \.self) { m in
                            let state = app.summary.state(month: m)
                            let c = state == .completed || state == .archived ? app.revealedChallenge(month: m) : nil
                            MonthStamp(month: m, state: state, symbol: c?.symbol, accent: c.map { Color.token($0.accent) } ?? .lime, showsName: false)
                        }
                    }

                    if facts.isEmpty {
                        EmptyNote(symbol: "leaf", title: "A quiet year here", message: "There's nothing logged to look back on yet.")
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(facts) { fact in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fact.value).font(.numeral(40, weight: .medium)).foregroundStyle(Color.ink)
                                    Text(fact.label).font(.footnote).foregroundStyle(Color.inkSoft)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .background(Color.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.hairline))
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }

                    if !moments.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel("Moments you kept")
                            ForEach(moments, id: \.id) { EntryRow(entry: $0) }
                        }
                    }

                    if !facts.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel("Make a card to share")
                            Text("Choose exactly what appears. Your writing and photos are never included.")
                                .font(.footnote).foregroundStyle(Color.inkSoft)
                            ForEach(facts) { fact in
                                Toggle(isOn: Binding(get: { included.contains(fact.id) }, set: { on in
                                    if on { included.insert(fact.id) } else { included.remove(fact.id) }
                                })) {
                                    Text("\(fact.value) \(fact.label)").font(.subheadline).foregroundStyle(Color.ink)
                                }
                                .tint(.pop)
                            }
                            if !app.profile.displayName.isEmpty {
                                Toggle(isOn: $includeName) {
                                    Text("Include my name").font(.subheadline).foregroundStyle(Color.ink)
                                }
                                .tint(.pop)
                            }

                            let card = ShareCard(facts: chosen, completed: Set(app.store.stamps().map(\.month)),
                                                 name: includeName ? app.profile.displayName : nil)
                            card.frame(maxWidth: .infinity)
                            if chosen.isEmpty {
                                Text("Switch on at least one line to share.").font(.footnote).foregroundStyle(Color.inkSoft)
                            } else if let image = render(card) {
                                ShareLink(item: image, preview: SharePreview("My 2027 in TWELVE", image: image)) {
                                    Label("Share card", systemImage: "square.and.arrow.up")
                                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                                }
                                .buttonStyle(.glassProminent)
                                .buttonBorderShape(.capsule)
                                .tint(.pop)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
            .paperScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
        }
    }

    @MainActor
    private func render(_ card: ShareCard) -> Image? {
        let renderer = ImageRenderer(content: card.frame(width: 360))
        renderer.scale = 3
        guard let ui = renderer.uiImage else { return nil }
        return Image(uiImage: ui)
    }
}

/// The shareable image. Contains only what was switched on.
struct ShareCard: View {
    let facts: [YearInReviewScreen.Fact]
    let completed: Set<Int>
    let name: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("2027").font(.numeral(54, weight: .medium)).foregroundStyle(Color.cloud)
                    Text(name.map { "\($0)'s year" } ?? "A year made to count")
                        .font(.system(size: 13, weight: .semibold)).tracking(1.2).textCase(.uppercase)
                        .foregroundStyle(Color.lime)
                }
                Spacer()
                TwelveDots(completed: completed, current: nil).frame(width: 64, height: 64)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(facts) { fact in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(fact.value).font(.numeral(28, weight: .medium)).foregroundStyle(Color.cloud)
                            .frame(minWidth: 44, alignment: .leading)
                        Text(fact.label).font(.system(size: 15)).foregroundStyle(Color.cloud.opacity(0.8))
                    }
                }
            }
            Text("TWELVE · Make the year count")
                .font(.system(size: 10, weight: .semibold)).tracking(1.4).textCase(.uppercase)
                .foregroundStyle(Color.cloud.opacity(0.5))
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SkyBackground(style: .vivid, clouds: 0.4))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
