const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dockerz = b.addModule("dockerz", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const dusty = b.dependency("dusty", .{
        .target = target,
        .optimize = optimize,
        .use_tls = false,
        .use_http2 = false,
    });

    dockerz.addImport("dusty", dusty.module("dusty"));

    const docker_integration = b.option(
        bool,
        "docker-integration",
        "Run integration tests against the local docker socket",
    ) orelse false;

    const test_options = b.addOptions();
    test_options.addOption(
        bool,
        "docker_integration",
        docker_integration,
    );
    dockerz.addOptions("test_options", test_options);

    // tests
    const tests = b.addTest(.{
        .root_module = dockerz,
    });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);

    // Codegen step
    const openapi_codegen = b.addSystemCommand(&.{
        "openapi2zig",
    });
    openapi_codegen.addArgs(&.{ "generate", "-i", "spec/v1.55.json", "-o", "src/generated/models.zig", "--models-only" });
    const openapi_codegen_step = b.step("codegen", "Generate Docker API models");
    openapi_codegen_step.dependOn(&openapi_codegen.step);
}
