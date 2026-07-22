# Changelog

## 0.5.1 beta — stale-tab recovery

- detect Chrome `discarded` and `frozen` managed tabs before reading the page;
- mark managed tabs as `autoDiscardable: false` when supported;
- add bounded content-script timeouts and automatic reinjection;
- reload and rehydrate a chat when its content script stops responding or the page reports an error;
- periodically refresh inactive chats every 5–15 minutes to synchronize stale SPA content with the server;
- never perform a periodic refresh on an active tab, during normal generation, or while the composer contains a user draft;
- recover an inactive generation only after it has remained stuck for more than 20 minutes;
- repeat the freshness preflight immediately before sending a continuation command;
- preserve at-most-once dispatch protection across all recovery paths;
- record the last recovery time, reason and recovery count in local state;
- add dedicated stale-tab recovery tests and expand the Manifest V3 audit.

## 0.5.0 beta — Chrome extension

- replaced the unsupported embedded WebKit login with the authenticated Google Chrome profile;
- migrated to Manifest V3;
- added background scheduling with `chrome.alarms`;
- added selected-chat management and automatic tab recovery;
- preserved baseline delay and at-most-once duplicate protection;
- added macOS and ChatPulse Preview themes;
- added local logs, settings and manual diagnostics;
- limited permissions to `alarms`, `scripting`, `storage` and `tabs`;
- added five-cycle CI, ZIP packaging and SHA-256 validation;
- removed the native macOS/WebKit implementation from the active repository branches.

The current repository is Chrome-extension-only.
