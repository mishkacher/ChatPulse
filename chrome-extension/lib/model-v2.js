export const DEFAULT_COMMAND = "продолжай и не останавливайся до технического лимита";
export const MIN_INTERVAL_MINUTES = 0.5;
export const MAX_INTERVAL_MINUTES = 1_440;
export const MAX_LOG_ENTRIES = 300;

export function createSessionId() {
  if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID();
  return `${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

export function clampInterval(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 5;
  return Math.min(Math.max(parsed, MIN_INTERVAL_MINUTES), MAX_INTERVAL_MINUTES);
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

export function createChat({ title, url, tabId = null }) {
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
    lastError: stringOrNull(raw.lastError)
  };
}

export function defaultState() {
  return {
    schemaVersion: 1,
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
    schemaVersion: 1,
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
  const updated = { ...chat, lastObservedAt: new Date().toISOString(), lastError: null };
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

function stringOrNull(value) {
  return typeof value === "string" && value.length ? value : null;
}

function isValidLog(value) {
  return value && typeof value === "object" && typeof value.message === "string";
}
