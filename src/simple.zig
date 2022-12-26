const std = @import("std");
const sample_utils = @import("sample_utils.zig");
const glfw = @import("glfw");
const gpu = @import("gpu");
const crescent = @import("crescent");

pub const GPUInterface = crescent.Interface;

pub fn main() !void {
    gpu.Impl.init();
    try glfw.init(.{});
    defer glfw.terminate();

    const window = try glfw.Window.create(640, 480, "crescent example", null, null, .{ .client_api = .no_api });
    defer window.destroy();

    const instance = gpu.createInstance(null) orelse return error.GpuInit;
    defer instance.release();
    const surface = sample_utils.createSurfaceForWindow(
        instance,
        window,
        comptime sample_utils.detectGLFWOptions(),
    );
    defer surface.release();

    var response: ?RequestAdapterResponse = null;
    instance.requestAdapter(&gpu.RequestAdapterOptions{
        .compatible_surface = surface,
        .power_preference = .undef,
        .force_fallback_adapter = false,
    }, &response, requestAdapterCallback);
    if (response.?.status != .success) {
        std.debug.print("failed to create GPU adapter: {s}\n", .{response.?.message.?});
        std.process.exit(1);
    }
    defer response.?.adapter.release();

    // Print which adapter we are using.
    var props: gpu.Adapter.Properties = undefined;
    response.?.adapter.getProperties(&props);
    std.debug.print("found {s} backend on {s} adapter: {s}, {s}\n", .{
        props.backend_type.name(),
        props.adapter_type.name(),
        props.name,
        props.driver_description,
    });

    // Create a device with default limits/features.
    const device = response.?.adapter.createDevice(null) orelse return error.DeviceInit;
    defer device.release();

    const vs = createSpirvShader(device, @embedFile("vertex.spv"));
    const fs = createSpirvShader(device, @embedFile("fragment.spv"));

    const layout = device.createPipelineLayout(&.{});

    const blend = gpu.BlendState{
        .color = .{
            .dst_factor = .one,
        },
        .alpha = .{
            .dst_factor = .one,
        },
    };
    const color_target = gpu.ColorTargetState{
        .format = .bgra8_unorm,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };
    const fragment = gpu.FragmentState.init(.{
        .module = fs,
        .entry_point = "main",
        .targets = &.{color_target},
    });
    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .fragment = &fragment,
        .layout = layout,
        .depth_stencil = null,
        .vertex = gpu.VertexState{
            .module = vs,
            .entry_point = "main",
        },
        .multisample = .{},
        .primitive = .{},
    };
    const pipeline = device.createRenderPipeline(&pipeline_descriptor);
    defer pipeline.release();

    layout.release();

    vs.release();
    fs.release();

    // Reconfigure the swap chain with the new framebuffer width/height, otherwise e.g. the Vulkan
    // device would be lost after a resize.
    window.setFramebufferSizeCallback((struct {
        fn callback(win: glfw.Window, width: u32, height: u32) void {
            const pl = win.getUserPointer(WindowData);
            pl.?.target_desc.width = width;
            pl.?.target_desc.height = height;
        }
    }).callback);
}

inline fn requestAdapterCallback(
    context: *?RequestAdapterResponse,
    status: gpu.RequestAdapterStatus,
    adapter: *gpu.Adapter,
    message: ?[*:0]const u8,
) void {
    context.* = RequestAdapterResponse{
        .status = status,
        .adapter = adapter,
        .message = message,
    };
}
const RequestAdapterResponse = struct {
    status: gpu.RequestAdapterStatus,
    adapter: *gpu.Adapter,
    message: ?[*:0]const u8,
};

fn createSpirvShader(device: *gpu.Device, comptime bytes: []const u8) *gpu.ShaderModule {
    const source = comptime std.mem.bytesAsSlice(u32, bytes);
    const spv = source[0..source.len].*;
    return device.createShaderModule(&.{ .next_in_chain = .{
        .spirv_descriptor = &.{
            .code_size = @sizeOf(u32) * spv.len,
            .code = &spv,
        },
    } });
}
