//! Терминальный прогресс-бар (порт класса `Bar` из PHP-пакета macroman/terminal-progress-bar).
//!
//! Выводит в указанный поток прогресс-бар с токенами `:bar`, `:current`, `:total`,
//! `:elapsed`, `:percent`, `:eta`, `:rate`.

const std = @import("std");
const builtin = @import("builtin");

// ─── ANSI-коды ───────────────────────────────────────────────────────────────
pub const ANSI = struct {
    pub const move_start: []const u8 = "\x1b[1G"; // \033[1G — переход в начало строки
    pub const hide_cursor: []const u8 = "\x1b[?25l"; // \033[?25l — скрыть курсор
    pub const show_cursor: []const u8 = "\x1b[?25h"; // \033[?25h — показать курсор
    pub const erase_line: []const u8 = "\x1b[2K"; // \033[2K — стереть строку
};

/// Токены формата, которые заменяются на значения.
const tokens = [_][]const u8{ ":current", ":total", ":elapsed", ":percent", ":eta", ":rate" };

/// Максимальная ширина значения в `roundAndPad` (nnn.nn).
const pad_width: usize = 6;

/// Псевдоним типа писателя (интерфейс ввода-вывода Zig).
pub const Writer = std.Io.Writer;

/// Прогресс-бар.
pub const Bar = struct {
    allocator: std.mem.Allocator,
    /// Интерфейс I/O для чтения времени.
    io: std.Io,

    /// Доступная ширина экрана.
    width: usize,
    /// Поток вывода. `null` — вывод не производится (удобно для тестов).
    stream: ?*Writer,
    /// Строка формата (владение — у бара).
    format: []u8,
    /// Время инициализации бара (секунды).
    start_time: f64,
    /// Время последней отрисовки (секунды).
    time_since_last_call: f64,

    /// Не отрисовывать чаще, чем это значение (обходится в `interrupt`).
    throttle: f64 = 0.1,

    /// Символ завершённой части бара.
    symbol_complete: u8 = '=',
    /// Символ незавершённой части бара.
    symbol_incomplete: u8 = ' ',

    /// Количество десятичных знаков для секунд.
    second_precision: usize = 0,
    /// Количество десятичных знаков для процентов.
    percent_precision: usize = 1,

    /// Текущий тик.
    current: f64 = 0,
    /// Максимальное число тиков.
    total: f64 = 1,

    /// Секунд прошло.
    elapsed: f64 = 0,
    /// Текущий процент завершения.
    percent: f64 = 0,
    /// Оценочное время до завершения.
    eta: ?f64 = null,
    /// Текущая скорость.
    rate: f64 = 0,

    /// Выделить структуру на куче и инициализировать прогресс-бар.
    ///
    /// `allocator` — аллокатор для структуры и буферов; `io` — интерфейс
    /// ввода-вывода (для замера времени); `total` — максимальное число тиков;
    /// `format` — строка формата (копируется); `writer` — поток вывода, либо
    /// `null` (вывод не производится — удобно для тестов).
    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        total: f64,
        format: []const u8,
        writer: ?*Writer,
    ) !*Bar {
        const self = try allocator.create(Bar);
        errdefer allocator.destroy(self);

        const fmt = try allocator.dupe(u8, format);
        errdefer allocator.free(fmt);

        // Получаем ширину терминала; при неудаче — 80 колонок (аналог `tput cols`).
        const width = getTerminalWidth();

        const now = nowSeconds(io);

        self.* = .{
            .io = io,
            .allocator = allocator,
            .width = width,
            .stream = writer,
            .format = fmt,
            .start_time = now,
            .time_since_last_call = now,
            .total = total,
        };

        // Инициализация дисплея.
        self.write(ANSI.hide_cursor);
        self.write(ANSI.move_start);

        self.drawBar();

        return self;
    }

    /// Освободить ресурсы (аналог `__destruct`).
    pub fn deinit(self: *Bar) void {
        self.end();
        self.allocator.free(self.format);
        self.allocator.destroy(self);
    }

    /// Увеличить текущий тик на `amount`.
    pub fn tick(self: *Bar, amount: f64) void {
        self.update(self.current + amount);
    }

    /// Установить текущий тик и пересчитать данные.
    pub fn update(self: *Bar, amount: f64) void {
        self.current = amount;
        const now = nowSeconds(self.io);
        const draw_elapsed = now - self.time_since_last_call;

        if (draw_elapsed > self.throttle) {
            self.elapsed = now - self.start_time;
            self.percent = self.current / self.total * 100;
            self.rate = self.current / self.elapsed;

            if (self.current > 0) {
                self.eta = @abs(self.elapsed / self.current * self.total - self.elapsed);
            } else {
                self.eta = null;
            }

            self.drawBar();
        }
    }

    /// Вывести сообщение на новой строке перед прогресс-баром.
    pub fn interrupt(self: *Bar, message: []const u8) void {
        self.write(ANSI.move_start);
        self.write(ANSI.erase_line);
        self.write(message);
        self.write("\n");
        self.drawBar();
    }

    /// Выполнить фактическую отрисовку бара.
    fn drawBar(self: *Bar) void {
        self.time_since_last_call = nowSeconds(self.io);
        self.write(ANSI.move_start);

        // Строим значения замены для токенов.
        const elapsed_s = self.roundAndPad(self.elapsed, self.second_precision);
        const percent_s = self.roundAndPad(self.percent, self.percent_precision);
        const eta_v: f64 = self.eta orelse 0;
        const eta_s = self.roundAndPad(eta_v, self.second_precision);
        const rate_s = self.roundAndPad(self.rate, 1);
        const current_s = self.floatToSlice(self.current);
        const total_s = self.floatToSlice(self.total);

        // Все выделенные строки освобождаем в конце.
        defer {
            self.allocator.free(elapsed_s);
            self.allocator.free(percent_s);
            self.allocator.free(eta_s);
            self.allocator.free(rate_s);
            self.allocator.free(current_s);
            self.allocator.free(total_s);
        }

        // Заменяем токены на значения.
        var output = self.allocator.dupe(u8, self.format) catch return;
        defer self.allocator.free(output);

        const replacements = [_][]const u8{
            current_s,
            total_s,
            elapsed_s,
            percent_s,
            eta_s,
            rate_s,
        };

        var i: usize = 0;
        while (i < tokens.len) : (i += 1) {
            const new_output = self.replaceAll(output, tokens[i], replacements[i]);
            self.allocator.free(output);
            output = new_output;
        }

        // Если в выводе есть :bar, вычисляем графическую полосу.
        if (std.mem.indexOf(u8, output, ":bar") != null) {
            const bar_s = self.buildBarString(strlen(output));
            defer self.allocator.free(bar_s);
            const new_output = self.replaceAll(output, ":bar", bar_s);
            self.allocator.free(output);
            output = new_output;
        }

        self.write(output);
    }

    /// Длина строки в символах (кодовых точках UTF-8).
    fn strlen(string: []const u8) usize {
        return std.unicode.utf8CountCodepoints(string) catch string.len;
    }

    /// Вычислить строку-полосу для токена `:bar`.
    fn buildBarString(self: *Bar, output_len: usize) []u8 {
        const available_space: i64 = @as(i64, @intCast(self.width)) -
            @as(i64, @intCast(output_len)) + 4;
        const done_f = @as(f64, @floatFromInt(available_space)) * (self.percent / 100);
        var done: i64 = @intFromFloat(done_f);
        if (done < 0) done = 0;
        const left_raw = available_space - done;
        const left: i64 = if (left_raw < 0) 0 else left_raw;

        const total_len: usize = @intCast(done + left);
        const buf = self.allocator.alloc(u8, total_len) catch return &.{};

        @memset(buf[0..@intCast(done)], self.symbol_complete);
        @memset(buf[@intCast(done)..], self.symbol_incomplete);
        return buf;
    }

    /// Округлить и дополнить число пробелами до фиксированной длины (nnn.nn).
    fn roundAndPad(self: *Bar, input: f64, precision: usize) []u8 {
        const prec: usize = if (precision > 3) 3 else precision;
        var num_buf: [128]u8 = undefined;

        // Спецификатор формата должен быть известен на этапе компиляции.
        // Используем switch по точности (0..3).
        const num_s: []const u8 = switch (prec) {
            0 => std.fmt.bufPrint(&num_buf, "{d:.0}", .{input}) catch return self.empty(),
            1 => std.fmt.bufPrint(&num_buf, "{d:.1}", .{input}) catch return self.empty(),
            2 => std.fmt.bufPrint(&num_buf, "{d:.2}", .{input}) catch return self.empty(),
            else => std.fmt.bufPrint(&num_buf, "{d:.3}", .{input}) catch return self.empty(),
        };

        // Дополняем пробелами слева до длины 6.
        if (num_s.len >= pad_width) {
            return self.allocator.dupe(u8, num_s) catch return self.empty();
        }
        const padded = self.allocator.alloc(u8, pad_width) catch return self.empty();
        @memset(padded, ' ');
        @memcpy(padded[pad_width - num_s.len ..], num_s);
        return padded;
    }

    /// Пустая строка (для веток ошибок).
    fn empty(self: *Bar) []u8 {
        return self.allocator.dupe(u8, "") catch return &.{};
    }

    /// Преобразовать число в строку (для current/total).
    fn floatToSlice(self: *Bar, value: f64) []u8 {
        var buf: [64]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d}", .{value}) catch return self.empty();
        return self.allocator.dupe(u8, s) catch return self.empty();
    }

    /// Заменить все вхождения `needle` на `replacement` в `haystack`.
    fn replaceAll(self: *Bar, haystack: []const u8, needle: []const u8, replacement: []const u8) []u8 {
        var out = std.ArrayList(u8).empty;
        var start: usize = 0;
        while (std.mem.indexOf(u8, haystack[start..], needle)) |idx| {
            out.appendSlice(self.allocator, haystack[start .. start + idx]) catch return self.empty();
            out.appendSlice(self.allocator, replacement) catch return self.empty();
            start += idx + needle.len;
        }
        out.appendSlice(self.allocator, haystack[start..]) catch return self.empty();
        return out.toOwnedSlice(self.allocator) catch return self.empty();
    }

    /// Записать строку в поток, если поток задан.
    fn write(self: *Bar, data: []const u8) void {
        if (self.stream) |w| {
            w.writeAll(data) catch {};
        }
    }

    /// Завершить отрисовку: новая строка + показать курсор.
    pub fn end(self: *Bar) void {
        self.write("\n");
        self.write(ANSI.show_cursor);
    }
};

