//! Интернационализация пользовательских строк.
//!
//! Содержит типизированный каталог сообщений (`Messages`), реализованный
//! для локалей `ru` и `en`. Активная локаль выбирается на этапе сборки через
//! build-опцию `-Dlocale` и инжектируется как `build_options.locale`.
//!
//! Все хелперы вывода в приложении принимают `comptime fmt`, поэтому значения
//! `Messages` (формат-строки с плейсхолдерами `{s}`) подставляются напрямую,
//! без изменения сигнатур хелперов.

const lang = @import("lang.zig");
const build_options = @import("build_options");

pub const Lang = lang.Lang;

/// Шаблон каталога сообщений. Типизация гарантирует полноту: если в какой-то
/// локали не хватает поля — возникает ошибка компиляции.
pub const Messages = struct {
    desc: []const u8,
    help_fail: []const u8,
    help_export: []const u8,
    help_timeout: []const u8,
    help_parallels: []const u8,
    help_header: []const u8,
    help_url: []const u8,
    err_out_of_memory: []const u8,
    err_no_url: []const u8,
    err_header_format: []const u8,
    err_header_name: []const u8,
    err_header_value: []const u8,
    err_header_managed: []const u8,
    err_header_other: []const u8,
    err_prefix: []const u8,
    warn_prefix: []const u8,
    err_load_failed: []const u8,
    err_invalid_url: []const u8,
    warn_no_urls: []const u8,
    err_check_links: []const u8,
    err_export_csv: []const u8,
    err_render_table: []const u8,
    msg_empty_list: []const u8,
    col_num: []const u8,
    col_page_url: []const u8,
    col_checked_url: []const u8,
    col_http_code: []const u8,
    csv_header: []const u8,
    progress_template: []const u8,
    completion: []const u8,
    err_no_shell: []const u8,
    err_generate_completion: []const u8,
    err_init_parser: []const u8,
    usage: []const u8,
    arguments: []const u8,
    commands: []const u8,
    command_tag: []const u8,
    options: []const u8,
    options_tag: []const u8,
    required: []const u8,
    help: []const u8,
    version: []const u8,
    default: []const u8,
};

/// Русская локаль (по умолчанию).
pub const ru: Messages = .{
    .desc =
    \\CheckLinks
    \\
    \\Утилита CLI для проверки ссылок на веб-странице. Загружает HTML-страницу
    \\по указанному URL, собирает все ссылки (<a href>) и изображения (<img src>),
    \\затем проверяет каждый URL на доступность и выводит результат на экран
    \\в виде таблицы или в CSV-файл.
    ,
    .help_fail = "Выводить только результаты с ошибками.",
    .help_export = "Вывод в формате CSV",
    .help_timeout = "Таймаут в секундах",
    .help_parallels = "Число параллельных запросов",
    .help_header = "Установить HTTP-заголовок (можно повторять)",
    .help_url = "Проверяемый URL.",
    .err_out_of_memory = "недостаточно памяти",
    .err_no_url = "не указан проверяемый URL",
    .err_header_format = "заголовок должен иметь формат NAME: VALUE",
    .err_header_name = "имя заголовка некорректно",
    .err_header_value = "значение заголовка содержит запрещённый перевод строки",
    .err_header_managed = "Content-Length и Transfer-Encoding задаются HTTP-клиентом",
    .err_header_other = "не удалось обработать HTTP-заголовки",
    .err_prefix = "Ошибка:",
    .warn_prefix = "Предупреждение:",
    .err_load_failed = "Ошибка при загрузке страницы: {s}",
    .err_invalid_url = "Некорректный URL: {s}",
    .warn_no_urls = "URL на указанной странице {s} не найдены",
    .err_check_links = "Ошибка при проверке ссылок",
    .err_export_csv = "Ошибка при экспорте в CSV: {s}",
    .err_render_table = "Ошибка при выводе таблицы",
    .msg_empty_list = "Передан пустой список проверенных ссылок",
    .col_num = " № ",
    .col_page_url = "URL страницы",
    .col_checked_url = "Проверенный URL",
    .col_http_code = "HTTP Код",
    .csv_header = "№;URL страницы;Проверенный URL;HTTP Код",
    .progress_template = "Обработка: [:bar] - :current/:total - :percent% - Прошло::elapseds - Осталось::etas - Скорость::rate/s",
    .completion = "Генерация скрипта для автодополнения",
    .err_no_shell = "Неизвестный тип оболочки",
    .err_generate_completion = "Ошибка при генерации скрипта для автодополнения",
    .err_init_parser = "Ошибка инициализации парсера. Код ошибки: ",
    .arguments = "АРГУМЕНТЫ:",
    .commands = "КОМАНДЫ:",
    .command_tag = " <КОМАНДА>",
    .options = "ОПЦИИ:",
    .options_tag = " [ОПЦИИ]",
    .required = "[обязательно]",
    .help = "Вывести эту справку",
    .version = "Вывести версию",
    .usage = "ИСПОЛЬЗОВАНИЕ:",
    .default = "[по умолчанию: ",
};

