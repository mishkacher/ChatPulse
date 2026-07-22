export const DEFAULT_COMMAND = "продолжай и не останавливайся до технического лимита";
export const MIN_INTERVAL_MINUTES = 0.5;
export const MAX_INTERVAL_MINUTES = 1_440;
export const MAX_LOG_ENTRIES = 300;
export const MIN_REFRESH_INTERVAL_MS = 5 * 60_000;
export const MAX_REFRESH_INTERVAL_MS = 15 * 60_000;
export const STUCK_GENERATION_MS = 20 * 60_000;

export function createSessionId() {
  if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID();
  return `${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

export function clampInterval(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 5;
  return Math.min(Math.max(parsed, MIN_INTERVAL_MINUTES), MAX_INTERVAL_MINUTES);
}

export function refreshIntervalMs(intervalMinutes) {
  const requested = clampInterval(intervalMinutes) * 3 * 60_000;
  return Math.min(MAX_REFRESH_INTERVAL_MS, Math.max(MIN_REFRESH_INTERVAL_MS, requested));
}

export function normalizeChatURL(rawValue) {
  try {
    const url = new URL(rawValue);
    const host = url.hostname.toLowerCase();
    if (host !== "chatgpt.com" && host !== "chat.openai.com") return null;
    const parts = url.pathname.split("/").filter(Boolean);
    const conversationIndex = parts.findIndex((part, index) => part === "c" && parts[index + 1]);
    if (conversationIndex < 0) return null;
    return `https://chatgpt.com/${parts.slice(0, conversationIndex + 2).join("/")}`;
  } catch {
    return null;
  }
}

export function createChat({ title, url, tabId = null, now = new Date().toISOString() }) {
  const normalizedURL = normalizeChatURL(url);
  if (!normalizedURL) throw new Error("Открыта не страница конкретного чата ChatGPT.");
  return {
    id: createSessionId(),
    title: String(title || "Чат ChatGPT").trim() || "Чат ChatGPT",
    url: normalizedURL,
    enabled: true,
    tabId: Number.isInteger(tabId) ? tabId : null,
    lastObservedFingerprint: null,
    lastCommandedFingerprint: null,
    lastObservedAt: null,
    lastCommandAt: null,
    lastDispatchOutcome: null,
    lastObservedSessionId: null,
    lastSnapshotAt: null,
    lastHardRefreshAt: now,
    lastRecoveryAt: null,
    lastRecoveryReason: null,
    staleRecoveries: 0,
    lastError: null
  };
}

export function normalizeChat(raw) {
  const normalizedURL = normalizeChatURL(raw?.url);
  if (!normalizedURL) return null;
  return {
    id: typeof raw.id === "string" && raw.id ? raw.id : createSessionId(),
    title: typeof raw.title === "string" && raw.title.trim() ? raw.title.trim() : "Чат ChatGPT",
    url: normalizedURL,
    enabled: raw.enabled !== false,
    tabId: Number.isInteger(raw.tabId) ? raw.tabId : null,
    lastObservedFingerprint: stringOrNull(raw.lastObservedFingerprint),
    lastCommandedFingerprint: stringOrNull(raw.lastCommandedFingerprint),
    lastObservedAt: stringOrNull(raw.lastObservedAt),
    lastCommandAt: stringOrNull(raw.lastCommandAt),
    lastDispatchOutcome: stringOrNull(raw.lastDispatchOutcome),
    lastObservedSessionId: stringOrNull(raw.lastObservedSessionId),
    lastSnapshotAt: stringOrNull(raw.lastSnapshotAt),
    lastHardRefreshAt: stringOrNull(raw.lastHardRefreshAt),
    lastRecoveryAt: stringOrNull(raw.lastRecoveryAt),
    lastRecoveryReason: stringOrNull(raw.lastRecoveryReason),
    staleRecoveries: nonNegativeInteger(raw.staleRecoveries),
    lastError: stringOrNull(raw.lastError)
  };
}

