const std = @import("std");
const zsdl = @import("zsdl");

// missing from zsdl
pub fn waitEvent() !zsdl.Event {
    var event: zsdl.Event = undefined;
    if (SDL_WaitEvent(&event) == 0)
        return error.SdlError;
    return event;
}
extern fn SDL_WaitEvent(event: ?*zsdl.Event) i32;

// to handle window events during drag/resize
// adapted from https://stackoverflow.com/a/50858339
fn filterEvent(userdata: *anyopaque, event: *zsdl.Event) callconv(.C) c_int {
    //IMPORTANT: Might be called from a different thread, see SDL_SetEventFilter docs
    if (event.type == .windowevent and event.window.event == .resized) {
        const frame_start = zsdl.getPerformanceCounter();

        Globals.needs_repaint = true;
        draw(Globals.renderer) catch |err| std.log.err("failed draw during filterEvent! err={}", .{err});

        const elapsed: f32 = @as(f32, @floatFromInt(zsdl.getPerformanceCounter() - frame_start)) /
            @as(f32, @floatFromInt(zsdl.getPerformanceFrequency()));
        var title_buf: [64]u8 = undefined;
        const title = std.fmt.bufPrintZ(&title_buf, "Geomtric Constraint Solver ({d:.1} FPS)", .{1.0 / elapsed}) catch unreachable;

        const window: *zsdl.Window = @ptrCast(userdata);
        window.setTitle(title);

        // return 0 so we don't handle the event in mainloop
        return 0;
    }
    return 1;
}
extern fn SDL_SetEventFilter(filter: *const fn (*anyopaque, *zsdl.Event) callconv(.C) c_int, userdata: *anyopaque) callconv(.C) void;

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

// TODO: give units and whatever
const Line = struct {
    start: usize,
    end: ?usize = null,

    fn render(self: Line, renderer: *zsdl.Renderer) !void {
        const start = Globals.drawing.points.items[self.start];
        const end = if (self.end) |end_idx|
            Globals.drawing.points.items[end_idx]
        else pt: {
            var mouse_x: i32 = undefined;
            var mouse_y: i32 = undefined;
            _ = zsdl.getMouseState(&mouse_x, &mouse_y);
            break :pt zsdl.PointF{ .x = @floatFromInt(mouse_x), .y = @floatFromInt(mouse_y) };
        };

        try renderer.setDrawColorRGB(0, 0, 0);
        try renderer.drawLineF(start.x, start.y, end.x, end.y);
    }

    fn setEnd(self: *Line, end: *const zsdl.PointF) void {
        self.end = end;
    }
};

