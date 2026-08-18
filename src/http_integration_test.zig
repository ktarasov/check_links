//! Интеграционные тесты HTTP-проверки ссылок.
//!
//! Запускают локальный тестовый HTTP-сервер на эфемерном порту и проверяют
//! поведение `check_http.checkHttpCodes` и `check_link_list.checkLinkList`
//! на реальных HTTP-ответах: 200, 404, 500, редиректы, пустые URL и дубликаты.

const std = @import("std");
const check_http = @import("check_http.zig");
const check_link_list = @import("check_link_list.zig");

const net = std.Io.net;
const http = std.http;

/// Локальный тестовый HTTP-сервер.
///
/// Прослушивает TCP-соединения на loopback-адресе с эфемерным портом и
/// отвечает на каждый запрос в соответствии с переданной функцией-обработчиком.
const TestServer = struct {
    io: std.Io,
    server: net.Server,
    /// Буфер для чтения заголовков запроса.
    read_buffer: [8192]u8 = undefined,
    /// Буфер для записи ответа.
    write_buffer: [8192]u8 = undefined,

    /// Обработчик запроса: получает путь запроса и возвращает HTTP-статус.
    handler: *const fn (path: []const u8) http.Status,
    authorization_count: usize = 0,

    fn init(io: std.Io, handler: *const fn (path: []const u8) http.Status) !TestServer {
        var address: net.IpAddress = .{ .ip4 = net.Ip4Address.loopback(0) };
        const server = try net.IpAddress.listen(&address, io, .{});
        return .{
            .io = io,
            .server = server,
            .handler = handler,
        };
    }

    fn deinit(self: *TestServer) void {
        self.server.deinit(self.io);
    }

    /// Возвращает фактический порт, на котором слушает сервер.
    fn port(self: *const TestServer) u16 {
        return self.server.socket.address.getPort();
    }

    /// Формирует базовый URL вида `http://127.0.0.1:<port>`.
    fn baseUrl(self: *const TestServer, buffer: []u8) []const u8 {
        return std.fmt.bufPrint(buffer, "http://127.0.0.1:{d}", .{self.port()}) catch unreachable;
    }

    /// Обрабатывает одно входящее соединение: читает запрос и отправляет ответ.
    fn handleConnection(self: *TestServer, stream: net.Stream) void {
        defer stream.close(self.io);

        var reader = stream.reader(self.io, &self.read_buffer);
        var writer = stream.writer(self.io, &self.write_buffer);

        var http_server = http.Server.init(&reader.interface, &writer.interface);
        var request = http_server.receiveHead() catch return;

        var headers = request.iterateHeaders();
        while (headers.next()) |header| {
            if (std.ascii.eqlIgnoreCase(header.name, "authorization")) {
                self.authorization_count += 1;
            }
        }

        const status = self.handler(request.head.target);
        request.respond("", .{ .status = status }) catch return;
    }

    /// Принимает одно соединение и обрабатывает его.
    fn serveOne(self: *TestServer) void {
        const stream = self.server.accept(self.io) catch return;
        self.handleConnection(stream);
    }
};

/// Обработчик, возвращающий 200 для всех путей.
fn handlerOk(path: []const u8) http.Status {
    _ = path;
    return .ok;
}

/// Обработчик, возвращающий 404 для всех путей.
fn handlerNotFound(path: []const u8) http.Status {
    _ = path;
    return .not_found;
}

/// Обработчик, возвращающий 500 для всех путей.
fn handlerServerError(path: []const u8) http.Status {
    _ = path;
    return .internal_server_error;
}

/// Обработчик, возвращающий 301 (редирект) для всех путей.
fn handlerRedirect(path: []const u8) http.Status {
    _ = path;
    return .moved_permanently;
}

/// Обработчик, возвращающий разные статусы в зависимости от пути.
fn handlerMixed(path: []const u8) http.Status {
    if (std.mem.eql(u8, path, "/ok")) return .ok;
    if (std.mem.eql(u8, path, "/missing")) return .not_found;
    if (std.mem.eql(u8, path, "/error")) return .internal_server_error;
    if (std.mem.eql(u8, path, "/redirect")) return .moved_permanently;
    return .not_found;
}

