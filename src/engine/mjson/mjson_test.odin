package mjson

import "core:testing"
import "core:encoding/json"

@(test)
test_vec3_parses_three_floats :: proc(t: ^testing.T) {
	value, err := json.parse_string(`[1, 2, 3]`, spec = .MJSON)
	testing.expect(t, err == .None)
	defer json.destroy_value(value)

	v, code := vec3(value)
	testing.expect(t, code == .NONE)
	testing.expect_value(t, v, [3]f32{1, 2, 3})
}

@(test)
test_vec3_rejects_wrong_length :: proc(t: ^testing.T) {
	value, _ := json.parse_string(`[1, 2]`, spec = .MJSON)
	defer json.destroy_value(value)

	_, code := vec3(value)
	testing.expect(t, code == .PARSE_ERROR)
}

@(test)
test_as_object_rejects_non_object :: proc(t: ^testing.T) {
	value, err := json.parse_string(`["hello"]`, spec = .MJSON)
	testing.expect(t, err == .None)
	defer json.destroy_value(value)

	arr, ok := value.(json.Array)
	testing.expect(t, ok)

	_, code := as_object(arr[0])
	testing.expect(t, code == .PARSE_ERROR)
}

@(test)
test_parse_rejects_malformed_input :: proc(t: ^testing.T) {
	_, code := parse(transmute([]byte)string("{ this is not valid"))
	testing.expect(t, code == .PARSE_ERROR)
}