/// Текущее время в секундах с дробной частью (монотонные часы).
fn nowSeconds(io: std.Io) f64 {
    const ts = std.Io.Timestamp.now(io, .awake);
    return @as(f64, @floatFromInt(ts.nanoseconds)) /
        @as(f64, @floatFromInt(std.time.ns_per_s));
}

/// Получить ширину терминала. При неудаче — 80 (аналог `tput cols`).
fn getTerminalWidth() usize {
    const terminal_size = getTerminalSize() catch TerminalSize.default();
    return @as(usize, terminal_size.cols);
}

/// Размеры терминала.
pub const TerminalSize = struct {
    cols: u16,
    rows: u16,

    pub fn default() TerminalSize {
        return .{ .cols = 80, .rows = 24 };
    }
};

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

// ══════════════════════════════════════════════════════════════════════════════
// Тесты
// ══════════════════════════════════════════════════════════════════════════════

const testing = std.testing;

/// Создаёт I/O интерфейс для тестов (лёгкий, на одном потоке).
fn testIo() std.Io {
    var threaded = std.Io.Threaded.init(testing.allocator, .{
        .async_limit = .nothing,
        .concurrent_limit = .nothing,
    });
    return threaded.io();
}

test "init создаёт бар и скрывает курсор в потоке" {
    var buf: [8192]u8 = undefined;
    var w = Writer.fixed(&buf);
    const io = testIo();

    var bar = try Bar.init(testing.allocator, io, 10, "Progress: [:bar]", &w);
    defer bar.deinit();

    const written = w.buffered();
    try testing.expect(std.mem.indexOf(u8, written, ANSI.hide_cursor) != null);
    try testing.expect(std.mem.indexOf(u8, written, ANSI.move_start) != null);
}

