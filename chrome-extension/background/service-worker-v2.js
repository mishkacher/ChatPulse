import {
  appendLog,
  clampInterval,
  createChat,
  createSessionId,
  decide,
  defaultState,
  mergeRuntimeState,
  normalizeChatURL,
  normalizeState,
  planTabRecovery,
  recordDispatch,
  recordRecovery
} from "../lib/model-v2.js";

const STORAGE_KEY = "chatpulseState";
const ALARM_NAME = "chatpulse-monitor";
const CHATGPT_PATTERNS = ["https://chatgpt.com/*", "https://chat.openai.com/*"];
const TAB_LOAD_TIMEOUT_MS = 45_000;
const HYDRATION_TIMEOUT_MS = 20_000;
const CONTENT_MESSAGE_TIMEOUT_MS = 4_000;
const POST_RELOAD_SETTLE_MS = 750;
let activeCheck = null;

chrome.runtime.onInstalled.addListener(() => {
  void initialize("Установлено расширение ChatPulse");
});

chrome.runtime.onStartup.addListener(() => {
  void initialize("Chrome запущен: создана новая безопасная сессия наблюдения");
});

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === ALARM_NAME) void runCheck("alarm");
});

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  handleMessage(message)
    .then((result) => sendResponse({ ok: true, ...result }))
    .catch((error) => sendResponse({
      ok: false,
      error: error instanceof Error ? error.message : String(error)
    }));
  return true;
});

async function initialize(message) {
  let state = await loadState();
  state = appendLog({
    ...state,
    checkInProgress: false,
    sessionId: createSessionId()
  }, "info", message);
  state = await configureAlarm(state);
  await persistAndPublish(state);
}

async function handleMessage(message) {
  switch (message?.type) {
    case "GET_STATE":
      return { state: await loadState() };

    case "START_MONITORING": {
      let state = await loadState();
      state = appendLog({
        ...state,
        enabled: true,
        sessionId: createSessionId()
      }, "info", "Наблюдение запущено");
      state = await configureAlarm(state);
      await persistAndPublish(state);
      void runCheck("start");
      return { state };
    }

    case "STOP_MONITORING": {
      let state = await loadState();
      state = appendLog({
        ...state,
        enabled: false,
        checkInProgress: false,
        nextCheckAt: null
      }, "info", "Наблюдение остановлено");
      await chrome.alarms.clear(ALARM_NAME);
      await persistAndPublish(state);
      return { state };
    }

    case "CHECK_NOW":
      await runCheck("manual", true);
      return { state: await loadState() };

    case "ADD_CURRENT_CHAT":
      return { state: await addCurrentChat() };

    case "REMOVE_CHAT":
      return { state: await mutateChat(message.chatId, (state, index) => {
        const [removed] = state.chats.splice(index, 1);
        return appendLog(state, "info", `Чат «${removed.title}» удалён из ChatPulse`);
      }) };

    case "TOGGLE_CHAT":
      return { state: await mutateChat(message.chatId, (state, index) => {
        state.chats[index].enabled = !state.chats[index].enabled;
        const chat = state.chats[index];
        return appendLog(
          state,
          "info",
          `${chat.enabled ? "Включено" : "Отключено"} наблюдение за «${chat.title}»`
        );
      }) };

    case "OPEN_CHAT": {
      const state = await loadState();
      const chat = state.chats.find((candidate) => candidate.id === message.chatId);
      if (!chat) throw new Error("Чат не найден.");
      const tab = await chrome.tabs.create({ url: chat.url, active: true });
      chat.tabId = tab.id ?? null;
      if (Number.isInteger(tab.id)) await protectManagedTab(tab.id);
      await persistAndPublish(state);
      return { state };
    }

    case "UPDATE_SETTINGS":
      return { state: await updateSettings(message.patch || {}) };

    case "CLEAR_LOGS": {
      const state = { ...(await loadState()), logs: [] };
      await persistAndPublish(state);
      return { state };
    }

    default:
      throw new Error("Неизвестная команда расширения.");
  }
}

