package component
import "../entity"
import "core:math/linalg"
import "../registry"
import "../error"
import "../mjson"
import "core:math"
import "core:encoding/json"

@(private) camera_manager: CameraManager

/*
Perspective projection. Objects shrink with distance.

- fovy: the vertical field of view, in DEGREES
*/
Perspective :: struct {
    fovy: f32,
}

/*
Orthographic projection. Objects keep their size regardless of distance.

- height: the vertical size of the view volume, in WORLD UNITS

Note:

This is not a field of view, the two modes take different quantities and that is
why they are separate types rather than one struct with a mode flag and a number
that means degrees or metres depending on the flag.
*/
Orthographic :: struct {
    height: f32,
}

/*
Which projection a Camera uses, and the parameters that projection needs.

A nil CameraProjection is a camera that has not been given a projection yet, and
any procedure that needs one will report .INVALID_CAMERA_PROJECTION.
*/
CameraProjection :: union {
    Perspective,
    Orthographic,
}

Camera :: struct {
    projection: CameraProjection,
}

@(private)
CameraManager :: struct {
    camera_registry: registry.Registry(Camera, entity.Id),
    main_camera: entity.Id,
    initialized: bool
}

/*
initializes the camera manager, must be called prior to any function that deals with cameras
a corresponding call to destroy_camera_manager must be called to cleanup

Note:

This individually initializes the camera manager
See also init_component_managers, which initializes all component mangers
*/
init_camera_manager :: proc() {
    if camera_manager.initialized {
        error.printf(.MANAGER_ALREADY_INITIALIZED, "initializing camera manager")
        return
    }
    registry.init_registry(&camera_manager.camera_registry, nil)
    camera_manager.initialized = true
}

/*
Destroys the camera manager, must be called at cleanup time to free the camera system

Note:

This individually destroys the camera manager
See also destroy_component_managers, which destroys all component mangers
*/
destroy_camera_manager :: proc() {
    if !camera_manager.initialized {
        error.printf(.DESTROYING_UNINITIALIZED_MANAGER, "destroying camera manager")
        return
    }
    registry.destroy_registry(&camera_manager.camera_registry)
    camera_manager.initialized = false
}

/*
Creates a Camera component for the entity specified by entity_id

Inputs:
- entity_id: entity.Id The Id of the entity to create a Camera for
- projection: CameraProjection The projection the camera uses, either a
  Perspective or an Orthographic

Note:

If the supplied entity_id is invalid the system will panic

See also camera_create_perspective and camera_create_orthographic, which name
the mode in the call rather than in the argument

Example:
    camera_create(id, Perspective{fovy = 45})
    camera_create(id, Orthographic{height = 10})
*/
camera_create :: proc(entity_id: entity.Id, projection: CameraProjection) {
    assert(camera_manager.initialized, "camera_create: camera manager not initialized, call init_camera_manager first")

    camera: Camera = {
        projection = projection
    }

    err := registry.create_item(&camera_manager.camera_registry, entity_id, camera)
    error.must(err)
}

/*
Creates a Camera component with a perspective projection

Inputs:
- entity_id: entity.Id The Id of the entity to create a Camera for
- fovy: f32 The vertical field of view, in degrees

Note:

If the supplied entity_id is invalid the system will panic
*/
camera_create_perspective :: proc(entity_id: entity.Id, fovy: f32) {
    camera_create(entity_id, Perspective{fovy = fovy})
}

/*
Creates a Camera component with an orthographic projection

Inputs:
- entity_id: entity.Id The Id of the entity to create a Camera for
- height: f32 The vertical size of the view volume, in world units

Note:

If the supplied entity_id is invalid the system will panic
*/
camera_create_orthographic :: proc(entity_id: entity.Id, height: f32) {
    camera_create(entity_id, Orthographic{height = height})
}

/*
Removes a Camera component from the entity specified by entity_id and frees the underlying memory

Inputs:
- entity_id: entity.Id The id of the entity whose Camera component will be destroyed

Note:

If the supplied entity_id is invalid, or has no corresponding Camera component the system will panic
*/
camera_destroy :: proc(entity_id: entity.Id) {
    assert(camera_manager.initialized, "camera_destroy: camera manager not initialized, call init_camera_manager first")
    camera, found := registry.get_item(&camera_manager.camera_registry, entity_id)
    error.must(found)
    registry.destroy_item(&camera_manager.camera_registry, entity_id)
}

/*
Returns the projection of the Camera component specified by the entity_id

Inputs:
- entity_id: entity.Id The id of the entity whose projection will be returned

Outputs:
- CameraProjection The projection of the Camera, a Perspective or an Orthographic

Note:

If the supplied entity_id is invalid, or has no corresponding Camera component the system will panic

Example:
    switch p in camera_get_projection(id) {
    case Perspective:  // p.fovy is degrees
    case Orthographic: // p.height is world units
    }
*/
camera_get_projection :: proc(entity_id: entity.Id) -> CameraProjection {
    assert(camera_manager.initialized, "camera_get_projection: camera manager not initialized, call init_camera_manager first")
    camera, found := registry.get_item(&camera_manager.camera_registry, entity_id)
    error.must(found)

    return camera.projection
}

