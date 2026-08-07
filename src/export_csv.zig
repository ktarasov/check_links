//! Экспорт результатов проверки ссылок в CSV-файл.
//!
//! Аналог PHP-класса `ExportCSV`. Записывает результаты в CSV-файл
//! с разделителем `;` и заголовком «№;URL страницы;Проверенный URL;HTTP Код».
//! При опции `fail` экспортируются только ошибочные ссылки.

const std = @import("std");
const check_link_list = @import("check_link_list.zig");

/// Экспортирует результаты проверки ссылок в CSV-файл.
///
/// `io` используется для файловых операций. `url` — URL проверяемой страницы.
/// `checked_list` — сгруппированные по HTTP-коду результаты.
/// `fail` — если true, экспортируются только ошибочные ссылки.
/// `file_name` — путь к CSV-файлу.
pub fn exportCsv(
    io: std.Io,
    allocator: std.mem.Allocator,
    url: []const u8,
    checked_list: *const check_link_list.CheckedList,
    fail: bool,
    file_name: []const u8,
) !void {
    if (checked_list.groups.items.len == 0) {
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

    // Создаём файл (режим 'x' — ошибка, если файл существует).
    const cwd = std.Io.Dir.cwd();
    var file = cwd.createFile(io, file_name, .{ .exclusive = true }) catch |err| switch (err) {
        error.PathAlreadyExists => blk: {
            // Если файл существует, переименовываем его в .bak и создаём заново.
            const bak = try std.fmt.allocPrint(allocator, "{s}.bak", .{file_name});
            defer allocator.free(bak);
            cwd.rename(file_name, cwd, bak, io) catch {};
            break :blk try cwd.createFile(io, file_name, .{ .exclusive = true });
        },
        else => return err,
    };
    defer file.close(io);

    var buffer: [4096]u8 = undefined;
    var writer = file.writer(io, &buffer);

    try writer.interface.print("№;URL страницы;Проверенный URL;HTTP Код\n", .{});
    try writer.flush();

    var line_number: usize = 1;
    for (sorted.items) |group| {
        // Если указана опция --fail, то экспортируем только ошибки.
        if (fail and group.http_code == 200) continue;

        for (group.urls.items) |checked_url| {
            try writer.interface.print("{d};{s};{s};{d}\n", .{
                line_number,
                url,
                checked_url,
                group.http_code,
            });
            line_number += 1;
        }
    }
    try writer.flush();
}
