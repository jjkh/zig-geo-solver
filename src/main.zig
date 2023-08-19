const std = @import("std");
const zsdl = @import("zsdl");
const zsdl_ext = @import("zsdl_ext.zig");

// to handle window events during drag/resize
// adapted from https://stackoverflow.com/a/50858339
fn filterEvent(userdata: ?*anyopaque, event: *zsdl.Event) callconv(.C) c_int {
    //IMPORTANT: Might be called from a different thread, see SDL_SetEventFilter docs
    if (event.type == .windowevent and event.window.event == .resized) {
        const frame_start = zsdl.getPerformanceCounter();

        Globals.needs_repaint = true;
        draw(Globals.renderer) catch |err| std.log.err("failed draw during filterEvent! err={}", .{err});

        const elapsed: f32 = @as(f32, @floatFromInt(zsdl.getPerformanceCounter() - frame_start)) /
            @as(f32, @floatFromInt(zsdl.getPerformanceFrequency()));
        var title_buf: [64]u8 = undefined;
        const title = std.fmt.bufPrintZ(&title_buf, "Geomtric Constraint Solver ({d:.1} FPS)", .{1.0 / elapsed}) catch unreachable;

        const window: *zsdl.Window = @ptrCast(userdata.?);
        window.setTitle(title);

        // return 0 so we don't handle the event in mainloop
        return 0;
    }
    return 1;
}

fn logButtonPress(tool: Toolbar.Tool) void {
    std.log.info("tool '{s}' selected", .{tool.name});
}

const Toolbar = struct {
    tools: std.BoundedArray(Tool, 10) = .{},
    selected: u16 = 1,
    hovered: ?u16 = null,

    pos: zsdl.Point = .{ .x = 0, .y = 0 },
    tool_size: f16 = 30,

    // TODO: make tagged union
    pub const Tool = struct {
        name: [:0]const u8,
        action: ?*const fn (@This()) void = null,
    };

    pub fn render(self: Toolbar, renderer: *zsdl.Renderer) !void {
        for (self.tools.slice(), 0..) |tool, i| {
            const rect = zsdl.FRect{
                .x = 0,
                .y = @as(f32, @floatFromInt(i)) * self.tool_size,
                .w = self.tool_size,
                .h = self.tool_size,
            };

            if (self.hovered != null and i == self.hovered.?)
                if (i == self.selected)
                    try renderer.setDrawColorRGB(177, 203, 209)
                else
                    try renderer.setDrawColorRGB(232, 243, 248)
            else if (i == self.selected)
                try renderer.setDrawColorRGB(164, 188, 194)
            else
                try renderer.setDrawColorRGB(219, 230, 236);
            try renderer.fillFRect(rect);
            try renderer.setDrawColorRGB(129, 168, 184);
            try renderer.drawFRect(.{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h + 1 });

            const label_surface = try Globals.ui_font.renderTextBlended(tool.name, zsdl.Color.black);
            const label_texture = try renderer.createTextureFromSurface(label_surface);
            const label_size = size: {
                var label_width_px: c_int = undefined;
                var label_height_px: c_int = undefined;
                try label_texture.query(null, null, &label_width_px, &label_height_px);
                break :size zsdl.FRect{
                    .x = undefined,
                    .y = undefined,
                    .w = @as(f32, @floatFromInt(label_width_px)) / Globals.x_scale,
                    .h = @as(f32, @floatFromInt(label_height_px)) / Globals.y_scale,
                };
            };

            try renderer.copyF(
                label_texture,
                null,
                &zsdl.FRect{
                    .x = (self.tool_size - label_size.w) / 2,
                    .y = (self.tool_size - label_size.h) / 2 + rect.y,
                    .w = label_size.w,
                    .h = label_size.h,
                },
            );
        }
    }

    fn mouseEvent(self: *Toolbar, event_type: enum { up, down, move }, mouse_pos: zsdl.Point) bool {
        if (self.contains(mouse_pos)) |tool_index| {
            switch (event_type) {
                .up => if (self.selected != tool_index) {
                    self.selected = tool_index;
                    const button = self.tools.get(tool_index);
                    if (button.action != null) button.action.?(button);

                    Globals.needs_repaint = true;
                },
                .move => {
                    if (self.hovered != tool_index) {
                        self.hovered = tool_index;
                        Globals.needs_repaint = true;
                    }
                    return false;
                },
                else => {},
            }
            return true;
        } else {
            if (self.hovered != null) {
                self.hovered = null;
                Globals.needs_repaint = true;
            }
            return false;
        }
    }

    fn contains(self: Toolbar, pt: zsdl.Point) ?u16 {
        const tool_size_int: i32 = @intFromFloat(self.tool_size);
        if (pt.x < self.pos.x or pt.y < self.pos.y or pt.x > self.pos.x + tool_size_int or pt.y > self.pos.y + tool_size_int * self.tools.len)
            return null;

        return @intCast(@divFloor(pt.y - self.pos.y, tool_size_int));
    }
};

