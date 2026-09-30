const std = @import("std");
const args = @import("args");
const builtin = @import("builtin");
const check_links_by_page = @import("check_links_by_page.zig");
const request_headers = @import("request_headers.zig");
const i18n = @import("i18n.zig");
const Io = std.Io;
const TerminalSize = @import("TerminalSize.zig");
const build_options = @import("build_options");
const prints = @import("prints.zig");

extern "kernel32" fn SetConsoleOutputCP(wCodePageID: std.os.windows.UINT) callconv(.winapi) std.os.windows.BOOL;

pub fn main(init: std.process.Init) u8 {
    const arena: std.mem.Allocator = init.arena.allocator();
    const io = init.io;

    // Для Windows устанавливаем кодировку UTF-8
    if (builtin.os.tag == .windows) {
        const CP_UTF8 = 65001;
        _ = SetConsoleOutputCP(CP_UTF8);
    }

    const terminal_width = TerminalSize.getTerminalWidth();

    var parser = args.ArgumentParser.init(arena, .{
        .name = "check-links",
        .version = build_options.version,
        .description = i18n.Current.desc,
        .config = .{
            .allow_negated_flags = false,
            .exit_on_error = true,
            .help_indent = 30,
            // Отключаем перенос help-текста библиотекой args: при переносе он
            // начинается в столбце help_indent (35), а обычные строки — ~38-40,
            // что ломает вертикальное выравнивание (особенно для длинных русских
            // строк). Большой лимит гарантирует единую вертикальную линию.
            .help_line_width = terminal_width,
            .custom_help_strings = .{
                .usage_label = i18n.Current.usage,
                .arguments_label = i18n.Current.arguments,
                .commands_label = i18n.Current.commands,
                .command_tag = i18n.Current.command_tag,
                .options_label = i18n.Current.options,
                .options_tag = i18n.Current.options_tag,
                .required_annotation = i18n.Current.required,
                .print_help_label = i18n.Current.help,
                .print_version_label = i18n.Current.version,
                .default_label = i18n.Current.default,
            },
        },
    }) catch {
        prints.printError(io, i18n.Current.err_init_parser ++ "00001");
        return 1;
    };
    defer parser.deinit();

    parser.addFlag("fail", .{
        .short = 'f',
        .help = i18n.Current.help_fail,
    }) catch {
        prints.printError(io, i18n.Current.err_init_parser ++ "00002");
        return 1;
    };

    parser.addFileOption("export", .{
        .short = 'e',
        .help = i18n.Current.help_export,
    }) catch {
        prints.printError(io, i18n.Current.err_init_parser ++ "00003");
        return 1;
    };

    parser.addIntOption("timeout", .{
        .short = 't',
        .help = i18n.Current.help_timeout,
        .min = 0,
        .max = 3600,
        .default = "15",
    }) catch {
        prints.printError(io, i18n.Current.err_init_parser ++ "00004");
        return 1;
    };

    parser.addIntOption("parallels", .{
        .short = 'p',
        .help = i18n.Current.help_parallels,
        .min = 1,
        .max = 100,
        .default = "5",
    }) catch {
        prints.printError(io, i18n.Current.err_init_parser ++ "00005");
        return 1;
    };

    parser.addAppend("header", .{
        .short = 'H',
        .metavar = "NAME: VALUE",
        .help = i18n.Current.help_header,
    }) catch {
        prints.printError(io, i18n.Current.err_init_parser ++ "00006");
        return 1;
    };

    parser.addPositional("url", .{
        .help = i18n.Current.help_url,
        .required = true,
    }) catch {
        prints.printError(io, i18n.Current.err_init_parser ++ "00007");
        return 1;
    };

    parser.addSubcommand(.{
        .name = "completion",
        .help = i18n.Current.completion,
    }) catch {
        prints.printError(io, i18n.Current.err_init_parser ++ "00008");
        return 1;
    };

    var result = parser.parseProcess(init) catch |err| {
        const message = switch (err) {
            error.OutOfMemory => i18n.Current.err_out_of_memory,
            else => i18n.Current.err_unknown,
        };
        prints.printError(io, message);
        return 1;
    };
    defer result.deinit();

    // Если выбран подкоманда completion, то генерируем скрипт для автозавершения и выходим
    if (result.subcommand) |cmd| {
        if (std.mem.eql(u8, cmd, "completion")) {
            if (detectShell(init.environ_map)) |shell| {
                const script = parser.generateCompletion(shell) catch {
                    prints.printError(io, i18n.Current.err_generate_completion);
                    return 1;
                };
                defer arena.free(script);

                var stdout = std.Io.File.stdout().writer(io, &.{});
                stdout.interface.writeAll(script) catch {
                    prints.printError(io, i18n.Current.err_generate_completion);
                    return 1;
                };
                return 0;
            } else {
                prints.printError(io, i18n.Current.err_no_shell);
                return 1;
            }
        }
    }

    const raw_headers = result.getArray("header") orelse &.{};
    var headers = request_headers.parse(arena, raw_headers) catch |err| {
        prints.printHeaderError(io, err);
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
            .terminal_width = terminal_width,
        });
    } else {
        prints.printError(io, i18n.Current.err_no_url);
        return 1;
    }
}

fn detectShell(env: *std.process.Environ.Map) ?args.Shell {
    if (env.get("SHELL")) |shell_path| {
        if (std.mem.endsWith(u8, shell_path, "bash")) return .bash;
        if (std.mem.endsWith(u8, shell_path, "zsh")) return .zsh;
        if (std.mem.endsWith(u8, shell_path, "fish")) return .fish;
        if (std.mem.endsWith(u8, shell_path, "nushell")) return .nushell;
    }
    return null;
}
