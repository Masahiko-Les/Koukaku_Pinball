import Foundation

/// One completed game's final score.
struct ScoreRecord: Codable, Identifiable {
    let id: UUID
    let score: Int
    let date: Date
}

/// A log of past game scores, persisted via UserDefaults — separate from `GameState`'s
/// single `highScore`, which tracks only the current best. Newest entries first.
final class ScoreHistoryStore: ObservableObject {
    @Published private(set) var records: [ScoreRecord] = []

    /// Oldest entries are dropped past this count.
    private let maxRecords = 20
    private let storageKey = "com.mfujita.koukakupinball.scoreHistory"

    init() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([ScoreRecord].self, from: data) else {
            return
        }
        records = decoded
    }

    func record(_ score: Int) {
        records.insert(ScoreRecord(id: UUID(), score: score, date: Date()), at: 0)
        if records.count > maxRecords {
            records.removeLast(records.count - maxRecords)
        }
        guard let data = try? JSONEncoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
