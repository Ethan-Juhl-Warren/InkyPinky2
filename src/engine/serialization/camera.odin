package serialization
import "../entity"
import "../error"
import "../mjson"
import "../component"
import "core:encoding/json"

/*
The begin_draw and end_draw procedures that used to live here were raylib's
BeginMode3D and EndMode3D wrapped up, and they are gone with it. A camera does
not begin or end anything now, it answers with a view matrix and a projection
matrix and the renderer decides what to do with them.

camera_get_view_matrix and camera_get_projection_matrix above are the
replacement, and they already existed.
*/
/*
Reads a camera block. The projection key picks the mode, and the mode decides
which other key is required:

	camera = { projection = "PERSPECTIVE"  fovy = 45.0   main = true }
	camera = { projection = "ORTHOGRAPHIC" height = 10.0 }

A perspective block with a height, or an orthographic block with a fovy, is a
parse error rather than a silently ignored key.
*/
camera_from_mjson :: proc(entity_id: entity.Id, value: json.Value) -> error.Code {
	obj := mjson.as_object(value) or_return
	proj_str := mjson.as_string(obj["projection"]) or_return

	projection: component.CameraProjection
	switch proj_str {
	case "PERSPECTIVE":
		fovy := mjson.as_float(obj["fovy"]) or_return
		projection = component.Perspective{fovy = f32(fovy)}
	case "ORTHOGRAPHIC":
		height := mjson.as_float(obj["height"]) or_return
		projection = component.Orthographic{height = f32(height)}
	case:
		return .PARSE_ERROR
	}

	component.camera_create(entity_id, projection)

	if main_val, has_main := obj["main"]; has_main {
		if is_main, ok := main_val.(json.Boolean); ok && bool(is_main) {
			return component.set_main_camera(entity_id)
		}
	}
	return .NONE
}