test "init с нулевым writer не падает" {
    const io = testIo();
    var bar = try Bar.init(testing.allocator, io, 10, "Progress: [:bar]", null);
    defer bar.deinit();

    try testing.expectEqual(@as(f64, 10), bar.total);
}

test "tick увеличивает current" {
    var buf: [8192]u8 = undefined;
    var w = Writer.fixed(&buf);
    const io = testIo();

    var bar = try Bar.init(testing.allocator, io, 10, "Progress: [:bar] - :current/:total", &w);
    defer bar.deinit();

    bar.throttle = 0; // принудительно отрисовываем всегда

    bar.tick(1);
    try testing.expectEqual(@as(f64, 1), bar.current);
    try testing.expect(bar.percent > 0);
}

test "update устанавливает current и пересчитывает процент" {
    var buf: [8192]u8 = undefined;
    var w = Writer.fixed(&buf);
    const io = testIo();

    var bar = try Bar.init(testing.allocator, io, 100, "Progress: [:bar]", &w);
    defer bar.deinit();

    bar.throttle = 0;

    bar.update(25);
    try testing.expectEqual(@as(f64, 25), bar.current);
    // percent = 25 / 100 * 100 = 25
    try testing.expectApproxEqAbs(@as(f64, 25), bar.percent, 0.001);

    bar.update(50);
    try testing.expectApproxEqAbs(@as(f64, 50), bar.percent, 0.001);
}

