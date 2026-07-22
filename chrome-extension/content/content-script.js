(() => {
  if (globalThis.__chatPulseContentScriptInstalled) return;
  globalThis.__chatPulseContentScriptInstalled = true;

  const MESSAGE_SELECTOR = "[data-message-author-role], article[data-testid^='conversation-turn-']";
  const INPUT_SELECTORS = [
    "#prompt-textarea",
    "textarea[placeholder]",
    "textarea",
    "[contenteditable='true'][data-virtualkeyboard]",
    "[contenteditable='true'][role='textbox']",
    "[contenteditable='true']"
  ];

  chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
    if (!message || typeof message.type !== "string") return false;

    if (message.type === "CHATPULSE_PING") {
      sendResponse({ ok: true, url: location.href });
      return false;
    }

    if (message.type === "CHATPULSE_INSPECT") {
      sendResponse({ ok: true, snapshot: inspectPage() });
      return false;
    }

    if (message.type === "CHATPULSE_SEND") {
      sendCommand(String(message.command || ""))
        .then((result) => sendResponse({ ok: true, ...result }))
        .catch((error) => sendResponse({
          ok: false,
          error: error instanceof Error ? error.message : String(error)
        }));
      return true;
    }

    return false;
  });

  function inspectPage() {
    const messages = getMessages();
    const latest = messages.at(-1) || null;
    const latestRole = roleFor(latest);
    const latestText = normalizedText(latest);
    const latestId = latest?.getAttribute?.("data-message-id")
      || latest?.getAttribute?.("data-testid")
      || latest?.id
      || "";

    const title = (document.title || "Чат ChatGPT")
      .replace(/\s*[-|]\s*ChatGPT\s*$/i, "")
      .trim() || "Чат ChatGPT";

    return {
      title,
      url: location.href,
      latestRole,
      latestFingerprint: latest
        ? fnv1a(`${latestRole}|${latestId}|${latestText}`)
        : null,
      isGenerating: isGenerating(),
      errorDetected: hasPageError(),
      pageReady: document.readyState === "interactive" || document.readyState === "complete",
      authenticated: isAuthenticated(),
      messageCount: messages.length
    };
  }

  async function sendCommand(command) {
    const normalizedCommand = normalize(command);
    if (!normalizedCommand) throw new Error("Команда продолжения пуста.");
    if (!isAuthenticated()) throw new Error("В профиле Chrome не выполнен вход в ChatGPT.");
    if (isGenerating()) throw new Error("ChatGPT ещё создаёт ответ.");

    const input = findInput();
    if (!input) throw new Error("Поле ввода ChatGPT не найдено.");

    fillInput(input, command);
    const sendButton = await waitForSendButton(4_000);
    if (!sendButton) throw new Error("Кнопка отправки недоступна после заполнения поля.");

    sendButton.click();

    for (let attempt = 0; attempt < 20; attempt += 1) {
      await delay(500);
      if (latestUserMessageMatches(normalizedCommand)) {
        return { outcome: "confirmed" };
      }
    }

    return { outcome: "submitted-unconfirmed" };
  }

  function getMessages() {
    const elements = [...document.querySelectorAll(MESSAGE_SELECTOR)];
    return elements.filter((element, index) => {
      const parent = element.parentElement?.closest?.(MESSAGE_SELECTOR);
      if (parent && parent !== element) return false;
      return elements.indexOf(element) === index;
    });
  }

  function roleFor(element) {
    if (!element) return "unknown";
    const direct = element.getAttribute?.("data-message-author-role")?.toLowerCase();
    if (["assistant", "user", "system"].includes(direct)) return direct;

    const nested = element.querySelector?.("[data-message-author-role]");
    const nestedRole = nested?.getAttribute?.("data-message-author-role")?.toLowerCase();
    if (["assistant", "user", "system"].includes(nestedRole)) return nestedRole;

    const testId = element.getAttribute?.("data-testid") || "";
    if (/user/i.test(testId)) return "user";
    if (/assistant/i.test(testId)) return "assistant";
    return "unknown";
  }

  function normalizedText(element) {
    return normalize(element?.innerText || element?.textContent || "");
  }

  function normalize(value) {
    return String(value || "").replace(/\s+/g, " ").trim();
  }

  function fnv1a(value) {
    let hash = 2166136261;
    for (let index = 0; index < value.length; index += 1) {
      hash ^= value.charCodeAt(index);
      hash = Math.imul(hash, 16777619);
    }
    return (hash >>> 0).toString(16);
  }

  function isGenerating() {
    if (document.querySelector("button[data-testid='stop-button']")) return true;
    return [...document.querySelectorAll("button")].some((button) => {
      const label = normalize(button.getAttribute("aria-label") || button.innerText).toLowerCase();
      return /^(stop|остановить|停止|detener)/i.test(label);
    });
  }

  function hasPageError() {
    const text = [...document.querySelectorAll(
      "[role='alert'], [aria-live='assertive'], [data-testid*='error' i]"
    )]
      .map((element) => normalize(element.innerText || element.textContent).toLowerCase())
      .join("\n");

    return /(something went wrong|network error|failed to load|произошла ошибка|ошибка сети|не удалось загрузить)/i.test(text);
  }

  function isAuthenticated() {
    if (location.pathname.startsWith("/auth") || /login|signin/i.test(location.pathname)) return false;
    return Boolean(
      findInput()
      || document.querySelector("[data-message-author-role]")
      || document.querySelector("[data-testid='profile-button']")
      || document.querySelector("nav a[href^='/c/']")
    );
  }

  function findInput() {
    for (const selector of INPUT_SELECTORS) {
      const candidate = document.querySelector(selector);
      if (candidate && isVisible(candidate)) return candidate;
    }
    return null;
  }

  function isVisible(element) {
    const rect = element.getBoundingClientRect();
    const style = getComputedStyle(element);
    return rect.width > 0
      && rect.height > 0
      && style.visibility !== "hidden"
      && style.display !== "none";
  }

  function fillInput(input, command) {
    input.focus();

    if (input instanceof HTMLTextAreaElement || input instanceof HTMLInputElement) {
      const prototype = input instanceof HTMLTextAreaElement
        ? HTMLTextAreaElement.prototype
        : HTMLInputElement.prototype;
      const setter = Object.getOwnPropertyDescriptor(prototype, "value")?.set;
      if (!setter) throw new Error("Не удалось получить системный setter поля ввода.");
      setter.call(input, command);
      input.dispatchEvent(new InputEvent("input", {
        bubbles: true,
        inputType: "insertText",
        data: command
      }));
      input.dispatchEvent(new Event("change", { bubbles: true }));
      return;
    }

    const selection = getSelection();
    const range = document.createRange();
    range.selectNodeContents(input);
    selection?.removeAllRanges();
    selection?.addRange(range);

    let inserted = false;
    try {
      inserted = document.execCommand("insertText", false, command);
    } catch {
      inserted = false;
    }

    if (!inserted) {
      input.replaceChildren();
      const paragraph = document.createElement("p");
      paragraph.textContent = command;
      input.appendChild(paragraph);
    }

    input.dispatchEvent(new InputEvent("input", {
      bubbles: true,
      inputType: "insertText",
      data: command
    }));
  }

  async function waitForSendButton(timeoutMs) {
    const startedAt = Date.now();
    while (Date.now() - startedAt < timeoutMs) {
      const button = findSendButton();
      if (button && !button.disabled && button.getAttribute("aria-disabled") !== "true") {
        return button;
      }
      await delay(100);
    }
    return null;
  }

  function findSendButton() {
    const direct = document.querySelector(
      "button[data-testid='send-button'], button[aria-label*='Send' i], button[aria-label*='Отправ' i]"
    );
    if (direct && isVisible(direct)) return direct;

    return [...document.querySelectorAll("button")].find((button) => {
      const label = normalize(button.getAttribute("aria-label") || button.innerText);
      return /^(send|отправить)$/i.test(label) && isVisible(button);
    }) || null;
  }

  function latestUserMessageMatches(normalizedCommand) {
    const userMessages = getMessages().filter((message) => roleFor(message) === "user");
    const latest = userMessages.at(-1);
    return latest ? normalizedText(latest) === normalizedCommand : false;
  }

  function delay(milliseconds) {
    return new Promise((resolve) => setTimeout(resolve, milliseconds));
  }
})();
