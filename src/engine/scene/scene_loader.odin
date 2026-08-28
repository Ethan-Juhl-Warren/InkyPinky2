#+feature dynamic-literals
package scene

import "core:encoding/json"
import "../component"
import "../entity"
import "../error"
import "../mjson"
import "../file"

@(private)
Component_Parser :: proc(entity.Id, json.Value) -> error.Code

@(private)
component_parsers := map[string]Component_Parser {
	"transform" = component.transform_from_mjson,
	"camera"    = component.camera_from_mjson,
	"rigidbody" = component.rigidbody_from_mjson,
	// "model" : will do but model isnt set up yet
}

load_manifest :: proc(path: string) -> (manifest: SceneManifest, err: error.Code) {
	data := file.read_asset(path) or_return
	defer delete(data)

	root := mjson.parse(data) or_return
	defer json.destroy_value(root)

	obj := mjson.as_object(root) or_return          // or move _as_x into a shared package, see note below
	scenes := mjson.as_array(obj["scenes"]) or_return

	for entry in scenes {
		entry_obj := mjson.as_object(entry) or_return
		name := mjson.as_string(entry_obj["name"]) or_return
		index_f := mjson.as_float(entry_obj["index"]) or_return
		index := Id(index_f)
		desc_path := mjson.as_string(entry_obj["descriptor"]) or_return

		descriptor := SceneDescriptor{name = name, id = index, path = desc_path}
		manifest.by_name[name] = descriptor
		manifest.by_index[index] = descriptor
	}
	manifest.initialized = true
	return manifest, .NONE
}

load_scene_by_name :: proc(manifest: ^SceneManifest, name: string) -> error.Code {
	descriptor, found := manifest.by_name[name]
	if !found {
		return .OBJECT_NOT_FOUND
	}
	return _load_scene_descriptor(descriptor)
}

load_scene_by_index :: proc(manifest: ^SceneManifest, index: Id) -> error.Code {
	descriptor, found := manifest.by_index[index]
	if !found {
		return .OBJECT_NOT_FOUND
	}
	return _load_scene_descriptor(descriptor)
}

@(private)
_load_scene_descriptor :: proc(descriptor: SceneDescriptor) -> error.Code {
	data := file.read_asset(descriptor.path) or_return
	defer delete(data)

	root := mjson.parse(data) or_return
	defer json.destroy_value(root)

	obj := mjson.as_object(root) or_return

	// config gravity and ambient not read yet, doesnt exist to deal with, consult InkyPinky Grand Wizard to move forward

	entities := mjson.as_array(obj["entities"]) or_return
	for entity_value in entities {
		entity_obj := mjson.as_object(entity_value) or_return
		name := mjson.as_string(entity_obj["name"]) or_return

		id := add_entity(name, descriptor.id)

		for key, value in entity_obj {
			if key == "name" { continue }
			if key == "model" { continue } // TODO no ModelManager yet
			parser, known := component_parsers[key]
			if !known { continue }
			if err := parser(id, value); err != .NONE {
				return err
			}
		}
	}
	return .NONE
}