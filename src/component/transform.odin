package component
import "../registry"
import "../error"

@(private) transform_manager: TransformManager

TransformId :: distinct int

Transform :: struct {
	position: [3]f32,
	scale: [3]f32,
	rotation: [3]f32
}

@(private)
TransformManager :: struct {
	transform_registry: registry.Registry(Transform),
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

transform_create :: proc(position: [3]f32 = {0,0,0}, scale: [3]f32 = {1,1,1}, rotation: [3]f32 = {0,0,0}) -> (TransformId, error.Code) {
	assert(transform_manager.initilized, "create: transform manager not intitialized, call init_transform_manager first")
	transform: Transform
	transform.position = position
	transform.rotation = rotation
	transform.scale = scale

	transform_id, err := registry.create_item(&transform_manager.transform_registry, transform)
	if err != .NONE {
		return registry.INVALID_ID, err
	}
	return cast(TransformId) transform_id, .NONE
}

transform_destroy :: proc(transform_id: TransformId) -> error.Code {
	assert(transform_manager.initilized, "destroy: transform manager not initialized, call init_transform_manager first")

	transform, present := registry.get_item(&transform_manager.transform_registry, cast(registry.RegistryId) transform_id)

	if present != .NONE {
		return present
	}

	registry.destroy_item(&transform_manager.transform_registry, cast(registry.RegistryId) transform_id)
	return .NONE
}

transform_get_position :: proc(transform_id: TransformId) -> ([3]f32, error.Code) {
	assert(transform_manager.initilized, "get_position: transform manager not initialized, call init_transform_manager first")
	entity, found := registry.get_item(&transform_manager.transform_registry, cast(registry.RegistryId) transform_id)
	if found != .NONE {
		return {0,0,0}, found
	}
	return entity.position, .NONE
}

transform_get_scale :: proc(transform_id: TransformId) -> ([3]f32, error.Code) {
	assert(transform_manager.initilized, "get_scale: transform manager not initialized, call init_transform_manager first")
	entity, found := registry.get_item(&transform_manager.transform_registry, cast(registry.RegistryId) transform_id)
	if found != .NONE {
		return {0,0,0}, found
	}
	return entity.scale, .NONE
}

transform_get_rotation :: proc(transform_id: TransformId) -> ([3]f32, error.Code) {
	assert(transform_manager.initilized, "get_rotation: transform manager not initialized, call init_transform_manager first")
	entity, found := registry.get_item(&transform_manager.transform_registry, cast(registry.RegistryId) transform_id)
	if found != .NONE {
		return {0,0,0}, found
	}
	return entity.rotation, .NONE
}

transform_set_position :: proc(transform_id: TransformId, position: [3]f32) -> error.Code {
	assert(transform_manager.initilized, "get_position: transform manager not initialized, call init_transform_manager first")
	entity, found := registry.get_item(&transform_manager.transform_registry, cast(registry.RegistryId) transform_id)
	if found != .NONE {
		return found
	}
	entity.position = position
	return .NONE
}

transform_set_scale :: proc(transform_id: TransformId, scale: [3]f32) -> error.Code {
	assert(transform_manager.initilized, "get_scale: transform manager not initialized, call init_transform_manager first")
	entity, found := registry.get_item(&transform_manager.transform_registry, cast(registry.RegistryId) transform_id)
	if found != .NONE {
		return found
	}
	entity.scale = scale
	return .NONE
}

transform_set_rotation :: proc(transform_id: TransformId, rotation: [3]f32) -> error.Code {
	assert(transform_manager.initilized, "get_rotation: transform manager not initialized, call init_transform_manager first")
	entity, found := registry.get_item(&transform_manager.transform_registry, cast(registry.RegistryId) transform_id)
	if found != .NONE {
		return found
	}
	entity.rotation = rotation
	return .NONE
}