test "update при current=0 не вычисляет eta" {
    var buf: [8192]u8 = undefined;
    var w = Writer.fixed(&buf);
    const io = testIo();

    var bar = try Bar.init(testing.allocator, io, 10, "Progress: [:bar]", &w);
    defer bar.deinit();

    bar.throttle = 0;
    bar.update(0);

    try testing.expect(bar.eta == null);
}

test "eta вычисляется корректно" {
    var buf: [8192]u8 = undefined;
    var w = Writer.fixed(&buf);
    const io = testIo();

    var bar = try Bar.init(testing.allocator, io, 100, "Progress: [:bar]", &w);
    defer bar.deinit();

    bar.throttle = 0;
    bar.update(50);

    // При current=50, total=100: eta = elapsed/current*total - elapsed = elapsed.
    try testing.expect(bar.eta != null);
    if (bar.eta) |eta| {
        try testing.expectApproxEqAbs(bar.elapsed, eta, 0.001);
    }
}

test "rate вычисляется корректно" {
    var buf: [8192]u8 = undefined;
    var w = Writer.fixed(&buf);
    const io = testIo();

    var bar = try Bar.init(testing.allocator, io, 100, "Progress: [:bar]", &w);
    defer bar.deinit();

    bar.throttle = 0;
    bar.update(50);

    // rate = current / elapsed. elapsed > 0, поэтому rate > 0.
    try testing.expect(bar.rate > 0);
}

test "interrupt выводит сообщение и рисует бар" {
    var buf: [16384]u8 = undefined;
    var w = Writer.fixed(&buf);
    const io = testIo();

    var bar = try Bar.init(testing.allocator, io, 10, "Progress: [:bar]", &w);
    defer bar.deinit();

    const before_len = w.buffered().len;
    bar.interrupt("Ошибка: файл не найден");
    const after_len = w.buffered().len;

    try testing.expect(after_len > before_len);
    const written = w.buffered();
    try testing.expect(std.mem.indexOf(u8, written, "Ошибка") != null);
    try testing.expect(std.mem.indexOf(u8, written, "\n") != null);
}

test "end выводит новую строку и показывает курсор" {
    var buf: [4096]u8 = undefined;
    var w = Writer.fixed(&buf);
    const io = testIo();

    var bar = try Bar.init(testing.allocator, io, 10, "Progress: [:bar]", &w);
    defer bar.deinit();

    const before_len = w.buffered().len;
    bar.end();
    const after_len = w.buffered().len;

    try testing.expect(after_len > before_len);
    const written = w.buffered();
    try testing.expect(std.mem.indexOf(u8, written, ANSI.show_cursor) != null);
}

