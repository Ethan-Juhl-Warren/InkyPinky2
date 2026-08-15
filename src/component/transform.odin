package component
import "../entity"
import "../registry"
import "../error"
import "core:math/linalg"

@(private) transform_manager: TransformManager

// Right handed co-ordinates


GLOBAL_UP :: [3]f32 {0, 1, 0}
GLOBAL_RIGHT :: [3]f32 {1, 0, 0}
GLOBAL_FORWARD :: [3]f32 {0, 0, -1}

Transform :: struct {
	position: [3]f32,
	scale: [3]f32,
	rotation: quaternion128
}

@(private)
TransformManager :: struct {
	transform_registry: registry.Registry(Transform, entity.Id),
	initilized: bool
}

/*
Initilizes the transform manager, must be called prior to any function that deals with transforms
a corresponding call to destroy_transform_manager must be called to cleanup

Note:

This individually intilizes the transform manager.
See also init_component_managers, which initilizes all component mangers
*/
init_transform_manager :: proc() {
	if transform_manager.initilized {
		error.printf(.MANAGER_ALREADY_INITILIZED, "initilizing transform manager")
		return
	}
	registry.init_registry(&transform_manager.transform_registry, nil)
	transform_manager.initilized = true
}

/*
Destroys the transform manager, must be called at cleanup time to free the transform system

Note:

This individually destroys the transform manager.
See also destroy_component_managers, which destroys all component mangers
*/
destroy_transform_manager :: proc() {
	if !transform_manager.initilized {
		error.printf(.DESTROYING_UNINITILIZED_MANAGER, "destroying transform manager")
		return
	}
	registry.destroy_registry(&transform_manager.transform_registry)
	transform_manager.initilized = false
}

/*
Creates a Transform component for the entity specified by entity_id

Inputs:
- entity_id: entity.Id The Id of the entity to create a Transform for
- position: [3]f32 The position vector of the Transform
- scale: [3]f32 The scale vector of the Transform
- rotation: quaternion128 The rotation quaternion of the Transform

Note:

If the supplied entity_id is invalid the system will panic
*/
transform_create :: proc(entity_id: entity.Id, position: [3]f32 = {0,0,0}, scale: [3]f32 = {1,1,1}, rotation: quaternion128 = linalg.QUATERNIONF32_IDENTITY) {
	assert(transform_manager.initilized, "transform_create: transform manager not intitialized, call init_transform_manager first")
	transform: Transform
	transform.position = position
	transform.rotation = rotation
	transform.scale = scale

	err := registry.create_item(&transform_manager.transform_registry, entity_id, transform)
	error.must(err)
}

/*
Removes a Transform component from the entity specified by entity_id and frees the underlying memory

Inputs:
- entity_id: entity.Id The id of the entity whose Transform component will be destroyed

Note:

If the supplied entity_id is invalid, or has no corresponding Transform component the system will panic
*/
transform_destroy :: proc(entiy_id: entity.Id) {
	assert(transform_manager.initilized, "transform_destroy: transform manager not initialized, call init_transform_manager first")
	transform, present := registry.get_item(&transform_manager.transform_registry, entiy_id)
	error.must(present)
	registry.destroy_item(&transform_manager.transform_registry, entiy_id)
}

/*
Returns the position vector [3]f32 of the entity specified by entity_id's corresponding Transform component

Inputs:
- entity_id: entity.Id The id of the entity whose position will be returned

Outputs:
- [3]f32 The position vector of the entity

Note:

If the supplied entity_id is invalid, or has no corresponding Transform component the system will panic
*/
transform_get_position :: proc(entity_id: entity.Id) -> [3]f32 {
	assert(transform_manager.initilized, "transform_get_position: transform manager not initialized, call init_transform_manager first")
	transform, found := registry.get_item(&transform_manager.transform_registry, entity_id)
	error.must(found)
	return transform.position
}

/*
Returns the scale vector [3]f32 of the entity specified by entity_id's corresponding Transform component

Inputs:
- entity_id: entity.Id The id of the entity whose scale will be returned

Outputs:
- [3]f32 The scale vector of the entity

Note:

If the supplied entity_id is invalid, or has no corresponding Transform component the system will panic
*/
transform_get_scale :: proc(entity_id: entity.Id) -> [3]f32 {
	assert(transform_manager.initilized, "transform_get_scale: transform manager not initialized, call init_transform_manager first")
	transform, found := registry.get_item(&transform_manager.transform_registry, entity_id)
	error.must(found)
	return transform.scale
}

