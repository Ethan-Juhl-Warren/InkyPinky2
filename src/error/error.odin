package error
import "base:runtime"
import "core:fmt"
import "core:strings"

/*
Identifies a failure. Every engine procedure that can fail returns one of these,
with `.NONE` meaning success.

Adding a member here is a compile error until it is described in `INFO` below.
*/
Code :: enum i32 {
	NONE = 0,
	ID_INVALID,
	OBJECT_NOT_FOUND,
	OBJECT_ALREADY_EXISTS,
	SCENE_IS_ACTIVE,
	NAME_EXISTS,
	ADDING_CAMERA_TO_ENTITY_WITH_NO_TRANSFORM,
	INVALID_CAMERA_PROJECTION,
	NO_MAIN_CAMERA_SET,
	INVALID_CAMERA,
	MANAGER_ALREADY_INITILIZED,
	DESTROYING_UNINITILIZED_MANAGER,
}

/*
How loud a code is. Only affects the tag and the colour on the printed message.
*/
Severity :: enum {
	WARNING,
	ERROR,
}

/*
What a code means and what to do about it. `hint` is the line that turns
"something broke" into "here is how to fix it", so it is worth filling in.
*/
@(private)
Info :: struct {
	message: string,
	hint: string,
	severity: Severity,
}

/*
Describes every Code.

Enumerated array literals have to be fully populated in Odin, so adding a Code
without describing it here is a compile error rather than a silent
"error message unimplemented" at runtime.
*/
@(private, rodata)
INFO := [Code]Info {
	.NONE = {
		message = "none",
		severity = .WARNING,
	},
	.ID_INVALID = {
		message = "Invalid ID supplied to manager",
		hint = "IDs must come from a create() call and be above registry.UNASSIGNED_ID",
		severity = .ERROR,
	},
	.OBJECT_NOT_FOUND = {
		message = "Object could not be found",
		hint = "the ID is well formed but nothing is registered under it, it may already have been destroyed",
		severity = .ERROR,
	},
	.OBJECT_ALREADY_EXISTS = {
		message = "Object already exists on entity",
		hint = "registires cannot have multiple objects indexed by the same key",
		severity = .ERROR
	},
	.SCENE_IS_ACTIVE = {
		message = "Cannot delete active scene",
		hint = "switch to another scene with scene.set_active first",
		severity = .WARNING,
	},
	.NAME_EXISTS = {
		message = "Supplied entity name already exists",
		hint = "entity names are unique, pick another or look the existing one up with entity.get_by_name",
		severity = .WARNING,
	},
	.ADDING_CAMERA_TO_ENTITY_WITH_NO_TRANSFORM = {
		message = "Attempted to add camera component to entity with no transform",
		hint = "call transform_create on the entity before camera_create",
		severity = .ERROR,
	},
	.INVALID_CAMERA_PROJECTION = {
		message = "Invalid camera projection, projection type either unknown or none",
		hint = "use .PERSPECTIVE or .ORTHOGRAPHIC",
		severity = .ERROR,
	},
	.NO_MAIN_CAMERA_SET = {
		message = "No main camera set",
		hint = "nominate one with cmpt.set_main_camera(entity_id)",
		severity = .ERROR,
	},
	.INVALID_CAMERA = {
		message = "Cannot perform operation on invalid camera",
		hint = "the entity has no camera component, add one with camera_create",
		severity = .ERROR,
	},
	.MANAGER_ALREADY_INITILIZED = {
		message = "Attempted to intilize a manager that is already intilized",
		hint = "only intilize managers if they are unititilized or after they have been destroyed",
		severity = .WARNING,
	},
	.DESTROYING_UNINITILIZED_MANAGER = {
		message = "Attempted to destroy a manager that is unitinilized",
		hint = "do not call destroy on a uninitilized manager"
	}
}

/*
Describes what went wrong.

Inputs:
- code: The code to describe

Returns:
- The human readable message for `code`, or a placeholder if it is out of range
*/
get_error_message :: proc(code: Code) -> string {
	return INFO[code].message if code >= min(Code) && code <= max(Code) else "error message unimplemented"
}

/*
Suggests what to do about a failure.

Inputs:
- code: The code to advise on

Returns:
- The hint for `code`, or "" when it has no advice attached
*/
get_error_hint :: proc(code: Code) -> string {
	return INFO[code].hint if code >= min(Code) && code <= max(Code) else ""
}

/*
Reports how loud a code is.

Inputs:
- code: The code to classify

Returns:
- The severity of `code`, defaulting to `.ERROR` if it is out of range
*/
get_severity :: proc(code: Code) -> Severity {
	return INFO[code].severity if code >= min(Code) && code <= max(Code) else .ERROR
}

// Set to false to strip the ANSI colour codes, e.g. when piping output to a file.
color := true

// Set to false to drop the "hint:" line once the messages stop being news.
hints := true

