package main

import rl "vendor:raylib"
import b3 "vendor:box3d"
import cmpt "component"
import "core:math"
import "core:math/linalg"
import "error"
import "entity"

MOUSE_SENSITIVITY :: 0.003
PITCH_LIMIT_DEGREES :: 89

main :: proc() {
	rl.InitWindow(1280, 720, "Box3D + raylib")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)
	rl.DisableCursor()

	// Init entity manager
	entity.init_entity_manager()
	defer entity.destroy_entity_manager()

	// Init Components
	cmpt.init_component_managers()
	defer cmpt.destroy_component_managers()

	main_camera := entity.create("main camera") 
	cmpt.transform_create(main_camera, {0, 10, 20}, {1, 1, 1}, linalg.QUATERNIONF32_IDENTITY)
	cmpt.camera_create(main_camera, 45, .PERSPECTIVE)
	camera_error := cmpt.set_main_camera(main_camera)
	error.must(camera_error)

	// --- Box3D world ---
	world_def := b3.DefaultWorldDef()
	world_def.gravity = {0, -10, 0}
	world_id := b3.CreateWorld(world_def)
	defer b3.DestroyWorld(world_id)

	// Static ground
	ground_def := b3.DefaultBodyDef()
	ground_def.position = {0, -0.5, 0}
	ground_id := b3.CreateBody(world_id, ground_def)
	ground_hull := b3.MakeBoxHull(25, 0.5, 25) // half-extents
	ground_shape_def := b3.DefaultShapeDef()
	_ = b3.CreateHullShape(ground_id, ground_shape_def, &ground_hull.base)

	// Dynamic falling box
	box_def := b3.DefaultBodyDef()
	box_def.type = .dynamicBody
	box_def.position = {0, 8, 0}
	box_id := b3.CreateBody(world_id, box_def)
	box_hull := b3.MakeBoxHull(0.5, 0.5, 0.5)
	box_shape_def := b3.DefaultShapeDef()
	box_shape_def.density = 1.0
	_ = b3.CreateHullShape(box_id, box_shape_def, &box_hull.base)

	// --- Raylib meshes matching the hull sizes (full extents, not half) ---
	ground_model := rl.LoadModelFromMesh(rl.GenMeshCube(50, 1, 50))
	defer rl.UnloadModel(ground_model)

	box_model := rl.LoadModelFromMesh(rl.GenMeshCube(1, 1, 1))
	defer rl.UnloadModel(box_model)
	box_model.materials[0].maps[rl.MaterialMapIndex.ALBEDO].color = rl.RED
	
	for !rl.WindowShouldClose() {
		b3.World_Step(world_id, 1.0 / 60.0, 4)
		cam_pos := cmpt.transform_get_position(main_camera)
		handle_input(main_camera, cam_pos)
		handle_mouse(main_camera)

		rl.BeginDrawing()
		rl.ClearBackground(rl.SKYBLUE)
		rl.DrawFPS(100, 100)

		error.print(cmpt.main_camera_begin_draw())
		defer cmpt.camera_end_draw()
		
		gt := b3.Body_GetTransform(ground_id)
		ground_mat := rl.MatrixCompose(rl.Vector3(gt.p), rl.Quaternion(gt.q), {1, 1, 1})
		rl.DrawMesh(ground_model.meshes[0], ground_model.materials[0], ground_mat)

		bt := b3.Body_GetTransform(box_id)
		box_mat := rl.MatrixCompose(rl.Vector3(bt.p), rl.Quaternion(bt.q), {1, 1, 1})
		rl.DrawMesh(box_model.meshes[0], box_model.materials[0], box_mat)

		//rl.EndMode3D()
		rl.EndDrawing()
	}
}

handle_input :: proc(main_camera: entity.Id, curr_pos: [3]f32) {
	up := cmpt.transform_get_up_local(main_camera)
	right := cmpt.transform_get_right_local(main_camera)
	forward := cmpt.transform_get_forward_local(main_camera)
	delta_d := [3]f32 {0, 0, 0}
	if rl.IsKeyDown(rl.KeyboardKey.W) {
		delta_d += forward
	}
	if rl.IsKeyDown(rl.KeyboardKey.S) {
		delta_d -= forward
	}

	if rl.IsKeyDown(rl.KeyboardKey.A) {
		delta_d -= right
	}
	if rl.IsKeyDown(rl.KeyboardKey.D) {
		delta_d += right
	}

	if rl.IsKeyDown(rl.KeyboardKey.SPACE) {
		delta_d += up
	}
	if rl.IsKeyDown(rl.KeyboardKey.LEFT_SHIFT) {
		delta_d -= up
	}
	cmpt.transform_set_position(main_camera, curr_pos + delta_d)
}

handle_mouse :: proc(main_camera: entity.Id) {
	delta := rl.GetMouseDelta()
	if delta.x == 0 && delta.y == 0 {
		return
	}

	// yaw about the global up, so the horizon never tilts
	yaw := -delta.x * MOUSE_SENSITIVITY
	cmpt.transform_rotate(main_camera, linalg.quaternion_angle_axis(yaw, cmpt.GLOBAL_UP))

	// pitch about the camera's own right axis, stopping short of straight up/down
	limit := math.to_radians_f32(PITCH_LIMIT_DEGREES)
	forward := cmpt.transform_get_forward_local(main_camera)
	pitch_now := math.asin_f32(clamp(forward.y, -1, 1))
	pitch := clamp(-delta.y * MOUSE_SENSITIVITY, -limit - pitch_now, limit - pitch_now)
	cmpt.transform_rotate_local(main_camera, linalg.quaternion_angle_axis(pitch, cmpt.GLOBAL_RIGHT))
}