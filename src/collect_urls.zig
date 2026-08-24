//! Сбор URL-адресов со страницы.
//!
//! Загружает HTML-содержимое страницы по URL (HTTP/HTTPS или file://),
//! парсит его и извлекает значения атрибутов `href` из тегов `<a>` и `src`
//! из тегов `<img>`. Относительные URL нормализуются в абсолютные на основе
//! базового домена. Дубликаты удаляются.

const std = @import("std");
const url_normalize = @import("url_normalize.zig");
const html_parser = @import("html_parser.zig");
const request_headers = @import("request_headers.zig");

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
    headers: []const std.http.Header,
) !std.ArrayList([]const u8) {
    const domain_url = try url_normalize.makeDomainUrl(allocator, url);
    defer allocator.free(domain_url);

    const html = try loadDocument(io, allocator, url, headers);
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
    headers: []const std.http.Header,
) GetDocumentError![]u8 {
    if (std.mem.startsWith(u8, url, "file://")) {
        return loadFromFile(io, allocator, url);
    }

    if (std.mem.startsWith(u8, url, "http://") or std.mem.startsWith(u8, url, "https://")) {
        return loadFromHttp(io, allocator, url, headers);
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
    headers: []const std.http.Header,
) GetDocumentError![]u8 {
    if (headers.len == 0) return loadFromHttpDefault(io, allocator, url);

    var client: std.http.Client = .{
        .allocator = allocator,
        .io = io,
    };
    defer client.deinit();

    var current_url = allocator.dupe(u8, url) catch return error.OutOfMemory;
    defer allocator.free(current_url);

    var redirect_count: usize = 0;
    while (true) {
        const uri = std.Uri.parse(current_url) catch return error.InvalidUrl;
        const current_headers = if (request_headers.sameOrigin(url, current_url)) headers else &.{};

        var request = client.request(.GET, uri, .{
            .redirect_behavior = .unhandled,
            .headers = standardHeaders(current_headers),
            .extra_headers = current_headers,
        }) catch return error.LoadFailed;
        defer request.deinit();

        request.sendBodiless() catch return error.LoadFailed;
        var response = request.receiveHead(&.{}) catch return error.LoadFailed;

        if (response.head.status.class() == .redirect) {
            if (redirect_count >= 3) return error.LoadFailed;
            const location = response.head.location orelse return error.LoadFailed;
            const next_url = resolveRedirect(allocator, uri, current_url.len, location) catch return error.LoadFailed;
            allocator.free(current_url);
            current_url = next_url;
            redirect_count += 1;
            continue;
        }

        if (response.head.status.class() != .success) return error.LoadFailed;
        return readResponseBody(allocator, &response) catch return error.LoadFailed;
    }
}

/// Старый быстрый путь без пользовательских заголовков.
fn loadFromHttpDefault(
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
            .user_agent = .{ .override = default_user_agent },
        },
    }) catch return error.LoadFailed;

    if (result.status.class() != .success) {
        return error.LoadFailed;
    }

    body = allocating.toArrayList();
    return body.toOwnedSlice(allocator) catch return error.LoadFailed;
}

const default_user_agent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/103.0.5060.114 Safari/537.36";

fn standardHeaders(headers: []const std.http.Header) std.http.Client.Request.Headers {
    return .{
        .host = if (request_headers.contains(headers, "host")) .omit else .default,
        .authorization = if (request_headers.contains(headers, "authorization")) .omit else .default,
        .user_agent = if (request_headers.contains(headers, "user-agent")) .omit else .{ .override = default_user_agent },
        .connection = if (request_headers.contains(headers, "connection")) .omit else .default,
        .accept_encoding = if (request_headers.contains(headers, "accept-encoding")) .omit else .default,
        .content_type = if (request_headers.contains(headers, "content-type")) .omit else .default,
    };
}

fn resolveRedirect(
    allocator: std.mem.Allocator,
    base: std.Uri,
    base_url_len: usize,
    location: []const u8,
) ![]u8 {
    const buffer = try allocator.alloc(u8, base_url_len + location.len + 2);
    defer allocator.free(buffer);
    @memcpy(buffer[0..location.len], location);
    var remaining = buffer;
    const resolved = try base.resolveInPlace(location.len, &remaining);
    return std.fmt.allocPrint(allocator, "{f}", .{resolved});
}

