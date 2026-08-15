package component
import "../entity"
import "../registry"
import "../error"
import rl "vendor:raylib"

@(private) camera_manager: CameraManager

CameraProjection :: enum {
    NONE = 0,
    PERSPECTIVE,
    ORTHOGRAPHIC
}

Camera :: struct {
    rl_camera: rl.Camera3D
}

@(private)
CameraManager :: struct {
    camera_registry: registry.Registry(Camera, entity.Id),
    main_camera: entity.Id,
    initilized: bool
}

init_camera_manager :: proc() {
    if camera_manager.initilized {
        error.printf(.MANAGER_ALREADY_INITILIZED, "initilizing camera manager")
        return
    }
    registry.init_registry(&camera_manager.camera_registry, nil)
    camera_manager.initilized = true
}

destroy_camera_manager :: proc() {
    if !camera_manager.initilized {
        error.printf(.DESTROYING_UNINITILIZED_MANAGER, "destroying camera manager")
        return
    }
    registry.destroy_registry(&camera_manager.camera_registry)
    camera_manager.initilized = false
}

camera_create :: proc(entity_id: entity.Id, target: [3]f32, up: [3]f32, fovy: f32, projection: CameraProjection) -> error.Code {
    assert(camera_manager.initilized, "camera_create: camera manager not initilized, call init_camera_manager first")
    camera: Camera

    proj: rl.CameraProjection
    if projection == CameraProjection.PERSPECTIVE {
        proj = rl.CameraProjection.PERSPECTIVE
    } else if projection == CameraProjection.ORTHOGRAPHIC {
        proj = rl.CameraProjection.ORTHOGRAPHIC
    } else {
        error.must(.ADDING_CAMERA_TO_ENTITY_WITH_NO_TRANSFORM)
    }

    position := transform_get_position(entity_id)

    camera.rl_camera = rl.Camera3D {
        position = position,
        target = target,
        up = up,
        fovy = fovy,
        projection = proj
    }

    err := registry.create_item(&camera_manager.camera_registry, entity_id, camera)
    error.must(err)
    return .NONE
}

camera_destroy :: proc(entity_id: entity.Id) {
    assert(camera_manager.initilized, "camera_destroy: camera manager not initilized, call init_camera_manager first")

    camera, found := registry.get_item(&camera_manager.camera_registry, entity_id)
    error.must(found)

    registry.destroy_item(&camera_manager.camera_registry, entity_id)
}

camera_get_fovy :: proc(entity_id: entity.Id) -> f32 {
    assert(camera_manager.initilized, "camera_get_fovy: camera manager not initilized, call init_camera_manager first")
    camera, err := registry.get_item(&camera_manager.camera_registry, entity_id)
    error.must(err)
    return camera.rl_camera.fovy
}

camera_get_projection :: proc(entity_id: entity.Id) -> CameraProjection {
    assert(camera_manager.initilized, "camera_get_projection: camera manager not initilized, call init_camera_manager first")
    camera, found := registry.get_item(&camera_manager.camera_registry, entity_id)
    error.must(found)

    if camera.rl_camera.projection == rl.CameraProjection.PERSPECTIVE {
        return CameraProjection.PERSPECTIVE
    } else if camera.rl_camera.projection == rl.CameraProjection.ORTHOGRAPHIC {
        return CameraProjection.ORTHOGRAPHIC
    } else {
        return CameraProjection.NONE
    }
}

camera_set_fovy :: proc(entity_id: entity.Id, fovy: f32) {
    assert(camera_manager.initilized, "camera_set_fovy: camera manager not initilized, call init_camera_manager first")
    camera, found := registry.get_item(&camera_manager.camera_registry, entity_id)
    error.must(found)
    camera.rl_camera.fovy = fovy
}

camera_set_target :: proc(entity_id: entity.Id, target: [3]f32) {
    assert(camera_manager.initilized, "camera_set_target: camera manager not initilized, call init_camera_manager first")
    camera, found := registry.get_item(&camera_manager.camera_registry, entity_id)
    error.must(found)
    camera.rl_camera.target = target
}

camera_set_projection :: proc(entity_id: entity.Id, projection: CameraProjection) {
    assert(camera_manager.initilized, "camera_set_projection: camera manager not initilized, call init_camera_manager first")
    camera, found := registry.get_item(&camera_manager.camera_registry, entity_id)
    error.must(found)

    if camera.rl_camera.projection == rl.CameraProjection.PERSPECTIVE {
        camera.rl_camera.projection = rl.CameraProjection.PERSPECTIVE
    } else if camera.rl_camera.projection == rl.CameraProjection.ORTHOGRAPHIC {
        camera.rl_camera.projection = rl.CameraProjection.ORTHOGRAPHIC
    } else {
        error.must(.INVALID_CAMERA_PROJECTION)
    }
}

@(require_results)
get_main_camera :: proc() -> (entity.Id, error.Code) {
    assert(camera_manager.initilized, "get_main_camera: camera manager not initilized, call init_camera_manager first")
    if camera_manager.main_camera <= registry.UNASSIGNED_ID {
        return registry.INVALID_ID, .NO_MAIN_CAMERA_SET
    }
    return camera_manager.main_camera, .NONE
}

@(require_results)
set_main_camera :: proc(entity_id: entity.Id) -> error.Code {
    assert(camera_manager.initilized, "set_main_camera: camera manager not initilized, call init_camera_manager first")
    if entity_id <= registry.UNASSIGNED_ID {
        return .INVALID_CAMERA
    }
    camera_manager.main_camera = entity_id
    return .NONE
}

/*
 * This is temp while raylib is acting as the renderer
 */
main_camera_begin_draw :: proc() -> error.Code {
    assert(camera_manager.initilized, "main_camera_begin_draw: camera manager not initilized, call init_camera_manager first")
    if camera_manager.main_camera <= registry.UNASSIGNED_ID {
        return .INVALID_CAMERA
    }
    camera, found := registry.get_item(&camera_manager.camera_registry, camera_manager.main_camera)
    error.must(found)

    pos := transform_get_position(camera_manager.main_camera)
    
    camera.rl_camera.position = pos
    rl.BeginMode3D(camera.rl_camera)
    return .NONE
}

/*
 * This is temp while raylib is acting as the renderer
 */
camera_end_draw :: proc() {
    rl.EndMode3D()
}
