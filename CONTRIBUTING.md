# Contributing to ChatPulse

ChatPulse is a dependency-free Manifest V3 extension written in JavaScript, HTML and CSS.

## Requirements

- Google Chrome 120 or newer;
- Node.js 20 or newer;
- no runtime npm dependencies.

## Local checks

```bash
npm run audit:extension
```

This command must pass before opening a pull request.

## Manual acceptance test

1. Load `chrome-extension` through `chrome://extensions`.
2. Sign in to ChatGPT in the same Chrome profile.
3. Add a test conversation.
4. Confirm that the first check records a baseline without sending.
5. Confirm that a stable assistant response receives exactly one command.
6. Confirm that stop and chat-disable actions cancel a pending send.
7. Confirm that settings changed during a check are preserved.

## Pull requests

Keep permissions minimal. Changes that add `cookies`, `history`, `webRequest`, `debugger`, `nativeMessaging`, `<all_urls>`, telemetry, remote code or third-party analytics require an explicit security justification and will normally be rejected.

Do not commit browser profiles, conversation URLs, logs containing private chat names, credentials or generated ZIP artifacts.