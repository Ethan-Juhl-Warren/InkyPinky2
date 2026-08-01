package physics
import "../registry"
import "../error"
import b3 "vendor:box3d"

@(private) rigidbody_manager: RigidBodyManager

RigidBodyId :: distinct int

RigidBody :: struct {
	b3_rigidbody_id: b3.BodyId,
	b3_bodydef: b3.BodyDef
}

@(private)
RigidBodyManager :: struct {
	rigidbody_registry: registry.Registry(RigidBody),
	initilized: bool
}

init_rigidbody_manager :: proc() {
	registry.init_registry(&rigidbody_manager.rigidbody_registry, _free_rigidbody)
	rigidbody_manager.initilized = true
}

destroy_rigidbody_manager :: proc() {
	registry.destroy_registry(&rigidbody_manager.rigidbody_registry)
	rigidbody_manager.initilized = false
}

create_rigidbody :: proc(bodydef: b3.BodyDef) -> (RigidBodyId, error.Code) {
	assert(rigidbody_manager.initilized, "create_rigidbody: rigidbody_manager not intilized, call init_rigid_bosy_manager")
	rigidbody: RigidBody
	rigidbody.b3_rigidbody_id = b3.nullBodyId
	rigidbody.b3_bodydef = bodydef

	rigidbody_id, err := registry.create_item(&rigidbody_manager.rigidbody_registry, rigidBody)
	if err != .NONE {
		return registry.INVALID_ID, err
	}
	return cast(RigidBodyId) rigidbody_id, .NONE
}

destroy_rigidbody :: proc(rigidbody_id: RigidBodyId) -> error.Code {
	assert(rigidbody_manager.initilized, "destroy_rigidbody: rigidbody manager not initialized, call init_rigidbosy_manager first")

	rigidbody, present := registry.get_item(&rigidbody_manager.rigidbody_registry, cast(registry.RegistryId) rigidbody_id)

	if present != .NONE {
		return present
	}
	registry.destroy_item(&rigidbody_manager.rigidbody_registry, cast(registry.RegistryId) rigidbody_id)
	return .NONE
}

@(private)
_free_rigidbody :: proc(rigidbody: ^RigidBody) {
	b3.DestroyBody(rigidbody.b3_rigidbody_id)
}
