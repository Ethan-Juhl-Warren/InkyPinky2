package component
import "../entity"
import "core:math/linalg"
import "../registry"
import "../error"
import "../mjson"
import "core:math"
import "core:encoding/json"

@(private) camera_manager: CameraManager

CameraProjection :: enum {
    PERSPECTIVE,
    ORTHOGRAPHIC
}

Camera :: struct {
    fovy: f32,
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
- entity_id: entity.Id The Id of the entity to create a Transform for
- fovy: f32 The vertical field of view of the camera
- projection: CameraProjection The projection mode of the camera

Note:

If the supplied entity_id is invalid the system will panic
*/
camera_create :: proc(entity_id: entity.Id, fovy: f32, projection: CameraProjection) {
    assert(camera_manager.initialized, "camera_create: camera manager not initialized, call init_camera_manager first")
    valid := transform_exists(entity_id)
    if !valid {
        error.must(.ADDING_CAMERA_TO_ENTITY_WITH_NO_TRANSFORM)
    }

    camera: Camera = {
        fovy,
        projection
    }

    err := registry.create_item(&camera_manager.camera_registry, entity_id, camera)
    error.must(err)
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
Returns the vertical field of view of the Camera component specified by the entity_id

Inputs:
- entity_id: entity.Id The id of the entity whose fovy will be returned

Outputs:
- f32 The fovy of the Camera

Note:

If the supplied entity_id is invalid, or has no corresponding Camera component the system will panic
*/
camera_get_fovy :: proc(entity_id: entity.Id) -> f32 {
    assert(camera_manager.initialized, "camera_get_fovy: camera manager not initialized, call init_camera_manager first")
    camera, err := registry.get_item(&camera_manager.camera_registry, entity_id)
    error.must(err)
    return camera.fovy
}

/*
Returns the projection mode of the Camera component specified by the entity_id

Inputs:
- entity_id: entity.Id The id of the entity whose Projection will be returned

Outputs:
- CameraProjection The Projection mode of the Camera

Note:

If the supplied entity_id is invalid, or has no corresponding Camera component the system will panic
*/
camera_get_projection :: proc(entity_id: entity.Id) -> CameraProjection {
    assert(camera_manager.initialized, "camera_get_projection: camera manager not initialized, call init_camera_manager first")
    camera, found := registry.get_item(&camera_manager.camera_registry, entity_id)
    error.must(found)

    return camera.projection
}

/*
Sets the vertical field of view f32 of the entity specified by entity_id's corresponding Camera component

Inputs:
- entity_id: entity.Id The id of the entity whose fovy will be set

Note:

If the supplied entity_id is invalid, or has no corresponding Camera component the system will panic
*/
camera_set_fovy :: proc(entity_id: entity.Id, fovy: f32) {
    assert(camera_manager.initialized, "camera_set_fovy: camera manager not initialized, call init_camera_manager first")
    camera, found := registry.get_item(&camera_manager.camera_registry, entity_id)
    error.must(found)
    camera.fovy = fovy
}

/*
Sets the Projection mode CameraProjection of the entity specified by entity_id's corresponding Camera component

Inputs:
- entity_id: entity.Id The id of the entity whose projection mode will be set

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
*/
camera_get_projection_matrix :: proc(entity_id: entity.Id, aspect, near, far: f32) -> matrix[4,4]f32 {
    assert(camera_manager.initialized, "camera_get_projection_matrix: camera manager not initialized, call init_camera_manager first")
    camera, found := registry.get_item(&camera_manager.camera_registry, entity_id)
    error.must(found)
    switch camera.projection {
    case .PERSPECTIVE:
        return linalg.matrix4_perspective(math.to_radians_f32(camera.fovy), aspect, near, far)
    case .ORTHOGRAPHIC:
        top := camera.fovy * 0.5
        right := top * aspect
        return linalg.matrix_ortho3d(-right, right, -top, top, near, far)
    }
    error.must(.INVALID_CAMERA_PROJECTION)
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



camera_from_mjson :: proc(entity_id: entity.Id, value: json.Value) -> error.Code {
	obj := mjson.as_object(value) or_return
	fovy_val := mjson.as_float(obj["fovy"]) or_return
	proj_str := mjson.as_string(obj["projection"]) or_return

	projection: CameraProjection
	switch proj_str {
	case "PERSPECTIVE":
		projection = .PERSPECTIVE
	case "ORTHOGRAPHIC":
		projection = .ORTHOGRAPHIC
	case:
		return .PARSE_ERROR
	}

	camera_create(entity_id, f32(fovy_val), projection)

	if main_val, has_main := obj["main"]; has_main {
		if is_main, ok := main_val.(json.Boolean); ok && bool(is_main) {
			return set_main_camera(entity_id)
		}
	}
	return .NONE
}
