const std = @import("std");
const builtin = @import("builtin");

/// Порт класса `TableFormatter` из PHP-библиотеки splitbrain/php-cli-ru
/// (файл TableFormatter.php) на язык Zig 0.16.0.
///
/// Назначение: вывод текста в несколько колонок с автоподбором ширины,
/// переносом слов и опциональной цветовой подсветкой.
pub const TableFormatter = @This();

// ---------------------------------------------------------------------------
// Поля состояния
// ---------------------------------------------------------------------------

/// Ввод-вывод (std.Io) для доступа к терминалу.
io: std.Io,
/// Аллокатор для временных буферов.
allocator: std.mem.Allocator,
/// Разделитель (border) между колонками. По умолчанию одиночный пробел.
border: []const u8 = " ",
/// Ширина терминала в символах (максимальная ширина строки вывода).
max: usize = 74,

// ---------------------------------------------------------------------------
// Ошибки
// ---------------------------------------------------------------------------

pub const TableFormatterError = error{
    /// Допустима только одна колонка с автоматической шириной '*'.
    OnlyOneFluidColumnAllowed,
    /// Неизвестный формат спецификации ширины столбца.
    UnknownColumnFormat,
    /// Требуемая ширина столбцов превышает доступное пространство.
    ColumnWidthExceedsTerminal,
} || error{OutOfMemory};

// ---------------------------------------------------------------------------
// Colors
// ---------------------------------------------------------------------------

/// Имена цветов, доступных для окраски вывода.
pub const Colors = enum {
    reset,
    black,
    darkgray,
    blue,
    lightblue,
    green,
    lightgreen,
    cyan,
    lightcyan,
    red,
    lightred,
    purple,
    lightpurple,
    brown,
    yellow,
    lightgray,
    white,

    /// Возвращает ANSI-код для данного цвета (в формате `\x1b[...m`).
    pub fn code(self: Colors) []const u8 {
        return switch (self) {
            .reset => "\x1b[0m",
            .black => "\x1b[0;30m",
            .darkgray => "\x1b[1;30m",
            .blue => "\x1b[0;34m",
            .lightblue => "\x1b[1;34m",
            .green => "\x1b[0;32m",
            .lightgreen => "\x1b[1;32m",
            .cyan => "\x1b[0;36m",
            .lightcyan => "\x1b[1;36m",
            .red => "\x1b[0;31m",
            .lightred => "\x1b[1;31m",
            .purple => "\x1b[0;35m",
            .lightpurple => "\x1b[1;35m",
            .brown => "\x1b[0;33m",
            .yellow => "\x1b[1;33m",
            .lightgray => "\x1b[0;37m",
            .white => "\x1b[1;37m",
        };
    }

    /// Оборачивает текст цветовым кодом и кодом сброса: `<code>text<reset>`.
    /// В Zig 0.16.0 возвращает аллоцированную строку.
    pub fn wrap(allocator: std.mem.Allocator, text: []const u8, color: Colors) ![]u8 {
        var out = std.array_list.Managed(u8).initCapacity(allocator, text.len + 9) catch return error.OutOfMemory;
        defer out.deinit();
        try out.appendSlice(color.code());
        try out.appendSlice(text);
        try out.appendSlice(Colors.reset.code());
        return out.toOwnedSlice();
    }

    /// Попытка распознать цвет по имени; возвращает null, если имя неизвестно.
    pub fn parse(name: []const u8) ?Colors {
        inline for (@typeInfo(Colors).@"enum".fields) |f| {
            if (std.mem.eql(u8, name, f.name)) {
                return @enumFromInt(f.value);
            }
        }
        return null;
    }
};

// ---------------------------------------------------------------------------
// Жизненный цикл
// ---------------------------------------------------------------------------

/// Инициализация форматтера. Пытается определить ширину терминала,
/// иначе использует значение по умолчанию 80 (max = 79).
pub fn init(io: std.Io, allocator: std.mem.Allocator) TableFormatter {
    const size = getTerminalSize() catch TerminalSize.default();
    const cols: usize = if (size.cols > 0) @as(usize, size.cols) - 1 else 79;
    return .{
        .io = io,
        .allocator = allocator,
        .max = cols,
    };
}

// ---------------------------------------------------------------------------
// Доступ к свойствам
// ---------------------------------------------------------------------------

