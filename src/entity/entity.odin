package entity
import "../registry"
import "core:strings"
import "../error"

@(private) entity_manager: EntityManager

Id :: distinct int

@(private)
EntityManager :: struct {
	entity_names: map[string]Id,
	entity_registry: registry.Registry(string, Id),
	next_id: Id,
	initialized: bool
}

init_entity_manager :: proc() {
	entity_manager.entity_names = make(map[string]Id)
	registry.init_registry(&entity_manager.entity_registry, _free_entity)
	entity_manager.next_id = Id(0)
	entity_manager.initialized = true
}

destroy_entity_manager :: proc() {
	delete(entity_manager.entity_names)
	registry.destroy_registry(&entity_manager.entity_registry)
	entity_manager.next_id = Id(0)
	entity_manager.initialized = false
}


create :: proc(name: string) -> Id {
	assert(entity_manager.initialized, "create: entity manager not intitialized, call init_entity_manager first")
	_, found := entity_manager.entity_names[name]
	if found {
		error.must(.NAME_EXISTS)
	}
	name := strings.clone(name)

	entity_manager.next_id += 1
	err := registry.create_item(&entity_manager.entity_registry, entity_manager.next_id, name)
	error.must(err)
	entity_manager.entity_names[name] = entity_manager.next_id
	return entity_manager.next_id
}

// TODO Needs some resource manager cleanup
destroy_by_id :: proc(entity_id: Id) {
	assert(entity_manager.initialized, "destroy_by_id: entity manager not initialized, call init_entity_manager first")

	entity, found := registry.get_item(&entity_manager.entity_registry, entity_id)
	error.must(found)

	delete_key(&entity_manager.entity_names, entity^)
	registry.destroy_item(&entity_manager.entity_registry, entity_id)
}

destroy_by_name :: proc(name: string) {
	assert(entity_manager.initialized, "destroy_by_name: entity manager not initialized, call init_entity_manager first")
	entity_id, found := entity_manager.entity_names[name]
	if !found {
		error.must(.OBJECT_NOT_FOUND)
	}
	destroy_by_id(entity_id)
}

get_by_name :: proc(name: string) -> Id {
	assert(entity_manager.initialized, "get_by_name: entity manager not initialized, call init_entity_manager first")
	enity, valid := entity_manager.entity_names[name]
	if !valid {
		error.must(.OBJECT_NOT_FOUND)
	}
	return enity
}

get_entity_name :: proc(entity_id: Id) -> string {
	assert(entity_manager.initialized, "get_entity_name: entity manager not initialized, call init_entity_manager first")
	entity_name, found := registry.get_item(&entity_manager.entity_registry, entity_id)
	error.must(found)
	return entity_name^
}

/*
 * TODO IMPORTANT Must add cleanup for material and script refrences once they are concrete
*/
@(private)
_free_entity :: proc(entity_name: ^string) {
	delete(entity_name^)
}