async function addCurrentChat() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  const normalizedURL = normalizeChatURL(tab?.url);
  if (!tab?.id || !normalizedURL) {
    throw new Error("Откройте конкретный чат ChatGPT в активной вкладке Chrome.");
  }

  await protectManagedTab(tab.id);
  let title = tab.title || "Чат ChatGPT";
  try {
    const response = await sendToContent(tab.id, { type: "CHATPULSE_INSPECT" }, { attempts: 2 });
    if (response?.snapshot?.title) title = response.snapshot.title;
  } catch {
    // Заголовок вкладки используется как безопасный fallback.
  }

  let state = await loadState();
  const index = state.chats.findIndex((chat) => chat.url === normalizedURL);
  if (index >= 0) {
    state.chats[index] = {
      ...state.chats[index],
      title,
      tabId: tab.id,
      enabled: true,
      lastObservedSessionId: null,
      lastHardRefreshAt: new Date().toISOString()
    };
    state = appendLog(state, "info", `Чат «${title}» обновлён и включён`);
  } else {
    state.chats.push(createChat({ title, url: normalizedURL, tabId: tab.id }));
    state = appendLog(state, "info", `Добавлен чат «${title}»`);
  }

  await persistAndPublish(state);
  return state;
}

async function updateSettings(patch) {
  let state = await loadState();
  if (Object.hasOwn(patch, "intervalMinutes")) {
    state.intervalMinutes = clampInterval(patch.intervalMinutes);
  }
  if (typeof patch.commandText === "string" && patch.commandText.trim()) {
    state.commandText = patch.commandText.trim();
  }
  if (patch.theme === "macos" || patch.theme === "preview") {
    state.theme = patch.theme;
  }
  state = appendLog(state, "info", "Настройки ChatPulse обновлены");
  state = await configureAlarm(state);
  await persistAndPublish(state);
  return state;
}

async function mutateChat(chatId, mutator) {
  let state = await loadState();
  const index = state.chats.findIndex((chat) => chat.id === chatId);
  if (index < 0) throw new Error("Чат не найден.");
  state = mutator(state, index) || state;
  await persistAndPublish(state);
  return state;
}

async function runCheck(source, allowWhenStopped = false) {
  if (activeCheck) return activeCheck;
  activeCheck = performCheck(source, allowWhenStopped).finally(() => {
    activeCheck = null;
  });
  return activeCheck;
}

