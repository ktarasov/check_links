//! Собственный HTTP HEAD-клиент с поддержкой таймаутов запроса.
//!
//! Является альтернативой `std.http.Client`, у которого (на момент написания)
//! отсутствует поддержка таймаутов. Клиент реализован напрямую через сокеты
//! (`std.Io.net`), без использования `std.http.Client`.
//!
//! Особенности:
//!  - Предназначен только для HTTP-метода `HEAD`.
//!  - Поддерживает схемы `http` и `https` (TLS через `std.crypto.tls.Client`).
//!  - Редиректы не проходятся — возвращается код первого ответа.
//!  - Таймаут покрывает TCP-connect, отправку запроса, чтение ответа и TLS-handshake.
//!
//! Механизм таймаута: запускается поток-таймер, который по истечении
//! `timeout_ms` вызывает `shutdown` сокета, прерывая блокирующие операции
//! чтения/записи. Это единственный надёжный способ реализовать таймаут в
//! `std.Io.Threaded`, поскольку:
//!  - ядровый таймаут чтения/записи (`SO_RCVTIMEO`/`SO_SNDTIMEO`) не
//!    реализован в `std.Io.Threaded` (при `EAGAIN` возникает паника);
//!  - таймаут TCP-connect в `std.Io.Threaded` тоже не реализован (паникует
//!    при `timeout != .none`).
//!
//! Этап TCP-connect также покрыт таймаутом: `connectMany` запускается
//! асинхронно, и по истечении `timeout_ms` вызывается `Future.cancel`,
//! который через механизм отмены блокирующих syscall'ов `std.Io.Threaded`
//! (`signalCanceledSyscall`/SIGIO) прерывает «зависший» `connect()`.

const std = @import("std");

const Io = std.Io;
const net = Io.net;
const Uri = std.Uri;
const tls = std.crypto.tls.Client;
const Certificate = std.crypto.Certificate;
const http = std.http;
const request_headers = @import("request_headers.zig");

/// Порт по умолчанию для HTTP.
const default_http_port: u16 = 80;
/// Порт по умолчанию для HTTPS.
const default_https_port: u16 = 443;

/// Таймаут чтения/записи по умолчанию (миллисекунды).
pub const default_timeout_ms: u64 = 30_000;

/// Собственный HTTP HEAD-клиент.
pub const HttpHeadClient = @This();

// ---------------------------------------------------------------------------
// Поля состояния
// ---------------------------------------------------------------------------

/// Ввод-вывод (std.Io).
io: Io,
/// Аллокатор для временных буферов и TLS-операций.
allocator: std.mem.Allocator,
/// Таймаут чтения/записи ответа в миллисекундах.
timeout_ms: u64 = default_timeout_ms,
/// Пользовательские заголовки запроса.
headers: []const http.Header = &.{},

/// Пул системных сертификатов для TLS (заполняется лениво при первом https).
ca_bundle_lock: Io.RwLock = .init,
ca_bundle: Certificate.Bundle = .empty,
ca_loaded: bool = false,

/// Размер буфера для TLS-шифрования (минимальный размер для `tls.Client`).
tls_buffer_size: usize = tls.min_buffer_len,
/// Размер буфера чтения HTTP-заголовков.
read_buffer_size: usize = 8192,
/// Размер буфера записи HTTP-запроса.
write_buffer_size: usize = 1024,

// ---------------------------------------------------------------------------
// Ошибки
// ---------------------------------------------------------------------------

pub const Error = error{
    /// Истёк таймаут чтения/записи или TLS-handshake.
    Timeout,
    /// Неподдерживаемая схема URL (не `http`/`https`).
    UnsupportedScheme,
    /// В URL отсутствует хост.
    UriMissingHost,
    /// Некорректный URL.
    InvalidUrl,
    /// Некорректный HTTP-ответ (не удалось распарсить статус).
    InvalidResponse,
    /// Не удалось загрузить системные сертификаты для TLS.
    CertificateBundleLoadFailure,
    /// Не удалось установить TLS-соединение (handshake/проверка сертификата).
    TlsHandshakeFailed,
} || error{ OutOfMemory, Canceled };

// ---------------------------------------------------------------------------
// Жизненный цикл
// ---------------------------------------------------------------------------

/// Освобождает ресурсы клиента (в т.ч. кэш сертификатов TLS).
pub fn deinit(self: *HttpHeadClient) void {
    if (self.ca_loaded) {
        self.ca_bundle.deinit(self.allocator);
    }
    self.* = undefined;
}

