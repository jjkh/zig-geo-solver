const std = @import("std");
const zsdl = @import("zsdl");
const zsdl_ext = @import("zsdl_ext.zig");

const SUPER_SAMPLE_FACTOR = 2;

// to handle window events during drag/resize
// adapted from https://stackoverflow.com/a/50858339
fn filterEvent(userdata: ?*anyopaque, event: *zsdl.Event) callconv(.C) c_int {
    // IMPORTANT: Might be called from a different thread, see SDL_SetEventFilter docs
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

const Toolbar = struct {
    selected: Tool = .line,
    hovered: ?Tool = null,

    pos: zsdl.Point = .{ .x = 0, .y = 0 },

    const TOOL_SIZE = 30 * SUPER_SAMPLE_FACTOR;

    pub const Tool = enum {
        move,
        line,
        dimension,
        fix_point,

        pub fn shortName(self: Tool) [:0]const u8 {
            return switch (self) {
                .move => "mv",
                .line => "ln",
                .dimension => "dim",
                .fix_point => "fix",
            };
        }

        pub fn rect(self: Tool) zsdl.FRect {
            return .{
                .x = 0,
                .y = @as(f32, @floatFromInt(@intFromEnum(self))) * TOOL_SIZE,
                .w = TOOL_SIZE,
                .h = TOOL_SIZE,
            };
        }

        pub fn count() usize {
            return @typeInfo(Tool).Enum.fields.len;
        }
    };

    pub fn render(self: Toolbar, renderer: *zsdl.Renderer) !void {
        for (std.enums.values(Tool)) |tool| {
            if (self.hovered != tool)
                if (tool == self.selected)
                    try renderer.setDrawColorRGB(177, 203, 209)
                else
                    try renderer.setDrawColorRGB(232, 243, 248)
            else if (tool == self.selected)
                try renderer.setDrawColorRGB(164, 188, 194)
            else
                try renderer.setDrawColorRGB(219, 230, 236);

            const rect = tool.rect();
            try renderer.fillFRect(rect);
            try renderer.setDrawColorRGB(129, 168, 184);
            try renderer.drawFRect(.{ .x = rect.x, .y = rect.y, .w = rect.w, .h = rect.h + 1 });

            const label_surface = try Globals.ui_font.renderTextBlended(tool.shortName(), zsdl.Color{ .r = 0, .b = 0, .g = 0, .a = 0xFF });
            defer label_surface.free();
            const label_texture = try renderer.createTextureFromSurface(label_surface);
            defer label_texture.destroy();
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
                    .x = (TOOL_SIZE - label_size.w) / 2,
                    .y = (TOOL_SIZE - label_size.h) / 2 + rect.y,
                    .w = label_size.w,
                    .h = label_size.h,
                },
            );
        }
    }

    fn mouseEvent(self: *Toolbar, event_type: enum { up, down, move }, mouse_pos: zsdl.Point) bool {
        if (self.contains(mouse_pos)) |tool| {
            switch (event_type) {
                .up => if (self.selected != tool) {
                    self.selected = tool;
                    Globals.needs_repaint = true;
                },
                .move => {
                    if (self.hovered != tool) {
                        self.hovered = tool;
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

    fn contains(self: Toolbar, pt: zsdl.Point) ?Tool {
        if (pt.x < self.pos.x or pt.y < self.pos.y or pt.x > self.pos.x + TOOL_SIZE or pt.y > self.pos.y + TOOL_SIZE * @as(i32, @intCast(Tool.count())))
            return null;

        return @enumFromInt(@divFloor(pt.y - self.pos.y, TOOL_SIZE));
    }
};

fn toScreen(pt: zsdl.Point) zsdl.Point {
    const pan_dist = if (Globals.pan) |pan_info| pan_info.dist() else zsdl.Point{ .x = 0, .y = 0 };
    const origin = zsdl.FPoint{
        .x = @floatFromInt(Globals.origin_offset.x + pan_dist.x),
        .y = @floatFromInt(Globals.origin_offset.y + pan_dist.y),
    };
    return .{
        .x = @intFromFloat(@as(f32, @floatFromInt(pt.x)) / Globals.zoom_level + origin.x),
        .y = @intFromFloat(@as(f32, @floatFromInt(pt.y)) / Globals.zoom_level + origin.y),
    };
}

fn toScreenF(pt: zsdl.FPoint) zsdl.FPoint {
    const pan_dist = if (Globals.pan) |pan_info| pan_info.dist() else zsdl.Point{ .x = 0, .y = 0 };
    const origin = zsdl.FPoint{
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

fn toGridF(pt: zsdl.Point) zsdl.FPoint {
    const pan_dist = if (Globals.pan) |pan_info| pan_info.dist() else zsdl.Point{ .x = 0, .y = 0 };
    const origin = zsdl.FPoint{
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
        const start = Globals.drawing.points.items[self.start].toScreen();
        const end = if (self.end) |end_idx|
            Globals.drawing.points.items[end_idx].toScreen()
        else pt: {
            var mouse_x: i32 = undefined;
            var mouse_y: i32 = undefined;
            _ = zsdl.getMouseState(&mouse_x, &mouse_y);
            break :pt zsdl.FPoint{ .x = @floatFromInt(mouse_x * SUPER_SAMPLE_FACTOR), .y = @floatFromInt(mouse_y * SUPER_SAMPLE_FACTOR) };
        };

        const width = 2 * SUPER_SAMPLE_FACTOR;
        const color = zsdl.Color{ .r = 0x00, .g = 0x00, .b = 0x00, .a = 0xFF };
        const verts = self.vertices orelse blk: {
            const vec = .{ .x = end.x - start.x, .y = end.y - start.y };
            const vec_len = @sqrt(vec.x * vec.x + vec.y * vec.y);
            const vecn = .{ .x = vec.x / vec_len, .y = vec.y / vec_len };

            const norm1 = .{ .x = vecn.y * width / 2, .y = -vecn.x * width / 2 };
            const norm2 = .{ .x = -vecn.y * width / 2, .y = vecn.x * width / 2 };

            const vertices = [_]zsdl.Vertex{
                .{ .position = .{ .x = start.x + norm1.x, .y = start.y + norm1.y }, .color = color, .tex_coord = undefined },
                .{ .position = .{ .x = start.x + norm2.x, .y = start.y + norm2.y }, .color = color, .tex_coord = undefined },
                .{ .position = .{ .x = end.x + norm2.x, .y = end.y + norm2.y }, .color = color, .tex_coord = undefined },
                .{ .position = .{ .x = end.x + norm1.x, .y = end.y + norm1.y }, .color = color, .tex_coord = undefined },
            };
            // if (self.end != null)
            //     self.vertices = vertices;

            break :blk vertices;
        };
        const indices = .{ 0, 1, 2, 2, 3, 0 };
        try renderer.drawGeometry(null, &verts, &indices);
    }
};

const Point = struct {
    x: f32,
    y: f32,
    fixed: bool = false,

    pub fn fromGrid(pt: zsdl.FPoint) Point {
        return .{ .x = pt.x, .y = pt.y };
    }

    pub fn toScreen(self: Point) zsdl.FPoint {
        return toScreenF(.{ .x = self.x, .y = self.y });
    }
};

const Drawing = struct {
    allocator: std.mem.Allocator,

    // TODO: use zpool? does it makes sense here?
    points: std.ArrayListUnmanaged(Point) = .{},
    lines: std.ArrayListUnmanaged(Line) = .{},
    hovered_point_index: ?usize = null,

    dragged_point_index: ?usize = null,

    const point_radius = 3.5 * SUPER_SAMPLE_FACTOR;

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
        const outside_points = 8;
        const default_color = zsdl.Color{ .r = 0x70, .g = 0x70, .b = 0x70, .a = 0xFF };
        const hover_color = zsdl.Color{ .r = 0xFF, .g = 0x00, .b = 0x00, .a = 0xFF };
        const circle_indices = comptime x: {
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
            if (pt.fixed) {} else {
                const center = pt.toScreen();
                const color = if (self.hovered_point_index == i) hover_color else default_color;
                var circle_vertices: [outside_points + 1]zsdl.Vertex = undefined;
                circle_vertices[0] = .{ .position = center, .color = color, .tex_coord = undefined };
                for (0..outside_points) |j| {
                    circle_vertices[j + 1] = .{ .position = .{
                        .x = center.x + (point_radius * std.math.cos(@as(f32, @floatFromInt(j)) * tau / outside_points)),
                        .y = center.y + (point_radius * std.math.sin(@as(f32, @floatFromInt(j)) * tau / outside_points)),
                    }, .color = color, .tex_coord = undefined };
                }
                try renderer.drawGeometry(null, &circle_vertices, &circle_indices);
            }
        }
    }

    fn snappedPointIndex(self: Drawing, grid_pos: zsdl.FPoint) ?usize {
        const pos1 = toScreenF(grid_pos);
        const pow = std.math.pow;
        for (self.points.items, 0..) |pt, i| {
            const pos2 = pt.toScreen();
            const dist = @sqrt(pow(f32, pos1.x - pos2.x, 2) + pow(f32, pos1.y - pos2.y, 2));
            if (dist < point_radius) {
                std.log.debug("snapped to point {}: {any}", .{ i, pt });
                return i;
            }
        }
        return null;
    }

    pub fn mouseEvent(self: *Drawing, event_type: enum { up, down, move }, mouse_pos: zsdl.FPoint) !bool {
        // std.log.debug("mouseEvent: {}, {}", .{ event_type, mouse_pos });
        switch (event_type) {
            .down => {
                // TODO check tool
                Globals.needs_repaint = true;

                const point_under_cursor = self.snappedPointIndex(mouse_pos);
                switch (Globals.toolbar.selected) {
                    .line => {
                        const start_point = point_under_cursor orelse idx: {
                            try self.points.append(self.allocator, Point.fromGrid(mouse_pos));
                            const point_idx = self.points.items.len - 1;
                            std.log.debug("added point {}: {any}", .{ point_idx, self.points.items[point_idx] });
                            break :idx point_idx;
                        };
                        try self.lines.append(self.allocator, .{ .start = start_point });
                    },
                    .move => {
                        self.dragged_point_index = point_under_cursor;
                        if (self.dragged_point_index) |point_idx|
                            self.points.items[point_idx] = Point.fromGrid(mouse_pos);
                    },
                    else => {},
                }

                return true;
            },
            .move => {
                const new_hover_index = self.snappedPointIndex(mouse_pos);
                if (new_hover_index != self.hovered_point_index) {
                    self.hovered_point_index = new_hover_index;
                    Globals.needs_repaint = true;
                }
                switch (Globals.toolbar.selected) {
                    .line => {
                        if (self.lines.getLastOrNull()) |line| {
                            if (line.end == null) {
                                Globals.needs_repaint = true;
                                return true;
                            }
                        }
                    },
                    .move => {
                        if (self.dragged_point_index) |point_idx|
                            self.points.items[point_idx] = Point.fromGrid(mouse_pos);
                        Globals.needs_repaint = true;
                        return true;
                    },
                    else => {},
                }
                return false;
            },
            .up => {
                if (self.lines.items.len == 0)
                    return false;

                var line: *Line = &self.lines.items[self.lines.items.len - 1];
                switch (Globals.toolbar.selected) {
                    .line => {
                        if (line.end == null) {
                            Globals.needs_repaint = true;

                            const end_idx = self.snappedPointIndex(mouse_pos) orelse idx: {
                                try self.points.append(self.allocator, Point.fromGrid(mouse_pos));
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
                    .move => {
                        if (self.dragged_point_index) |point_idx| {
                            Globals.needs_repaint = true;
                            self.points.items[point_idx] = Point.fromGrid(mouse_pos);
                            // TODO: join dropped point to point underneath
                            self.dragged_point_index = null;
                            return true;
                        }
                    },
                    else => {},
                }
                return false;
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
    var current_texture: *zsdl.Texture = undefined;
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
    _ = zsdl.setHint("SDL_WINDOWS_DPI_SCALING", "1");

    try zsdl.init(.{ .events = true, .video = true });
    defer zsdl.quit();

    try zsdl.ttf.init();
    defer zsdl.ttf.quit();

    var window = try zsdl.Window.create(
        "Geomtric Constraint Solver",
        zsdl.Window.pos_centered,
        zsdl.Window.pos_centered,
        800,
        600,
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
        Globals.x_scale = (@as(f32, @floatFromInt(rs.w)) / @as(f32, @floatFromInt(ww)));
        Globals.y_scale = (@as(f32, @floatFromInt(rs.h)) / @as(f32, @floatFromInt(wh)));
        std.log.info("x_scale: {}, y_scale: {}", .{ Globals.x_scale, Globals.y_scale });
        try Globals.renderer.setScale(Globals.x_scale, Globals.y_scale);
    }
    const screen_size = try screenSize(Globals.renderer);
    Globals.origin_offset = .{ .x = @divTrunc(screen_size.x, 2), .y = @divTrunc(screen_size.y, 2) };

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) std.log.warn("gpa problems!", .{});
    Globals.allocator = gpa.allocator();

    {
        var base_path = zsdl.getBasePath().?;
        defer zsdl_ext.free(base_path.ptr);
        const font_path = try std.mem.concatWithSentinel(Globals.allocator, u8, &[_][]const u8{ base_path, "Roboto-Regular.ttf" }, 0);
        defer Globals.allocator.free(font_path);
        Globals.ui_font = try zsdl.ttf.Font.open(font_path, @intFromFloat(14 * SUPER_SAMPLE_FACTOR * Globals.x_scale));
    }
    defer Globals.ui_font.close();

    // handle ONLY window resize
    zsdl_ext.setEventFilter(filterEvent, window);

    Globals.drawing = Drawing.init(Globals.allocator);
    defer Globals.drawing.deinit();

    mainLoop: while (true) {
        const frame_start = zsdl.getPerformanceCounter();
        const event = try zsdl_ext.waitEvent();
        switch (event.type) {
            .quit => break :mainLoop,
            // TODO make nicer
            .mousebuttonup => blk: {
                const mouse_pos = .{ .x = event.button.x * SUPER_SAMPLE_FACTOR, .y = event.button.y * SUPER_SAMPLE_FACTOR };

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
                const mouse_pos = .{ .x = event.button.x * SUPER_SAMPLE_FACTOR, .y = event.button.y * SUPER_SAMPLE_FACTOR };

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
                const mouse_pos = .{ .x = event.motion.x * SUPER_SAMPLE_FACTOR, .y = event.motion.y * SUPER_SAMPLE_FACTOR };

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

        const output_size = try renderer.getOutputSize();
        if (output_size.w == 0 or output_size.h == 0) return;

        Globals.current_texture = try renderer.createTexture(.rgba8888, .target, output_size.w * SUPER_SAMPLE_FACTOR, output_size.h * SUPER_SAMPLE_FACTOR);
        defer {
            Globals.current_texture.destroy();
            Globals.current_texture = undefined;
        }
        try renderer.setTarget(Globals.current_texture);

        try renderAxes(renderer);
        try Globals.drawing.render(renderer);
        try Globals.toolbar.render(renderer);

        try renderer.setTarget(null);

        // WARNING: calling into SDL_ttf resets this!
        _ = zsdl.setHint("SDL_RENDER_SCALE_QUALITY", "best");
        try renderer.copy(Globals.current_texture, null, &.{ .x = 0, .y = 0, .w = output_size.w, .h = output_size.h });

        renderer.present();
    }
}

fn screenSize(renderer: *zsdl.Renderer) !zsdl.Point {
    const unscaled_size = try renderer.getOutputSize();
    return .{
        .x = @intFromFloat(@as(f32, @floatFromInt(unscaled_size.w * SUPER_SAMPLE_FACTOR)) / Globals.x_scale),
        .y = @intFromFloat(@as(f32, @floatFromInt(unscaled_size.h * SUPER_SAMPLE_FACTOR)) / Globals.y_scale),
    };
}

fn renderAxes(renderer: *zsdl.Renderer) !void {
    // colours from https://www.colourlovers.com/palette/490780/The_First_Raindrop
    try renderer.setDrawColorRGB(232, 243, 248);
    try renderer.clear();

    const size = try screenSize(renderer);
    const origin = getOrigin();

    // minor axes
    const minor_axis_step: i32 = @intFromFloat(40 * SUPER_SAMPLE_FACTOR / Globals.zoom_level);
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
