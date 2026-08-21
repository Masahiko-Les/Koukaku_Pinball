import SwiftUI

/// Lists past game scores, highest first. The top-scoring entry (or entries, in a tie) is
/// highlighted so the record among records is easy to spot at a glance.
struct ScoreHistoryView: View {
    @ObservedObject var scoreHistory: ScoreHistoryStore

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        // Fixed, locale-independent format (rather than `.dateTime`'s locale-driven style)
        // so this always reads like "2026/3/2 12:00" regardless of the device's locale.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy/M/d HH:mm"
        return formatter
    }()

    private var bestScore: Int? {
        scoreHistory.records.map(\.score).max()
    }

    /// Swift's sort is stable, so entries with equal scores keep `scoreHistory.records`'
    /// own newest-first relative order.
    private var sortedRecords: [ScoreRecord] {
        scoreHistory.records.sorted { $0.score > $1.score }
    }

    var body: some View {
        NavigationStack {
            Group {
                if scoreHistory.records.isEmpty {
                    emptyState
                } else {
                    List(sortedRecords) { record in
                        row(for: record)
                    }
                }
            }
            .navigationTitle("スコア履歴")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("記録はまだありません")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(for record: ScoreRecord) -> some View {
        let isBest = record.score == bestScore
        return HStack {
            Text("\(record.score)")
                .font(.system(.body, design: .rounded).bold())
                .monospacedDigit()
                .foregroundStyle(isBest ? .yellow : .primary)
            if isBest {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
            Spacer()
            Text(Self.dateFormatter.string(from: record.date))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ScoreHistoryView(scoreHistory: ScoreHistoryStore())
}
