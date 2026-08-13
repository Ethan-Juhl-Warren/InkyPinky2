package component
import "../entity"
import "../registry"
import "../error"

@(private) transform_manager: TransformManager

Transform :: struct {
	position: [3]f32,
	scale: [3]f32,
	rotation: [3]f32
}

@(private)
TransformManager :: struct {
	transform_registry: registry.Registry(Transform, entity.EntityId),
	initilized: bool
}

init_transform_manager :: proc() {
	registry.init_registry(&transform_manager.transform_registry, nil)
	transform_manager.initilized = true
}

destroy_transform_manager :: proc() {
	registry.destroy_registry(&transform_manager.transform_registry)
	transform_manager.initilized = false
}

transform_create :: proc(entity_id: entity.EntityId, position: [3]f32 = {0,0,0}, scale: [3]f32 = {1,1,1}, rotation: [3]f32 = {0,0,0}) -> (error.Code) {
	assert(transform_manager.initilized, "create: transform manager not intitialized, call init_transform_manager first")
	transform: Transform
	transform.position = position
	transform.rotation = rotation
	transform.scale = scale

	err := registry.create_item(&transform_manager.transform_registry, entity_id, transform)
	if err != .NONE {
		return err
	}
	return .NONE
}

transform_destroy :: proc(entiy_id: entity.EntityId) -> error.Code {
	assert(transform_manager.initilized, "destroy: transform manager not initialized, call init_transform_manager first")

	transform, present := registry.get_item(&transform_manager.transform_registry, entiy_id)

	if present != .NONE {
		return present
	}

	registry.destroy_item(&transform_manager.transform_registry, entiy_id)
	return .NONE
}

transform_get_position :: proc(entity_id: entity.EntityId) -> ([3]f32, error.Code) {
	assert(transform_manager.initilized, "get_position: transform manager not initialized, call init_transform_manager first")
	entity, found := registry.get_item(&transform_manager.transform_registry, entity_id)
	if found != .NONE {
		return {0,0,0}, found
	}
	return entity.position, .NONE
}

transform_get_scale :: proc(entity_id: entity.EntityId) -> ([3]f32, error.Code) {
	assert(transform_manager.initilized, "get_scale: transform manager not initialized, call init_transform_manager first")
	entity, found := registry.get_item(&transform_manager.transform_registry, entity_id)
	if found != .NONE {
		return {0,0,0}, found
	}
	return entity.scale, .NONE
}

transform_get_rotation :: proc(entity_id: entity.EntityId) -> ([3]f32, error.Code) {
	assert(transform_manager.initilized, "get_rotation: transform manager not initialized, call init_transform_manager first")
	entity, found := registry.get_item(&transform_manager.transform_registry, entity_id)
	if found != .NONE {
		return {0,0,0}, found
	}
	return entity.rotation, .NONE
}

transform_set_position :: proc(entity_id: entity.EntityId, position: [3]f32) -> error.Code {
	assert(transform_manager.initilized, "get_position: transform manager not initialized, call init_transform_manager first")
	entity, found := registry.get_item(&transform_manager.transform_registry, entity_id)
	if found != .NONE {
		return found
	}
	entity.position = position
	return .NONE
}

transform_set_scale :: proc(entity_id: entity.EntityId, scale: [3]f32) -> error.Code {
	assert(transform_manager.initilized, "get_scale: transform manager not initialized, call init_transform_manager first")
	entity, found := registry.get_item(&transform_manager.transform_registry, entity_id)
	if found != .NONE {
		return found
	}
	entity.scale = scale
	return .NONE
}

transform_set_rotation :: proc(entity_id: entity.EntityId, rotation: [3]f32) -> error.Code {
	assert(transform_manager.initilized, "get_rotation: transform manager not initialized, call init_transform_manager first")
	entity, found := registry.get_item(&transform_manager.transform_registry, entity_id)
	if found != .NONE {
		return found
	}
	entity.rotation = rotation
	return .NONE
}
