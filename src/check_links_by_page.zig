//! Оркестрация проверки ссылок на одной странице.
//!
//! Аналог PHP-класса `CheckLinksByPage`. Собирает все URL с указанной
//! страницы, проверяет их HTTP-статусы и выводит результат в табличной
//! форме (в консоль) или экспортирует в CSV.

const std = @import("std");
const collect_urls = @import("collect_urls.zig");
const check_link_list = @import("check_link_list.zig");
const table_view = @import("table_view.zig");
const export_csv = @import("export_csv.zig");

/// Параметры запуска проверки ссылок на странице.
pub const Options = struct {
    /// URL страницы, ссылки на которой нужно проверить.
    url: []const u8,
    /// Если true — показывать только упавшие (ошибочные) ссылки.
    fail: bool = false,
    /// Имя CSV-файла для экспорта. Если null — вывод в консоль.
    export_filename: ?[]const u8 = null,
};

/// Запускает процесс проверки ссылок на странице.
///
/// `io` и `allocator` используются для сетевых операций и выделения памяти.
/// Возвращает код завершения (0 — успех, 1 — ошибка).
pub fn run(
    io: std.Io,
    allocator: std.mem.Allocator,
    options: Options,
) u8 {
    // 0. Создание заголовка прогресс-бара.
    const parent_title = std.fmt.allocPrint(allocator, "Проверка ссылок на странице {s}", .{options.url}) catch options.url;
    defer allocator.free(parent_title);

    // 0.1. Создание прогресс-бара.
    const parent_progress_node = std.Progress.start(io, .{
        .root_name = parent_title,
    });
    defer parent_progress_node.end();

    // 1. Сбор всех URL с указанной страницы.
    var url_list = collect_urls.collectUrls(io, allocator, options.url, parent_progress_node) catch |err| {
        switch (err) {
            error.LoadFailed => printError(io, "Ошибка при загрузке страницы: {s}", .{options.url}),
            error.InvalidUrl => printError(io, "Некорректный URL: {s}", .{options.url}),
            else => printError(io, "Ошибка при загрузке страницы: {s}", .{options.url}),
        }
        return 1;
    };
    defer {
        for (url_list.items) |item| allocator.free(item);
        url_list.deinit(allocator);
    }

    // 2. Если URL не найдены — вывод предупреждения и завершение.
    if (url_list.items.len == 0) {
        printWarning(io, "URL на указанной странице {s} не найдены", .{options.url});
        return 0;
    }

    // 3. Проверка каждого URL.
    var checked_list = check_link_list.checkLinkList(io, allocator, url_list.items, parent_progress_node) catch {
        printError(io, "Ошибка при проверке ссылок", .{});
        return 1;
    };
    defer checked_list.deinit();

    // 4. Вывод результатов.
    if (options.export_filename) |file_name| {
        export_csv.exportCsv(io, allocator, options.url, &checked_list, options.fail, file_name) catch |err| {
            printError(io, "Ошибка при экспорте в CSV: {s}", .{@errorName(err)});
            return 1;
        };
    } else {
        table_view.renderTableView(io, allocator, options.url, &checked_list, options.fail) catch {
            printError(io, "Ошибка при выводе таблицы", .{});
            return 1;
        };
    }

    return 0;
}

/// Выводит сообщение об ошибке в stderr.
fn printError(io: std.Io, comptime fmt: []const u8, args: anytype) void {
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stderr().writer(io, &buffer);
    writer.interface.print("Ошибка: " ++ fmt ++ "\n", args) catch {};
    writer.flush() catch {};
}

/// Выводит предупреждение в stderr.
fn printWarning(io: std.Io, comptime fmt: []const u8, args: anytype) void {
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stderr().writer(io, &buffer);
    writer.interface.print("Предупреждение: " ++ fmt ++ "\n", args) catch {};
    writer.flush() catch {};
}
