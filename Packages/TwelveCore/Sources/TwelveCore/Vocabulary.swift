import Foundation

public struct VocabularyWord: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let word: String
    public let meaning: String
    public let example: String
    public let exampleMeaning: String
}

public struct VocabularyLanguage: Codable, Identifiable, Equatable, Sendable {
    public let id: String          // "es"
    public let name: String        // "Spanish"
    public let nativeName: String  // "Español"
    public let speechCode: String  // BCP-47 code for the system voice, e.g. "es-ES"
    public let words: [VocabularyWord]
}

public struct RecallQuestion: Equatable, Identifiable, Sendable {
    public let id: String
    /// The meaning shown; the person must pick the matching word.
    public let meaning: String
    public let options: [String]
    public let answer: Int
}

public enum Vocabulary {
    public static let languages: [VocabularyLanguage] = CoreResources.decode("vocabulary") ?? []
    public static let wordsToLearn = 12
    /// Correct answers needed to pass the recall exercise.
    public static let passMark = 10

    public static func language(_ id: String) -> VocabularyLanguage? { languages.first { $0.id == id } }

    /// Builds a recall quiz: for each word, show the meaning and four words to
    /// choose from. This checks recall of the new word, not recognition of the card.
    public static func quiz(words: [VocabularyWord], seed: String) -> [RecallQuestion] {
        var rng = SeededGenerator(string: "quiz|\(seed)")
        return words.shuffled(using: &rng).map { w in
            var distractors = words.filter { $0.id != w.id }.shuffled(using: &rng).prefix(3).map(\.word)
            distractors.append(w.word)
            let options = distractors.shuffled(using: &rng)
            return RecallQuestion(id: w.id, meaning: w.meaning, options: options, answer: options.firstIndex(of: w.word) ?? 0)
        }
    }

    public static func passed(correct: Int, total: Int) -> Bool {
        total >= wordsToLearn && correct >= passMark
    }
}
