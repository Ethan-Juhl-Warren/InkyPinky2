// src/engine/scene/scene_loader_test.odin
package scene

import "core:testing"
import "../component"
import "../entity"

@(test)
test_load_real_scene_descriptor :: proc(t: ^testing.T) {
	init_scene_manager()
	component.init_component_managers()
	defer destroy_scene_manager()
	defer component.destroy_component_managers()

	descriptor := SceneDescriptor{
		name = "City Outskirts",
		id   = 1,
		refrence = "scene_descriptor.mjson",   // relative to repo root
	}
	err := _load_scene_descriptor(descriptor)
	testing.expect(t, err == .NONE)

	crate_id := component.name_get_entities("crate")[0]
	testing.expect(t, crate_id != entity.INVALID)

	pos := component.transform_get_position(crate_id)
	testing.expect_value(t, pos, [3]f32{0, 8, 0})

	cam_id := component.name_get_entities("main camera")[0]
	fovy := component.camera_get_fovy(cam_id)
	testing.expect_value(t, fovy, f32(45.0))

	main_cam, main_err := component.get_main_camera()
	testing.expect(t, main_err == .NONE)
	testing.expect(t, main_cam == cam_id)
}