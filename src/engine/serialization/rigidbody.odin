package serialization
import "../entity"
import "../error"
import "../mjson"
import "vendor:box3d"
import "../component"
import "core:encoding/json"


rigidbody_from_mjson :: proc (entity_id: entity.Id, value: json.Value) -> error.Code {
	obj := mjson.as_object(value) or_return
	kind := mjson.as_string(obj["kind"]) or_return

	bodydef := box3d.DefaultBodyDef()
	switch kind {
		case "STATIC":
			bodydef.type = .staticBody
		case "DYNAMIC":
			bodydef.type = .dynamicBody
		case:
			return .PARSE_ERROR
	}

	component.rigidbody_create(entity_id, bodydef)

	half_extent := mjson.vec3(obj["half_extent"]) or_return

	density: f32 = 0
	density_val, has_density := obj["density"]
	if has_density {
		density_f := mjson.as_float(density_val) or_return
		density = f32(density_f)
	}

	component.add_box_shape(entity_id, half_extent, density)
	return .NONE
}
