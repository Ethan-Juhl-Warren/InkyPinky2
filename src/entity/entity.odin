package manager
import "../error"
import "../model"
import b3 "vendor:box3d"

@(private) entity_manager: EntityManager

EntityId :: distinct int

INVALID_ENTITY_ID :: -1

Entity :: struct {
	id: EntityId,
	name: string,
	body_id: b3.BodyId,
	model_id: model.ModelId,
	script: int
}

@(private)
EntityManager :: struct {
	entities: map[EntityId]^Entity,
	entity_names: map[string]EntityId,
	entity_refrences: map[EntityId]u32,
	next_id: EntityId
}

init_entity_manager :: proc() {
	entity_manager.entities = make(map[EntityId]^Entity)
	entity_manager.entity_names = make(map[string]EntityId)
	entity_manager.entity_refrences = make(map[EntityId]u32)
	reserve(&entity_manager.entities, 10)
	reserve(&entity_manager.entity_names, 10)
	reserve(&entity_manager.entity_refrences, 10)
}

destroy_entity_manager :: proc() {
	ids := make([dynamic]EntityId, 0, len(entity_manager.entities))
	for id in entity_manager.entities {
		append(&ids, id)
	}
	for id in ids {
		_entity_manager_delete_entity(entity_manager.entities[id])
	}
	delete(entity_manager.entities)
	delete(entity_manager.entity_names)
	delete(entity_manager.entity_refrences)
	delete(ids)
}

destroy_entity :: proc(entity_id: EntityId) {

}

new_entity :: proc(entity_id: EntityId) -> error.ErrorCode {
	return error.ErrorCode.NONE
}

get_entity_by_name :: proc(name: string) -> (EntityId, error.ErrorCode) {
	enity, valid := entity_manager.entity_names[name]
	if !valid {
		return INVALID_ENTITY_ID, error.ErrorCode.REGISTRY_ITEM_NOT_FOUND
	}
	return enity, error.ErrorCode.NONE
}


get_entity_name :: proc(entity_id: EntityId) -> (string, error.ErrorCode) {
	entity, found := _get_entity_ptr(entity_id)
	if found != error.ErrorCode.NONE {
		return "", found
	}
	return entity.name, error.ErrorCode.NONE
}

@(private)
_entity_manager_delete_entity :: proc(entity: ^Entity) {
	delete_key(&entity_manager.entities, entity.id)
	delete_key(&entity_manager.entity_names, entity.name)
	delete_key(&entity_manager.entity_refrences, entity.id)
	free(entity)
}

@(private)
_get_entity_ptr :: proc(entity_id: EntityId) -> (^Entity, error.ErrorCode) {
	if entity_id <= INVALID_ENTITY_ID {
		return nil, error.ErrorCode.ID_INVALID
	}
	entity, present := entity_manager.entities[entity_id]
	if !present {
		return nil, error.ErrorCode.REGISTRY_ITEM_NOT_FOUND
	}
	return entity, error.ErrorCode.NONE
}