fn toScreen(pt: zsdl.Point) zsdl.Point {
    const pan_dist = if (Globals.pan) |pan_info| pan_info.dist() else zsdl.Point{ .x = 0, .y = 0 };
    const origin = zsdl.PointF{
        .x = @floatFromInt(Globals.origin_offset.x + pan_dist.x),
        .y = @floatFromInt(Globals.origin_offset.y + pan_dist.y),
    };
    return .{
        .x = @intFromFloat(@as(f32, @floatFromInt(pt.x)) / Globals.zoom_level + origin.x),
        .y = @intFromFloat(@as(f32, @floatFromInt(pt.y)) / Globals.zoom_level + origin.y),
    };
}

fn toScreenF(pt: zsdl.PointF) zsdl.PointF {
    const pan_dist = if (Globals.pan) |pan_info| pan_info.dist() else zsdl.Point{ .x = 0, .y = 0 };
    const origin = zsdl.PointF{
        .x = @floatFromInt(Globals.origin_offset.x + pan_dist.x),
        .y = @floatFromInt(Globals.origin_offset.y + pan_dist.y),
    };
    return .{
        .x = pt.x / Globals.zoom_level + origin.x,
        .y = pt.y / Globals.zoom_level + origin.y,
    };
}

fn getOrigin() zsdl.Point {
    return toScreen(.{ .x = 0, .y = 0 });
}

fn toGridF(pt: zsdl.Point) zsdl.PointF {
    const pan_dist = if (Globals.pan) |pan_info| pan_info.dist() else zsdl.Point{ .x = 0, .y = 0 };
    const origin = zsdl.PointF{
        .x = @floatFromInt(Globals.origin_offset.x + pan_dist.x),
        .y = @floatFromInt(Globals.origin_offset.y + pan_dist.y),
    };
    return .{
        .x = (@as(f32, @floatFromInt(pt.x)) - origin.x) * Globals.zoom_level,
        .y = (@as(f32, @floatFromInt(pt.y)) - origin.y) * Globals.zoom_level,
    };
}

// TODO: give units and whatever
const Line = struct {
    start: usize,
    end: ?usize = null,
    vertices: ?[4]zsdl.Vertex = null,

    fn render(self: *Line, renderer: *zsdl.Renderer) !void {
        const start = toScreenF(Globals.drawing.points.items[self.start]);
        const end = if (self.end) |end_idx|
            toScreenF(Globals.drawing.points.items[end_idx])
        else pt: {
            var mouse_x: i32 = undefined;
            var mouse_y: i32 = undefined;
            _ = zsdl.getMouseState(&mouse_x, &mouse_y);
            break :pt zsdl.PointF{ .x = @floatFromInt(mouse_x), .y = @floatFromInt(mouse_y) };
        };

        const width = 2.5;
        const color = zsdl.Color.black;
        const verts = self.vertices orelse blk: {
            const vec = .{ .x = end.x - start.x, .y = end.y - start.y };
            const vec_len = @sqrt(vec.x * vec.x + vec.y * vec.y);
            const vecn = .{ .x = vec.x / vec_len, .y = vec.y / vec_len };

            const norm1 = .{ .x = vecn.y * width / 2, .y = -vecn.x * width / 2 };
            const norm2 = .{ .x = -vecn.y * width / 2, .y = vecn.x * width / 2 };

            const vertices = [_]zsdl.Vertex{
                .{ .position = .{ .x = start.x + norm1.x, .y = start.y + norm1.y }, .color = color },
                .{ .position = .{ .x = start.x + norm2.x, .y = start.y + norm2.y }, .color = color },
                .{ .position = .{ .x = end.x + norm2.x, .y = end.y + norm2.y }, .color = color },
                .{ .position = .{ .x = end.x + norm1.x, .y = end.y + norm1.y }, .color = color },
            };
            // if (self.end != null)
            //     self.vertices = vertices;

            break :blk vertices;
        };
        const indices = .{ 0, 1, 2, 2, 3, 0 };
        try renderer.drawGeometry(null, &verts, &indices);
    }
};

