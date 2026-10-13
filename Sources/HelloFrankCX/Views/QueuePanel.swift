#if os(macOS)
import AppKit
import HelloFrankCore
import SwiftUI

struct QueuePanel: View {
    @EnvironmentObject private var store: QueueStore
    @AppStorage(SettingsKey.cxOnly) private var cxOnly = false
    @State private var search = ""
    @State private var confirmation: Confirmation?

    struct Confirmation {
        let ticket: Ticket
        let proposal: FixProposal
        let decision: ProposalDecision
    }

    var body: some View {
        let now = Date()
        let needsYou = QueueBuilder.filter(store.needsYou, search: search, cxOnly: false)
        let all = QueueBuilder.filter(store.tickets, search: search, cxOnly: cxOnly)

        VStack(spacing: 0) {
            header
            Divider()
            if !store.hasLinearKey {
                setupPrompt
            } else if store.tickets.isEmpty && store.lastUpdated == nil {
                placeholder(store.isRefreshing ? "Loading the queue…" : "No data yet. Press Refresh.")
            } else {
                queue(needsYou: needsYou, all: all, now: now)
            }
            Divider()
            footer
        }
        .frame(width: 400)
        .overlay {
            if let confirmation {
                ConfirmDecisionView(
                    ticket: confirmation.ticket,
                    proposal: confirmation.proposal,
                    decision: confirmation.decision,
                    onConfirm: {
                        self.confirmation = nil
                        Task {
                            await store.react(
                                confirmation.decision,
                                channel: confirmation.proposal.channel,
                                ts: confirmation.proposal.ts
                            )
                        }
                    },
                    onCancel: { self.confirmation = nil }
                )
            }
        }
        .onAppear { store.refreshIfStale() }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("HelloFrank CX").font(.headline)
                Text("\(store.tickets.count) open").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if store.isRefreshing {
                    ProgressView().controlSize(.small)
                }
            }
            TextField("Filter by ID or title", text: $search)
                .textFieldStyle(.roundedBorder)
            if let error = store.linearError {
                errorLine(error)
            }
            if let error = store.slackError {
                errorLine(error)
            }
            if store.hasWarning {
                errorLine("Polling every 15 min until a poll succeeds")
            }
        }
        .padding(12)
    }

    private func queue(needsYou: [Ticket], all: [Ticket], now: Date) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !needsYou.isEmpty {
                        sectionHeader("Needs you", count: needsYou.count)
                        ForEach(needsYou) { ticket in
                            row(ticket, now: now).id("needs-\(ticket.id)")
                            Divider().padding(.leading, 12)
                        }
                    }
                    HStack {
                        sectionHeader("All open tickets", count: all.count)
                        Toggle("CX only", isOn: $cxOnly)
                            .toggleStyle(.checkbox)
                            .font(.caption)
                            .padding(.trailing, 12)
                    }
                    if all.isEmpty {
                        Text(search.isEmpty ? "Nothing open." : "No tickets match.")
                            .foregroundStyle(.secondary)
                            .padding(12)
                    }
                    ForEach(all) { ticket in
                        row(ticket, now: now).id("all-\(ticket.id)")
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .frame(height: scrollHeight(needsYou: needsYou.count, all: all.count))
            .onAppear { scrollToFocus(proxy, needsYou: needsYou) }
            .onChange(of: store.focusedTicketID) { _ in scrollToFocus(proxy, needsYou: needsYou) }
        }
    }

    private func row(_ ticket: Ticket, now: Date) -> some View {
        TicketRow(
            ticket: ticket,
            now: now,
            isFocused: store.focusedTicketID == ticket.id,
            action: ticket.proposal.flatMap { store.proposalActions[$0.ts] },
            onDecision: { decision in
                guard let proposal = ticket.proposal else { return }
                confirmation = Confirmation(ticket: ticket, proposal: proposal, decision: decision)
            }
        )
    }

    private var footer: some View {
        HStack(spacing: 12) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(updatedText(now: context.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .help("Refresh (⌘R)")
            .disabled(store.isRefreshing || !store.hasLinearKey)
            Button("Settings") { SettingsWindow.show() }
                .keyboardShortcut(",", modifiers: .command)
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var setupPrompt: some View {
        VStack(spacing: 8) {
            Text("Add your Linear API key to see the queue.")
                .foregroundStyle(.secondary)
            Button("Open Settings") { SettingsWindow.show() }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    // MARK: Helpers

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title.uppercased()).font(.caption.weight(.semibold))
            Text("\(count)").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(24)
    }

    private func errorLine(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
    }

    /// The panel grows with its content up to about 600 pt in total.
    private func scrollHeight(needsYou: Int, all: Int) -> CGFloat {
        let estimate = CGFloat(needsYou) * 92 + CGFloat(all) * 58 + 80
        return min(460, max(140, estimate))
    }

    private func scrollToFocus(_ proxy: ScrollViewProxy, needsYou: [Ticket]) {
        guard let id = store.focusedTicketID else { return }
        let anchor = needsYou.contains { $0.id == id } ? "needs-\(id)" : "all-\(id)"
        DispatchQueue.main.async {
            withAnimation { proxy.scrollTo(anchor, anchor: .center) }
        }
        // Clear the highlight after a few seconds.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if store.focusedTicketID == id { store.focus(ticketID: nil) }
        }
    }

    private func updatedText(now: Date) -> String {
        guard let lastUpdated = store.lastUpdated else { return "Not updated yet" }
        let seconds = max(0, now.timeIntervalSince(lastUpdated))
        switch seconds {
        case ..<60: return "Updated just now"
        case ..<3600: return "Updated \(Int(seconds / 60)) min ago"
        default: return "Updated \(Int(seconds / 3600)) h ago"
        }
    }
}
#endif
