package component
import "../entity"
import "core:math/linalg"
import "../registry"
import "../error"
import "core:math"
import rl "vendor:raylib"

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
    initilized: bool
}

/*
Initilizes the camera manager, must be called prior to any function that deals with cameras
a corresponding call to destroy_camera_manager must be called to cleanup

Note:

This individually intilizes the camera manager
See also init_component_managers, which initilizes all component mangers
*/
init_camera_manager :: proc() {
    if camera_manager.initilized {
        error.printf(.MANAGER_ALREADY_INITILIZED, "initilizing camera manager")
        return
    }
    registry.init_registry(&camera_manager.camera_registry, nil)
    camera_manager.initilized = true
}

/*
Destroys the camera manager, must be called at cleanup time to free the camera system

Note:

This individually destroys the camera manager
See also destroy_component_managers, which destroys all component mangers
*/
destroy_camera_manager :: proc() {
    if !camera_manager.initilized {
        error.printf(.DESTROYING_UNINITILIZED_MANAGER, "destroying camera manager")
        return
    }
    registry.destroy_registry(&camera_manager.camera_registry)
    camera_manager.initilized = false
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
    assert(camera_manager.initilized, "camera_create: camera manager not initilized, call init_camera_manager first")
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
    assert(camera_manager.initilized, "camera_destroy: camera manager not initilized, call init_camera_manager first")
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
    assert(camera_manager.initilized, "camera_get_fovy: camera manager not initilized, call init_camera_manager first")
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
    assert(camera_manager.initilized, "camera_get_projection: camera manager not initilized, call init_camera_manager first")
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
    assert(camera_manager.initilized, "camera_set_fovy: camera manager not initilized, call init_camera_manager first")
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
    assert(camera_manager.initilized, "camera_set_projection: camera manager not initilized, call init_camera_manager first")
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
    assert(camera_manager.initilized, "get_main_camera: camera manager not initilized, call init_camera_manager first")
    if camera_manager.main_camera <= registry.UNASSIGNED_ID {
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
    assert(camera_manager.initilized, "set_main_camera: camera manager not initilized, call init_camera_manager first")
    if entity_id <= registry.UNASSIGNED_ID {
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
    assert(camera_manager.initilized, "camera_get_view_matrix: camera manager not initilized, call init_camera_manager first")
    camera, found := registry.get_item(&camera_manager.camera_registry, entity_id)
    error.must(found)
    pos := transform_get_position(entity_id)
    up, _, forward := transform_get_orientation_local(entity_id)
    return linalg.matrix4_look_at(pos, pos + forward, up)
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
    assert(camera_manager.initilized, "camera_get_projection_matrix: camera manager not initilized, call init_camera_manager first")
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
 * This is temp while raylib is acting as the renderer
 */
main_camera_begin_draw :: proc() {
    assert(camera_manager.initilized, "main_camera_begin_draw: camera manager not initilized, call init_camera_manager first")
    camera, camera_found := registry.get_item(&camera_manager.camera_registry, camera_manager.main_camera)
    error.must(camera_found)

    pos := transform_get_position(camera_manager.main_camera)
    up, _, forward := transform_get_orientation_local(camera_manager.main_camera)

    rl.BeginMode3D({
        fovy = camera.fovy,
        projection = .PERSPECTIVE if camera.projection == .PERSPECTIVE else .ORTHOGRAPHIC,
        position = pos,
        target = pos + forward,
        up = up
    })
}

camera_begin_draw :: proc(entity_id: entity.Id) {
    assert(camera_manager.initilized, "camera_begin_draw: camera manager not initilized, call init_camera_manager first")
    camera, camera_found := registry.get_item(&camera_manager.camera_registry, entity_id)
    error.must(camera_found)

    pos := transform_get_position(entity_id)
    up, _, forward := transform_get_orientation_local(entity_id)

    rl.BeginMode3D({
        fovy = camera.fovy,
        projection = .PERSPECTIVE if camera.projection == .PERSPECTIVE else .ORTHOGRAPHIC,
        position = pos,
        target = pos + forward,
        up = up
    })
}

/*
 * This is temp while raylib is acting as the renderer
 */
camera_end_draw :: proc() {
    rl.EndMode3D()
}