export function defaultState() {
  return {
    schemaVersion: 2,
    enabled: false,
    checkInProgress: false,
    intervalMinutes: 5,
    commandText: DEFAULT_COMMAND,
    theme: "macos",
    sessionId: createSessionId(),
    lastCheckAt: null,
    nextCheckAt: null,
    chats: [],
    logs: []
  };
}

export function normalizeState(raw) {
  const fallback = defaultState();
  return {
    schemaVersion: 2,
    enabled: raw?.enabled === true,
    checkInProgress: raw?.checkInProgress === true,
    intervalMinutes: clampInterval(raw?.intervalMinutes ?? fallback.intervalMinutes),
    commandText: typeof raw?.commandText === "string" && raw.commandText.trim()
      ? raw.commandText.trim()
      : DEFAULT_COMMAND,
    theme: raw?.theme === "preview" ? "preview" : "macos",
    sessionId: typeof raw?.sessionId === "string" && raw.sessionId ? raw.sessionId : fallback.sessionId,
    lastCheckAt: stringOrNull(raw?.lastCheckAt),
    nextCheckAt: stringOrNull(raw?.nextCheckAt),
    chats: Array.isArray(raw?.chats) ? raw.chats.map(normalizeChat).filter(Boolean) : [],
    logs: Array.isArray(raw?.logs)
      ? raw.logs.filter(isValidLog).slice(-MAX_LOG_ENTRIES)
      : []
  };
}

export function appendLog(state, level, message, details = null) {
  return {
    ...state,
    logs: [...state.logs, {
      id: createSessionId(),
      at: new Date().toISOString(),
      level,
      message: String(message),
      details: details ? String(details) : null
    }].slice(-MAX_LOG_ENTRIES)
  };
}

export function decide(chat, snapshot, sessionId) {
  const observedAt = stringOrNull(snapshot?.observedAt) || new Date().toISOString();
  const updated = {
    ...chat,
    lastObservedAt: new Date().toISOString(),
    lastSnapshotAt: observedAt,
    lastError: null
  };
  if (!chat.enabled) return { chat: updated, decision: "disabled" };
  if (!snapshot?.pageReady) return { chat: updated, decision: "page-not-ready" };
  if (!snapshot?.authenticated) return { chat: updated, decision: "not-authenticated" };
  if (snapshot.errorDetected) return { chat: updated, decision: "page-error" };
  if (snapshot.isGenerating) return { chat: updated, decision: "generating" };

  const fingerprint = stringOrNull(snapshot.latestFingerprint);
  if (!fingerprint) return { chat: updated, decision: "no-messages" };
  if (chat.lastObservedSessionId !== sessionId) {
    return {
      chat: { ...updated, lastObservedSessionId: sessionId, lastObservedFingerprint: fingerprint },
      decision: "baseline-recorded"
    };
  }
  if (chat.lastObservedFingerprint !== fingerprint) {
    return {
      chat: { ...updated, lastObservedFingerprint: fingerprint },
      decision: "response-changed"
    };
  }
  if (snapshot.latestRole !== "assistant") {
    return { chat: updated, decision: "waiting-for-assistant" };
  }
  if (chat.lastCommandedFingerprint === fingerprint) {
    return { chat: updated, decision: "already-continued" };
  }
  return { chat: updated, decision: "send-continuation", fingerprint };
}

