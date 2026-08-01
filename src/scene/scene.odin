package scene

import "../registry"
import "../entity"
import "../error"
import b3 "vendor:box3d"
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
	scene_names: map[string]SceneId,
	scene_registry: registry.Registry(Scene),
	active_scene: SceneId,
	initialized: bool
}

init_scene_manager :: proc() {
	registry.init_registry(&scene_manager.scene_registry, _free_scene)
	scene_manager.scene_names = make(map[string]SceneId)
	scene_manager.active_scene = registry.UNASSIGNED_ID
	scene_manager.initialized = true
}

destroy_scene_manager :: proc() {
	registry.destroy_registry(&scene_manager.scene_registry)
	delete(scene_manager.scene_names)
	scene_manager.active_scene = registry.UNASSIGNED_ID
	scene_manager.initialized = false
}

create :: proc(name: string, gravity: [3]f32) -> (SceneId, error.Code) {
	assert(scene_manager.initialized, "create: scene manager not initialized, call init_scene_manager first")
	_, exists := scene_manager.scene_names[name]
	if exists {
		return registry.INVALID_ID, .NAME_EXISTS
	}
	scene: Scene
	scene.name = strings.clone(name)

	// Setup physics world for scene
	world_def := b3.DefaultWorldDef()
	world_def.gravity = gravity
	scene.world_id = b3.CreateWorld(world_def)

	scene_id, err := registry.create_item(&scene_manager.scene_registry, scene)
	if err != .NONE {
		return registry.INVALID_ID, err
	}
	scene_manager.scene_names[scene.name] = cast(SceneId) scene_id
	return cast(SceneId) scene_id, .NONE
}

get_active :: proc() -> SceneId {
	assert(scene_manager.initialized, "get_active: scene manager not initialized, call init_scene_manager first")
	return scene_manager.active_scene
}

/*
 * param scene_id id of scene to set active
 * note scene_id must be valid and loaded
 */
set_active :: proc(scene_id: SceneId) -> error.Code {
	assert(scene_manager.initialized, "set_active: scene manager not initialized, call init_scene_manager first")
	_, err := registry.get_item(&scene_manager.scene_registry, cast(registry.RegistryId)scene_id)
	if err != .NONE {
		return .OBJECT_NOT_FOUND
	}
	scene_manager.active_scene = scene_id
	return .NONE
}

set_active_by_name :: proc(name: string) -> error.Code {
	assert(scene_manager.initialized, "set_active_by_name: scene manager not initialized, call init_scene_manager first")
	scene_id, valid := scene_manager.scene_names[name]
	if !valid {
		return .OBJECT_NOT_FOUND
	}
	return set_active(scene_id)
}


get_by_name :: proc(name: string) -> (SceneId, error.Code) {
	assert(scene_manager.initialized, "get_by_name: scene manager not initialized, call init_scene_manager first")
	scene_id, valid := scene_manager.scene_names[name]
	if !valid {
		return registry.INVALID_ID, .OBJECT_NOT_FOUND
	}
	return scene_id, .NONE
}

destroy_by_id :: proc(scene_id: SceneId) -> error.Code {
	assert(scene_manager.initialized, "destroy_by_id: scene manager not initialized, call init_scene_manager first")
	if scene_id == scene_manager.active_scene {
		return .SCENE_IS_ACTIVE
	}

	scene, present := registry.get_item(&scene_manager.scene_registry, cast(registry.RegistryId)scene_id)

	if present != .NONE {
		return present
	}

	delete_key(&scene_manager.scene_names, scene.name)
	registry.destroy_item(&scene_manager.scene_registry, cast(registry.RegistryId)scene_id)
	return .NONE
}

destroy_by_name :: proc(name: string) -> error.Code {
	assert(scene_manager.initialized, "destroy_by_name: scene manager not initialized, call init_scene_manager first")
	scene_id, present := scene_manager.scene_names[name]
	if !present {
		return .OBJECT_NOT_FOUND
	}
	return destroy_by_id(scene_id)
}

/*
 * TODO INCOMPLETE doesnt deal with physics side
 */
add_entity :: proc(scene_id: SceneId, entity_id: entity.EntityId) -> error.Code {
	assert(scene_manager.initialized, "add_entity: scene manager not initialized, call init_scene_manager first")
	scene, err := registry.get_item(&scene_manager.scene_registry, cast(registry.RegistryId)scene_id)
	if err != .NONE {
		return err
	}
	append(&scene.entities, entity_id)
	return .NONE
}

remove_entity :: proc(scene_id: SceneId, entity_id: entity.EntityId) -> error.Code {
	assert(scene_manager.initialized, "remove_entity: scene manager not initialized, call init_scene_manager first")
	scene, err := registry.get_item(&scene_manager.scene_registry, cast(registry.RegistryId)scene_id)
	if err != .NONE {
		return err
	}
	for id, index in scene.entities {
	    if id == entity_id {
	        unordered_remove(&scene.entities, index)
	        return .NONE
	    }
	}
	return .OBJECT_NOT_FOUND
}

/*
 * Returns a borrowed view of the scene's entities.
 * The slice is only valid until the next add_entity/remove_entity on this
 * scene (the backing array may reallocate) or until the scene is destroyed.
 * Copy it (e.g. slice.clone) if you need to retain it across those calls.
 */
get_entities :: proc(scene_id: SceneId) -> ([]entity.EntityId, error.Code) {
	assert(scene_manager.initialized, "get_entities: scene manager not initialized, call init_scene_manager first")
	scene, err := registry.get_item(&scene_manager.scene_registry, cast(registry.RegistryId)scene_id)
	if err != .NONE {
		return nil, err
	}
	return scene.entities[:], .NONE
}

@(private)
_free_scene :: proc(scene: ^Scene) {
	b3.DestroyWorld(scene.world_id)
	delete(scene.entities)
	delete(scene.name)
}

// Stub
@(private)
_load_scene :: proc(name: string) -> SceneId {
	id, _ := create(name, {0, -9.8, 0})
	return id
}
