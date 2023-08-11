// --------------------------------------------------------------------------
// The following code is adapted from Richard Russell's modifications of the
// SDL2_gfx library. The original license is included in full below.
// --------------------------------------------------------------------------
// SDL2_gfxPrimitives.c: graphics primitives for SDL2 renderers
//
// Copyright (C) 2012-2014  Andreas Schiffler
// Modifications and additions for BBC BASIC (C) 2016-2020 Richard Russell
//
// This software is provided 'as-is', without any express or implied
// warranty. In no event will the authors be held liable for any damages
// arising from the use of this software.
//
// Permission is granted to anyone to use this software for any purpose,
// including commercial applications, and to alter it and redistribute it
// freely, subject to the following restrictions:
//
// 1. The origin of this software must not be misrepresented; you must not
// claim that you wrote the original software. If you use this software
// in a product, an acknowledgment in the product documentation would be
// appreciated but is not required.
//
// 2. Altered source versions must be plainly marked as such, and must not be
// misrepresented as being the original software.
//
// 3. This notice may not be removed or altered from any source
// distribution.
//
// Andreas Schiffler -- aschiffler at ferzkopp dot net
// Richard Russell -- richard at rtrussell dot co dot uk
// --------------------------------------------------------------------------

const std = @import("std");
const zsdl = @import("zsdl");

const BresenhamIterator = struct {
    x: i16,
    y: i16,

    dx: i32,
    dy: i32,
    s1: i32,
    s2: i32,
    swapdir: i32,
    err: i32,

    count: u32,
};

fn setColorAndBlend(renderer: *zsdl.Renderer, color: zsdl.Color) !void {
    if (color.a != 0xFF)
        try renderer.setDrawBlendMode(.blend);
    try renderer.setDrawColor(color);
}

/// Draw pixel with blending enabled if a<255
fn pixel(renderer: *zsdl.Renderer, pt: zsdl.Point, color: ?zsdl.Color) !void {
    if (color) |c|
        try setColorAndBlend(renderer, c);
    try renderer.drawPoint(pt.x, pt.y);
}

/// Draw horizontal line with blending.
fn hline(renderer: *zsdl.Renderer, x1: i32, x2: i32, y: i32, color: ?zsdl.Color) !void {
    if (color) |c|
        try setColorAndBlend(renderer, c);
    try renderer.drawLine(x1, y, x2, y);
}

/// Draw vertical line in currently set color.
fn vline(renderer: *zsdl.Renderer, x: i32, y1: i32, y2: i32, color: ?zsdl.Color) !void {
    if (color) |c|
        try setColorAndBlend(renderer, c);
    try renderer.drawLine(x, y1, x, y2);
}

