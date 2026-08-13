//! Корневой файл тестов.
//!
//! Импортирует все модули приложения, содержащие тесты, чтобы они были
//! включены в сборку тестов (`zig build test`).

const std = @import("std");

test {
    _ = @import("url_normalize.zig");
    _ = @import("html_parser.zig");
    _ = @import("collect_urls.zig");
    _ = @import("check_http.zig");
    _ = @import("check_link_list.zig");
    _ = @import("TableFormatter.zig");
    _ = @import("table_view.zig");
    _ = @import("export_csv.zig");
    _ = @import("check_links_by_page.zig");
    _ = @import("bar.zig");
    _ = @import("http_integration_test.zig");
}
