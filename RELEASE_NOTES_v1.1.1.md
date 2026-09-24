# Описание релиза: v1.1.1

Релиз посвящён инфраструктуре проекта: версия программы в CLI теперь всегда совпадает с версией пакета, добавлена автоматизация сборки и публикации релизов через GitHub Actions (включая `.deb` и `.rpm` пакеты), а также улучшена обработка ошибок командной строки.

## Новые возможности

- **Актуальная версия в CLI.** Вывод `--version` теперь берётся из [`build.zig.zon`](build.zig.zon) через build-опции, а не из жёстко заданной строки: версия, которую сообщает утилита, больше не расходится с версией пакета.
- **Автоматизация релизов.** Добавлен workflow [`.github/workflows/release.yml`](.github/workflows/release.yml): при создании тега вида `v*` (или вручную через `workflow_dispatch`) запускаются тесты, собираются релизные архивы и публикуется черновик GitHub Release.
- **Сборка `.deb` и `.rpm` пакетов.** Для каждой локали (`ru`, `en`, `es`, `fr`) генерируются пакеты `check_links_<locale>`, устанавливающие бинарник в `/usr/bin/check-links`.
- **Контроль релизных заметок.** Workflow проверяет наличие файла `RELEASE_NOTES_<тег>.md` и останавливает публикацию с ошибкой, если он отсутствует.
- **Переименование исполняемого файла.** Бинарник теперь собирается как `check-links`; обновлены имена релизных архивов (`check-links-<arch>-<os>-<locale>.tar.gz` / `.zip`). Внутреннее имя CLI (справка, `--version`, автодополнение) также приведено к `check-links`.

## Исправления

- Исправлено внутреннее имя программы, используемое при генерации скрипта автодополнения: теперь оно совпадает с именем исполняемого файла.
- Неизвестные ошибки разбора аргументов больше не приводят к техническому стек-трейсу: выводится локализованное сообщение «Неизвестная ошибка при выполнении программы», процесс завершается с кодом возврата 1.
- Добавлено локализованное сообщение `err_unknown` для всех четырёх языков интерфейса ([`src/i18n.zig`](src/i18n.zig)).
- Исправлен ANSI-код цвета для префикса сообщений об ошибках.

## Прочее

- Версия проекта поднята до **1.1.1** (см. [`build.zig.zon`](build.zig.zon)).

---

# Release Notes: v1.1.1

This release focuses on project infrastructure: the version reported by the CLI now always matches the package version, release builds and publishing are automated via GitHub Actions (including `.deb` and `.rpm` packages), and command-line error handling has been improved.

## New Features

- **Up-to-date version in the CLI.** The `--version` output is now taken from [`build.zig.zon`](build.zig.zon) via build options instead of a hardcoded string: the version reported by the utility no longer drifts from the package version.
- **Release automation.** Added the [`.github/workflows/release.yml`](.github/workflows/release.yml) workflow: on tags matching `v*` (or manually via `workflow_dispatch`) tests are run, release archives are built, and a draft GitHub Release is published.
- **`.deb` and `.rpm` package building.** For each locale (`ru`, `en`, `es`, `fr`) packages named `check_links_<locale>` are generated, installing the binary to `/usr/bin/check-links`.
- **Release notes check.** The workflow verifies that the `RELEASE_NOTES_<tag>.md` file exists and stops the publish with an error if it is missing.
- **Executable renamed.** The binary is now built as `check-links`; release archive names have been updated accordingly (`check-links-<arch>-<os>-<locale>.tar.gz` / `.zip`). The internal CLI name (help, `--version`, autocompletion) has also been aligned to `check-links`.

## Bug Fixes

- Fixed the internal program name used when generating the autocompletion script: it now matches the executable name.
- Unknown argument parsing errors no longer produce a technical stack trace: a localized "Unknown error while executing the program." message is printed and the process exits with return code 1.
- Added the localized `err_unknown` message for all four UI languages ([`src/i18n.zig`](src/i18n.zig)).
- Fixed the ANSI color code used for the error-message prefix.

## Other

- Project version bumped to **1.1.1** (see [`build.zig.zon`](build.zig.zon)).

---

# Notas de la versión: v1.1.1

Esta versión se centra en la infraestructura del proyecto: la versión que muestra la CLI ahora siempre coincide con la versión del paquete, la compilación y publicación de versiones están automatizadas mediante GitHub Actions (incluidos los paquetes `.deb` y `.rpm`), y se ha mejorado el manejo de errores de la línea de comandos.

