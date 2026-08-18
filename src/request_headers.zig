//! Разбор пользовательских HTTP-заголовков и политика их отправки.

const std = @import("std");

pub const HeaderList = std.ArrayList(std.http.Header);

pub const ParseError = error{
    InvalidHeaderFormat,
    InvalidHeaderName,
    InvalidHeaderValue,
    ManagedFramingHeader,
};

pub const CliError = error{
    MissingHeaderValue,
    InlineHeaderUnsupported,
};

pub const CliArguments = struct {
    args: std.ArrayList([]const u8),
    header_values: std.ArrayList([]const u8),

    pub fn deinit(self: *CliArguments, allocator: std.mem.Allocator) void {
        self.args.deinit(allocator);
        self.header_values.deinit(allocator);
    }
};

/// Извлекает повторяемые `-H VALUE` / `--header VALUE`, оставляя остальные
/// аргументы для основного CLI-парсера.
pub fn extractCliArguments(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
) (CliError || std.mem.Allocator.Error)!CliArguments {
    var result: CliArguments = .{
        .args = .empty,
        .header_values = .empty,
    };
    errdefer result.deinit(allocator);

    var index: usize = 0;
    while (index < argv.len) : (index += 1) {
        const arg = argv[index];

        if (std.mem.eql(u8, arg, "--")) {
            try result.args.appendSlice(allocator, argv[index..]);
            break;
        }

        if (std.mem.startsWith(u8, arg, "--header=") or
            std.mem.startsWith(u8, arg, "-H="))
        {
            return error.InlineHeaderUnsupported;
        }

        if (std.mem.eql(u8, arg, "--header") or std.mem.eql(u8, arg, "-H")) {
            index += 1;
            if (index >= argv.len) return error.MissingHeaderValue;
            try result.header_values.append(allocator, argv[index]);
            continue;
        }

        try result.args.append(allocator, arg);
    }

    return result;
}

/// Разбирает значения заголовков. Срезы имени и значения указывают на строки
/// из `raw_headers` и должны жить не меньше возвращённого списка.
pub fn parse(
    allocator: std.mem.Allocator,
    raw_headers: []const []const u8,
) (ParseError || std.mem.Allocator.Error)!HeaderList {
    var result: HeaderList = .empty;
    errdefer result.deinit(allocator);

    for (raw_headers) |raw| {
        const separator = std.mem.indexOfScalar(u8, raw, ':') orelse
            return error.InvalidHeaderFormat;
        const name = std.mem.trim(u8, raw[0..separator], " \t");
        const value = std.mem.trim(u8, raw[separator + 1 ..], " \t");

        if (!isValidHeaderName(name)) return error.InvalidHeaderName;
        if (std.mem.indexOfAny(u8, value, "\r\n") != null) {
            return error.InvalidHeaderValue;
        }
        if (std.ascii.eqlIgnoreCase(name, "content-length") or
            std.ascii.eqlIgnoreCase(name, "transfer-encoding"))
        {
            return error.ManagedFramingHeader;
        }

        try result.append(allocator, .{ .name = name, .value = value });
    }

    return result;
}

/// Проверяет, задан ли заголовок с указанным именем.
pub fn contains(headers: []const std.http.Header, name: []const u8) bool {
    for (headers) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, name)) return true;
    }
    return false;
}

/// Сравнивает HTTP-origin: схема, host и эффективный порт.
pub fn sameOrigin(left_url: []const u8, right_url: []const u8) bool {
    const left = std.Uri.parse(left_url) catch return false;
    const right = std.Uri.parse(right_url) catch return false;

    const left_port = effectivePort(&left) orelse return false;
    const right_port = effectivePort(&right) orelse return false;
    if (left_port != right_port) return false;
    if (!std.ascii.eqlIgnoreCase(left.scheme, right.scheme)) return false;

    var left_buffer: [std.Io.net.HostName.max_len]u8 = undefined;
    var right_buffer: [std.Io.net.HostName.max_len]u8 = undefined;
    const left_host = left.getHost(&left_buffer) catch return false;
    const right_host = right.getHost(&right_buffer) catch return false;
    return std.ascii.eqlIgnoreCase(left_host.bytes, right_host.bytes);
}

fn effectivePort(uri: *const std.Uri) ?u16 {
    if (uri.port) |port| return port;
    if (std.ascii.eqlIgnoreCase(uri.scheme, "http")) return 80;
    if (std.ascii.eqlIgnoreCase(uri.scheme, "https")) return 443;
    return null;
}

