//! Нормализация URL-адресов.
//!
//! Содержит функции для построения базового доменного URL из полного URL (`makeDomainUrl`)
//! и нормализации ссылок в абсолютные на основе базового URL страницы (`normalizeUrl`).

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

/// Нормализует ссылку, извлечённую из атрибута `href`/`src`, в абсолютный URL.
///
/// Аналог PHP-функции `normalizeUrl`. Возвращает `null`, если URL пустой,
/// начинается с `mailto:`/`tel:` или не может быть разобран/разрешён.
///
/// Относительная ссылка (`books/...`, `/path`, `../up`, `./same`, `#anchor`,
/// `?query`) разрешается в абсолютную относительно полного базового URL страницы
/// `base_url` по алгоритму RFC 3986 (Section 5). Протокол-относительные ссылки
/// (`//host/...`) наследуют схему из `base_url`. Абсолютные ссылки (включая
/// `data:`) возвращаются без изменений.
///
/// `allocator` используется для выделения результирующей строки.
/// Возвращаемая строка принадлежит вызывающему коду.
pub fn normalizeUrl(
    allocator: std.mem.Allocator,
    base_url: []const u8,
    url: []const u8,
) !?[]const u8 {
    if (url.len == 0) return null;
    const trimmed = std.mem.trim(u8, url, " \t\r\n");

    if (trimmed.len == 0) return null;
    if (std.mem.startsWith(u8, trimmed, "mailto:")) return null;
    if (std.mem.startsWith(u8, trimmed, "tel:")) return null;
    if (std.mem.startsWith(u8, trimmed, "data:")) return null;

    return resolveAgainstBase(allocator, base_url, trimmed) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        // Нерезолвимую/невалидную ссылку пропускаем (не включаем в список).
        else => return null,
    };
}

/// Разрешает ссылку `ref` относительно базового URL `base_url` по RFC 3986.
///
/// Внутри используется `std.Uri.resolveInPlace`: ссылка копируется во
/// вспомогательный буфер, разрешается относительно базы, а результат
/// рендерится в новую выделенную строку. Возвращаемая строка принадлежит
/// вызывающему коду.
fn resolveAgainstBase(
    allocator: std.mem.Allocator,
    base_url: []const u8,
    ref: []const u8,
) ![]const u8 {
    const base = try std.Uri.parse(base_url);

    // Во вспомогательный буфер копируется `ref`, а при необходимости
    // (merge_paths) туда же дописывается объединённый путь. Размера
    // ref + base_url достаточно, т.к. объединённый путь не длиннее их суммы.
    const buf = try allocator.alloc(u8, ref.len + base_url.len + 16);
    defer allocator.free(buf);

    var aux: []u8 = buf;
    @memcpy(aux[0..ref.len], ref);

    // После вызова компоненты `resolved` указывают в `buf`, поэтому
    // буфер должен оставаться живым до завершения рендера ниже.
    const resolved = try base.resolveInPlace(ref.len, &aux);

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var allocating = std.Io.Writer.Allocating.fromArrayList(allocator, &out);
    defer allocating.deinit();

    try renderUri(&allocating.writer, resolved);

    out = allocating.toArrayList();
    // std.debug.print("\x1b[0;36mBaseUrl:\x1b[0m {s}, \x1b[0;36mRef:\x1b[0m {s}, \x1b[0;36mResolved:\x1b[0m {s}\n", .{ base_url, ref, out.items });

    return out.toOwnedSlice(allocator);
}

/// Рендерит URI в writer. Аналог `std.Uri.writeToStream`, но для схемы
/// `file:` всегда выводит пустой authority (`file://`), сохраняя каноническую
/// форму `file:///путь`.
fn renderUri(w: *std.Io.Writer, uri: std.Uri) !void {
    if (uri.scheme.len != 0) {
        try w.print("{s}:", .{uri.scheme});
        if (uri.host != null or std.mem.eql(u8, uri.scheme, "file")) {
            try w.writeAll("//");
        }
    }
    if (uri.host) |host| {
        if (uri.user) |user| {
            try user.formatUser(w);
            if (uri.password) |password| {
                try w.writeByte(':');
                try password.formatPassword(w);
            }
            try w.writeByte('@');
        }
        try host.formatHost(w);
        if (uri.port) |port| try w.print(":{d}", .{port});
    }
    const uri_path: std.Uri.Component = if (uri.path.isEmpty()) .{ .percent_encoded = "/" } else uri.path;
    try uri_path.formatPath(w);
    if (uri.query) |query| {
        try w.writeByte('?');
        try query.formatQuery(w);
    }
    if (uri.fragment) |fragment| {
        try w.writeByte('#');
        try fragment.formatFragment(w);
    }
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
    const result = (try normalizeUrl(allocator, "https://example.com/page", "https://other.com/page")) orelse
        return error.TestUnexpectedNull;
    defer allocator.free(result);
    try std.testing.expectEqualStrings("https://other.com/page", result);
}

test "normalizeUrl: относительный путь с ведущим слешем склеивается с корнем домена" {
    const allocator = std.testing.allocator;
    const result = (try normalizeUrl(allocator, "https://example.com/docs/page", "/relative/page")) orelse
        return error.TestUnexpectedNull;
    defer allocator.free(result);
    try std.testing.expectEqualStrings("https://example.com/relative/page", result);
}

test "normalizeUrl: относительный путь без ведущего слеша резолвится от корня" {
    const allocator = std.testing.allocator;
    const result = (try normalizeUrl(allocator, "https://example.com/", "books/learning-zig/chapter11/")) orelse
        return error.TestUnexpectedNull;
    defer allocator.free(result);
    try std.testing.expectEqualStrings("https://example.com/books/learning-zig/chapter11/", result);
}

test "normalizeUrl: относительный путь резолвится от подпути текущей страницы" {
    const allocator = std.testing.allocator;
    const result = (try normalizeUrl(allocator, "https://example.com/docs/index.html", "books/learning-zig/")) orelse
        return error.TestUnexpectedNull;
    defer allocator.free(result);
    try std.testing.expectEqualStrings("https://example.com/docs/books/learning-zig/", result);
}

test "normalizeUrl: восходящий переход ../ обрабатывается" {
    const allocator = std.testing.allocator;
    const result = (try normalizeUrl(allocator, "https://example.com/a/b/c/page", "../other")) orelse
        return error.TestUnexpectedNull;
    defer allocator.free(result);
    try std.testing.expectEqualStrings("https://example.com/a/b/other", result);
}

test "normalizeUrl: якорь резолвится относительно текущей страницы" {
    const allocator = std.testing.allocator;
    const result = (try normalizeUrl(allocator, "https://example.com/docs/page", "#anchor")) orelse
        return error.TestUnexpectedNull;
    defer allocator.free(result);
    try std.testing.expectEqualStrings("https://example.com/docs/page#anchor", result);
}

test "normalizeUrl: протокол-относительная ссылка наследует схему базы" {
    const allocator = std.testing.allocator;
    const result = (try normalizeUrl(allocator, "https://example.com/page", "//cdn.example.com/img.png")) orelse
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
    const result = (try normalizeUrl(allocator, "https://example.com", "data:image/png;base64,iVBORw0KGgo="));
    try std.testing.expect(result == null);
}

test "normalizeUrl: URL с пробелами обрезается" {
    const allocator = std.testing.allocator;
    const result = (try normalizeUrl(allocator, "https://example.com", "  https://example.com/page  ")) orelse
        return error.TestUnexpectedNull;
    defer allocator.free(result);
    try std.testing.expectEqualStrings("https://example.com/page", result);
}
