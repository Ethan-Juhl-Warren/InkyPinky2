package serialization
import "../entity"
import "../error"
import "core:encoding/json"

@(private)
Component_Parser :: proc(entity.Id, json.Value) -> error.Code

@(private)
component_parsers: map[string]Component_Parser

@(private)
_build_component_parser_map :: proc() {
    component_parsers = make(map[string]Component_Parser)
    component_parsers["transform"] = transform_from_mjson
    component_parsers["camera"] = camera_from_mjson
    component_parsers["rigidbody"] = rigidbody_from_mjson
    component_parsers["name"] = name_from_mjson
}

@(private)
_destroy_component_parser_map :: proc() {
    delete(component_parsers)
}