fn isValidHeaderName(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |char| {
        if (std.ascii.isAlphanumeric(char)) continue;
        switch (char) {
            '!', '#', '$', '%', '&', '\'', '*', '+', '-', '.', '^', '_', '`', '|', '~' => {},
            else => return false,
        }
    }
    return true;
}

test "parse: разбирает несколько заголовков и делит по первому двоеточию" {
    const allocator = std.testing.allocator;
    var headers = try parse(allocator, &.{
        " Authorization : Bearer token ",
        "X-Endpoint: https://example.com:8443/path",
        "X-Empty:",
        "X-Repeat: one",
        "X-Repeat: two",
    });
    defer headers.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 5), headers.items.len);
    try std.testing.expectEqualStrings("Authorization", headers.items[0].name);
    try std.testing.expectEqualStrings("Bearer token", headers.items[0].value);
    try std.testing.expectEqualStrings("https://example.com:8443/path", headers.items[1].value);
    try std.testing.expectEqualStrings("", headers.items[2].value);
    try std.testing.expectEqualStrings("one", headers.items[3].value);
    try std.testing.expectEqualStrings("two", headers.items[4].value);
}

test "parse: отклоняет некорректные и управляемые заголовки" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InvalidHeaderFormat, parse(allocator, &.{"Authorization"}));
    try std.testing.expectError(error.InvalidHeaderName, parse(allocator, &.{": value"}));
    try std.testing.expectError(error.InvalidHeaderName, parse(allocator, &.{"Bad Header: value"}));
    try std.testing.expectError(error.InvalidHeaderName, parse(allocator, &.{"X-Bad\r\nName: value"}));
    try std.testing.expectError(error.InvalidHeaderValue, parse(allocator, &.{"X-Test: one\r\ntwo"}));
    try std.testing.expectError(error.ManagedFramingHeader, parse(allocator, &.{"Content-Length: 10"}));
    try std.testing.expectError(error.ManagedFramingHeader, parse(allocator, &.{"transfer-encoding: chunked"}));
}

test "extractCliArguments: извлекает заголовки и сохраняет остальные аргументы" {
    const allocator = std.testing.allocator;
    var extracted = try extractCliArguments(allocator, &.{
        "--fail",
        "-H",
        "Authorization: Bearer token",
        "https://example.com/",
        "--header",
        "X-Test: yes",
    });
    defer extracted.deinit(allocator);

    try std.testing.expectEqualSlices([]const u8, &.{ "--fail", "https://example.com/" }, extracted.args.items);
    try std.testing.expectEqualSlices([]const u8, &.{ "Authorization: Bearer token", "X-Test: yes" }, extracted.header_values.items);
}

test "extractCliArguments: не разбирает аргументы после разделителя" {
    const allocator = std.testing.allocator;
    var extracted = try extractCliArguments(allocator, &.{ "--", "--header", "X-Test: yes" });
    defer extracted.deinit(allocator);

    try std.testing.expectEqualSlices([]const u8, &.{ "--", "--header", "X-Test: yes" }, extracted.args.items);
    try std.testing.expectEqual(@as(usize, 0), extracted.header_values.items.len);
}

test "extractCliArguments: отклоняет inline-форму и отсутствующее значение" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.InlineHeaderUnsupported, extractCliArguments(allocator, &.{"--header=X-Test: yes"}));
    try std.testing.expectError(error.InlineHeaderUnsupported, extractCliArguments(allocator, &.{"-H=X-Test: yes"}));
    try std.testing.expectError(error.MissingHeaderValue, extractCliArguments(allocator, &.{"--header"}));
}

test "sameOrigin: учитывает схему, host и эффективный порт" {
    try std.testing.expect(sameOrigin("https://EXAMPLE.com/a", "https://example.COM:443/b"));
    try std.testing.expect(sameOrigin("http://example.com/a", "http://example.com:80/b"));
    try std.testing.expect(!sameOrigin("http://example.com", "https://example.com"));
    try std.testing.expect(!sameOrigin("https://example.com", "https://example.com:444"));
    try std.testing.expect(!sameOrigin("https://example.com", "https://other.example.com"));
    try std.testing.expect(!sameOrigin("file:///tmp/a", "file:///tmp/b"));
}