// ---------------------------------------------------------------------------
// Основной метод
// ---------------------------------------------------------------------------

/// Выполняет HEAD-запрос к `url` и возвращает HTTP-код ответа.
///
/// В случае таймаута чтения/записи возвращает `error.Timeout`.
/// Редиректы не проходятся — возвращается код первого ответа.
pub fn check(self: *HttpHeadClient, url: []const u8) Error!u16 {
    const uri = Uri.parse(url) catch return error.InvalidUrl;

    const is_tls: bool = if (std.mem.eql(u8, uri.scheme, "http"))
        false
    else if (std.mem.eql(u8, uri.scheme, "https"))
        true
    else
        return error.UnsupportedScheme;

    const port: u16 = uri.port orelse (if (is_tls) default_https_port else default_http_port);

    var host_buffer: [net.HostName.max_len]u8 = undefined;
    const host = uri.getHost(&host_buffer) catch return error.UriMissingHost;

    // TCP-connect с таймаутом (см. `connectWithTimeout`).
    const stream = try self.connectWithTimeout(host, port);
    defer stream.close(self.io);

    // Поток-таймер: по истечении дедлайна вызывает shutdown сокета, прерывая
    // блокирующие чтение/запись (и TLS-handshake). Это единственный надёжный
    // механизм таймаута в `std.Io.Threaded`, где ядровый таймаут чтения/записи
    // (`SO_RCVTIMEO`) не реализован и вызывает панику при `EAGAIN`.
    var timer_event: Io.Event = .unset;
    var timed_out = std.atomic.Value(bool).init(false);
    var timer_ctx = TimerCtx{
        .io = self.io,
        .stream = stream,
        .event = &timer_event,
        .timed_out = &timed_out,
        .timeout_ms = self.timeout_ms,
    };
    const timer_thread: ?std.Thread = if (self.timeout_ms > 0)
        std.Thread.spawn(.{}, timerFunc, .{&timer_ctx}) catch null
    else
        null;
    defer if (timer_thread) |t| t.join();
    defer timer_event.set(self.io); // пробуждаем таймер при любом завершении

    // Буферы стрима. Для TLS оба буфера (read/write) должны быть
    // >= `tls.min_buffer_len`, т.к. `tls.Client` обменивается зашифрованными
    // записями через `stream_reader`/`stream_writer`.
    const stream_read_len: usize = if (is_tls) self.tls_buffer_size else self.read_buffer_size;
    const stream_write_len: usize = if (is_tls) self.tls_buffer_size else self.write_buffer_size;
    const read_buf = try self.allocator.alloc(u8, stream_read_len);
    defer self.allocator.free(read_buf);
    const write_buf = try self.allocator.alloc(u8, stream_write_len);
    defer self.allocator.free(write_buf);

    var stream_reader = stream.reader(self.io, read_buf);
    var stream_writer = stream.writer(self.io, write_buf);

    // Буферы TLS выделяются на всю длительность запроса (даже для http),
    // чтобы `tls_client` (и его reader/writer) оставались валидными до конца
    // `check()`. `defer` внутри блока `if` освобождал бы их слишком рано.
    const tls_read_buf = try self.allocator.alloc(u8, self.tls_buffer_size + self.read_buffer_size);
    defer self.allocator.free(tls_read_buf);
    const tls_write_buf = try self.allocator.alloc(u8, self.write_buffer_size);
    defer self.allocator.free(tls_write_buf);

    // TLS-клиент размещается в куче, чтобы не копировать его по значению:
    // `tls.Client` содержит vtable-методы, вычисляющие `this` через
    // `@fieldParentPtr`, поэтому копирование ломает ссылки.
    var tls_client: *tls = try self.allocator.create(tls);
    defer self.allocator.destroy(tls_client);
    if (is_tls) {
        tls_client.* = self.initTls(&stream_reader, &stream_writer, host.bytes, tls_read_buf, tls_write_buf) catch |err| {
            // При таймауте (shutdown от таймера во время handshake) — `error.Timeout`.
            if (timed_out.load(.seq_cst)) return error.Timeout;
            return err;
        };
    }

    const in_reader: *Io.Reader = if (is_tls) &tls_client.reader else &stream_reader.interface;
    const out_writer: *Io.Writer = if (is_tls) &tls_client.writer else &stream_writer.interface;

    // HTTP-парсер заголовков (read-only; тело у HEAD отсутствует).
    var http_reader: http.Reader = .{
        .in = in_reader,
        .state = .ready,
        .interface = undefined,
        .max_head_len = self.read_buffer_size,
    };

    // Отправляем HEAD-запрос.
    sendHead(out_writer, &uri, self.headers) catch {
        return if (timed_out.load(.seq_cst)) error.Timeout else error.InvalidResponse;
    };
    out_writer.flush() catch {
        return if (timed_out.load(.seq_cst)) error.Timeout else error.InvalidResponse;
    };
    if (is_tls) {
        // Для TLS нужен двойной flush (по образцу `std.http.Client.Connection.flush`):
        // `tls_client.writer.flush()` шифрует и помещает зашифрованные байты в буфер
        // нижележащего TCP-писателя, но не отправляет их по сети. Без сброса
        // `stream_writer` запрос остаётся в локальном буфере, сервер его не получает
        // и закрывает соединение (EOF при чтении ответа).
        stream_writer.interface.flush() catch {
            return if (timed_out.load(.seq_cst)) error.Timeout else error.InvalidResponse;
        };
    }

    // Читаем заголовки ответа.
    const head = http_reader.receiveHead() catch {
        return if (timed_out.load(.seq_cst)) error.Timeout else error.InvalidResponse;
    };

    return parseStatus(head);
}

