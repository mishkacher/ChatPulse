# Contributing

## Development

```bash
swift test
python3 scripts/quality_gate.py
```

Native app validation requires macOS 13 or newer and Google Chrome.

## Pull requests

- keep the core deterministic;
- do not add paid API or LLM dependencies for basic monitoring;
- preserve the exact default continuation command;
- add tests for every state-machine change;
- document any new Chrome selectors and their fallback behavior;
- do not weaken host validation or duplicate suppression.
