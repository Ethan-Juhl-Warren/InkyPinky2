package main
import b3 "vendor:box3d"
import "base:runtime"
import "core:math/linalg"
import "core:math"
import "file"
import "config"
import "scene"
import "entity"
import "error"
import "component"
import "render"

/*
The engine's C ABI.

Everything exported below is the entire contract with the client application.
The only things it assumes a client can do are call a C function and own a
window. It does not assume a language, a runtime, a graphics API, a windowing
library or an input device.

There are no structs in it, and that is the point. A struct obliges the client
to reproduce a memory layout, including padding that appears in no declaration:
a { u32, void*, void*, i32, i32 } has an invisible four byte hole after the
first field on any 64 bit target, and a client that lays it out naively reads a
garbage pointer with nothing anywhere to catch it. Scalars oblige the client to
agree on nothing but the calling convention. Every foreign function interface
in every language can pass an integer, a float and a pointer.

For the same reason the return type is i32 rather than bool: nobody has to
guess at the width of a C _Bool.

The parameter order and the numbering of the constants below are what has to
stay stable. See include/engine.h, which is this same contract written out for
clients that are not Odin, and has to be kept in step by hand.
*/

// Which windowing system the client's window came from. Mirrors
// render.SurfaceKind and must keep the same values.
SURFACE_WIN32   :: u32(1)
SURFACE_X11     :: u32(2)
SURFACE_WAYLAND :: u32(3)

// No window. The engine draws into its own framebuffer and the client collects
// the frame with engine_read_pixels.
//
// This is for clients that have no window worth giving the engine. A browser
// based UI is the case in point: its window belongs to its own compositor, and
// a native window placed over the page loses to that compositor no matter how
// it is arranged. Handing back pixels avoids the fight entirely, and lets the
// client draw its own interface over the top of the viewport, which it cannot
// do over a real window.
SURFACE_OFFSCREEN :: u32(4)

// Bits in Frame.actions.
//
// These are intentionally movement intents and not key codes. Shipping a
// keyboard enum across this boundary would be the engine telling the client
// what an input device is, and the client may not have a keyboard, or may want
// these bound to a gamepad, a script or a replay file. Mapping whatever it
// does have onto six bits is the client's job.
ACTION_FORWARD :: u32(1 << 0)
ACTION_BACK    :: u32(1 << 1)
ACTION_LEFT    :: u32(1 << 2)
ACTION_RIGHT   :: u32(1 << 3)
ACTION_UP      :: u32(1 << 4)
ACTION_DOWN    :: u32(1 << 5)

@(private) engine_ctx: runtime.Context
@(private) viewport_width: i32 = 1
@(private) viewport_height: i32 = 1

/*
Brings the engine up on a window the client already created.

Inputs:
- surface_kind: One of the SURFACE_ constants, saying which windowing system
  display and handle came from
- display: The native display connection, or nil on the platforms without one
- handle: The native window to draw into
- width, height: The size of the drawable area in pixels

Outputs:
- i32 1 when the engine is ready to be ticked, 0 when it is not

Note:

What handle has to contain depends on surface_kind, and is not uniform:

  SURFACE_WIN32    an HWND. display is unused and must be nil.
  SURFACE_X11      an XID, the value of a Window, passed as the pointer sized
                   integer it is rather than a pointer to one. display is the
                   Display*.
  SURFACE_WAYLAND  a wl_egl_window*, not a wl_surface*. display is the
                   wl_display*.

The Wayland case is the awkward one and it is on the client's side of the line
on purpose, see src/engine/render/context_linux.odin.

The graphics context is made current on the calling thread. Every later call
into the engine has to come from that same thread.
*/
@(export, link_name="engine_init")
init :: proc "c" (surface_kind: u32, display, handle: rawptr, width, height: i32) -> i32 {
    engine_ctx = runtime.default_context()
    context = engine_ctx
    viewport_width = max(width, 1)
    viewport_height = max(height, 1)
    if !render.init(render.SurfaceKind(surface_kind), display, handle, viewport_width, viewport_height) {
        return 0
    }
    config.load_config()
    file.load_asset_pack()
    scene.init_scene_manager()
    component.init_component_managers()
    _temp_init()
    return 1
}

