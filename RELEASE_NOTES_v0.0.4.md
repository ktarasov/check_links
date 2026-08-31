# Описание релиза: v0.0.4

## Новые возможности

- **Поддержка пользовательских HTTP-заголовков.** Добавлен параметр `-H`/`--header` в формате `NAME: VALUE`. Параметр можно указывать несколько раз, чтобы задать произвольный набор заголовков для запросов.
- **Параметр таймаута `-t`/`--timeout`.** Устанавливает таймаут проверки в секундах (по умолчанию — 15). Таймаут теперь применяется и к установке соединения.
- **Параметр параллельности `-p`/`--parallels`.** Задаёт количество параллельных запросов (по умолчанию — 5), что ускоряет проверку большого числа ссылок.
- **Таймаут на соединение.** Для установки соединения добавлен собственный таймаут с асинхронной отменой (`Future.cancel`), а не только на ожидание ответа.
- **Обработка редиректов** при загрузке документов для сбора ссылок.
- **Стандартный `User-Agent`** по умолчанию для HTTP-запросов.

## Исправления

- Обработка повторяющихся аргументов `header` приведена к стандарту библиотеки `args.zig`.
- Исправлен проброс таймаута вплоть до момента создания соединения.
- Изменён размер чанка обработки ссылок — интерфейс стал отзывчивее.
- Улучшена обработка ошибок CLI и валидация заголовков (формат, имя, запрещённые символы, `Content-Length`/`Transfer-Encoding`).

## Прочее

- Обновлён README.
- Зависимость `args.zig` обновлена до версии 0.0.9.
- Зависимость `zigquery` обновлена.

---

# Release Notes: v0.0.4

## New Features

- **Custom HTTP headers support.** Added the `-H`/`--header` option in `NAME: VALUE` format. The option can be repeated multiple times to set an arbitrary set of headers for requests.
- **Timeout option `-t`/`--timeout`.** Sets the check timeout in seconds (default: 15). The timeout now also applies to establishing the connection.
- **Concurrency option `-p`/`--parallels`.** Sets the number of parallel requests (default: 5), speeding up checks on large numbers of links.
- **Connection timeout.** A dedicated timeout was added for establishing connections, with asynchronous cancellation (`Future.cancel`), not just for waiting on responses.
- **Redirect handling** when loading documents to collect links.
- **Default `User-Agent`** for HTTP requests.

## Bug Fixes

- Handling of repeated `header` arguments brought in line with the `args.zig` library standard.
- Fixed timeout propagation down to the connection-establishment stage.
- Changed the link processing chunk size — the interface is now more responsive.
- Improved CLI error handling and header validation (format, name, forbidden characters, `Content-Length`/`Transfer-Encoding`).

## Other

- Updated README.
- Upgraded the `args.zig` dependency to 0.0.9.
- Upgraded the `zigquery` dependency.