async function performCheck(source, allowWhenStopped) {
  let observedState = await loadState();
  if (!observedState.enabled && !allowWhenStopped) return;

  observedState = appendLog(
    { ...observedState, checkInProgress: true },
    "debug",
    `Начата ${source === "manual" ? "ручная" : "плановая"} проверка`
  );
  await persistAndPublish(observedState);

  for (let index = 0; index < observedState.chats.length; index += 1) {
    const chat = observedState.chats[index];
    if (!chat.enabled) continue;

    try {
      let tab = await ensureChatTab(chat);
      chat.tabId = tab.id ?? null;

      const freshness = await obtainFreshSnapshot({
        tab,
        chat,
        intervalMinutes: observedState.intervalMinutes
      });
      tab = freshness.tab;
      let runtimeChat = { ...chat, tabId: tab.id ?? null };
      if (freshness.recoveryReason) {
        runtimeChat = recordRecovery(runtimeChat, freshness.recoveryReason);
        observedState = appendLog(
          observedState,
          "info",
          `${chat.title}: вкладка восстановлена (${recoveryDescription(freshness.recoveryReason)})`
        );
      }

      const result = decide(runtimeChat, freshness.snapshot, observedState.sessionId);
      observedState.chats[index] = result.chat;
      observedState = appendLog(
        observedState,
        decisionLevel(result.decision),
        `${chat.title}: ${decisionDescription(result.decision)}`
      );

      if (result.decision !== "send-continuation") continue;

      const latestState = await loadState();
      const liveChat = latestState.chats.find((candidate) => candidate.id === chat.id);
      if (!liveChat?.enabled || (!latestState.enabled && !allowWhenStopped)) {
        observedState = appendLog(
          observedState,
          "info",
          `Отправка в «${chat.title}» отменена: чат отключён или наблюдение остановлено`
        );
        continue;
      }

      const preflight = await obtainFreshSnapshot({
        tab: await chrome.tabs.get(tab.id),
        chat: observedState.chats[index],
        intervalMinutes: latestState.intervalMinutes,
        allowPeriodicRefresh: false
      });
      if (preflight.recoveryReason) {
        observedState.chats[index] = recordRecovery(
          observedState.chats[index],
          preflight.recoveryReason
        );
        observedState = appendLog(
          observedState,
          "info",
          `${chat.title}: вкладка восстановлена перед отправкой (${recoveryDescription(preflight.recoveryReason)})`
        );
      }

      const preflightDecision = decide(
        observedState.chats[index],
        preflight.snapshot,
        observedState.sessionId
      );
      observedState.chats[index] = preflightDecision.chat;
      if (preflightDecision.decision !== "send-continuation") {
        observedState = appendLog(
          observedState,
          "info",
          `Отправка в «${chat.title}» отменена после повторной проверки: ${decisionDescription(preflightDecision.decision)}`
        );
        continue;
      }

      const sendResponse = await sendToContent(preflight.tab.id, {
        type: "CHATPULSE_SEND",
        command: latestState.commandText
      }, { attempts: 2, timeoutMs: 15_000 });
      if (!sendResponse?.ok) throw new Error(sendResponse?.error || "Команда не отправлена.");

      const outcome = sendResponse.outcome === "confirmed"
        ? "confirmed"
        : "submitted-unconfirmed";
      observedState.chats[index] = recordDispatch(
        observedState.chats[index],
        preflightDecision.fingerprint,
        outcome
      );
      observedState = appendLog(
        observedState,
        outcome === "confirmed" ? "info" : "warning",
        outcome === "confirmed"
          ? `Команда отправлена в «${chat.title}»`
          : `Кнопка отправки нажата в «${chat.title}»; повтор для ответа заблокирован`
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      observedState.chats[index] = { ...observedState.chats[index], lastError: message };
      observedState = appendLog(observedState, "error", `${chat.title}: ${message}`);
    }
  }

  observedState = {
    ...observedState,
    checkInProgress: false,
    lastCheckAt: new Date().toISOString()
  };

  const latestState = await loadState();
  let merged = mergeRuntimeState(observedState, latestState);
  merged = await configureAlarm(merged);
  await persistAndPublish(merged);
}

async function ensureChatTab(chat) {
  if (Number.isInteger(chat.tabId)) {
    try {
      const tab = await chrome.tabs.get(chat.tabId);
      if (normalizeChatURL(tab.url) === chat.url) {
        await protectManagedTab(tab.id);
        return chrome.tabs.get(tab.id);
      }
    } catch {
      // Вкладка закрыта — ищем существующую или создаём новую.
    }
  }

  const tabs = await chrome.tabs.query({ url: CHATGPT_PATTERNS });
  const existing = tabs.find((tab) => normalizeChatURL(tab.url) === chat.url);
  if (existing?.id) {
    await protectManagedTab(existing.id);
    return chrome.tabs.get(existing.id);
  }

  const created = await chrome.tabs.create({ url: chat.url, active: false, pinned: false });
  if (!Number.isInteger(created.id)) throw new Error("Chrome не вернул идентификатор вкладки.");
  await protectManagedTab(created.id);
  return chrome.tabs.get(created.id);
}

async function protectManagedTab(tabId) {
  try {
    await chrome.tabs.update(tabId, { autoDiscardable: false });
  } catch {
    // Старые версии Chrome могут не принять autoDiscardable; восстановление всё равно работает.
  }
}

async function obtainFreshSnapshot({
  tab,
  chat,
  intervalMinutes,
  allowPeriodicRefresh = true
}) {
  if (!Number.isInteger(tab?.id)) throw new Error("У вкладки ChatGPT отсутствует идентификатор.");
  await protectManagedTab(tab.id);

  if (tab.discarded === true || tab.frozen === true) {
    const reason = tab.discarded === true ? "discarded-tab" : "frozen-tab";
    return recoverAndInspect(tab.id, reason);
  }

  await waitForTabComplete(tab.id, TAB_LOAD_TIMEOUT_MS);

  let snapshot = null;
  try {
    const response = await sendToContent(
      tab.id,
      { type: "CHATPULSE_INSPECT" },
      { attempts: 2, timeoutMs: CONTENT_MESSAGE_TIMEOUT_MS }
    );
    snapshot = response?.ok ? response.snapshot : null;
  } catch {
    snapshot = null;
  }

  const plan = planTabRecovery({
    tab,
    snapshot,
    chat: allowPeriodicRefresh ? chat : { ...chat, lastHardRefreshAt: new Date().toISOString() },
    intervalMinutes
  });

  if (plan.refresh) return recoverAndInspect(tab.id, plan.reason);
  if (!snapshot) throw new Error("Не удалось получить актуальное состояние страницы ChatGPT.");
  return { tab: await chrome.tabs.get(tab.id), snapshot, recoveryReason: null };
}

async function recoverAndInspect(tabId, reason) {
  await reloadTabAndWait(tabId, TAB_LOAD_TIMEOUT_MS);
  await delay(POST_RELOAD_SETTLE_MS);
  const snapshot = await waitForHydratedSnapshot(tabId, HYDRATION_TIMEOUT_MS);
  return {
    tab: await chrome.tabs.get(tabId),
    snapshot,
    recoveryReason: reason
  };
}

async function waitForHydratedSnapshot(tabId, timeoutMs) {
  const startedAt = Date.now();
  let lastSnapshot = null;
  let lastError = null;

  while (Date.now() - startedAt < timeoutMs) {
    try {
      const response = await sendToContent(
        tabId,
        { type: "CHATPULSE_INSPECT" },
        { attempts: 1, timeoutMs: CONTENT_MESSAGE_TIMEOUT_MS }
      );
      if (response?.ok && response.snapshot) {
        lastSnapshot = response.snapshot;
        const hydrated = lastSnapshot.pageReady
          && (!lastSnapshot.authenticated
            || lastSnapshot.messageCount > 0
            || lastSnapshot.hasComposer === true);
        if (hydrated) return lastSnapshot;
      }
    } catch (error) {
      lastError = error;
    }
    await delay(500);
  }

  if (lastSnapshot) return lastSnapshot;
  throw new Error(
    `Страница ChatGPT не восстановилась после обновления: ${lastError?.message || "DOM недоступен"}`
  );
}

async function waitForTabComplete(tabId, timeoutMs) {
  const current = await chrome.tabs.get(tabId);
  if (current.status === "complete" && current.discarded !== true) return current;

  return new Promise((resolve, reject) => {
    const timeout = setTimeout(
      () => finish(new Error("Вкладка ChatGPT не загрузилась за 45 секунд.")),
      timeoutMs
    );
    const onUpdated = (updatedTabId, changeInfo, updatedTab) => {
      if (updatedTabId === tabId && changeInfo.status === "complete") finish(null, updatedTab);
    };
    const onRemoved = (removedTabId) => {
      if (removedTabId === tabId) finish(new Error("Вкладка ChatGPT закрыта во время проверки."));
    };

    function finish(error, updatedTab) {
      clearTimeout(timeout);
      chrome.tabs.onUpdated.removeListener(onUpdated);
      chrome.tabs.onRemoved.removeListener(onRemoved);
      error ? reject(error) : resolve(updatedTab);
    }

    chrome.tabs.onUpdated.addListener(onUpdated);
    chrome.tabs.onRemoved.addListener(onRemoved);
  });
}

async function reloadTabAndWait(tabId, timeoutMs) {
  return new Promise((resolve, reject) => {
    let settled = false;
    const timeout = setTimeout(
      () => finish(new Error("Вкладка ChatGPT не обновилась за 45 секунд.")),
      timeoutMs
    );
    const onUpdated = (updatedTabId, changeInfo, updatedTab) => {
      if (updatedTabId === tabId && changeInfo.status === "complete") finish(null, updatedTab);
    };
    const onRemoved = (removedTabId) => {
      if (removedTabId === tabId) finish(new Error("Вкладка ChatGPT закрыта во время восстановления."));
    };

    function finish(error, updatedTab) {
      if (settled) return;
      settled = true;
      clearTimeout(timeout);
      chrome.tabs.onUpdated.removeListener(onUpdated);
      chrome.tabs.onRemoved.removeListener(onRemoved);
      error ? reject(error) : resolve(updatedTab);
    }

    chrome.tabs.onUpdated.addListener(onUpdated);
    chrome.tabs.onRemoved.addListener(onRemoved);
    chrome.tabs.reload(tabId).catch((error) => finish(error));
  });
}

async function sendToContent(
  tabId,
  message,
  { attempts = 3, timeoutMs = CONTENT_MESSAGE_TIMEOUT_MS } = {}
) {
  let lastError = null;
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try {
      const response = await withTimeout(
        chrome.tabs.sendMessage(tabId, message),
        timeoutMs,
        "content script не ответил вовремя"
      );
      if (response) return response;
    } catch (error) {
      lastError = error;
      if (attempt === 0) {
        try {
          await chrome.scripting.executeScript({
            target: { tabId },
            files: ["content/content-script.js"]
          });
        } catch {
          // Следующая попытка вернёт исходную понятную ошибку.
        }
      }
    }
    await delay(350);
  }
  throw new Error(
    `Не удалось связаться со страницей ChatGPT: ${lastError?.message || "content script недоступен"}`
  );
}