/// Текущий разделитель между колонками.
pub fn getBorder(self: *const TableFormatter) []const u8 {
    return self.border;
}

/// Установить разделитель между колонками.
pub fn setBorder(self: *TableFormatter, border: []const u8) void {
    self.border = border;
}

/// Максимальная ширина строки вывода (ширина терминала).
pub fn getMaxWidth(self: *const TableFormatter) usize {
    return self.max;
}

/// Задать максимальную ширину строки вывода вручную.
pub fn setMaxWidth(self: *TableFormatter, max: usize) void {
    self.max = max;
}

// ---------------------------------------------------------------------------
// Определение размера терминала
// ---------------------------------------------------------------------------

/// Размеры терминала.
pub const TerminalSize = struct {
    cols: u16,
    rows: u16,

    pub fn default() TerminalSize {
        return .{ .cols = 80, .rows = 24 };
    }
};

/// Попытка определить размер терминала с учётом платформы.
pub fn getTerminalSize() !TerminalSize {
    switch (builtin.os.tag) {
        .windows => return getWindowsTerminalSize(),
        else => return getPosixTerminalSize(),
    }
}

fn getPosixTerminalSize() !TerminalSize {
    var wsz: std.posix.winsize = .{
        .col = 0,
        .row = 0,
        .xpixel = 0,
        .ypixel = 0,
    };

    const result = std.posix.system.ioctl(std.posix.STDOUT_FILENO, std.posix.T.IOCGWINSZ, @intFromPtr(&wsz));
    if (result != 0) {
        return TerminalSize.default();
    }

    return .{
        .cols = wsz.col,
        .rows = wsz.row,
    };
}

fn getWindowsTerminalSize() !TerminalSize {
    if (builtin.os.tag != .windows) {
        return TerminalSize.default();
    }

    const CONSOLE_SCREEN_BUFFER_INFO = extern struct {
        dwSize: extern struct { X: i16, Y: i16 },
        dwCursorPosition: extern struct { X: i16, Y: i16 },
        wAttributes: u16,
        srWindow: extern struct { Left: i16, Top: i16, Right: i16, Bottom: i16 },
        dwMaximumWindowSize: extern struct { X: i16, Y: i16 },
    };

    const kernel32 = struct {
        extern "kernel32" fn GetConsoleScreenBufferInfo(
            handle: std.os.windows.HANDLE,
            info: *CONSOLE_SCREEN_BUFFER_INFO,
        ) callconv(.winapi) std.os.windows.BOOL;
    };

    const handle = std.os.windows.peb().ProcessParameters.hStdOutput;

    var info: CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (kernel32.GetConsoleScreenBufferInfo(handle, &info) == .FALSE) {
        return TerminalSize.default();
    }

    const w: u16 = @intCast(info.srWindow.Right - info.srWindow.Left + 1);
    const h: u16 = @intCast(info.srWindow.Bottom - info.srWindow.Top + 1);
    return .{ .cols = w, .rows = h };
}

// ---------------------------------------------------------------------------
// Расчёт ширины колонок
// ---------------------------------------------------------------------------

