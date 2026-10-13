#if os(macOS)
import HelloFrankCore
import SwiftUI

struct StatePill: View {
    let state: PipelineState

    var body: some View {
        Text(state.title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var color: Color {
        switch state {
        case .prOpen: return .green
        case .implementing: return .teal
        case .waitingOnYou: return .orange
        case .approvedPending, .declinePending: return .blue
        case .declined: return .gray
        case .question: return .purple
        case .proposed: return .indigo
        case .debugged: return .cyan
        case .triaged: return .brown
        case .untouched: return .secondary
        }
    }
}

struct LabelChip: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.5)))
            .foregroundStyle(.secondary)
    }
}
#endif
