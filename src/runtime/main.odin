package main

import "core:fmt"
import "core:time"

// "system:" means the linker resolves this by name instead of Odin resolving it
// as a path relative to this file. Where the library actually is stays in the
// Makefile as a search path, so nothing here has to know the build layout.
when ODIN_OS == .Windows {
    foreign import engine "system:engine.lib"
}  else {
    foreign import engine "system:engine"
}

/*
The client side of the engine ABI.

These declarations are a hand copy of what src/engine/engine.odin exports, and
they are a hand copy on purpose. This front end happens to be written in Odin,
but the engine must not assume that, so there is no shared package to import
and nothing here reaches into the engine's source. Anything that can declare a
C function and pass an integer, a float and a pointer can be a client on
exactly these terms; see include/engine.h for the same thing spelled for C.

There are no structs, so there is no memory layout to get wrong. What is left
to keep in step by hand is the parameter order and the constants below.
*/

SURFACE_WIN32   :: u32(1)
SURFACE_X11     :: u32(2)
SURFACE_WAYLAND :: u32(3)

ACTION_FORWARD :: u32(1 << 0)
ACTION_BACK    :: u32(1 << 1)
ACTION_LEFT    :: u32(1 << 2)
ACTION_RIGHT   :: u32(1 << 3)
ACTION_UP      :: u32(1 << 4)
ACTION_DOWN    :: u32(1 << 5)

foreign engine {
    engine_init    :: proc "c" (surface_kind: u32, display, handle: rawptr, width, height: i32) -> i32 ---
    engine_tick    :: proc "c" (dt, mouse_dx, mouse_dy: f32, actions: u32) -> i32 ---
    engine_resize  :: proc "c" (width, height: i32) ---
    engine_destroy :: proc "c" () -> i32 ---
}

WINDOW_TITLE : cstring : "InkyPinky"
WINDOW_WIDTH :: 1280
WINDOW_HEIGHT :: 720

main :: proc() {
    // The window is ours, not the engine's. We create it, we pump its
    // messages, we decide when it closes, and all the engine ever sees of it
    // is the handle inside Surface.
    if !window_open(WINDOW_TITLE, WINDOW_WIDTH, WINDOW_HEIGHT) {
        fmt.printfln("ERROR: Window could not be closed.")
        return
    }
    defer window_close()

    kind, display, handle, width, height := window_surface()
    if engine_init(kind, display, handle, width, height) == 0 {
        fmt.printfln("ERROR: Unable to start engine")
        return
    }
    defer engine_destroy()

    previous := time.tick_now()

    // Frames since the counter was last shown, and how long they took. The
    // title bar is the only place there is to put a number, because the engine
    // draws the scene and this front end draws nothing at all.
    //
    // Note that vsync is on: the engine asks for a swap interval of 1, so this
    // reads the display's refresh rate rather than what the engine could
    // manage unthrottled.
    fps_frames := 0
    fps_elapsed: f32 = 0

    for window_pump() {
        now := time.tick_now()
        dt := f32(time.duration_seconds(time.tick_diff(previous, now)))
        previous = now

        mouse_dx, mouse_dy, actions := window_input()
        engine_tick(dt, mouse_dx, mouse_dy, actions)

        fps_frames += 1
        fps_elapsed += dt
        if fps_elapsed >= 1 {
            window_set_title(fmt.ctprintf("%s - %.0f fps", WINDOW_TITLE, f32(fps_frames) / fps_elapsed))
            free_all(context.temp_allocator)
            fps_frames = 0
            fps_elapsed = 0
        }
    }
}