/// Английская локаль.
pub const en: Messages = .{
    .desc =
    \\CheckLinks
    \\
    \\A CLI utility for checking links on a web page. It loads the HTML page
    \\at the specified URL, collects all links (<a href>) and images (<img src>),
    \\then checks each URL for availability and displays the result on the screen
    \\in table form or in a CSV file.
    ,
    .help_fail = "Output results with errors only.",
    .help_export = "Output in CSV format",
    .help_timeout = "Timeout in seconds",
    .help_parallels = "Number of parallel requests",
    .help_header = "Set an HTTP header (can be repeated)",
    .help_url = "The URL to check.",
    .err_out_of_memory = "not enough memory",
    .err_no_url = "no URL to check was provided",
    .err_header_format = "header must have the NAME: VALUE format",
    .err_header_name = "invalid header name",
    .err_header_value = "header value contains a forbidden line break",
    .err_header_managed = "Content-Length and Transfer-Encoding are set by the HTTP client",
    .err_header_other = "failed to process HTTP headers",
    .err_prefix = "Error:",
    .warn_prefix = "Warning:",
    .err_load_failed = "Error loading page: {s}",
    .err_invalid_url = "Invalid URL: {s}",
    .warn_no_urls = "No URLs found on page {s}",
    .err_check_links = "Error while checking links",
    .err_export_csv = "Error exporting to CSV: {s}",
    .err_render_table = "Error rendering the table",
    .msg_empty_list = "An empty list of checked links was passed",
    .col_num = " No ",
    .col_page_url = "Page URL",
    .col_checked_url = "Checked URL",
    .col_http_code = "HTTP Code",
    .csv_header = "No;Page URL;Checked URL;HTTP Code",
    .progress_template = "Processing: [:bar] - :current/:total - :percent% - Elapsed::elapseds - ETA::etas - Rate::rate/s",
    .completion = "Generate completion script",
    .err_no_shell = "Unknown shell type",
    .err_generate_completion = "Error generating completion script",
    .err_init_parser = "Error initializing program. Error: ",
    .arguments = "ARGUMENTS:",
    .commands = "COMMANDS:",
    .command_tag = " <COMMAND>",
    .options = "OPTIONS:",
    .options_tag = " [OPTIONS]",
    .required = "[required]",
    .help = "Show this help",
    .version = "Show version",
    .usage = "USAGE:",
    .default = "[default: ",
};

/// Испанская локаль.
pub const es: Messages = .{
    .desc =
    \\CheckLinks
    \\
    \\Una utilidad CLI para comprobar los enlaces de una página web. Carga la
    \\página HTML en la URL indicada, recopila todos los enlaces (<a href>) e
    \\imágenes (<img src>), luego comprueba la disponibilidad de cada URL y
    \\muestra el resultado en pantalla en forma de tabla o en un archivo CSV.
    ,
    .help_fail = "Mostrar solo los resultados con errores.",
    .help_export = "Salida en formato CSV",
    .help_timeout = "Tiempo de espera en segundos",
    .help_parallels = "Número de solicitudes paralelas",
    .help_header = "Establecer una cabecera HTTP (se puede repetir)",
    .help_url = "La URL a comprobar.",
    .err_out_of_memory = "memoria insuficiente",
    .err_no_url = "no se proporcionó ninguna URL para comprobar",
    .err_header_format = "la cabecera debe tener el formato NAME: VALUE",
    .err_header_name = "nombre de cabecera no válido",
    .err_header_value = "el valor de la cabecera contiene un salto de línea prohibido",
    .err_header_managed = "Content-Length y Transfer-Encoding son establecidos por el cliente HTTP",
    .err_header_other = "no se pudieron procesar las cabeceras HTTP",
    .err_prefix = "Error:",
    .warn_prefix = "Advertencia:",
    .err_load_failed = "Error al cargar la página: {s}",
    .err_invalid_url = "URL no válida: {s}",
    .warn_no_urls = "No se encontraron URLs en la página {s}",
    .err_check_links = "Error al comprobar los enlaces",
    .err_export_csv = "Error al exportar a CSV: {s}",
    .err_render_table = "Error al mostrar la tabla",
    .msg_empty_list = "Se pasó una lista vacía de enlaces comprobados",
    .col_num = " Nº ",
    .col_page_url = "URL de la página",
    .col_checked_url = "URL comprobada",
    .col_http_code = "Código HTTP",
    .csv_header = "Nº;URL de la página;URL comprobada;Código HTTP",
    .progress_template = "Procesando: [:bar] - :current/:total - :percent% - Transcurrido::elapseds - Restante::etas - Velocidad::rate/s",
    .completion = "Generar el script de autocompletado",
    .err_no_shell = "Tipo de shell desconocido",
    .err_generate_completion = "Error al generar el script de autocompletado",
    .err_init_parser = "Error al inicializar el programa. Error: ",
    .arguments = "ARGUMENTOS:",
    .commands = "COMANDOS:",
    .command_tag = " <COMANDO>",
    .options = "OPCIONES:",
    .options_tag = " [OPCIONES]",
    .required = "[obligatorio]",
    .help = "Mostrar esta ayuda",
    .version = "Mostrar la versión",
    .usage = "USO:",
    .default = "[por defecto: ",
};

