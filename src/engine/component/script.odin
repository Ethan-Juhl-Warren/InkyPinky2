package component
import "../error"
import "../registry"
import "../entity"
import lua "vendor:lua/5.4"

@(private) script_manager: ScriptManager

Script :: distinct int

@(private)
ScriptManager :: struct {
    script_registry: registry.Registry(Script, entity.Id),
    initialized: bool
}

/*
initializes the script manager, must be called prior to any function that deals with scripts
a corresponding call to destroy_script_manager must be called to cleanup

Note:

This individually initializes the script manager
See also init_component_managers, which initializes all component managers
*/
inti_script_manager :: proc() {
    if script_manager.initialized {
        error.printf(.MANAGER_ALREADY_INITIALIZED, "initilizing transform manager")
        return
    }
    registry.init_registry(&script_manager.script_registry, nil)
    transform_manager.initialized = true
}

/*
Destroys the script manager, must be called at cleanup time to free the script system

Note:

This individually destroys the script manager
See also destroy_component_managers, which destroys all component mangers
*/
destroy_script_manager :: proc() {
    if !script_manager.initialized {
        error.printf(.DESTROYING_UNINITIALIZED_MANAGER, "destroying script manager")
        return
    }
    registry.destroy_registry(&script_manager.script_registry)
    script_manager.initialized = false
}


script_create :: proc(entity_id: entity.Id, script_ref: Script) {
    assert(script_manager.initialized, "script_create: script manager not initialized, call init_script_manager first")
    err := registry.create_item(&script_manager.script_registry, entity_id, script_ref)
    error.must(err)
}

script_destroy :: proc(entity_id: entity.Id) {
    assert(script_manager.initialized, "script_create: script manager not initialized, call init_script_manager first")
    _, present := registry.get_item(&script_manager.script_registry, entity_id)
    error.must(present)
    registry.destroy_item(&transform_manager.transform_registry, entity_id)
}