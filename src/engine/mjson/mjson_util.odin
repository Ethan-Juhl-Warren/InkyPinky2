package mjson

import "core:mem/virtual"
import "core:encoding/json"
import "../error"

/*
Parses Json out of a byte array

Inputs:
- data: []byte The file data

Outputs:
The root of the json file
An error code
*/
parse :: proc(data: []byte) -> (json.Value, error.Code) {
	// This is a load os shinanigans as a result of a memory leak on the failure path of json.parse
	arena: virtual.Arena
	_ = virtual.arena_init_growing(&arena, 128)
	defer virtual.arena_destroy(&arena)
	local_allocator := virtual.arena_allocator(&arena)

	root, err := json.parse(data, spec = .MJSON, allocator = local_allocator)
	if err != .None {
		return nil, .PARSE_ERROR
	}
	permanent_root := json.clone_value(root, context.allocator)

	return permanent_root, .NONE
}

/*
Casts a json value to a json object if valid returns an error if not
*/
as_object :: proc(value: json.Value) -> (json.Object, error.Code) {
	object, ok := value.(json.Object)
	if !ok {
		return nil, .PARSE_ERROR
	}
	return object, .NONE
}

/*
Casts a json value to a json array if valid returns an error if not
*/
as_array :: proc(value: json.Value) -> (json.Array, error.Code) {
	a, ok := value.(json.Array)
	if !ok {
		return nil, .PARSE_ERROR
	}
	return a, .NONE
}

/*
Casts a json value to a string if valid returns an error if not
*/
as_string :: proc(value: json.Value) -> (string, error.Code) {
	s, ok := value.(json.String)
	if !ok {
		return "", .PARSE_ERROR
	}
	return string(s), .NONE
}

/*
Casts a json value to a float if valid returns an error if not
*/
as_float :: proc(value: json.Value) -> (f64, error.Code) {
	f, ok := value.(json.Float)
	if !ok {
		return 0, .PARSE_ERROR
	}
	return f64(f), .NONE
}

/*
Parses a vec3 from a json value

Inputs:
- value: json.Value The json value

Outputs:
- vec: [3]f32 The vector3
- err: An error code
*/
vec3 :: proc(value: json.Value) -> (vec: [3]f32, err: error.Code) {
	arr := as_array(value) or_return
	if len(arr) != 3 {
		return {}, .PARSE_ERROR
	}
	x := as_float(arr[0]) or_return
	y := as_float(arr[1]) or_return
	z := as_float(arr[2]) or_return
	return {f32(x), f32(y), f32(z)}, .NONE
}

/*
Parses a quaternion from a json value

Inputs:
- value: json.Value The json value

Outputs:
- q: quaternion128 A quaternion having the data of value
- err: error.Code An error
*/
quat :: proc(value: json.Value) -> (q: quaternion128, err: error.Code) {
	arr := as_array(value) or_return
	if len(arr) != 4 {
		return {}, .PARSE_ERROR
	}
	x := as_float(arr[0]) or_return
	y := as_float(arr[1]) or_return
	z := as_float(arr[2]) or_return
	w := as_float(arr[3]) or_return
	return quaternion(x = f32(x), y = f32(y), z = f32(z), w = f32(w)), .NONE
}