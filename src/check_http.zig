//! Конкурентная проверка HTTP-кодов для списка URL-адресов.
//!
//! Выполняет HEAD-запросы к каждому URL параллельно (по одному потоку на URL)
//! и возвращает результат проверки для каждого URL. Редиректы не проходятся —
//! возвращается HTTP-код первого ответа, как в PHP-реализации
//! `CheckHttpCodeByUrlList`.

const std = @import("std");
const http_head_client = @import("http_head_client.zig");
const request_headers = @import("request_headers.zig");

/// Таймаут ожидания ответа от сервера в секундах.
pub const timeout_seconds: u64 = 30;

/// Результат проверки одного URL.
pub const ResolveUrlResult = struct {
    /// HTTP-код ответа (например, 200, 301, 404). 0 — если запрос не удался.
    http_code: u16 = 0,
    /// Исходный URL.
    url: []const u8,
};

/// Проверяет HTTP-коды для списка URL-адресов конкурентно.
///
/// `io` и `allocator` используются для сетевых операций и выделения памяти.
/// Возвращаемый список принадлежит вызывающему коду (нужно освободить через
/// `deinit`).
pub fn checkHttpCodes(
    io: std.Io,
    allocator: std.mem.Allocator,
    source_url: []const u8,
    url_list: []const []const u8,
    headers: []const std.http.Header,
) !std.ArrayList(ResolveUrlResult) {
    var result = std.ArrayList(ResolveUrlResult).empty;
    errdefer result.deinit(allocator);

    if (url_list.len == 0) return result;

    // Мьютекс для защиты общего списка результатов.
    var mutex = std.Io.Mutex.init;
    var shared = SharedState{
        .allocator = allocator,
        .io = io,
        .mutex = &mutex,
        .results = &result,
        .source_url = source_url,
        .headers = headers,
    };

    var threads = std.ArrayList(std.Thread).empty;
    defer threads.deinit(allocator);

    // Запускаем по одному потоку на каждый URL.
    for (url_list) |url| {
        if (url.len == 0) continue;

        const thread = std.Thread.spawn(.{}, worker, .{ &shared, url }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => continue,
        };
        try threads.append(allocator, thread);
    }

    // Ожидаем завершения всех потоков.
    for (threads.items) |thread| {
        thread.join();
    }

    return result;
}

/// Общее состояние для конкурентных задач.
const SharedState = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    mutex: *std.Io.Mutex,
    results: *std.ArrayList(ResolveUrlResult),
    source_url: []const u8,
    headers: []const std.http.Header,
};

/// Функция-воркер: выполняет HEAD-запрос к одному URL и сохраняет результат.
fn worker(state: *SharedState, url: []const u8) void {
    const headers = if (request_headers.sameOrigin(state.source_url, url)) state.headers else &.{};
    const r = checkOneUrl(state.io, state.allocator, url, headers);

    state.mutex.lockUncancelable(state.io);
    defer state.mutex.unlock(state.io);
    state.results.append(state.allocator, r) catch {};
}

/// Выполняет HEAD-запрос к одному URL и возвращает результат.
///
/// Используется собственный HTTP HEAD-клиент `HttpHeadClient` (замена
/// `std.http.Client`), который поддерживает таймаут запроса.
fn checkOneUrl(
    io: std.Io,
    allocator: std.mem.Allocator,
    url: []const u8,
    headers: []const std.http.Header,
) ResolveUrlResult {
    var client: http_head_client.HttpHeadClient = .{
        .io = io,
        .allocator = allocator,
        .timeout_ms = timeout_seconds * 1000,
        .headers = headers,
    };
    defer client.deinit();

    const code = client.check(url) catch {
        return .{
            .http_code = 0,
            .url = url,
        };
    };

    return .{
        .http_code = code,
        .url = url,
    };
}

test "checkHttpCodes: пустой список возвращает пустой результат" {
    const allocator = std.testing.allocator;
    var result = try checkHttpCodes(std.testing.io, allocator, "https://example.com", &.{}, &.{});
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), result.items.len);
}

test "checkHttpCodes: пропускает пустые строки" {
    const allocator = std.testing.allocator;
    var result = try checkHttpCodes(std.testing.io, allocator, "https://example.com", &.{ "", "", "" }, &.{});
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), result.items.len);
}