test "roundAndPad дополняет число пробелами до 6 символов" {
    var buf: [4096]u8 = undefined;
    var w = Writer.fixed(&buf);
    const io = testIo();

    var bar = try Bar.init(testing.allocator, io, 10, "Progress: [:bar]", &w);
    defer bar.deinit();

    const s = bar.roundAndPad(3.14, 1);
    defer bar.allocator.free(s);

    try testing.expectEqual(@as(usize, pad_width), s.len);
}

test "замена токенов в drawBar" {
    var buf: [16384]u8 = undefined;
    var w = Writer.fixed(&buf);
    const io = testIo();

    var bar = try Bar.init(testing.allocator, io, 10, "Progress: :current/:total - :percent% - :elapsed - :eta - :rate/s", &w);
    defer bar.deinit();

    bar.throttle = 0;
    bar.update(5);

    const written = w.buffered();
    // Токены должны быть заменены.
    try testing.expect(std.mem.indexOf(u8, written, ":current") == null);
    try testing.expect(std.mem.indexOf(u8, written, ":total") == null);
    try testing.expect(std.mem.indexOf(u8, written, ":percent") == null);
    // Значение присутствует.
    try testing.expect(std.mem.indexOf(u8, written, "Progress:") != null);
}

test "buildBarString создаёт полосу с правильными символами" {
    var buf: [4096]u8 = undefined;
    var w = Writer.fixed(&buf);
    const io = testIo();

    var bar = try Bar.init(testing.allocator, io, 10, "Progress: [:bar]", &w);
    defer bar.deinit();

    bar.percent = 50;
    const bar_str = bar.buildBarString(0);
    defer bar.allocator.free(bar_str);

    // Проверяем, что в строке есть и complete и incomplete символы.
    try testing.expect(std.mem.indexOfScalar(u8, bar_str, bar.symbol_complete) != null);
    try testing.expect(std.mem.indexOfScalar(u8, bar_str, bar.symbol_incomplete) != null);
}

test "deinit вызывает end (показывает курсор)" {
    var buf: [4096]u8 = undefined;
    var w = Writer.fixed(&buf);
    const io = testIo();

    var bar = try Bar.init(testing.allocator, io, 10, "Progress: [:bar]", &w);
    const written_before = w.buffered().len;

    // deinit должен вывести "\n" и показать курсор.
    bar.deinit();

    try testing.expect(w.buffered().len > written_before);
    const written = w.buffered();
    try testing.expect(std.mem.indexOf(u8, written, ANSI.show_cursor) != null);
}

test "buildBarString при 0% создаёт только неполные символы" {
    var buf: [4096]u8 = undefined;
    var w = Writer.fixed(&buf);
    const io = testIo();

    var bar = try Bar.init(testing.allocator, io, 10, "Progress: [:bar]", &w);
    defer bar.deinit();

    bar.percent = 0;
    const bar_str = bar.buildBarString(0);
    defer bar.allocator.free(bar_str);

    // При 0% символов complete быть не должно.
    try testing.expect(std.mem.indexOfScalar(u8, bar_str, bar.symbol_complete) == null);
    // При этом bar_str не пустой (есть incomplete символы).
    try testing.expect(bar_str.len > 0);
}

test "buildBarString при 100% создаёт только полные символы" {
    var buf: [4096]u8 = undefined;
    var w = Writer.fixed(&buf);
    const io = testIo();

    var bar = try Bar.init(testing.allocator, io, 10, "Progress: [:bar]", &w);
    defer bar.deinit();

    bar.percent = 100;
    const bar_str = bar.buildBarString(0);
    defer bar.allocator.free(bar_str);

    // При 100% символов incomplete быть не должно.
    try testing.expect(std.mem.indexOfScalar(u8, bar_str, bar.symbol_incomplete) == null);
}