/// Принимает массив спецификаций ширины колонок и вычисляет фактические
/// ширины в символах.
///
/// Форматы:
///  - целое число  — фиксированная ширина в символах;
///  - число + '%'  — процент от оставшегося пространства (после фикс. колонок);
///  - '*'          — одна (и только одна) колонка, забирающая весь остаток.
///
/// Спецификации передаются как `[]const []const u8`. Результат — массив `usize`.
pub fn calculateColLengths(self: *TableFormatter, columns: []const []const u8) TableFormatterError![]usize {
    if (columns.len == 0) return error.OutOfMemory; // результирующий пустой массив не нужен

    var result = try self.allocator.alloc(usize, columns.len);
    errdefer self.allocator.free(result);

    const border_len = self.strlen(self.border);
    var fixed: usize = (columns.len - 1) * border_len; // разделители уже заняты
    var fluid_idx: ?usize = null;

    // --- Первый проход: проверка форматов и фиксированные колонки ---
    for (columns, 0..) |col, idx| {
        // Целочисленная фиксированная ширина
        if (parseUsize(col)) |n| {
            fixed += n;
            result[idx] = n;
            continue;
        }

        // Процент
        if (isPercent(col)) {
            result[idx] = 0; // заполним во втором проходе
            continue;
        }

        // Автоматическая ширина '*'
        if (std.mem.eql(u8, col, "*")) {
            if (fluid_idx != null) {
                return error.OnlyOneFluidColumnAllowed;
            }
            fluid_idx = idx;
            result[idx] = 0; // заполним в конце
            continue;
        }

        return error.UnknownColumnFormat;
    }

    // --- Второй проход: проценты от оставшегося места ---
    // Все процентные колонки рассчитываются от одного и того же остатка —
    // пространства после фиксированных колонок и разделителей (max - fixed).
    if (fixed > self.max) {
        return error.ColumnWidthExceedsTerminal;
    }
    const percent_base: f64 = @floatFromInt(self.max - fixed);

    var allocated: usize = fixed;
    for (columns, 0..) |col, idx| {
        if (!isPercent(col)) continue;

        const percent = parsePercent(col);
        const real: usize = @intFromFloat(@floor((percent * percent_base) / 100.0));
        result[idx] = real;
        allocated += real;
    }

    if (allocated > self.max) {
        return error.ColumnWidthExceedsTerminal;
    }
    const remain: usize = self.max - allocated;

    // --- Распределение оставшегося пространства ---
    if (fluid_idx) |idx| {
        result[idx] += remain;
    } else {
        // без '*' остаток добавляем к последней колонке
        result[columns.len - 1] += remain;
    }

    return result;
}

/// Проверяет, является ли строка спецификацией процента (оканчивается на '%').
fn isPercent(col: []const u8) bool {
    return col.len > 1 and col[col.len - 1] == '%';
}

/// Извлекает числовое значение из процентной спецификации `"NN%"`.
fn parsePercent(col: []const u8) f64 {
    const num = col[0 .. col.len - 1];
    return std.fmt.parseFloat(f64, num) catch 0.0;
}

/// Пытается разобрать неотрицательное целое. Возвращает null при неудаче.
fn parseUsize(col: []const u8) ?usize {
    if (col.len == 0) return null;
    for (col) |c| {
        if (c < '0' or c > '9') return null;
    }
    return std.fmt.parseInt(usize, col, 10) catch null;
}

// ---------------------------------------------------------------------------
// Форматирование таблицы
// ---------------------------------------------------------------------------

/// Отображает тексты в несколько колонок с переносом слов.
///
/// Параметры:
///  - `columns` — спецификации ширины колонок (число, '%', '*');
///  - `texts`   — тексты для каждой колонки (количество должно совпадать);
///  - `colors`  — опциональный массив цветов для колонок (может быть пустым);
///
/// Возвращает аллоцированную строку готовой таблицы.
pub fn format(
    self: *TableFormatter,
    columns: []const []const u8,
    texts: []const []const u8,
    colors: []const ?Colors,
) TableFormatterError![]u8 {
    if (texts.len != columns.len) return error.UnknownColumnFormat;

    const widths = try self.calculateColLengths(columns);
    defer self.allocator.free(widths);

    var out = std.array_list.Managed(u8).initCapacity(self.allocator, self.max * texts.len) catch return error.OutOfMemory;
    defer out.deinit();

    // Перенос текстов по колонкам; вычисляем максимальное число строк.
    var wrapped = try self.allocator.alloc([]const u8, texts.len);
    defer self.allocator.free(wrapped);

    var maxlen: usize = 0;
    for (texts, 0..) |text, i| {
        const wrapped_text = try self.wordwrap(text, widths[i], "\n", true);
        wrapped[i] = wrapped_text;

        const line_count = countLines(wrapped_text);
        if (line_count > maxlen) maxlen = line_count;
    }
    defer {
        for (wrapped) |w| self.allocator.free(w);
    }

    const last_col = columns.len - 1;
    for (0..maxlen) |row| {
        for (columns, 0..) |_, col| {
            const line = nthLine(wrapped[col], row);
            var chunk = try self.pad(line, widths[col]);
            defer self.allocator.free(chunk);

            if (colors.len > col) {
                if (colors[col]) |color| {
                    const colored = try Colors.wrap(self.allocator, chunk, color);
                    self.allocator.free(chunk);
                    chunk = colored;
                }
            }

            try out.appendSlice(chunk);

            if (col != last_col) {
                try out.appendSlice(self.border);
            }
        }
        try out.appendSlice("\n");
    }

    return out.toOwnedSlice();
}