/// Инициализирует TLS-соединение поверх TCP-стрима.
///
/// `tls_read_buf`/`tls_write_buf` должны жить дольше возвращённого значения
/// (аллокатор выделяет их в вызывающей функции `check`).
fn initTls(
    self: *HttpHeadClient,
    stream_reader: *net.Stream.Reader,
    stream_writer: *net.Stream.Writer,
    host: []const u8,
    tls_read_buf: []u8,
    tls_write_buf: []u8,
) Error!tls {
    // Ленивая загрузка системных сертификатов.
    if (self.ca_loaded == false) {
        var bundle: Certificate.Bundle = .empty;
        defer bundle.deinit(self.allocator);
        const now = Io.Clock.real.now(self.io);
        bundle.rescan(self.allocator, self.io, now) catch
            return error.CertificateBundleLoadFailure;
        try self.ca_bundle_lock.lock(self.io);
        defer self.ca_bundle_lock.unlock(self.io);
        std.mem.swap(Certificate.Bundle, &self.ca_bundle, &bundle);
        self.ca_loaded = true;
    }

    var entropy: [tls.Options.entropy_len]u8 = undefined;
    self.io.random(&entropy);

    return tls.init(
        &stream_reader.interface,
        &stream_writer.interface,
        .{
            .host = .{ .explicit = host },
            .ca = .{
                .bundle = .{
                    .gpa = self.allocator,
                    .io = self.io,
                    .lock = &self.ca_bundle_lock,
                    .bundle = &self.ca_bundle,
                },
            },
            .write_buffer = tls_write_buf,
            .read_buffer = tls_read_buf,
            .entropy = &entropy,
            .realtime_now = Io.Clock.real.now(self.io),
            .allow_truncation_attacks = true,
        },
    ) catch |err| switch (err) {
        error.Canceled => return error.Canceled,
        // Таймаут/сетевая ошибка; `timed_out` проверяется вызывающим кодом.
        error.ReadFailed, error.WriteFailed => return error.InvalidResponse,
        else => return error.TlsHandshakeFailed,
    };
}

// ---------------------------------------------------------------------------
// Формирование HTTP-запроса и парсинг ответа
// ---------------------------------------------------------------------------

/// Записывает HEAD-запрос в writer.
fn sendHead(w: *Io.Writer, uri: *const Uri, headers: []const http.Header) Io.Writer.Error!void {
    try w.writeAll("HEAD ");
    try uri.writeToStream(w, .{ .path = true, .query = true });
    try w.writeAll(" HTTP/1.1\r\n");
    if (!request_headers.contains(headers, "host")) {
        try w.writeAll("host: ");
        try uri.writeToStream(w, .{ .authority = true });
        try w.writeAll("\r\n");
    }
    for (headers) |header| {
        try w.writeAll(header.name);
        try w.writeAll(": ");
        try w.writeAll(header.value);
        try w.writeAll("\r\n");
    }
    if (!request_headers.contains(headers, "user-agent")) {
        try w.writeAll("user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/103.0.5060.114 Safari/537.36\r\n");
    }
    if (!request_headers.contains(headers, "accept-encoding")) {
        try w.writeAll("accept-encoding: gzip, deflate\r\n");
    }
    if (!request_headers.contains(headers, "connection")) {
        try w.writeAll("connection: keep-alive\r\n");
    }
    try w.writeAll("\r\n");
}

