package main

import "registry"
import rl "vendor:raylib"
import b3 "vendor:box3d"

main :: proc() {
	rl.InitWindow(1280, 720, "Box3D + raylib")
	defer rl.CloseWindow()
	rl.SetTargetFPS(60)

	camera := rl.Camera3D{
		position   = {0, 10, 20},
		target     = {0, 0, 0},
		up         = {0, 1, 0},
		fovy       = 45,
		projection = rl.CameraProjection.PERSPECTIVE,
	}

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

		rl.BeginDrawing()
		rl.ClearBackground(rl.SKYBLUE)
		rl.BeginMode3D(camera)

		gt := b3.Body_GetTransform(ground_id)
		ground_mat := rl.MatrixCompose(rl.Vector3(gt.p), rl.Quaternion(gt.q), {1, 1, 1})
		rl.DrawMesh(ground_model.meshes[0], ground_model.materials[0], ground_mat)

		bt := b3.Body_GetTransform(box_id)
		box_mat := rl.MatrixCompose(rl.Vector3(bt.p), rl.Quaternion(bt.q), {1, 1, 1})
		rl.DrawMesh(box_model.meshes[0], box_model.materials[0], box_mat)

		rl.EndMode3D()
		rl.EndDrawing()
	}
}