/*
Advances and draws one frame.

Inputs:
- dt: Seconds elapsed since the last tick
- mouse_dx, mouse_dy: How far the pointer moved since the last tick, in pixels,
  or zero if the client has no pointer
- actions: The ACTION_ bits that are active this frame

Outputs:
- i32 1 when a frame was produced, 0 when it was not

Note:

The client is the only thing that knows any of this, because it owns the window
and therefore owns the event loop.
*/
@(export, link_name="engine_tick")
tick :: proc "c" (dt, mouse_dx, mouse_dy: f32, actions: u32) -> i32 {
    context = engine_ctx
    _temp_tick(dt, mouse_dx, mouse_dy, actions)
    return 1
}

/*
Copies the last drawn frame out, for clients running in SURFACE_OFFSCREEN mode.

Inputs:
- dest: Where to write the frame, with room for width * height * 4 bytes
- capacity: How large dest is, in bytes

Outputs:
- i32 The number of bytes written, or 0 if nothing was written

Note:

The format is RGBA with eight bits a channel, which a browser canvas takes
without conversion.

The rows are bottom to top, the direction OpenGL numbers them in. A client
drawing this into a canvas has to flip it, which is a property of the image and
cheaper to handle at the destination than to undo here.

Returns 0 rather than a partial frame when capacity is too small, so a client
that got its arithmetic wrong sees nothing rather than a torn image.
*/
@(export, link_name="engine_read_pixels")
read_pixels :: proc "c" (dest: rawptr, capacity: i32) -> i32 {
    context = engine_ctx
    if capacity <= 0 {
        return 0
    }
    return i32(render.read_pixels(dest, int(capacity)))
}

/*
Tells the engine the drawable area changed size.

Inputs:
- width, height: The new size in pixels

Note:

The client owns the window, so a resize is only observable there. Nothing in
the engine can notice one on its own.
*/
@(export, link_name="engine_resize")
resize :: proc "c" (width, height: i32) {
    context = engine_ctx
    viewport_width = max(width, 1)
    viewport_height = max(height, 1)
    render.resize(viewport_width, viewport_height)
}

/*
Shuts the engine down.

Outputs:
- i32 1 when the engine released everything it owns

Note:

The window is the client's and is left untouched.
*/
@(export, link_name="engine_destroy")
destroy :: proc "c" () -> i32 {
    context = engine_ctx
    component.destroy_component_managers()
    scene.destroy_scene_manager()
    file.release_asset_pack()
    _temp_destroy()
    render.destroy()
    return 1
}



////////////////////TEMP TEST STUFF///////////////////////////////
@(private) camera: entity.Id
@(private) world_id: b3.WorldId
@(private) ground_id, box_id: b3.BodyId
@(private) ground_mesh, box_mesh: render.Mesh

MOUSE_SENSITIVITY :: 0.003
PITCH_LIMIT_DEGREES :: 89
MOVE_SPEED :: 20.0

CLEAR_COLOR :: [4]f32 {0.40, 0.75, 1.00, 1.00}
GROUND_COLOR :: [4]f32 {1.00, 1.00, 1.00, 1.00}
BOX_COLOR :: [4]f32 {0.90, 0.16, 0.22, 1.00}

NEAR_PLANE :: 0.01
FAR_PLANE :: 1000.0