const Drawing = struct {
    allocator: std.mem.Allocator,

    // TODO: use zpool? does it makes sense here?
    points: std.ArrayListUnmanaged(zsdl.PointF) = .{},
    lines: std.ArrayListUnmanaged(Line) = .{},

    fn init(allocator: std.mem.Allocator) Drawing {
        return .{ .allocator = allocator };
    }

    fn deinit(self: *Drawing) void {
        self.lines.deinit(self.allocator);
        self.points.deinit(self.allocator);
    }

    fn render(self: Drawing, renderer: *zsdl.Renderer) !void {
        for (self.lines.items, 0..) |line, i| {
            std.log.info("Drawing.render line {}: {}", .{ i, line });
            try line.render(renderer);
        }

        try renderer.setDrawColorRGB(255, 0, 0);
        for (self.points.items, 0..) |point, i| {
            std.log.info("Drawing.render point {}: {}", .{ i, point });
            try renderer.drawPointF(point.x, point.y);
        }
    }

    fn mouseEvent(self: *Drawing, event_type: enum { up, down, move }, mouse_pos: zsdl.Point) !bool {
        switch (event_type) {
            .down => {
                std.log.info(".down", .{});

                // TODO check tool
                Globals.needs_repaint = true;

                // TODO handle snapping
                try self.points.append(self.allocator, .{
                    .x = @floatFromInt(mouse_pos.x),
                    .y = @floatFromInt(mouse_pos.y),
                });

                try self.lines.append(self.allocator, .{ .start = self.points.items.len - 1 });

                std.log.info(".down done", .{});
                return true;
            },
            .move => {
                std.log.info(".move", .{});
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
                    try self.points.append(self.allocator, .{
                        .x = @floatFromInt(mouse_pos.x),
                        .y = @floatFromInt(mouse_pos.y),
                    });

                    line.end = self.points.items.len - 1;
                    std.log.info("ended line: {any}", .{self.lines.getLast()});
                    return true;
                }
            },
        }
        return false;
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

    var ww: i32 = undefined;
    var wh: i32 = undefined;
    try window.getSize(&ww, &wh);
    var rs = try Globals.renderer.getOutputSize();
    Globals.x_scale = @as(f32, @floatFromInt(rs.w)) / @as(f32, @floatFromInt(ww));
    Globals.y_scale = @as(f32, @floatFromInt(rs.w)) / @as(f32, @floatFromInt(ww));
    try Globals.renderer.setScale(Globals.x_scale, Globals.y_scale);

    Globals.toolbar.tools.appendSliceAssumeCapacity(&[_]Toolbar.Tool{
        .{ .name = "mv", .action = logButtonPress },
        .{ .name = "ln", .action = logButtonPress },
        .{ .name = "dm", .action = logButtonPress },
        .{ .name = "fx", .action = logButtonPress },
    });

    Globals.ui_font = try zsdl.ttf.Font.open("Roboto-Regular.ttf", 14 * @as(i32, @intFromFloat(Globals.x_scale)));

    // handle ONLY window resize
    SDL_SetEventFilter(filterEvent, window);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) std.log.warn("gpa problems!", .{});
    Globals.allocator = gpa.allocator();

    Globals.drawing = Drawing.init(Globals.allocator);
    defer Globals.drawing.deinit();

    mainLoop: while (true) {
        const frame_start = zsdl.getPerformanceCounter();
        const event = try waitEvent();
        switch (event.type) {
            .quit => break :mainLoop,
            // TODO make nicer
            .mousebuttonup => blk: {
                if (try Globals.drawing.mouseEvent(.up, .{ .x = event.button.x, .y = event.button.y }))
                    break :blk;

                if (Globals.toolbar.mouseEvent(.up, .{ .x = event.button.x, .y = event.button.y }))
                    break :blk;
            },
            .mousebuttondown => blk: {
                if (Globals.toolbar.mouseEvent(.down, .{ .x = event.button.x, .y = event.button.y }))
                    break :blk;

                if (try Globals.drawing.mouseEvent(.down, .{ .x = event.button.x, .y = event.button.y }))
                    break :blk;
            },
            .mousemotion => blk: {
                if (try Globals.drawing.mouseEvent(.move, .{ .x = event.motion.x, .y = event.motion.y }))
                    break :blk;

                if (Globals.toolbar.mouseEvent(.move, .{ .x = event.motion.x, .y = event.motion.y }))
                    break :blk;
            },
            .windowevent => Globals.needs_repaint = true,
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
    std.log.info(".draw", .{});
    if (Globals.needs_repaint) {
        Globals.needs_repaint = false;

        std.log.info(".draw axes", .{});
        try renderAxes(renderer);
        std.log.info(".draw drawing", .{});
        try Globals.drawing.render(renderer);
        std.log.info(".draw toolbar", .{});
        try Globals.toolbar.render(renderer);

        std.log.info(".draw present", .{});
        renderer.present();
        std.log.info(".draw done", .{});
    }
}

fn renderAxes(renderer: *zsdl.Renderer) !void {
    // colours from https://www.colourlovers.com/palette/490780/The_First_Raindrop
    try renderer.setDrawColorRGB(232, 243, 248);
    try renderer.clear();

    const size = size: {
        const raw = try renderer.getOutputSize();
        break :size .{
            .w = @divTrunc(raw.w, @as(i32, @intFromFloat(Globals.x_scale))),
            .h = @divTrunc(raw.h, @as(i32, @intFromFloat(Globals.y_scale))),
        };
    };
    // minor axes
    const minor_axis_step = 40;
    try renderer.setDrawColorRGB(194, 203, 206);
    {
        var y: i32 = @divFloor(size.h, 2) - minor_axis_step;
        while (y >= 0) : (y -= minor_axis_step)
            try renderer.drawLine(0, y, size.w, y);
        y = @divFloor(size.h, 2) + minor_axis_step;
        while (y <= size.h) : (y += minor_axis_step)
            try renderer.drawLine(0, y, size.w, y);
    }
    {
        var x: i32 = @divFloor(size.w, 2) - minor_axis_step;
        while (x >= 0) : (x -= minor_axis_step)
            try renderer.drawLine(x, 0, x, size.h);
        x = @divFloor(size.w, 2) + minor_axis_step;
        while (x <= size.w) : (x += minor_axis_step)
            try renderer.drawLine(x, 0, x, size.h);
    }

    // main axes
    try renderer.setDrawColorRGB(129, 168, 184);
    try renderer.drawLine(
        0,
        @divFloor(size.h, 2),
        size.w,
        @divFloor(size.h, 2),
    );
    try renderer.drawLine(
        @divFloor(size.w, 2),
        0,
        @divFloor(size.w, 2),
        size.h,
    );
}
