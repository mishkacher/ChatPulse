# Architecture

## Goals

ChatPulse is intentionally small and deterministic. It does not use an LLM to decide what to do and does not require a remote service.

The application has four boundaries:

1. **Menu bar UI** — user controls and status presentation.
2. **Monitor coordinator** — scheduling, cancellation and sequential processing.
3. **Decision engine** — pure state transition logic.
4. **Chrome automation** — the only component allowed to inspect or modify a browser tab.

## Data flow

```text
Timer
  ↓
MonitorCoordinator
  ↓
ChromeAutomation.inspect(chat)
  ↓
BrowserSnapshot
  ↓
DecisionEngine.evaluate(...)
  ↓
MonitorDecision
  ├── no action
  ├── record new response
  ├── block on generation/error/limit
  └── send continuation
          ↓
    ChromeAutomation.send(...)
          ↓
    confirmation that the user message exists
          ↓
    persist commanded fingerprint
```

## Stable-response rule

A new assistant message is never continued during the same observation in which it is first discovered.

The decision engine requires the same assistant fingerprint on a subsequent check. This creates a complete interval between a newly observed response and the next continuation command.

## Deduplication

Each chat persists:

- `lastObservedFingerprint`;
- `lastCommandedFingerprint`;
- timestamps for observation and successful send.

If both fingerprints are equal, ChatPulse has already sent a continuation for that response and will not send it again.

## Browser fingerprint

The page script hashes:

- message role;
- DOM message identifier when available;
- normalized visible text of the final message.

The implementation uses a compact FNV-1a hash inside the browser page. The fingerprint is not cryptographic and is used only for change detection.

## Threading

- UI work stays on the main thread.
- browser checks run serially on a utility queue;
- only one check batch can be active;
- Stop prevents a pending decision from sending a new command;
- settings writes are protected by a lock and use atomic file replacement.

## Trust boundaries

The app accepts only normalized chat URLs on:

- `chatgpt.com`;
- `chat.openai.com`.

No arbitrary URL can be added through the UI.

## Future improvements

- signed and notarized release builds;
- resilient selector registry with remote-free compatibility packs;
- launch-at-login option;
- optional macOS notification when a technical limit is detected;
- UI tests against a local deterministic HTML fixture;
- optional Chrome extension transport that avoids Apple Events JavaScript permission.
