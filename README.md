# ChatPulse

[![CI](https://github.com/mishkacher/ChatPulse/actions/workflows/ci.yml/badge.svg)](https://github.com/mishkacher/ChatPulse/actions/workflows/ci.yml)
[![Release](https://github.com/mishkacher/ChatPulse/actions/workflows/release.yml/badge.svg)](https://github.com/mishkacher/ChatPulse/actions/workflows/release.yml)
[![GitHub release](https://img.shields.io/github/v/release/mishkacher/ChatPulse)](https://github.com/mishkacher/ChatPulse/releases/latest)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)](https://github.com/mishkacher/ChatPulse)
[![Universal 2](https://img.shields.io/badge/Universal_2-arm64%20%2B%20x86__64-blue)](https://github.com/mishkacher/ChatPulse/releases/latest)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange?logo=swift)](https://www.swift.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**ChatPulse** — нативная утилита строки меню macOS, которая следит за выбранными разговорами ChatGPT и при необходимости отправляет точную команду:

> продолжай и не останавливайся до технического лимита

Приложение использует собственный встроенный браузер на системном движке **WebKit**. Google Chrome, Playwright, Ollama, внешний ИИ и платные API не нужны.

![Обзор интерфейса ChatPulse](docs/chatpulse-overview.svg)

## Статус

Текущая версия: **0.4.0** — первый публичный релиз.

- macOS 13 Ventura и новее;
- Universal 2: `arm64` + `x86_64`;
- Mac с Apple Silicon и Intel;
- Swift 6;
- пять независимых полных CI-циклов на GitHub `macos-26` для каждого Pull Request;
- автоматическая публикация ZIP и SHA-256 после успешной проверки `main`;
- MIT License.

## Установка из GitHub Release

1. Откройте [последний релиз](https://github.com/mishkacher/ChatPulse/releases/latest).
2. Скачайте:
   - `ChatPulse-macOS-v0.4.0.zip`;
   - `ChatPulse-macOS-v0.4.0.zip.sha256`.
3. Проверьте checksum:

```bash
cd "$HOME/Downloads"
shasum -a 256 -c ChatPulse-macOS-v0.4.0.zip.sha256
```

Ожидаемый результат заканчивается словом `OK`.

4. Распакуйте ZIP.
5. Переместите `ChatPulse.app` в `/Applications` или `~/Applications`.
6. Запустите приложение.

### Gatekeeper

Сборка имеет ad-hoc подпись и hardened runtime, но пока не подписана Apple Developer ID и не нотарифицирована Apple. При первом запуске:

- нажмите `ChatPulse.app` правой кнопкой мыши → **Открыть**;
- либо подтвердите запуск в **System Settings → Privacy & Security**.

Не отключайте Gatekeeper полностью.

## Установка из исходников

Нужны Xcode Command Line Tools и Swift 6:

```bash
cd ~
rm -rf "$HOME/ChatPulse-install"
git clone --depth 1 https://github.com/mishkacher/ChatPulse.git "$HOME/ChatPulse-install"
cd "$HOME/ChatPulse-install"
bash scripts/install_app.sh
```

Скрипт собирает Universal 2 приложение и устанавливает его в `/Applications`, а без прав записи — в `~/Applications`.

## Первое использование

1. Нажмите значок ChatPulse в строке меню.
2. Откройте **«Браузер ChatPulse…»**.
3. Выберите скин.
4. Нажмите **«Войти ▾»**.
5. Используйте email / одноразовый код или заранее добавленный passkey.
6. Откройте нужный разговор ChatGPT.
7. Нажмите **«Добавить чат»**.
8. Выберите интервал.
9. Нажмите **«Запустить»**.

## Логика мониторинга

1. Первая проверка только запоминает текущий ответ.
2. Новый ответ также сначала только фиксируется.
3. Команда отправляется на следующей проверке, только если ответ завершён и не изменился.
4. После фактического клика отпечаток ответа помечается обработанным.
5. Один ответ не может получить команду повторно.
6. Перед отправкой повторно проверяется, что мониторинг не остановлен, а чат не удалён и не отключён.

Это исключает немедленный перезапуск чата после нового ответа.

## Возможности

- несколько сохранённых разговоров;
- интервалы 1, 2, 5, 10, 15 и 30 минут;
- собственный интервал от 30 секунд до 24 часов;
- ручная проверка;
- динамическая кнопка **«Запустить / Остановить»**;
- локальный журнал действий;
- вход по email / коду и passkey;
- постоянная WebKit-сессия;
- окно **«О ChatPulse…»** с версией и build number;
- скины **macOS** и **ChatPulse Preview**.

## Скины

### macOS

Системные материалы и автоматическое следование светлому или тёмному режиму macOS.

### ChatPulse Preview

- фон: `#071126 → #11183A → #24123D`;
- акцент: `#2C8CFF → #9B5CFF`;
- светлый текст;
- тёмные контролы;
- градиентная кнопка добавления чата.

Скин меняет только оболочку ChatPulse, а не страницу ChatGPT.

## Конфиденциальность

ChatPulse:

- не читает cookies Safari или Chrome;
- хранит сессию в отдельном WebKit-профиле;
- не сохраняет пароль, email, коды или passkey;
- не читает почту;
- не сохраняет всю переписку;
- не отправляет телеметрию;
- не использует внешний ИИ или платный API;
- принимает URL только официальных доменов ChatGPT;
- не обходит технические лимиты.

Подробнее: [SECURITY.md](SECURITY.md).

## Настройки

```text
~/Library/Application Support/ChatPulse/settings.json
```

Скин хранится отдельно в `UserDefaults` под ключом `ChatPulse.ui.skin`.

## Проверка проекта

```bash
make test
make audit
make build
make preflight
```

Релизный preflight проверяет:

- debug- и release-тесты;
- 20 quality gates;
- shell-скрипты;
- Universal 2 сборку;
- архитектуры `arm64` и `x86_64`;
- версию и build number;
- `Info.plist`, иконку и bundle identifier;
- code signature и hardened runtime.

CI выполняет полный набор в пяти независимых окружениях `macos-26`. После зелёной CI основной ветки workflow `Release` повторяет preflight, создаёт тег, ZIP, checksum и GitHub Release.

## Известные ограничения

- изменения DOM ChatGPT могут потребовать обновления селекторов;
- email-вход зависит от конфигурации аккаунта;
- passkey должен быть зарегистрирован заранее;
- Google OAuth внутри встроенного WebView намеренно не поддерживается;
- системное меню строки состояния оформляется macOS;
- релиз пока не нотарифицирован Apple;
- приложение не обходит и не ускоряет сброс лимитов.

## Документация

- [Установка](docs/SETUP.md)
- [Архитектура](docs/ARCHITECTURE.md)
- [План тестирования](docs/TEST_PLAN.md)
- [Релизный чек-лист](docs/RELEASE_CHECKLIST.md)
- [История изменений](CHANGELOG.md)
- [Поддержка](SUPPORT.md)
- [Безопасность](SECURITY.md)

## Удаление

```bash
bash scripts/uninstall_app.sh
```

## Лицензия

MIT License. См. [LICENSE](LICENSE).
