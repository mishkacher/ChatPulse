# Technical notes

The stale-tab recovery path is intentionally bounded and preserves at-most-once dispatch. Managed tabs are protected from automatic discarding when Chrome supports `autoDiscardable: false`. Recovery reloads are skipped for active tabs, ordinary in-progress generations and non-empty user drafts.
