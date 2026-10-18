# USS ACC architecture

Swift Package Manager builds a SwiftUI/AppKit executable and a dependency-free ACCCore library. No backend or account tokens are embedded.

## State and adapters

`AppModel` owns UI and connection state on the main actor. Calendar uses EventKit only after Connect. Mail automation uses a serialized actor and opt-in polling. Each live workspace generation invalidates outstanding results when the user switches to demo, disconnects, or switches modes. An actor-backed Mail operation already issued to macOS cannot be undone by cancelling a later UI operation.

`ACCCore` owns communication records, policy invariants, arrival ledger, persistence, travel types, and deterministic calendar candidate import. Its tests do not need account access or Apple Intelligence.

The Apple Intelligence adapter creates an independent Foundation Models session per message. Structured generation is validated again in core. The model cannot configure policy or execute actions. Incoming content is encoded as untrusted JSON. Trusted sender matching is supplied separately from configured exact addresses. This is not mail authentication; a future production mail adapter should add authenticated identity signals.

## Filter lifecycle

1. Connect Apple Mail. Snapshot the latest inbox identifiers as a baseline, with no automatic disposition or push.
2. Poll every 60 seconds while running; identify unseen arrivals through the durable ledger.
3. If classification is enabled, request an on-device score; failure leaves the item unscored.
4. Recheck the workspace generation and saved policy before applying any action.
5. OP5 always stays. Quarantine is a local view state. Delete delegates to Mail's delete behavior; no permanent expunge.
6. Save classification metadata and quarantine IDs atomically. Persistence failure pauses automatic filtering.

No retroactive bulk action occurs when settings are saved or a sample is tested. OP3/OP4 have no automatic classifier definition. A manually corrected score can use them for display; future arrivals are separate records.

## Journeys

Journey legs carry independent departure and arrival time zones, mode, source, calendar identity and reviewed state. Import detects candidates with word-boundary keywords, not a ticket parser. Unknown origins are explicitly placeholders and review is required. Reimport replaces only unreviewed candidates with the same identity, preserving user-reviewed routes. Calendar cancellations and changed reviewed events need a richer reconciliation workflow; they are not silently presented as real-time status.

## Terminal

SwiftTerm 1.20.0 supplies a PTY and VT terminal emulator. App-owned session objects preserve shells between workspaces. No shell starts on launch: New Session or Open Folder starts one. Closing a session terminates its child process. The app is intentionally not sandboxed for local development.

## Visual review

The approved image concepts live in docs/design. To render the running app's own demo views without account connections:

```sh
'build/USS ACC.app/Contents/MacOS/USSACC' --snapshot-dir /tmp/ussacc-previews
```

This renders Bridge, Comms, Events, Nav, Dev, and Settings, then exits. It does not capture other applications or the desktop. Terminal output in design mockups is fictional; actual shell sessions have no prefilled commands.
