const std = @import("std");
const args = @import("args");
const builtin = @import("builtin");
const check_links_by_page = @import("check_links_by_page.zig");
const request_headers = @import("request_headers.zig");
const i18n = @import("i18n.zig");
const Io = std.Io;

extern "kernel32" fn SetConsoleOutputCP(wCodePageID: std.os.windows.UINT) callconv(.winapi) std.os.windows.BOOL;

pub fn main(init: std.process.Init) !u8 {
    const arena: std.mem.Allocator = init.arena.allocator();
    const io = init.io;

    // Для Windows устанавливаем кодировку UTF-8
    if (builtin.os.tag == .windows) {
        const CP_UTF8 = 65001;
        _ = SetConsoleOutputCP(CP_UTF8);
    }

    var parser = try args.ArgumentParser.init(arena, .{
        .name = "check_links",
        .version = "0.0.1",
        .description = i18n.Current.desc,
        .config = .{
            .allow_negated_flags = false,
            .exit_on_error = true,
            .help_indent = 30,
            // Отключаем перенос help-текста библиотекой args: при переносе он
            // начинается в столбце help_indent (35), а обычные строки — ~38-40,
            // что ломает вертикальное выравнивание (особенно для длинных русских
            // строк). Большой лимит гарантирует единую вертикальную линию.
            .help_line_width = 200,
            .custom_help_strings = .{
                .usage_label = i18n.Current.usage,
                .arguments_label = i18n.Current.arguments,
                .options_label = i18n.Current.options,
                .options_tag = i18n.Current.options_tag,
                .required_annotation = i18n.Current.required,
                .print_help_label = i18n.Current.help,
                .print_version_label = i18n.Current.version,
                .default_label = i18n.Current.default,
            },
        },
    });
    defer parser.deinit();

    try parser.addFlag("fail", .{
        .short = 'f',
        .help = i18n.Current.help_fail,
    });

    try parser.addFileOption("export", .{
        .short = 'e',
        .help = i18n.Current.help_export,
    });

    try parser.addIntOption("timeout", .{
        .short = 't',
        .help = i18n.Current.help_timeout,
        .min = 0,
        .max = 3600,
        .default = "15",
    });

    try parser.addIntOption("parallels", .{
        .short = 'p',
        .help = i18n.Current.help_parallels,
        .min = 1,
        .max = 100,
        .default = "5",
    });

    try parser.addAppend("header", .{
        .short = 'H',
        .metavar = "NAME: VALUE",
        .help = i18n.Current.help_header,
    });

    try parser.addPositional("url", .{
        .help = i18n.Current.help_url,
        .required = true,
    });

    var result = parser.parseProcess(init) catch |err| {
        const message = switch (err) {
            error.OutOfMemory => i18n.Current.err_out_of_memory,
            else => return err,
        };
        printError(io, message);
        return 1;
    };
    defer result.deinit();

    const raw_headers = result.getArray("header") orelse &.{};
    var headers = request_headers.parse(arena, raw_headers) catch |err| {
        printHeaderError(io, err);
        return 1;
    };
    defer headers.deinit(arena);

    if (result.getString("url")) |url| {
        return check_links_by_page.run(io, arena, .{
            .url = url,
            .fail = result.getBool("fail") orelse false,
            .export_filename = result.getString("export"),
            .headers = headers.items,
            .timeout = @abs(result.getInt("timeout") orelse 15),
            .parallels = @intCast(result.getInt("parallels") orelse 5),
        });
    } else {
        printError(io, i18n.Current.err_no_url);
        return 1;
    }
}

fn printHeaderError(io: Io, err: anyerror) void {
    const message = switch (err) {
        error.InvalidHeaderFormat => i18n.Current.err_header_format,
        error.InvalidHeaderName => i18n.Current.err_header_name,
        error.InvalidHeaderValue => i18n.Current.err_header_value,
        error.ManagedFramingHeader => i18n.Current.err_header_managed,
        else => i18n.Current.err_header_other,
    };

    printError(io, message);
}

fn printError(io: Io, message: []const u8) void {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.File.stderr().writer(io, &buffer);
    writer.interface.print("\x1b[0;31m{s}\x1b[0m {s}\n", .{ i18n.Current.err_prefix, message }) catch {};
    writer.flush() catch {};
}