const Drawing = struct {
    allocator: std.mem.Allocator,

    // TODO: use zpool? does it makes sense here?
    points: std.ArrayListUnmanaged(zsdl.PointF) = .{},
    lines: std.ArrayListUnmanaged(Line) = .{},
    hovered_point_index: ?usize = null,

    const point_radius = 3;

    pub fn init(allocator: std.mem.Allocator) Drawing {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Drawing) void {
        self.lines.deinit(self.allocator);
        self.points.deinit(self.allocator);
    }

    pub fn render(self: Drawing, renderer: *zsdl.Renderer) !void {
        for (self.lines.items) |*line|
            try line.render(renderer);

        // TODO render this to texture and reuse
        const tau = std.math.tau;
        const outside_points = 6;
        const default_color = zsdl.Color.rgb(100, 100, 100);
        const hover_color = zsdl.Color.red;
        const indices = comptime x: {
            var idxs: [outside_points * 3]u32 = undefined;
            for (0..outside_points - 1) |i| {
                idxs[i * 3] = 0;
                idxs[i * 3 + 1] = i + 1;
                idxs[i * 3 + 2] = i + 2;
            }
            idxs[(outside_points - 1) * 3] = 0;
            idxs[(outside_points - 1) * 3 + 1] = outside_points;
            idxs[(outside_points - 1) * 3 + 2] = 1;

            break :x idxs;
        };
        for (self.points.items, 0..) |pt, i| {
            const center = toScreenF(pt);
            const color = if (self.hovered_point_index == i) hover_color else default_color;
            var vertices: [outside_points + 1]zsdl.Vertex = undefined;
            vertices[0] = .{ .position = center, .color = color };
            for (0..outside_points) |j| {
                vertices[j + 1] = .{ .position = .{
                    .x = center.x + (point_radius * std.math.cos(@as(f32, @floatFromInt(j)) * tau / outside_points)),
                    .y = center.y + (point_radius * std.math.sin(@as(f32, @floatFromInt(j)) * tau / outside_points)),
                }, .color = color };
            }
            try renderer.drawGeometry(null, &vertices, &indices);
        }
    }

    fn snappedPointIndex(self: Drawing, screen_pos: zsdl.PointF) ?usize {
        const pow = std.math.pow;
        for (self.points.items, 0..) |pt, i| {
            const dist = @sqrt(pow(f32, pt.x - screen_pos.x, 2) + pow(f32, pt.y - screen_pos.y, 2));
            if (dist < point_radius) {
                std.log.debug("snapped to point {}: {any}", .{ i, pt });
                return i;
            }
        }
        return null;
    }

    pub fn mouseEvent(self: *Drawing, event_type: enum { up, down, move }, mouse_pos: zsdl.PointF) !bool {
        switch (event_type) {
            .down => {
                // TODO check tool
                Globals.needs_repaint = true;

                const start_idx = self.snappedPointIndex(mouse_pos) orelse idx: {
                    try self.points.append(self.allocator, mouse_pos);
                    const point_idx = self.points.items.len - 1;
                    std.log.debug("added point {}: {any}", .{ point_idx, self.points.items[point_idx] });
                    break :idx point_idx;
                };
                try self.lines.append(self.allocator, .{ .start = start_idx });

                return true;
            },
            .move => {
                const new_hover_index = self.snappedPointIndex(mouse_pos);
                if (new_hover_index != self.hovered_point_index) {
                    self.hovered_point_index = new_hover_index;
                    Globals.needs_repaint = true;
                }

                if (self.lines.getLastOrNull()) |line| {
                    if (line.end == null) {
                        Globals.needs_repaint = true;
                        return true;
                    }
                }
                return false;
            },
            .up => {
                if (self.lines.items.len == 0)
                    return false;

                var line: *Line = &self.lines.items[self.lines.items.len - 1];
                if (line.end == null) {
                    Globals.needs_repaint = true;

                    // TODO handle snapping
                    const end_idx = self.snappedPointIndex(mouse_pos) orelse idx: {
                        try self.points.append(self.allocator, mouse_pos);
                        const point_idx = self.points.items.len - 1;
                        std.log.debug("added point {}: {any}", .{ point_idx, self.points.items[point_idx] });
                        break :idx point_idx;
                    };
                    line.end = end_idx;

                    const duplicate = for (self.lines.items[0 .. self.lines.items.len - 1]) |other_line| {
                        if (line.start == other_line.start and line.end == other_line.end)
                            break true;
                        if (line.start == other_line.end and line.end == other_line.start)
                            break true;
                    } else false;

                    if (duplicate) {
                        std.log.debug("duplicate line, removing", .{});
                        _ = self.lines.pop();
                    } else if (line.end == line.start) {
                        std.log.debug("zero-length line, removing", .{});
                        _ = self.lines.pop();
                        for (self.lines.items) |other_line| {
                            if (other_line.start == end_idx or other_line.end == end_idx)
                                break;
                        } else _ = self.points.pop();
                    } else {
                        std.log.debug("line {}: {any}", .{ self.lines.items.len - 1, self.lines.getLast() });
                    }
                    return true;
                }
            },
        }
        return false;
    }
};

