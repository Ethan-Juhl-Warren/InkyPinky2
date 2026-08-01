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
	rigidbbody_registry: registry.Registry(RigidBody),
	initilized: bool
}

init_rigidbody_manager :: proc() {
	registry.init_registry(&)
}
