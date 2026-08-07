//! Нормализация URL-адресов.
//!
//! Содержит функции для построения базового доменного URL из полного URL (`makeDomainUrl`)
//! и нормализации относительных ссылок в абсолютные (`normalizeUrl`).

const std = @import("std");

/// Строит базовый доменный URL вида `scheme://host[:port]` из полного URL.
///
/// Аналог PHP-функции `makeDomainUrl`. Если в URL отсутствует схема или хост,
/// соответствующие части просто пропускаются.
///
/// `allocator` используется для выделения результирующей строки.
/// Возвращаемая строка принадлежит вызывающему коду.
pub fn makeDomainUrl(allocator: std.mem.Allocator, url: []const u8) ![]const u8 {
    const uri = std.Uri.parse(url) catch return allocator.dupe(u8, "");

    var result = std.ArrayList(u8).empty;
    errdefer result.deinit(allocator);

    if (uri.scheme.len != 0) {
        try result.appendSlice(allocator, uri.scheme);
        try result.appendSlice(allocator, "://");
    }

    if (uri.host) |host| {
        const host_raw = host.toRawMaybeAlloc(allocator) catch return result.toOwnedSlice(allocator);
        try result.appendSlice(allocator, host_raw);
    }

    if (uri.port) |port| {
        const port_str = try std.fmt.allocPrint(allocator, ":{d}", .{port});
        defer allocator.free(port_str);
        try result.appendSlice(allocator, port_str);
    }

    return result.toOwnedSlice(allocator);
}

/// Нормализует URL-адрес, извлечённый из атрибута `href`/`src`.
///
/// Аналог PHP-функции `normalizeUrl`. Возвращает `null`, если URL пустой
/// или начинается с `mailto:`/`tel:`. Относительные ссылки (`/`, `#`)
/// преобразуются в абсолютные на основе `domain_url`. Протокол-относительные
/// ссылки (`//`) дополняются схемой `https:`.
///
/// `allocator` используется для выделения результирующей строки.
/// Возвращаемая строка принадлежит вызывающему коду.
pub fn normalizeUrl(
    allocator: std.mem.Allocator,
    domain_url: []const u8,
    url: []const u8,
) !?[]const u8 {
    if (url.len == 0) return null;
    const trimmed = std.mem.trim(u8, url, " \t\r\n");

    if (trimmed.len == 0) return null;
    if (std.mem.startsWith(u8, trimmed, "mailto:")) return null;
    if (std.mem.startsWith(u8, trimmed, "tel:")) return null;

    const result: []const u8 = trimmed;

    if (std.mem.startsWith(u8, result, "//")) {
        // Протокол-относительная ссылка: дополняем схемой https.
        const full = try std.fmt.allocPrint(allocator, "https:{s}", .{result});
        return full;
    } else if (std.mem.startsWith(u8, result, "/") or std.mem.startsWith(u8, result, "#")) {
        // Относительная ссылка: склеиваем с базовым доменом.
        const full = try std.fmt.allocPrint(allocator, "{s}{s}", .{ domain_url, result });
        return full;
    }

    // Абсолютная ссылка: возвращаем как есть (уже обрезанную).
    const duped = try allocator.dupe(u8, result);
    return @as(?[]const u8, duped);
}

test "makeDomainUrl: полный URL со схемой, хостом и портом" {
    const allocator = std.testing.allocator;
    const result = try makeDomainUrl(allocator, "https://example.com:8080/page");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("https://example.com:8080", result);
}

test "makeDomainUrl: URL без порта" {
    const allocator = std.testing.allocator;
    const result = try makeDomainUrl(allocator, "https://example.com/page");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("https://example.com", result);
}

test "makeDomainUrl: URL с query и fragment" {
    const allocator = std.testing.allocator;
    const result = try makeDomainUrl(allocator, "http://example.com/path?q=1#frag");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("http://example.com", result);
}

test "makeDomainUrl: невалидный URL возвращает пустую строку" {
    const allocator = std.testing.allocator;
    const result = try makeDomainUrl(allocator, "not a url");
    defer allocator.free(result);
    try std.testing.expectEqualStrings("", result);
}

test "normalizeUrl: абсолютный URL возвращается без изменений" {
    const allocator = std.testing.allocator;
    const result = (try normalizeUrl(allocator, "https://example.com", "https://other.com/page")) orelse
        return error.TestUnexpectedNull;
    defer allocator.free(result);
    try std.testing.expectEqualStrings("https://other.com/page", result);
}

test "normalizeUrl: относительный путь склеивается с доменом" {
    const allocator = std.testing.allocator;
    const result = (try normalizeUrl(allocator, "https://example.com", "/relative/page")) orelse
        return error.TestUnexpectedNull;
    defer allocator.free(result);
    try std.testing.expectEqualStrings("https://example.com/relative/page", result);
}

test "normalizeUrl: якорь склеивается с доменом" {
    const allocator = std.testing.allocator;
    const result = (try normalizeUrl(allocator, "https://example.com", "#anchor")) orelse
        return error.TestUnexpectedNull;
    defer allocator.free(result);
    try std.testing.expectEqualStrings("https://example.com#anchor", result);
}

test "normalizeUrl: протокол-относительная ссылка дополняется https" {
    const allocator = std.testing.allocator;
    const result = (try normalizeUrl(allocator, "https://example.com", "//cdn.example.com/img.png")) orelse
        return error.TestUnexpectedNull;
    defer allocator.free(result);
    try std.testing.expectEqualStrings("https://cdn.example.com/img.png", result);
}

test "normalizeUrl: пустая строка возвращает null" {
    const allocator = std.testing.allocator;
    const result = try normalizeUrl(allocator, "https://example.com", "");
    try std.testing.expect(result == null);
}

test "normalizeUrl: mailto возвращает null" {
    const allocator = std.testing.allocator;
    const result = try normalizeUrl(allocator, "https://example.com", "mailto:test@example.com");
    try std.testing.expect(result == null);
}

test "normalizeUrl: tel возвращает null" {
    const allocator = std.testing.allocator;
    const result = try normalizeUrl(allocator, "https://example.com", "tel:+123456789");
    try std.testing.expect(result == null);
}

test "normalizeUrl: data URI возвращается как есть" {
    const allocator = std.testing.allocator;
    const result = (try normalizeUrl(allocator, "https://example.com", "data:image/png;base64,iVBORw0KGgo=")) orelse
        return error.TestUnexpectedNull;
    defer allocator.free(result);
    try std.testing.expectEqualStrings("data:image/png;base64,iVBORw0KGgo=", result);
}

test "normalizeUrl: URL с пробелами обрезается" {
    const allocator = std.testing.allocator;
    const result = (try normalizeUrl(allocator, "https://example.com", "  https://example.com/page  ")) orelse
        return error.TestUnexpectedNull;
    defer allocator.free(result);
    try std.testing.expectEqualStrings("https://example.com/page", result);
}
