const ui = {
  body: document.body,
  themeSelect: document.querySelector("#themeSelect"),
  toggleButton: document.querySelector("#toggleButton"),
  statusValue: document.querySelector("#statusValue"),
  statusDetail: document.querySelector("#statusDetail"),
  chatMetric: document.querySelector("#chatMetric"),
  lastCheckMetric: document.querySelector("#lastCheckMetric"),
  nextCheckMetric: document.querySelector("#nextCheckMetric"),
  commandField: document.querySelector("#commandField"),
  intervalSelect: document.querySelector("#intervalSelect"),
  checkButton: document.querySelector("#checkButton"),
  saveButton: document.querySelector("#saveButton"),
  addCurrentButton: document.querySelector("#addCurrentButton"),
  addCurrentTopButton: document.querySelector("#addCurrentTopButton"),
  clearLogsButton: document.querySelector("#clearLogsButton"),
  messageBar: document.querySelector("#messageBar"),
  chatTable: document.querySelector("#chatTable"),
  logList: document.querySelector("#logList"),
  chatRowTemplate: document.querySelector("#chatRowTemplate"),
  logTemplate: document.querySelector("#logTemplate"),
  versionLabel: document.querySelector("#versionLabel")
};

let state = null;
let busy = false;
let messageTimer = null;
let commandDirty = false;
let intervalDirty = false;

const manifest = chrome.runtime.getManifest();
ui.versionLabel.textContent = `ChatPulse ${manifest.version_name || manifest.version}`;

void refresh();

chrome.runtime.onMessage.addListener((message) => {
  if (message?.type === "STATE_UPDATED" && message.state) {
    state = message.state;
    render();
  }
});

ui.toggleButton.addEventListener("click", () => action(
  state?.enabled ? "STOP_MONITORING" : "START_MONITORING"
));
ui.checkButton.addEventListener("click", () => action("CHECK_NOW"));
ui.addCurrentButton.addEventListener("click", () => action("ADD_CURRENT_CHAT"));
ui.addCurrentTopButton.addEventListener("click", () => action("ADD_CURRENT_CHAT"));
ui.clearLogsButton.addEventListener("click", () => action("CLEAR_LOGS"));
ui.commandField.addEventListener("input", () => {
  commandDirty = ui.commandField.value !== (state?.commandText || "");
});
ui.intervalSelect.addEventListener("change", () => {
  intervalDirty = Number(ui.intervalSelect.value) !== Number(state?.intervalMinutes);
});
ui.saveButton.addEventListener("click", () => action("UPDATE_SETTINGS", {
  patch: {
    commandText: ui.commandField.value,
    intervalMinutes: Number(ui.intervalSelect.value),
    theme: ui.themeSelect.value
  }
}));
ui.themeSelect.addEventListener("change", () => {
  ui.body.dataset.theme = ui.themeSelect.value === "preview" ? "preview" : "macos";
  void action("UPDATE_SETTINGS", { patch: { theme: ui.themeSelect.value } }, false);
});

async function refresh() {
  try {
    const response = await request("GET_STATE");
    state = response.state;
    render(true);
  } catch (error) {
    showMessage(errorMessage(error), "error");
  }
}

async function action(type, payload = {}, showSuccess = true) {
  if (busy) return;
  setBusy(true);
  try {
    const response = await request(type, payload);
    if (response.state) state = response.state;
    if (type === "UPDATE_SETTINGS" && Object.hasOwn(payload?.patch || {}, "commandText")) {
      commandDirty = false;
      intervalDirty = false;
    }
    render(type === "GET_STATE");
    if (showSuccess) showMessage(successMessage(type), "info");
  } catch (error) {
    showMessage(errorMessage(error), "error");
  } finally {
    setBusy(false);
  }
}

async function request(type, payload = {}) {
  const response = await chrome.runtime.sendMessage({ type, ...payload });
  if (!response?.ok) throw new Error(response?.error || "Фоновый процесс ChatPulse не ответил.");
  return response;
}

function render(initial = false) {
  if (!state) return;

  ui.body.dataset.theme = state.theme === "preview" ? "preview" : "macos";
  ui.themeSelect.value = state.theme;
  ui.toggleButton.textContent = state.enabled ? "Остановить" : "Запустить";
  ui.toggleButton.dataset.running = String(state.enabled);

  ui.statusValue.textContent = state.checkInProgress
    ? "Проверка…"
    : state.enabled
      ? "Работает"
      : "Остановлен";
  ui.statusDetail.textContent = state.enabled
    ? `${state.chats.filter((chat) => chat.enabled).length} активных чатов · профиль Chrome`
    : "Фоновый таймер не активен";
  ui.chatMetric.textContent = String(state.chats.filter((chat) => chat.enabled).length);
  ui.lastCheckMetric.textContent = state.lastCheckAt ? formatDateTime(state.lastCheckAt) : "—";
  ui.nextCheckMetric.textContent = `Следующая: ${state.nextCheckAt ? formatDateTime(state.nextCheckAt) : "—"}`;

  if (initial || !commandDirty) {
    ui.commandField.value = state.commandText;
  }
  ensureIntervalOption(state.intervalMinutes);
  if (initial || !intervalDirty) {
    ui.intervalSelect.value = String(state.intervalMinutes);
  }

  renderChats();
  renderLogs();
}

