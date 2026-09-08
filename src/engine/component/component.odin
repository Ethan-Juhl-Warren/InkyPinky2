
package component
import "../entity"
import "../registry"

@(private) Init_Manager_Proc :: proc()
@(private) Destroy_Manager_Proc :: proc()

TOTAL_COMPONENTS :: 4

@(private) component_manager_initializer_list := [TOTAL_COMPONENTS]Init_Manager_Proc {
    init_camera_manager,
    init_rigidbody_manager,
    init_transform_manager,
    inti_script_manager,
}

@(private) component_manager_destructor_list := [TOTAL_COMPONENTS]Destroy_Manager_Proc {
    destroy_camera_manager,
    destroy_rigidbody_manager,
    destroy_transform_manager,
    destroy_script_manager,
}



init_component_managers :: proc() {
    for init_proc in component_manager_initializer_list {
        init_proc()
    }
}

destroy_component_managers :: proc() {
    for destroy_proc in component_manager_destructor_list {
        destroy_proc()
    }
}

release_entity_components :: proc(entity_id: entity.Id) {
    registry.destroy_item(&camera_manager.registry, entity_id)
    registry.destroy_item(&rigidbody_manager.registry, entity_id)
    registry.destroy_item(&transform_manager.registry, entity_id)
    registry.destroy_item(&script_manager.registry, entity_id)
}