const PanInfo = struct {
    start: zsdl.Point,
    current: zsdl.Point,

    pub fn init(start: zsdl.Point) PanInfo {
        return .{
            .start = start,
            .current = start,
        };
    }

    pub fn dist(self: PanInfo) zsdl.Point {
        return .{
            .x = self.current.x - self.start.x,
            .y = self.current.y - self.start.y,
        };
    }
};

const Globals = struct {
    var toolbar = Toolbar{};
    var drawing: Drawing = undefined;

    var allocator: std.mem.Allocator = undefined;
    var renderer: *zsdl.Renderer = undefined;
    var ui_font: *zsdl.ttf.Font = undefined;

    var x_scale: f32 = 1;
    var y_scale: f32 = 1;
    var needs_repaint: bool = true;

    var shift_held: bool = false;
    var pan: ?PanInfo = null;
    var current_pan: ?zsdl.Point = null;

    var zoom_level: f32 = 1;
    var origin_offset: zsdl.Point = undefined; // in scree
};

pub fn main() !void {
    try zsdl.init(.{ .events = true, .video = true });
    defer zsdl.quit();

    try zsdl.ttf.init();
    defer zsdl.ttf.quit();

    var window = try zsdl.Window.create(
        "Geomtric Constraint Solver",
        zsdl.Window.pos_centered,
        zsdl.Window.pos_centered,
        640,
        480,
        .{ .resizable = true, .allow_highdpi = true },
    );
    defer window.destroy();

    Globals.renderer = try zsdl.Renderer.create(window, null, .{});
    defer Globals.renderer.destroy();

    {
        var ww: i32 = undefined;
        var wh: i32 = undefined;
        try window.getSize(&ww, &wh);
        var rs = try Globals.renderer.getOutputSize();
        Globals.x_scale = @as(f32, @floatFromInt(rs.w)) / @as(f32, @floatFromInt(ww));
        Globals.y_scale = @as(f32, @floatFromInt(rs.w)) / @as(f32, @floatFromInt(ww));
        try Globals.renderer.setScale(Globals.x_scale, Globals.y_scale);
    }
    const screen_size = try screenSize(Globals.renderer);
    Globals.origin_offset = .{ .x = @divTrunc(screen_size.x, 2), .y = @divTrunc(screen_size.y, 2) };

    Globals.toolbar.tools.appendSliceAssumeCapacity(&[_]Toolbar.Tool{
        .{ .name = "mv", .action = logButtonPress },
        .{ .name = "ln", .action = logButtonPress },
        .{ .name = "dm", .action = logButtonPress },
        .{ .name = "fx", .action = logButtonPress },
    });

    Globals.ui_font = try zsdl.ttf.Font.open("Roboto-Regular.ttf", 14 * @as(i32, @intFromFloat(Globals.x_scale)));

    // handle ONLY window resize
    zsdl_ext.setEventFilter(filterEvent, window);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) std.log.warn("gpa problems!", .{});
    Globals.allocator = gpa.allocator();

    Globals.drawing = Drawing.init(Globals.allocator);
    defer Globals.drawing.deinit();

    // FIXME: doesn't seem to make a difference
    _ = zsdl.setHint("SDL_HINT_RENDER_SCALE_QUALITY", "2");

    mainLoop: while (true) {
        const frame_start = zsdl.getPerformanceCounter();
        const event = try zsdl_ext.waitEvent();
        switch (event.type) {
            .quit => break :mainLoop,
            // TODO make nicer
            .mousebuttonup => blk: {
                const mouse_pos = .{ .x = event.button.x, .y = event.button.y };

                if (Globals.pan) |pan_info| {
                    const pan_dist = pan_info.dist();
                    Globals.origin_offset.x += pan_dist.x;
                    Globals.origin_offset.y += pan_dist.y;
                    Globals.pan = null;
                    if (!Globals.shift_held)
                        (try zsdl_ext.Cursor.current()).destroy();
                    break :blk;
                }

                if (try Globals.drawing.mouseEvent(.up, toGridF(mouse_pos)))
                    break :blk;

                if (Globals.toolbar.mouseEvent(.up, mouse_pos))
                    break :blk;
            },
            .mousebuttondown => blk: {
                const mouse_pos = .{ .x = event.button.x, .y = event.button.y };

                if (Globals.shift_held) {
                    Globals.pan = PanInfo.init(mouse_pos);
                    break :blk;
                }

                if (Globals.toolbar.mouseEvent(.down, mouse_pos))
                    break :blk;

                if (try Globals.drawing.mouseEvent(.down, toGridF(mouse_pos)))
                    break :blk;
            },
            .mousemotion => blk: {
                const mouse_pos = .{ .x = event.motion.x, .y = event.motion.y };

                if (Globals.pan) |*pan_info| {
                    pan_info.current = mouse_pos;
                    Globals.needs_repaint = true;
                    break :blk;
                }

                if (try Globals.drawing.mouseEvent(.move, toGridF(mouse_pos)))
                    break :blk;

                if (Globals.toolbar.mouseEvent(.move, mouse_pos))
                    break :blk;
            },
            .mousewheel => {
                Globals.zoom_level = std.math.clamp(Globals.zoom_level + event.wheel.preciseY / 20, 0.1, 10);
                Globals.needs_repaint = true;
            },
            .windowevent => Globals.needs_repaint = true,
            .keydown => {
                if (event.key.keysym.sym == .lshift and (zsdl.getMouseState(null, null) & 0x01) == 0) {
                    (try zsdl_ext.Cursor.current()).destroy();
                    const move_cursor = try zsdl_ext.Cursor.createSystem(.hand);
                    try move_cursor.set();
                    Globals.shift_held = true;
                }
            },
            .keyup => {
                if (event.key.keysym.sym == .lshift) {
                    if (Globals.pan == null) (try zsdl_ext.Cursor.current()).destroy();
                    Globals.shift_held = false;
                }
            },
            else => {},
        }

        try draw(Globals.renderer);

        const elapsed: f32 = @as(f32, @floatFromInt(zsdl.getPerformanceCounter() - frame_start)) /
            @as(f32, @floatFromInt(zsdl.getPerformanceFrequency()));
        var title_buf: [64]u8 = undefined;
        const title = try std.fmt.bufPrintZ(&title_buf, "Geomtric Constraint Solver ({d:.1} FPS)", .{1.0 / elapsed});
        window.setTitle(title);
    }
}