/*
Prints a code to stderr, along with its hint and the call site.

Returning whether it was a failure lets the whole notice-and-bail pattern fit on
one line:

	if error.print(cmpt.set_main_camera(cam)) { return }

Inputs:
- code: The code to print, `.NONE` prints nothing
- loc: The call site, captured automatically

Returns:
- true when `code` was a failure, false for `.NONE`

Example:
	[ERROR] NO_MAIN_CAMERA_SET: No main camera set
	  hint: nominate one with cmpt.set_main_camera(entity_id)
	    at: src/main.odin:70:3 in main
*/
print :: proc(code: Code, loc := #caller_location) -> bool {
	if code == .NONE {
		return false
	}
	buf: [1024]byte
	b := strings.builder_from_bytes(buf[:])
	_write(&b, code, "", loc)
	fmt.eprint(strings.to_string(b))
	return true
}

/*
Prints a code the way `print` does, plus a "what:" line saying what was being
attempted when it failed.

Inputs:
- code: The code to print, `.NONE` prints nothing
- format: A format string describing the attempt, as taken by `fmt.printf`
- args: Arguments for `format`
- loc: The call site, captured automatically

Returns:
- true when `code` was a failure, false for `.NONE`

Example:
	error.printf(err, "removing entity %d from scene %q", id, scene_name)

Output:
	[ERROR] OBJECT_NOT_FOUND: Object could not be found
	  what: removing entity 42 from scene "level_1"
	  hint: the ID is well formed but nothing is registered under it, it may already have been destroyed
	    at: src/scene/scene.odin:156:2 in remove_entity
*/
printf :: proc(code: Code, format: string, args: ..any, loc := #caller_location) -> bool {
	if code == .NONE {
		return false
	}
	detail_buf: [512]byte
	d := strings.builder_from_bytes(detail_buf[:])
	fmt.sbprintf(&d, format, ..args)

	buf: [1024]byte
	b := strings.builder_from_bytes(buf[:])
	_write(&b, code, strings.to_string(d), loc)
	fmt.eprint(strings.to_string(b))
	return true
}

/*
Prints a code and aborts. For failures there is no sensible way to continue from.

Inputs:
- code: The code to print, `.NONE` returns without aborting
- loc: The call site, captured automatically and reported in the panic
*/
must :: proc(code: Code, loc := #caller_location) {
	if code == .NONE {
		return
	}
	print(code, loc)
	panic(get_error_message(code), loc)
}

/*
Builds the same text `print` emits, for pushing errors somewhere other than a
terminal such as an in-game console.

*Allocates Using Temp Allocator*

Inputs:
- code: The code to render
- detail: Text for the "what:" line, omitted when ""
- loc: The call site, captured automatically

Returns:
- The formatted message, valid until the temp allocator is next reset
*/
format :: proc(code: Code, detail := "", loc := #caller_location) -> string {
	b := strings.builder_make(context.temp_allocator)
	_write(&b, code, detail, loc)
	return strings.to_string(b)
}

/*
Lays a code out into a builder. The single place the layout is defined, shared by
`print`, `printf` and `format`.

Inputs:
- b: The builder to write into
- code: The code being reported
- detail: Text for the "what:" line, omitted when ""
- loc: The call site to attribute the failure to

Example:
	[ERROR] NO_MAIN_CAMERA_SET: No main camera set
	  what: while beginning the frame draw
	  hint: nominate one with cmpt.set_main_camera(entity_id)
	    at: src/main.odin:70:3 in main
*/
@(private)
_write :: proc(b: ^strings.Builder, code: Code, detail: string, loc: runtime.Source_Code_Location) {
	tag := "\e[1;31m" if color else ""
	if get_severity(code) == .WARNING {
		tag = "\e[1;33m" if color else ""
	}
	cyan := "\e[36m" if color else ""
	grey := "\e[90m" if color else ""
	reset := "\e[0m" if color else ""

	label := "[ERROR]" if get_severity(code) == .ERROR else "[WARN] "
	fmt.sbprintfln(b, "%s%s %v%s: %s", tag, label, code, reset, get_error_message(code))

	if detail != "" {
		fmt.sbprintfln(b, "  %swhat:%s %s", grey, reset, detail)
	}
	if hint := get_error_hint(code); hints && hint != "" {
		fmt.sbprintfln(b, "  %shint:%s %s%s%s", grey, reset, cyan, hint, reset)
	}
	fmt.sbprintfln(
		b, "    %sat: %s:%d:%d in %s%s",
		grey, _short_path(loc.file_path), loc.line, loc.column, loc.procedure, reset,
	)
}

/*
Shortens an absolute source path for display, turning
"E:\Dev\3DEngine\src\main.odin" into "src/main.odin".

*Allocates Using Temp Allocator*

Inputs:
- path: The path to shorten, normally `loc.file_path`

Returns:
- The path from the last "src" onwards with forward slashes, or the whole path
  unchanged if it contains no "src"
*/
@(private)
_short_path :: proc(path: string) -> string {
	short := path
	if i := strings.last_index(path, "src"); i >= 0 {
		short = path[i:]
	}
	short, _ = strings.replace_all(short, "\\", "/", context.temp_allocator)
	return short
}