## Nuevas funcionalidades

- **Versión actualizada en la CLI.** La salida de `--version` ahora se toma de [`build.zig.zon`](build.zig.zon) mediante opciones de compilación en lugar de una cadena fija: la versión informada por la utilidad ya no difiere de la versión del paquete.
- **Automatización de versiones.** Se ha añadido el flujo de trabajo [`.github/workflows/release.yml`](.github/workflows/release.yml): al crear una etiqueta `v*` (o manualmente mediante `workflow_dispatch`) se ejecutan las pruebas, se compilan los archivos de la versión y se publica un borrador de GitHub Release.
- **Compilación de paquetes `.deb` y `.rpm`.** Para cada locale (`ru`, `en`, `es`, `fr`) se generan paquetes `check_links_<locale>` que instalan el binario en `/usr/bin/check-links`.
- **Verificación de las notas de la versión.** El flujo de trabajo comprueba la existencia del archivo `RELEASE_NOTES_<etiqueta>.md` y detiene la publicación con un error si no existe.
- **Ejecutable renombrado.** El binario ahora se compila como `check-links`; los nombres de los archivos de la versión se han actualizado en consecuencia (`check-links-<arch>-<os>-<locale>.tar.gz` / `.zip`). El nombre interno de la CLI (ayuda, `--version`, autocompletado) también se ha alineado con `check-links`.

## Correcciones

- Corregido el nombre interno del programa utilizado al generar el script de autocompletado: ahora coincide con el nombre del ejecutable.
- Los errores desconocidos de análisis de argumentos ya no producen un stack trace técnico: se muestra un mensaje localizado «Erro de tipo desconocido al ejecutar el programa.» y el proceso termina con el código de retorno 1.
- Se ha añadido el mensaje localizado `err_unknown` para los cuatro idiomas de la interfaz ([`src/i18n.zig`](src/i18n.zig)).
- Corregido el código de color ANSI utilizado para el prefijo de los mensajes de error.

## Otros cambios

- La versión del proyecto se ha elevado a **1.1.1** (véase [`build.zig.zon`](build.zig.zon)).

---

# Notes de version : v1.1.1

Cette version est consacrée à l'infrastructure du projet : la version affichée par la CLI correspond désormais toujours à la version du paquet, la compilation et la publication des versions sont automatisées via GitHub Actions (y compris les paquets `.deb` et `.rpm`), et la gestion des erreurs de ligne de commande a été améliorée.

## Nouvelles fonctionnalités

- **Version à jour dans la CLI.** La sortie de `--version` provient désormais de [`build.zig.zon`](build.zig.zon) via les options de compilation au lieu d'une chaîne codée en dur : la version signalée par l'utilitaire ne diverge plus de la version du paquet.
- **Automatisation des versions.** Ajout du workflow [`.github/workflows/release.yml`](.github/workflows/release.yml) : à la création d'un tag `v*` (ou manuellement via `workflow_dispatch`), les tests sont exécutés, les archives de version sont compilées et un brouillon de GitHub Release est publié.
- **Compilation des paquets `.deb` et `.rpm`.** Pour chaque locale (`ru`, `en`, `es`, `fr`), des paquets `check_links_<locale>` sont générés, installant le binaire dans `/usr/bin/check-links`.
- **Contrôle des notes de version.** Le workflow vérifie la présence du fichier `RELEASE_NOTES_<tag>.md` et interrompt la publication avec une erreur s'il est absent.
- **Exécutable renommé.** Le binaire est désormais compilé sous le nom `check-links` ; les noms des archives de version ont été mis à jour en conséquence (`check-links-<arch>-<os>-<locale>.tar.gz` / `.zip`). Le nom interne de la CLI (aide, `--version`, autocomplétion) a également été aligné sur `check-links`.

## Corrections

- Correction du nom interne du programme utilisé lors de la génération du script d'autocomplétion : il correspond désormais au nom de l'exécutable.
- Les erreurs inconnues d'analyse des arguments ne produisent plus de stack trace technique : un message localisé « Erreur inconnue lors de l'exécution du programme. » est affiché et le processus se termine avec le code de retour 1.
- Ajout du message localisé `err_unknown` pour les quatre langues de l'interface ([`src/i18n.zig`](src/i18n.zig)).
- Correction du code couleur ANSI utilisé pour le préfixe des messages d'erreur.

## Autres

- La version du projet est passée à **1.1.1** (voir [`build.zig.zon`](build.zig.zon)).