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
    /// Таймаут запроса в секундах
    timeout: u64 = 15,
    /// Имя CSV-файла для экспорта. Если null — вывод в консоль.
    export_filename: ?[]const u8 = null,
    /// Пользовательские HTTP-заголовки для исходного origin.
    headers: []const std.http.Header = &.{},
    /// Количество параллельных запросов.
    parallels: u8 = 5,
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
    // 0. Установка количества параллельных запросов.
    check_link_list.chunk_size = options.parallels;

    // 1. Сбор всех URL с указанной страницы.
    var url_list = collect_urls.collectUrls(io, allocator, options.url, options.headers) catch |err| {
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

    // 3. Подготовка Writer для прогресс-бара
    var stderr_writer = std.Io.File.stderr().writer(io, &.{});

    // 4. Проверка каждого URL.
    var checked_list = check_link_list.checkLinkList(
        io,
        allocator,
        options.url,
        url_list.items,
        options.headers,
        options.timeout,
        &stderr_writer.interface,
    ) catch {
        printError(io, "Ошибка при проверке ссылок", .{});
        return 1;
    };
    defer checked_list.deinit();

    // 5. Вывод результатов.
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
