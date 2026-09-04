# Описание релиза: v1.1.0

Релиз добавляет в утилиту **CheckLinks** два новых языка интерфейса и многоязычную документацию.

## Новые возможности

- **Поддержка испанского (`es`) и французского (`fr`) языков.** Build-опция `-Dlocale` теперь принимает значения `ru|en|es|fr` (по умолчанию — `ru`). Добавлены полные типизированные каталоги локализованных сообщений для испанского и французского языков в [`src/i18n.zig`](src/i18n.zig); перечисление поддерживаемых языков в [`src/lang.zig`](src/lang.zig) расширено вариантами `.es` и `.fr`.
- **Локализованы все тексты интерфейса.** На испанский и французский языки переведены описание утилиты, справка CLI, сообщения об ошибках и предупреждениях (включая их префиксы), заголовки таблицы и CSV, а также шаблон прогресс-бара. Полнота ключей для каждого языка гарантируется компилятором.
- **Релизная сборка для всех четырёх локалей.** Команда `zig build release` теперь собирает сжатые архивы отдельно для каждой из четырёх локалей (`ru`, `en`, `es`, `fr`) на всех поддерживаемых платформах (`x86_64-linux`, `x86_64-windows`, `x86_64-macos`, `aarch64-macos`).
- **Многоязычная документация.** Единый README разделён на четыре независимых файла — [`README.md`](README.md) (русский), [`README.en.md`](README.en.md), [`README.es.md`](README.es.md) и [`README.fr.md`](README.fr.md). В начале каждого файла размещены перекрёстные ссылки на остальные языковые версии.

## Прочее

- Версия проекта поднята до **1.1.0** (см. [`build.zig.zon`](build.zig.zon) и [`src/main.zig`](src/main.zig)).

---

# Release Notes: v1.1.0

This release adds two new UI languages to the **CheckLinks** utility and multilingual documentation.

## New Features

- **Spanish (`es`) and French (`fr`) language support.** The `-Dlocale` build option now accepts `ru|en|es|fr` (default: `ru`). Complete typed catalogs of localized messages were added for Spanish and French in [`src/i18n.zig`](src/i18n.zig); the supported-languages enum in [`src/lang.zig`](src/lang.zig) was extended with the `.es` and `.fr` variants.
- **All UI strings are localized.** The utility description, CLI help, error and warning messages (including their prefixes), table and CSV headers, and the progress-bar template are now translated into Spanish and French. Key completeness for each language is guaranteed by the compiler.
- **Release builds for all four locales.** The `zig build release` command now produces compressed archives separately for each of the four locales (`ru`, `en`, `es`, `fr`) on all supported platforms (`x86_64-linux`, `x86_64-windows`, `x86_64-macos`, `aarch64-macos`).
- **Multilingual documentation.** The single README has been split into four independent files — [`README.md`](README.md) (Russian), [`README.en.md`](README.en.md), [`README.es.md`](README.es.md), and [`README.fr.md`](README.fr.md). Cross-links to the other language versions are placed at the top of each file.

## Other

- Project version bumped to **1.1.0** (see [`build.zig.zon`](build.zig.zon) and [`src/main.zig`](src/main.zig)).

---

# Notas de la versión: v1.1.0

Esta versión añade dos nuevos idiomas de interfaz a la utilidad **CheckLinks** y documentación multilingüe.

## Nuevas funcionalidades

- **Soporte de los idiomas español (`es`) y francés (`fr`).** La opción de compilación `-Dlocale` ahora acepta `ru|en|es|fr` (por defecto — `ru`). Se han añadido catálogos tipados completos de mensajes localizados para español y francés en [`src/i18n.zig`](src/i18n.zig); la enumeración de idiomas admitidos en [`src/lang.zig`](src/lang.zig) se ha ampliado con las variantes `.es` y `.fr`.
- **Todos los textos de la interfaz están localizados.** Al español y al francés se han traducido la descripción de la utilidad, la ayuda CLI, los mensajes de error y advertencia (incluidos sus prefijos), los encabezados de la tabla y del CSV, así como la plantilla de la barra de progreso. La integridad de las claves para cada idioma está garantizada por el compilador.
- **Compilación de la versión final para las cuatro locales.** El comando `zig build release` ahora genera archivos comprimidos por separado para cada una de las cuatro locales (`ru`, `en`, `es`, `fr`) en todas las plataformas admitidas (`x86_64-linux`, `x86_64-windows`, `x86_64-macos`, `aarch64-macos`).
- **Documentación multilingüe.** El README único se ha dividido en cuatro archivos independientes — [`README.md`](README.md) (ruso), [`README.en.md`](README.en.md), [`README.es.md`](README.es.md) y [`README.fr.md`](README.fr.md). En la parte superior de cada archivo se han colocado enlaces cruzados a las demás versiones lingüísticas.

## Otros cambios

- La versión del proyecto se ha elevado a **1.1.0** (véase [`build.zig.zon`](build.zig.zon) y [`src/main.zig`](src/main.zig)).

---

# Notes de version : v1.1.0

Cette version ajoute deux nouvelles langues d'interface à l'utilitaire **CheckLinks** ainsi qu'une documentation multilingue.

## Nouvelles fonctionnalités

- **Prise en charge de l'espagnol (`es`) et du français (`fr`).** L'option de compilation `-Dlocale` accepte désormais `ru|en|es|fr` (par défaut — `ru`). Des catalogues typés complets de messages localisés ont été ajoutés pour l'espagnol et le français dans [`src/i18n.zig`](src/i18n.zig) ; l'énumération des langues prises en charge dans [`src/lang.zig`](src/lang.zig) a été étendue avec les variantes `.es` et `.fr`.
- **Tous les textes de l'interface sont localisés.** La description de l'utilitaire, l'aide CLI, les messages d'erreur et d'avertissement (y compris leurs préfixes), les en-têtes du tableau et du CSV, ainsi que le modèle de la barre de progression sont traduits en espagnol et en français. L'exhaustivité des clés pour chaque langue est garantie par le compilateur.
- **Compilation de version pour les quatre locales.** La commande `zig build release` produit désormais des archives compressées séparément pour chacune des quatre locales (`ru`, `en`, `es`, `fr`) sur toutes les plateformes prises en charge (`x86_64-linux`, `x86_64-windows`, `x86_64-macos`, `aarch64-macos`).
- **Documentation multilingue.** Le README unique a été scindé en quatre fichiers indépendants — [`README.md`](README.md) (russe), [`README.en.md`](README.en.md), [`README.es.md`](README.es.md) et [`README.fr.md`](README.fr.md). Des liens croisés vers les autres versions linguistiques sont placés en haut de chaque fichier.

## Autres

- La version du projet a été portée à **1.1.0** (voir [`build.zig.zon`](build.zig.zon) et [`src/main.zig`](src/main.zig)).