/// Количество строк в тексте (разделитель '\n').
fn countLines(text: []const u8) usize {
    if (text.len == 0) return 1;
    var count: usize = 1;
    for (text) |c| {
        if (c == '\n') count += 1;
    }
    return count;
}

/// Возвращает строку с индексом `row` (0-based) из текста, разбитого по '\n'.
/// Если такой строки нет — возвращает пустую строку.
fn nthLine(text: []const u8, row: usize) []const u8 {
    var start: usize = 0;
    var current: usize = 0;
    var i: usize = 0;
    while (i <= text.len) : (i += 1) {
        if (i == text.len or text[i] == '\n') {
            if (current == row) {
                return text[start..i];
            }
            current += 1;
            start = i + 1;
        }
    }
    return "";
}

// ---------------------------------------------------------------------------
// Вспомогательные утилиты для строк
// ---------------------------------------------------------------------------

/// Дополняет строку справа пробелами до длины `len` (в символах).
/// Если строка длиннее — возвращает её без изменений.
fn pad(self: *TableFormatter, string: []const u8, len: usize) TableFormatterError![]u8 {
    const str_len = self.strlen(string);
    if (str_len >= len) {
        return self.allocator.dupe(u8, string);
    }

    const pad_len = len - str_len;
    var out = std.array_list.Managed(u8).initCapacity(self.allocator, string.len + pad_len) catch return error.OutOfMemory;
    defer out.deinit();
    try out.appendSlice(string);
    for (0..pad_len) |_| {
        try out.append(' ');
    }
    return out.toOwnedSlice();
}

/// Длина строки в символах (кодовых точках UTF-8), без учёта ANSI-кодов.
pub fn strlen(self: *TableFormatter, string: []const u8) usize {
    const clean = self.removeAnsiCodes(string);
    defer self.allocator.free(clean);

    return std.unicode.utf8CountCodepoints(clean) catch clean.len;
}

/// Удаляет ANSI-escape-последовательности вида `\x1b[<num>(;<num>)m` из строки.
/// Возвращает аллоцированную строку без этих кодов.
fn removeAnsiCodes(self: *TableFormatter, string: []const u8) []u8 {
    var out = std.array_list.Managed(u8).initCapacity(self.allocator, string.len) catch return "";
    defer out.deinit();

    var i: usize = 0;
    while (i < string.len) {
        if (string[i] == 0x1B) {
            // Пропускаем последовательность до 'm'
            i += 1;
            while (i < string.len and string[i] != 'm') : (i += 1) {}
            if (i < string.len and string[i] == 'm') i += 1;
            continue;
        }
        out.append(string[i]) catch break;
        i += 1;
    }

    return out.toOwnedSlice() catch "";
}

/// Возвращает подстроку по кодовым точкам UTF-8.
/// `start` — начальная позиция, `len` — количество символов (null = до конца).
fn substr(self: *TableFormatter, string: []const u8, start: usize, len: ?usize) TableFormatterError![]u8 {
    const view = std.unicode.Utf8View.init(string) catch return self.allocator.dupe(u8, "");

    // Собираем кодовые точки в диапазон [start, start+len)
    var count: usize = 0;
    const end: usize = if (len) |l| start + l else std.math.maxInt(usize);

    var out = std.array_list.Managed(u8).initCapacity(self.allocator, string.len) catch return error.OutOfMemory;
    defer out.deinit();

    var iter = view.iterator();
    while (iter.nextCodepointSlice()) |seq| {
        if (count >= end) break;
        if (count >= start) {
            try out.appendSlice(seq);
        }
        count += 1;
    }

    return out.toOwnedSlice();
}

