package main
import b3 "vendor:box3d"
import "vendor:raylib"
import "base:runtime"
import "core:math/linalg"
import "core:math"
import "file"
import "config"
import "scene"
import "entity"
import "error"
import "component"

@(private) engine_ctx: runtime.Context


@(export, link_name="engine_init")
init :: proc "c" () -> bool {
    engine_ctx = runtime.default_context()
    context = engine_ctx
    config.load_config()
    file.load_asset_pack()
    scene.init_scene_manager()
    component.init_component_managers()
    _temp_init()
    return true
}

@(export, link_name="engine_tick")
tick :: proc "c" () -> bool {
    context = engine_ctx
    _temp_tick()
    return true   
}

@(export, link_name="engine_destroy")
destroy :: proc "c" () -> bool {
    context = engine_ctx
    component.destroy_component_managers()
    scene.destroy_scene_manager()
    file.release_asset_pack()
    _temp_destroy()    
    return true
}

@(export, link_name="engine_stop")
stop :: proc "c" () -> bool {
    context = engine_ctx
    return raylib.WindowShouldClose()
}



////////////////////TEMP TEST STUFF///////////////////////////////
@(private) camera: entity.Id
@(private) world_id: b3.WorldId
@(private) ground_id, box_id: b3.BodyId
@(private) ground_model, box_model: raylib.Model

MOUSE_SENSITIVITY :: 0.003
PITCH_LIMIT_DEGREES :: 89


_temp_init :: proc() {
    raylib.InitWindow(1280, 720, "InkyPinky")
    raylib.SetTargetFPS(60)
    raylib.DisableCursor()
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

    ground_model = raylib.LoadModelFromMesh(raylib.GenMeshCube(50, 1, 50))
    box_model = raylib.LoadModelFromMesh(raylib.GenMeshCube(1, 1, 1))

    box_model.materials[0].maps[raylib.MaterialMapIndex.ALBEDO].color = raylib.RED
}

_temp_tick :: proc() {
    b3.World_Step(world_id, 1.0 / 60.0, 4)
    cam_pos := component.transform_get_position(camera)
    handle_input(camera, cam_pos)
    handle_mouse(camera)

    raylib.BeginDrawing()
    raylib.ClearBackground(raylib.SKYBLUE)
    raylib.DrawFPS(100, 100)

    component.main_camera_begin_draw()
    
    gt := b3.Body_GetTransform(ground_id)
    ground_mat := raylib.MatrixCompose(raylib.Vector3(gt.p), raylib.Quaternion(gt.q), {1, 1, 1})
    raylib.DrawMesh(ground_model.meshes[0], ground_model.materials[0], ground_mat)

    bt := b3.Body_GetTransform(box_id)
    box_mat := raylib.MatrixCompose(raylib.Vector3(bt.p), raylib.Quaternion(bt.q), {1, 1, 1})
    raylib.DrawMesh(box_model.meshes[0], box_model.materials[0], box_mat)

    component.camera_end_draw()
    raylib.EndDrawing()
}

_temp_destroy :: proc() {
    b3.DestroyWorld(world_id)
    raylib.UnloadModel(ground_model)
    raylib.UnloadModel(box_model)
    raylib.CloseWindow()
}


handle_input :: proc(main_camera: entity.Id, curr_pos: [3]f32) {
	up := component.transform_get_up_local(main_camera)
	right := component.transform_get_right_local(main_camera)
	forward := component.transform_get_forward_local(main_camera)
	delta_d := [3]f32 {0, 0, 0}
	if raylib.IsKeyDown(raylib.KeyboardKey.W) {
		delta_d += forward
	}
	if raylib.IsKeyDown(raylib.KeyboardKey.S) {
		delta_d -= forward
	}

	if raylib.IsKeyDown(raylib.KeyboardKey.A) {
		delta_d -= right
	}
	if raylib.IsKeyDown(raylib.KeyboardKey.D) {
		delta_d += right
	}

	if raylib.IsKeyDown(raylib.KeyboardKey.SPACE) {
		delta_d += up
	}
	if raylib.IsKeyDown(raylib.KeyboardKey.LEFT_SHIFT) {
		delta_d -= up
	}
	component.transform_set_position(main_camera, curr_pos + delta_d)
}

handle_mouse :: proc(main_camera: entity.Id) {
	delta := raylib.GetMouseDelta()
	if delta.x == 0 && delta.y == 0 {
		return
	}

	// yaw about the global up, so the horizon never tilts
	yaw := -delta.x * MOUSE_SENSITIVITY
	component.transform_rotate(main_camera, linalg.quaternion_angle_axis(yaw, component.GLOBAL_UP))

	// pitch about the camera's own right axis, stopping short of straight up/down
	limit := math.to_radians_f32(PITCH_LIMIT_DEGREES)
	forward := component.transform_get_forward_local(main_camera)
	pitch_now := math.asin_f32(clamp(forward.y, -1, 1))
	pitch := clamp(-delta.y * MOUSE_SENSITIVITY, -limit - pitch_now, limit - pitch_now)
	component.transform_rotate_local(main_camera, linalg.quaternion_angle_axis(pitch, component.GLOBAL_RIGHT))
}

