import Foundation

public struct InterestCategory: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let symbol: String
    public let blurb: String
    /// Follow-up question, asked only if the category is chosen.
    public let question: String?
    public let subcategories: [Subcategory]

    public struct Subcategory: Codable, Identifiable, Equatable, Sendable {
        public let id: String
        public let name: String
    }
}

public enum Interests {
    public static let all: [InterestCategory] = [
        .init(id: "technology", name: "Technology", symbol: "cpu", blurb: "How the things we use came to be",
              question: "Which corner of technology?", subcategories: [
                .init(id: "ai", name: "AI and computing"), .init(id: "products", name: "Products and innovation"),
                .init(id: "internet", name: "Internet history"), .init(id: "general", name: "General technology")]),
        .init(id: "design", name: "Design", symbol: "pencil.and.ruler", blurb: "Why things look and work the way they do",
              question: nil, subcategories: []),
        .init(id: "books", name: "Books", symbol: "book.closed", blurb: "Stories, ideas and the people behind them",
              question: "What do you like to read?", subcategories: [
                .init(id: "fiction", name: "Fiction"), .init(id: "nonfiction", name: "Non-fiction"),
                .init(id: "both", name: "Both")]),
        .init(id: "science", name: "Science", symbol: "atom", blurb: "Everyday phenomena, explained",
              question: nil, subcategories: []),
        .init(id: "history", name: "History", symbol: "hourglass", blurb: "Surprising connections across time",
              question: nil, subcategories: []),
        .init(id: "art", name: "Art & Culture", symbol: "paintpalette", blurb: "Pictures, films, music and makers",
              question: "What draws you in?", subcategories: [
                .init(id: "visual", name: "Visual art"), .init(id: "film", name: "Film"),
                .init(id: "music", name: "Music history"), .init(id: "designhistory", name: "Design history")]),
        .init(id: "sports", name: "Sports", symbol: "figure.run", blurb: "Great moments and how games evolved",
              question: "Which sports?", subcategories: [
                .init(id: "football", name: "Football"), .init(id: "f1", name: "Formula 1"),
                .init(id: "running", name: "Running and fitness"), .init(id: "general", name: "General sports")]),
        .init(id: "nature", name: "Nature", symbol: "leaf", blurb: "The living world, up close",
              question: nil, subcategories: []),
        .init(id: "health", name: "Health & Wellbeing", symbol: "heart", blurb: "Small, sensible ideas for feeling well",
              question: nil, subcategories: []),
    ]

    public static func category(_ id: String) -> InterestCategory? { all.first { $0.id == id } }
    public static let minimumSelection = 2
    public static let maximumSelection = 4
}

/// A chosen interest with an optional refinement.
public struct InterestChoice: Codable, Equatable, Hashable, Sendable {
    public var category: String
    public var subcategory: String?
    public var weight: Double

    public init(category: String, subcategory: String? = nil, weight: Double = 1) {
        self.category = category
        self.subcategory = subcategory
        self.weight = weight
    }
}

/// "How would you like your year to feel?"
public enum YearFeeling: String, Codable, CaseIterable, Sendable {
    case curious, active, creative, balanced, surprise

    public var title: String {
        switch self {
        case .curious: return "A little more curious."
        case .active: return "A little more active."
        case .creative: return "A little more creative."
        case .balanced: return "A little more balanced."
        case .surprise: return "Surprise me."
        }
    }

    public var symbol: String {
        switch self {
        case .curious: return "sparkle.magnifyingglass"
        case .active: return "figure.walk"
        case .creative: return "paintbrush.pointed"
        case .balanced: return "circle.lefthalf.filled"
        case .surprise: return "wand.and.stars"
        }
    }

    /// Micro-challenge flavours this feeling leans toward. The twelve monthly
    /// challenges are the same for everyone and are never changed by this.
    public var favouredMoods: [String] {
        switch self {
        case .curious: return ["notice", "learn"]
        case .active: return ["move"]
        case .creative: return ["make"]
        case .balanced: return ["rest", "notice", "move"]
        case .surprise: return []
        }
    }

    public var welcomeLine: String {
        switch self {
        case .curious: return "Twelve months of things worth wondering about."
        case .active: return "Twelve months with a little more movement in them."
        case .creative: return "Twelve months of making small things."
        case .balanced: return "Twelve months, taken at a steady pace."
        case .surprise: return "Twelve months. We'll keep a few surprises back."
        }
    }
}