fn draw(renderer: *zsdl.Renderer) !void {
    if (Globals.needs_repaint) {
        Globals.needs_repaint = false;

        try renderAxes(renderer);
        try Globals.drawing.render(renderer);
        try Globals.toolbar.render(renderer);

        renderer.present();
    }
}

fn screenSize(renderer: *zsdl.Renderer) !zsdl.Point {
    const unscaledSize = try renderer.getOutputSize();
    return .{
        .x = @divTrunc(unscaledSize.w, @as(i32, @intFromFloat(Globals.x_scale))),
        .y = @divTrunc(unscaledSize.h, @as(i32, @intFromFloat(Globals.y_scale))),
    };
}

fn renderAxes(renderer: *zsdl.Renderer) !void {
    // colours from https://www.colourlovers.com/palette/490780/The_First_Raindrop
    try renderer.setDrawColorRGB(232, 243, 248);
    try renderer.clear();

    const size = try screenSize(renderer);
    const origin = getOrigin();

    // minor axes
    const minor_axis_step: i32 = @intFromFloat(40 / Globals.zoom_level);
    try renderer.setDrawColorRGB(194, 203, 206);
    {
        var y: i32 = origin.y - minor_axis_step;
        while (y >= 0) : (y -= minor_axis_step)
            try renderer.drawLine(0, y, size.x, y);
        y = origin.y + minor_axis_step;
        while (y <= size.y) : (y += minor_axis_step)
            try renderer.drawLine(0, y, size.x, y);
    }
    {
        var x: i32 = origin.x - minor_axis_step;
        while (x >= 0) : (x -= minor_axis_step)
            try renderer.drawLine(x, 0, x, size.y);
        x = origin.x + minor_axis_step;
        while (x <= size.x) : (x += minor_axis_step)
            try renderer.drawLine(x, 0, x, size.y);
    }

    // main axes
    try renderer.setDrawColorRGB(129, 168, 184);
    try renderer.drawLine(0, origin.y, size.x, origin.y);
    try renderer.drawLine(origin.x, 0, origin.x, size.y);
}
