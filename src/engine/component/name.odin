package component
import "core:strings"
import "core:mem"
import "../registry"
import "../entity"
import "../error"

@(private) name_manager: NameManager

@(private)
NameManager :: struct {
    registry: registry.Registry(string, entity.Id),
    initialized: bool
}

/*
initializes the name manager, must be called prior to any function that deals with names
a corresponding call to destroy_name_manager must be called to cleanup

Note:

This individually initializes the name manager
See also init_component_managers, which initializes all component managers
*/
init_name_manager :: proc() {
	if name_manager.initialized {
		error.printf(.MANAGER_ALREADY_INITIALIZED, "initializing name manager")
		return
	}
	registry.init_registry(&name_manager.registry, _free_name)
	name_manager.initialized = true
}

/*
Destroys the name manager, must be called at cleanup time to free the name system

Note:

This individually destroys the name manager
See also destroy_component_managers, which destroys all component mangers
*/
destroy_name_manager :: proc() {
	if !name_manager.initialized {
		error.printf(.DESTROYING_UNINITIALIZED_MANAGER, "destroying name manager")
		return
	}
	registry.destroy_registry(&name_manager.registry)
	name_manager.initialized = false
}

/*
Creates a Name component for the entity specified by entity_id

Inputs:
- entity_id: entity.Id The Id of the entity to create a Name for
- String literal of the name

Note:

If the supplied entity_id is invalid the system will panic
*/
name_create :: proc(entity_id: entity.Id, name: string) {
	assert(name_manager.initialized, "name_create: name manager not initialized, call init_name_manager first")

	err := registry.create_item(&name_manager.registry, entity_id, strings.clone(name))
	error.must(err)
}

/*
Removes a Name component from the entity specified by entity_id and frees the underlying memory

Inputs:
- entity_id: entity.Id The id of the entity whose Name component will be destroyed

Note:

If the supplied entity_id is invalid, or has no corresponding Name component the system will panic
*/
name_destroy :: proc(entity_id: entity.Id) {
	assert(name_manager.initialized, "name_destroy: name manager not initialized, call init_name_manager first")
	err := registry.destroy_item(&name_manager.registry, entity_id)
	error.print(err)
}

/*
Returns the name of a given component

Inputs:
- entity_id: entity.Id The id of the entity

Outputs:
- string The name of the entity
*/
get_name :: proc(entity_id: entity.Id) -> string {
    assert(name_manager.initialized, "get_name: name manager not initialized, call init_name_manager first")
    name, found := registry.get_item(&name_manager.registry, entity_id)
    error.must(found)
    return name^
}

/*
Returns all entities possesing a given name

Inputs:
- name: string The name of the entity

Outputs:
- []entity.Id Array of the ids of the entites with that name.
*/
name_get_entities :: proc(name: string, allocator: mem.Allocator = context.allocator) -> [dynamic]entity.Id {
    assert(name_manager.initialized, "name_get_entities: name manager not initialized, call init_name_manager first")
    names := registry.registry_item_slice(&name_manager.registry)
	ids := registry.registry_id_slice(&name_manager.registry)
    ent := make([dynamic]entity.Id, 0, 10, allocator)
    for n, i in names {
        if n == name {
			append(&ent, ids[i])
		}
    }
	return ent
}

/*
Frees a name string
*/
@(private) _free_name :: proc(name: ^string) {
    free(name)
}