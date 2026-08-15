import SwiftUI

/// One of the two large LEFT / RIGHT circles that light up when a smile is detected.
struct SmileIndicatorCircle: View {
    let label: String
    let isActive: Bool
    let activeColor: Color

    var body: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(isActive ? activeColor : Color(.systemGray4))
                .frame(width: 120, height: 120)
                .animation(.easeOut(duration: 0.1), value: isActive)
            Text(label)
                .font(.headline)
        }
    }
}
