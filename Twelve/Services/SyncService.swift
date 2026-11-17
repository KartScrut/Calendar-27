import Foundation
import Observation
import TwelveCore

/// Copies on-device data to the server and back when signed in.
///
/// Design rules
///   * The device is always usable on its own; sync is best-effort and resumable.
///   * Every row has a stable client-generated id, so re-sending is harmless.
///   * Nothing is deleted locally because of a network failure.
///   * Rewards are decided by the server: it recomputes progress from the
///     uploaded activity before it records an achievement.
@MainActor
@Observable
final class SyncService {
    enum Status: Equatable {
        case idle
        case syncing
        case offline
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var lastSyncedAt: Date?
    /// Rows the server refused (kept on device, shown in Profile).
    private(set) var rejectedCount = 0

    weak var app: AppModel?
    private var scheduled: Task<Void, Never>?
    private var isRunning = false
    private var needsAnotherPass = false

    private var defaults: UserDefaults { .standard }

    /// Sync soon, coalescing bursts of changes into one pass.
    func schedule() {
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    func syncNow() async {
        guard let app, let client = app.auth.client, let userID = app.auth.userID,
              !app.isDemo, !app.isInMemory, app.profile.ownerUserID == userID else { return }
        if isRunning { needsAnotherPass = true; return }
        isRunning = true
        status = .syncing
        defer { isRunning = false }
        do {
            repeat {
                needsAnotherPass = false
                try await pushProfile(app, client, userID)
                try await pushActivity(app, client)
                try await pushSudoku(app, client)
                try await pushInteractions(app, client)
                try await pull(app, client, userID)
                try await claim(app, client)
                try await pullEditorial(app, client)
            } while needsAnotherPass
            lastSyncedAt = Date()
            status = .idle
            app.refresh()
        } catch BackendError.offline {
            status = .offline
        } catch BackendError.sessionExpired, BackendError.notSignedIn {
            app.auth.markExpired()
            status = .idle
        } catch {
            status = .failed((error as? LocalizedError)?.errorDescription ?? "Sync didn't finish. It will try again.")
        }
    }

    // MARK: Push

    private func pushProfile(_ app: AppModel, _ client: SupabaseClient, _ userID: String) async throws {
        let p = app.profile
        guard p.needsSync else { return }
        let reminders = p.reminders
        let preferences: [String: Any] = ["vocabulary_language": p.vocabularyLanguage ?? NSNull(),
                                          "accessible_variant": p.useAccessibleVariant]
        try await client.update("profiles", match: [URLQueryItem(name: "id", value: "eq.\(userID)")], values: [
            "display_name": String(p.displayName.prefix(60)),
            "calendar_time_zone": p.timeZoneID,
            "onboarding_complete": p.onboardingComplete,
            "feeling": p.feelingRaw ?? NSNull(),
            "preferences": preferences,
        ])
        let interests = p.interests
        try await client.upsert("user_interests", rows: interests.map {
            ["category": $0.category, "subcategory": $0.subcategory ?? NSNull(), "weight": $0.weight]
        }, onConflict: "user_id,category")
        let keep = interests.map(\.category).joined(separator: ",")
        try await client.delete("user_interests", match: [
            URLQueryItem(name: "user_id", value: "eq.\(userID)"),
            URLQueryItem(name: "category", value: "not.in.(\(keep))"),
        ])
        let time = String(format: "%02d:%02d:00", reminders.dailyMinutes / 60, reminders.dailyMinutes % 60)
        try await client.upsert("notification_preferences", rows: [
            ["category": "daily_spark", "enabled": reminders.dailySpark, "preferred_local_time": time],
            ["category": "monthly_reveal", "enabled": reminders.monthlyReveal, "preferred_local_time": "09:00:00"],
            ["category": "progress", "enabled": reminders.progress, "preferred_local_time": "18:00:00"],
        ], onConflict: "user_id,category")
        p.needsSync = false
        app.store.save()
    }

    private func sessionRow(_ e: ActivityEntry) -> [String: Any] {
        let events = e.eventsData.flatMap { try? JSONSerialization.jsonObject(with: $0) } ?? [Any]()
        return ["id": e.id.uuidString.lowercased(), "challenge_id": e.challengeID, "kind": e.kind,
                "started_at": ServerDate.string(e.startedAt ?? e.date.addingTimeInterval(-e.amount)),
                "ended_at": ServerDate.string(e.date), "elapsed_seconds": e.amount, "events": events,
                "local_day": e.dayKey, "variant": e.variant ?? NSNull(), "deleted": e.removed]
    }

    private func journalRow(_ e: ActivityEntry) -> [String: Any] {
        ["id": e.id.uuidString.lowercased(), "challenge_id": e.challengeID, "kind": e.kind,
         "entry_at": ServerDate.string(e.date), "local_day": e.dayKey,
         "title": e.title.map { String($0.prefix(200)) } ?? NSNull(),
         "body": e.text.map { String($0.prefix(4000)) } ?? NSNull(),
         "amount": e.amount, "ref": e.ref ?? NSNull(),
         // Photos themselves never leave the device; only the fact that one exists.
         "has_local_photo": e.photoFile != nil, "deleted": e.removed]
    }

    private func pushActivity(_ app: AppModel, _ client: SupabaseClient) async throws {
        let pending = app.store.entries(includeRemoved: true).filter(\.needsSync)
        guard !pending.isEmpty else { return }
        var rejected = 0
        for (table, group) in [("activity_sessions", pending.filter { ActivityEntry.timedKinds.contains($0.kind) }),
                               ("journal_entries", pending.filter { !ActivityEntry.timedKinds.contains($0.kind) })] {
            guard !group.isEmpty else { continue }
            let row: (ActivityEntry) -> [String: Any] = table == "activity_sessions" ? sessionRow : journalRow
            for chunk in stride(from: 0, to: group.count, by: 100).map({ Array(group[$0..<min($0 + 100, group.count)]) }) {
                do {
                    try await client.upsert(table, rows: chunk.map(row), onConflict: "id")
                    chunk.forEach { $0.needsSync = false }
                } catch BackendError.server(let status, _) where (400..<500).contains(status) && status != 401 && status != 429 {
                    // One bad row must not block the rest: send them one by one.
                    for e in chunk {
                        do {
                            try await client.upsert(table, rows: [row(e)], onConflict: "id")
                            e.needsSync = false
                        } catch BackendError.server(let s, _) where (400..<500).contains(s) && s != 401 && s != 429 {
                            rejected += 1 // stays on the device, untouched
                        }
                    }
                }
                app.store.save()
            }
        }
        rejectedCount = rejected
    }

    private func pushSudoku(_ app: AppModel, _ client: SupabaseClient) async throws {
        for save in app.store.sudokuSaves() where save.needsSync {
            guard let game = save.game, game.values.count == 81 else { save.needsSync = false; continue }
            let grid = game.values.map(String.init).joined()
            if let day = save.solvedDayKey, save.solvedAt != nil {
                let result = try await client.rpc("submit_sudoku_solution", params: [
                    "p_puzzle_id": save.puzzleID, "p_grid": grid, "p_local_day": day, "p_hints": game.hintsUsed,
                ]) as? [String: Any]
                save.serverVerified = (result?["solved"] as? Bool) == true
                save.needsSync = false
            } else {
                do {
                    try await client.upsert("sudoku_attempts", rows: [[
                        "puzzle_id": save.puzzleID, "current_grid": grid,
                        "pencil_notes": game.notes.map { Int($0) }, "hint_count": min(81, game.hintsUsed),
                    ]], onConflict: "user_id,puzzle_id")
                } catch BackendError.server(let status, _) where (400..<500).contains(status) && status != 401 && status != 429 {
                    // Already solved on the server, or not accepted: leave the local game alone.
                }
                save.needsSync = false
            }
            app.store.save()
        }
    }

    private func pushInteractions(_ app: AppModel, _ client: SupabaseClient) async throws {
        let pending = app.store.interactions().filter(\.needsSync)
        guard !pending.isEmpty else { return }
        var rows: [[String: Any]] = []
        for i in pending {
            rows.append(["card_id": i.cardID, "interaction_type": "viewed", "completed_at": ServerDate.string(i.seenAt), "saved": false])
            rows.append(["card_id": i.cardID, "interaction_type": "saved", "completed_at": ServerDate.string(i.updatedAt), "saved": i.saved])
            if let at = i.answeredAt {
                rows.append(["card_id": i.cardID, "interaction_type": "answered", "completed_at": ServerDate.string(at), "saved": false])
            }
            if i.dismissed {
                rows.append(["card_id": i.cardID, "interaction_type": "dismissed", "completed_at": ServerDate.string(i.updatedAt), "saved": false])
            }
        }
        do {
            try await client.upsert("discovery_interactions", rows: rows, onConflict: "user_id,card_id,interaction_type")
        } catch BackendError.server(let status, _) where (400..<500).contains(status) && status != 401 && status != 429 {
            rejectedCount += 1
        }
        pending.forEach { $0.needsSync = false }
        app.store.save()
    }

    // MARK: Pull

    private func cursorKey(_ table: String, _ userID: String) -> String { "sync.cursor.\(table).\(userID)" }

    private func pull(_ app: AppModel, _ client: SupabaseClient, _ userID: String) async throws {
        // Activity from other devices.
        for table in ["activity_sessions", "journal_entries"] {
            let key = cursorKey(table, userID)
            var query = [URLQueryItem(name: "select", value: "*"),
                         URLQueryItem(name: "order", value: "updated_at.asc"),
                         URLQueryItem(name: "limit", value: "1000")]
            if let cursor = defaults.string(forKey: key) {
                query.append(URLQueryItem(name: "updated_at", value: "gt.\(cursor)"))
            }
            let rows = try await client.select(table, query: query)
            for row in rows { merge(row, timed: table == "activity_sessions", into: app) }
            if let last = rows.last?["updated_at"] as? String { defaults.set(last, forKey: key) }
            if rows.count == 1000 { needsAnotherPass = true }
        }

        // Solved puzzles and games in progress.
        let attempts = try await client.select("sudoku_attempts", query: [URLQueryItem(name: "select", value: "*")])
        for row in attempts { mergeAttempt(row, into: app) }

        // Achievements the server has verified.
        let achievements = try await client.select("achievements", query: [
            URLQueryItem(name: "select", value: "*"), URLQueryItem(name: "year", value: "eq.\(AppModel.year)"),
        ])
        for row in achievements {
            guard let month = row["month"] as? Int, let cid = row["challenge_id"] as? String,
                  let verified = (row["verified_at"] as? String).flatMap(ServerDate.parse) else { continue }
            app.store.awardStamp(year: AppModel.year, month: month, challengeID: cid, completedAt: verified, verifiedAt: verified)
        }

        // Discovery history, once per account on this device.
        let interactionsKey = cursorKey("discovery_interactions", userID)
        if !defaults.bool(forKey: interactionsKey) {
            let rows = try await client.select("discovery_interactions", query: [URLQueryItem(name: "select", value: "*")])
            for row in rows {
                guard let cardID = row["card_id"] as? String, let type = row["interaction_type"] as? String,
                      DiscoveryLibrary.card(id: cardID) != nil else { continue }
                let at = (row["completed_at"] as? String).flatMap(ServerDate.parse) ?? app.now
                let existed = app.store.interaction(cardID: cardID) != nil
                let i = app.store.interaction(cardID: cardID, dayKey: app.calendar.dayKey(for: at), now: at)
                switch type {
                case "answered": if i.answeredAt == nil { i.answeredAt = at }
                case "saved": if !existed { i.saved = (row["saved"] as? Bool) ?? false }
                case "dismissed": i.dismissed = true
                default: break
                }
                if !existed { i.needsSync = false }
            }
            app.store.save()
            defaults.set(true, forKey: interactionsKey)
        }

        // Profile from another device, unless this device has newer edits.
        if !app.profile.needsSync {
            let rows = try await client.select("profiles", query: [
                URLQueryItem(name: "select", value: "*"), URLQueryItem(name: "id", value: "eq.\(userID)"),
            ])
            if let row = rows.first, let updated = (row["updated_at"] as? String).flatMap(ServerDate.parse),
               updated > app.profile.updatedAt, (row["onboarding_complete"] as? Bool) == true {
                let p = app.profile
                if let name = row["display_name"] as? String { p.displayName = name }
                if let feeling = row["feeling"] as? String { p.feelingRaw = feeling }
                let interests = try await client.select("user_interests", query: [URLQueryItem(name: "select", value: "*")])
                let choices = interests.compactMap { r -> InterestChoice? in
                    guard let c = r["category"] as? String, Interests.category(c) != nil else { return nil }
                    return InterestChoice(category: c, subcategory: r["subcategory"] as? String, weight: (r["weight"] as? Double) ?? 1)
                }
                if !choices.isEmpty { p.interests = choices }
                p.updatedAt = updated
                p.needsSync = false
                app.store.save()
            }
        }
    }

    private func merge(_ row: [String: Any], timed: Bool, into app: AppModel) {
        guard let idString = row["id"] as? String, let id = UUID(uuidString: idString),
              let challengeID = row["challenge_id"] as? String, let kind = row["kind"] as? String,
              let day = row["local_day"] as? String else { return }
        let deleted = (row["deleted"] as? Bool) ?? false
        if let local = app.store.entry(id: id) {
            // Local unsynced edits win; otherwise accept the server's version.
            guard !local.needsSync else { return }
            if deleted, !local.removed { app.store.remove(local); local.needsSync = false }
            if !timed, !deleted {
                local.text = row["body"] as? String
                local.title = row["title"] as? String
            }
            app.store.save()
            return
        }
        guard !deleted else { return }
        let dateString = (timed ? row["ended_at"] : row["entry_at"]) as? String
        guard let date = dateString.flatMap(ServerDate.parse) else { return }
        let amount = ((timed ? row["elapsed_seconds"] : row["amount"]) as? NSNumber)?.doubleValue ?? 1
        let entry = ActivityEntry(id: id, challengeID: challengeID, kind: kind, dayKey: day, date: date, amount: amount,
                                  ref: row["ref"] as? String, title: row["title"] as? String, text: row["body"] as? String,
                                  variant: row["variant"] as? String,
                                  startedAt: (row["started_at"] as? String).flatMap(ServerDate.parse))
        entry.needsSync = false
        app.store.add(entry)
    }

    private func mergeAttempt(_ row: [String: Any], into app: AppModel) {
        guard let puzzleID = row["puzzle_id"] as? String, let puzzle = SudokuLibrary.puzzle(id: puzzleID),
              let gridString = row["current_grid"] as? String else { return }
        let grid = gridString.compactMap(\.wholeNumberValue)
        guard grid.count == 81 else { return }
        let solved = (row["state"] as? String) == "solved"
        let local = app.store.sudokuSave(puzzleID: puzzleID)
        if let local, local.solvedAt != nil {
            if solved { local.serverVerified = true; app.store.save() }
            return
        }
        // Only adopt the server's board if this device has none, or it is the solution.
        guard local == nil || solved else { return }
        var game = SudokuGame(puzzle: puzzle)
        for i in 0..<81 where !game.isGiven(i) && grid[i] != 0 { game.place(grid[i], at: i) }
        if let local { app.store.context.delete(local); app.store.save() }
        let save = SudokuSave(puzzleID: puzzleID, gameData: (try? JSONEncoder().encode(game)) ?? Data())
        if solved, game.isSolved {
            save.solvedAt = (row["solved_at"] as? String).flatMap(ServerDate.parse) ?? app.now
            save.solvedDayKey = row["local_day"] as? String
            save.challengeID = row["challenge_id"] as? String
            save.serverVerified = true
        }
        save.needsSync = false
        app.store.context.insert(save)
        app.store.save()
    }

    // MARK: Rewards

    /// Asks the server to verify completed months. The server recomputes the
    /// total itself; the app only says which month to look at.
    private func claim(_ app: AppModel, _ client: SupabaseClient) async throws {
        app.refresh() // pulled activity may have completed something
        for stamp in app.store.stamps() where stamp.verifiedAt == nil && stamp.year == AppModel.year {
            guard app.calendar.isRevealed(month: stamp.month, at: Date()) else { continue }
            do {
                let result = try await client.rpc("claim_month_completion", params: ["p_challenge_id": stamp.challengeID]) as? [String: Any]
                if let verified = (result?["verified_at"] as? String).flatMap(ServerDate.parse) {
                    stamp.verifiedAt = verified
                    app.store.save()
                }
            } catch BackendError.server(let status, _) where (400..<500).contains(status) && status != 401 && status != 429 {
                continue // not accepted; the local stamp remains, marked as not yet backed up
            }
        }
    }

    /// Copy updates for months that have already been revealed.
    private func pullEditorial(_ app: AppModel, _ client: SupabaseClient) async throws {
        let rows = try await client.select("challenge_definitions", query: [
            URLQueryItem(name: "select", value: "editorial"), URLQueryItem(name: "year", value: "eq.\(AppModel.year)"),
        ])
        let overrides: [ChallengeDefinition] = rows.compactMap { row in
            guard let editorial = row["editorial"], JSONSerialization.isValidJSONObject(editorial),
                  let data = try? JSONSerialization.data(withJSONObject: editorial) else { return nil }
            return try? JSONDecoder().decode(ChallengeDefinition.self, from: data)
        }
        if !overrides.isEmpty { app.applyEditorial(overrides) }
    }
}
