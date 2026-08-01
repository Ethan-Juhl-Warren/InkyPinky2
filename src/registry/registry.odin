package registry

import "../error"

RegistryId :: distinct int

INVALID_ID :: -1
UNASSIGNED_ID :: 0


Registry :: struct($T: typeid) {
	items: [dynamic]T,
	id_of: [dynamic]RegistryId,
	slot_of: map[RegistryId]int,
	next_id: RegistryId,
	free_item: proc(^T),
}

init_registry :: proc(registry: ^Registry($T), free_item: proc(^T) = nil) {
	assert(registry != nil, "init_registry: cannot init null, must allocate registry")
	registry.items = make([dynamic]T)
	registry.id_of = make([dynamic]RegistryId)
	registry.slot_of = make(map[RegistryId]int)
	registry.next_id = UNASSIGNED_ID
	registry.free_item = free_item
}

destroy_registry :: proc(registry: ^Registry($T)) {
	assert(registry != nil, "destroy_registry: cannot destroy null registry")
	if registry == nil {
		return
	}
	if registry.free_item != nil {
		for &item in registry.items {
			registry.free_item(&item)
		}
	}
	delete(registry.items)
	delete(registry.id_of)
	delete(registry.slot_of)
	registry.next_id = UNASSIGNED_ID
}

get_item :: proc(registry: ^Registry($T), item_id: RegistryId) -> (^T, error.Code) {
	assert(registry != nil, "get_item: cannot insert into null registry")
	if item_id <= INVALID_ID {
		return nil, .ID_INVALID
	}
	index, present := registry.slot_of[item_id]
	if !present {
		return nil, .OBJECT_NOT_FOUND,
	}
	return &registry.items[index], .NONE
}

create_item :: proc(registry: ^Registry($T), #by_ptr item: T) -> (RegistryId, error.Code) {
	assert(registry != nil, "create_item: cannot create item on null registry")
	registry.next_id += 1
	id := registry.next_id

	append(&registry.items, item)
	append(&registry.id_of, id)
	registry.slot_of[id] = len(registry.items) - 1

	return id, .NONE
}

destroy_item :: proc(registry: ^Registry($T), item_id: RegistryId) -> error.Code {
	assert(registry != nil, "destroy_item: cannot destroy item on null registry")
	if item_id <= INVALID_ID {
		return .ID_INVALID
	}
	index, present := registry.slot_of[item_id]
	if !present {
		return .OBJECT_NOT_FOUND,
	}

	if registry.free_item != nil {
		registry.free_item(&registry.items[index])
	}

	last := len(registry.items) - 1
	moved_id := registry.id_of[last]

	unordered_remove(&registry.items, index)
	unordered_remove(&registry.id_of, index)

	if index != last {
		registry.slot_of[moved_id] = index
	}
	delete_key(&registry.slot_of, item_id)

	return .NONE
}

registry_slice :: proc(registry: ^Registry($T)) -> []T {
	assert(registry != nil, "registry_slice: cannot get slice of null registry")
	return registry.items[:]
}

registry_len :: proc(registry: ^Registry($T)) -> int {
	assert(registry != nil, "registry_len: cannot get length of null registry")
	return len(registry.items)
}
