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
  recordDispatch
} from "../lib/model-v2.js";

const STORAGE_KEY = "chatpulseState";
const ALARM_NAME = "chatpulse-monitor";
const CHATGPT_PATTERNS = ["https://chatgpt.com/*", "https://chat.openai.com/*"];
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

  let title = tab.title || "Чат ChatGPT";
  try {
    const response = await sendToContent(tab.id, { type: "CHATPULSE_INSPECT" });
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
      lastObservedSessionId: null
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
      const tab = await ensureChatTab(chat);
      chat.tabId = tab.id ?? null;
      await waitForTabComplete(tab.id, 45_000);

      const response = await sendToContent(tab.id, { type: "CHATPULSE_INSPECT" });
      if (!response?.ok || !response.snapshot) {
        throw new Error(response?.error || "Content script не вернул состояние страницы.");
      }

      const result = decide(chat, response.snapshot, observedState.sessionId);
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

      const sendResponse = await sendToContent(tab.id, {
        type: "CHATPULSE_SEND",
        command: latestState.commandText
      });
      if (!sendResponse?.ok) throw new Error(sendResponse?.error || "Команда не отправлена.");

      const outcome = sendResponse.outcome === "confirmed"
        ? "confirmed"
        : "submitted-unconfirmed";
      observedState.chats[index] = recordDispatch(
        observedState.chats[index],
        result.fingerprint,
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
      if (normalizeChatURL(tab.url) === chat.url) return tab;
    } catch {
      // Вкладка закрыта — ищем существующую или создаём новую.
    }
  }

  const tabs = await chrome.tabs.query({ url: CHATGPT_PATTERNS });
  const existing = tabs.find((tab) => normalizeChatURL(tab.url) === chat.url);
  if (existing) return existing;
  return chrome.tabs.create({ url: chat.url, active: false, pinned: false });
}

async function waitForTabComplete(tabId, timeoutMs) {
  const current = await chrome.tabs.get(tabId);
  if (current.status === "complete") return current;

  return new Promise((resolve, reject) => {
    const timeout = setTimeout(
      () => finish(new Error("Вкладка ChatGPT не загрузилась за 45 секунд.")),
      timeoutMs
    );
    const onUpdated = (updatedTabId, changeInfo, tab) => {
      if (updatedTabId === tabId && changeInfo.status === "complete") finish(null, tab);
    };
    const onRemoved = (removedTabId) => {
      if (removedTabId === tabId) finish(new Error("Вкладка ChatGPT закрыта во время проверки."));
    };

    function finish(error, tab) {
      clearTimeout(timeout);
      chrome.tabs.onUpdated.removeListener(onUpdated);
      chrome.tabs.onRemoved.removeListener(onRemoved);
      error ? reject(error) : resolve(tab);
    }

    chrome.tabs.onUpdated.addListener(onUpdated);
    chrome.tabs.onRemoved.addListener(onRemoved);
  });
}

async function sendToContent(tabId, message) {
  let lastError = null;
  for (let attempt = 0; attempt < 12; attempt += 1) {
    try {
      const response = await chrome.tabs.sendMessage(tabId, message);
      if (response) return response;
    } catch (error) {
      lastError = error;
      if (attempt === 1) {
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
    await delay(500);
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

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
