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

init_registry :: proc(registry: ^Registry($T), free_item: proc(^T)) {
	assert(registry != nil, "init_registry: cannot init null, must allocate registry")
	assert(free_item != nil, "init_registry: cannot supply nil free procudure leave default")
	registry.items = make([dynamic]T)
	registry.id_of = make([dynamic]RegistryId)
	registry.slot_of = make(map[RegistryId]int)
	registry.next_id = UNASSIGNED_ID
	registry.free_item = free_item
}

destroy_registry :: proc(registry: ^Registry($T)) {
	if registry == nil {
		return
	}
	assert(registry.free_item != nil, "destroy_registry: registry imporoperly initilized")
	for &item in registry.items {
		registry.free_item(&item)
	}
	delete(registry.items)
	delete(registry.id_of)
	delete(registry.slot_of)
	registry.next_id = UNASSIGNED_ID
}

get_registry_item :: proc(registry: ^Registry($T), item_id: RegistryId) -> (^T, error.ErrorCode) {
	if item_id <= INVALID_ID {
		return nil, error.ErrorCode.ID_INVALID
	}
	index, present := registry.slot_of[item_id]
	if !present {
		return nil, error.ErrorCode.OBJECT_NOT_FOUND,
	}
	return &registry.items[index], error.ErrorCode.NONE
}

new_registry_item :: proc(registry: ^Registry($T), item: T) -> (RegistryId, error.ErrorCode) {
	assert(registry != nil, "new_registry_item: cannot insert into null registry")
	registry.next_id += 1
	id := registry.next_id

	append(&registry.items, item)
	append(&registry.id_of, id)
	registry.slot_of[id] = len(registry.items) - 1

	return id, error.ErrorCode.NONE
}

remove_registry_item :: proc(registry: ^Registry($T), item_id: RegistryId) -> error.ErrorCode {
	if item_id <= INVALID_ID {
		return error.ErrorCode.ID_INVALID
	}
	index, present := registry.slot_of[item_id]
	if !present {
		return error.ErrorCode.OBJECT_NOT_FOUND,
	}

	registry.free_item(&registry.items[index])

	last := len(registry.items) - 1
	moved_id := registry.id_of[last]

	unordered_remove(&registry.items, index)
	unordered_remove(&registry.id_of, index)

	if index != last {
		registry.slot_of[moved_id] = index
	}
	delete_key(&registry.slot_of, item_id)

	return error.ErrorCode.NONE
}

registry_slice :: proc(registry: ^Registry($T)) -> []T {
	return registry.items[:]
}

registry_len :: proc(registry: ^Registry($T)) -> int {
	return len(registry.items)
}
