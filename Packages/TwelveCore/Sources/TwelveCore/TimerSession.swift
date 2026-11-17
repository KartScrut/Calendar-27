import Foundation

/// What a timed session is for. Each kind has its own sanity limits.
public enum TimerKind: String, Codable, Sendable {
    case plank, walk, focus

    /// The longest single session we will log. Honour-based logging still
    /// deserves a ceiling so a forgotten timer cannot finish a month by itself.
    public var maximumSeconds: Double {
        switch self {
        case .plank: return 20 * 60
        case .walk: return 6 * 3600
        case .focus: return 10 * 60
        }
    }

    /// Sessions shorter than this are not worth logging.
    public var minimumSeconds: Double {
        switch self {
        case .plank: return 5
        case .walk: return 60
        case .focus: return 10 * 60
        }
    }

    public var displayName: String {
        switch self {
        case .plank: return "Plank"
        case .walk: return "Walk"
        case .focus: return "Focus"
        }
    }
}

/// A timed session rebuilt from its events. Nothing ticks: elapsed time is
/// always computed from timestamps, so it survives backgrounding, device lock
/// and the app being terminated.
public struct TimerSession: Codable, Equatable, Identifiable, Sendable {
    public enum EventType: String, Codable, Sendable { case start, pause, resume, finish }

    public struct Event: Codable, Equatable, Sendable {
        public let type: EventType
        public let at: Date
        public init(type: EventType, at: Date) { self.type = type; self.at = at }
    }

    public let id: UUID
    public let challengeID: String
    public let kind: TimerKind
    public let variant: String?
    public private(set) var events: [Event]

    public init(id: UUID = UUID(), challengeID: String, kind: TimerKind, variant: String? = nil, startedAt: Date) {
        self.id = id
        self.challengeID = challengeID
        self.kind = kind
        self.variant = variant
        self.events = [Event(type: .start, at: startedAt)]
    }

    public var startedAt: Date { events.first?.at ?? Date(timeIntervalSince1970: 0) }

    public var isFinished: Bool { events.last?.type == .finish }
    public var isPaused: Bool { events.last?.type == .pause }
    public var isRunning: Bool { !isFinished && !isPaused }

    /// Active (un-paused) seconds as of `now`, clamped to the kind's ceiling.
    /// Events that go backwards in time are ignored rather than trusted.
    public func elapsed(at now: Date) -> Double {
        var total = 0.0
        var runningSince: Date?
        var lastTime = Date(timeIntervalSince1970: 0)
        for e in events {
            let t = max(e.at, lastTime) // never let the clock run backwards
            lastTime = t
            switch e.type {
            case .start, .resume:
                if runningSince == nil { runningSince = t }
            case .pause, .finish:
                if let s = runningSince { total += t.timeIntervalSince(s); runningSince = nil }
            }
        }
        if let s = runningSince { total += max(0, max(now, lastTime).timeIntervalSince(s)) }
        return min(max(0, total), kind.maximumSeconds)
    }

    /// True when a running session has hit its ceiling and should stop itself.
    public func reachedLimit(at now: Date) -> Bool {
        !isFinished && elapsed(at: now) >= kind.maximumSeconds
    }

    /// The instant a running session will reach `seconds` of active time.
    public func projectedDate(reaching seconds: Double, from now: Date) -> Date? {
        guard isRunning else { return nil }
        return now.addingTimeInterval(seconds - elapsed(at: now))
    }

    /// A virtual start instant such that `now - anchor == elapsed`. Lets the
    /// system render a live-updating timer without the app running.
    public func displayAnchor(at now: Date) -> Date { now.addingTimeInterval(-elapsed(at: now)) }

    @discardableResult
    public mutating func pause(at now: Date) -> Bool {
        guard isRunning else { return false }
        events.append(Event(type: .pause, at: now)); return true
    }

    @discardableResult
    public mutating func resume(at now: Date) -> Bool {
        guard isPaused else { return false }
        events.append(Event(type: .resume, at: now)); return true
    }

    @discardableResult
    public mutating func finish(at now: Date) -> Bool {
        guard !isFinished else { return false }
        events.append(Event(type: .finish, at: now)); return true
    }

    /// The seconds to log when finished, or nil if the session is too short
    /// (or otherwise not valid) to count.
    public func loggableSeconds(at now: Date) -> Double? {
        let s = elapsed(at: now)
        guard s.isFinite, s >= kind.minimumSeconds, s <= kind.maximumSeconds else { return nil }
        return s.rounded(.down)
    }
}
