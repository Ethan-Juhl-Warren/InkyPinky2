package registry

import "../error"

INVALID_ID :: -1
UNASSIGNED_ID :: 0


Registry :: struct($T: typeid, $K: typeid) {
	items: [dynamic]T,
	id_of: [dynamic]K,
	slot_of: map[K]int,
	free_item: proc(^T),
}

init_registry :: proc(registry: ^Registry($T, $K), free_item: proc(^T) = nil) {
	assert(registry != nil, "init_registry: cannot init null, must allocate registry")
	registry.items = make([dynamic]T)
	registry.id_of = make([dynamic]K)
	registry.slot_of = make(map[K]int)
	registry.free_item = free_item
}

destroy_registry :: proc(registry: ^Registry($T, $K)) {
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
}

get_item :: proc(registry: ^Registry($T, $K), item_id: K) -> (^T, error.Code) {
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

create_item :: proc(registry: ^Registry($T, $K), item_id: K, #by_ptr item: T) -> error.Code {
	assert(registry != nil, "create_item: cannot create item on null registry")
	if item_id <= INVALID_ID {
		return .ID_INVALID
	}
	if item_id in registry.slot_of {
		return .OBJECT_ALREADY_EXISTS
	}
	append(&registry.items, item)
	append(&registry.id_of, item_id)
	registry.slot_of[item_id] = len(registry.items) - 1
	return .NONE
}

destroy_item :: proc(registry: ^Registry($T, $K), item_id: K) -> error.Code {
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

registry_slice :: proc(registry: ^Registry($T, $K)) -> []T {
	assert(registry != nil, "registry_slice: cannot get slice of null registry")
	return registry.items[:]
}

registry_len :: proc(registry: ^Registry($T, $K)) -> int {
	assert(registry != nil, "registry_len: cannot get length of null registry")
	return len(registry.items)
}
