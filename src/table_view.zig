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
const TableFormatter = @import("TableFormatter.zig");
const i18n = @import("i18n.zig");
const Colors = TableFormatter.Colors;

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
        try printLineFmt(io, i18n.Current.msg_empty_list, .{});
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

    var tf = TableFormatter.init(io, allocator);
    const line_format = [_][]const u8{ "4%", "45%", "45%", "*" };
    tf.setBorder(" | ");

    const line_separator = try buildSeparator(allocator, tf.max + 1);
    defer allocator.free(line_separator);

    // Выводим заголовок таблицы.
    printLn(io, line_separator, true);
    const table_title = try tf.format(
        &line_format,
        &[_][]const u8{
            i18n.Current.col_num,
            i18n.Current.col_page_url,
            i18n.Current.col_checked_url,
            i18n.Current.col_http_code,
        },
        &.{},
    );
    printLn(io, table_title, false);
    allocator.free(table_title);
    printLn(io, line_separator, true);

    var line_number: usize = 1;
    for (sorted.items) |group| {
        // Если указана опция --fail, то выводим только ошибки.
        if (fail and group.http_code == 200) continue;

        for (group.urls.items) |checked_url| {
            const line_color = colorForCode(group.http_code);
            const line_colors = [_]?Colors{ null, null, line_color, line_color };
            const line = try tf.format(
                &line_format,
                &[_][]const u8{
                    try std.fmt.allocPrint(allocator, " {d}.", .{line_number}),
                    url,
                    checked_url,
                    try std.fmt.allocPrint(allocator, "{d}", .{group.http_code}),
                },
                &line_colors,
            );
            printLn(io, line, false);
            allocator.free(line);
            line_number += 1;
        }
    }

    printLn(io, line_separator, true);
}

/// Строит разделитель таблицы из дефисов.
fn buildSeparator(allocator: std.mem.Allocator, total: usize) ![]u8 {
    const line = try allocator.alloc(u8, total);
    @memset(line, '-');
    return line;
}

/// Возвращает ANSI-цвет для HTTP-кода.
fn colorForCode(code: u16) ?Colors {
    if (code >= 200 and code < 300) return .green;
    if (code >= 300 and code < 400) return .yellow;
    if (code >= 400 and code < 600) return .red;
    return null;
}

/// Выводит строку в stdout.
fn printLineFmt(io: std.Io, comptime fmt: []const u8, args: anytype) !void {
    var buffer: [8192]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buffer);
    try writer.interface.print(fmt ++ "\n", args);
    try writer.flush();
}

fn printLn(io: std.Io, line: []const u8, is_newline: bool) void {
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buffer);
    writer.interface.writeAll(line) catch {};
    if (is_newline) writer.interface.writeAll("\n") catch {};
    writer.flush() catch {};
}