/// Переносит текст по словам до заданной ширины (в символах).
///
/// Параметры:
///  - `str`   — исходный текст;
///  - `width` — максимальная ширина строки;
///  - `break` — разделитель переноса (обычно '\n');
///  - `cut`   — разрешить ли разрыв длинных слов, не влезающих в строку.
pub fn wordwrap(
    self: *TableFormatter,
    str: []const u8,
    width: usize,
    break_str: []const u8,
    cut: bool,
) TableFormatterError![]u8 {
    var out = std.array_list.Managed(u8).initCapacity(self.allocator, str.len + 8) catch return error.OutOfMemory;
    defer out.deinit();

    // Проходим по логическим строкам, разделённым break_str.
    var line_start: usize = 0;
    var i: usize = 0;
    var first_line = true;
    while (i <= str.len) {
        const at_end = (i == str.len);
        const at_break = (!at_end and std.mem.startsWith(u8, str[i..], break_str));

        if (at_end or at_break) {
            const raw = str[line_start..i];
            const line = std.mem.trimEnd(u8, raw, " \t");
            if (!first_line) try out.appendSlice(break_str);
            first_line = false;
            try self.wrapLine(&out, line, width, break_str, cut);

            if (at_break) {
                i += break_str.len;
            } else {
                i += 1;
            }
            line_start = i;
        } else {
            i += 1;
        }
    }

    return out.toOwnedSlice();
}

/// Переносит одну логическую строку по словам, дописывая результат в `out`.
fn wrapLine(
    self: *TableFormatter,
    out: *std.array_list.Managed(u8),
    line: []const u8,
    width: usize,
    break_str: []const u8,
    cut: bool,
) TableFormatterError!void {
    if (self.strlen(line) <= width) {
        try out.appendSlice(line);
        return;
    }

    // Слова — срезы исходной строки, владение остаётся за `line`.
    var words = splitByWhitespace(line);
    defer words.deinit();

    var actual = std.array_list.Managed(u8).initCapacity(self.allocator, line.len) catch return error.OutOfMemory;
    defer actual.deinit();

    for (words.items) |word| {
        if (self.strlen(actual.items) + self.strlen(word) <= width) {
            try actual.appendSlice(word);
            try actual.appendSlice(" ");
        } else {
            if (actual.items.len > 0) {
                try out.appendSlice(std.mem.trimEnd(u8, actual.items, " "));
                try out.appendSlice(break_str);
            }
            actual.clearRetainingCapacity();
            try actual.appendSlice(word);
            if (cut) {
                while (self.strlen(actual.items) > width) {
                    const slice = try self.substr(actual.items, 0, width);
                    try out.appendSlice(slice);
                    self.allocator.free(slice);
                    try out.appendSlice(break_str);
                    const rest = try self.substr(actual.items, width, null);
                    actual.clearRetainingCapacity();
                    try actual.appendSlice(rest);
                    self.allocator.free(rest);
                }
            }
            try actual.appendSlice(" ");
        }
    }

    try out.appendSlice(std.mem.trim(u8, actual.items, " "));
}

/// Разбивает строку по пробелам и табуляции. Возвращает список срезов,
/// ссылающихся на память исходной строки (владение не передаётся).
fn splitByWhitespace(str: []const u8) std.array_list.Managed([]const u8) {
    var result = std.array_list.Managed([]const u8).init(std.heap.page_allocator);
    var i: usize = 0;
    while (i < str.len) {
        while (i < str.len and (str[i] == ' ' or str[i] == '\t')) : (i += 1) {}
        if (i >= str.len) break;
        const start = i;
        while (i < str.len and str[i] != ' ' and str[i] != '\t') : (i += 1) {}
        result.append(str[start..i]) catch break;
    }
    return result;
}

// ---------------------------------------------------------------------------
// Тесты
// ---------------------------------------------------------------------------

const testing = std.testing;

fn initForTest() TableFormatter {
    var tf = TableFormatter.init(testing.io, testing.allocator);
    tf.setMaxWidth(74);
    return tf;
}

// --- getTerminalSize ---

test "getTerminalSize возвращает размер по умолчанию в среде тестов" {
    const size = try getTerminalSize();
    try testing.expect(size.cols > 0);
}

// --- strlen ---

test "strlen считает латинские символы" {
    var tf = initForTest();
    try testing.expectEqual(@as(usize, 5), tf.strlen("hello"));
    try testing.expectEqual(@as(usize, 0), tf.strlen(""));
}

test "strlen считает кириллические символы как одну кодовую точку" {
    var tf = initForTest();
    // "привет" — 6 символов кириллицы
    try testing.expectEqual(@as(usize, 6), tf.strlen("привет"));
    // Смешанная строка: "aбв" = 1 + 2 = 3
    try testing.expectEqual(@as(usize, 3), tf.strlen("aбв"));
}

