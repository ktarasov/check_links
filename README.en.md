# CheckLinks

Read this document in other languages: [Русский](README.md) · [Español](README.es.md) · [Français](README.fr.md)

---

## About

**CheckLinks** is a command-line utility (CLI) written in **Zig** for checking links on a web page.

The utility loads the HTML page at the given URL, collects all links (`<a href>`) and images (`<img src>`), and then checks each URL for availability. The results are displayed on the screen as a table or exported to a CSV file.

> The project is a Zig rewrite of a previously existing PHP implementation.

## Features

- Loads pages using the `http://`, `https://`, and `file://` schemes (local HTML file reading).
- Extracts URLs from the `href` attribute of `<a>` tags and the `src` attribute of `<img>` tags.
- Normalizes relative links into absolute ones based on the base domain (including protocol-relative `//` links).
- Removes duplicate URLs.
- Concurrently checks the availability of each URL using the `HEAD` method (one thread per URL).
- Checks URLs concurrently in batches of a configurable size: the number of parallel requests is set via `--parallels` (default 5), concurrently within a batch and sequentially between batches.
- Custom HTTP HEAD client with TLS support and a request timeout (15 seconds by default, configurable via `--timeout`).
- Repeatable custom HTTP headers for authenticated pages and same-origin links.
- Groups results by HTTP response code.
- Terminal table output with color-coded codes:
  - `2xx` — green;
  - `3xx` — yellow;
  - `4xx`/`5xx` — red.
- Exports results to a CSV file (delimiter `;`).
- "Errors only" mode — shows only failed links.
- Progress bar for the checking process.
- UI localization: CLI help, error and warning messages, table and CSV headers, and the progress-bar template can be built in Russian, English, Spanish, or French via the `-Dlocale` build option (default `ru`).
- Generates a shell autocompletion script via the `completion` subcommand. Supported shells are `bash`, `zsh`, `fish`, and `nushell`.
- Explicit application error handling in `main`: errors from argument parsing, parser initialization, headers, and completion-script generation are printed as a localized message to stderr, and the process exits with a non-zero return code.

## Requirements

- **Zig 0.16.0** or newer (see `minimum_zig_version` in [`build.zig.zon`](build.zig.zon)).

External project dependencies:

- [`args.zig`](https://github.com/ktarasov/args.zig) (0.0.9) — command-line argument parsing; provides subcommands and autocompletion script generation.
- `zigquery` (0.2.0) — HTML parser for extracting `href`/`src`.

## Installation and Build

Clone the repository and build the project:

```sh
zig build
```

The binary will be placed in `zig-out/bin/`.

### Build Commands

| Command | Description |
| --- | --- |
| `zig build` | Builds the executable (`check_links`). |
| `zig build run -- <arguments>` | Builds and runs the utility. |
| `zig build test` | Runs all tests. |
| `zig build release` | Builds release binaries (compressed archives) for multiple platforms. |
| `zig build -Dlocale=ru` | Builds the Russian UI (default). |
| `zig build -Dlocale=en` | Builds the English UI. |
| `zig build -Dlocale=es` | Builds the Spanish UI. |
| `zig build -Dlocale=fr` | Builds the French UI. |

### Supported Release Platforms

`zig build release` builds and packages binaries for:

- `x86_64-linux`
- `x86_64-windows` (`.zip` archive)
- `x86_64-macos`
- `aarch64-macos`

### Localization

The utility UI (CLI help, error and warning messages, table and CSV headers, progress-bar template) can be built in Russian, English, Spanish, or French. The language is selected at build time via the `-Dlocale` build option (default — Russian):

```sh
zig build -Dlocale=ru   # Russian UI (default)
zig build -Dlocale=en   # English UI
zig build -Dlocale=es   # Spanish UI
zig build -Dlocale=fr   # French UI
```

Localized strings live in the typed catalog [`src/i18n.zig`](src/i18n.zig); key completeness for each language is guaranteed by the compiler.

## Usage

```sh
check_links <URL> [options]
```

### Arguments

| Argument | Description |
| --- | --- |
| `<URL>` | URL of the page whose links to check (required). |
| `-f`, `--fail` | Show only failed links. |
| `-e`, `--export <file>` | Export results to a CSV file. |
| `-t`, `--timeout <seconds>` | Request timeout in seconds (default 15; `0` — no timeout). |
| `-H`, `--header <NAME: VALUE>` | Add an HTTP header; may be repeated. |
| `-p`, `--parallels <count>` | Number of parallel requests (default 5; from 1 to 100). |

### The `completion` Subcommand

Generates an autocompletion script for the environment the utility is run in. The shell type is detected automatically from the `$SHELL` environment variable. Supported shells are `bash`, `zsh`, `fish`, and `nushell`.

```sh
check_links completion
```

The script is written to standard output, so you can redirect it to your shell's autoload file:

```sh
# bash
check_links completion > ~/.bash_completion

# zsh
check_links completion > ${fpath[1]}/_check_links

# fish
check_links completion > ~/.config/fish/completions/check_links.fish

# nushell
check_links completion > check_links-completions.nu
```

If the shell type cannot be determined or generation fails, the utility prints an error to stderr and exits with a non-zero return code.

### Examples

```sh
# Check all links on a page and print a table in the terminal
check_links https://example.com/

# Generate an autocompletion script for the current shell
check_links completion

# Show only failed links
check_links --fail https://example.com/

# Increase the request timeout to 60 seconds
check_links --timeout 60 https://example.com/

# Increase the number of parallel requests (e.g., to 20)
check_links --parallels 20 https://example.com/

# Export results to a CSV file
check_links --export result.csv https://example.com/

# Export only failed links to CSV
check_links --fail --export errors.csv https://example.com/

# Check an authenticated page with multiple headers
check_links -H 'Authorization: Bearer token' \
  --header 'X-Tenant-ID: 42' \
  https://example.com/private
```

Headers are sent when loading the source page and when making `HEAD` requests to links with the same origin (scheme, host, and effective port). They are omitted when redirecting to or checking an external origin. Both `--header 'NAME: VALUE'` and `--header='NAME: VALUE'` forms are supported.

> Header values passed on the command line may be stored in shell history or visible to other local processes. Keep this in mind when passing tokens or other secrets.

### Example Output (table)

```
--------------------------------------------------------------------------
 №      | URL of the page         | Checked URL                | HTTP Code
--------------------------------------------------------------------------
     1. | https://example.com     | https://example.com/page1  |   200
     2. | https://example.com     | https://example.com/page2  |   404
     3. | https://example.com     | https://example.com/page3  |   200
--------------------------------------------------------------------------
```

HTTP codes in the table are color-coded by range:
- **2xx** — green;
- **3xx** — yellow;
- **4xx/5xx** — red.

## Typical Use Cases

### 1. Checking for broken links on your site after a redesign or migration

After changing the design, URL structure, or moving to a new domain, you should make sure that no links point to old (removed) sections or files.

```sh
check_links --fail https://example.com/page/
```

The utility shows only links that lead to non-existent pages (404, 410) or server errors (500).

### 2. SEO audit: finding links to external resources that stopped working

Broken external links harm behavioral factors and search-engine trust in your site. Regularly checking external links is a mandatory part of SEO maintenance.

```sh
check_links --export broken-links.csv https://example.com/
```

The CSV file can be opened in Excel/Google Sheets and handed to a content manager for fixing.

### 3. Checking links in an article or landing page before publication

Before publishing content with many external sources, it helps to verify that all links are working and do not lead to 404.

```sh
check_links https://blog.example.com/draft-article/
```

Green 200 codes mean everything is fine, yellow 3xx means redirects (worth updating the links to current ones), red 4xx/5xx are broken links.

### 4. Monitoring links in documentation or a knowledge base

For sites with extensive documentation (wikis, knowledge bases, manuals), it is useful to set up a regular link check so that the documentation stays up to date.

```sh
# Weekly check via cron
0 6 * * 1 /usr/local/bin/check_links --fail --export /var/log/links-check/docs-errors.csv https://docs.company.ru/
```

### 5. Checking links on a product page in an online store

Product cards often contain links to related products, categories, and reviews. If such links lead nowhere, it is a direct loss of sales.

```sh
check_links --fail https://store.example.com/catalog/product-123/
```

### 6. Auditing a link profile before buying links

When doing SEO, before buying links from a donor site, it is worth checking whether it has broken pages that could reduce the effect of the purchase.

```sh
check_links --fail https://donor-site.example.com/
```

### 7. Finding images that fail to load

The utility collects not only links (`<a href>`) but also images (`<img src>`). This lets you find broken images on a page — a common cause of poor visual perception of a site.

```sh
check_links --fail https://example.com/gallery/
```

### 8. Checking redirects (redirect chains)

Although the utility does not follow redirect chains step by step, it shows the 3xx HTTP code for URLs that redirect. This helps to identify unnecessary intermediate redirects that slow down page loading.

```sh
check_links https://example.com/
```

Pay attention to the yellow rows — these are URLs returning 301, 302, etc.

### 9. Exporting a full link map of a page for further analysis

CSV export lets you pass results to BI systems, Google Sheets, or Excel for building reports and dashboards.

```sh
check_links --export full-links-report.csv https://example.com/
```

### 10. Quick client site check before a presentation

For agencies and freelancers: before showing a site to a client, run the home page and typical pages through the utility to avoid an awkward situation with broken links during a demo.

```sh
check_links --fail https://client-site.example.com/
```

## Project Structure

| Module | Purpose |
| --- | --- |
| [`src/main.zig`](src/main.zig) | CLI entry point: argument parsing (including timeout, the number of parallel requests, and the `completion` subcommand), plus explicit error handling with localized messages and correct return codes. |
| [`src/i18n.zig`](src/i18n.zig) | Typed catalog of localized messages (`ru`/`en`/`es`/`fr`) and active-locale selection via `-Dlocale`. |
| [`src/lang.zig`](src/lang.zig) | Enum of supported UI languages (used by the build). |
| [`src/check_links_by_page.zig`](src/check_links_by_page.zig) | Orchestrates link checking for a single page. |
| [`src/collect_urls.zig`](src/collect_urls.zig) | Loads the page and collects URLs from HTML. |
| [`src/html_parser.zig`](src/html_parser.zig) | HTML parser (based on the `zigquery` library) for extracting `href`/`src`. |
| [`src/url_normalize.zig`](src/url_normalize.zig) | URL normalization and absolute URL building. |
| [`src/check_link_list.zig`](src/check_link_list.zig) | Batch URL checking (chunks) and grouping by code. |
| [`src/check_http.zig`](src/check_http.zig) | Concurrent HTTP code checking. |
| [`src/http_head_client.zig`](src/http_head_client.zig) | Custom HTTP HEAD client with TLS and timeout. |
| [`src/request_headers.zig`](src/request_headers.zig) | Custom HTTP header parsing and same-origin policy. |
| [`src/table_view.zig`](src/table_view.zig) | Renders results as a terminal table. |
| [`src/export_csv.zig`](src/export_csv.zig) | Exports results to CSV. |
| [`src/TableFormatter.zig`](src/TableFormatter.zig) | Table formatting to fit the terminal width. |
| [`src/bar.zig`](src/bar.zig) | Progress bar for the checking process. |
| [`src/tests.zig`](src/tests.zig) | Root test file. |
| [`src/http_integration_test.zig`](src/http_integration_test.zig) | HTTP link-checking integration tests against a local server. |

## How It Works

1. The utility loads the HTML content of the page from the given URL.
2. The HTML parser extracts all URLs from `href` and `src` attributes.
3. Relative links are normalized to absolute ones; duplicates are removed.
4. Each URL is checked concurrently with the `HEAD` method using a custom HTTP HEAD client with a request timeout.
5. Results are grouped by HTTP response code and printed as a table or exported to a CSV file.

## CSV Format

Exports use the `;` delimiter. The file structure:

```
№;URL страницы;Проверенный URL;HTTP Код
1;https://example.com;https://example.com/page1;200
2;https://example.com;https://example.com/page2;404
```

If the file already exists, it is renamed to `<name>.bak` before being overwritten.

## Testing

Run all tests:

```sh
zig build test
```

Tests cover: HTML parsing (based on `zigquery`), URL normalization, link collection from a page, custom HTTP header parsing and same-origin policy, HTTP code checking against a local test server (including timeouts and redirects), table formatting, and CSV export.

## License

This project is distributed under the **Vaslex Free Software License (version 2.0, dated 11 March 2025)**. The full license text is available in the [`LICENSE`](LICENSE) file.