export function planTabRecovery({ tab, snapshot, chat, intervalMinutes, now = Date.now() }) {
  if (!tab || !Number.isInteger(tab.id)) return { refresh: true, reason: "missing-tab" };
  if (tab.discarded === true) return { refresh: true, reason: "discarded-tab" };
  if (tab.frozen === true) return { refresh: true, reason: "frozen-tab" };

  // Никогда не обновляем активную вкладку автоматически: пользователь может читать,
  // выделять текст или работать с интерфейсом, даже если content script временно недоступен.
  if (tab.active === true) return { refresh: false, reason: null };
  if (!snapshot) return { refresh: true, reason: "content-unreachable" };

  const hasDraft = snapshot.hasDraft === true;
  if (hasDraft) return { refresh: false, reason: null };
  if (snapshot.errorDetected) return { refresh: true, reason: "page-error" };

  const generationAgeMs = finiteNonNegative(snapshot.generationAgeMs);
  if (snapshot.isGenerating && generationAgeMs >= STUCK_GENERATION_MS) {
    return { refresh: true, reason: "stuck-generation" };
  }
  if (snapshot.isGenerating) return { refresh: false, reason: null };

  const lastRefreshMs = timestampOrZero(chat?.lastHardRefreshAt);
  const elapsedMs = Math.max(0, now - lastRefreshMs);
  if (elapsedMs >= refreshIntervalMs(intervalMinutes)) {
    return { refresh: true, reason: "periodic-freshness" };
  }
  return { refresh: false, reason: null };
}

export function recordRecovery(chat, reason, at = new Date().toISOString()) {
  return {
    ...chat,
    lastHardRefreshAt: at,
    lastRecoveryAt: at,
    lastRecoveryReason: String(reason || "unknown"),
    staleRecoveries: nonNegativeInteger(chat?.staleRecoveries) + 1,
    lastError: null
  };
}

export function recordDispatch(chat, fingerprint, outcome) {
  return {
    ...chat,
    lastCommandedFingerprint: fingerprint,
    lastCommandAt: new Date().toISOString(),
    lastDispatchOutcome: outcome,
    lastError: outcome === "confirmed" ? null : "Отправка нажата, но DOM не подтвердил сообщение"
  };
}

export function mergeRuntimeState(observedState, latestState) {
  const observedById = new Map(observedState.chats.map((chat) => [chat.id, chat]));
  return {
    ...latestState,
    checkInProgress: false,
    lastCheckAt: observedState.lastCheckAt,
    logs: mergeLogs(latestState.logs, observedState.logs),
    chats: latestState.chats.map((latestChat) => {
      const observed = observedById.get(latestChat.id);
      if (!observed) return latestChat;
      return {
        ...latestChat,
        tabId: observed.tabId,
        lastObservedFingerprint: observed.lastObservedFingerprint,
        lastCommandedFingerprint: observed.lastCommandedFingerprint,
        lastObservedAt: observed.lastObservedAt,
        lastCommandAt: observed.lastCommandAt,
        lastDispatchOutcome: observed.lastDispatchOutcome,
        lastObservedSessionId: observed.lastObservedSessionId,
        lastSnapshotAt: observed.lastSnapshotAt,
        lastHardRefreshAt: observed.lastHardRefreshAt,
        lastRecoveryAt: observed.lastRecoveryAt,
        lastRecoveryReason: observed.lastRecoveryReason,
        staleRecoveries: observed.staleRecoveries,
        lastError: observed.lastError
      };
    })
  };
}

function mergeLogs(latestLogs, observedLogs) {
  const byId = new Map();
  for (const log of [...latestLogs, ...observedLogs]) {
    if (!isValidLog(log)) continue;
    const key = typeof log.id === "string" && log.id
      ? log.id
      : `${log.at || ""}|${log.level || ""}|${log.message}`;
    byId.set(key, log);
  }
  return [...byId.values()]
    .sort((left, right) => String(left.at || "").localeCompare(String(right.at || "")))
    .slice(-MAX_LOG_ENTRIES);
}

function timestampOrZero(value) {
  const parsed = Date.parse(String(value || ""));
  return Number.isFinite(parsed) ? parsed : 0;
}

function finiteNonNegative(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : 0;
}

function nonNegativeInteger(value) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed >= 0 ? parsed : 0;
}

function stringOrNull(value) {
  return typeof value === "string" && value.length ? value : null;
}

function isValidLog(value) {
  return value && typeof value === "object" && typeof value.message === "string";
}