/// Извлекает HTTP-код из строки заголовков ответа.
fn parseStatus(head: []const u8) Error!u16 {
    const line_end = std.mem.indexOf(u8, head, "\r\n") orelse head.len;
    const status_line = head[0..line_end];

    var it = std.mem.tokenizeAny(u8, status_line, " ");
    _ = it.next() orelse return error.InvalidResponse; // "HTTP/1.1"
    const code_str = it.next() orelse return error.InvalidResponse;

    return std.fmt.parseInt(u16, code_str, 10) catch error.InvalidResponse;
}

// ---------------------------------------------------------------------------
// Таймаут через поток-таймер
// ---------------------------------------------------------------------------

/// Контекст потока-таймера.
const TimerCtx = struct {
    io: Io,
    stream: net.Stream,
    event: *Io.Event,
    timed_out: *std.atomic.Value(bool),
    timeout_ms: u64,
};

/// Поток-таймер: ждёт либо сигнал об успешном завершении, либо истечение
/// таймаута. При истечении помечает `timed_out` и вызывает `shutdown` сокета,
/// что прерывает блокирующие `recv`/`send` в основном потоке.
fn timerFunc(ctx: *TimerCtx) void {
    const timeout: Io.Timeout = .{
        .duration = .{
            .raw = .fromMilliseconds(@intCast(ctx.timeout_ms)),
            .clock = .awake,
        },
    };
    ctx.event.waitTimeout(ctx.io, timeout) catch |err| switch (err) {
        error.Timeout => {
            ctx.timed_out.store(true, .seq_cst);
            ctx.stream.shutdown(ctx.io, .both) catch {};
        },
        error.Canceled => {},
    };
}

/// Мапит ошибку подключения в ошибку клиента.
fn mapConnectError(err: anyerror) Error {
    return switch (err) {
        error.Canceled => error.Canceled,
        else => error.InvalidResponse,
    };
}

/// Устанавливает TCP-соединение с таймаутом на этап connect.
///
/// Воспроизводит логику `net.HostName.connect`, но с получением `Future`
/// задачи `connectMany`, что позволяет прервать «зависший» `connect()`
/// через `Future.cancel` по истечении `timeout_ms`. Механизм отмены
/// (`signalCanceledSyscall`/SIGIO) прерывает блокирующий syscall connect.
fn connectWithTimeout(self: *HttpHeadClient, host: net.HostName, port: u16) Error!net.Stream {
    var connect_many_buffer: [32]net.IpAddress.ConnectError!net.Stream = undefined;
    var connect_many_queue: Io.Queue(net.IpAddress.ConnectError!net.Stream) = .init(&connect_many_buffer);

    var connect_many = self.io.async(net.HostName.connectMany, .{
        host,
        self.io,
        port,
        &connect_many_queue,
        .{ .mode = .stream },
    });

    // Поток-таймер для этапа connect: по истечении дедлайна отменяет
    // `connectMany`, прерывая блокирующий `connect()`.
    var timer_event: Io.Event = .unset;
    var timed_out = std.atomic.Value(bool).init(false);
    var connect_timer_ctx = ConnectTimerCtx{
        .io = self.io,
        .future = &connect_many,
        .event = &timer_event,
        .timed_out = &timed_out,
        .timeout_ms = self.timeout_ms,
    };
    const timer_thread: ?std.Thread = if (self.timeout_ms > 0)
        std.Thread.spawn(.{}, connectTimerFunc, .{&connect_timer_ctx}) catch null
    else
        null;

    defer {
        // Пробуждаем таймер при любом завершении, чтобы он не отменил уже
        // установленное соединение, и дожидаемся его завершения.
        timer_event.set(self.io);
        if (timer_thread) |t| t.join();
        // Если таймер уже отменил future при таймауте — повторно не отменяем
        // (это была бы отмена уже уничтоженного future).
        if (!timed_out.load(.seq_cst)) {
            connect_many.cancel(self.io) catch {};
        }
        // Закрываем соединения, успевшие установиться до завершения/отмены.
        while (connect_many_queue.getOneUncancelable(self.io)) |loser| {
            if (loser) |s| s.close(self.io) else |_| {}
        } else |err| switch (err) {
            error.Closed => {},
        }
    }

    var ip_connect_error: ?net.IpAddress.ConnectError = null;

    while (connect_many_queue.getOne(self.io)) |result| {
        if (result) |stream| return stream else |err| switch (err) {
            error.Canceled => unreachable,

            error.SystemResources,
            error.OptionUnsupported,
            error.ProcessFdQuotaExceeded,
            error.SystemFdQuotaExceeded,
            error.WouldBlock,
            => |e| return mapConnectError(e),

            else => |e| ip_connect_error = e,
        }
    } else |err| switch (err) {
        error.Canceled => |e| return e,
        error.Closed => {
            // Таймер сработал — connect превысил таймаут.
            if (timed_out.load(.seq_cst)) return error.Timeout;
            // Разрешение имени / попытки подключения завершились неудачей.
            if (connect_many.await(self.io)) |_| {
                return mapConnectError(ip_connect_error orelse error.InvalidResponse);
            } else |_| {
                return error.InvalidResponse;
            }
        },
    }
}

