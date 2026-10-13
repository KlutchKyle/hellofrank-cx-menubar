# HelloFrank CX menu bar app

A macOS menu bar app that shows Kyle's open HelloFrank Board tickets oldest first, shows where each one sits in the triage → debug → fix pipeline, and approves or declines fix proposals with one click.

It only reads what the Claude Code routines already write: Linear tickets and their marker comments, and the `[fix-proposal …]` / `[prod-debug …]` messages in Kyle's Slack self-DM. Approving adds Kyle's ✅ to the Slack proposal, so Fix Approvals and Ticket Fix Implement run exactly as they do today. The app never writes to Linear, never posts to Slack and never starts a routine.

## Requirements

- macOS 13 Ventura or later
- Xcode 15 or later (Swift 5.9+), or the matching Command Line Tools

No third-party packages.

## Build and install

```sh
scripts/build-app.sh --install
```

This builds a release binary, wraps it in `HelloFrank CX.app` (with `LSUIElement`, so there is no Dock icon), signs it ad hoc, copies it to `/Applications` and launches it. Without `--install` the app is left in `build/`.

To develop in Xcode, open `Package.swift` and run the `HelloFrankCX` scheme. Running outside an app bundle works for the queue and the panel, but macOS turns off notifications and launch at login for it. Use the script to test those.

Ad hoc signing changes with every build, so after a rebuild macOS may ask once whether HelloFrank CX can use its Keychain items. Click **Always Allow**. To avoid this, sign with your own identity: `SIGN_IDENTITY="Apple Development: …" scripts/build-app.sh --install`.

## First-run setup

Settings opens automatically on first launch. You can also reach it from the panel footer (⌘,).

1. **Linear API key:** Linear → Settings → Security & access → Personal API keys. Create a read-only key and paste it into Settings.
2. **Slack user token (optional, needed for proposals and approvals):** create a Slack app from [`slack-app-manifest.yml`](slack-app-manifest.yml) in the hello, Frank workspace. It asks for the user scopes `im:history`, `im:write` and `reactions:write`. Install it (a workspace admin may need to approve), then copy the **User OAuth Token** (`xoxp-…`) into Settings.
3. Click **Test connection**. It should show `kyle@hellofrank.ai` for Linear and your Slack user.

Both tokens are stored only in the Keychain (service `ai.hellofrank.cx-menubar`, accounts `linear-api-key` and `slack-user-token`). Settings shows only whether each one is saved. Errors and logs show HTTP status and API error codes, never tokens.

## How it works

| Piece | Where |
| --- | --- |
| Menu bar label and app entry | `Sources/HelloFrankCX/HelloFrankCXApp.swift` |
| Polling, merging, approvals | `Sources/HelloFrankCX/Store/QueueStore.swift` |
| Panel, rows, confirm dialog, settings | `Sources/HelloFrankCX/Views/` |
| Notifications with Approve/Decline actions | `Sources/HelloFrankCX/Notifications/Notifier.swift` |
| Keychain, launch at login | `Sources/HelloFrankCX/Services/`, `Support/` |
| Models, marker parsing, pipeline state | `Sources/HelloFrankCore/` (Foundation only) |
| Linear GraphQL and Slack Web API clients | `Sources/HelloFrankCore/Services/` |
| Change detection for notifications | `Sources/HelloFrankCore/Logic/QueueEvents.swift` |

All the logic that decides what to show lives in `HelloFrankCore`, which has no UI dependencies and is covered by unit tests (`swift test`, which also runs on Linux).

### Pipeline states

Checked top to bottom; the first match wins.

| Pill | Rule | Badge |
| --- | --- | --- |
| PR open | Has a `<!-- fix-pr -->` comment; the PR link comes from its body | |
| Implementing | Slack proposal has 🚀 | |
| Waiting on you | Slack proposal has none of ✅ ❌ 🚀 🚫 (or both ✅ and ❌, shown as a conflict) | ✓ |
| Approved / Declining | You added ✅ or ❌; waiting for Fix Approvals to add 🚀 or 🚫 | |
| Declined | A `fix-declined` comment is newer than the latest `fix-proposal` comment, or the proposal has 🚫 | |
| Question | Latest `cx-triage` comment has "Question for Kyle:" and Kyle hasn't commented since | ✓ |
| Proposed | Has a `fix-proposal` comment but its Slack message wasn't found (Slack not connected, or older than 14 days) | |
| Debugged | Has a `fix-debug` comment and no proposal | |
| Triaged | Has a `cx-triage` comment | |
| Untouched | No marker comments | |

Human activity is any comment without a marker that isn't by `Customer Support`, `GitHub Copilot` or `Linear`, plus status changes made by a person. A ticket with no human activity for the stale threshold (14 days by default) shows its age in red.

Expired proposals (older than 7 days, which Fix Approvals no longer sees) stay in the full queue marked as expired, with Approve and Decline disabled. They don't count toward the badge.

### Polling and notifications

- Polls every 2 minutes by default (1, 2, 5 or 15 in Settings). It also polls when you open the panel if the last poll is more than 30 seconds old.
- Pauses while the Mac is asleep or offline, and polls once after wake or reconnect.
- After 3 failed polls in a row, it backs off to 15 minutes and shows ⚠︎ next to the icon until a poll succeeds.
- Notifications fire only for things not seen before. Seen keys (Linear comment IDs, Slack `ts`, issue IDs) are kept in `~/Library/Application Support/ai.hellofrank.cx-menubar/state.json`. The first successful poll of each source marks everything as seen without notifying, so a relaunch or a newly connected Slack token never replays old alerts.
- Stale tickets are batched into at most one notification a day.

## Design choices beyond the spec

These are the places where the spec left room for interpretation.

- **Slack lookback is 14 days, not 7.** Fix Approvals only looks back 7 days. Reading a bit further lets the app show a proposal as expired instead of dropping it silently.
- **Thread replies:** the app uses Slack's `latest_reply` field for the most recent reminder time. It calls `conversations.replies` only when that field is missing on a proposal still waiting on you.
- **Linear query:** besides the fields in the spec, it fetches `history(first: 25)` for status changes (used for human activity) and the comment author's `id`, so it can tell Kyle's own replies apart. If Linear rejects a page as too complex, the app halves the page size and retries.
- **Answering a question:** only a comment from Kyle (the Linear viewer), without a marker, counts as a reply. If the viewer can't be loaded, any human comment counts.
- **Opening the panel from a notification** clicks the status item, since SwiftUI has no API for this. If a macOS update breaks it, clicking the notification just does nothing; nothing else changes.

## Open questions from the spec

- Can Kyle install the Slack app himself, or does an admin need to approve it?
- Should stale tickets count toward the badge? Currently they don't.
- Should the default view be CX only? The toggle is off by default.
- Is a "Run triage now" or "Check approvals now" button wanted? Both need an API trigger on the routine.
