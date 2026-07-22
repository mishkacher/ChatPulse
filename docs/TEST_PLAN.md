# Test plan

## Automated core tests

The test suite verifies:

- first observation becomes a baseline;
- a changed response is not immediately continued;
- an unchanged completed assistant response is continued on the next check;
- one response cannot receive the command twice;
- a user message waits for the assistant;
- active generation blocks sending;
- limits and errors block sending;
- disabled chats are ignored;
- state survives JSON serialization;
- current and legacy ChatGPT URLs are normalized safely;
- interval values are bounded;
- the ring log retains only its configured capacity.

Run:

```bash
swift test
```

## Manual macOS acceptance test

1. Build and install ChatPulse.
2. Enable JavaScript from Apple Events.
3. Add two test chats from Chrome.
4. Set a one-minute interval.
5. Start monitoring.
6. Confirm that the first observation does not send anything.
7. Leave one assistant response unchanged.
8. Confirm one exact continuation message after the next check.
9. Confirm no duplicate message on another check before a new assistant response.
10. Allow ChatGPT to finish a new response.
11. Confirm that the first check after the new response only records it.
12. Confirm continuation on the following unchanged check.
13. Press Stop while a check is running and confirm no later chat receives a command.
14. Restart ChatPulse and confirm chat names and interval persist.
15. Disable one chat and confirm it is skipped.
16. Temporarily disable JavaScript from Apple Events and confirm a useful error appears.

## Release gate

A release candidate must pass:

```bash
make audit
bash scripts/build_app.sh
```

It must also complete the manual acceptance test on both Apple Silicon and Intel macOS where possible.
