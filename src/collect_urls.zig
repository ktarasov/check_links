//! Сбор URL-адресов со страницы.
//!
//! Загружает HTML-содержимое страницы по URL (HTTP/HTTPS или file://),
//! парсит его и извлекает значения атрибутов `href` из тегов `<a>` и `src`
//! из тегов `<img>`. Относительные URL нормализуются в абсолютные на основе
//! базового домена. Дубликаты удаляются.

const std = @import("std");
const url_normalize = @import("url_normalize.zig");
const html_parser = @import("html_parser.zig");

/// Ошибка загрузки документа по URL.
pub const GetDocumentError = error{
    /// Не удалось загрузить страницу (сетевые ошибки, ошибки HTTP, ошибки файловой системы).
    LoadFailed,
    /// Не удалось разобрать URL.
    InvalidUrl,
} || std.mem.Allocator.Error;

/// Собирает список URL-адресов со страницы по заданному URL.
///
/// `io` и `allocator` используются для сетевых операций и выделения памяти.
/// Возвращаемый список принадлежит вызывающему коду (нужно освободить через
/// `deinit`).
pub fn collectUrls(
    io: std.Io,
    allocator: std.mem.Allocator,
    url: []const u8,
) !std.ArrayList([]const u8) {
    const domain_url = try url_normalize.makeDomainUrl(allocator, url);
    defer allocator.free(domain_url);

    const html = try loadDocument(io, allocator, url);
    defer allocator.free(html);

    var parsed = try html_parser.parse(allocator, html);
    defer parsed.deinit();

    var result = std.ArrayList([]const u8).empty;
    errdefer result.deinit(allocator);

    // Собираем URL из тегов <a> и <img>.
    var parsed_it = parsed.iterator();
    while (parsed_it.next()) |raw| {
        if (try url_normalize.normalizeUrl(allocator, domain_url, raw)) |normalized| {
            if (!try appendUnique(allocator, &result, normalized)) {
                allocator.free(normalized);
            }
        }
    }

    return result;
}

/// Добавляет строку в список, если её ещё нет (дедупликация).
fn appendUnique(
    allocator: std.mem.Allocator,
    list: *std.ArrayList([]const u8),
    value: []const u8,
) !bool {
    for (list.items) |existing| {
        if (std.mem.eql(u8, existing, value)) {
            return false;
        }
    }
    try list.append(allocator, value);
    return true;
}

/// Загружает HTML-содержимое документа по URL.
///
/// Поддерживает схемы `http://`, `https://` и `file://`. Для HTTP-запросов
/// используется `std.http.Client`. Для `file://` — чтение файла.
fn loadDocument(
    io: std.Io,
    allocator: std.mem.Allocator,
    url: []const u8,
) GetDocumentError![]u8 {
    if (std.mem.startsWith(u8, url, "file://")) {
        return loadFromFile(io, allocator, url);
    }

    if (std.mem.startsWith(u8, url, "http://") or std.mem.startsWith(u8, url, "https://")) {
        return loadFromHttp(io, allocator, url);
    }

    return error.InvalidUrl;
}

/// Загружает HTML из локального файла по URL вида `file:///path/to/file`.
fn loadFromFile(
    io: std.Io,
    allocator: std.mem.Allocator,
    url: []const u8,
) GetDocumentError![]u8 {
    // Отбрасываем префикс "file://".
    const file_path = url["file://".len..];

    return std.Io.Dir.cwd().readFileAlloc(io, file_path, allocator, .unlimited) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.LoadFailed,
    };
}

/// Загружает HTML по HTTP/HTTPS с использованием `std.http.Client`.
fn loadFromHttp(
    io: std.Io,
    allocator: std.mem.Allocator,
    url: []const u8,
) GetDocumentError![]u8 {
    var client: std.http.Client = .{
        .allocator = allocator,
        .io = io,
    };
    defer client.deinit();

    var body = std.ArrayList(u8).empty;
    defer body.deinit(allocator);

    var allocating = std.Io.Writer.Allocating.fromArrayList(allocator, &body);
    defer allocating.deinit();

    const result = client.fetch(.{
        .location = .{ .url = url },
        .method = .GET,
        .response_writer = &allocating.writer,
        .headers = .{
            .user_agent = .{ .override = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/103.0.5060.114 Safari/537.36" },
        },
    }) catch return error.LoadFailed;

    if (result.status.class() != .success) {
        return error.LoadFailed;
    }

    body = allocating.toArrayList();
    return body.toOwnedSlice(allocator) catch return error.LoadFailed;
}

test "collectUrls: извлекает URL из HTML-строки" {
    const allocator = std.testing.allocator;
    const html =
        \\<html><body>
        \\  <a href="https://example.com/page1">Link 1</a>
        \\  <a href="/relative/page2">Link 2</a>
        \\  <img src="https://example.com/image1.jpg">
        \\</body></html>
    ;

    // Тестируем через временный файл.
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "page.html", .data = html });
    const dir_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", allocator);
    defer allocator.free(dir_path);
    const file_url = try std.fmt.allocPrint(allocator, "file://{s}/page.html", .{dir_path});
    defer allocator.free(file_url);

    var result = try collectUrls(
        std.testing.io,
        allocator,
        file_url,
    );
    defer {
        for (result.items) |item| allocator.free(item);
        result.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 3), result.items.len);
    try std.testing.expectEqualStrings("https://example.com/page1", result.items[0]);
    try std.testing.expectEqualStrings("file:///relative/page2", result.items[1]);
    try std.testing.expectEqualStrings("https://example.com/image1.jpg", result.items[2]);
}

test "collectUrls: дедупликация URL" {
    const allocator = std.testing.allocator;
    const html =
        \\<html><body>
        \\  <a href="https://example.com/page1">Link 1</a>
        \\  <a href="https://example.com/page1">Link 2</a>
        \\  <img src="https://example.com/page1">
        \\</body></html>
    ;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "page.html", .data = html });
    const dir_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", allocator);
    defer allocator.free(dir_path);
    const file_url = try std.fmt.allocPrint(allocator, "file://{s}/page.html", .{dir_path});
    defer allocator.free(file_url);

    var result = try collectUrls(
        std.testing.io,
        allocator,
        file_url,
    );
    defer {
        for (result.items) |item| allocator.free(item);
        result.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 1), result.items.len);
    try std.testing.expectEqualStrings("https://example.com/page1", result.items[0]);
}

test "collectUrls: пустая страница возвращает пустой список" {
    const allocator = std.testing.allocator;
    const html = "<html><body><p>No links.</p></body></html>";

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "page.html", .data = html });
    const dir_path = try tmp.dir.realPathFileAlloc(std.testing.io, ".", allocator);
    defer allocator.free(dir_path);
    const file_url = try std.fmt.allocPrint(allocator, "file://{s}/page.html", .{dir_path});
    defer allocator.free(file_url);

    var result = try collectUrls(
        std.testing.io,
        allocator,
        file_url,
    );
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), result.items.len);
}

test "collectUrls: несуществующий файл возвращает ошибку" {
    const allocator = std.testing.allocator;
    const file_url = "file:///nonexistent/path.html";

    try std.testing.expectError(error.LoadFailed, collectUrls(
        std.testing.io,
        allocator,
        file_url,
    ));
}

test "collectUrls: невалидный URL возвращает ошибку" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidUrl, collectUrls(
        std.testing.io,
        allocator,
        "not a url",
    ));
}
