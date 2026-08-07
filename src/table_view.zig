//! Вывод результатов проверки ссылок в виде таблицы в терминал.
//!
//! Аналог PHP-класса `TableView`. Формирует таблицу с колонками
//! «№», «URL страницы», «Проверенный URL», «HTTP Код» и окрашивает
//! HTTP-коды в зависимости от диапазона (2xx — зелёный, 3xx — жёлтый,
//! 4xx/5xx — красный). При опции `fail` выводятся только ошибочные ссылки.
//!
//! Таблица растягивается на всю ширину терминала: ширина колонок
//! вычисляется динамически на основе размера окна терминала и длины
//! содержимого.

const std = @import("std");
const check_link_list = @import("check_link_list.zig");

/// ANSI-коды цветов.
const Color = struct {
    const reset = "\x1b[0m";
    const green = "\x1b[32m";
    const yellow = "\x1b[33m";
    const red = "\x1b[31m";
};

/// Ширина терминала по умолчанию, если её не удалось определить.
const default_terminal_width: usize = 80;

/// Минимальная ширина колонки с URL.
const min_url_width: usize = 10;

/// Выводит таблицу результатов проверки ссылок в stdout.
///
/// `io` используется для записи в stdout. `url` — URL проверяемой страницы.
/// `checked_list` — сгруппированные по HTTP-коду результаты.
/// `fail` — если true, выводятся только ошибочные ссылки (HTTP-код != 200).
pub fn renderTableView(
    io: std.Io,
    allocator: std.mem.Allocator,
    url: []const u8,
    checked_list: *const check_link_list.CheckedList,
    fail: bool,
) !void {
    if (checked_list.groups.items.len == 0) {
        try printLine(io, "Передан пустой список проверенных ссылок", .{});
        return;
    }

    // Сортируем группы по HTTP-коду.
    var sorted = std.ArrayList(check_link_list.CheckedList.Group).empty;
    defer sorted.deinit(allocator);
    for (checked_list.groups.items) |group| {
        try sorted.append(allocator, group);
    }
    std.mem.sort(check_link_list.CheckedList.Group, sorted.items, {}, struct {
        fn lessThan(_: void, a: check_link_list.CheckedList.Group, b: check_link_list.CheckedList.Group) bool {
            return a.http_code < b.http_code;
        }
    }.lessThan);

    // Собираем строки таблицы (только те, что будут выведены).
    var rows = std.ArrayList(Row).empty;
    defer rows.deinit(allocator);

    var line_number: usize = 1;
    for (sorted.items) |group| {
        // Если указана опция --fail, то выводим только ошибки.
        if (fail and group.http_code == 200) continue;

        for (group.urls.items) |checked_url| {
            try rows.append(allocator, .{
                .number = line_number,
                .page_url = url,
                .checked_url = checked_url,
                .http_code = group.http_code,
            });
            line_number += 1;
        }
    }

    if (rows.items.len == 0) {
        try printLine(io, "Нет результатов для отображения", .{});
        return;
    }

    // Определяем ширину терминала.
    const terminal_width = getTerminalWidth(io) orelse default_terminal_width;

    // Вычисляем ширины колонок.
    const widths = computeWidths(rows.items, terminal_width);

    // Формируем разделитель.
    const separator = try buildSeparator(allocator, widths);
    defer allocator.free(separator);

    try printLine(io, "{s}", .{separator});

    const header = try formatHeader(allocator, widths);
    defer allocator.free(header);
    try printLine(io, "{s}", .{header});

    try printLine(io, "{s}", .{separator});

    for (rows.items) |row| {
        const color = colorForCode(row.http_code);
        const line = try formatRow(allocator, widths, row, color);
        defer allocator.free(line);
        try printLine(io, "{s}", .{line});
    }

    try printLine(io, "{s}", .{separator});
}

/// Строка таблицы.
const Row = struct {
    number: usize,
    page_url: []const u8,
    checked_url: []const u8,
    http_code: u16,
};

/// Ширины колонок таблицы.
const Widths = struct {
    number: usize,
    page_url: usize,
    checked_url: usize,
    http_code: usize,
};

/// Вычисляет ширины колонок так, чтобы таблица занимала всю ширину терминала.
fn computeWidths(rows: []const Row, terminal_width: usize) Widths {
    // Минимальные ширины: заголовки и содержимое (визуальная ширина).
    var number_w: usize = visualWidth("№");
    var page_w: usize = visualWidth("URL страницы");
    var checked_w: usize = visualWidth("Проверенный URL");
    var code_w: usize = visualWidth("HTTP Код");

    for (rows) |row| {
        number_w = @max(number_w, std.fmt.count("{d}", .{row.number}));
        page_w = @max(page_w, visualWidth(row.page_url));
        checked_w = @max(checked_w, visualWidth(row.checked_url));
        code_w = @max(code_w, std.fmt.count("{d}", .{row.http_code}));
    }

    // Ширина разделителей между колонками: 3 разделителя по 3 символа (" | ").
    const separators_width: usize = 3 * 3;
    const fixed_width = number_w + code_w + separators_width;

    // Доступная ширина для двух колонок с URL.
    const available = if (terminal_width > fixed_width) terminal_width - fixed_width else 0;

    var page_w_final = page_w;
    var checked_w_final = checked_w;

    if (available > 0) {
        const total_url = page_w + checked_w;
        if (total_url == 0) {
            page_w_final = available / 2;
            checked_w_final = available - page_w_final;
        } else {
            // Пропорционально длине содержимого, но с минимумом.
            const extra = available -| total_url;
            page_w_final = page_w + extra * page_w / total_url;
            checked_w_final = checked_w + extra - (page_w_final - page_w);
        }
    }

    // Гарантируем минимальную ширину колонок с URL.
    page_w_final = @max(page_w_final, min_url_width);
    checked_w_final = @max(checked_w_final, min_url_width);

    return .{
        .number = number_w,
        .page_url = page_w_final,
        .checked_url = checked_w_final,
        .http_code = code_w,
    };
}

