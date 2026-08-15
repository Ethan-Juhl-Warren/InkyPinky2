package main

import rl "vendor:raylib"
import b3 "vendor:box3d"
import cmpt "component"
import "core:math"
import "error"
import "entity"

main :: proc() {
	rl.InitWindow(1280, 720, "Box3D + raylib")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	// Init entity manager
	entity.init_entity_manager()
	defer entity.destroy_entity_manager()

	// Init Components
	cmpt.init_component_managers()
	defer cmpt.destroy_component_managers()

	main_camera := entity.create("main camera") 
	cmpt.transform_create(main_camera, {0, 10, 20}, {1, 1, 1}, {0, 0, 0})
	cmpt.camera_create(main_camera, {0, 0, 0}, {0, 1, 0}, 45, .PERSPECTIVE)
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
	if rl.IsKeyDown(rl.KeyboardKey.W) {
		cmpt.transform_set_position(main_camera, curr_pos + {0,0,1})
	}
	if rl.IsKeyDown(rl.KeyboardKey.S) {
		cmpt.transform_set_position(main_camera, curr_pos + {0,0,-1})
	}

	if rl.IsKeyDown(rl.KeyboardKey.A) {
		cmpt.transform_set_position(main_camera, curr_pos + {1,0,0})
	}
	if rl.IsKeyDown(rl.KeyboardKey.D) {
		cmpt.transform_set_position(main_camera, curr_pos + {-1,0,0})
	}

	if rl.IsKeyDown(rl.KeyboardKey.SPACE) {
		cmpt.transform_set_position(main_camera, curr_pos + {0,1,0})
	}
	if rl.IsKeyDown(rl.KeyboardKey.LEFT_SHIFT) {
		cmpt.transform_set_position(main_camera, curr_pos + {0, -1,0})
	}
}