/*
Returns the rotation quaternion128 of the entity specified by entity_id's corresponding Transform component

Inputs:
- entity_id: entity.Id The id of the entity whose rotation will be returned

Outputs:
- quaternion128 The rotation quaternion of the entity

Note:

If the supplied entity_id is invalid, or has no corresponding Transform component the system will panic
*/
transform_get_rotation :: proc(entity_id: entity.Id) -> quaternion128 {
	assert(transform_manager.initilized, "transform_get_rotation: transform manager not initialized, call init_transform_manager first")
	transform, found := registry.get_item(&transform_manager.transform_registry, entity_id)
	error.must(found)
	return transform.rotation
}

/*
Sets the position vector [3]f32 of the entity specified by entity_id's corresponding Transform component

Inputs:
- entity_id: entity.Id The id of the entity whose position will be set

Note:

If the supplied entity_id is invalid, or has no corresponding Transform component the system will panic
*/
transform_set_position :: proc(entity_id: entity.Id, position: [3]f32) {
	assert(transform_manager.initilized, "transform_set_position: transform manager not initialized, call init_transform_manager first")
	transform, found := registry.get_item(&transform_manager.transform_registry, entity_id)
	error.must(found)
	transform.position = position
}

/*
Sets the scale vector [3]f32 of the entity specified by entity_id's corresponding Transform component

Inputs:
- entity_id: entity.Id The id of the entity whose scale will be set

Note:

If the supplied entity_id is invalid, or has no corresponding Transform component the system will panic
*/
transform_set_scale :: proc(entity_id: entity.Id, scale: [3]f32) {
	assert(transform_manager.initilized, "transform_set_scale: transform manager not initialized, call init_transform_manager first")
	transform, found := registry.get_item(&transform_manager.transform_registry, entity_id)
	error.must(found)
	transform.scale = scale
}

/*
Sets the rotation quaternion128 of the entity specified by entity_id's corresponding Transform component

Inputs:
- entity_id: entity.Id The id of the entity whose rotation will be set

Note:

If the supplied entity_id is invalid, or has no corresponding Transform component the system will panic
*/
transform_set_rotation :: proc(entity_id: entity.Id, rotation: quaternion128) {
	assert(transform_manager.initilized, "transform_set_rotation: transform manager not initialized, call init_transform_manager first")
	transform, found := registry.get_item(&transform_manager.transform_registry, entity_id)
	error.must(found)
	transform.rotation = rotation
}

/*
Returns a copy of the entity's transform

Inputs:
- entity_id: entity.Id The id of the entity

Outputs:
- Transform: a copy of the transform of the entity

Note:

If the entity_id is invalid or the entity_id is valid,
but lacks a transform component this will panic
*/
transform_get_transform :: proc(entity_id: entity.Id) -> Transform {
	assert(transform_manager.initilized, "transform_get_transform: transform manager not initialized, call init_transform_manager first")
	transform, found := registry.get_item(&transform_manager.transform_registry, entity_id)
	error.must(found)
	return transform^
}

/*
Copies the values of the supplied Transform to the internal transform

Inputs:
- entity_id: entity.Id The id of the entity
- transform: The new transform of the entity

Note:

If the entity_id is invalid or the entity_id is valid,
but lacks a transform component this will panic
*/
transform_set_transform :: proc(entity_id: entity.Id, #by_ptr transform: Transform) {
	assert(transform_manager.initilized, "transform_set_transform: transform manager not initialized, call init_transform_manager first")
	trn, found := registry.get_item(&transform_manager.transform_registry, entity_id)
	error.must(found)
	trn.position = transform.position
	trn.rotation = transform.rotation
	trn.scale = transform.scale
}

/*
Queries if a transform exists for the given entity_id

Input:
- entity_id: entity.Id The id of the entity being queried

Output:
- bool True if there is a transform, False if not

Note:

If the supplied entity_id is invalid it will panic
*/
transform_exists :: proc(entity_id: entity.Id) -> bool {
	assert(transform_manager.initilized, "transform_set_transform: transform manager not initialized, call init_transform_manager first")
	_, found := registry.get_item(&transform_manager.transform_registry, entity_id)
	if found == .ID_INVALID {
		error.must(.ID_INVALID)
	}
	return found == .NONE
}

