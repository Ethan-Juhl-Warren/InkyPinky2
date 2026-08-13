package component
import "../registry"
import "../error"
import b3 "vendor:box3d"
import "../entity"

@(private) rigidbody_manager: RigidBodyManager

BoxGeometry :: struct {
	half_extents: [3]f32
}

ShapeGeometry :: union {
	b3.Sphere,
	b3.Capsule,
	BoxGeometry,
	u64
}

CollisionShape :: struct {
	geometry: ShapeGeometry,
	material: b3.SurfaceMaterial,
	density: f32,
	is_sensor: bool,
	shape_id: b3.ShapeId
}

RigidBody :: struct {
	internal_rigidbody_id: b3.BodyId,
	internal_bodydef: b3.BodyDef,
	shapes: [dynamic]CollisionShape
}

@(private)
RigidBodyManager :: struct {
	rigidbody_registry: registry.Registry(RigidBody, entity.Id),
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

create_rigidbody :: proc(entity_id: entity.Id, bodydef: b3.BodyDef) -> error.Code {
	assert(rigidbody_manager.initilized, "create_rigidbody: rigidbody_manager not intilized, call init_rigid_bosy_manager")
	rigidbody: RigidBody
	rigidbody.internal_rigidbody_id = b3.nullBodyId
	rigidbody.internal_bodydef = bodydef

	err := registry.create_item(&rigidbody_manager.rigidbody_registry, entity_id, rigidbody)
	if err != .NONE {
		return err
	}
	return .NONE
}

destroy_rigidbody :: proc(entity_id: entity.Id) -> error.Code {
	assert(rigidbody_manager.initilized, "destroy_rigidbody: rigidbody manager not initialized, call init_rigidbody_manager first")

	rigidbody, present := registry.get_item(&rigidbody_manager.rigidbody_registry, entity_id)

	if present != .NONE {
		return present
	}
	registry.destroy_item(&rigidbody_manager.rigidbody_registry, entity_id)
	return .NONE
}

realize_rigidbody :: proc(entity_id: entity.Id, world_id: b3.WorldId) -> error.Code {
	rigidbody, err := registry.get_item(&rigidbody_manager.rigidbody_registry, entity_id)
	if err != .NONE {
		return err
	}
	_realize_rigidbody(rigidbody, world_id)
	return .NONE
}

unrealize_rigidbody :: proc(entity_id: entity.Id) -> error.Code {
	rigidbody, err := registry.get_item(&rigidbody_manager.rigidbody_registry, entity_id)
	if err != .NONE {
		return err
	}
	_unrealize_rigidbody(rigidbody)
	return .NONE
}

@(private)
_realize_rigidbody :: proc(rigidbody: ^RigidBody, world_id: b3.WorldId) {
	rigidbody.internal_rigidbody_id = b3.CreateBody(world_id, rigidbody.internal_bodydef)
	for &shape in rigidbody.shapes {
		shape_def := b3.DefaultShapeDef()
		shape_def.density = shape.density
		shape_def.baseMaterial = shape.material

		switch geometry in shape.geometry {
			case b3.Sphere:
				sphere := geometry
				shape.shape_id = b3.CreateSphereShape(rigidbody.internal_rigidbody_id, shape_def, &sphere)
			case b3.Capsule:
				capsule := geometry
				shape.shape_id = b3.CreateCapsuleShape(rigidbody.internal_rigidbody_id, shape_def, &capsule)
			case BoxGeometry:
				hull := b3.MakeBoxHull(geometry.half_extents.x, geometry.half_extents.y, geometry.half_extents.z)
				shape.shape_id = b3.CreateHullShape(rigidbody.internal_rigidbody_id, shape_def, &hull.base)
			case u64:
				assert(false, "Custom hull types unsupported")
		}
	}
}

@(private)
_unrealize_rigidbody :: proc(rigidbody: ^RigidBody) {
	if b3.Body_IsValid(rigidbody.internal_rigidbody_id) == false {
		return
	}
	rb_id := rigidbody.internal_rigidbody_id
	rb_def := &rigidbody.internal_bodydef

	rb_def.type = b3.Body_GetType(rb_id)
	rb_def.position = b3.Body_GetPosition(rb_id)
	rb_def.rotation = b3.Body_GetRotation(rb_id)
	rb_def.linearVelocity = b3.Body_GetLinearVelocity(rb_id)
	rb_def.angularVelocity = b3.Body_GetAngularVelocity(rb_id)
	rb_def.linearDamping = b3.Body_GetLinearDamping(rb_id)
	rb_def.angularDamping = b3.Body_GetAngularDamping(rb_id)
	rb_def.gravityScale = b3.Body_GetGravityScale(rb_id)
	rb_def.sleepThreshold = b3.Body_GetSleepThreshold(rb_id)
	rb_def.motionLocks = b3.Body_GetMotionLocks(rb_id)
	rb_def.isAwake = b3.Body_IsAwake(rb_id)
	rb_def.isEnabled = b3.Body_IsEnabled(rb_id)

	b3.DestroyBody(rb_id)
	rigidbody.internal_rigidbody_id = b3.nullBodyId
	for &shape in rigidbody.shapes {
		shape.shape_id = b3.nullShapeId
	}
}

@(private)
_free_rigidbody :: proc(rigidbody: ^RigidBody) {
	_unrealize_rigidbody(rigidbody)
	delete(rigidbody.shapes)
}