fn readResponseBody(
    allocator: std.mem.Allocator,
    response: *std.http.Client.Response,
) ![]u8 {
    var body = std.ArrayList(u8).empty;
    defer body.deinit(allocator);
    var allocating = std.Io.Writer.Allocating.fromArrayList(allocator, &body);
    defer allocating.deinit();

    const decompress_buffer: []u8 = switch (response.head.content_encoding) {
        .identity => &.{},
        .zstd => try allocator.alloc(u8, std.compress.zstd.default_window_len),
        .deflate, .gzip => try allocator.alloc(u8, std.compress.flate.max_window_len),
        .compress => return error.UnsupportedCompressionMethod,
    };
    defer if (decompress_buffer.len > 0) allocator.free(decompress_buffer);

    var transfer_buffer: [64]u8 = undefined;
    var decompress: std.http.Decompress = undefined;
    const reader = response.readerDecompressing(&transfer_buffer, &decompress, decompress_buffer);
    _ = try reader.streamRemaining(&allocating.writer);

    body = allocating.toArrayList();
    return body.toOwnedSlice(allocator);
}

const DocumentServer = struct {
    const Mode = enum { page, same_origin_redirect, external_redirect, redirect_loop };

    io: std.Io,
    server: std.Io.net.Server,
    read_buffer: [8192]u8 = undefined,
    write_buffer: [8192]u8 = undefined,
    mode: Mode,
    external_location: []const u8 = "",
    authorization_count: usize = 0,
    x_test_count: usize = 0,
    user_agent_count: usize = 0,
    custom_user_agent_seen: bool = false,

    fn init(io: std.Io, mode: Mode) !DocumentServer {
        var address: std.Io.net.IpAddress = .{ .ip4 = std.Io.net.Ip4Address.loopback(0) };
        return .{
            .io = io,
            .server = try std.Io.net.IpAddress.listen(&address, io, .{}),
            .mode = mode,
        };
    }

    fn deinit(self: *DocumentServer) void {
        self.server.deinit(self.io);
    }

    fn url(self: *const DocumentServer, path: []const u8, buffer: []u8) []const u8 {
        return std.fmt.bufPrint(buffer, "http://127.0.0.1:{d}{s}", .{ self.server.socket.address.getPort(), path }) catch unreachable;
    }

    fn serve(self: *DocumentServer, count: usize) void {
        for (0..count) |_| {
            const stream = self.server.accept(self.io) catch return;
            defer stream.close(self.io);

            var reader = stream.reader(self.io, &self.read_buffer);
            var writer = stream.writer(self.io, &self.write_buffer);
            var http_server = std.http.Server.init(&reader.interface, &writer.interface);
            var request = http_server.receiveHead() catch return;

            var headers = request.iterateHeaders();
            while (headers.next()) |header| {
                if (std.ascii.eqlIgnoreCase(header.name, "authorization")) self.authorization_count += 1;
                if (std.ascii.eqlIgnoreCase(header.name, "x-test")) self.x_test_count += 1;
                if (std.ascii.eqlIgnoreCase(header.name, "user-agent")) {
                    self.user_agent_count += 1;
                    if (std.mem.eql(u8, header.value, "custom-agent")) self.custom_user_agent_seen = true;
                }
            }

            switch (self.mode) {
                .page => request.respond("<a href=\"/ok\">ok</a>", .{ .keep_alive = false }) catch return,
                .same_origin_redirect => {
                    if (std.mem.eql(u8, request.head.target, "/start")) {
                        request.respond("", .{
                            .status = .found,
                            .keep_alive = false,
                            .extra_headers = &.{.{ .name = "Location", .value = "/page" }},
                        }) catch return;
                    } else {
                        request.respond("<a href=\"/ok\">ok</a>", .{ .keep_alive = false }) catch return;
                    }
                },
                .external_redirect => request.respond("", .{
                    .status = .found,
                    .keep_alive = false,
                    .extra_headers = &.{.{ .name = "Location", .value = self.external_location }},
                }) catch return,
                .redirect_loop => request.respond("", .{
                    .status = .found,
                    .keep_alive = false,
                    .extra_headers = &.{.{ .name = "Location", .value = "/loop" }},
                }) catch return,
            }
        }
    }
};

