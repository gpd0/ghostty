//! This file implements the "dev mode" interface for the terminal. This
//! includes state managements and rendering.
const DevMode = @This();

const std = @import("std");
const imgui = @import("imgui");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Atlas = @import("Atlas.zig");
const Window = @import("Window.zig");
const renderer = @import("renderer.zig");
const Config = @import("config.zig").Config;

/// If this is false, the rest of the terminal will be compiled without
/// dev mode support at all.
pub const enabled = true;

/// The global DevMode instance that can be used app-wide. Assume all functions
/// are NOT thread-safe unless otherwise noted.
pub var instance: DevMode = .{};

/// Whether to show the dev mode UI currently.
visible: bool = false,

/// Our app config
config: ?*const Config = null,

/// The window we're tracking.
window: ?*Window = null,

/// Update the state associated with the dev mode. This should generally
/// only be called paired with a render since it otherwise wastes CPU
/// cycles.
///
/// Note: renderers should call their implementation "newFrame" functions
/// prior to this.
pub fn update(self: *const DevMode) !void {
    // Buffer that can be used for stuff...
    var buf: [1024 * 32]u8 = undefined;

    imgui.newFrame();

    if (imgui.begin("dev mode", null, .{})) {
        defer imgui.end();

        if (self.config) |config| {
            if (imgui.collapsingHeader("Ghostty Configuration", null, .{})) {
                if (imgui.beginTable("config", 2, .{
                    .row_bg = true,
                    .borders_inner_h = true,
                    .borders_outer_h = true,
                    .borders_inner_v = true,
                    .borders_outer_v = true,
                })) {
                    // Setup headers
                    imgui.tableSetupColumn("Key", .{}, 0);
                    imgui.tableSetupColumn("Value", .{}, 0);
                    imgui.tableHeadersRow();

                    // Values
                    imgui.tableNextRow(0);
                    _ = imgui.tableNextColumn();
                    imgui.text("font-family");
                    _ = imgui.tableNextColumn();
                    imgui.text((try std.fmt.bufPrintZ(&buf, "{any}", .{config.@"font-family"})).ptr);
                    defer imgui.endTable();
                }

                if (imgui.treeNode("Raw Config (Advanced & Ugly)", .{})) {
                    defer imgui.treePop();

                    var raw = try std.fmt.bufPrintZ(&buf, "{}", .{config});
                    imgui.textWrapped("%s", raw.ptr);
                }
            }
        }

        if (self.window) |window| {
            if (imgui.collapsingHeader("Font Manager", null, .{})) {
                imgui.text("Glyphs: %d", window.font_group.glyphs.count());
                imgui.sameLine(0, -1);
                helpMarker("The number of glyphs loaded and rendered into a " ++
                    "font atlas currently.");

                const Renderer = @TypeOf(window.renderer);
                if (imgui.treeNode("Atlas: Greyscale", .{ .default_open = true })) {
                    defer imgui.treePop();
                    const atlas = &window.font_group.atlas_greyscale;
                    const tex = switch (Renderer) {
                        renderer.OpenGL => @intCast(usize, window.renderer.texture.id),
                        renderer.Metal => @ptrToInt(window.renderer.texture_greyscale.value),
                        else => @compileError("renderer unsupported, add it!"),
                    };
                    try self.atlasInfo(atlas, tex);
                }

                if (imgui.treeNode("Atlas: Color (Emoji)", .{ .default_open = true })) {
                    defer imgui.treePop();
                    const atlas = &window.font_group.atlas_color;
                    const tex = switch (Renderer) {
                        renderer.OpenGL => @intCast(usize, window.renderer.texture_color.id),
                        renderer.Metal => @ptrToInt(window.renderer.texture_color.value),
                        else => @compileError("renderer unsupported, add it!"),
                    };
                    try self.atlasInfo(atlas, tex);
                }
            }
        }
    }

    // Just demo for now
    imgui.showDemoWindow(null);
}

/// Render the scene and return the draw data. The caller must be imgui-aware
/// in order to render the draw data. This lets this file be renderer/backend
/// agnostic.
pub fn render(self: DevMode) !*imgui.DrawData {
    _ = self;
    imgui.render();
    return try imgui.DrawData.get();
}

/// Helper to render a tooltip.
fn helpMarker(desc: [:0]const u8) void {
    imgui.textDisabled("(?)");
    if (imgui.isItemHovered(.{})) {
        imgui.beginTooltip();
        defer imgui.endTooltip();
        imgui.pushTextWrapPos(imgui.getFontSize() * 35);
        defer imgui.popTextWrapPos();
        imgui.text(desc.ptr);
    }
}

fn atlasInfo(self: *const DevMode, atlas: *Atlas, tex: ?usize) !void {
    _ = self;

    imgui.text("Dimensions: %d x %d", atlas.size, atlas.size);
    imgui.sameLine(0, -1);
    helpMarker("The pixel dimensions of the atlas texture.");

    imgui.text("Size: %d KB", atlas.data.len >> 10);
    imgui.sameLine(0, -1);
    helpMarker("The byte size of the atlas texture.");

    var buf: [1024]u8 = undefined;
    imgui.text(
        "Format: %s (depth = %d)",
        (try std.fmt.bufPrintZ(&buf, "{}", .{atlas.format})).ptr,
        atlas.format.depth(),
    );
    imgui.sameLine(0, -1);
    helpMarker("The internal storage format of this atlas.");

    if (tex) |id| {
        imgui.c.igImage(
            @intToPtr(*anyopaque, id),
            .{
                .x = @intToFloat(f32, atlas.size),
                .y = @intToFloat(f32, atlas.size),
            },
            .{ .x = 0, .y = 0 },
            .{ .x = 1, .y = 1 },
            .{ .x = 1, .y = 1, .z = 1, .w = 1 },
            .{ .x = 0, .y = 0, .z = 0, .w = 0 },
        );
    }
}