/// Draw anti-aliased filled ellipse with blending.
pub fn filledEllipse(renderer: *zsdl.Renderer, c: zsdl.PointF, r: zsdl.PointF, col: zsdl.Color) !void {
    if (r.x <= 0.0 or r.y <= 0.0)
        return error.InvalidRadius;

    try renderer.setDrawBlendMode(.blend);

    if (r.x >= r.y) {
        const n: i32 = @intFromFloat(r.y + 1);
        var yi: i32 = @as(i32, @intFromFloat(c.y)) - n - 1;
        while (yi <= @as(i32, @intFromFloat(c.y)) + n + 1) : (yi += 1) {
            const y: f64 = if (yi < @as(i32, @intFromFloat(c.y - 0.5)))
                @floatFromInt(yi)
            else
                @floatFromInt(yi + 1);
            var s: f64 = (y - c.y) / r.y;
            s *= s;
            var x: f64 = 0.5;
            if (s < 1.0) {
                x = r.x * @sqrt(1.0 - s);
                if (x >= 0.5) {
                    try renderer.setDrawColor(col);
                    try renderer.drawLine(
                        @intFromFloat(c.x - x + 1),
                        yi,
                        @intFromFloat(c.x + x - 1),
                        yi,
                    );
                }
            }
            s = 8 * r.y * r.y;
            const dy: f64 = @fabs(y - c.y) - 1.0;

            {
                var xi: i32 = @intFromFloat(c.x - x); // left
                while (true) : (xi -= 1) {
                    const dx: f64 = (c.x - @as(f32, @floatFromInt(xi)) - 1) * r.y / r.x;
                    var v: f64 = s - 4 * (dx - dy) * (dx - dy);
                    if (v < 0) break;
                    v = (@sqrt(v) - 2 * (dx + dy)) / 4;
                    if (v < 0) break;
                    if (v > 1.0) v = 1.0;

                    try renderer.setDrawColorRGBA(col.r, col.g, col.b, @intFromFloat(@as(f64, @floatFromInt(col.a)) * v));
                    try renderer.drawPoint(xi, yi);
                }
            }
            {
                var xi: i32 = @intFromFloat(c.x + x); // right
                while (true) : (xi += 1) {
                    const dx: f64 = (@as(f32, @floatFromInt(xi)) - c.x) * r.y / r.x;
                    var v: f64 = s - 4 * (dx - dy) * (dx - dy);
                    if (v < 0) break;
                    v = (@sqrt(v) - 2 * (dx + dy)) / 4;
                    if (v < 0) break;
                    if (v > 1.0) v = 1.0;

                    try renderer.setDrawColorRGBA(col.r, col.g, col.b, @intFromFloat(@as(f64, @floatFromInt(col.a)) * v));
                    try renderer.drawPoint(xi, yi);
                }
            }
        }
    } else {
        const n: i32 = @intFromFloat(r.x + 1);
        var xi: i32 = @as(i32, @intFromFloat(c.x)) - n - 1;
        while (xi <= @as(i32, @intFromFloat(c.x)) + n + 1) : (xi += 1) {
            const x: f64 = if (xi < @as(i32, @intFromFloat(c.x - 0.5)))
                @floatFromInt(xi)
            else
                @floatFromInt(xi + 1);
            var s: f64 = (x - c.x) / r.x;
            s *= s;
            var y: f64 = 0.5;
            if (s < 1.0) {
                y = r.y * @sqrt(1.0 - s);
                if (y >= 0.5) {
                    try renderer.setDrawColor(col);
                    try renderer.drawLine(
                        xi,
                        @intFromFloat(c.y - y + 1),
                        xi,
                        @intFromFloat(c.y + y - 1),
                    );
                }
            }
            s = 8 * r.x * r.x;
            const dx: f64 = @fabs(x - c.x) - 1.0;

            {
                var yi: i32 = @intFromFloat(c.y - y); // top
                while (true) : (yi -= 1) {
                    const dy: f64 = (c.y - @as(f32, @floatFromInt(yi)) - 1) * r.x / r.y;
                    var v: f64 = s - 4 * (dy - dx) * (dy - dx);
                    if (v < 0) break;
                    v = (@sqrt(v) - 2 * (dy + dx)) / 4;
                    if (v < 0) break;
                    if (v > 1.0) v = 1.0;

                    try renderer.setDrawColorRGBA(col.r, col.g, col.b, @intFromFloat(@as(f64, @floatFromInt(col.a)) * v));
                    try renderer.drawPoint(xi, yi);
                }
            }
            {
                var yi: i32 = @intFromFloat(c.y + y); // bottom
                while (true) : (yi += 1) {
                    const dy: f64 = (@as(f32, @floatFromInt(yi)) - c.y) * r.x / r.y;
                    var v: f64 = s - 4 * (dy - dx) * (dy - dx);
                    if (v < 0) break;
                    v = (@sqrt(v) - 2 * (dy + dx)) / 4;
                    if (v < 0) break;
                    if (v > 1.0) v = 1.0;

                    try renderer.setDrawColorRGBA(col.r, col.g, col.b, @intFromFloat(@as(f64, @floatFromInt(col.a)) * v));
                    try renderer.drawPoint(xi, yi);
                }
            }
        }
    }
}

/// Draw box (filled rectangle) with blending.
pub fn box(renderer: *zsdl.Renderer, rect: zsdl.Rect, color: zsdl.Color) !void {
    // special cases (straight line or single point)
    if (rect.w == 0) {
        if (rect.h == 0)
            return pixel(renderer, .{ .x = rect.x, .y = rect.y }, color)
        else
            return vline(renderer, rect.x, rect.y, rect.y + rect.h, color);
    } else if (rect.h == 0) {
        return hline(renderer, rect.x, rect.x + rect.w, rect.y, color);
    }

    try setColorAndBlend(renderer, color);
    try renderer.fillRect(rect);
}

