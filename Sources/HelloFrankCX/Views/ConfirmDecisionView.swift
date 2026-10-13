#if os(macOS)
import HelloFrankCore
import SwiftUI

/// Confirmation before adding ✅ or ❌ to a proposal. Shown as an overlay
/// because sheets are unreliable inside a menu bar panel.
struct ConfirmDecisionView: View {
    let ticket: Ticket
    let proposal: FixProposal
    let decision: ProposalDecision
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
            VStack(alignment: .leading, spacing: 10) {
                Text(decision == .approve ? "Approve this fix?" : "Decline this fix?")
                    .font(.headline)
                Text("\(ticket.identifier) · \(ticket.title)")
                    .lineLimit(2)
                if let rootCause = proposal.rootCause {
                    field("Root cause", rootCause)
                }
                if let fix = proposal.fix {
                    field("Fix", fix)
                }
                Text(decision == .approve
                     ? "Adds ✅ to the Slack proposal. Fix Approvals starts Ticket Fix Implement on its next run."
                     : "Adds ❌ to the Slack proposal. Fix Approvals records the decline on its next run.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Button(decision == .approve ? "Approve" : "Decline", action: onConfirm)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .shadow(radius: 8)
            .padding(20)
        }
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.callout).lineLimit(4).fixedSize(horizontal: false, vertical: true)
        }
    }
}
#endif