/// Контекст потока-таймера для этапа TCP-connect.
const ConnectTimerCtx = struct {
    io: Io,
    future: *Io.Future(net.HostName.LookupError!void),
    event: *Io.Event,
    timed_out: *std.atomic.Value(bool),
    timeout_ms: u64,
};

/// Поток-таймер для connect: ждёт либо сигнал об успешном завершении, либо
/// истечение таймаута. При истечении помечает `timed_out` и отменяет
/// `connectMany`, что прерывает блокирующий `connect()` через
/// `signalCanceledSyscall` (SIGIO).
fn connectTimerFunc(ctx: *ConnectTimerCtx) void {
    const timeout: Io.Timeout = .{
        .duration = .{
            .raw = .fromMilliseconds(@intCast(ctx.timeout_ms)),
            .clock = .awake,
        },
    };
    ctx.event.waitTimeout(ctx.io, timeout) catch |err| switch (err) {
        error.Timeout => {
            ctx.timed_out.store(true, .seq_cst);
            ctx.future.cancel(ctx.io) catch {};
        },
        error.Canceled => {},
    };
}

// ---------------------------------------------------------------------------
// Тесты
// ---------------------------------------------------------------------------

const testing = std.testing;

/// Тестовый сервер: принимает одно соединение, возвращает заданный статус.
///
/// Если `delay_ms > 0`, перед ответом сервер задерживается на указанное
/// время (это позволяет имитировать «медленный»/«зависший» сервер).
const TestServer = struct {
    io: Io,
    server: net.Server,
    read_buffer: [8192]u8 = undefined,
    write_buffer: [8192]u8 = undefined,
    status: http.Status,
    delay_ms: u64 = 0,
    x_test_count: usize = 0,
    user_agent_count: usize = 0,
    custom_user_agent_seen: bool = false,

    fn init(io: Io, status: http.Status) !TestServer {
        var address: net.IpAddress = .{ .ip4 = net.Ip4Address.loopback(0) };
        const server = try net.IpAddress.listen(&address, io, .{});
        return .{ .io = io, .server = server, .status = status };
    }

    fn deinit(self: *TestServer) void {
        self.server.deinit(self.io);
    }

    fn port(self: *const TestServer) u16 {
        return self.server.socket.address.getPort();
    }

    fn baseUrl(self: *const TestServer, buffer: []u8) []const u8 {
        return std.fmt.bufPrint(buffer, "http://127.0.0.1:{d}", .{self.port()}) catch unreachable;
    }

    fn serveOne(self: *TestServer) void {
        const stream = self.server.accept(self.io) catch return;
        defer stream.close(self.io);

        var reader = stream.reader(self.io, &self.read_buffer);
        var writer = stream.writer(self.io, &self.write_buffer);
        var http_server = http.Server.init(&reader.interface, &writer.interface);
        var request = http_server.receiveHead() catch return;

        var headers = request.iterateHeaders();
        while (headers.next()) |header| {
            if (std.ascii.eqlIgnoreCase(header.name, "x-test")) {
                self.x_test_count += 1;
            }
            if (std.ascii.eqlIgnoreCase(header.name, "user-agent")) {
                self.user_agent_count += 1;
                if (std.mem.eql(u8, header.value, "custom-agent")) {
                    self.custom_user_agent_seen = true;
                }
            }
        }

        if (self.delay_ms > 0) {
            Io.sleep(self.io, .fromMilliseconds(@intCast(self.delay_ms)), .awake) catch return;
        }

        request.respond("", .{ .status = self.status }) catch return;
    }
};