/*
Sets the projection of the entity specified by entity_id's corresponding Camera component

Inputs:
- entity_id: entity.Id The id of the entity whose projection will be set
- projection: CameraProjection The projection to switch to, a Perspective or an Orthographic

Note:

If the supplied entity_id is invalid, or has no corresponding Camera component the system will panic
*/
camera_set_projection :: proc(entity_id: entity.Id, projection: CameraProjection) {
    assert(camera_manager.initialized, "camera_set_projection: camera manager not initialized, call init_camera_manager first")
    camera, found := registry.get_item(&camera_manager.camera_registry, entity_id)
    error.must(found)
    camera.projection = projection
}

/*
Reports whether the Camera component specified by entity_id is perspective

Inputs:
- entity_id: entity.Id The id of the entity whose Camera will be checked

Outputs:
- bool true when the camera projects with a Perspective

Note:

If the supplied entity_id is invalid, or has no corresponding Camera component the system will panic
*/
camera_is_perspective :: proc(entity_id: entity.Id) -> bool {
    _, ok := camera_get_projection(entity_id).(Perspective)
    return ok
}

/*
Reports whether the Camera component specified by entity_id is orthographic

Inputs:
- entity_id: entity.Id The id of the entity whose Camera will be checked

Outputs:
- bool true when the camera projects with an Orthographic

Note:

If the supplied entity_id is invalid, or has no corresponding Camera component the system will panic
*/
camera_is_orthographic :: proc(entity_id: entity.Id) -> bool {
    _, ok := camera_get_projection(entity_id).(Orthographic)
    return ok
}

/*
Returns the vertical field of view, in degrees, of the perspective Camera component specified by entity_id

Inputs:
- entity_id: entity.Id The id of the entity whose fovy will be returned

Outputs:
- f32 The fovy of the Camera, in degrees

Note:

If the supplied entity_id is invalid, has no corresponding Camera component, or
that camera is not a Perspective the system will panic. Guard with
camera_is_perspective, or read the projection with camera_get_projection when
either mode is possible
*/
camera_get_fovy :: proc(entity_id: entity.Id) -> f32 {
    assert(camera_manager.initialized, "camera_get_fovy: camera manager not initialized, call init_camera_manager first")
    camera, found := registry.get_item(&camera_manager.camera_registry, entity_id)
    error.must(found)
    perspective, ok := camera.projection.(Perspective)
    if !ok {
        error.must(.INVALID_CAMERA_PROJECTION)
    }
    return perspective.fovy
}

/*
Sets the vertical field of view, in degrees, of the perspective Camera component specified by entity_id

Inputs:
- entity_id: entity.Id The id of the entity whose fovy will be set
- fovy: f32 The vertical field of view, in degrees

Note:

If the supplied entity_id is invalid, has no corresponding Camera component, or
that camera is not a Perspective the system will panic. To change a camera from
orthographic to perspective, assign a whole projection with camera_set_projection
*/
camera_set_fovy :: proc(entity_id: entity.Id, fovy: f32) {
    assert(camera_manager.initialized, "camera_set_fovy: camera manager not initialized, call init_camera_manager first")
    camera, found := registry.get_item(&camera_manager.camera_registry, entity_id)
    error.must(found)
    if _, ok := camera.projection.(Perspective); !ok {
        error.must(.INVALID_CAMERA_PROJECTION)
    }
    camera.projection = Perspective{fovy = fovy}
}

/*
Returns the vertical size of the view volume, in world units, of the orthographic
Camera component specified by entity_id

Inputs:
- entity_id: entity.Id The id of the entity whose height will be returned

Outputs:
- f32 The height of the view volume, in world units

Note:

If the supplied entity_id is invalid, has no corresponding Camera component, or
that camera is not an Orthographic the system will panic. Guard with
camera_is_orthographic, or read the projection with camera_get_projection when
either mode is possible
*/
camera_get_orthographic_height :: proc(entity_id: entity.Id) -> f32 {
    assert(camera_manager.initialized, "camera_get_orthographic_height: camera manager not initialized, call init_camera_manager first")
    camera, found := registry.get_item(&camera_manager.camera_registry, entity_id)
    error.must(found)
    orthographic, ok := camera.projection.(Orthographic)
    if !ok {
        error.must(.INVALID_CAMERA_PROJECTION)
    }
    return orthographic.height
}

/*
Sets the vertical size of the view volume, in world units, of the orthographic
Camera component specified by entity_id

Inputs:
- entity_id: entity.Id The id of the entity whose height will be set
- height: f32 The vertical size of the view volume, in world units

Note:

If the supplied entity_id is invalid, has no corresponding Camera component, or
that camera is not an Orthographic the system will panic. To change a camera from
perspective to orthographic, assign a whole projection with camera_set_projection
*/
camera_set_orthographic_height :: proc(entity_id: entity.Id, height: f32) {
    assert(camera_manager.initialized, "camera_set_orthographic_height: camera manager not initialized, call init_camera_manager first")
    camera, found := registry.get_item(&camera_manager.camera_registry, entity_id)
    error.must(found)
    if _, ok := camera.projection.(Orthographic); !ok {
        error.must(.INVALID_CAMERA_PROJECTION)
    }
    camera.projection = Orthographic{height = height}
}

