package scene
import "../entity"
import "../registry"
import "../error"
import "../component"
import "../file"
import "core:strings"



@(private) scene_manager: SceneManager

Id :: distinct u32

SceneDescriptor :: struct {
	name: string,
	refrence: file.AssetRefrence,
	id: Id
}

SceneManifest :: struct {
	scenes_descriptors: [dynamic]SceneDescriptor,
	scene_names: map[string]Id
}

@(private)
Scene :: struct {
	id: Id,
	name: string,
	next_entity_id: u32,
	entities: [dynamic]entity.Id,
}

@(private)
SceneManager :: struct {
	active_scene: ^Scene,
	next_scene: ^Scene,
	scene_manifest: SceneManifest,
	initialized: bool
}

init_scene_manager :: proc() {
	scene_manager.active_scene = new(Scene)
	scene_manager.next_scene = new(Scene)
	_init_scene(scene_manager.active_scene)
	_init_scene(scene_manager.next_scene)
	_init_manifest(&scene_manager.scene_manifest)
	scene_manager.initialized = true
}

destroy_scene_manager :: proc() {
	_destroy_scene(scene_manager.active_scene)
	_destroy_scene(scene_manager.next_scene)
	scene_manager.active_scene = nil
	scene_manager.next_scene = nil
	_destroy_manifest(&scene_manager.scene_manifest)
	scene_manager.initialized = false
}

create_entity :: proc() -> entity.Id {
	assert(scene_manager.initialized, "create_entity: scene manager not initialized, call init_scene_manager first")

	scene_manager.active_scene.next_entity_id += 1 
	id := entity.make_id(u32(scene_manager.active_scene.id), u32(scene_manager.active_scene.next_entity_id))
	append(&scene_manager.active_scene.entities, id)
	return id
}

preload_entity :: proc() -> entity.Id {
	assert(scene_manager.initialized, "preload_entity: scene manager not initialized, call init_scene_manager first")

	scene_manager.next_scene.next_entity_id += 1
	id := entity.make_id(u32(scene_manager.next_scene.id), u32(scene_manager.next_scene.next_entity_id))
	append(&scene_manager.next_scene.entities, id)
	return id
}

destroy_entity :: proc(entity_id: entity.Id) {
	assert(scene_manager.initialized, "destroy_entity_by_id: scene manager not initialized, call init_scene_manager first")

	unordered_remove(&scene_manager.active_scene.entities, entity_id)
	component.release_entity_components(entity_id)
}

get_manifest :: proc() -> ^SceneManifest {
	assert(scene_manager.initialized, "get_manifest: scene manager not initialized")
	return &scene_manager.scene_manifest
}

@(private)
_init_manifest :: proc(scene_manifest: ^SceneManifest) {
	scene_manifest.scene_names = make(map[string]Id)
	scene_manifest.scenes_descriptors = make([dynamic]SceneDescriptor)
}

@(private)
_destroy_manifest :: proc(scene_manifest: ^SceneManifest) {
	delete(scene_manifest.scene_names)
	delete(scene_manifest.scenes_descriptors)
}

@(private)
_init_scene :: proc(scene: ^Scene) {
	if scene == nil {
		return
	}
	scene.entities = make([dynamic]entity.Id)
	scene.next_entity_id = 0
}

@(private)
_destroy_scene :: proc(scene: ^Scene) {
	if scene == nil {
		return
	}
	delete(scene.entities)
	free(scene)
}