test "strlen игнорирует ANSI-коды" {
    var tf = initForTest();
    const colored = "\x1b[1;31mкрасный\x1b[0m";
    // "красный" = 7 символов, коды ANSI не считаются
    try testing.expectEqual(@as(usize, 7), tf.strlen(colored));
}

// --- calculateColLengths ---

test "calculateColLengths: фиксированные ширины" {
    var tf = initForTest();

    const columns = [_][]const u8{ "10", "20", "30" };
    const result = try tf.calculateColLengths(&columns);
    defer testing.allocator.free(result);

    // max=74, border=' ' (1 символ) * 2 разделителя = 2,
    // фикс. 10+20+30=60, остаток 74-62=12 уходит в последнюю колонку
    try testing.expectEqualSlices(usize, &[_]usize{ 10, 20, 42 }, result);
}

test "calculateColLengths: проценты и остаток" {
    var tf = initForTest();

    const columns = [_][]const u8{ "10%", "20%", "70%" };
    const result = try tf.calculateColLengths(&columns);
    defer testing.allocator.free(result);

    // max=74, border=' ' (1 символ) между 3 колонками = 2 символа.
    // Колонки занимают max - границы = 72 символа, независимо от округления.
    const total: usize = result[0] + result[1] + result[2];
    try testing.expectEqual(@as(usize, 72), total);
    // 10% от (74-2)=72 → floor(7.2)=7
    try testing.expectEqual(@as(usize, 7), result[0]);
}

test "calculateColLengths: проценты строго" {
    var tf = initForTest();
    const columns = [_][]const u8{ "4%", "45%", "45%", "*" };
    const result = try tf.calculateColLengths(&columns);
    defer std.testing.allocator.free(result);

    // std.debug.print("Result: {any}\n", .{result});

    // max=74, border=' ' (1 символ) между 4 колонками = 3 разделителя.
    // Колонки занимают max - границы = 71 символ, независимо от округления.
    const total: usize = result[0] + result[1] + result[2] + result[3];
    try testing.expectEqual(@as(usize, 71), total);
    // 4% и 45% считаются от одной базы (max - границы = 71):
    // 4% → floor(2.84)=2, 45% → floor(31.95)=31. Одинаковые проценты → одинаковая ширина.
    try testing.expectEqual(result[1], result[2]);
    try testing.expectEqual(@as(usize, 31), result[1]);
}

test "calculateColLengths: единственная колонка '*'" {
    var tf = initForTest();

    const columns = [_][]const u8{"*"};
    const result = try tf.calculateColLengths(&columns);
    defer testing.allocator.free(result);

    try testing.expectEqualSlices(usize, &[_]usize{74}, result);
}

test "calculateColLengths: '*' забирает остаток после фикс. колонок" {
    var tf = initForTest();

    const columns = [_][]const u8{ "10", "20", "*" };
    const result = try tf.calculateColLengths(&columns);
    defer testing.allocator.free(result);

    // max=74, border 1*2=2, фикс. 30, остаток 42 уходит в '*'
    try testing.expectEqualSlices(usize, &[_]usize{ 10, 20, 42 }, result);
}

test "calculateColLengths: ошибка при двух колонках '*'" {
    var tf = initForTest();

    const columns = [_][]const u8{ "*", "*" };
    try testing.expectError(error.OnlyOneFluidColumnAllowed, tf.calculateColLengths(&columns));
}

test "calculateColLengths: ошибка при неизвестном формате" {
    var tf = initForTest();

    const columns = [_][]const u8{ "10", "abc" };
    try testing.expectError(error.UnknownColumnFormat, tf.calculateColLengths(&columns));
}

test "calculateColLengths: ошибка при превышении ширины" {
    var tf = initForTest();
    tf.setMaxWidth(10);

    const columns = [_][]const u8{ "30", "30" };
    try testing.expectError(error.ColumnWidthExceedsTerminal, tf.calculateColLengths(&columns));
}

// --- pad ---

test "pad дополняет короткую строку пробелами" {
    var tf = initForTest();

    const padded = try tf.pad("ab", 5);
    defer testing.allocator.free(padded);
    try testing.expectEqualStrings("ab   ", padded);
}

test "pad не обрезает длинную строку" {
    var tf = initForTest();

    const padded = try tf.pad("длинная-строка", 5);
    defer testing.allocator.free(padded);
    try testing.expectEqualStrings("длинная-строка", padded);
}