/// Французская локаль.
pub const fr: Messages = .{
    .desc =
    \\CheckLinks
    \\
    \\Un utilitaire CLI pour vérifier les liens d'une page web. Il charge la page
    \\HTML à l'URL indiquée, collecte tous les liens (<a href>) et les images
    \\(<img src>), puis vérifie la disponibilité de chaque URL et affiche le
    \\résultat à l'écran sous forme de tableau ou dans un fichier CSV.
    ,
    .help_fail = "Afficher uniquement les résultats avec des erreurs.",
    .help_export = "Sortie au format CSV",
    .help_timeout = "Délai d'attente en secondes",
    .help_parallels = "Nombre de requêtes parallèles",
    .help_header = "Définir un en-tête HTTP (peut être répété)",
    .help_url = "L'URL à vérifier.",
    .err_out_of_memory = "mémoire insuffisante",
    .err_no_url = "aucune URL à vérifier n'a été fournie",
    .err_header_format = "l'en-tête doit avoir le format NAME: VALUE",
    .err_header_name = "nom d'en-tête invalide",
    .err_header_value = "la valeur de l'en-tête contient un saut de ligne interdit",
    .err_header_managed = "Content-Length et Transfer-Encoding sont définis par le client HTTP",
    .err_header_other = "échec du traitement des en-têtes HTTP",
    .err_prefix = "Erreur :",
    .warn_prefix = "Avertissement :",
    .err_load_failed = "Erreur lors du chargement de la page : {s}",
    .err_invalid_url = "URL invalide : {s}",
    .warn_no_urls = "Aucune URL trouvée sur la page {s}",
    .err_check_links = "Erreur lors de la vérification des liens",
    .err_export_csv = "Erreur lors de l'exportation en CSV : {s}",
    .err_render_table = "Erreur lors de l'affichage du tableau",
    .msg_empty_list = "Une liste vide de liens vérifiés a été passée",
    .col_num = " N° ",
    .col_page_url = "URL de la page",
    .col_checked_url = "URL vérifiée",
    .col_http_code = "Code HTTP",
    .csv_header = "N°;URL de la page;URL vérifiée;Code HTTP",
    .progress_template = "Traitement : [:bar] - :current/:total - :percent% - Écoulé::elapseds - Restant::etas - Vitesse::rate/s",
    .completion = "Générer le script de complétion",
    .err_no_shell = "Type de shell inconnu",
    .err_generate_completion = "Erreur lors de la génération du script de complétion",
    .err_init_parser = "Erreur lors de l'initialisation du programme. Erreur : ",
    .arguments = "ARGUMENTS :",
    .commands = "COMMANDES :",
    .command_tag = " <COMMANDE>",
    .options = "OPTIONS :",
    .options_tag = " [OPTIONS]",
    .required = "[obligatoire]",
    .help = "Afficher cette aide",
    .version = "Afficher la version",
    .usage = "UTILISATION :",
    .default = "[par défaut : ",
};

/// Активная локаль, выбранная build-опцией `-Dlocale` (по умолчанию `ru`).
///
/// `build_options.locale` — константа, известная на этапе компиляции, поэтому
/// значение `Current` также вычисляется в `comptime`-контексте.
pub const Current: Messages = switch (build_options.locale) {
    .ru => ru,
    .en => en,
    .es => es,
    .fr => fr,
};
