#if os(macOS)
import AppKit
import HelloFrankCore
import SwiftUI

struct TicketRow: View {
    let ticket: Ticket
    let now: Date
    let isFocused: Bool
    let action: ProposalAction?
    let onDecision: (ProposalDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(ticket.identifier)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(ticket.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text("\(ticket.ageDays(now: now))d")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(ticket.isStale ? Color.red : Color.secondary)
                    .help(ageHelp)
            }
            HStack(spacing: 4) {
                StatePill(state: ticket.pipelineState)
                ForEach(ticket.cxLabelNames, id: \.self) { LabelChip(name: $0) }
                if ticket.isStale {
                    Text("Stale").font(.caption2).foregroundStyle(.red)
                }
                Spacer(minLength: 0)
            }
            detail
            actions
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(isFocused ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(ticket.url) }
        .contextMenu {
            Button("Copy ticket ID") { copy(ticket.identifier) }
            Button("Copy link") { copy(ticket.url.absoluteString) }
        }
        .help(ticket.title)
    }

    private var ageHelp: String {
        guard let last = ticket.lastHumanActivityAt else { return "No human activity yet" }
        let days = Int(now.timeIntervalSince(last) / 86_400)
        return "Last human activity \(days)d ago"
    }

    private var proposalExpired: Bool { ticket.proposal?.isExpired(now: now) ?? false }

    @ViewBuilder
    private var detail: some View {
        switch ticket.pipelineState {
        case .waitingOnYou:
            if ticket.proposal?.isConflicting == true {
                note("Conflicting reactions, fix in Slack", color: .orange)
            } else if proposalExpired {
                note("Proposal expired: Fix Approvals only looks back 7 days", color: .orange)
            } else if let rootCause = ticket.proposal?.rootCause {
                note("Root cause: \(rootCause)", color: .secondary)
            }
            if case .failed(_, let message)? = action {
                note(message, color: .red)
            }
        case .approvedPending:
            note("Approved, waiting for Fix Approvals" + (proposalExpired ? " (proposal expired)" : ""), color: .blue)
        case .declinePending:
            note("Declined, waiting for Fix Approvals" + (proposalExpired ? " (proposal expired)" : ""), color: .blue)
        case .question:
            if let question = ticket.questionForKyle, !question.isEmpty {
                note(question, color: .purple)
            }
        case .proposed:
            note("Fix proposed; Slack message not found in the last 14 days", color: .secondary)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch ticket.pipelineState {
        case .waitingOnYou:
            HStack(spacing: 8) {
                let disabled = ticket.proposal?.isConflicting == true || proposalExpired || isSending
                Button("✅ Approve") { onDecision(.approve) }.disabled(disabled)
                Button("❌ Decline") { onDecision(.decline) }.disabled(disabled)
                if isSending { ProgressView().controlSize(.small) }
            }
            .controlSize(.small)
        case .prOpen:
            if let prURL = ticket.prURL {
                Button("Open PR") { NSWorkspace.shared.open(prURL) }.controlSize(.small)
            }
        case .question:
            Button("Answer in Linear") { NSWorkspace.shared.open(ticket.url) }.controlSize(.small)
        default:
            EmptyView()
        }
    }

    private var isSending: Bool {
        if case .sending? = action { return true }
        return false
    }

    private func note(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
#endif
