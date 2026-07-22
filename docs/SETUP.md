# Setup and troubleshooting

## Build prerequisites

Install Xcode Command Line Tools:

```bash
xcode-select --install
```

Verify Swift:

```bash
swift --version
```

## Build

```bash
bash scripts/build_app.sh
```

Output:

```text
dist/ChatPulse.app
```

## Install

```bash
bash scripts/install_app.sh
```

## Chrome permission

Enable:

```text
View → Developer → Allow JavaScript from Apple Events
```

Then allow Automation access in macOS when prompted.

## “Не удалось добавить чат”

Check that:

- the frontmost application is Google Chrome;
- the active Chrome tab is a specific ChatGPT conversation;
- its URL contains `/c/`;
- JavaScript from Apple Events is enabled.

## Chat opens but no command is sent

Expected reasons:

- the response changed on this check, so ChatPulse waits one full interval;
- ChatGPT is still generating;
- the latest message belongs to the user;
- the same response has already been continued;
- a technical limit or page error is visible;
- the prompt control could not be found after a ChatGPT UI update.

Inspect **Последние действия…** from the menu.

## Reset settings

Quit ChatPulse and remove:

```bash
rm -rf "$HOME/Library/Application Support/ChatPulse"
```

## Uninstall application

```bash
bash scripts/uninstall_app.sh
```
