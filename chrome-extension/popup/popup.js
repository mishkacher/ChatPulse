const elements = {
  body: document.body,
  statusText: document.querySelector("#statusText"),
  monitorState: document.querySelector("#monitorState"),
  toggleButton: document.querySelector("#toggleButton"),
  addChatButton: document.querySelector("#addChatButton"),
  checkButton: document.querySelector("#checkButton"),
  intervalSelect: document.querySelector("#intervalSelect"),
  chatCount: document.querySelector("#chatCount"),
  chatList: document.querySelector("#chatList"),
  lastLog: document.querySelector("#lastLog"),
  themeButton: document.querySelector("#themeButton"),
  openOptionsButton: document.querySelector("#openOptionsButton"),
  chatTemplate: document.querySelector("#chatTemplate"),
  versionLabel: document.querySelector("#versionLabel")
};

let currentState = null;
let busy = false;

const manifest = chrome.runtime.getManifest();
elements.versionLabel.textContent = manifest.version_name || manifest.version;

void refresh();

chrome.runtime.onMessage.addListener((message) => {
  if (message?.type === "STATE_UPDATED" && message.state) {
    currentState = message.state;
    render();
  }
});

elements.toggleButton.addEventListener("click", () => runAction(
  currentState?.enabled ? "STOP_MONITORING" : "START_MONITORING"
));
elements.addChatButton.addEventListener("click", () => runAction("ADD_CURRENT_CHAT"));
elements.checkButton.addEventListener("click", () => runAction("CHECK_NOW"));
elements.intervalSelect.addEventListener("change", () => runAction("UPDATE_SETTINGS", {
  patch: { intervalMinutes: Number(elements.intervalSelect.value) }
}));
elements.themeButton.addEventListener("click", () => runAction("UPDATE_SETTINGS", {
  patch: { theme: currentState?.theme === "preview" ? "macos" : "preview" }
}));
elements.openOptionsButton.addEventListener("click", () => chrome.runtime.openOptionsPage());

async function refresh() {
  try {
    const response = await request("GET_STATE");
    currentState = response.state;
    render();
  } catch (error) {
    showError(error);
  }
}

async function runAction(type, payload = {}) {
  if (busy) return;
  setBusy(true);
  try {
    const response = await request(type, payload);
    if (response.state) currentState = response.state;
    render();
  } catch (error) {
    showError(error);
  } finally {
    setBusy(false);
  }
}

async function request(type, payload = {}) {
  const response = await chrome.runtime.sendMessage({ type, ...payload });
  if (!response?.ok) throw new Error(response?.error || "ChatPulse не ответил.");
  return response;
}

function render() {
  if (!currentState) return;

  elements.body.dataset.theme = currentState.theme === "preview" ? "preview" : "macos";
  elements.monitorState.textContent = currentState.checkInProgress
    ? "Проверка чатов…"
    : currentState.enabled
      ? "Работает"
      : "Остановлено";
  elements.statusText.textContent = statusSummary(currentState);
  elements.toggleButton.textContent = currentState.enabled ? "Остановить" : "Запустить";
  elements.toggleButton.dataset.running = String(currentState.enabled);
  elements.intervalSelect.value = String(currentState.intervalMinutes);
  elements.chatCount.textContent = String(currentState.chats.length);
  elements.themeButton.title = currentState.theme === "preview"
    ? "Переключить на системный скин macOS"
    : "Переключить на скин ChatPulse Preview";

  elements.chatList.replaceChildren();
  for (const chat of currentState.chats) {
    const fragment = elements.chatTemplate.content.cloneNode(true);
    const card = fragment.querySelector(".chat-card");
    const main = fragment.querySelector(".chat-main");
    const toggle = fragment.querySelector(".chat-toggle");
    const remove = fragment.querySelector(".chat-remove");

    card.dataset.enabled = String(chat.enabled);
    fragment.querySelector(".chat-title").textContent = chat.title;
    fragment.querySelector(".chat-status").textContent = chatStatus(chat);

    main.addEventListener("click", () => runAction("OPEN_CHAT", { chatId: chat.id }));
    toggle.addEventListener("click", () => runAction("TOGGLE_CHAT", { chatId: chat.id }));
    remove.addEventListener("click", () => runAction("REMOVE_CHAT", { chatId: chat.id }));
    elements.chatList.append(fragment);
  }

  const lastLog = currentState.logs.at(-1);
  elements.lastLog.textContent = lastLog
    ? `${formatTime(lastLog.at)} · ${lastLog.message}`
    : "Действий пока нет.";
}

function statusSummary(state) {
  if (state.checkInProgress) return "Идёт последовательная проверка";
  if (!state.enabled) return "Использует текущий профиль Chrome";
  const enabledCount = state.chats.filter((chat) => chat.enabled).length;
  if (!enabledCount) return "Добавьте или включите хотя бы один чат";
  if (state.nextCheckAt) return `Следующая проверка ${formatTime(state.nextCheckAt)}`;
  return `${enabledCount} чатов под наблюдением`;
}

function chatStatus(chat) {
  if (!chat.enabled) return "Наблюдение отключено";
  if (chat.lastError) return chat.lastError;
  if (chat.lastCommandAt) return `Команда отправлена ${formatTime(chat.lastCommandAt)}`;
  if (chat.lastRecoveryAt) return `Вкладка восстановлена ${formatTime(chat.lastRecoveryAt)}`;
  if (chat.lastObservedAt) return `Проверен ${formatTime(chat.lastObservedAt)}`;
  return "Ожидает первой проверки";
}

function formatTime(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "—";
  return new Intl.DateTimeFormat("ru-RU", {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit"
  }).format(date);
}

function setBusy(value) {
  busy = value;
  for (const button of document.querySelectorAll("button")) button.disabled = value;
  elements.intervalSelect.disabled = value;
}

function showError(error) {
  const message = error instanceof Error ? error.message : String(error);
  elements.statusText.textContent = message;
  elements.lastLog.textContent = `Ошибка: ${message}`;
}