async function configureAlarm(state) {
  await chrome.alarms.clear(ALARM_NAME);
  if (!state.enabled) return { ...state, nextCheckAt: null };
  const intervalMinutes = clampInterval(state.intervalMinutes);
  await chrome.alarms.create(ALARM_NAME, {
    delayInMinutes: intervalMinutes,
    periodInMinutes: intervalMinutes
  });
  return {
    ...state,
    intervalMinutes,
    nextCheckAt: new Date(Date.now() + intervalMinutes * 60_000).toISOString()
  };
}

async function loadState() {
  const stored = await chrome.storage.local.get(STORAGE_KEY);
  return normalizeState(stored[STORAGE_KEY] || defaultState());
}

async function saveState(state) {
  await chrome.storage.local.set({ [STORAGE_KEY]: normalizeState(state) });
}

async function persistAndPublish(state) {
  await saveState(state);
  await updateBadge(state);
  try {
    await chrome.runtime.sendMessage({ type: "STATE_UPDATED", state });
  } catch {
    // Popup/options могут быть закрыты.
  }
}

async function updateBadge(state) {
  const text = state.checkInProgress ? "…" : state.enabled ? "ON" : "";
  await chrome.action.setBadgeText({ text });
  await chrome.action.setBadgeBackgroundColor({
    color: state.checkInProgress ? "#9B5CFF" : "#2C8CFF"
  });
  await chrome.action.setTitle({
    title: state.enabled
      ? `ChatPulse работает · ${state.chats.filter((chat) => chat.enabled).length} чатов`
      : "ChatPulse остановлен"
  });
}

