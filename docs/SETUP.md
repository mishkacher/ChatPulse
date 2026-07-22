# Установка и устранение проблем

## Системные требования

Для готового релиза:

- macOS 13 Ventura или новее;
- аккаунт ChatGPT;
- подключение к интернету.

Xcode и Swift нужны только для самостоятельной сборки из исходников.

## Установка готового релиза

1. Откройте страницу GitHub Releases.
2. Скачайте `ChatPulse-macOS-v0.4.0.zip` и `ChatPulse-macOS-v0.4.0.zip.sha256`.
3. При желании проверьте checksum:

```bash
cd "$HOME/Downloads"
shasum -a 256 -c ChatPulse-macOS-v0.4.0.zip.sha256
```

Ожидаемый результат:

```text
ChatPulse-macOS-v0.4.0.zip: OK
```

4. Распакуйте ZIP.
5. Переместите `ChatPulse.app` в `/Applications` или `~/Applications`.
6. Запустите приложение.

## Первый запуск и Gatekeeper

Релиз `0.4.0` подписан ad-hoc с hardened runtime, но не подписан Apple Developer ID и не нотарифицирован Apple. Поэтому macOS может запросить ручное подтверждение.

Используйте один из стандартных способов:

- правый клик по `ChatPulse.app` → **Открыть**;
- **System Settings → Privacy & Security** → подтверждение запуска.

Не отключайте Gatekeeper полностью и не используйте глобальную команду `spctl --master-disable`.

## Требования для сборки из исходников

Установите Xcode Command Line Tools:

```bash
xcode-select --install
```

Проверьте Swift:

```bash
swift --version
```

## Чистая сборка и установка из исходников

```bash
cd ~
rm -rf "$HOME/ChatPulse-install"
git clone --depth 1 https://github.com/mishkacher/ChatPulse.git "$HOME/ChatPulse-install"
cd "$HOME/ChatPulse-install"
bash scripts/install_app.sh
```

Не выполняйте `git clone` внутри уже открытой папки ChatPulse: это создаёт вложенные каталоги и затрудняет обновление.

## Ручная сборка

```bash
bash scripts/build_app.sh
```

Результат:

```text
dist/ChatPulse.app
```

Во время сборки автоматически:

- считываются `VERSION` и `BUILD_NUMBER`;
- компилируется release-версия Swift;
- из SVG создаётся системная иконка `.icns`;
- формируется bundle `ChatPulse.app`;
- добавляются bundle identifier, категория, версия и номер сборки;
- включается hardened runtime;
- выполняется ad-hoc подпись либо подпись идентификатором из `CHATPULSE_CODESIGN_IDENTITY`.

## Релизный preflight

```bash
make preflight
```

Проверка включает debug- и release-тесты, 20 quality gates, shell-синтаксис, сборку, `Info.plist`, иконку, bundle identifier, версию, build number, hardened runtime и code signature.

## Повторная установка из исходников

```bash
cd "$HOME/ChatPulse-install"
git pull --ff-only
bash scripts/install_app.sh
```

Скрипт:

1. собирает свежую версию;
2. останавливает уже запущенную копию;
3. устанавливает приложение в `/Applications`, если папка доступна для записи;
4. иначе использует `~/Applications`;
5. запускает установленную копию.

Для ручного запуска:

```bash
open "/Applications/ChatPulse.app" 2>/dev/null || open "$HOME/Applications/ChatPulse.app"
```

## Первый вход

1. Откройте **«Браузер ChatPulse»** из строки меню.
2. Нажмите **«Войти ▾»**.
3. Выберите **email / код** или **passkey**.
4. После входа откройте конкретный разговор.
5. Нажмите **«Добавить чат»**.
6. Выберите интервал.
7. Нажмите **«Запустить»**.

Разрешения Automation для Chrome или Safari не требуются.

## Вход по email / одноразовому коду

ChatPulse открывает официальный экран OpenAI и помогает перейти к доступному email-сценарию. Код вводится только на странице входа.

Приложение не читает почту, не перехватывает код и не сохраняет email, пароль или одноразовые данные.

Если аккаунт создан только через социального провайдера, email-вход может быть недоступен. В таком случае используйте заранее добавленный passkey.

## Вход с passkey

Passkey должен быть заранее добавлен в аккаунт и доступен в macOS. В зависимости от конфигурации подтверждение может использовать Touch ID, пароль Mac, iCloud Keychain, менеджер учётных данных или аппаратный ключ.

Если ключ не найден:

1. войдите в ChatGPT через Safari или официальное приложение;
2. добавьте passkey в настройках безопасности аккаунта;
3. повторите вход в ChatPulse.

## Вход через Google

Google OAuth внутри управляемого приложением WebView не используется. ChatPulse отменяет такой переход и предлагает email-код или passkey.

Сессия Safari не переносится в отдельное хранилище `WKWebView`.

## Чат открыт, но команда не отправляется

Возможные причины:

- ответ обнаружен впервые и приложение ждёт следующую проверку;
- ChatGPT ещё генерирует;
- последнее сообщение принадлежит пользователю;
- ответ уже был продолжен;
- страница не загрузилась;
- поле ввода или кнопка отправки недоступны;
- чат отключён или удалён во время проверки;
- интерфейс ChatGPT изменился.

Проверьте пункт **«Последние действия…»**.

## Как узнать версию

Нажмите значок ChatPulse в строке меню и выберите **«О ChatPulse…»**. Окно показывает версию и номер build из bundle.

## Сброс рабочих настроек

```bash
rm -rf "$HOME/Library/Application Support/ChatPulse"
```

## Удаление приложения

```bash
bash scripts/uninstall_app.sh
```

Скрипт удаляет ChatPulse из `/Applications` и `~/Applications`, но оставляет рабочие настройки пользователя.

Данные сессии WebKit управляются отдельно системным хранилищем сайтов macOS.
