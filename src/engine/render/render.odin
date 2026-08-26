package render

import gl "vendor:OpenGL"

/*
TEMPORARY RENDERER.

This is the second temporary renderer. It replaces the raylib one and it will
itself be replaced. It exists to move one thing into place: the render surface
is owned by the client application, and the engine draws into a handle it is
handed. Everything else here is scaffolding around that.

So it is deliberately stupid. One shader, one vertex format, one uniform upload
per draw, no batching, no material system, no resource tables, no texture
support. Adding any of that would be work thrown away when the real renderer
lands, and would make this file look load bearing when it is not.

The part that is not temporary is the shape of the boundary. Nothing above this
package knows OpenGL exists: the engine hands it matrices and meshes, and the
platform files beside it turn a native window handle into something drawable.
Replacing this renderer means replacing this package, not unpicking OpenGL out
of the rest of the engine.

GL 3.3 core is the floor. See the note in context_windows.odin about what the
context actually comes back as.
*/

// The version the shaders below are written against, and what the platform
// files ask the driver for. Kept here rather than in either of them so the two
// cannot drift apart.
GL_MAJOR :: 3
GL_MINOR :: 3

/*
Which windowing system the client's handle came from.

This is about the window, not the graphics API. A future renderer that is not
OpenGL needs exactly these same facts to attach to a client's window, so the
values are part of the engine's public ABI and must not be renumbered.

See the platform files for what the handle field has to contain for each, which
is not uniform: Wayland in particular wants a wl_egl_window rather than the
wl_surface you might expect.
*/
SurfaceKind :: enum u32 {
	WIN32   = 1,
	X11     = 2,
	WAYLAND = 3,
	// No window at all. The engine renders into its own framebuffer and the
	// client reads the pixels out with read_pixels.
	//
	// This exists for clients that cannot give the engine a window worth
	// drawing into. An Electron editor is the case in point: its window
	// belongs to Chromium, which presents through DirectComposition, and a
	// native child window placed over the page is composited underneath it by
	// DWM no matter where it sits in the window z order. Handing back pixels
	// sidesteps the entire argument, and has the side benefit that the client's
	// own UI can draw over the viewport, which it cannot do over a real window.
	//
	// A graphics context still has to exist, so the platform files make one
	// against a hidden drawable of their own. The client never sees it.
	OFFSCREEN = 4,
}

// Vertex format. Position and normal is the whole of it, which is what the
// single shader below consumes.
Vertex :: struct {
	position: [3]f32,
	normal:   [3]f32,
}

// A block of triangles on the GPU. No indices: the meshes this renderer draws
// are two cubes, and an index buffer would be more bookkeeping than it saves.
Mesh :: struct {
	vao, vbo:     u32,
	vertex_count: i32,
}

@(private)
VERTEX_SHADER :: `#version 330 core
layout(location = 0) in vec3 a_position;
layout(location = 1) in vec3 a_normal;

uniform mat4 u_model;
uniform mat4 u_view;
uniform mat4 u_projection;

out vec3 v_normal;

void main() {
	// inverse transpose so non uniform scale does not skew the normal. It is
	// per vertex here, which is wasteful, and would be a uniform in anything
	// that mattered.
	v_normal = mat3(transpose(inverse(u_model))) * a_normal;
	gl_Position = u_projection * u_view * u_model * vec4(a_position, 1.0);
}
`

@(private)
FRAGMENT_SHADER :: `#version 330 core
in vec3 v_normal;

uniform vec4 u_color;

out vec4 frag_color;

const vec3 LIGHT_DIRECTION = vec3(0.32, 0.80, 0.24);

void main() {
	// One hardcoded directional light and an ambient floor, so the faces of a
	// cube are told apart. This is not a lighting model, it is enough to see
	// that the geometry arrived.
	float lambert = max(dot(normalize(v_normal), normalize(LIGHT_DIRECTION)), 0.0);
	frag_color = vec4(u_color.rgb * (0.35 + 0.65 * lambert), u_color.a);
}
`

