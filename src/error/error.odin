package error
import "core:fmt"

Code :: enum i32 {
	NONE = 0,
	ID_INVALID,
	OBJECT_NOT_FOUND,
	SCENE_IS_ACTIVE,
	NAME_EXISTS,
	ADDING_CAMERA_TO_ENTITY_WITH_NO_TRANSFORM,
	INVALID_CAMERA_PROJECTION,
	NO_MAIN_CAMERA_SET,
	INVALID_CAMERA
}

get_error_message :: proc(code: Code) -> string {
	switch code {
		case .ID_INVALID:  return "Invalid ID supplied to manager"
		case .OBJECT_NOT_FOUND: return "Object could not be found"
		case .SCENE_IS_ACTIVE: return "Cannot delete active scene"
		case .NAME_EXISTS: return "Supplied entity name already exists"
		case .INVALID_CAMERA: return "Cannot perform operation on invalid camera"
		case .NO_MAIN_CAMERA_SET: return "No main camera set"
		case .ADDING_CAMERA_TO_ENTITY_WITH_NO_TRANSFORM: return "Attempted to add camera component to entity with no transform"
		case .INVALID_CAMERA_PROJECTION: return "Invalid camera projection, projection type either unknown or none"
		case .NONE: return "none"
		case: return "error message unimplemented"
	}
}