function renderChats() {
  ui.chatTable.replaceChildren();

  for (const chat of state.chats) {
    const fragment = ui.chatRowTemplate.content.cloneNode(true);
    const row = fragment.querySelector(".chat-row");
    const openButton = fragment.querySelector(".open-chat");
    const toggleButton = fragment.querySelector(".toggle-chat");
    const removeButton = fragment.querySelector(".remove-chat");

    row.dataset.enabled = String(chat.enabled);
    fragment.querySelector(".chat-title").textContent = chat.title;
    fragment.querySelector(".chat-url").textContent = chat.url;
    fragment.querySelector(".chat-runtime-text").textContent = runtimeText(chat);
    toggleButton.textContent = chat.enabled ? "Отключить" : "Включить";

    openButton.addEventListener("click", () => action("OPEN_CHAT", { chatId: chat.id }));
    toggleButton.addEventListener("click", () => action("TOGGLE_CHAT", { chatId: chat.id }));
    removeButton.addEventListener("click", async () => {
      if (!confirm(`Удалить чат «${chat.title}» из ChatPulse?`)) return;
      await action("REMOVE_CHAT", { chatId: chat.id });
    });

    ui.chatTable.append(fragment);
  }
}

function renderLogs() {
  ui.logList.replaceChildren();
  const recentLogs = [...state.logs].reverse().slice(0, 100);

  for (const log of recentLogs) {
    const fragment = ui.logTemplate.content.cloneNode(true);
    const entry = fragment.querySelector(".log-entry");
    entry.dataset.level = log.level || "debug";
    fragment.querySelector("time").textContent = formatDateTime(log.at);
    fragment.querySelector(".log-level").textContent = levelLabel(log.level);
    fragment.querySelector("p").textContent = log.message;
    ui.logList.append(fragment);
  }
}

function runtimeText(chat) {
  if (!chat.enabled) return "Наблюдение отключено";
  if (chat.lastError) return `Ошибка: ${chat.lastError}`;
  if (chat.lastRecoveryAt && (!chat.lastCommandAt || chat.lastRecoveryAt > chat.lastCommandAt)) {
    return `Вкладка восстановлена ${formatDateTime(chat.lastRecoveryAt)}`;
  }
  if (chat.lastCommandAt) {
    const outcome = chat.lastDispatchOutcome === "confirmed" ? "подтверждено" : "клик выполнен";
    return `Отправлено ${formatDateTime(chat.lastCommandAt)} · ${outcome}`;
  }
  if (chat.lastObservedAt) return `Проверен ${formatDateTime(chat.lastObservedAt)}`;
  return "Ожидает первой безопасной проверки";
}

function ensureIntervalOption(value) {
  const raw = String(value);
  if ([...ui.intervalSelect.options].some((option) => option.value === raw)) return;
  const option = document.createElement("option");
  option.value = raw;
  option.textContent = `${value} мин`;
  ui.intervalSelect.append(option);
}

function successMessage(type) {
  const messages = {
    START_MONITORING: "Наблюдение запущено. Первая проверка новой сессии будет пассивной.",
    STOP_MONITORING: "Наблюдение остановлено.",
    CHECK_NOW: "Ручная проверка завершена.",
    ADD_CURRENT_CHAT: "Последний использованный чат ChatGPT добавлен или обновлён.",
    REMOVE_CHAT: "Чат удалён.",
    TOGGLE_CHAT: "Состояние чата изменено.",
    UPDATE_SETTINGS: "Настройки сохранены.",
    CLEAR_LOGS: "Журнал очищен.",
    OPEN_CHAT: "Чат открыт в Chrome."
  };
  return messages[type] || "Готово.";
}

function levelLabel(level) {
  return {
    debug: "ОТЛАДКА",
    info: "ИНФО",
    warning: "ВНИМАНИЕ",
    error: "ОШИБКА"
  }[level] || "СОБЫТИЕ";
}

function formatDateTime(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return new Intl.DateTimeFormat("ru-RU", {
    day: "2-digit",
    month: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit"
  }).format(date);
}

function setBusy(value) {
  busy = value;
  for (const control of document.querySelectorAll("button, select, textarea")) {
    control.disabled = value;
  }
}

function showMessage(message, level) {
  clearTimeout(messageTimer);
  ui.messageBar.hidden = false;
  ui.messageBar.dataset.level = level;
  ui.messageBar.textContent = message;
  messageTimer = setTimeout(() => {
    ui.messageBar.hidden = true;
  }, 5_000);
}

function errorMessage(error) {
  return error instanceof Error ? error.message : String(error);
}
