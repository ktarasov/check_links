const std = @import("std");
const args = @import("args");
const check_links_by_page = @import("check_links_by_page.zig");
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

    try parser.addPositional("url", .{
        .help = "The URL to check.",
        .required = true,
    });

    var result = try parser.parseProcess(init);
    defer result.deinit();

    return check_links_by_page.run(io, arena, .{
        .url = result.getString("url").?,
        .fail = result.getBool("fail") orelse false,
        .export_filename = result.getString("export"),
    });
}