/*
Returns the Id of the main camera

Outputs:
- entity.Id The id of the entity the main camera is attached to
- error.Code The error state returned no error if .NONE .NO_MAIN_CAMERA_SET if the main camera is invalid or unassigned

Note:

If the supplied entity_id is invalid, or has no corresponding Camera component the system will panic
*/
@(require_results)
get_main_camera :: proc() -> (entity.Id, error.Code) {
    assert(camera_manager.initialized, "get_main_camera: camera manager not initialized, call init_camera_manager first")
    if camera_manager.main_camera <= registry.INVALID_ID {
        return registry.INVALID_ID, .NO_MAIN_CAMERA_SET
    }
    return camera_manager.main_camera, .NONE
}

/*
Sets the main camera

Inputs:
- entity_id: entity.Id The id of the entity the camera is attached to

Outputs:
- error.Code The error state returned no error if .NONE .INVALID_CAMERA if the specified Id is invalid

Note:

If the supplied entity_id is invalid, or has no corresponding Camera component the system will panic
*/
@(require_results)
set_main_camera :: proc(entity_id: entity.Id) -> error.Code {
    assert(camera_manager.initialized, "set_main_camera: camera manager not initialized, call init_camera_manager first")
    if entity_id <= registry.INVALID_ID {
        return .INVALID_CAMERA
    }
    _, found := registry.get_item(&camera_manager.camera_registry, entity_id)
    error.must(found)
    camera_manager.main_camera = entity_id
    return .NONE
}

/*
Returns the View Matrix of the camera

Inputs:
- entity_id: entity.Id The id of the camera

Outputs:
- matrix[4,4]f32 The view matrix of the camera

Note

If the supplied entity_id is invalid, or has no corresponding Camera component the system will panic
*/
camera_get_view_matrix :: proc(entity_id: entity.Id) -> matrix[4,4]f32 {
    assert(camera_manager.initialized, "camera_get_view_matrix: camera manager not initialized, call init_camera_manager first")
    return _transform_get_view_matrix(entity_id)
}

/*
Returns the Projection Matrix of the camera

Inputs:
- entity_id: entity.Id The id of the camera

Outputs:
- matrix[4,4]f32 The projection matrix of the camera

Note

If the supplied entity_id is invalid, or has no corresponding Camera component the system will panic

A Perspective builds a frustum from its fovy, converted from degrees to radians
here. An Orthographic builds a box from its height, which is already in world
units and needs no conversion. Both take their horizontal extent from aspect
*/
camera_get_projection_matrix :: proc(entity_id: entity.Id, aspect, near, far: f32) -> matrix[4,4]f32 {
    assert(camera_manager.initialized, "camera_get_projection_matrix: camera manager not initialized, call init_camera_manager first")
    camera, found := registry.get_item(&camera_manager.camera_registry, entity_id)
    error.must(found)
    switch projection in camera.projection {
    case Perspective:
        return linalg.matrix4_perspective(math.to_radians_f32(projection.fovy), aspect, near, far)
    case Orthographic:
        top := projection.height * 0.5
        right := top * aspect
        return linalg.matrix_ortho3d(-right, right, -top, top, near, far)
    }
    error.must(.INVALID_CAMERA_PROJECTION) // the union is nil, the camera was never given a projection
    return {} // Unreachable kkk must add error.throw at some stage
}

/*
The begin_draw and end_draw procedures that used to live here were raylib's
BeginMode3D and EndMode3D wrapped up, and they are gone with it. A camera does
not begin or end anything now, it answers with a view matrix and a projection
matrix and the renderer decides what to do with them.

camera_get_view_matrix and camera_get_projection_matrix above are the
replacement, and they already existed.
*/
/*
Reads a camera block. The projection key picks the mode, and the mode decides
which other key is required:

	camera = { projection = "PERSPECTIVE"  fovy = 45.0   main = true }
	camera = { projection = "ORTHOGRAPHIC" height = 10.0 }

A perspective block with a height, or an orthographic block with a fovy, is a
parse error rather than a silently ignored key.
*/
camera_from_mjson :: proc(entity_id: entity.Id, value: json.Value) -> error.Code {
	obj := mjson.as_object(value) or_return
	proj_str := mjson.as_string(obj["projection"]) or_return

	projection: CameraProjection
	switch proj_str {
	case "PERSPECTIVE":
		fovy := mjson.as_float(obj["fovy"]) or_return
		projection = Perspective{fovy = f32(fovy)}
	case "ORTHOGRAPHIC":
		height := mjson.as_float(obj["height"]) or_return
		projection = Orthographic{height = f32(height)}
	case:
		return .PARSE_ERROR
	}

	camera_create(entity_id, projection)

	if main_val, has_main := obj["main"]; has_main {
		if is_main, ok := main_val.(json.Boolean); ok && bool(is_main) {
			return set_main_camera(entity_id)
		}
	}
	return .NONE
}