/*
Returns the up vector based off the entites local orientation

Input:
- entity_id: entity.Id The id of the entity

Output:
- [3]f32 The local up vector

Note:

If the supplied entity_id is invalid, or has no corresponding Transform the system will panic
*/
transform_get_up_local :: proc(entity_id: entity.Id) -> [3]f32 {
	assert(transform_manager.initilized, "transform_get_up_local: transform manager not initialized, call init_transform_manager first")
	transform, found := registry.get_item(&transform_manager.transform_registry, entity_id)
	error.must(found)
	return linalg.quaternion_mul_vector3(linalg.quaternion_normalize0(transform.rotation), GLOBAL_UP)
}

/*
Returns the right vector based off the entites local orientation

Input:
- entity_id: entity.Id The id of the entity

Output:
- [3]f32 The local right vector

Note:

If the supplied entity_id is invalid, or has no corresponding Transform the system will panic
*/
transform_get_right_local :: proc(entity_id: entity.Id) -> [3]f32 {
	assert(transform_manager.initilized, "transform_get_right_local: transform manager not initialized, call init_transform_manager first")
	transform, found := registry.get_item(&transform_manager.transform_registry, entity_id)
	error.must(found)
	return linalg.quaternion_mul_vector3(linalg.quaternion_normalize0(transform.rotation), GLOBAL_RIGHT)
}

/*
Returns the forward vector based off the entites local orientation

Input:
- entity_id: entity.Id The id of the entity

Output:
- [3]f32 The local forward vector

Note:

If the supplied entity_id is invalid, or has no corresponding Transform the system will panic
*/
transform_get_forward_local :: proc(entity_id: entity.Id) -> [3]f32 {
	assert(transform_manager.initilized, "transform_get_forward_local: transform manager not initialized, call init_transform_manager first")
	transform, found := registry.get_item(&transform_manager.transform_registry, entity_id)
	error.must(found)
	return linalg.quaternion_mul_vector3(linalg.quaternion_normalize0(transform.rotation), GLOBAL_FORWARD)
}

/*
Translates the entity's transform by delta

Input:
- entity_id: entity.Id The id of the entity
- delta: [3]f32 The delta vector by which the transform will be translated

Note:

If the supplied entity_id is invalid, or has no corresponding Transform the system will panic
*/
transform_translate :: proc(entity_id: entity.Id, delta: [3]f32) {
	assert(transform_manager.initilized, "transform_translate: transform manager not initialized, call init_transform_manager first")
	transform, found := registry.get_item(&transform_manager.transform_registry, entity_id)
	error.must(found)
	transform.position += delta
}

/*
Translates the entity's transform by delta in the local co-ordiantes

Input:
- entity_id: entity.Id The id of the entity
- delta: [3]f32 The delta vector by which the transform will be translated

Note:

If the supplied entity_id is invalid, or has no corresponding Transform the system will panic
*/
transform_translate_local :: proc(entity_id: entity.Id, delta: [3]f32) {
	assert(transform_manager.initilized, "transform_translate_local: transform manager not initialized, call init_transform_manager first")
	transform, found := registry.get_item(&transform_manager.transform_registry, entity_id)
	error.must(found)
	right := linalg.quaternion_mul_vector3(linalg.quaternion_normalize0(transform.rotation), GLOBAL_RIGHT)
	up := linalg.quaternion_mul_vector3(linalg.quaternion_normalize0(transform.rotation), GLOBAL_UP)
	forward := linalg.quaternion_mul_vector3(linalg.quaternion_normalize0(transform.rotation), GLOBAL_FORWARD)
	delta_local := delta.x * right + delta.y * up + delta.z * forward
	transform.position += delta_local
}

/*
Returns the TRS matrix from the entities Transform

Input:
- entity_id: entity.Id The id of the entity

Output:
- matrix[4,4]f32 The Transform matrix

Note:

If the supplied entity_id is invalid, or has no corresponding Transform the system will panic
*/
transform_get_matrix :: proc(entity_id: entity.Id) -> matrix[4,4]f32 {
	assert(transform_manager.initilized, "transform_get_matrix: transform manager not initialized, call init_transform_manager first")
	transform, found := registry.get_item(&transform_manager.transform_registry, entity_id)
	error.must(found)
	return linalg.matrix4_from_trs_f32(transform.position, transform.rotation, transform.scale)
}
