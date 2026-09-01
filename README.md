# Check Links

[Read this document in English](#english) — английская версия документа находится ниже.

---

## О проекте

**Check Links** — консольная утилита (CLI) на языке **Zig** для проверки ссылок на веб-странице.

Утилита загружает HTML-страницу по указанному URL, собирает все ссылки (`<a href>`) и изображения (`<img src>`), а затем проверяет каждый URL на доступность. Результат выводится на экран в виде таблицы или экспортируется в CSV-файл.

> Проект является переработкой ранее существовавшей [PHP-реализации](https://gitverse.ru/kvt/check-links) на языке Zig.

## Возможности

- Загрузка страницы по схемам `http://`, `https://` и `file://` (чтение локального HTML-файла).
- Извлечение URL из атрибутов `href` тегов `<a>` и `src` тегов `<img>`.
- Нормализация относительных ссылок в абсолютные на основе базового домена (включая протокол-относительные `//`).
- Удаление дубликатов URL.
- Конкурентная проверка доступности каждого URL методом `HEAD` (по одному потоку на URL).
- Конкурентная проверка URL партиями настраиваемого размера: количество параллельных запросов задаётся через `--parallels` (по умолчанию 5; внутри партии — конкурентно, между партиями — последовательно).
- Собственный HTTP HEAD-клиент с поддержкой TLS и таймаута запроса (по умолчанию 15 секунд, настраивается через `--timeout`).
- Повторяемые пользовательские HTTP-заголовки для авторизованных страниц и ссылок того же origin.
- Группировка результатов по HTTP-коду ответа.
- Вывод в терминал в виде таблицы с цветовой подсветкой кодов:
  - `2xx` — зелёный;
  - `3xx` — жёлтый;
  - `4xx`/`5xx` — красный.
- Экспорт результатов в CSV-файл (разделитель `;`).
- Режим «только ошибки» — показывать лишь упавшие ссылки.
- Индикатор прогресса выполнения проверки.
- Интернационализация интерфейса: справка CLI, сообщения об ошибках и предупреждениях, заголовки таблицы и CSV, а также шаблон прогресс-бара собираются на русском или английском языке через build-опцию `-Dlocale` (по умолчанию `ru`).

## Требования

- **Zig 0.16.0** или новее (см. `minimum_zig_version` в [`build.zig.zon`](build.zig.zon)).

## Установка и сборка

Клонируйте репозиторий и соберите проект:

```sh
zig build
```

Бинарный файл появится в `zig-out/bin/`.

### Команды сборки

| Команда | Описание |
| --- | --- |
| `zig build` | Сборка исполняемого файла (`check_links`). |
| `zig build run -- <аргументы>` | Сборка и запуск утилиты. |
| `zig build test` | Запуск всех тестов. |
| `zig build release` | Сборка релизных бинарных файлов (сжатые архивы) для нескольких платформ. |
| `zig build -Dlocale=ru` | Сборка с русским интерфейсом (по умолчанию). |
| `zig build -Dlocale=en` | Сборка с английским интерфейсом. |

### Поддерживаемые платформы для релизной сборки

`zig build release` собирает и упаковывает бинарники для:

- `x86_64-linux`
- `x86_64-windows` (архив `.zip`)
- `x86_64-macos`
- `aarch64-macos`

### Локализация

Интерфейс утилиты (справка CLI, сообщения об ошибках и предупреждениях, заголовки таблицы и CSV, шаблон прогресс-бара) можно собирать на русском или английском языке. Язык задаётся на этапе сборки через build-опцию `-Dlocale` (по умолчанию — русский):

```sh
zig build -Dlocale=ru   # русский интерфейс (по умолчанию)
zig build -Dlocale=en   # английский интерфейс
```

Тексты локализации хранятся в типизированном каталоге [`src/i18n.zig`](src/i18n.zig); полнота ключей для каждого языка гарантируется компилятором.

## Использование

```sh
check_links <URL> [опции]
```

### Параметры

| Аргумент | Описание |
| --- | --- |
| `<URL>` | URL страницы, ссылки которой нужно проверить (обязательный). |
| `-f`, `--fail` | Показывать только ошибочные ссылки. |
| `-e`, `--export <файл>` | Экспорт результатов в CSV-файл. |
| `-t`, `--timeout <секунды>` | Таймаут запроса в секундах (по умолчанию 15; `0` — без таймаута). |
| `-H`, `--header <NAME: VALUE>` | Добавить HTTP-заголовок; опцию можно повторять. |
| `-p`, `--parallels <количество>` | Количество параллельных запросов (по умолчанию 5; от 1 до 100). |

### Примеры

```sh
# Проверить все ссылки на странице и вывести таблицу в терминал
check_links https://example.com/

# Показать только ошибочные ссылки
check_links --fail https://example.com/

# Увеличить таймаут запроса до 60 секунд
check_links --timeout 60 https://example.com/

# Увеличить число параллельных запросов (например, до 20)
check_links --parallels 20 https://example.com/

# Экспортировать результаты в CSV-файл
check_links --export result.csv https://example.com/

# Экспортировать только ошибочные ссылки в CSV
check_links --fail --export errors.csv https://example.com/

# Проверить авторизованную страницу с несколькими заголовками
check_links -H 'Authorization: Bearer token' \
  --header 'X-Tenant-ID: 42' \
  https://example.com/private
```

Заголовки передаются при загрузке исходной страницы и при `HEAD`-проверке ссылок с тем же origin (схема, хост и эффективный порт). При переходе или проверке внешнего origin они не отправляются. Поддерживаются формы `--header 'NAME: VALUE'` и `--header='NAME: VALUE'`.

> Значения заголовков, переданные в командной строке, могут сохраниться в истории shell или быть видны другим локальным процессам. Учитывайте это при передаче токенов и других секретов.

### Пример вывода (таблица)

```
--------------------------------------------------------------------------
 №      | URL страницы            | Проверенный URL            | HTTP Код
--------------------------------------------------------------------------
     1. | https://example.com     | https://example.com/page1  |   200
     2. | https://example.com     | https://example.com/page2  |   404
     3. | https://example.com     | https://example.com/page3  |   200
--------------------------------------------------------------------------
```

HTTP-коды в таблице окрашиваются в зависимости от диапазона:
- **2xx** — зелёный;
- **3xx** — жёлтый;
- **4xx/5xx** — красный.

## Типовые сценарии использования утилиты

### 1. Проверка битых ссылок на своём сайте после редизайна или миграции

После смены дизайна, структуры URL или переезда на новый домен необходимо убедиться, что на страницах не осталось ссылок на старые (удалённые) разделы или файлы.

```sh
check_links --fail https://мой-сайт.рф/page/
```

Утилита покажет только те ссылки, которые ведут на несуществующие страницы (404, 410) или серверные ошибки (500).

### 2. SEO-аудит: поиск ссылок на внешние ресурсы, которые перестали работать

Битые внешние ссылки ухудшают поведенческие факторы и доверие поисковых систем к сайту. Регулярная проверка внешних ссылок — обязательная часть SEO-поддержки.

```sh
check_links --export broken-links.csv https://мой-сайт.рф/
```

CSV-файл можно открыть в Excel/Google Sheets и передать контент-менеджеру для исправления.

### 3. Проверка ссылок в статье или лендинге перед публикацией

Перед публикацией материала с множеством внешних источников полезно убедиться, что все ссылки рабочие, а не ведут на 404.

```sh
check_links https://блог.рф/черновик-статьи/
```

Зелёные коды 200 — всё в порядке, жёлтые 3xx — редиректы (стоит обновить ссылки на актуальные), красные 4xx/5xx — битые ссылки.

### 4. Мониторинг ссылок в документации или базе знаний

Для сайтов с объёмной документацией (вики, базы знаний, мануалы) полезно настроить регулярную проверку ссылок, чтобы документация всегда оставалась актуальной.

```sh
# Еженедельная проверка по cron
0 6 * * 1 /usr/local/bin/check_links --fail --export /var/log/links-check/docs-errors.csv https://docs.company.ru/
```

### 5. Проверка ссылок на странице товара в интернет-магазине

В карточках товаров часто бывают ссылки на связанные товары, категории, обзоры. Если такие ссылки ведут в никуда — это прямые потери продаж.

```sh
check_links --fail https://internet-magazin.ru/catalog/tovar-123/
```

### 6. Аудит ссылочной массы перед закупкой ссылок

При SEO-продвижении перед покупкой ссылок с донорского сайта полезно проверить, не висит ли на нём битых страниц, которые могут снизить эффект от закупки.

```sh
check_links --fail https://donor-site.ru/
```

### 7. Поиск изображений, которые не загружаются

Утилита собирает не только ссылки (`<a href>`), но и изображения (`<img src>`). Это позволяет найти битые картинки на странице — частую причину ухудшения визуального восприятия сайта.

```sh
check_links --fail https://мой-сайт.рф/gallery/
```

### 8. Проверка редиректов (цепочки перенаправлений)

Хотя утилита не отслеживает цепочки редиректов пошагово, она показывает HTTP-код 3xx для URL, которые перенаправляют. Это помогает выявить лишние промежуточные редиректы, замедляющие загрузку страницы.

```sh
check_links https://example.com/
```

Обращайте внимание на жёлтые строки — это URL, которые возвращают 301, 302 и т.д.

### 9. Экспорт полной карты ссылок страницы для дальнейшего анализа

CSV-экспорт позволяет передать результаты в BI-системы, Google Sheets или Excel для построения отчётов и дашбордов.

```sh
check_links --export full-links-report.csv https://мой-сайт.рф/
```

### 10. Быстрая проверка сайта клиента перед презентацией

Агентствам и фрилансерам: перед показом сайта клиенту стоит прогнать главную страницу и типовые страницы через утилиту, чтобы исключить неловкую ситуацию с битыми ссылками на демонстрации.

```sh
check_links --fail https://сайт-клиента.рф/
```

## Структура проекта

| Модуль | Назначение |
| --- | --- |
| [`src/main.zig`](src/main.zig) | Точка входа CLI, разбор аргументов (включая таймаут и число параллельных запросов). |
| [`src/i18n.zig`](src/i18n.zig) | Типизированный каталог локализованных сообщений (`ru`/`en`) и выбор активной локали через `-Dlocale`. |
| [`src/lang.zig`](src/lang.zig) | Перечисление поддерживаемых языков интерфейса (используется сборкой). |
| [`src/check_links_by_page.zig`](src/check_links_by_page.zig) | Оркестрация проверки ссылок на одной странице. |
| [`src/collect_urls.zig`](src/collect_urls.zig) | Загрузка страницы и сбор URL из HTML. |
| [`src/html_parser.zig`](src/html_parser.zig) | HTML-парсер (на основе библиотеки `zigquery`) для извлечения `href`/`src`. |
| [`src/url_normalize.zig`](src/url_normalize.zig) | Нормализация и построение абсолютных URL. |
| [`src/check_link_list.zig`](src/check_link_list.zig) | Пакетная проверка списка URL (чанки) и группировка по коду. |
| [`src/check_http.zig`](src/check_http.zig) | Конкурентная проверка HTTP-кодов. |
| [`src/http_head_client.zig`](src/http_head_client.zig) | Собственный HTTP HEAD-клиент с TLS и таймаутом. |
| [`src/request_headers.zig`](src/request_headers.zig) | Разбор пользовательских HTTP-заголовков и проверка same-origin. |
| [`src/table_view.zig`](src/table_view.zig) | Вывод результатов в виде таблицы в терминал. |
| [`src/export_csv.zig`](src/export_csv.zig) | Экспорт результатов в CSV. |
| [`src/TableFormatter.zig`](src/TableFormatter.zig) | Форматирование таблицы под ширину терминала. |
| [`src/bar.zig`](src/bar.zig) | Прогресс-бар выполнения проверки. |
| [`src/tests.zig`](src/tests.zig) | Корневой файл тестов. |
| [`src/http_integration_test.zig`](src/http_integration_test.zig) | Интеграционные тесты HTTP-проверки на локальном сервере. |

## Как это работает

1. Утилита загружает HTML-содержимое страницы по указанному URL.
2. HTML-парсер извлекает все URL из атрибутов `href` и `src`.
3. Относительные ссылки нормализуются в абсолютные, дубликаты удаляются.
4. Каждый URL проверяется методом `HEAD` конкурентно; для проверки используется собственный HTTP HEAD-клиент с таймаутом запроса.
5. Результаты группируются по HTTP-коду ответа и выводятся в виде таблицы или CSV-файла.

## Формат CSV

При экспорте используется разделитель `;`. Структура файла:

```
№;URL страницы;Проверенный URL;HTTP Код
1;https://example.com;https://example.com/page1;200
2;https://example.com;https://example.com/page2;404
```

Если файл уже существует, перед перезаписью он переименовывается в `<имя>.bak`.

## Тестирование

Запуск всех тестов:

```sh
zig build test
```

Тесты покрывают: парсинг HTML (на базе `zigquery`), нормализацию URL, сбор ссылок со страницы, разбор пользовательских HTTP-заголовков и политику same-origin, проверку HTTP-кодов на локальном тестовом сервере (включая таймауты и редиректы), форматирование таблицы и экспорт в CSV.

## Лицензия

Проект распространяется на условиях лицензии **Васлекс для свободного программного обеспечения (версия 2.0 от 11.03.2025)**. Полный текст лицензии приведён в файле [`LICENSE`](LICENSE).

---

# English

## About

**Check Links** is a command-line utility (CLI) written in **Zig** for checking links on a web page.

The utility loads the HTML page at the given URL, collects all links (`<a href>`) and images (`<img src>`), and then checks each URL for availability. The results are displayed on the screen as a table or exported to a CSV file.

> The project is a Zig rewrite of a previously existing PHP implementation.

## Features

- Loads pages using the `http://`, `https://`, and `file://` schemes (local HTML file reading).
- Extracts URLs from the `href` attribute of `<a>` tags and the `src` attribute of `<img>` tags.
- Normalizes relative links into absolute ones based on the base domain (including protocol-relative `//` links).
- Removes duplicate URLs.
- Concurrently checks the availability of each URL using the `HEAD` method (one thread per URL).
- Checks URLs concurrently in batches of a configurable size: the number of parallel requests is set via `--parallels` (default 5), concurrently within a batch and sequentially between batches.
- Custom HTTP HEAD client with TLS support and a request timeout (15 seconds by default, configurable via `--timeout`).
- Repeatable custom HTTP headers for authenticated pages and same-origin links.
- Groups results by HTTP response code.
- Terminal table output with color-coded codes:
  - `2xx` — green;
  - `3xx` — yellow;
  - `4xx`/`5xx` — red.
- Exports results to a CSV file (delimiter `;`).
- "Errors only" mode — shows only failed links.
- Progress bar for the checking process.
- UI localization: CLI help, error and warning messages, table and CSV headers, and the progress-bar template can be built in Russian or English via the `-Dlocale` build option (default `ru`).

## Requirements

- **Zig 0.16.0** or newer (see `minimum_zig_version` in [`build.zig.zon`](build.zig.zon)).

## Installation and Build

Clone the repository and build the project:

```sh
zig build
```

The binary will be placed in `zig-out/bin/`.

### Build Commands

| Command | Description |
| --- | --- |
| `zig build` | Builds the executable (`check_links`). |
| `zig build run -- <arguments>` | Builds and runs the utility. |
| `zig build test` | Runs all tests. |
| `zig build release` | Builds release binaries (compressed archives) for multiple platforms. |
| `zig build -Dlocale=ru` | Builds the Russian UI (default). |
| `zig build -Dlocale=en` | Builds the English UI. |

### Supported Release Platforms

`zig build release` builds and packages binaries for:

- `x86_64-linux`
- `x86_64-windows` (`.zip` archive)
- `x86_64-macos`
- `aarch64-macos`

### Localization

The utility UI (CLI help, error and warning messages, table and CSV headers, progress-bar template) can be built in Russian or English. The language is selected at build time via the `-Dlocale` build option (default — Russian):

```sh
zig build -Dlocale=ru   # Russian UI (default)
zig build -Dlocale=en   # English UI
```

Localized strings live in the typed catalog [`src/i18n.zig`](src/i18n.zig); key completeness for each language is guaranteed by the compiler.

## Usage

```sh
check_links <URL> [options]
```

### Arguments

| Argument | Description |
| --- | --- |
| `<URL>` | URL of the page whose links to check (required). |
| `-f`, `--fail` | Show only failed links. |
| `-e`, `--export <file>` | Export results to a CSV file. |
| `-t`, `--timeout <seconds>` | Request timeout in seconds (default 15; `0` — no timeout). |
| `-H`, `--header <NAME: VALUE>` | Add an HTTP header; may be repeated. |
| `-p`, `--parallels <count>` | Number of parallel requests (default 5; from 1 to 100). |

### Examples

```sh
# Check all links on a page and print a table in the terminal
check_links https://example.com/

# Show only failed links
check_links --fail https://example.com/

# Increase the request timeout to 60 seconds
check_links --timeout 60 https://example.com/

# Increase the number of parallel requests (e.g., to 20)
check_links --parallels 20 https://example.com/

# Export results to a CSV file
check_links --export result.csv https://example.com/

# Export only failed links to CSV
check_links --fail --export errors.csv https://example.com/

# Check an authenticated page with multiple headers
check_links -H 'Authorization: Bearer token' \
  --header 'X-Tenant-ID: 42' \
  https://example.com/private
```

Headers are sent when loading the source page and when making `HEAD` requests to links with the same origin (scheme, host, and effective port). They are omitted when redirecting to or checking an external origin. Both `--header 'NAME: VALUE'` and `--header='NAME: VALUE'` forms are supported.

> Header values passed on the command line may be stored in shell history or visible to other local processes. Keep this in mind when passing tokens or other secrets.

### Example Output (table)

```
--------------------------------------------------------------------------
 №      | URL of the page         | Checked URL                | HTTP Code
--------------------------------------------------------------------------
     1. | https://example.com     | https://example.com/page1  |   200
     2. | https://example.com     | https://example.com/page2  |   404
     3. | https://example.com     | https://example.com/page3  |   200
--------------------------------------------------------------------------
```

HTTP codes in the table are color-coded by range:
- **2xx** — green;
- **3xx** — yellow;
- **4xx/5xx** — red.

## Typical Use Cases

### 1. Checking for broken links on your site after a redesign or migration

After changing the design, URL structure, or moving to a new domain, you should make sure that no links point to old (removed) sections or files.

```sh
check_links --fail https://example.com/page/
```

The utility shows only links that lead to non-existent pages (404, 410) or server errors (500).

### 2. SEO audit: finding links to external resources that stopped working

Broken external links harm behavioral factors and search-engine trust in your site. Regularly checking external links is a mandatory part of SEO maintenance.

```sh
check_links --export broken-links.csv https://example.com/
```

The CSV file can be opened in Excel/Google Sheets and handed to a content manager for fixing.

### 3. Checking links in an article or landing page before publication

Before publishing content with many external sources, it helps to verify that all links are working and do not lead to 404.

```sh
check_links https://blog.example.com/draft-article/
```

Green 200 codes mean everything is fine, yellow 3xx means redirects (worth updating the links to current ones), red 4xx/5xx are broken links.

### 4. Monitoring links in documentation or a knowledge base

For sites with extensive documentation (wikis, knowledge bases, manuals), it is useful to set up a regular link check so that the documentation stays up to date.

```sh
# Weekly check via cron
0 6 * * 1 /usr/local/bin/check_links --fail --export /var/log/links-check/docs-errors.csv https://docs.company.ru/
```

### 5. Checking links on a product page in an online store

Product cards often contain links to related products, categories, and reviews. If such links lead nowhere, it is a direct loss of sales.

```sh
check_links --fail https://store.example.com/catalog/product-123/
```

### 6. Auditing a link profile before buying links

When doing SEO, before buying links from a donor site, it is worth checking whether it has broken pages that could reduce the effect of the purchase.

```sh
check_links --fail https://donor-site.example.com/
```

### 7. Finding images that fail to load

The utility collects not only links (`<a href>`) but also images (`<img src>`). This lets you find broken images on a page — a common cause of poor visual perception of a site.

```sh
check_links --fail https://example.com/gallery/
```

### 8. Checking redirects (redirect chains)

Although the utility does not follow redirect chains step by step, it shows the 3xx HTTP code for URLs that redirect. This helps to identify unnecessary intermediate redirects that slow down page loading.

```sh
check_links https://example.com/
```

Pay attention to the yellow rows — these are URLs returning 301, 302, etc.

### 9. Exporting a full link map of a page for further analysis

CSV export lets you pass results to BI systems, Google Sheets, or Excel for building reports and dashboards.

```sh
check_links --export full-links-report.csv https://example.com/
```

### 10. Quick client site check before a presentation

For agencies and freelancers: before showing a site to a client, run the home page and typical pages through the utility to avoid an awkward situation with broken links during a demo.

```sh
check_links --fail https://client-site.example.com/
```

## Project Structure

| Module | Purpose |
| --- | --- |
| [`src/main.zig`](src/main.zig) | CLI entry point, argument parsing (including timeout and the number of parallel requests). |
| [`src/i18n.zig`](src/i18n.zig) | Typed catalog of localized messages (`ru`/`en`) and active-locale selection via `-Dlocale`. |
| [`src/lang.zig`](src/lang.zig) | Enum of supported UI languages (used by the build). |
| [`src/check_links_by_page.zig`](src/check_links_by_page.zig) | Orchestrates link checking for a single page. |
| [`src/collect_urls.zig`](src/collect_urls.zig) | Loads the page and collects URLs from HTML. |
| [`src/html_parser.zig`](src/html_parser.zig) | HTML parser (based on the `zigquery` library) for extracting `href`/`src`. |
| [`src/url_normalize.zig`](src/url_normalize.zig) | URL normalization and absolute URL building. |
| [`src/check_link_list.zig`](src/check_link_list.zig) | Batch URL checking (chunks) and grouping by code. |
| [`src/check_http.zig`](src/check_http.zig) | Concurrent HTTP code checking. |
| [`src/http_head_client.zig`](src/http_head_client.zig) | Custom HTTP HEAD client with TLS and timeout. |
| [`src/request_headers.zig`](src/request_headers.zig) | Custom HTTP header parsing and same-origin policy. |
| [`src/table_view.zig`](src/table_view.zig) | Renders results as a terminal table. |
| [`src/export_csv.zig`](src/export_csv.zig) | Exports results to CSV. |
| [`src/TableFormatter.zig`](src/TableFormatter.zig) | Table formatting to fit the terminal width. |
| [`src/bar.zig`](src/bar.zig) | Progress bar for the checking process. |
| [`src/tests.zig`](src/tests.zig) | Root test file. |
| [`src/http_integration_test.zig`](src/http_integration_test.zig) | HTTP link-checking integration tests against a local server. |

## How It Works

1. The utility loads the HTML content of the page from the given URL.
2. The HTML parser extracts all URLs from `href` and `src` attributes.
3. Relative links are normalized to absolute ones; duplicates are removed.
4. Each URL is checked concurrently with the `HEAD` method using a custom HTTP HEAD client with a request timeout.
5. Results are grouped by HTTP response code and printed as a table or exported to a CSV file.

## CSV Format

Exports use the `;` delimiter. The file structure:

```
№;URL страницы;Проверенный URL;HTTP Код
1;https://example.com;https://example.com/page1;200
2;https://example.com;https://example.com/page2;404
```

If the file already exists, it is renamed to `<name>.bak` before being overwritten.

## Testing

Run all tests:

```sh
zig build test
```

Tests cover: HTML parsing (based on `zigquery`), URL normalization, link collection from a page, custom HTTP header parsing and same-origin policy, HTTP code checking against a local test server (including timeouts and redirects), table formatting, and CSV export.

## License

This project is distributed under the **Vaslex Free Software License (version 2.0, dated 11 March 2025)**. The full license text is available in the [`LICENSE`](LICENSE) file.
