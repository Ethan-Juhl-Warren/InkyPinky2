package entity
import "../registry"
import "../error"
import "../model"
import b3 "vendor:box3d"

@(private) entity_manager: EntityManager

EntityId :: distinct int

Entity :: struct {
	name: string,
	body_id: b3.BodyId,
	model_id: model.ModelId,
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

create :: proc(entity_id: EntityId) -> (EntityId, error.ErrorCode) {
	assert(entity_manager.initialized, "create: entity manager not intitialized, call init_entity_manager first")
}

destroy_by_id :: proc(entity_id: EntityId) {
	assert(entity_manager.initialized, "destroy_by_id: entity manager not initialized, call init_entity_manager first")
}

destroy_by_name :: proc(entity_id: EntityId) {
	assert(entity_manager.initialized, "destroy_by_name: entity manager not initialized, call init_entity_manager first")

}

get_by_name :: proc(name: string) -> (EntityId, error.ErrorCode) {
	assert(entity_manager.initialized, "get_by_name: entity manager not initialized, call init_entity_manager first")
	enity, valid := entity_manager.entity_names[name]
	if !valid {
		return registry.INVALID_ID, error.ErrorCode.OBJECT_NOT_FOUND
	}
	return enity, error.ErrorCode.NONE
}


get_entity_name :: proc(entity_id: EntityId) -> (string, error.ErrorCode) {
	assert(entity_manager.initialized, "get_entity_name: entity manager not initialized, call init_entity_manager first")
	entity, found := registry.get_item(&entity_manager.entity_registry, cast(registry.RegistryId)entity_id)
	if found != error.ErrorCode.NONE {
		return "", found
	}
	return entity.name, error.ErrorCode.NONE
}


/*
 * TODO IMPORTANT Must add cleanup for material and script refrences once they are concrete
*/
@(private)
_free_entity :: proc(entity: ^Entity) {
	b3.DestroyBody(entity.body_id)
	delete(entity.name)
}
