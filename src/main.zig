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

    // Регистрируется для справки; значения извлекаются предварительно из-за
    // дефекта повторяемых inline-опций в args.zig 0.0.7.
    try parser.addAppend("header", .{
        .short = 'H',
        .metavar = "NAME: VALUE",
        .help = "Set an HTTP header (can be repeated; do not use '=')",
    });

    try parser.addPositional("url", .{
        .help = "The URL to check.",
        .required = true,
    });

    const process_args = try init.minimal.args.toSlice(arena);
    const argv = try arena.alloc([]const u8, if (process_args.len > 0) process_args.len - 1 else 0);
    const first_cli_arg: usize = if (process_args.len > 0) 1 else 0;
    for (process_args[first_cli_arg..], 0..) |arg, index| {
        argv[index] = arg;
    }

    var extracted = request_headers.extractCliArguments(arena, argv) catch |err| {
        printHeaderError(io, err);
        return 1;
    };
    defer extracted.deinit(arena);

    var headers = request_headers.parse(arena, extracted.header_values.items) catch |err| {
        printHeaderError(io, err);
        return 1;
    };
    defer headers.deinit(arena);

    var result = try parser.parseWithIo(extracted.args.items, io);
    defer result.deinit();

    return check_links_by_page.run(io, arena, .{
        .url = result.getString("url").?,
        .fail = result.getBool("fail") orelse false,
        .export_filename = result.getString("export"),
        .headers = headers.items,
    });
}

fn printHeaderError(io: Io, err: anyerror) void {
    const message = switch (err) {
        error.MissingHeaderValue => "для --header/-H не указано значение NAME: VALUE",
        error.InlineHeaderUnsupported => "форма --header=VALUE не поддерживается; используйте --header 'NAME: VALUE'",
        error.InvalidHeaderFormat => "заголовок должен иметь формат NAME: VALUE",
        error.InvalidHeaderName => "имя заголовка некорректно",
        error.InvalidHeaderValue => "значение заголовка содержит запрещённый перевод строки",
        error.ManagedFramingHeader => "Content-Length и Transfer-Encoding задаются HTTP-клиентом",
        else => "не удалось обработать HTTP-заголовки",
    };

    var buffer: [1024]u8 = undefined;
    var writer = std.Io.File.stderr().writer(io, &buffer);
    writer.interface.print("Ошибка: {s}\n", .{message}) catch {};
    writer.flush() catch {};
}
