package serialization
import "../entity"
import "../error"
import "../mjson"
import "../component"
import "core:encoding/json"

transform_from_mjson :: proc(entity_id: entity.Id, value: json.Value) -> error.Code {
    obj, ok := value.(json.Object)
	if !ok {
		return .PARSE_ERROR
	}
	position := mjson.vec3(obj["position"]) or_return
	scale := mjson.vec3(obj["scale"]) or_return
	rotation := mjson.quat(obj["rotation"]) or_return

	component.transform_create(entity_id, position, scale, rotation)
	return .NONE
}
