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

/// Активная локаль, выбранная build-опцией `-Dlocale` (по умолчанию `ru`).
///
/// `build_options.locale` — константа, известная на этапе компиляции, поэтому
/// значение `Current` также вычисляется в `comptime`-контексте.
pub const Current: Messages = switch (build_options.locale) {
    .ru => ru,
    .en => en,
};
