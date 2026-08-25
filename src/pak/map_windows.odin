#+build windows
package pak

import win32 "core:sys/windows"

/*
WRITTEN BY CLAUDE OPUS 5 (Anthropic), 2026-08-25. Not reviewed line by line by a
human. See README.md.

Maps a whole file into memory, read only.

A pak never changes once it is built, so the operating system can hand the same
physical pages to every reader and drop them under memory pressure without
anything having to be written back. Entries stored without compression are then
just windows onto this mapping.

Inputs:
- handle: The open file, as returned by `os.fd`
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

	mapping := win32.CreateFileMappingW(win32.HANDLE(handle), nil, win32.PAGE_READONLY, 0, 0, nil)
	if mapping == nil {
		return nil, false
	}
	// The view holds its own reference to the file, so the mapping object has
	// done its job as soon as the view exists.
	defer win32.CloseHandle(mapping)

	view := win32.MapViewOfFile(mapping, win32.FILE_MAP_READ, 0, 0, 0)
	if view == nil {
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
		win32.UnmapViewOfFile(raw_data(data))
	}
}

/*
Asks the operating system to bring a range of a mapping into memory, without
waiting for it.

This is what makes reading from a pak asynchronous. Nothing in this package
issues a read: touching a page that is not resident faults, and that fault
blocks whichever thread touched it. Prefetching ahead of time means the pages
are already there when the read finally happens, so the fault never occurs.

Advisory. The operating system is free to ignore it, and a failure here is not
worth reporting because the only consequence is a fault later.

Inputs:
- data: The range to bring in, a slice of a mapping
*/
@(private)
_prefetch :: proc(data: []byte) {
	if len(data) == 0 {
		return
	}

	range := win32.WIN32_MEMORY_RANGE_ENTRY {
		VirtualAddress = raw_data(data),
		NumberOfBytes = win32.SIZE_T(len(data)),
	}
	win32.PrefetchVirtualMemory(win32.GetCurrentProcess(), 1, &range, 0)
}
