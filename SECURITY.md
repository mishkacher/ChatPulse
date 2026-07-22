# Security policy

## Supported version

The current development line is `0.1.x`.

## Security model

ChatPulse is not sandboxed in version 0.1.0 because it must send Apple Events to Google Chrome. macOS therefore grants it Automation access after user confirmation.

The application:

- accepts only ChatGPT conversation URLs;
- does not read Chrome cookies directly;
- does not store passwords or authentication tokens;
- does not send telemetry;
- does not call an external AI or API;
- stores settings locally in the user Application Support directory;
- sends only the configured continuation command;
- confirms the new user message before marking a response as processed.

## Important Chrome setting

`Allow JavaScript from Apple Events` gives approved Apple Events clients the ability to execute page JavaScript in Chrome. Enable it only on a trusted Mac and revoke ChatPulse Automation permission if the application binary is replaced by an untrusted build.

A dedicated Chrome profile is recommended for additional isolation.

## Reporting a vulnerability

Open a private security advisory in the GitHub repository. Do not publish secrets, private chat URLs or conversation content in a public issue.
