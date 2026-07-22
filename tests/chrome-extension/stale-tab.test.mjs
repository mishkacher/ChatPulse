import assert from "node:assert/strict";
import test from "node:test";

import {
  createChat,
  defaultState,
  mergeRuntimeState,
  planTabRecovery,
  recordRecovery,
  refreshIntervalMs,
  STUCK_GENERATION_MS
} from "../../chrome-extension/lib/model-v2.js";

const now = Date.parse("2026-07-23T00:00:00.000Z");
const chat = (overrides = {}) => ({
  ...createChat({
    title: "Тестовый чат",
    url: "https://chatgpt.com/c/example",
    now: "2026-07-22T23:55:00.000Z"
  }),
  ...overrides
});
const tab = (overrides = {}) => ({ id: 7, active: false, discarded: false, frozen: false, ...overrides });
const snapshot = (overrides = {}) => ({
  pageReady: true,
  authenticated: true,
  errorDetected: false,
  isGenerating: false,
  generationAgeMs: 0,
  hasDraft: false,
  ...overrides
});

test("выгруженная вкладка всегда восстанавливается", () => {
  assert.deepEqual(
    planTabRecovery({ tab: tab({ discarded: true }), snapshot: null, chat: chat(), intervalMinutes: 5, now }),
    { refresh: true, reason: "discarded-tab" }
  );
});

test("замороженная вкладка всегда восстанавливается", () => {
  assert.deepEqual(
    planTabRecovery({ tab: tab({ frozen: true }), snapshot: snapshot(), chat: chat(), intervalMinutes: 5, now }),
    { refresh: true, reason: "frozen-tab" }
  );
});

test("неотвечающий content script приводит к обновлению вкладки", () => {
  assert.deepEqual(
    planTabRecovery({ tab: tab(), snapshot: null, chat: chat(), intervalMinutes: 5, now }),
    { refresh: true, reason: "content-unreachable" }
  );
});

test("активная вкладка и пользовательский черновик не перезагружаются планово", () => {
  const old = chat({ lastHardRefreshAt: "2026-07-22T20:00:00.000Z" });
  assert.equal(
    planTabRecovery({ tab: tab({ active: true }), snapshot: snapshot(), chat: old, intervalMinutes: 1, now }).refresh,
    false
  );
  assert.equal(
    planTabRecovery({ tab: tab(), snapshot: snapshot({ hasDraft: true }), chat: old, intervalMinutes: 1, now }).refresh,
    false
  );
});

test("обычная активная генерация не прерывается", () => {
  const result = planTabRecovery({
    tab: tab(),
    snapshot: snapshot({ isGenerating: true, generationAgeMs: 2 * 60_000 }),
    chat: chat({ lastHardRefreshAt: "2026-07-22T20:00:00.000Z" }),
    intervalMinutes: 1,
    now
  });
  assert.equal(result.refresh, false);
});

test("зависшая генерация в фоновой вкладке восстанавливается", () => {
  assert.deepEqual(
    planTabRecovery({
      tab: tab(),
      snapshot: snapshot({ isGenerating: true, generationAgeMs: STUCK_GENERATION_MS + 1 }),
      chat: chat(),
      intervalMinutes: 5,
      now
    }),
    { refresh: true, reason: "stuck-generation" }
  );
});

test("неактивная вкладка периодически обновляется для свежего серверного состояния", () => {
  const old = chat({ lastHardRefreshAt: "2026-07-22T23:40:00.000Z" });
  assert.deepEqual(
    planTabRecovery({ tab: tab(), snapshot: snapshot(), chat: old, intervalMinutes: 5, now }),
    { refresh: true, reason: "periodic-freshness" }
  );
});

test("недавно обновлённая вкладка не перезагружается повторно", () => {
  const recent = chat({ lastHardRefreshAt: "2026-07-22T23:58:00.000Z" });
  assert.equal(
    planTabRecovery({ tab: tab(), snapshot: snapshot(), chat: recent, intervalMinutes: 5, now }).refresh,
    false
  );
});

test("интервал принудительной свежести ограничен 5–15 минутами", () => {
  assert.equal(refreshIntervalMs(0.5), 5 * 60_000);
  assert.equal(refreshIntervalMs(5), 15 * 60_000);
  assert.equal(refreshIntervalMs(60), 15 * 60_000);
});

test("восстановление сохраняется и переживает runtime merge", () => {
  const original = chat();
  const recovered = recordRecovery(original, "frozen-tab", "2026-07-23T00:00:00.000Z");
  const observed = { ...defaultState(), chats: [recovered] };
  const latest = { ...defaultState(), chats: [{ ...original, title: "Новое имя" }] };
  const merged = mergeRuntimeState(observed, latest);

  assert.equal(merged.chats[0].title, "Новое имя");
  assert.equal(merged.chats[0].lastRecoveryReason, "frozen-tab");
  assert.equal(merged.chats[0].staleRecoveries, 1);
  assert.equal(merged.chats[0].lastHardRefreshAt, "2026-07-23T00:00:00.000Z");
});
