const std = @import("std");
const glfw = @import("mach-glfw/build.zig");
const gpu_sdk = @import("mach-gpu/sdk.zig");

pub fn build(b: *std.build.Builder) !void {
    const mode = b.standardReleaseOptions();
    const target = b.standardTargetOptions(.{});
    const gpu = gpu_sdk.Sdk(.{
        .glfw = glfw,
        .gpu_dawn = crescent,
    });

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&(try gpu.testStep(b, mode, target, .{})).step);

    // const example = b.addExecutable("gpu-hello-triangle", "mach-gpu/examples/main.zig");
    // example.setBuildMode(mode);
    // example.setTarget(target);
    // example.addPackage(gpu.pkg);
    // example.addPackage(glfw.pkg);
    // example.addPackage(.{
    //     .name = "crescent",
    //     .source = std.build.FileSource.relative("crescent/src/main.zig"),
    //     .dependencies = &.{gpu.pkg},
    // });
    // try gpu.link(b, example, .{});
    // example.install();

    const example = b.addExecutable("gpu-hello-triangle", "src/main.zig");
    example.setBuildMode(mode);
    example.setTarget(target);
    example.addPackage(gpu.pkg);
    example.addPackage(glfw.pkg);
    example.addPackage(.{
        .name = "crescent",
        .source = std.build.FileSource.relative("crescent/src/main.zig"),
        .dependencies = &.{gpu.pkg},
    });
    try glfw.link(b, example, .{});
    example.install();

    const example_run_cmd = example.run();
    example_run_cmd.step.dependOn(b.getInstallStep());
    const example_run_step = b.step("run-example", "Run the example");
    example_run_step.dependOn(&example_run_cmd.step);
}

const crescent = struct {
    pub const Options = struct {};
    pub fn link(b: *std.build.Builder, step: *std.build.LibExeObjStep, options: Options) !void {
        _ = options;
        _ = b;
        step.linkLibC(); // Make absolutely sure libc is linked cuz otherwise Vulkan will catch fire
    }
};