fn serveOneThread(server: *TestServer) void {
    server.serveOne();
}

/// Создаёт клиент с заданным таймаутом.
fn clientWithTimeout(timeout_ms: u64) HttpHeadClient {
    return .{
        .io = testing.io,
        .allocator = testing.allocator,
        .timeout_ms = timeout_ms,
    };
}

/// Формирует URL для обращения к тестовому серверу с заданным путём.
/// Записывает результат в `buf` (должен быть достаточно большим).
fn urlFor(server: *const TestServer, path: []const u8, buf: []u8) []const u8 {
    var base_buf: [128]u8 = undefined;
    const base = server.baseUrl(&base_buf);
    return std.fmt.bufPrint(buf, "{s}{s}", .{ base, path }) catch unreachable;
}

test "HEAD: сервер отвечает 200" {
    var server = try TestServer.init(testing.io, .ok);
    defer server.deinit();
    var url_buf: [256]u8 = undefined;
    const url = urlFor(&server, "/page", &url_buf);

    const thread = try std.Thread.spawn(.{}, serveOneThread, .{&server});
    defer thread.join();

    var client = clientWithTimeout(5_000);
    defer client.deinit();

    const code = try client.check(url);
    try testing.expectEqual(@as(u16, 200), code);
}

test "HEAD: сервер отвечает 404" {
    var server = try TestServer.init(testing.io, .not_found);
    defer server.deinit();
    var url_buf: [256]u8 = undefined;
    const url = urlFor(&server, "/missing", &url_buf);

    const thread = try std.Thread.spawn(.{}, serveOneThread, .{&server});
    defer thread.join();

    var client = clientWithTimeout(5_000);
    defer client.deinit();

    const code = try client.check(url);
    try testing.expectEqual(@as(u16, 404), code);
}

test "HEAD: сервер отвечает 500" {
    var server = try TestServer.init(testing.io, .internal_server_error);
    defer server.deinit();
    var url_buf: [256]u8 = undefined;
    const url = urlFor(&server, "/error", &url_buf);

    const thread = try std.Thread.spawn(.{}, serveOneThread, .{&server});
    defer thread.join();

    var client = clientWithTimeout(5_000);
    defer client.deinit();

    const code = try client.check(url);
    try testing.expectEqual(@as(u16, 500), code);
}

test "HEAD: сервер отвечает редиректом 301 (редирект не проходится)" {
    var server = try TestServer.init(testing.io, .moved_permanently);
    defer server.deinit();
    var url_buf: [256]u8 = undefined;
    const url = urlFor(&server, "/redirect", &url_buf);

    const thread = try std.Thread.spawn(.{}, serveOneThread, .{&server});
    defer thread.join();

    var client = clientWithTimeout(5_000);
    defer client.deinit();

    const code = try client.check(url);
    try testing.expectEqual(@as(u16, 301), code);
}

test "HEAD: граничное условие — нулевой таймаут означает бесконечное ожидание" {
    // timeout_ms = 0 — таймауты отключены; запрос должен успешно завершиться.
    var server = try TestServer.init(testing.io, .ok);
    defer server.deinit();
    var url_buf: [256]u8 = undefined;
    const url = urlFor(&server, "/page", &url_buf);

    const thread = try std.Thread.spawn(.{}, serveOneThread, .{&server});
    defer thread.join();

    var client = clientWithTimeout(0);
    defer client.deinit();

    const code = try client.check(url);
    try testing.expectEqual(@as(u16, 200), code);
}