test "HTTP: сервер отвечает 200" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try TestServer.init(io, handlerOk);
    defer server.deinit();

    var base_buffer: [128]u8 = undefined;
    const base = server.baseUrl(&base_buffer);

    var url_buffer: [256]u8 = undefined;
    const url = std.fmt.bufPrint(&url_buffer, "{s}/page", .{base}) catch unreachable;

    // Запускаем сервер в отдельном потоке, чтобы он принял соединение.
    const thread = try std.Thread.spawn(.{}, serveOneThread, .{&server});
    defer thread.join();

    var result = try check_http.checkHttpCodes(io, allocator, url, &.{url}, &.{});
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), result.items.len);
    try std.testing.expectEqual(@as(u16, 200), result.items[0].http_code);
    try std.testing.expectEqualStrings(url, result.items[0].url);
}

test "HTTP: сервер отвечает 404" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try TestServer.init(io, handlerNotFound);
    defer server.deinit();

    var base_buffer: [128]u8 = undefined;
    const base = server.baseUrl(&base_buffer);

    var url_buffer: [256]u8 = undefined;
    const url = std.fmt.bufPrint(&url_buffer, "{s}/missing", .{base}) catch unreachable;

    const thread = try std.Thread.spawn(.{}, serveOneThread, .{&server});
    defer thread.join();

    var result = try check_http.checkHttpCodes(io, allocator, url, &.{url}, &.{});
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), result.items.len);
    try std.testing.expectEqual(@as(u16, 404), result.items[0].http_code);
}

test "HTTP: сервер отвечает 500" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try TestServer.init(io, handlerServerError);
    defer server.deinit();

    var base_buffer: [128]u8 = undefined;
    const base = server.baseUrl(&base_buffer);

    var url_buffer: [256]u8 = undefined;
    const url = std.fmt.bufPrint(&url_buffer, "{s}/error", .{base}) catch unreachable;

    const thread = try std.Thread.spawn(.{}, serveOneThread, .{&server});
    defer thread.join();

    var result = try check_http.checkHttpCodes(io, allocator, url, &.{url}, &.{});
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), result.items.len);
    try std.testing.expectEqual(@as(u16, 500), result.items[0].http_code);
}

test "HTTP: сервер отвечает редиректом 301" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try TestServer.init(io, handlerRedirect);
    defer server.deinit();

    var base_buffer: [128]u8 = undefined;
    const base = server.baseUrl(&base_buffer);

    var url_buffer: [256]u8 = undefined;
    const url = std.fmt.bufPrint(&url_buffer, "{s}/redirect", .{base}) catch unreachable;

    const thread = try std.Thread.spawn(.{}, serveOneThread, .{&server});
    defer thread.join();

    var result = try check_http.checkHttpCodes(io, allocator, url, &.{url}, &.{});
    defer result.deinit(allocator);

    // Редиректы не проходятся — возвращается код первого ответа.
    try std.testing.expectEqual(@as(usize, 1), result.items.len);
    try std.testing.expectEqual(@as(u16, 301), result.items[0].http_code);
}

test "HTTP: пустые URL пропускаются" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try TestServer.init(io, handlerOk);
    defer server.deinit();

    var base_buffer: [128]u8 = undefined;
    const base = server.baseUrl(&base_buffer);

    var url_buffer: [256]u8 = undefined;
    const url = std.fmt.bufPrint(&url_buffer, "{s}/page", .{base}) catch unreachable;

    const thread = try std.Thread.spawn(.{}, serveOneThread, .{&server});
    defer thread.join();

    // Пустые строки должны быть пропущены, проверяется только непустой URL.
    var result = try check_http.checkHttpCodes(io, allocator, url, &.{ "", url, "" }, &.{});
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), result.items.len);
    try std.testing.expectEqual(@as(u16, 200), result.items[0].http_code);
}

test "HTTP: дубликаты URL проверяются каждый" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try TestServer.init(io, handlerOk);
    defer server.deinit();

    var base_buffer: [128]u8 = undefined;
    const base = server.baseUrl(&base_buffer);

    var url_buffer: [256]u8 = undefined;
    const url = std.fmt.bufPrint(&url_buffer, "{s}/page", .{base}) catch unreachable;

    // Два одинаковых URL — сервер должен обработать два соединения.
    const thread = try std.Thread.spawn(.{}, serveTwoThread, .{&server});
    defer thread.join();

    var result = try check_http.checkHttpCodes(io, allocator, url, &.{ url, url }, &.{});
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.items.len);
    try std.testing.expectEqual(@as(u16, 200), result.items[0].http_code);
    try std.testing.expectEqual(@as(u16, 200), result.items[1].http_code);
}

