# Changelog

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