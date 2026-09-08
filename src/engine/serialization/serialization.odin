package serialization

init_serialization_system :: proc() {
    _build_component_parser_map()
}

destroy_serialization_system :: proc() {
    _destroy_component_parser_map()
}