test "HTTP: пользовательские заголовки отправляются только на исходный origin" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const headers = &.{http.Header{ .name = "Authorization", .value = "Bearer secret" }};

    var origin_server = try TestServer.init(io, handlerOk);
    defer origin_server.deinit();
    var origin_url_buffer: [256]u8 = undefined;
    const origin_url = std.fmt.bufPrint(&origin_url_buffer, "http://127.0.0.1:{d}/internal", .{origin_server.port()}) catch unreachable;

    const origin_thread = try std.Thread.spawn(.{}, serveOneThread, .{&origin_server});
    var origin_result = try check_http.checkHttpCodes(io, allocator, origin_url, &.{origin_url}, headers);
    defer origin_result.deinit(allocator);
    origin_thread.join();
    try std.testing.expectEqual(@as(usize, 1), origin_server.authorization_count);

    var external_server = try TestServer.init(io, handlerOk);
    defer external_server.deinit();
    var external_url_buffer: [256]u8 = undefined;
    const external_url = std.fmt.bufPrint(&external_url_buffer, "http://127.0.0.1:{d}/external", .{external_server.port()}) catch unreachable;

    const external_thread = try std.Thread.spawn(.{}, serveOneThread, .{&external_server});
    var external_result = try check_http.checkHttpCodes(io, allocator, origin_url, &.{external_url}, headers);
    defer external_result.deinit(allocator);
    external_thread.join();
    try std.testing.expectEqual(@as(usize, 0), external_server.authorization_count);
}

test "HTTP: checkLinkList группирует разные статусы" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var server = try TestServer.init(io, handlerMixed);
    defer server.deinit();

    var base_buffer: [128]u8 = undefined;
    const base = server.baseUrl(&base_buffer);

    var ok_buffer: [256]u8 = undefined;
    var missing_buffer: [256]u8 = undefined;
    var error_buffer: [256]u8 = undefined;
    var redirect_buffer: [256]u8 = undefined;

    const ok_url = std.fmt.bufPrint(&ok_buffer, "{s}/ok", .{base}) catch unreachable;
    const missing_url = std.fmt.bufPrint(&missing_buffer, "{s}/missing", .{base}) catch unreachable;
    const error_url = std.fmt.bufPrint(&error_buffer, "{s}/error", .{base}) catch unreachable;
    const redirect_url = std.fmt.bufPrint(&redirect_buffer, "{s}/redirect", .{base}) catch unreachable;

    // Четыре разных URL — сервер должен обработать четыре соединения.
    const thread = try std.Thread.spawn(.{}, serveFourThread, .{&server});
    defer thread.join();

    var result = try check_link_list.checkLinkList(
        io,
        allocator,
        base,
        &.{ ok_url, missing_url, error_url, redirect_url },
        &.{},
        null,
    );
    defer result.deinit();

    // Ожидаем 4 группы: 200, 404, 500, 301.
    try std.testing.expectEqual(@as(usize, 4), result.groups.items.len);

    var found_200 = false;
    var found_404 = false;
    var found_500 = false;
    var found_301 = false;

    for (result.groups.items) |group| {
        switch (group.http_code) {
            200 => {
                found_200 = true;
                try std.testing.expectEqual(@as(usize, 1), group.urls.items.len);
            },
            404 => {
                found_404 = true;
                try std.testing.expectEqual(@as(usize, 1), group.urls.items.len);
            },
            500 => {
                found_500 = true;
                try std.testing.expectEqual(@as(usize, 1), group.urls.items.len);
            },
            301 => {
                found_301 = true;
                try std.testing.expectEqual(@as(usize, 1), group.urls.items.len);
            },
            else => {},
        }
    }

    try std.testing.expect(found_200);
    try std.testing.expect(found_404);
    try std.testing.expect(found_500);
    try std.testing.expect(found_301);
}

/// Обёртка для запуска `serveOne` в отдельном потоке.
fn serveOneThread(server: *TestServer) void {
    server.serveOne();
}

/// Обёртка для запуска двух последовательных соединений в отдельном потоке.
fn serveTwoThread(server: *TestServer) void {
    server.serveOne();
    server.serveOne();
}

/// Обёртка для запуска четырёх последовательных соединений в отдельном потоке.
fn serveFourThread(server: *TestServer) void {
    server.serveOne();
    server.serveOne();
    server.serveOne();
    server.serveOne();
}