function decisionLevel(decision) {
  return ["page-error", "not-authenticated"].includes(decision) ? "warning" : "debug";
}

function decisionDescription(decision) {
  return {
    disabled: "чат отключён",
    "page-not-ready": "страница ещё не готова",
    "not-authenticated": "в профиле Chrome не выполнен вход",
    "page-error": "на странице обнаружена ошибка",
    generating: "ответ ещё создаётся",
    "no-messages": "сообщения не найдены",
    "baseline-recorded": "зафиксировано исходное состояние новой сессии",
    "response-changed": "обнаружен новый ответ; ожидается следующая проверка",
    "waiting-for-assistant": "последнее сообщение принадлежит пользователю",
    "already-continued": "этот ответ уже получил команду",
    "send-continuation": "ответ стабилен и готов к продолжению"
  }[decision] || decision;
}

function recoveryDescription(reason) {
  return {
    "discarded-tab": "Chrome выгрузил вкладку из памяти",
    "frozen-tab": "Chrome заморозил вкладку",
    "content-unreachable": "content script перестал отвечать",
    "page-error": "страница сообщила об ошибке",
    "periodic-freshness": "плановое обновление содержимого",
    "stuck-generation": "генерация зависла более 20 минут",
    "missing-tab": "вкладка была потеряна"
  }[reason] || reason;
}

function withTimeout(promise, timeoutMs, message) {
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error(message)), timeoutMs);
    Promise.resolve(promise).then(
      (value) => {
        clearTimeout(timeout);
        resolve(value);
      },
      (error) => {
        clearTimeout(timeout);
        reject(error);
      }
    );
  });
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