fn serveDocument(server: *DocumentServer, count: usize) void {
    server.serve(count);
}

test "HTTP GET: отправляет заголовки и заменяет встроенный User-Agent" {
    const allocator = std.testing.allocator;
    var server = try DocumentServer.init(std.testing.io, .page);
    defer server.deinit();
    var url_buffer: [256]u8 = undefined;
    const url = server.url("/page", &url_buffer);
    const thread = try std.Thread.spawn(.{}, serveDocument, .{ &server, 1 });

    const body = try loadFromHttp(std.testing.io, allocator, url, &.{
        .{ .name = "Authorization", .value = "Bearer secret" },
        .{ .name = "X-Test", .value = "one" },
        .{ .name = "X-Test", .value = "two" },
        .{ .name = "User-Agent", .value = "custom-agent" },
    });
    defer allocator.free(body);
    thread.join();

    try std.testing.expectEqual(@as(usize, 1), server.authorization_count);
    try std.testing.expectEqual(@as(usize, 2), server.x_test_count);
    try std.testing.expectEqual(@as(usize, 1), server.user_agent_count);
    try std.testing.expect(server.custom_user_agent_seen);
}

test "HTTP GET: сохраняет заголовки на same-origin редиректе" {
    const allocator = std.testing.allocator;
    var server = try DocumentServer.init(std.testing.io, .same_origin_redirect);
    defer server.deinit();
    var url_buffer: [256]u8 = undefined;
    const url = server.url("/start", &url_buffer);
    const thread = try std.Thread.spawn(.{}, serveDocument, .{ &server, 2 });

    const body = try loadFromHttp(std.testing.io, allocator, url, &.{.{ .name = "Authorization", .value = "Bearer secret" }});
    defer allocator.free(body);
    thread.join();

    try std.testing.expectEqual(@as(usize, 2), server.authorization_count);
}

test "HTTP GET: снимает заголовки на cross-origin редиректе" {
    const allocator = std.testing.allocator;
    var target = try DocumentServer.init(std.testing.io, .page);
    defer target.deinit();
    var target_url_buffer: [256]u8 = undefined;
    const target_url = target.url("/page", &target_url_buffer);

    var source = try DocumentServer.init(std.testing.io, .external_redirect);
    defer source.deinit();
    source.external_location = target_url;
    var source_url_buffer: [256]u8 = undefined;
    const source_url = source.url("/start", &source_url_buffer);

    const source_thread = try std.Thread.spawn(.{}, serveDocument, .{ &source, 1 });
    const target_thread = try std.Thread.spawn(.{}, serveDocument, .{ &target, 1 });
    const body = try loadFromHttp(std.testing.io, allocator, source_url, &.{.{ .name = "Authorization", .value = "Bearer secret" }});
    defer allocator.free(body);
    source_thread.join();
    target_thread.join();

    try std.testing.expectEqual(@as(usize, 1), source.authorization_count);
    try std.testing.expectEqual(@as(usize, 0), target.authorization_count);
}

test "HTTP GET: ограничивает цепочку тремя редиректами" {
    const allocator = std.testing.allocator;
    var server = try DocumentServer.init(std.testing.io, .redirect_loop);
    defer server.deinit();
    var url_buffer: [256]u8 = undefined;
    const url = server.url("/loop", &url_buffer);
    const thread = try std.Thread.spawn(.{}, serveDocument, .{ &server, 4 });

    try std.testing.expectError(error.LoadFailed, loadFromHttp(
        std.testing.io,
        allocator,
        url,
        &.{.{ .name = "Authorization", .value = "Bearer secret" }},
    ));
    thread.join();

    try std.testing.expectEqual(@as(usize, 4), server.authorization_count);
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
        &.{},
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
        &.{},
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
        &.{},
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
        &.{},
    ));
}

test "collectUrls: невалидный URL возвращает ошибку" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidUrl, collectUrls(
        std.testing.io,
        allocator,
        "not a url",
        &.{},
    ));
}
