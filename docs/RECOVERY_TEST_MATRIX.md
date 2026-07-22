# Recovery test matrix

- discarded tab → reload and rehydrate;
- frozen tab → reload and rehydrate;
- content script timeout → reinject and reload;
- page error → reload;
- inactive stale tab → periodic refresh;
- active tab → no periodic refresh;
- user draft → no periodic refresh;
- normal generation → no periodic refresh;
- generation stuck over 20 minutes → recovery;
- duplicate response fingerprint → no repeated command.
