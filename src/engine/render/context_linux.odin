#+build linux
package render

import gl "vendor:OpenGL"
import "vendor:egl"

/*
Turns a window owned by the client application into something OpenGL can draw
into, on Linux.

EGL rather than GLX. GLX is X11 only and Odin ships no bindings for it, so it
would mean hand written ones; EGL covers X11 and Wayland through the same calls
and vendor:egl is already there. The cost is a hard dependency on libEGL, which
is present on any Mesa or proprietary driver install from the last decade.

Unlike the Windows path, this asks for exactly what it wants and fails if it
cannot have it: a 3.3 core profile, no compatibility fallback. EGL exposes the
profile mask directly, so there is no reason to take whatever the driver feels
like handing over. That means this path is the stricter of the two, and code
that runs here will run on Windows but not necessarily the other way round.

What the client passes as the window handle differs by platform, and this is
the one place the contract is not uniform:

  X11      an XID (the value of a Window), placed in the handle field as an
           integer, not a pointer. Xlib's Window is an unsigned long, so it
           fits, but taking its address instead is a silent way to get
           EGL_BAD_NATIVE_WINDOW.

  Wayland  a wl_egl_window*, NOT a wl_surface*. eglCreateWindowSurface cannot
           take a bare surface, it needs the wl_egl_window wrapper that
           libwayland-egl builds from a surface plus a size. Making the client
           do that keeps libwayland-egl out of the engine, and it is the right
           side of the line anyway: the client owns the window system, so it
           owns the object that represents its window.
*/

// vendor:egl ships WINDOW_BIT but not this one, and a surfaceless config still
// has to ask for a surface type it could in principle support.
@(private) EGL_PBUFFER_BIT :: 0x0001

@(private)
egl_context: struct {
	display: egl.Display,
	surface: egl.Surface,
	ctx:     egl.Context,
}

@(private)
_context_create :: proc(kind: SurfaceKind, display, handle: rawptr) -> bool {
	offscreen := kind == .OFFSCREEN

	platform: egl.Platform
	switch kind {
	case .X11:
		platform = .X11_KHR
	case .WAYLAND:
		platform = .WAYLAND_KHR
	case .OFFSCREEN:
		// No window and no display connection to attach to. Mesa's surfaceless
		// platform exists for exactly this, and everything is drawn to a
		// framebuffer object rather than to any surface.
		platform = .SURFACELESS_MESA
	case .WIN32:
		// The client told us it has an HWND while the engine is built for
		// Linux. Nothing sensible to do with that.
		return false
	case:
		return false
	}

	egl_display := egl.GetPlatformDisplay(platform, nil if offscreen else display, nil)
	if egl_display == egl.NO_DISPLAY {
		return false
	}
	if !egl.Initialize(egl_display, nil, nil) {
		return false
	}

	// Desktop GL, not GLES. EGL defaults to GLES, so leaving this out gets a
	// context that rejects the core profile request below for no obvious
	// reason.
	if !egl.BindAPI(egl.OPENGL_API) {
		egl.Terminate(egl_display)
		return false
	}

	config_attributes := [?]i32 {
		egl.SURFACE_TYPE,    EGL_PBUFFER_BIT if offscreen else egl.WINDOW_BIT,
		egl.RENDERABLE_TYPE, egl.OPENGL_BIT,
		egl.RED_SIZE,        8,
		egl.GREEN_SIZE,      8,
		egl.BLUE_SIZE,       8,
		egl.DEPTH_SIZE,      24,
		egl.STENCIL_SIZE,    8,
		egl.NONE,
	}
	config: egl.Config
	config_count: i32
	if !egl.ChooseConfig(egl_display, &config_attributes[0], &config, 1, &config_count) || config_count == 0 {
		egl.Terminate(egl_display)
		return false
	}

	// Offscreen has no surface at all. A surfaceless context is allowed to be
	// made current with EGL_NO_SURFACE, and since every draw goes to a
	// framebuffer object there is nothing a surface would be for.
	surface := egl.NO_SURFACE
	if !offscreen {
		surface = egl.CreateWindowSurface(egl_display, config, egl.NativeWindowType(handle), nil)
		if surface == egl.NO_SURFACE {
			egl.Terminate(egl_display)
			return false
		}
	}

	context_attributes := [?]i32 {
		egl.CONTEXT_MAJOR_VERSION,       GL_MAJOR,
		egl.CONTEXT_MINOR_VERSION,       GL_MINOR,
		egl.CONTEXT_OPENGL_PROFILE_MASK, egl.CONTEXT_OPENGL_CORE_PROFILE_BIT,
		egl.NONE,
	}
	ctx := egl.CreateContext(egl_display, config, egl.NO_CONTEXT, &context_attributes[0])
	if ctx == egl.NO_CONTEXT {
		if surface != egl.NO_SURFACE {
			egl.DestroySurface(egl_display, surface)
		}
		egl.Terminate(egl_display)
		return false
	}

	if !egl.MakeCurrent(egl_display, surface, surface, ctx) {
		egl.DestroyContext(egl_display, ctx)
		if surface != egl.NO_SURFACE {
			egl.DestroySurface(egl_display, surface)
		}
		egl.Terminate(egl_display)
		return false
	}

	gl.load_up_to(GL_MAJOR, GL_MINOR, egl.gl_set_proc_address)

	// Vsync, and only where there is something to synchronise with. A driver
	// is allowed to refuse, which only means the client's loop runs free, so
	// the result is not checked.
	if !offscreen {
		egl.SwapInterval(egl_display, 1)
	}

	egl_context = {egl_display, surface, ctx}
	return true
}

@(private)
_context_present :: proc() {
	egl.SwapBuffers(egl_context.display, egl_context.surface)
}

@(private)
_context_destroy :: proc() {
	if egl_context.display == egl.NO_DISPLAY {
		return
	}
	egl.MakeCurrent(egl_context.display, egl.NO_SURFACE, egl.NO_SURFACE, egl.NO_CONTEXT)
	if egl_context.ctx != egl.NO_CONTEXT {
		egl.DestroyContext(egl_context.display, egl_context.ctx)
	}
	if egl_context.surface != egl.NO_SURFACE {
		egl.DestroySurface(egl_context.display, egl_context.surface)
	}
	egl.Terminate(egl_context.display)
	egl_context = {}
}
