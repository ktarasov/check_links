//! Лёгкий HTML-парсер для извлечения URL из атрибутов.
//!
//! Извлекает значения атрибута `href` из тегов `<a>` и атрибута `src`
//! из тегов `<img>`. Не строит полное DOM-дерево, а сканирует HTML-строку
//! последовательно, что достаточно для задачи сбора ссылок.

const std = @import("std");
const zq = @import("zigquery");

/// Результат парсинга: списки URL-строк, извлечённых из HTML.
pub const ParseResult = struct {
    allocator: std.mem.Allocator,
    /// Список URL из атрибутов `href` и `src`.
    urls: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) ParseResult {
        return .{
            .allocator = allocator,
            .urls = std.ArrayList([]const u8).empty,
        };
    }

    pub fn deinit(self: *ParseResult) void {
        for (self.urls.items) |item| self.allocator.free(item);
        self.urls.deinit(self.allocator);
    }

    pub fn append(self: *ParseResult, url: []const u8) !void {
        try self.urls.append(self.allocator, try self.allocator.dupe(u8, url));
    }

    pub fn len(self: *ParseResult) usize {
        return self.urls.items.len;
    }

    pub fn get(self: *ParseResult, index: usize) ?[]const u8 {
        if (index >= self.urls.items.len) return null;
        return self.urls.items[index];
    }

    /// Iterator over elements as single-element Selections.
    pub fn iterator(self: *ParseResult) Iterator {
        return .{ .result = self, .pos = 0 };
    }

    pub const Iterator = struct {
        result: *ParseResult,
        pos: usize,

        pub fn next(self: *Iterator) ?[]const u8 {
            if (self.pos >= self.result.urls.items.len) return null;
            const pos = self.pos;
            self.pos += 1;
            return self.result.urls.items[pos];
        }
    };
};

/// Парсит HTML-строку и извлекает URL из тегов `<a href>` и `<img src>`.
///
/// `allocator` используется для выделения результирующих списков.
/// Значения атрибутов указывают на исходную строку `html` (не копируются).
pub fn parse(allocator: std.mem.Allocator, html: []const u8) !ParseResult {
    var result = ParseResult.init(allocator);
    errdefer result.deinit();

    var doc = try zq.Document.initFromSlice(allocator, html);
    defer doc.deinit();

    // Извлекаем все теги <A>
    const sel_a = try doc.find("a");
    var it_a = sel_a.iterator();
    while (it_a.next()) |el_a| {
        const attr_href = el_a.attr("href");
        if (attr_href) |href| {
            try result.append(href);
        }
    }

    // Извлекаем все теги <IMG>
    const sel_img = try doc.find("img");
    var it_img = sel_img.iterator();
    while (it_img.next()) |el_img| {
        const attr_src = el_img.attr("src");
        if (attr_src) |src| {
            try result.append(src);
        }
    }

    return result;
}

test "parse: извлекает href из тегов a" {
    const allocator = std.testing.allocator;
    const html =
        \\<html><body>
        \\  <a href="https://example.com/page1">Link 1</a>
        \\  <a href='/relative/page2'>Link 2</a>
        \\  <a href=unquoted>Link 3</a>
        \\</body></html>
    ;
    var result = try parse(allocator, html);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 3), result.len());
    try std.testing.expectEqualStrings("https://example.com/page1", result.get(0).?);
    try std.testing.expectEqualStrings("/relative/page2", result.get(1).?);
    try std.testing.expectEqualStrings("unquoted", result.get(2).?);
}

test "parse: извлекает src из тегов img" {
    const allocator = std.testing.allocator;
    const html =
        \\<html><body>
        \\  <img src="https://example.com/image1.jpg" alt="Image 1">
        \\  <img src='/relative/image2.png'>
        \\</body></html>
    ;
    var result = try parse(allocator, html);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.len());
    try std.testing.expectEqualStrings("https://example.com/image1.jpg", result.get(0).?);
    try std.testing.expectEqualStrings("/relative/image2.png", result.get(1).?);
}

test "parse: смешанные теги a и img" {
    const allocator = std.testing.allocator;
    const html =
        \\<a href="https://example.com/page1">L</a>
        \\<img src="https://example.com/image1.jpg">
        \\<a href="https://example.com/page2">L</a>
        \\<img src="/relative/image2.png">
    ;
    var result = try parse(allocator, html);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 4), result.len());
}

test "parse: пустой HTML возвращает пустые списки" {
    const allocator = std.testing.allocator;
    var result = try parse(allocator, "");
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 0), result.len());
}

test "parse: HTML без тегов a и img" {
    const allocator = std.testing.allocator;
    const html = "<html><body><p>No links here.</p></body></html>";
    var result = try parse(allocator, html);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 0), result.len());
}

test "parse: регистронезависимость имён тегов и атрибутов" {
    const allocator = std.testing.allocator;
    const html =
        \\<A HREF="https://example.com/page1">L</A>
        \\<IMG SRC="https://example.com/image1.jpg">
    ;
    var result = try parse(allocator, html);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.len());
    try std.testing.expectEqualStrings("https://example.com/page1", result.get(0).?);
    try std.testing.expectEqualStrings("https://example.com/image1.jpg", result.get(1).?);
}

test "parse: тег a без атрибута href" {
    const allocator = std.testing.allocator;
    const html = "<a>No href</a><a href=''>Empty</a>";
    var result = try parse(allocator, html);
    defer result.deinit();

    // Первый <a> без href пропускается, второй с пустым href сохраняется.
    try std.testing.expectEqual(@as(usize, 1), result.len());
    try std.testing.expectEqualStrings("", result.get(0).?);
}

test "parse: атрибут с пробелами вокруг знака равенства" {
    const allocator = std.testing.allocator;
    const html = "<a href = \"https://example.com/page1\">L</a>";
    var result = try parse(allocator, html);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.len());
    try std.testing.expectEqualStrings("https://example.com/page1", result.get(0).?);
}

test "parse: URL с query-параметрами и спецсимволами" {
    const allocator = std.testing.allocator;
    const html =
        \\<a href="https://example.com/path?param=value&other=1">Q</a>
        \\<a href="https://example.com/%D1%80%D1%83%D1%81%D1%81%D0%BA%D0%B8%D0%B9-%D0%BF%D1%83%D1%82%D1%8C">Cyr</a>
        \\<img src="https://example.com/image.jpg?w=200&h=100">
    ;
    var result = try parse(allocator, html);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 3), result.len());
    try std.testing.expectEqualStrings("https://example.com/path?param=value&other=1", result.get(0).?);
    try std.testing.expectEqualStrings("https://example.com/%D1%80%D1%83%D1%81%D1%81%D0%BA%D0%B8%D0%B9-%D0%BF%D1%83%D1%82%D1%8C", result.get(1).?);
    try std.testing.expectEqualStrings("https://example.com/image.jpg?w=200&h=100", result.get(2).?);
}

test "parse: многострочный HTML с комментариями" {
    const allocator = std.testing.allocator;
    const html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head><title>Test</title></head>
        \\<body>
        \\  <!-- <a href="https://example.com/comment">Comment</a> -->
        \\  <a href="https://example.com/real">Real</a>
        \\</body>
        \\</html>
    ;
    var result = try parse(allocator, html);
    defer result.deinit();

    // Комментарий не должен быть распознан как тег <a>.
    try std.testing.expectEqual(@as(usize, 1), result.len());
    try std.testing.expectEqualStrings("https://example.com/real", result.get(0).?);
}
