package entity
import "../registry"
import "core:strings"
import "../error"
import cmpt "../component"
import b3 "vendor:box3d"

@(private) entity_manager: EntityManager

EntityId :: distinct int

Entity :: struct {
	name: string,
	transform: cmpt.TransformId,
	rigidbody: cmpt.RigidBodyId,
	model_id: cmpt.ModelId,
	script: int
}

@(private)
EntityManager :: struct {
	entity_names: map[string]EntityId,
	entity_references: map[EntityId]u32,
	entity_registry: registry.Registry(Entity),
	initialized: bool
}

init_entity_manager :: proc() {
	entity_manager.entity_names = make(map[string]EntityId)
	entity_manager.entity_references = make(map[EntityId]u32)
	registry.init_registry(&entity_manager.entity_registry, _free_entity)
	entity_manager.initialized = true
}

destroy_entity_manager :: proc() {
	delete(entity_manager.entity_names)
	delete(entity_manager.entity_references)
	registry.destroy_registry(&entity_manager.entity_registry)
	entity_manager.initialized = false
}

create :: proc(name: string) -> (EntityId, error.Code) {
	assert(entity_manager.initialized, "create: entity manager not intitialized, call init_entity_manager first")
	_, exists := entity_manager.entity_names[name]
	if exists {
		return registry.INVALID_ID, error.Code.NAME_EXISTS
	}
	entity: Entity
	entity.name = strings.clone(name)
	entity.rigidbody = cast(cmpt.RigidBodyId) registry.INVALID_ID
	entity.

	entity_id, err := registry.create_item(&entity_manager.entity_registry, entity)
	if err != .NONE {
		return registry.INVALID_ID, err
	}
	entity_manager.entity_names[entity.name] = cast(EntityId) entity_id
	return cast(EntityId) entity_id, .NONE
}

// TODO Needs some resource manager cleanup
destroy_by_id :: proc(entity_id: EntityId) -> error.Code {
	assert(entity_manager.initialized, "destroy_by_id: entity manager not initialized, call init_entity_manager first")

	entity, present := registry.get_item(&entity_manager.entity_registry, cast(registry.RegistryId)entity_id)

	if present != .NONE {
		return present
	}

	delete_key(&entity_manager.entity_names, entity.name)
	registry.destroy_item(&entity_manager.entity_registry, cast(registry.RegistryId) entity_id)
	return .NONE
}

destroy_by_name :: proc(name: string) -> error.Code {
	assert(entity_manager.initialized, "destroy_by_name: entity manager not initialized, call init_entity_manager first")
	entity_id, present := entity_manager.entity_names[name]
	if !present {
		return .OBJECT_NOT_FOUND
	}
	return destroy_by_id(entity_id)
}

get_by_name :: proc(name: string) -> (EntityId, error.Code) {
	assert(entity_manager.initialized, "get_by_name: entity manager not initialized, call init_entity_manager first")
	enity, valid := entity_manager.entity_names[name]
	if !valid {
		return registry.INVALID_ID, error.Code.OBJECT_NOT_FOUND
	}
	return enity, error.Code.NONE
}

get_entity_name :: proc(entity_id: EntityId) -> (string, error.Code) {
	assert(entity_manager.initialized, "get_entity_name: entity manager not initialized, call init_entity_manager first")
	entity, found := registry.get_item(&entity_manager.entity_registry, cast(registry.RegistryId)entity_id)
	if found != error.Code.NONE {
		return "", found
	}
	return entity.name, error.Code.NONE
}

/*
 * TODO IMPORTANT Must add cleanup for material and script refrences once they are concrete
*/
@(private)
_free_entity :: proc(entity: ^Entity) {
	b3.DestroyBody(entity.rigidbody)
	delete(entity.name)
}