// --- wordwrap ---

test "wordwrap: короткая строка не переносится" {
    var tf = initForTest();

    const result = try tf.wordwrap("короткий", 20, "\n", false);
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("короткий", result);
}

test "wordwrap: перенос по словам" {
    var tf = initForTest();

    const result = try tf.wordwrap("один два три", 8, "\n", false);
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("один два\nтри", result);
}

test "wordwrap: cut длинного слова" {
    var tf = initForTest();

    const result = try tf.wordwrap("abcdefghijk", 5, "\n", true);
    defer testing.allocator.free(result);
    // 11 символов, ширина 5 => abcde\nfghij\nk
    try testing.expectEqualStrings("abcde\nfghij\nk", result);
}

test "wordwrap: длинное слово без cut не режется полностью" {
    var tf = initForTest();

    const result = try tf.wordwrap("abcdefghijk", 5, "\n", false);
    defer testing.allocator.free(result);
    // без cut слово не влезает, но не разбивается насильно
    try testing.expectEqualStrings("abcdefghijk", result);
}

test "wordwrap: многострочный ввод сохраняет переносы" {
    var tf = initForTest();

    const result = try tf.wordwrap("первая строка\nвторая строка", 50, "\n", false);
    defer testing.allocator.free(result);
    try testing.expectEqualStrings("первая строка\nвторая строка", result);
}

// --- format ---

test "format: простая таблица с border" {
    var tf = initForTest();
    tf.setBorder(" | ");

    const columns = [_][]const u8{ "10", "20", "*" };
    const texts = [_][]const u8{ "привет", "мир", "!" };
    const result = try tf.format(&columns, &texts, &.{});
    defer testing.allocator.free(result);

    // Строка должна содержать разделители
    try testing.expect(std.mem.indexOf(u8, result, " | ") != null);
    // Должна заканчиваться переносом строки
    try testing.expect(result.len > 0 and result[result.len - 1] == '\n');
}

test "format: цвета оборачивают колонку" {
    var tf = initForTest();

    const columns = [_][]const u8{ "10", "*" };
    const texts = [_][]const u8{ "привет", "мир" };
    const colors = [_]?Colors{ .red, null };
    const result = try tf.format(&columns, &texts, &colors);
    defer testing.allocator.free(result);

    // Красный код должен присутствовать, а сброс — в конце цветной части
    try testing.expect(std.mem.indexOf(u8, result, "\x1b[0;31m") != null);
    try testing.expect(std.mem.indexOf(u8, result, "\x1b[0m") != null);
}

test "format: округление процентов корректно распределяет ширину" {
    var tf = initForTest();

    const columns = [_][]const u8{ "4%", "45%", "45%", "*" };
    const texts = [_][]const u8{ " № ", "URL", "Проверенный URL", "Код" };
    const result = try tf.format(&columns, &texts, &.{});
    defer testing.allocator.free(result);

    // 4% от 74 = 2, 45% от 74 = 33 (×2 = 66), итого 68, остаток 6 в '*'
    try testing.expect(result.len > 0);
    try testing.expect(std.mem.indexOf(u8, result, "Код") != null);
}

test "format: перенос длинного текста в колонке" {
    var tf = initForTest();

    const columns = [_][]const u8{ "5", "*" };
    const texts = [_][]const u8{ "short", "это очень длинный текст который должен быть перенесён на несколько строк" };
    const result = try tf.format(&columns, &texts, &.{});
    defer testing.allocator.free(result);

    // Многострочный вывод — должен содержать несколько '\n'
    var newlines: usize = 0;
    for (result) |c| {
        if (c == '\n') newlines += 1;
    }
    try testing.expect(newlines > 1);
}

// --- Colors ---

test "Colors.parse распознаёт известные имена" {
    try testing.expectEqual(Colors.red, Colors.parse("red").?);
    try testing.expectEqual(Colors.reset, Colors.parse("reset").?);
    try testing.expect(Colors.parse("nonexistent") == null);
}

test "Colors.wrap оборачивает текст кодом и сбросом" {
    const wrapped = try Colors.wrap(testing.allocator, "текст", Colors.green);
    defer testing.allocator.free(wrapped);
    try testing.expectEqualStrings("\x1b[0;32mтекст\x1b[0m", wrapped);
}
