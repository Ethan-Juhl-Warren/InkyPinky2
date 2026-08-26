package main

import "vendor:glfw"

/*
The game front end's window.

This uses GLFW, and the engine has no idea that it does. That is the boundary
working: a client picks whatever windowing library suits it, creates a window
however it likes, and the only thing that crosses into the engine is a native
handle and a size. The editor front end is an Electron application and will
arrive at a handle by a completely different route; neither of them is special
to the engine.

GLFW is asked for a window with CLIENT_API set to NO_API, so it creates a bare
window and does not make a graphics context or set a pixel format. Letting it
make its own context would put two of them on one window, and on Windows the
pixel format is set once per window for the life of the window, so whichever
got there first would win and the other would fail. Context creation is the
engine's job and this leaves it alone to do it.
*/

@(private) window: struct {
    handle:              glfw.WindowHandle,
    width, height:       i32,
    last_x, last_y:      f64,
    has_last_cursor_pos: bool,
}

@(private)
framebuffer_size_callback :: proc "c" (handle: glfw.WindowHandle, width, height: i32) {
    // A minimise reports zero, which is not a size anything wants to divide an
    // aspect ratio by.
    if width <= 0 || height <= 0 {
        return
    }
    window.width = width
    window.height = height
    engine_resize(width, height)
}

@(private)
window_open :: proc(title: cstring, width, height: i32) -> bool {
    if !glfw.Init() {
        return false
    }

    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
    glfw.WindowHint(glfw.RESIZABLE, 1)

    handle := glfw.CreateWindow(width, height, title, nil, nil)
    if handle == nil {
        glfw.Terminate()
        return false
    }

    window.handle = handle
    window.width = width
    window.height = height

    glfw.SetFramebufferSizeCallback(handle, framebuffer_size_callback)

    // Unbounded virtual cursor, which is what a first person camera wants and
    // what the old raylib DisableCursor was doing.
    glfw.SetInputMode(handle, glfw.CURSOR, glfw.CURSOR_DISABLED)
    return true
}

/*
The five values engine_init wants.

This is the one place the front end has to care which windowing system it is
on, because a native window handle is a different kind of object on each and
there is no honest way to paper over that.
*/
@(private)
window_surface :: proc() -> (kind: u32, display, handle: rawptr, width, height: i32) {
    when ODIN_OS == .Windows {
        // display stays nil: Windows has no display connection to pass.
        return SURFACE_WIN32, nil, rawptr(glfw.GetWin32Window(window.handle)), window.width, window.height
    } else when ODIN_OS == .Linux {
        // An X11 Window is an XID, so it travels as the pointer sized integer
        // it already is rather than as a pointer to one.
        return SURFACE_X11,
            rawptr(glfw.GetX11Display()),
            rawptr(uintptr(glfw.GetX11Window(window.handle))),
            window.width,
            window.height
    } else {
        return 0, nil, nil, 0, 0
    }
}

@(private)
window_pump :: proc() -> bool {
    glfw.PollEvents()
    return !glfw.WindowShouldClose(window.handle)
}

/*
Replaces the window's title text.

The title bar is the only surface this front end has to show a number on, since
the engine draws the scene and nothing else, and there is no text rendering
anywhere in it yet.
*/
@(private)
window_set_title :: proc(title: cstring) {
    glfw.SetWindowTitle(window.handle, title)
}

@(private)
window_input :: proc() -> (mouse_dx, mouse_dy: f32, actions: u32) {
    x, y := glfw.GetCursorPos(window.handle)
    if window.has_last_cursor_pos {
        mouse_dx = f32(x - window.last_x)
        mouse_dy = f32(y - window.last_y)
    }
    window.last_x = x
    window.last_y = y
    window.has_last_cursor_pos = true

    // Binding WASD, space and shift is a choice made here, not in the engine.
    // All the engine is told is which of six movement intents are active.
    down :: proc(key: i32) -> bool {
        return glfw.GetKey(window.handle, key) == glfw.PRESS
    }
    if down(glfw.KEY_W)          { actions |= ACTION_FORWARD }
    if down(glfw.KEY_S)          { actions |= ACTION_BACK }
    if down(glfw.KEY_A)          { actions |= ACTION_LEFT }
    if down(glfw.KEY_D)          { actions |= ACTION_RIGHT }
    if down(glfw.KEY_SPACE)      { actions |= ACTION_UP }
    if down(glfw.KEY_LEFT_SHIFT) { actions |= ACTION_DOWN }
    return
}

@(private)
window_close :: proc() {
    if window.handle != nil {
        glfw.DestroyWindow(window.handle)
        window.handle = nil
    }
    glfw.Terminate()
}