@(private)
state: struct {
	program:      u32,
	u_model:      i32,
	u_view:       i32,
	u_projection: i32,
	u_color:      i32,
	view:         matrix[4, 4]f32,
	projection:   matrix[4, 4]f32,
	initialized:  bool,

	// Offscreen mode only. Zero in window mode, where drawing goes to the
	// framebuffer the window owns.
	offscreen:     bool,
	fbo:           u32,
	color_texture: u32,
	depth_buffer:  u32,
	width, height: i32,
}

/*
Brings up the renderer on a surface the client application owns.

Inputs:
- kind: Which windowing system display and handle came from
- display: The native display connection, on the platforms that have one, nil on Windows
- handle: The native window handle to draw into, see the platform files for what it must hold
- width, height: The size of the drawable area in pixels

Outputs:
- bool True when a context was created and the renderer is ready to draw

Note:

The graphics context is made current on the calling thread and stays there, so
every later call into this package has to come from the same thread that called
init. This is a property of the context, not a choice made here.
*/
init :: proc(kind: SurfaceKind, display, handle: rawptr, width, height: i32) -> bool {
	if state.initialized {
		return true
	}
	if !_context_create(kind, display, handle) {
		return false
	}

	program, ok := gl.load_shaders_source(VERTEX_SHADER, FRAGMENT_SHADER)
	if !ok {
		_context_destroy()
		return false
	}
	state.program = program
	state.u_model = gl.GetUniformLocation(program, "u_model")
	state.u_view = gl.GetUniformLocation(program, "u_view")
	state.u_projection = gl.GetUniformLocation(program, "u_projection")
	state.u_color = gl.GetUniformLocation(program, "u_color")

	gl.Enable(gl.DEPTH_TEST)
	gl.Enable(gl.CULL_FACE)
	gl.CullFace(gl.BACK)
	gl.FrontFace(gl.CCW)
	gl.Viewport(0, 0, width, height)

	state.view = 1
	state.projection = 1
	state.width = width
	state.height = height
	state.offscreen = kind == .OFFSCREEN

	if state.offscreen && !_create_offscreen_target(width, height) {
		gl.DeleteProgram(program)
		_context_destroy()
		return false
	}

	state.initialized = true
	return true
}

/*
Builds the framebuffer that offscreen mode draws into.

A texture for colour rather than a renderbuffer, because a later version of
this will want to hand the texture to the client directly instead of reading it
back through the CPU, and a renderbuffer cannot be shared that way.
*/
@(private)
_create_offscreen_target :: proc(width, height: i32) -> bool {
	gl.GenFramebuffers(1, &state.fbo)
	gl.BindFramebuffer(gl.FRAMEBUFFER, state.fbo)

	gl.GenTextures(1, &state.color_texture)
	gl.BindTexture(gl.TEXTURE_2D, state.color_texture)
	gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA8, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, nil)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR)
	gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR)
	gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, state.color_texture, 0)

	gl.GenRenderbuffers(1, &state.depth_buffer)
	gl.BindRenderbuffer(gl.RENDERBUFFER, state.depth_buffer)
	gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH24_STENCIL8, width, height)
	gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.DEPTH_STENCIL_ATTACHMENT, gl.RENDERBUFFER, state.depth_buffer)

	complete := gl.CheckFramebufferStatus(gl.FRAMEBUFFER) == gl.FRAMEBUFFER_COMPLETE
	gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
	return complete
}

@(private)
_destroy_offscreen_target :: proc() {
	if state.fbo == 0 {
		return
	}
	gl.DeleteFramebuffers(1, &state.fbo)
	gl.DeleteTextures(1, &state.color_texture)
	gl.DeleteRenderbuffers(1, &state.depth_buffer)
	state.fbo = 0
	state.color_texture = 0
	state.depth_buffer = 0
}

