const std = @import("std");
const builtin = @import("builtin");

pub const TerminalSize = @This();

/// Размеры терминала.
cols: u16,
rows: u16,

/// Размер терминала по умолчанию.
pub fn default() TerminalSize {
    return .{ .cols = 80, .rows = 24 };
}

/// Получить ширину терминала. При неудаче — 80 (аналог `tput cols`).
pub fn getTerminalWidth() usize {
    const terminal_size = getTerminalSize() catch TerminalSize.default();
    return @as(usize, terminal_size.cols);
}

/// Попытка определить размер терминала с учётом платформы.
pub fn getTerminalSize() !TerminalSize {
    switch (builtin.os.tag) {
        .windows => return getWindowsTerminalSize(),
        else => return getPosixTerminalSize(),
    }
}

fn getPosixTerminalSize() !TerminalSize {
    var wsz: std.posix.winsize = std.mem.zeroes(std.posix.winsize);

    const result = std.posix.system.ioctl(std.posix.STDOUT_FILENO, std.posix.T.IOCGWINSZ, @intFromPtr(&wsz));
    if (result != 0) {
        return TerminalSize.default();
    }

    return .{
        .cols = wsz.col,
        .rows = wsz.row,
    };
}

fn getWindowsTerminalSize() !TerminalSize {
    const CONSOLE_SCREEN_BUFFER_INFO = extern struct {
        dwSize: extern struct { X: i16, Y: i16 },
        dwCursorPosition: extern struct { X: i16, Y: i16 },
        wAttributes: u16,
        srWindow: extern struct { Left: i16, Top: i16, Right: i16, Bottom: i16 },
        dwMaximumWindowSize: extern struct { X: i16, Y: i16 },
    };

    const kernel32 = struct {
        extern "kernel32" fn GetConsoleScreenBufferInfo(
            handle: std.os.windows.HANDLE,
            info: *CONSOLE_SCREEN_BUFFER_INFO,
        ) callconv(.winapi) std.os.windows.BOOL;
    };

    const handle = std.os.windows.peb().ProcessParameters.hStdOutput;

    var info: CONSOLE_SCREEN_BUFFER_INFO = undefined;
    if (kernel32.GetConsoleScreenBufferInfo(handle, &info) == .FALSE) {
        return TerminalSize.default();
    }

    const w: u16 = @intCast(info.srWindow.Right - info.srWindow.Left + 1);
    const h: u16 = @intCast(info.srWindow.Bottom - info.srWindow.Top + 1);
    return .{ .cols = w, .rows = h };
}
