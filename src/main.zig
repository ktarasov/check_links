const std = @import("std");
const args = @import("args");
const check_links_by_page = @import("check_links_by_page.zig");
const request_headers = @import("request_headers.zig");
const Io = std.Io;

pub fn main(init: std.process.Init) !u8 {
    const arena: std.mem.Allocator = init.arena.allocator();
    const io = init.io;

    var parser = try args.ArgumentParser.init(arena, .{
        .name = "check_links",
        .version = "0.0.1",
        .description =
        \\Check Links
        \\
        \\A CLI utility for checking links on a web page. 
        \\It loads the HTML page at the specified URL, collects all links (<a href>) and images (<img src>), 
        \\then checks each URL for availability and displays the result on the screen in table form or in a CSV file.
        ,
        .config = .{
            .allow_negated_flags = false,
            .exit_on_error = true,
        },
    });
    defer parser.deinit();

    try parser.addFlag("fail", .{
        .short = 'f',
        .help = "Output results with errors only.",
    });

    try parser.addFileOption("export", .{
        .short = 'e',
        .help = "Output in CSV format",
    });

    try parser.addAppend("header", .{
        .short = 'H',
        .metavar = "NAME: VALUE",
        .help = "Set an HTTP header (can be repeated)",
    });

    try parser.addPositional("url", .{
        .help = "The URL to check.",
        .required = true,
    });

    const process_args = try init.minimal.args.toSlice(arena);
    const first_cli_arg: usize = @intFromBool(process_args.len > 0);
    var normalized_args = try request_headers.normalizeCliArguments(arena, process_args[first_cli_arg..]);
    defer normalized_args.deinit(arena);

    var result = parser.parseWithIo(normalized_args.items, io) catch |err| {
        const message = switch (err) {
            error.MissingValue => "для опции не указано значение",
            error.InvalidFormat => "некорректный формат аргумента",
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

    return check_links_by_page.run(io, arena, .{
        .url = result.getString("url").?,
        .fail = result.getBool("fail") orelse false,
        .export_filename = result.getString("export"),
        .headers = headers.items,
    });
}

fn printHeaderError(io: Io, err: anyerror) void {
    const message = switch (err) {
        error.InvalidHeaderFormat => "заголовок должен иметь формат NAME: VALUE",
        error.InvalidHeaderName => "имя заголовка некорректно",
        error.InvalidHeaderValue => "значение заголовка содержит запрещённый перевод строки",
        error.ManagedFramingHeader => "Content-Length и Transfer-Encoding задаются HTTP-клиентом",
        else => "не удалось обработать HTTP-заголовки",
    };

    printError(io, message);
}

fn printError(io: Io, message: []const u8) void {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.File.stderr().writer(io, &buffer);
    writer.interface.print("Ошибка: {s}\n", .{message}) catch {};
    writer.flush() catch {};
}