_temp_init :: proc() {
    camera = scene.create_entity("main camera")
    component.transform_create(camera, {0, 10, 20}, {1, 1, 1}, linalg.QUATERNIONF32_IDENTITY)
	component.camera_create(camera, 45, .PERSPECTIVE)
	camera_error := component.set_main_camera(camera)

    world_def := b3.DefaultWorldDef()
	world_def.gravity = {0, -10, 0}
	world_id = b3.CreateWorld(world_def)

    ground_def := b3.DefaultBodyDef()
	ground_def.position = {0, -0.5, 0}
	ground_id = b3.CreateBody(world_id, ground_def)
	ground_hull := b3.MakeBoxHull(25, 0.5, 25) // half-extents
	ground_shape_def := b3.DefaultShapeDef()
	_ = b3.CreateHullShape(ground_id, ground_shape_def, &ground_hull.base)

    box_def := b3.DefaultBodyDef()
	box_def.type = .dynamicBody
	box_def.position = {0, 8, 0}
	box_id = b3.CreateBody(world_id, box_def)
	box_hull := b3.MakeBoxHull(0.5, 0.5, 0.5)
	box_shape_def := b3.DefaultShapeDef()
	box_shape_def.density = 1.0
	_ = b3.CreateHullShape(box_id, box_shape_def, &box_hull.base)

    ground_mesh = render.mesh_cube(50, 1, 50)
    box_mesh = render.mesh_cube(1, 1, 1)
}

_temp_tick :: proc(dt, mouse_dx, mouse_dy: f32, actions: u32) {
    b3.World_Step(world_id, 1.0 / 60.0, 4)
    cam_pos := component.transform_get_position(camera)
    handle_input(camera, cam_pos, dt, actions)
    handle_mouse(camera, mouse_dx, mouse_dy)

    render.begin_frame(CLEAR_COLOR)

    aspect := f32(viewport_width) / f32(viewport_height)
    render.set_camera(
        component.camera_get_view_matrix(camera),
        component.camera_get_projection_matrix(camera, aspect, NEAR_PLANE, FAR_PLANE),
    )

    gt := b3.Body_GetTransform(ground_id)
    render.draw_mesh(ground_mesh, linalg.matrix4_from_trs_f32(gt.p, gt.q, {1, 1, 1}), GROUND_COLOR)

    bt := b3.Body_GetTransform(box_id)
    render.draw_mesh(box_mesh, linalg.matrix4_from_trs_f32(bt.p, bt.q, {1, 1, 1}), BOX_COLOR)

    render.end_frame()
}

_temp_destroy :: proc() {
    b3.DestroyWorld(world_id)
    render.mesh_destroy(&ground_mesh)
    render.mesh_destroy(&box_mesh)
}


handle_input :: proc(main_camera: entity.Id, curr_pos: [3]f32, dt: f32, actions: u32) {
	up := component.transform_get_up_local(main_camera)
	right := component.transform_get_right_local(main_camera)
	forward := component.transform_get_forward_local(main_camera)
	delta_d := [3]f32 {0, 0, 0}
	if actions & ACTION_FORWARD != 0 {
		delta_d += forward
	}
	if actions & ACTION_BACK != 0 {
		delta_d -= forward
	}

	if actions & ACTION_LEFT != 0 {
		delta_d -= right
	}
	if actions & ACTION_RIGHT != 0 {
		delta_d += right
	}

	if actions & ACTION_UP != 0 {
		delta_d += up
	}
	if actions & ACTION_DOWN != 0 {
		delta_d -= up
	}
	component.transform_set_position(main_camera, curr_pos + delta_d * MOVE_SPEED * dt)
}

handle_mouse :: proc(main_camera: entity.Id, mouse_dx, mouse_dy: f32) {
	if mouse_dx == 0 && mouse_dy == 0 {
		return
	}

	// yaw about the global up, so the horizon never tilts
	yaw := -mouse_dx * MOUSE_SENSITIVITY
	component.transform_rotate(main_camera, linalg.quaternion_angle_axis(yaw, component.GLOBAL_UP))

	// pitch about the camera's own right axis, stopping short of straight up/down
	limit := math.to_radians_f32(PITCH_LIMIT_DEGREES)
	forward := component.transform_get_forward_local(main_camera)
	pitch_now := math.asin_f32(clamp(forward.y, -1, 1))
	pitch := clamp(-mouse_dy * MOUSE_SENSITIVITY, -limit - pitch_now, limit - pitch_now)
	component.transform_rotate_local(main_camera, linalg.quaternion_angle_axis(pitch, component.GLOBAL_RIGHT))
}
