package scene

import "../registry"
import "../entity"
import "../error"
import b3 "vendor:box3d"
import "core:slice"
import "core:strings"

@(private) scene_manager: SceneManager

SceneId :: distinct int

Scene :: struct {
	name: string,
	world_id: b3.WorldId,
	entities: [dynamic]entity.EntityId
}

@(private)
SceneManager :: struct {
	reistry: registry.Registry(Scene),
	names: map[string]SceneId,
	active_scene: SceneId,
}

init_scene_manager :: proc() {
	scene_manager.reistry := new(registry.Registry(Scene))
	registry.init_registry(&scene_manager.reistry, _free_scene)
	scene_manager.names := make(map[string]SceneId)
	scene_manager.active_scene = registry.UNASSIGNED_ID
}

destroy_scene_manager :: proc() {
	registry.destroy_registry(&scene_manager.reistry)
	delete(scene_manager.names)
	scene_manager.active_scene = registry.UNASSIGNED_ID
}

new_scene :: proc(name: string, gravity: [3]f32) -> (SceneId, error.ErrorCode) {
	_, exists := scene_manager.scene_names[name]
	if exists {
		return INVALID_SCENE_ID, error.ErrorCode.NAME_EXISTS
	}
	scene := new(Scene)
	scene.name = strings.clone(name)

	world_def := b3.DefaultWorldDef()
	world_def.gravity = gravity
	scene.world_id = b3.CreateWorld(world_def)

	scene_id := _scene_manager_append_scene(scene)
	return scene_id, error.ErrorCode.NONE
}

get_active_scene :: proc() -> SceneId {
	return scene_manager.active_scene
}

set_active_scene_by_name :: proc(name: string) -> error.ErrorCode {
	scene_id, valid := scene_manager.scene_names[name]
	if !valid {
		return error.ErrorCode.REGISTRY_ITEM_NOT_FOUND
	}
	return set_active_scene(scene_id)
}

/*
 * param scene_id id of scene to set active
 * note scene_id must be valid and loaded
 */
set_active_scene :: proc(scene_id: SceneId) -> error.ErrorCode {
	_, valid := scene_manager.scenes[scene_id]
	if !valid {
		return error.ErrorCode.REGISTRY_ITEM_NOT_FOUND
	}
	scene_manager.active_scene = scene_id
	return error.ErrorCode.NONE
}

get_scene_by_name :: proc(name: string) -> (SceneId, error.ErrorCode) {
	scene_id, valid := scene_manager.scene_names[name]
	if !valid {
		return INVALID_SCENE_ID, error.ErrorCode.REGISTRY_ITEM_NOT_FOUND
	}
	return scene_id, error.ErrorCode.NONE
}

delete_scene_by_id :: proc(scene_id: SceneId) -> error.ErrorCode {
	scene, present := _get_scene_ptr(scene_id)

	if present != error.ErrorCode.NONE {
		return present
	}

	_scene_manager_delete_scene(scene, scene_id)

	return error.ErrorCode.NONE
}

delete_scene_by_name :: proc(name: string) -> error.ErrorCode {
	scene_id, present := scene_manager.scene_names[name]
	if !present {
		return error.ErrorCode.REGISTRY_ITEM_NOT_FOUND
	}
	return delete_scene_by_id(scene_id)
}

scene_add_entity :: proc(scene_id: SceneId, entity_id: entity.EntityId) -> error.ErrorCode {
	scene, err := _get_scene_ptr(scene_id)
	if err != error.ErrorCode.NONE {
		return err
	}
	append(&scene.entities, entity_id)
	return error.ErrorCode.NONE
}

scene_remove_entity :: proc(scene_id: SceneId, entity_id: entity.EntityId) -> error.ErrorCode {
	scene, err := _get_scene_ptr(scene_id)
	if err != error.ErrorCode.NONE {
		return err
	}
	for id, index in scene.entities {
		if id == entity_id {
			unordered_remove(&scene.entities, index)
			return error.ErrorCode.NONE
		}
	}
	return error.ErrorCode.REGISTRY_ITEM_NOT_FOUND
}

scene_get_entities :: proc(scene_id: SceneId) -> ([]entity.EntityId, error.ErrorCode) {
	scene, err := _get_scene_ptr(scene_id)
	if err != error.ErrorCode.NONE {
		return nil, err
	}
	entities_deep_copy := slice.clone(scene.entities[:])
	return entities_deep_copy, error.ErrorCode.NONE
}

@(private)
_scene_manager_append_scene :: proc(scene: ^Scene) -> SceneId{
	scene_id, error := registry.new_registry_item(&scene_manager.reistry, scene^)
	if error != .NONE {
		return registry.INVALID_ID
	}

}

@(private)
_free_scene :: proc(scene: ^Scene) {
	b3.DestroyWorld(scene.world_id)
	delete(scene.entities)
	delete(scene.name)
	free(scene)
}

@(private)
_get_scene_ptr :: proc(scene_id: SceneId) -> (^Scene, error.ErrorCode) {
	if scene_id <= INVALID_SCENE_ID {
		return nil, error.ErrorCode.ID_INVALID
	}
	_, present := scene_manager.scenes[scene_id]
	if !present {
		return nil, error.ErrorCode.REGISTRY_ITEM_NOT_FOUND
	}
	return &scene_manager.scenes[scene_id], error.ErrorCode.NONE
}

// Stub
@(private)
_load_scene :: proc(name: string) -> SceneId {
	id, _ := new_scene(name, {0, -9.8, 0})
	return id
}
