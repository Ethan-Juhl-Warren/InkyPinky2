package id

// An Id is an 8-byte handle: the scene an entity belongs to, plus its index
// within that scene.
//
// Bit layout, LSB first:
//
//   [ 0 ..31 ]  index  u32, entity index within its scene
//   [32 ..63 ]  scene  u32, always >= SCENE_FIRST
//
// Scene numbering starts at 1, so zero is unreachable by construction and is
// the single invalid value. Because the scene is part of the handle, indices
// restart per scene and two scenes can be resident in the same manager at
// once without their ids colliding.
//
// The scene occupies the high bits, so the numeric order of an Id is
// scene-major: sorting ids makes each scene a contiguous run. That is what
// lets a preload sit interleaved in the arrays, get sorted into place after
// the swap, and then be truncated away by a shrink.

Id :: distinct u64

INDEX_BITS :: 32

INDEX_MASK :: u64(1) << INDEX_BITS - 1
SCENE_MASK :: ~INDEX_MASK

SCENE_FIRST :: u32(1)

// The zero value, and the only invalid one.
INVALID :: Id(0)

#assert(size_of(Id) == 8)
#assert(u64(INVALID) == 0) // must stay the zero value, do not change

make_id :: proc(scene: u32, index: u32) -> Id {
	assert(scene >= SCENE_FIRST, "id.make_id: scene 0 is reserved, number scenes from SCENE_FIRST")
	return Id(u64(index) | u64(scene) << INDEX_BITS)
}

index :: proc "contextless" (id: Id) -> u32 {
	return u32(u64(id) & INDEX_MASK)
}

scene :: proc "contextless" (id: Id) -> u32 {
	return u32(u64(id) >> INDEX_BITS)
}

is_valid :: proc "contextless" (id: Id) -> bool {
	return scene(id) >= SCENE_FIRST
}

// tag_of is the scene's bit pattern in Id space, for comparing against a
// handle without extracting the field. Hoist it out of a per-entity loop and
// the filter is a mask and a compare.
tag_of :: proc "contextless" (scene: u32) -> Id {
	return Id(u64(scene) << INDEX_BITS)
}

in_scene :: proc "contextless" (id: Id, tag: Id) -> bool {
	return Id(u64(id) & SCENE_MASK) == tag
}

same_scene :: proc "contextless" (a, b: Id) -> bool {
	return (u64(a) ~ u64(b)) & SCENE_MASK == 0
}

// bounds_of is the inclusive Id range a scene occupies once ids are sorted.
// Everything below lo is an older scene, everything above hi is a newer one.
bounds_of :: proc "contextless" (scene: u32) -> (lo, hi: Id) {
	tag := tag_of(scene)
	return tag, Id(u64(tag) | INDEX_MASK)
}
