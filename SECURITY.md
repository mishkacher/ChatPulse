# Security Policy

## Supported version

Security fixes are applied to the current Chrome extension beta in `main`.

## Reporting a vulnerability

Use a private GitHub Security Advisory:

`https://github.com/mishkacher/ChatPulse/security/advisories/new`

Do not publish sensitive information in a public issue. Never attach:

- cookies or exported browser profiles;
- email addresses, passwords, one-time codes or passkeys;
- private ChatGPT conversation URLs;
- conversation contents;
- screenshots containing account or billing information.

## Security boundaries

ChatPulse:

- runs locally in Google Chrome;
- has no backend and no telemetry;
- restricts host access to `chatgpt.com` and `chat.openai.com`;
- does not request `cookies`, `history`, `webRequest`, `debugger`, `nativeMessaging` or `<all_urls>`;
- stores settings in `chrome.storage.local`;
- records only technical response fingerprints for duplicate prevention.

## User responsibilities

Install the unpacked extension only from a trusted copy of this repository. Review `manifest.json` before loading it and re-check permissions after updates.