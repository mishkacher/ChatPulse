import assert from "node:assert/strict";
import { readFile, stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const extensionRoot = path.join(root, "chrome-extension");
const manifestPath = path.join(extensionRoot, "manifest.json");
const manifest = JSON.parse(await readFile(manifestPath, "utf8"));

assert.equal(manifest.manifest_version, 3, "Требуется Manifest V3");
assert.equal(manifest.name, "ChatPulse");
assert.equal(manifest.version, "0.5.0");
assert.equal(manifest.background?.type, "module");
assert.equal(manifest.background?.service_worker, "background/service-worker.js");
assert.equal(manifest.action?.default_popup, "popup/popup.html");
assert.equal(manifest.options_page, "options/options.html");

const permissions = new Set(manifest.permissions || []);
for (const required of ["alarms", "scripting", "storage", "tabs"]) {
  assert.ok(permissions.has(required), `Отсутствует разрешение ${required}`);
}
for (const forbidden of ["cookies", "history", "webRequest", "debugger", "nativeMessaging"]) {
  assert.ok(!permissions.has(forbidden), `Лишнее чувствительное разрешение ${forbidden}`);
}

const hosts = new Set(manifest.host_permissions || []);
assert.deepEqual(
  [...hosts].sort(),
  ["https://chat.openai.com/*", "https://chatgpt.com/*"],
  "Доступ должен быть ограничен официальными доменами ChatGPT"
);
assert.ok(!JSON.stringify(manifest).includes("<all_urls>"), "Запрещён широкий доступ <all_urls>");
assert.ok(!JSON.stringify(manifest).includes("http://*/*"), "Запрещён общий HTTP-доступ");

const requiredFiles = [
  "manifest.json",
  "assets/logo.svg",
  "lib/model.js",
  "background/service-worker.js",
  "content/content-script.js",
  "popup/popup.html",
  "popup/popup.css",
  "popup/popup.js",
  "options/options.html",
  "options/options.css",
  "options/options.js"
];

for (const relativePath of requiredFiles) {
  const file = path.join(extensionRoot, relativePath);
  const metadata = await stat(file);
  assert.ok(metadata.isFile() && metadata.size > 0, `Файл отсутствует или пуст: ${relativePath}`);
}

const model = await readFile(path.join(extensionRoot, "lib/model.js"), "utf8");
const background = await readFile(path.join(extensionRoot, "background/service-worker.js"), "utf8");
const content = await readFile(path.join(extensionRoot, "content/content-script.js"), "utf8");
const popupCSS = await readFile(path.join(extensionRoot, "popup/popup.css"), "utf8");
const optionsCSS = await readFile(path.join(extensionRoot, "options/options.css"), "utf8");

assert.ok(model.includes("продолжай и не останавливайся до технического лимита"));
assert.ok(model.includes("lastCommandedFingerprint"));
assert.ok(model.includes("submitted-unconfirmed"));
assert.ok(model.includes("lastObservedSessionId"));
assert.ok(background.includes("mergeRuntimeState"));
assert.ok(background.includes("liveChat?.enabled"));
assert.ok(background.includes("chrome.alarms"));
assert.ok(background.includes("chrome.tabs.create"));
assert.ok(content.includes("CHATPULSE_INSPECT"));
assert.ok(content.includes("CHATPULSE_SEND"));
assert.ok(content.includes("data-message-author-role"));
assert.ok(content.includes("send-button"));

for (const color of ["#071126", "#11183a", "#24123d", "#2c8cff", "#9b5cff"]) {
  assert.ok(
    popupCSS.toLowerCase().includes(color) && optionsCSS.toLowerCase().includes(color),
    `В обоих интерфейсах отсутствует цвет превью ${color}`
  );
}

console.log("Manifest V3 и структура Chrome-расширения прошли статический аудит.");
