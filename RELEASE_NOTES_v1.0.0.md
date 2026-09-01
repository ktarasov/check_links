# Описание релиза: v1.0.0

Первый стабильный релиз утилиты **Check Links**.

## Новые возможности

- **Поддержка локализации интерфейса.** Добавлена build-опция `-Dlocale=ru|en` (по умолчанию `ru`). На русский или английский язык переводятся справка CLI, сообщения об ошибках и предупреждениях (включая их префиксы), заголовки таблицы и CSV, а также шаблон прогресс-бара.
- **Типизированный каталог локализованных сообщений.** Все тексты локализации хранятся в новом модуле [`src/i18n.zig`](src/i18n.zig); полнота ключей для каждого языка гарантируется компилятором. Выбор языка задаётся перечислением [`src/lang.zig`](src/lang.zig).
- **Автоматизация сборки релизных бинарников.** Команда `zig build release` теперь собирает оптимизированные (`ReleaseSmall`) сжатые архивы для нескольких платформ:
  - `x86_64-linux` (`.tar.gz`);
  - `x86_64-windows` (`.zip`);
  - `x86_64-macos` (`.tar.gz`);
  - `aarch64-macos` (`.tar.gz`);

  причём для каждой из двух локалей (`ru` и `en`) отдельно. Артефакты помещаются в `zig-out/compressed/`.
- **Значения по умолчанию в справке CLI.** В выводе справки для параметров `--timeout` и `--parallels` теперь явно отображаются значения по умолчанию (`15` и `5` соответственно).

## Прочее

- Версия проекта поднята до **1.0.0** (см. [`build.zig.zon`](build.zig.zon)).
- Обновлён README: добавлены разделы о локализации, командах сборки и поддерживаемых платформах для релизной сборки.

---

# Release Notes: v1.0.0

The first stable release of the **Check Links** utility.

## New Features

- **UI localization support.** Added the `-Dlocale=ru|en` build option (default: `ru`). The CLI help, error and warning messages (including their prefixes), table and CSV headers, and the progress-bar template are now localized into Russian or English.
- **Typed catalog of localized messages.** All localized strings live in the new module [`src/i18n.zig`](src/i18n.zig); key completeness for each language is guaranteed by the compiler. The language selection is defined by the [`src/lang.zig`](src/lang.zig) enum.
- **Release build automation.** The `zig build release` command now builds optimized (`ReleaseSmall`) compressed archives for several platforms:
  - `x86_64-linux` (`.tar.gz`);
  - `x86_64-windows` (`.zip`);
  - `x86_64-macos` (`.tar.gz`);
  - `aarch64-macos` (`.tar.gz`);

  separately for each of the two locales (`ru` and `en`). Artifacts are placed in `zig-out/compressed/`.
- **Default values shown in CLI help.** The help output for the `--timeout` and `--parallels` options now explicitly shows their default values (`15` and `5` respectively).

## Other

- Project version bumped to **1.0.0** (see [`build.zig.zon`](build.zig.zon)).
- Updated README: added sections about localization, build commands, and supported platforms for the release build.