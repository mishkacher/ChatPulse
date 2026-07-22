# 20-round optimization and audit record

This document records the initial implementation review performed for version 0.1.0.

| Round | Focus | Result |
|---:|---|---|
| 1 | Requirement fidelity | Exact command, Chrome requirement and menu-bar-only UX fixed in the core specification. |
| 2 | Scope reduction | Removed the need for Browser Use, Playwright, local models and paid APIs. |
| 3 | Native UX | Selected AppKit status item with accessory activation and no Dock icon. |
| 4 | Start/Stop interaction | Implemented one dynamic menu command instead of separate buttons. |
| 5 | Interval control | Added presets and a custom interval with safe minimum and maximum bounds. |
| 6 | Chat identity | Persisted both human-readable title and normalized conversation URL. |
| 7 | Fresh-response protection | New assistant responses become a baseline and are never continued immediately. |
| 8 | Duplicate prevention | Added per-response commanded fingerprints persisted across restarts. |
| 9 | Restart safety | First observation of every process run is always passive. |
| 10 | Generation detection | Stop-button and localized accessible-label fallbacks block sending. |
| 11 | Limit/error handling | Restricted detection to alerts and assistant output to avoid matching the command itself. |
| 12 | URL security | Limited automation to supported ChatGPT hosts and conversation paths. |
| 13 | Persistence resilience | Atomic JSON writes, interval clamping and fallback defaults were added. |
| 14 | Concurrency audit | Serialized browser work and removed an unsafe state reset during Stop. |
| 15 | Stop semantics | Added a final running-state check immediately before command dispatch. |
| 16 | Delivery verification | Added post-send browser confirmation before storing a successful command fingerprint. |
| 17 | Build ergonomics | Added reproducible build, install and uninstall scripts for a single `.app`. |
| 18 | Test coverage | Added deterministic tests for the complete baseline → send → response → wait cycle. |
| 19 | CI and quality gates | Added macOS CI, app artifact generation and 20 static project invariants. |
| 20 | Documentation and security | Added setup, architecture, test plan, limitations and security guidance. |

## Outcome

The deterministic core passes its automated tests and quality gates in the development environment. Native Chrome automation still requires a real macOS acceptance run because AppKit, Google Chrome and Apple Events are not available in the Linux validation environment.
