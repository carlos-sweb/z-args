const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zargs_module = b.addModule("zargs", .{
        .root_source_file = b.path("src/zargs.zig"),
        .target = target,
        .optimize = optimize,
    });

    const docs = b.addObject(.{
        .name = "zargs",
        .root_module = zargs_module,
    });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Generate native Zig API documentation in zig-out/docs");
    docs_step.dependOn(&install_docs.step);

    const test_step = b.step("test", "Run all tests");

    const test_files = [_][]const u8{
        "tests/simple_test.zig",
        "tests/builder_test.zig",
        "tests/declarative_test.zig",
        "tests/commands_test.zig",
    };

    inline for (test_files) |test_file| {
        const unit_tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(test_file),
                .target = target,
                .optimize = optimize,
            }),
        });
        unit_tests.root_module.addImport("zargs", zargs_module);
        const run_unit_tests = b.addRunArtifact(unit_tests);
        test_step.dependOn(&run_unit_tests.step);
    }

    b.default_step = test_step;
}
