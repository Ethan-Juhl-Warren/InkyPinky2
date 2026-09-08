package serialization
import "../entity"
import "../error"
import "../mjson"
import "../component"
import "core:encoding/json"

name_from_mjson :: proc(entity_id: entity.Id, value: json.Value) -> error.Code {
    obj := mjson.as_object(value) or_return
    name := mjson.as_string(obj["name"]) or_return
    component.name_create(entity_id, name)
    return .NONE
}