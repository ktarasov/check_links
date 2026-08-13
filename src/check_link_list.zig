//! Проверка списка URL-адресов на доступность.
//!
//! Разбивает переданный список URL на чанки, последовательно проверяет
//! HTTP-коды ответов для каждого чанка (конкурентно внутри чанка) и
//! группирует результаты по коду ответа. Аналог PHP-класса `CheckLinkList`.

const std = @import("std");
const check_http = @import("check_http.zig");
const Bar = @import("bar.zig").Bar;

/// Размер чанка для пакетной обработки URL.
pub const chunk_size: usize = 10;

/// Результат проверки списка URL: группировка URL по HTTP-коду.
pub const CheckedList = struct {
    allocator: std.mem.Allocator,
    /// Список групп: каждая группа содержит HTTP-код и список URL с этим кодом.
    groups: std.ArrayList(Group),

    pub const Group = struct {
        http_code: u16,
        urls: std.ArrayList([]const u8),
    };

    pub fn init(allocator: std.mem.Allocator) CheckedList {
        return .{
            .allocator = allocator,
            .groups = std.ArrayList(Group).empty,
        };
    }

    pub fn deinit(self: *CheckedList) void {
        for (self.groups.items) |*group| {
            group.urls.deinit(self.allocator);
        }
        self.groups.deinit(self.allocator);
    }
};

/// Проверяет все URL-адреса, разбивая их на чанки.
///
/// `io` и `allocator` используются для сетевых операций и выделения памяти.
/// Возвращаемый результат принадлежит вызывающему коду (нужно освободить
/// через `deinit`).
pub fn checkLinkList(
    io: std.Io,
    allocator: std.mem.Allocator,
    url_list: []const []const u8,
    writer: ?*std.Io.Writer,
) !CheckedList {
    var result = CheckedList.init(allocator);
    errdefer result.deinit();

    // создадим прогресс-бар
    var progress_bar = try Bar.init(
        allocator,
        io,
        @floatFromInt(url_list.len),
        "Обработка: [:bar] - :current/:total - :percent% - Прошло::elapseds - Оценка::etas - Скорость::rate/s",
        writer,
    );
    defer progress_bar.deinit();

    // Разбиваем список на чанки.
    var start: usize = 0;
    while (start < url_list.len) : (start += chunk_size) {
        const end = @min(start + chunk_size, url_list.len);
        const chunk = url_list[start..end];

        var check_results = try check_http.checkHttpCodes(io, allocator, chunk);
        defer check_results.deinit(allocator);

        for (check_results.items) |check_result| {
            try addToGroup(&result, allocator, check_result.http_code, check_result.url);
        }

        progress_bar.tick(@floatFromInt(chunk.len));
    }

    return result;
}

/// Добавляет URL в группу с указанным HTTP-кодом, создавая группу при необходимости.
fn addToGroup(
    list: *CheckedList,
    allocator: std.mem.Allocator,
    http_code: u16,
    url: []const u8,
) !void {
    for (list.groups.items) |*group| {
        if (group.http_code == http_code) {
            try group.urls.append(allocator, url);
            return;
        }
    }

    var new_group = CheckedList.Group{
        .http_code = http_code,
        .urls = std.ArrayList([]const u8).empty,
    };
    try new_group.urls.append(allocator, url);
    try list.groups.append(allocator, new_group);
}

test "checkLinkList: пустой список возвращает пустой результат" {
    const allocator = std.testing.allocator;
    var result = try checkLinkList(std.testing.io, allocator, &.{}, null);
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 0), result.groups.items.len);
}
