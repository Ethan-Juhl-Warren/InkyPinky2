package serialization
import "../entity"
import "../error"
import "core:encoding/json"

@(private)
Component_Parser :: proc(entity.Id, json.Value) -> error.Code

@(private)
component_parsers := map[string]Component_Parser {
	"transform" = transform_from_mjson,
	"camera"    = camera_from_mjson,
	"rigidbody" = rigidbody_from_mjson,
    "name" = name_from_mjson,
	// "model" : will do but model isnt set up yet
}