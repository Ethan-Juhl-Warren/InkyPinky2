
package component

@(private) Init_Manager_Proc :: proc()
@(private) Destroy_Manager_Proc :: proc()

@(private) component_initializer_list := [4]Init_Manager_Proc {
    init_camera_manager,
    init_rigidbody_manager,
    init_transform_manager,
    inti_script_manager,
}

@(private) component_destructor_list := [4]Destroy_Manager_Proc {
    destroy_camera_manager,
    destroy_rigidbody_manager,
    destroy_transform_manager,
    destroy_script_manager,
}

init_component_managers :: proc() {
    for init_proc in component_initializer_list {
        init_proc()
    }
}

destroy_component_managers :: proc() {
    for destroy_proc in component_destructor_list {
        destroy_proc()
    }
}