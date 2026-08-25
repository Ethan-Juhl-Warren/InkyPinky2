package scene
import "../entity"
import "../registry"
import "../error"
import "core:strings"



@(private) scene_manager: SceneManager

Id :: distinct u32

SceneRegistry :: struct {

}

@(private)
SceneManager :: struct {
	entity_names: map[string]entity.Id,
	entity_registry: registry.Registry(string, entity.Id),
	scene_id: Id,
	next_entity_id: Id,
	initialized: bool
}

init_scene_manager :: proc() {
	scene_manager.entity_names = make(map[string]entity.Id)
	registry.init_registry(&scene_manager.entity_registry, _free_entity)
	scene_manager.scene_id = 1
	scene_manager.next_entity_id = 0
	scene_manager.initialized = true
}

destroy_scene_manager :: proc() {
	delete(scene_manager.entity_names)
	registry.destroy_registry(&scene_manager.entity_registry)
	scene_manager.scene_id = 0
	scene_manager.next_entity_id = 0
	scene_manager.initialized = false
}

create_entity :: proc(name: string) -> entity.Id {
	assert(scene_manager.initialized, "create_entity: scene manager not initialized, call init_scene_manager first")
	_, found := scene_manager.entity_names[name]
	if found {
		error.must(.NAME_EXISTS)
	}
	name := strings.clone(name)

	scene_manager.next_entity_id += 1
	id := entity.make_id(cast(u32)scene_manager.scene_id, cast(u32)scene_manager.next_entity_id)
	err := registry.create_item(&scene_manager.entity_registry, id, name)
	error.must(err)
	scene_manager.entity_names[name] = id
	return id
}

add_entity :: proc(name: string, scene_id: Id) -> entity.Id {
	assert(scene_manager.initialized, "add_entity: scene manager not initialized, call init_scene_manager first")
	_, found := scene_manager.entity_names[name]
	if found {
		error.must(.NAME_EXISTS)
	}
	name := strings.clone(name)

	scene_manager.next_entity_id += 1
	id := entity.make_id(cast(u32)scene_manager.scene_id, cast(u32)scene_manager.next_entity_id)
	err := registry.create_item(&scene_manager.entity_registry, id, name)
	error.must(err)
	scene_manager.entity_names[name] = id
	return id
}

// TODO Needs some resource manager cleanup
destroy_entity_by_id :: proc(entity_id: entity.Id) {
	assert(scene_manager.initialized, "destroy_entity_by_id: scene manager not initialized, call init_scene_manager first")

	entity, found := registry.get_item(&scene_manager.entity_registry, entity_id)
	error.must(found)

	delete_key(&scene_manager.entity_names, entity^)
	registry.destroy_item(&scene_manager.entity_registry, entity_id)
}

destroy_entity_by_name :: proc(name: string) {
	assert(scene_manager.initialized, "destroy_entity_by_name: scene manager not initialized, call init_scene_manager first")
	entity_id, found := scene_manager.entity_names[name]
	if !found {
		error.must(.OBJECT_NOT_FOUND)
	}
	destroy_entity_by_id(entity_id)
}

get_entity_by_name :: proc(name: string) -> entity.Id {
	assert(scene_manager.initialized, "get_entity_by_name: scene manager not initialized, call init_scene_manager first")
	enity, valid := scene_manager.entity_names[name]
	if !valid {
		error.must(.OBJECT_NOT_FOUND)
	}
	return enity
}

get_entity_name :: proc(entity_id: entity.Id) -> string {
	assert(scene_manager.initialized, "get_entity_name: scene manager not initialized, call init_scene_manager first")
	entity_name, found := registry.get_item(&scene_manager.entity_registry, entity_id)
	error.must(found)
	return entity_name^
}

/*
 * TODO IMPORTANT Must add cleanup for material and script references once they are concrete
*/
@(private)
_free_entity :: proc(entity_name: ^string) {
	delete(entity_name^)
}
