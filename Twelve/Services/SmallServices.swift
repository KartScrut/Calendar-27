import AVFoundation
import Foundation
import HealthKit
import UIKit

/// Haptic feedback for meaningful moments. Respects the system setting.
@MainActor
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func thud() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

/// Photos stay on this iPhone, inside the app's own storage, excluded from
/// nothing and uploaded nowhere.
enum PhotoStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Photos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                     attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        return dir
    }

    /// Saves a downsized JPEG and returns its file name.
    static func save(_ image: UIImage) -> String? {
        let maxSide: CGFloat = 1600
        let scale = min(1, maxSide / max(image.size.width, image.size.height, 1))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = resized.jpegData(compressionQuality: 0.82) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do {
            try data.write(to: directory.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return name
        } catch {
            return nil
        }
    }

    static func url(_ name: String) -> URL { directory.appendingPathComponent(name) }

    static func image(_ name: String?) -> UIImage? {
        guard let name else { return nil }
        return UIImage(contentsOfFile: url(name).path)
    }

    static func delete(_ name: String) {
        try? FileManager.default.removeItem(at: url(name))
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Speaks vocabulary using the system's own voices for each language.
@MainActor
final class Speaker {
    static let shared = Speaker()
    private let synthesizer = AVSpeechSynthesizer()

    /// True when the system has a voice for this language installed.
    func canSpeak(_ languageCode: String) -> Bool {
        AVSpeechSynthesisVoice(language: languageCode) != nil
    }

    func speak(_ text: String, languageCode: String) {
        guard let voice = AVSpeechSynthesisVoice(language: languageCode) else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.85
        synthesizer.speak(utterance)
    }
}

/// Optional, read-only access to walking workouts. Never requested unless the
/// person switches it on, and never used for anything but the walking month.
@MainActor
final class HealthService {
    static let shared = HealthService()
    private let store = HKHealthStore()

    struct Walk: Identifiable {
        let id: UUID
        let start: Date
        let end: Date
        var seconds: Double { end.timeIntervalSince(start) }
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAccess() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: [HKObjectType.workoutType()])
            return true
        } catch {
            return false
        }
    }

    /// Walking workouts recorded between two instants (for example by a watch).
    func walks(from start: Date, to end: Date) async -> [Walk] {
        guard isAvailable else { return [] }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                HKQuery.predicateForWorkouts(with: .walking),
                HKQuery.predicateForWorkouts(with: .hiking),
            ]),
        ])
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate,
                                      limit: 200, sortDescriptors: nil) { _, samples, _ in
                let walks = (samples as? [HKWorkout] ?? []).map { Walk(id: $0.uuid, start: $0.startDate, end: $0.endDate) }
                continuation.resume(returning: walks)
            }
            store.execute(query)
        }
    }
}