// Code for Murphy thick line algorithm from http://kt8216.unixcab.org/murphy/
fn xPerpendicular(
    renderer: *zsdl.Renderer,
    a: zsdl.Point,
    dx: i32,
    dy: i32,
    x_step: i32,
    y_step: i32,
    e_init: i32,
    w_left: i32,
    w_right: i32,
    w_init: i32,
) !void {
    const threshold = dx - 2 * dy;
    const e_diag = -2 * dx;
    const e_square = 2 * dy;

    var p: i32 = 0;
    var q: i32 = 0;

    var x = a.x;
    var y = a.y;
    var err = e_init;
    var tk = dx + dy - w_init;
    while (tk <= w_left) : (q += 1) {
        try renderer.drawPoint(x, y);
        if (err >= threshold) {
            x += x_step;
            err += e_diag;
            tk += 2 * dy;
        }
        err += e_square;
        y += y_step;
        tk += 2 * dx;
    }

    x = a.x;
    y = a.y;
    err = -e_init;
    tk = dx + dy + w_init;
    while (tk <= w_right) : (p += 1) {
        if (p > 0)
            try renderer.drawPoint(x, y);

        if (err > threshold) {
            x -= x_step;
            err += e_diag;
            tk += 2 * dy;
        }
        err += e_square;
        y -= y_step;
        tk += 2 * dx;
    }

    // we need this for very thin lines
    if (q == 0 and p < 2)
        try renderer.drawPoint(a.x, a.y);
}

fn xVarThickLine(
    renderer: *zsdl.Renderer,
    a: zsdl.Point,
    dx: i32,
    dy: i32,
    x_step: i32,
    y_step: i32,
    width: f64,
    px_step: i32,
    py_step: i32,
) !void {
    var p_err: i32 = 0;
    var err: i32 = 0;
    var new_a = .{ .x = a.x, .y = a.y };
    const threshold = dx - 2 * dy;
    const e_diag = -2 * dx;
    const e_square = 2 * dy;
    const length: u32 = @intCast(dx + 1);
    const d = @sqrt(@as(f64, @floatFromInt(dx * dx + dy * dy)));
    const w_left: i32 = @intFromFloat(width * d + 0.5);
    const w_right: i32 = @as(i32, @intFromFloat(2 * width * d + 0.5)) - w_left;

    for (0..length) |_| {
        try xPerpendicular(renderer, new_a, dx, dy, px_step, py_step, p_err, w_left, w_right, err);

        if (err >= threshold) {
            new_a.y += y_step;
            err += e_diag;
            if (p_err >= threshold) {
                try xPerpendicular(renderer, new_a, dx, dy, px_step, py_step, (p_err + e_diag + e_square), w_left, w_right, err);
                p_err += e_diag;
            }
            p_err += e_square;
        }
        err += e_square;
        new_a.x += x_step;
    }
}

fn yPerpendicular(
    renderer: *zsdl.Renderer,
    a: zsdl.Point,
    dx: i32,
    dy: i32,
    x_step: i32,
    y_step: i32,
    e_init: i32,
    w_left: i32,
    w_right: i32,
    w_init: i32,
) !void {
    const threshold = dy - 2 * dx;
    const e_diag = -2 * dy;
    const e_square = 2 * dx;

    var p: i32 = 0;
    var q: i32 = 0;

    var x = a.x;
    var y = a.y;
    var err = -e_init;
    var tk = dx + dy + w_init;
    while (tk <= w_left) : (q += 1) {
        try renderer.drawPoint(x, y);
        if (err >= threshold) {
            y += y_step;
            err += e_diag;
            tk += 2 * dx;
        }
        err += e_square;
        x += x_step;
        tk += 2 * dy;
    }

    x = a.x;
    y = a.y;
    err = e_init;
    tk = dx + dy - w_init;
    while (tk <= w_right) : (p += 1) {
        if (p > 0)
            try renderer.drawPoint(x, y);

        if (err > threshold) {
            y -= y_step;
            err += e_diag;
            tk += 2 * dx;
        }
        err += e_square;
        x -= x_step;
        tk += 2 * dy;
    }

    // we need this for very thin lines
    if (q == 0 and p < 2)
        try renderer.drawPoint(a.x, a.y);
}

