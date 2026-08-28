package mjson

import "core:encoding/json"
import "../error"

parse :: proc(data: []byte) -> (json.Value, error.Code) {
	root, err := json.parse(data, spec = .MJSON)
	if err != .None {
		//json.destroy_value(root)			// TODO with or without this there ends up being a memory leak, will look into it sometime
		return nil, .PARSE_ERROR
	}
	return root, .NONE
}

as_object :: proc(v: json.Value) -> (json.Object, error.Code) {
	o, ok := v.(json.Object)
	if !ok { return nil, .PARSE_ERROR }
	return o, .NONE
}

as_array :: proc(v: json.Value) -> (json.Array, error.Code) {
	a, ok := v.(json.Array)
	if !ok { return nil, .PARSE_ERROR }
	return a, .NONE
}

as_string :: proc(v: json.Value) -> (string, error.Code) {
	s, ok := v.(json.String)
	if !ok { return "", .PARSE_ERROR }
	return string(s), .NONE
}

as_float :: proc(v: json.Value) -> (f64, error.Code) {
	f, ok := v.(json.Float)
	if !ok { return 0, .PARSE_ERROR }
	return f64(f), .NONE
}

vec3 :: proc(value: json.Value) -> (v: [3]f32, err: error.Code) {
	arr := as_array(value) or_return
	if len(arr) != 3 { return {}, .PARSE_ERROR }
	x := as_float(arr[0]) or_return
	y := as_float(arr[1]) or_return
	z := as_float(arr[2]) or_return
	return {f32(x), f32(y), f32(z)}, .NONE
}

quat :: proc(value: json.Value) -> (q: quaternion128, err: error.Code) {
	arr := as_array(value) or_return
	if len(arr) != 4 { return {}, .PARSE_ERROR }
	x := as_float(arr[0]) or_return
	y := as_float(arr[1]) or_return
	z := as_float(arr[2]) or_return
	w := as_float(arr[3]) or_return
	return quaternion(x = f32(x), y = f32(y), z = f32(z), w = f32(w)), .NONE
}