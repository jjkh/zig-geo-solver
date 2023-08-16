/// Required functions missing from zig-gamedev zsdl
const zsdl = @import("zsdl");

pub fn waitEvent() !zsdl.Event {
    var event: zsdl.Event = undefined;
    if (SDL_WaitEvent(&event) == 0)
        return error.SdlError;
    return event;
}
extern fn SDL_WaitEvent(event: ?*zsdl.Event) i32;

// cursor APIs
pub const Cursor = opaque {
    pub const SystemCursor = enum(c_int) {
        arrow,
        i_beam,
        wait,
        crosshair,
        wait_arrow,
        size_nw_se,
        size_ne_sw,
        size_w_e,
        size_n_s,
        size_all,
        no,
        hand,
    };

    pub fn createSystem(cursor_type: SystemCursor) !*Cursor {
        if (SDL_CreateSystemCursor(cursor_type)) |cursor|
            return cursor;
        return error.SdlError;
    }
    extern fn SDL_CreateSystemCursor(id: SystemCursor) ?*Cursor;

    pub fn set(cursor: ?*Cursor) !void {
        if (SDL_SetCursor(cursor) != 0)
            return error.SdlError;
    }
    extern fn SDL_SetCursor(cursor: ?*Cursor) i32;

    pub fn current() !*Cursor {
        if (SDL_GetCursor()) |cursor|
            return cursor;
        return error.NoMouse;
    }
    extern fn SDL_GetCursor() ?*Cursor;

    // You do not have to call SDL_DestroyCursor() on the return value, but it is
    // safe to do so.
    pub fn default() !*Cursor {
        if (SDL_GetDefaultCursor()) |cursor|
            return cursor;
        return error.SdlError;
    }
    extern fn SDL_GetDefaultCursor() ?*Cursor;

    // Use this function to free cursor resources created with SDL_CreateCursor(),
    // SDL_CreateColorCursor() or SDL_CreateSystemCursor().
    pub const destroy = SDL_FreeCursor;
    extern fn SDL_FreeCursor(cursor: *Cursor) void;
};

// event filter
pub const setEventFilter = SDL_SetEventFilter;
pub const EventFilterCallback = *const fn (userdata: ?*anyopaque, event: *zsdl.Event) callconv(.C) c_int;
extern fn SDL_SetEventFilter(filter: EventFilterCallback, userdata: *anyopaque) void;
