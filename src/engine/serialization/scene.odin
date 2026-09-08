package serialization
import "core:encoding/json"
import "../scene"
import "../file"
import "../error"
import "../mjson"


scene_manifest_from_mjson :: proc(manifest:  ^scene.SceneManifest, path: string) -> error.Code {
	assert(manifest != nil, "Cannot load to a nil manifest")
	data := file.read_asset(path) or_return
	defer delete(data)

	root := mjson.parse(data) or_return
	defer json.destroy_value(root)

	obj := mjson.as_object(root) or_return
	scenes := mjson.as_array(obj["scenes"]) or_return

	scene_count := len(scenes)
	
	for entry in scenes {
		entry_obj := mjson.as_object(entry) or_return
		name := mjson.as_string(entry_obj["name"]) or_return
		index_f := mjson.as_float(entry_obj["index"]) or_return
		index := scene.Id(index_f)
		desc_path := mjson.as_string(entry_obj["descriptor"]) or_return

		descriptor := scene.SceneDescriptor{name = name, id = index, refrence = desc_path}
		manifest.scenes_descriptors[index] = descriptor
		manifest.scene_names[name] = index
	}

	return .NONE
}


@(private)
_load_scene_descriptor :: proc(descriptor: scene.SceneDescriptor) -> error.Code {
	data := file.read_asset(descriptor.refrence) or_return
	defer delete(data)

	root := mjson.parse(data) or_return
	defer json.destroy_value(root)

	obj := mjson.as_object(root) or_return

	// config gravity and ambient not read yet, doesnt exist to deal with, consult InkyPinky Grand Wizard to move forward

	entities := mjson.as_array(obj["entities"]) or_return
	for entity_value in entities {
		entity_obj := mjson.as_object(entity_value) or_return

		id := scene.preload_entity()

		for key, value in entity_obj {
			if key == "name" { continue }
			if key == "model" { continue } // TODO no ModelManager yet
			parser, known := component_parsers[key]
			if !known {
				return .PARSE_ERROR
			}
			if err := parser(id, value); err != .NONE {
				return err
			}
		}
	}
	return .NONE
}

load_scene_by_name :: proc(name: string) -> error.Code {
    manifest := scene.get_manifest()
	index, found := manifest.scene_names[name]
	if !found {
		return .OBJECT_NOT_FOUND
	}
	return _load_scene_descriptor(manifest.scenes_descriptors[int(index)])
}

load_scene_by_index :: proc(index: scene.Id) -> error.Code {
    manifest := scene.get_manifest()
	if index < 0 || int(index) > len(manifest.scenes_descriptors) {
		return .ID_INVALID
	}
	descriptor := manifest.scenes_descriptors[index]
	return _load_scene_descriptor(descriptor)
}