/// Формирует строку заголовка таблицы.
fn formatHeader(allocator: std.mem.Allocator, widths: Widths) ![]u8 {
    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(allocator);

    try writeCell(&buf, allocator, widths.number, "№");
    try writeSeparator(&buf, allocator);
    try writeCell(&buf, allocator, widths.page_url, "URL страницы");
    try writeSeparator(&buf, allocator);
    try writeCell(&buf, allocator, widths.checked_url, "Проверенный URL");
    try writeSeparator(&buf, allocator);
    try writeCell(&buf, allocator, widths.http_code, "HTTP Код");

    return buf.toOwnedSlice(allocator);
}

/// Формирует строку таблицы для одной записи.
fn formatRow(
    allocator: std.mem.Allocator,
    widths: Widths,
    row: Row,
    color: []const u8,
) ![]u8 {
    var buf = std.ArrayList(u8).empty;
    errdefer buf.deinit(allocator);

    const number_str = try std.fmt.allocPrint(allocator, "{d}", .{row.number});
    defer allocator.free(number_str);
    const code_str = try std.fmt.allocPrint(allocator, "{d}", .{row.http_code});
    defer allocator.free(code_str);

    try buf.appendSlice(allocator, color);
    try writeCell(&buf, allocator, widths.number, number_str);
    try writeSeparator(&buf, allocator);
    try writeCell(&buf, allocator, widths.page_url, row.page_url);
    try writeSeparator(&buf, allocator);
    try writeCell(&buf, allocator, widths.checked_url, row.checked_url);
    try writeSeparator(&buf, allocator);
    try writeCell(&buf, allocator, widths.http_code, code_str);
    try buf.appendSlice(allocator, Color.reset);

    return buf.toOwnedSlice(allocator);
}

/// Записывает ячейку, дополняя её пробелами справа до указанной ширины.
fn writeCell(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, width: usize, text: []const u8) !void {
    try buf.appendSlice(allocator, text);
    const text_w = visualWidth(text);
    if (text_w < width) {
        try buf.appendNTimes(allocator, ' ', width - text_w);
    }
}

/// Возвращает визуальную ширину строки (количество Unicode-кодовых точек).
///
/// Используется для корректного выравнивания колонок, когда текст содержит
/// многобайтовые символы (например, «№» занимает 2 байта, но 1 колонку).
fn visualWidth(text: []const u8) usize {
    var count: usize = 0;
    const view = std.unicode.Utf8View.init(text) catch return text.len;
    var it = view.iterator();
    while (it.nextCodepointSlice()) |_| {
        count += 1;
    }
    return count;
}

/// Записывает разделитель колонок " | ".
fn writeSeparator(buf: *std.ArrayList(u8), allocator: std.mem.Allocator) !void {
    try buf.appendSlice(allocator, " | ");
}

/// Строит разделитель таблицы из дефисов.
fn buildSeparator(allocator: std.mem.Allocator, widths: Widths) ![]u8 {
    const total = widths.number + widths.page_url + widths.checked_url + widths.http_code + 3 * 3;
    const line = try allocator.alloc(u8, total);
    @memset(line, '-');
    return line;
}

/// Возвращает ANSI-цвет для HTTP-кода.
fn colorForCode(code: u16) []const u8 {
    if (code >= 200 and code < 300) return Color.green;
    if (code >= 300 and code < 400) return Color.yellow;
    if (code >= 400 and code < 600) return Color.red;
    return "";
}

/// Определяет ширину терминала (количество колонок) через ioctl TIOCGWINSZ.
///
/// Возвращает `null`, если терминал недоступен или размер не удалось получить.
fn getTerminalWidth(io: std.Io) ?usize {
    _ = io;
    const builtin = @import("builtin");
    if (builtin.os.tag != .linux) return null;

    const posix = std.posix;
    const linux = std.os.linux;

    const stdout = std.Io.File.stdout();
    var wsz: posix.winsize = undefined;

    const rc = posix.system.ioctl(stdout.handle, linux.T.IOCGWINSZ, @intFromPtr(&wsz));
    switch (posix.errno(rc)) {
        .SUCCESS => {
            if (wsz.col == 0) return null;
            return wsz.col;
        },
        else => return null,
    }
}

/// Выводит строку в stdout.
fn printLine(io: std.Io, comptime fmt: []const u8, args: anytype) !void {
    var buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buffer);
    try writer.interface.print(fmt ++ "\n", args);
    try writer.flush();
}
