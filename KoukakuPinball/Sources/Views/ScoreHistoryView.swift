import SwiftUI

/// Lists past game scores, newest first. The highest-scoring entry is highlighted so the
/// record among records is easy to spot at a glance.
struct ScoreHistoryView: View {
    @ObservedObject var scoreHistory: ScoreHistoryStore

    private var bestScore: Int? {
        scoreHistory.records.map(\.score).max()
    }

    var body: some View {
        NavigationStack {
            Group {
                if scoreHistory.records.isEmpty {
                    emptyState
                } else {
                    List(scoreHistory.records) { record in
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
            Text(record.date, format: .dateTime.year().month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ScoreHistoryView(scoreHistory: ScoreHistoryStore())
}
