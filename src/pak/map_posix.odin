#+build linux, darwin
package pak

import "core:sys/posix"

/*
WRITTEN BY CLAUDE OPUS 5 (Anthropic), 2026-08-25. Not reviewed line by line by a
human, and never compiled or run on macOS despite the darwin build tag above.
See README.md.

Maps a whole file into memory, read only.

A pak never changes once it is built, so the operating system can hand the same
physical pages to every reader and drop them under memory pressure without
anything having to be written back. Entries stored without compression are then
just windows onto this mapping.

Inputs:
- handle: The open file descriptor, as returned by `os.fd`
- size: The file's size in bytes

Returns:
- data: The whole file as bytes, to be released with `_unmap`
- ok: false when the file could not be mapped
*/
@(private)
_map_read_only :: proc(handle: uintptr, size: i64) -> (data: []byte, ok: bool) {
	if size <= 0 {
		return nil, true
	}

	// MAP_PRIVATE rather than MAP_SHARED: nothing writes through this mapping,
	// and private keeps the pages copy on write should anything ever try.
	view := posix.mmap(nil, uint(size), {.READ}, {.PRIVATE}, posix.FD(handle), 0)
	if view == posix.MAP_FAILED {
		return nil, false
	}
	return (cast([^]byte)view)[:size], true
}

/*
Releases a mapping made by `_map_read_only`.

Inputs:
- data: The mapping to release
*/
@(private)
_unmap :: proc(data: []byte) {
	if len(data) > 0 {
		posix.munmap(raw_data(data), uint(len(data)))
	}
}