/*
Tears the renderer down and releases the graphics context.

Note:

The window itself belongs to the client application and is left alone.
*/
destroy :: proc() {
	if !state.initialized {
		return
	}
	_destroy_offscreen_target()
	gl.DeleteProgram(state.program)
	_context_destroy()
	state.initialized = false
}

/*
Resizes the drawable area.

Inputs:
- width, height: The new size in pixels

Note:

The client application owns the window, so it is the only thing that knows a
resize happened. Nothing here can detect one.
*/
resize :: proc(width, height: i32) {
	if !state.initialized {
		return
	}
	state.width = width
	state.height = height
	if state.offscreen {
		// The attachments are fixed size, so a resize means new ones.
		_destroy_offscreen_target()
		_create_offscreen_target(width, height)
	}
	gl.Viewport(0, 0, width, height)
}

/*
Starts a frame, clearing colour and depth.

Inputs:
- clear: The background colour as linear RGBA
*/
begin_frame :: proc(clear: [4]f32) {
	// In offscreen mode the default framebuffer belongs to a hidden drawable
	// nobody will ever look at, so everything is aimed at the FBO instead.
	gl.BindFramebuffer(gl.FRAMEBUFFER, state.fbo if state.offscreen else 0)
	gl.Viewport(0, 0, state.width, state.height)
	gl.ClearColor(clear.r, clear.g, clear.b, clear.a)
	gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT)
	gl.UseProgram(state.program)
}

/*
Sets the matrices every later draw_mesh in this frame is seen through.

Inputs:
- view: The view matrix
- projection: The projection matrix
*/
set_camera :: proc(view, projection: matrix[4, 4]f32) {
	state.view = view
	state.projection = projection
}

/*
Draws a mesh.

Inputs:
- mesh: The mesh to draw
- model: The model matrix placing it in the world
- color: Flat albedo as linear RGBA

Note:

Every uniform is re-uploaded per call. With two cubes on screen that costs
nothing and keeps the call self contained.
*/
draw_mesh :: proc(mesh: Mesh, model: matrix[4, 4]f32, color: [4]f32) {
	model := model
	view := state.view
	projection := state.projection
	color := color

	gl.UniformMatrix4fv(state.u_model, 1, false, &model[0, 0])
	gl.UniformMatrix4fv(state.u_view, 1, false, &view[0, 0])
	gl.UniformMatrix4fv(state.u_projection, 1, false, &projection[0, 0])
	gl.Uniform4fv(state.u_color, 1, &color[0])

	gl.BindVertexArray(mesh.vao)
	gl.DrawArrays(gl.TRIANGLES, 0, mesh.vertex_count)
}

/*
Ends the frame and puts it on screen.
*/
end_frame :: proc() {
	gl.BindVertexArray(0)
	if state.offscreen {
		// Nothing to present. The frame sits in the FBO until read_pixels.
		return
	}
	_context_present()
}

/*
Copies the last rendered frame out of the offscreen framebuffer.

Inputs:
- dest: Where to write, which must have room for width * height * 4 bytes
- capacity: How many bytes dest can hold, checked rather than trusted

Outputs:
- int The number of bytes written, or 0 if nothing was

Note:

The format is RGBA, eight bits a channel, which is what a browser canvas wants
without further conversion.

The rows come out bottom to top, because that is the direction OpenGL numbers
them in. Anything expecting top down has to flip, and it is cheaper to do that
wherever the pixels are going than to reorder them here.

This stalls: it waits for the GPU to finish the frame and then drags it back
across the bus. That is the price of not having a window, and at editor
viewport sizes it is affordable, particularly since an editor has no reason to
redraw a still scene. The way out later is a pixel buffer object read one frame
behind, which turns the stall into a copy that overlaps the next frame.
*/
read_pixels :: proc(dest: rawptr, capacity: int) -> int {
	if !state.initialized || !state.offscreen || dest == nil {
		return 0
	}
	needed := int(state.width) * int(state.height) * 4
	if capacity < needed {
		return 0
	}

	gl.BindFramebuffer(gl.FRAMEBUFFER, state.fbo)
	// The default is 4 byte row alignment, which silently corrupts any image
	// whose width is not a multiple of four.
	gl.PixelStorei(gl.PACK_ALIGNMENT, 1)
	gl.ReadPixels(0, 0, state.width, state.height, gl.RGBA, gl.UNSIGNED_BYTE, dest)
	gl.BindFramebuffer(gl.FRAMEBUFFER, 0)
	return needed
}