test "HEAD: отправляет повторяющиеся заголовки и заменяет встроенный User-Agent" {
    var server = try TestServer.init(testing.io, .ok);
    defer server.deinit();
    var url_buf: [256]u8 = undefined;
    const url = urlFor(&server, "/headers", &url_buf);

    const thread = try std.Thread.spawn(.{}, serveOneThread, .{&server});

    var client = clientWithTimeout(5_000);
    client.headers = &.{
        .{ .name = "X-Test", .value = "one" },
        .{ .name = "X-Test", .value = "two" },
        .{ .name = "User-Agent", .value = "custom-agent" },
    };
    defer client.deinit();

    const code = try client.check(url);
    thread.join();

    try testing.expectEqual(@as(u16, 200), code);
    try testing.expectEqual(@as(usize, 2), server.x_test_count);
    try testing.expectEqual(@as(usize, 1), server.user_agent_count);
    try testing.expect(server.custom_user_agent_seen);
}

test "HEAD: таймаут — сервер не отвечает в течение заданного времени" {
    // Сервер отвечает с задержкой 2000мс, клиентский таймаут — 200мс.
    var server = try TestServer.init(testing.io, .ok);
    server.delay_ms = 2_000;
    defer server.deinit();
    var url_buf: [256]u8 = undefined;
    const url = urlFor(&server, "/slow", &url_buf);

    var client = clientWithTimeout(200);
    defer client.deinit();

    const thread = try std.Thread.spawn(.{}, serveOneThread, .{&server});
    defer thread.join();

    try testing.expectError(error.Timeout, client.check(url));
}

test "HEAD: connect к недостижимому адресу не вешает клиент" {
    // Подключение к немаршрутизируемому документационному адресу (RFC 5737,
    // 192.0.2.0/24) никогда не должно завершаться успехом. В зависимости от
    // окружения:
    //  - если ОС блокирует connect (пакеты отбрасываются) — малый таймаут
    //    прерывает его через `Future.cancel` и возвращает `error.Timeout`;
    //  - если ОС сразу возвращает "network unreachable" — `error.InvalidResponse`.
    // В обоих случаях клиент обязан вернуться в пределах таймаута, не зависнув.
    var client = clientWithTimeout(500);
    defer client.deinit();

    if (client.check("http://192.0.2.1/")) |_| {
        // Успешный connect к документационному адресу невозможен.
        return error.Unexpected;
    } else |err| switch (err) {
        error.Timeout => {},
        error.InvalidResponse => {},
        else => |e| return e,
    }
}

test "HEAD: connect к заблокированному адресу не вешает клиент" {
    var client = clientWithTimeout(1_000);
    defer client.deinit();

    if (client.check("https://t.me/zig_lang_ru/1068")) |_| {
        // Успешный connect к заблокированному адресу невозможен из РФ без VPN.
        return error.Unexpected;
    } else |err| switch (err) {
        error.Timeout => {},
        error.InvalidResponse => {},
        else => |e| return e,
    }
}

test "HEAD: невалидный URL (нет схемы)" {
    var client = clientWithTimeout(5_000);
    defer client.deinit();
    try testing.expectError(error.InvalidUrl, client.check("127.0.0.1:80/page"));
}

test "HEAD: неподдерживаемая схема" {
    var client = clientWithTimeout(5_000);
    defer client.deinit();
    try testing.expectError(error.UnsupportedScheme, client.check("ftp://example.com/file"));
}

test "HEAD: URL без хоста" {
    var client = clientWithTimeout(5_000);
    defer client.deinit();
    try testing.expectError(error.UriMissingHost, client.check("http:///path"));
}

test "parseStatus: извлекает HTTP-код из строки заголовков" {
    try testing.expectEqual(@as(u16, 200), try parseStatus("HTTP/1.1 200 OK\r\ncontent-length: 0\r\n\r\n"));
    try testing.expectEqual(@as(u16, 404), try parseStatus("HTTP/1.1 404 Not Found\r\n\r\n"));
    try testing.expectEqual(@as(u16, 301), try parseStatus("HTTP/1.0 301 Moved Permanently\r\n\r\n"));
}

test "parseStatus: некорректная строка ответа" {
    try testing.expectError(error.InvalidResponse, parseStatus("not an http response"));
    try testing.expectError(error.InvalidResponse, parseStatus("HTTP/1.1"));
}

test "HEAD: HTTPS (TLS) — реальный сервер zig-lang.ru" {
    // Интеграционный тест TLS: выполняет настоящий HTTPS HEAD-запрос.
    // Требует доступа к сети. Проверяет установку TLS-соединения
    // (включая проверку сертификата через системный CA-пул).
    var client = clientWithTimeout(15_000);
    defer client.deinit();

    const code = try client.check("https://zig-lang.ru/");
    try testing.expectEqual(@as(u16, 200), code);
}
