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
	transform_registry: registry.Registry(Transform, entity.Id),
	initilized: bool
}

init_transform_manager :: proc() {
	if transform_manager.initilized {
		error.printf(.MANAGER_ALREADY_INITILIZED, "initilizing transform manager")
		return
	}
	registry.init_registry(&transform_manager.transform_registry, nil)
	transform_manager.initilized = true
}

destroy_transform_manager :: proc() {
	if !transform_manager.initilized {
		error.printf(.DESTROYING_UNINITILIZED_MANAGER, "destroying transform manager")
		return
	}
	registry.destroy_registry(&transform_manager.transform_registry)
	transform_manager.initilized = false
}

transform_create :: proc(entity_id: entity.Id, position: [3]f32 = {0,0,0}, scale: [3]f32 = {1,1,1}, rotation: [3]f32 = {0,0,0}) {
	assert(transform_manager.initilized, "create: transform manager not intitialized, call init_transform_manager first")
	transform: Transform
	transform.position = position
	transform.rotation = rotation
	transform.scale = scale

	err := registry.create_item(&transform_manager.transform_registry, entity_id, transform)
	error.must(err)
}

transform_destroy :: proc(entiy_id: entity.Id) {
	assert(transform_manager.initilized, "destroy: transform manager not initialized, call init_transform_manager first")

	transform, present := registry.get_item(&transform_manager.transform_registry, entiy_id)

	error.must(present)

	registry.destroy_item(&transform_manager.transform_registry, entiy_id)
}

transform_get_position :: proc(entity_id: entity.Id) -> [3]f32 {
	assert(transform_manager.initilized, "get_position: transform manager not initialized, call init_transform_manager first")
	entity, found := registry.get_item(&transform_manager.transform_registry, entity_id)
	error.must(found)
	return entity.position
}

transform_get_scale :: proc(entity_id: entity.Id) -> [3]f32 {
	assert(transform_manager.initilized, "get_scale: transform manager not initialized, call init_transform_manager first")
	entity, found := registry.get_item(&transform_manager.transform_registry, entity_id)
	error.must(found)
	return entity.scale
}

transform_get_rotation :: proc(entity_id: entity.Id) -> [3]f32 {
	assert(transform_manager.initilized, "get_rotation: transform manager not initialized, call init_transform_manager first")
	entity, found := registry.get_item(&transform_manager.transform_registry, entity_id)
	error.must(found)
	return entity.rotation
}

transform_set_position :: proc(entity_id: entity.Id, position: [3]f32) {
	assert(transform_manager.initilized, "get_position: transform manager not initialized, call init_transform_manager first")
	entity, found := registry.get_item(&transform_manager.transform_registry, entity_id)
	error.must(found)
	entity.position = position
}

transform_set_scale :: proc(entity_id: entity.Id, scale: [3]f32) {
	assert(transform_manager.initilized, "get_scale: transform manager not initialized, call init_transform_manager first")
	entity, found := registry.get_item(&transform_manager.transform_registry, entity_id)
	error.must(found)
	entity.scale = scale
}

transform_set_rotation :: proc(entity_id: entity.Id, rotation: [3]f32) {
	assert(transform_manager.initilized, "get_rotation: transform manager not initialized, call init_transform_manager first")
	entity, found := registry.get_item(&transform_manager.transform_registry, entity_id)
	error.must(found)
	entity.rotation = rotation
}
