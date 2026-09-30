//! Функции печати ошибок и предупреждений сгруппированы в отдельный файл.
//!
//! Сделано это, чтобы не было необходимости дублировать функции в других файлах.

const std = @import("std");
const Io = std.Io;
const i18n = @import("i18n.zig");

/// Выводит сообщение об ошибке в stderr.
/// @param io Io.
/// @param message Сообщение об ошибке.
pub fn printError(io: Io, message: []const u8) void {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.File.stderr().writer(io, &buffer);
    writer.interface.print("\x1b[31m{s}\x1b[0m {s}\n", .{ i18n.Current.err_prefix, message }) catch {};
    writer.flush() catch {};
}

/// Выводит сообщение об ошибке в stderr.
pub fn printErrorFmt(io: std.Io, comptime fmt: []const u8, args: anytype) void {
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stderr().writer(io, &buffer);
    writer.interface.print("\x1b[0;31m{s}\x1b[0m " ++ fmt ++ "\n", .{i18n.Current.err_prefix} ++ args) catch {};
    writer.flush() catch {};
}

/// Выводит предупреждение в stderr.
/// @param io Io.
/// @param fmt Формат сообщения.
/// @param args Аргументы сообщения.
pub fn printWarningFmt(io: std.Io, comptime fmt: []const u8, args: anytype) void {
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stderr().writer(io, &buffer);
    writer.interface.print("\x1b[0;33m{s}\x1b[0m " ++ fmt ++ "\n", .{i18n.Current.warn_prefix} ++ args) catch {};
    writer.flush() catch {};
}

/// Выводит сообщение об ошибке в stderr.
/// @param io Io.
/// @param err Ошибка.
pub fn printHeaderError(io: Io, err: anyerror) void {
    const message = switch (err) {
        error.InvalidHeaderFormat => i18n.Current.err_header_format,
        error.InvalidHeaderName => i18n.Current.err_header_name,
        error.InvalidHeaderValue => i18n.Current.err_header_value,
        error.ManagedFramingHeader => i18n.Current.err_header_managed,
        else => i18n.Current.err_header_other,
    };

    printError(io, message);
}