/*
Uploads a triangle list to the GPU.

Inputs:
- vertices: The triangles, three vertices per triangle, wound counter clockwise
  as seen from outside

Outputs:
- Mesh The uploaded mesh, to be released with mesh_destroy
*/
mesh_create :: proc(vertices: []Vertex) -> Mesh {
	mesh: Mesh
	mesh.vertex_count = i32(len(vertices))

	gl.GenVertexArrays(1, &mesh.vao)
	gl.BindVertexArray(mesh.vao)

	gl.GenBuffers(1, &mesh.vbo)
	gl.BindBuffer(gl.ARRAY_BUFFER, mesh.vbo)
	gl.BufferData(gl.ARRAY_BUFFER, len(vertices) * size_of(Vertex), raw_data(vertices), gl.STATIC_DRAW)

	gl.EnableVertexAttribArray(0)
	gl.VertexAttribPointer(0, 3, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, position))
	gl.EnableVertexAttribArray(1)
	gl.VertexAttribPointer(1, 3, gl.FLOAT, false, size_of(Vertex), offset_of(Vertex, normal))

	gl.BindVertexArray(0)
	return mesh
}

/*
Releases a mesh.

Inputs:
- mesh: The mesh to release, zeroed on return
*/
mesh_destroy :: proc(mesh: ^Mesh) {
	gl.DeleteBuffers(1, &mesh.vbo)
	gl.DeleteVertexArrays(1, &mesh.vao)
	mesh^ = {}
}

/*
Builds an axis aligned box centred on its own origin.

Inputs:
- width, height, depth: The full extents of the box, not the half extents

Outputs:
- Mesh The uploaded mesh, to be released with mesh_destroy

Note:

This is the raylib GenMeshCube replacement, and the only primitive this
temporary renderer generates, because the temporary scene is two boxes.
*/
mesh_cube :: proc(width, height, depth: f32) -> Mesh {
	half := [3]f32{width, height, depth} * 0.5

	// Each face is a normal plus the two in plane axes, ordered so that
	// right cross up points along the normal. That makes the corner walk
	// below come out counter clockwise seen from outside for every face,
	// which is what the back face culling set up in init expects.
	Face :: struct {
		normal, right, up: [3]f32,
	}
	faces := [6]Face {
		{{0, 0, 1}, {1, 0, 0}, {0, 1, 0}},
		{{0, 0, -1}, {-1, 0, 0}, {0, 1, 0}},
		{{1, 0, 0}, {0, 0, -1}, {0, 1, 0}},
		{{-1, 0, 0}, {0, 0, 1}, {0, 1, 0}},
		{{0, 1, 0}, {1, 0, 0}, {0, 0, -1}},
		{{0, -1, 0}, {1, 0, 0}, {0, 0, 1}},
	}

	vertices: [36]Vertex
	count := 0
	for face in faces {
		centre := face.normal * half
		right := face.right * half
		up := face.up * half
		corners := [4][3]f32 {
			centre - right - up,
			centre + right - up,
			centre + right + up,
			centre - right + up,
		}
		for corner in ([6]int{0, 1, 2, 0, 2, 3}) {
			vertices[count] = {corners[corner], face.normal}
			count += 1
		}
	}
	return mesh_create(vertices[:])
}
