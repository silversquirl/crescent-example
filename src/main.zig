const std = @import("std");
const sample_utils = @import("sample_utils.zig");
const glfw = @import("glfw");
const gpu = @import("gpu");
const crescent = @import("crescent");

pub const GPUInterface = crescent.Interface;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    gpu.Impl.init();
    const setup = try sample_utils.setup(allocator);
    defer {
        setup.surface.release();
        setup.device.release();
        setup.adapter.release();
        setup.instance.release();
        setup.window.destroy();
    }
    const framebuffer_size = try setup.window.getFramebufferSize();

    var window_data: WindowData = .{
        .surface = setup.surface,
        .swap_chain = null,
        .swap_chain_format = undefined,
        .current_desc = undefined,
        .target_desc = undefined,
    };
    setup.window.setUserPointer(&window_data);
    defer if (window_data.swap_chain) |chain| chain.release();

    window_data.swap_chain_format = .bgra8_unorm;
    const descriptor = gpu.SwapChain.Descriptor{
        .label = "basic swap chain",
        .usage = .{ .render_attachment = true },
        .format = window_data.swap_chain_format,
        .width = framebuffer_size.width,
        .height = framebuffer_size.height,
        .present_mode = .mailbox,
    };

    window_data.current_desc = descriptor;
    window_data.target_desc = descriptor;

    const vs_module = createSpirvShader(setup.device, @embedFile("vertex.spv"));
    const fs_module = createSpirvShader(setup.device, @embedFile("fragment.spv"));

    // Fragment state
    const blend = gpu.BlendState{
        .color = .{
            .dst_factor = .one,
        },
        .alpha = .{
            .dst_factor = .one,
        },
    };
    const color_target = gpu.ColorTargetState{
        .format = window_data.swap_chain_format,
        .blend = &blend,
        .write_mask = gpu.ColorWriteMaskFlags.all,
    };
    const fragment = gpu.FragmentState.init(.{
        .module = fs_module,
        .entry_point = "main",
        .targets = &.{color_target},
    });
    const layout = setup.device.createPipelineLayout(&.{});
    const pipeline_descriptor = gpu.RenderPipeline.Descriptor{
        .fragment = &fragment,
        .layout = layout,
        .depth_stencil = null,
        .vertex = gpu.VertexState{
            .module = vs_module,
            .entry_point = "main",
        },
        .multisample = .{},
        .primitive = .{},
    };
    const pipeline = setup.device.createRenderPipeline(&pipeline_descriptor);
    defer pipeline.release();

    layout.release();
    vs_module.release();
    fs_module.release();

    // Reconfigure the swap chain with the new framebuffer width/height, otherwise e.g. the Vulkan
    // device would be lost after a resize.
    setup.window.setFramebufferSizeCallback((struct {
        fn callback(window: glfw.Window, width: u32, height: u32) void {
            const pl = window.getUserPointer(WindowData);
            pl.?.target_desc.width = width;
            pl.?.target_desc.height = height;
        }
    }).callback);

    const queue = setup.device.getQueue();
    while (!setup.window.shouldClose()) {
        try frame(.{
            .window = setup.window,
            .device = setup.device,
            .pipeline = pipeline,
            .queue = queue,
        });
        //std.time.sleep(16 * std.time.ns_per_ms);
        // break; // TODO
    }

    std.debug.print("exiting...\n", .{});
}

const WindowData = struct {
    surface: ?*gpu.Surface,
    swap_chain: ?*gpu.SwapChain,
    swap_chain_format: gpu.Texture.Format,
    current_desc: gpu.SwapChain.Descriptor,
    target_desc: gpu.SwapChain.Descriptor,
};

const FrameParams = struct {
    window: glfw.Window,
    device: *gpu.Device,
    pipeline: *gpu.RenderPipeline,
    queue: *gpu.Queue,
};

fn frame(params: FrameParams) !void {
    const pool = try sample_utils.AutoReleasePool.init();
    defer sample_utils.AutoReleasePool.release(pool);

    try glfw.pollEvents();
    const pl = params.window.getUserPointer(WindowData).?;
    if (pl.swap_chain == null or !std.meta.eql(pl.current_desc, pl.target_desc)) {
        pl.swap_chain = params.device.createSwapChain(pl.surface, &pl.target_desc);
        pl.current_desc = pl.target_desc;
    }

    const back_buffer_view = pl.swap_chain.?.getCurrentTextureView();
    const color_attachment = gpu.RenderPassColorAttachment{
        .view = back_buffer_view,
        .resolve_target = null,
        .clear_value = std.mem.zeroes(gpu.Color),
        .load_op = .clear,
        .store_op = .store,
    };

    const encoder = params.device.createCommandEncoder(null);
    const render_pass_info = gpu.RenderPassDescriptor.init(.{
        .color_attachments = &.{color_attachment},
    });
    const pass = encoder.beginRenderPass(&render_pass_info);
    pass.setPipeline(params.pipeline);
    pass.draw(3, 1, 0, 0);
    pass.end();
    pass.release();

    var command = encoder.finish(null);
    encoder.release();

    var bufs = [_]*const gpu.CommandBuffer{command};
    params.queue.submit(&bufs);
    command.release();
    pl.swap_chain.?.present();
    back_buffer_view.release();
}

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
