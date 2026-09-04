const std = @import("std");
const builtin = @import("builtin");
const TargetQuery = std.Target.Query;

const release_targets = [_]TargetQuery{
    .{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
    },
    .{
        .cpu_arch = .x86_64,
        .os_tag = .windows,
    },
    .{
        .cpu_arch = .x86_64,
        .os_tag = .macos,
    },
    .{
        .cpu_arch = .aarch64,
        .os_tag = .macos,
    },
};

const FileExtension = enum {
    zip,
    @"tar.gz",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lang = @import("src/lang.zig");

    // Локаль интерфейса: -Dlocale=ru|en|es|fr (по умолчанию ru).
    const locale_option = b.option(lang.Lang, "locale", "UI language (ru|en|es|fr)") orelse .ru;

    const build_options = b.addOptions();
    build_options.addOption(lang.Lang, "locale", locale_option);

    // 1. Add args.zig as a dependency
    const args_dep = b.dependency("args", .{
        .target = target,
        .optimize = optimize,
    });

    const zigquery = b.dependency("zigquery", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "check_links",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{},
        }),
    });

    exe.root_module.addImport("args", args_dep.module("args"));
    exe.root_module.addImport("zigquery", zigquery.module("zigquery"));
    exe.root_module.addOptions("build_options", build_options);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // Zig 0.17+ replaced b.args with addPassthruArgs().
    // Zig 0.16 still uses the b.args field.
    if (comptime builtin.zig_version.minor >= 17) {
        run_cmd.addPassthruArgs();
    } else {
        if (b.args) |args| {
            run_cmd.addArgs(args);
        }
    }

    // Модуль для тестов: включает все исходники приложения.
    const tests_mod = b.createModule(.{
        .root_source_file = b.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });

    tests_mod.addImport("zigquery", zigquery.module("zigquery"));
    tests_mod.addOptions("build_options", build_options);

    const exe_tests = b.addTest(.{
        .root_module = tests_mod,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_exe_tests.step);

    { // zig build release
        const release_step = b.step("release", "Build release binaries");
        const install_dir: std.Build.InstallDir = .{ .custom = "compressed" };
        const release_locales = [_]lang.Lang{ .ru, .en, .es, .fr };
        for (release_locales) |locale| {
            for (release_targets) |release_target| {
                const resolved_target = b.resolveTargetQuery(release_target);
                const exe_release = b.addExecutable(.{
                    .name = "check_links",
                    .root_module = b.createModule(.{
                        .root_source_file = b.path("src/main.zig"),
                        .target = resolved_target,
                        .optimize = .ReleaseSmall,
                        .imports = &.{},
                    }),
                });

                exe_release.root_module.addImport("args", args_dep.module("args"));
                exe_release.root_module.addImport("zigquery", zigquery.module("zigquery"));

                const build_release_options = b.addOptions();
                build_release_options.addOption(lang.Lang, "locale", locale);
                exe_release.root_module.addOptions("build_options", build_release_options);

                const is_windows = release_target.os_tag == .windows;
                const exe_name = b.fmt("{s}{s}", .{ exe.name, resolved_target.result.exeFileExt() });

                // An array has been created for possible extensions to new types of archives.
                const extensions: []const FileExtension = if (is_windows) &.{.zip} else &.{.@"tar.gz"};
                var file_path: std.Build.LazyPath = undefined;
                for (extensions) |extension| {
                    // archive file name
                    const file_name = b.fmt("check_links-{t}-{t}-{t}.{t}", .{
                        resolved_target.result.cpu.arch,
                        resolved_target.result.os.tag,
                        locale,
                        extension,
                    });

                    // creating a command inside the project build step
                    const compress_cmd = std.Build.Step.Run.create(b, "compress artifact");
                    // init command properties
                    compress_cmd.clearEnvironment();
                    compress_cmd.step.max_rss = 16 * 1024 * 1024; // 16 MiB

                    // Building the compress command line
                    switch (extension) {
                        .zip => {
                            compress_cmd.addArgs(&.{ "7z", "a", "-mx=9" });
                            file_path = compress_cmd.addOutputFileArg(file_name);
                            compress_cmd.addArtifactArg(exe_release);
                        },
                        .@"tar.gz" => {
                            compress_cmd.addArgs(&.{ "tar", "caf" });
                            file_path = compress_cmd.addOutputFileArg(file_name);
                            compress_cmd.addPrefixedDirectoryArg("-C", exe_release.getEmittedBinDirectory());
                            compress_cmd.addArg(exe_name);
                            compress_cmd.addArgs(&.{
                                "--sort=name",
                                "--numeric-owner",
                                "--owner=0",
                                "--group=0",
                            });
                        },
                    }

                    // The artifact install to zig-out/compressed directory
                    const install_compressed = b.addInstallFileWithDir(file_path, install_dir, file_name);
                    release_step.dependOn(&install_compressed.step);
                }
            }
        }
    }
}
