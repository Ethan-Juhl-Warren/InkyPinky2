#+build windows
package render

import gl "vendor:OpenGL"
import win "core:sys/windows"

/*
Turns an HWND owned by the client application into something OpenGL can draw
into, on Windows.

This is the whole of the platform knowledge in the engine. The client creates
the window and pumps its messages in whatever language it likes; all the engine
asks for is the handle.

The context is created the short way: ChoosePixelFormat and wglCreateContext
straight onto the client's window. The long way is to spin up a throwaway window
first, load wglChoosePixelFormatARB and wglCreateContextAttribsARB through it,
then redo the real window with those. That buys three things: a core profile
rather than compatibility, an explicit version rather than whatever the driver
feels like, and control over MSAA and sRGB. None of it is worth ~100 lines in a
renderer that is already scheduled for demolition, because every current Windows
driver answers wglCreateContext with a compatibility context at the highest
version it supports, which is 4.6 on anything made in the last decade. GL 3.3
entry points load fine out of that.

What that costs, and what will bite whoever writes the real renderer: no core
profile means deprecated GL 1.x calls silently work here and will stop working
there, and there is no anti aliasing. Both are reasons to do the ARB dance
properly next time rather than to do it now.

SetPixelFormat is once per window, for the life of the window. If the client has
already set one on this HWND, this fails rather than papering over it, because
the format it picked is not knowable from here.
*/

@(private)
win32_context: struct {
	hwnd:  win.HWND,
	hdc:   win.HDC,
	hglrc: win.HGLRC,
}

// Set when the engine made its own hidden window for an offscreen context, so
// that it knows to destroy it again. Zero when drawing into a client's window,
// which is the client's to destroy.
@(private) win32_owns_window: bool

@(private) HIDDEN_CLASS_NAME : win.LPCWSTR : "InkyEngineOffscreen"

/*
Makes a hidden window to hold an offscreen context.

WGL has no way to make a context without a drawable, so offscreen mode gets a
one by one window that is never shown. Everything is then drawn to a
framebuffer object and this window's own buffers are never touched.

CS_OWNDC for the same reason the client's window needs it: the device context
is fetched once and kept.
*/
@(private)
_create_hidden_window :: proc() -> win.HWND {
	instance := win.HINSTANCE(win.GetModuleHandleW(nil))
	class := win.WNDCLASSEXW {
		cbSize        = size_of(win.WNDCLASSEXW),
		style         = win.CS_OWNDC,
		lpfnWndProc   = win.DefWindowProcW,
		hInstance     = instance,
		lpszClassName = HIDDEN_CLASS_NAME,
	}
	// A second call for an already registered class fails harmlessly, which is
	// what happens if the engine is brought up more than once in a process.
	win.RegisterClassExW(&class)

	return win.CreateWindowExW(
		0,
		HIDDEN_CLASS_NAME,
		HIDDEN_CLASS_NAME,
		win.WS_OVERLAPPEDWINDOW,
		0,
		0,
		1,
		1,
		nil,
		nil,
		instance,
		nil,
	)
}

@(private)
_context_create :: proc(kind: SurfaceKind, display, handle: rawptr) -> bool {
	// display is the X11 and Wayland connection. Windows has no equivalent and
	// the client is documented to pass nil.
	_ = display

	hwnd: win.HWND
	switch kind {
	case .WIN32:
		hwnd = win.HWND(handle)
		win32_owns_window = false
	case .OFFSCREEN:
		hwnd = _create_hidden_window()
		win32_owns_window = true
	case .X11, .WAYLAND:
		// The client told us it has an X11 or Wayland window while the engine
		// is built for Windows. Nothing sensible to do with that.
		return false
	case:
		return false
	}

	if hwnd == nil {
		return false
	}

	hdc := win.GetDC(hwnd)
	if hdc == nil {
		return false
	}

	descriptor := win.PIXELFORMATDESCRIPTOR {
		nSize        = size_of(win.PIXELFORMATDESCRIPTOR),
		nVersion     = 1,
		dwFlags      = win.PFD_DRAW_TO_WINDOW | win.PFD_SUPPORT_OPENGL | win.PFD_DOUBLEBUFFER,
		iPixelType   = win.PFD_TYPE_RGBA,
		cColorBits   = 32,
		cDepthBits   = 24,
		cStencilBits = 8,
		iLayerType   = win.PFD_MAIN_PLANE,
	}

	format := win.ChoosePixelFormat(hdc, &descriptor)
	if format == 0 {
		win.ReleaseDC(hwnd, hdc)
		return false
	}
	if !win.SetPixelFormat(hdc, format, &descriptor) {
		win.ReleaseDC(hwnd, hdc)
		return false
	}

	hglrc := win.wglCreateContext(hdc)
	if hglrc == nil {
		win.ReleaseDC(hwnd, hdc)
		return false
	}
	if !win.wglMakeCurrent(hdc, hglrc) {
		win.wglDeleteContext(hglrc)
		win.ReleaseDC(hwnd, hdc)
		return false
	}

	// core:sys/windows carries the loader for this, including the fallback into
	// opengl32.dll that wglGetProcAddress needs for the GL 1.1 entry points it
	// refuses to return. Rolling it by hand here is how that bug gets written
	// again.
	gl.load_up_to(GL_MAJOR, GL_MINOR, win.gl_set_proc_address)

	// Vsync. This is an extension, so it is only there once a context is
	// current, and a driver is within its rights to not have it. Missing vsync
	// is not a reason to fail the whole init, it just means the client's loop
	// is free running.
	win.wglSwapIntervalEXT = win.SwapIntervalEXTType(win.wglGetProcAddress("wglSwapIntervalEXT"))
	if win.wglSwapIntervalEXT != nil {
		win.wglSwapIntervalEXT(1)
	}

	win32_context = {hwnd, hdc, hglrc}
	return true
}

@(private)
_context_present :: proc() {
	win.SwapBuffers(win32_context.hdc)
}

@(private)
_context_destroy :: proc() {
	win.wglMakeCurrent(nil, nil)
	if win32_context.hglrc != nil {
		win.wglDeleteContext(win32_context.hglrc)
	}
	if win32_context.hdc != nil {
		win.ReleaseDC(win32_context.hwnd, win32_context.hdc)
	}
	// Only the hidden offscreen window is ours to destroy. A client's window
	// outlives the engine and is the client's to close.
	if win32_owns_window && win32_context.hwnd != nil {
		win.DestroyWindow(win32_context.hwnd)
	}
	win32_owns_window = false
	win32_context = {}
}