fn yVarThickLine(
    renderer: *zsdl.Renderer,
    a: zsdl.Point,
    dx: i32,
    dy: i32,
    x_step: i32,
    y_step: i32,
    width: f64,
    px_step: i32,
    py_step: i32,
) !void {
    var p_err: i32 = 0;
    var err: i32 = 0;
    var new_a = .{ .x = a.x, .y = a.y };
    const threshold = dy - 2 * dx;
    const e_diag = -2 * dy;
    const e_square = 2 * dx;
    const length: u32 = @intCast(dy + 1);
    const d = @sqrt(@as(f64, @floatFromInt(dx * dx + dy * dy)));
    const w_left: i32 = @intFromFloat(width * d + 0.5);
    const w_right: i32 = @as(i32, @intFromFloat(2 * width * d + 0.5)) - w_left;

    for (0..length) |_| {
        try yPerpendicular(renderer, new_a, dx, dy, px_step, py_step, p_err, w_left, w_right, err);

        if (err >= threshold) {
            new_a.x += x_step;
            err += e_diag;
            if (p_err >= threshold) {
                try yPerpendicular(renderer, new_a, dx, dy, px_step, py_step, (p_err + e_diag + e_square), w_left, w_right, err);
                p_err += e_diag;
            }
            p_err += e_square;
        }
        err += e_square;
        new_a.y += y_step;
    }
}

fn drawVarThickLine(renderer: *zsdl.Renderer, a: zsdl.Point, b: zsdl.Point, width: f64) !void {
    var dx: i32 = b.x - a.x;
    var dy: i32 = b.y - a.y;
    var x_step: i32 = 1;
    var y_step: i32 = 1;

    if (dx < 0) {
        dx = -dx;
        x_step = -1;
    }
    if (dy < 0) {
        dy = -dy;
        y_step = -1;
    }

    if (dx == 0) x_step = 0;
    if (dy == 0) y_step = 0;

    // TODO: work this out... why y_step*4?
    var py_step: i32 = 0;
    var px_step: i32 = 0;
    switch (x_step + y_step * 4) {
        // zig fmt: off
        -1 + -1*4 => { py_step = -1; px_step =  1; }, // -5
        -1 +  0*4 => { py_step = -1; px_step =  0; }, // -1
        -1 +  1*4 => { py_step =  1; px_step =  1; }, // 3
         0 + -1*4 => { py_step =  0; px_step = -1; }, // -4
         0 +  0*4 => { py_step =  0; px_step =  0; }, // 0
         0 +  1*4 => { py_step =  0; px_step =  1; }, // 4
         1 + -1*4 => { py_step = -1; px_step = -1; }, // -3
         1 +  0*4 => { py_step = -1; px_step =  0; }, // 1
         1 +  1*4 => { py_step =  1; px_step = -1; }, // 5
         else => {},
        // zig fmt: on
    }

    if (dx > dy)
        try xVarThickLine(renderer, a, dx, dy, x_step, y_step, width + 1.0, px_step, py_step)
    else
        try yVarThickLine(renderer, a, dx, dy, x_step, y_step, width + 1.0, px_step, py_step);
}

pub fn thickLine(renderer: *zsdl.Renderer, a: zsdl.Point, b: zsdl.Point, width: f32, color: zsdl.Color) !void {
    if (width == 0) return error.ZeroWidth;

    // special case: thick "point"
    if (a.x == b.x and a.y == b.y) {
        const pixel_width: u16 = @intFromFloat(width);
        return box(renderer, .{ .x = a.x - pixel_width / 2, .y = a.y - pixel_width / 2, .w = pixel_width, .h = pixel_width }, color);
    }

    try setColorAndBlend(renderer, color);
    try drawVarThickLine(renderer, a, b, width);
}
