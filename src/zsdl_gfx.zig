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

/// Draw pixel in currently set color.
fn pixel(renderer: *zsdl.Renderer, x: i16, y: i16) !void {
    try renderer.drawPoint(x, y);
}

/// Draw pixel with blending enabled if a<255
fn pixelRGBA(renderer: *zsdl.Renderer, x: i16, y: i16, r: u8, g: u8, b: u8, a: u8) !void {
    if (a != 0xFF)
        try renderer.setDrawBlendMode(.blend);

    try renderer.setDrawColorRGBA(renderer, r, g, b, a);
    try renderer.drawPoint(renderer, x, y);
}

/// Draw pixel with blending enabled and using alpha weight on color.
fn pixelRGBAWeight(renderer: *zsdl.Renderer, x: i16, y: i16, r: u8, g: u8, b: u8, a: u8, weight: u32) !void {
    // modify alpha by weight
    var ax: u32 = a;
    ax = (ax * weight) >> 8;
    a = if (ax < 0xFF) @truncate(ax) else 0xFF;

    try pixelRGBA(renderer, x, y, r, g, b, a);
}

/// Draw horizontal line in currently set color.
fn hline(renderer: *zsdl.Renderer, x1: i16, x2: i16, y: i16) !void {
    try renderer.drawLine(x1, y, x2, y);
}

/// Draw horizontal line in currently set color.
fn hlineRGBA(renderer: *zsdl.Renderer, x1: i16, x2: i16, y: i16) !void {
    try renderer.drawLine(x1, y, x2, y);
}

/// Draw anti-aliased filled ellipse with blending.
pub fn aaFilledEllipseRGBA(renderer: *zsdl.Renderer, c: zsdl.PointF, r: zsdl.PointF, col: zsdl.Color) !void {
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
