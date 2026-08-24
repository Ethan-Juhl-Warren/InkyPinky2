package pak

import "core:c"
import "core:hash"
import "core:mem"
import "core:strings"
import "../error"

/*
Reads assets out of a pak, which is a plain zip archive. Anything that can write
a zip can build one, and the engine only ever reads them.

Entries are addressed by the path they were stored under, with forward slashes.
Backslashes are accepted and converted, and lookups are case insensitive, so
`"models/box.obj"` and `"Models\Box.obj"` find the same entry.

Example:
	archive: pak.Pak
	if error.print(pak.open(&archive, "assets.pak")) {
		return
	}
	defer pak.close(&archive)

	data, code := pak.read(&archive, "models/box.obj")
	if error.print(code) {
		return
	}
	defer delete(data)
*/
Pak :: struct {
	// miniz stores a pointer to this field inside itself, so a Pak must not be
	// moved or copied once open. Pass it around by pointer.
	archive: Zip_Archive,
	is_open: bool,
}

/*
Whether `read` checks each entry against the CRC-32 stored for it.

miniz's own check is compiled out (see the Makefile), because on a pak stored
without compression it costs about ten times as much as the read it is
verifying. This one uses `core:hash`, which is table-per-byte-slice rather than
byte at a time, and lands close to a fifth of that.

Set to false to drop the check entirely, for a shipping build reading paks it
trusts.
*/
verify_crc := true

/*
One file inside a pak.

`index` is the entry's position in the archive's central directory and is what
`read_index` takes. It is stable for as long as the pak is open.
*/
Entry :: struct {
	name: string,
	index: int,
	size: u64,
	compressed_size: u64,
	crc32: u32,
	is_directory: bool,
}

/*
Opens a pak and reads its central directory.

The pak stays open, and its file handle held, until `close`. Nothing is
decompressed here, only the table of contents is read.

Inputs:
- p: Storage for the open pak, which must outlive every read from it
- path: Path to the archive on disk

Returns:
- `.NONE`, or why the archive could not be opened
*/
open :: proc(p: ^Pak, path: string) -> error.Code {
	assert(p != nil, "open: cannot open into a null pak")
	assert(!p.is_open, "open: pak is already open, close it before reopening")

	mz_zip_zero_struct(&p.archive)
	if !mz_zip_reader_init_file(&p.archive, strings.clone_to_cstring(path, context.temp_allocator), 0) {
		return _translate_error(mz_zip_get_last_error(&p.archive))
	}
	p.is_open = true
	return .NONE
}

/*
Closes a pak, releasing its central directory and file handle. Bytes handed out
by `read` are the caller's and are not touched.

Closing an already closed pak does nothing, so this is safe to `defer` next to
an `open` that may have failed.

Inputs:
- p: The pak to close
*/
close :: proc(p: ^Pak) {
	assert(p != nil, "close: cannot close a null pak")
	if !p.is_open {
		return
	}
	mz_zip_reader_end(&p.archive)
	p.is_open = false
}

/*
Counts the entries in a pak, directory records included.

Inputs:
- p: The pak to count

Returns:
- The number of entries, which is also the exclusive upper bound on the indices
  `read_index` accepts
*/
count :: proc(p: ^Pak) -> int {
	assert(p != nil && p.is_open, "count: pak is not open, call open first")
	return int(mz_zip_reader_get_num_files(&p.archive))
}

/*
Reports whether a pak holds an entry.

Inputs:
- p: The pak to search
- name: The stored path to look for

Returns:
- true when `name` is present
*/
contains :: proc(p: ^Pak, name: string) -> bool {
	assert(p != nil && p.is_open, "contains: pak is not open, call open first")
	_, found := _locate(p, name)
	return found
}

/*
Looks an entry up without decompressing it, for checking a size or a CRC before
committing to the read.

*Allocates Using Temp Allocator*

Inputs:
- p: The pak to search
- name: The stored path to look for
- allocator: Where `Entry.name` is cloned to, temp by default

Returns:
- entry: The entry's central directory record
- code: `.NONE`, or `.PAK_ENTRY_NOT_FOUND` when `name` is not in the pak
*/
stat :: proc(p: ^Pak, name: string, allocator := context.temp_allocator) -> (entry: Entry, code: error.Code) {
	assert(p != nil && p.is_open, "stat: pak is not open, call open first")

	index, found := _locate(p, name)
	if !found {
		return {}, .PAK_ENTRY_NOT_FOUND
	}
	return stat_index(p, int(index), allocator)
}

/*
Looks an entry up by index, for walking a pak alongside `count`.

*Allocates Using Temp Allocator*

Inputs:
- p: The pak to read from
- index: The entry's position in the central directory
- allocator: Where `Entry.name` is cloned to, temp by default

Returns:
- entry: The entry's central directory record
- code: `.NONE`, or why the record could not be read
*/
stat_index :: proc(p: ^Pak, index: int, allocator := context.temp_allocator) -> (entry: Entry, code: error.Code) {
	assert(p != nil && p.is_open, "stat_index: pak is not open, call open first")
	if index < 0 || index >= count(p) {
		return {}, .PAK_ENTRY_NOT_FOUND
	}

	record: Zip_Archive_File_Stat
	if !mz_zip_reader_file_stat(&p.archive, c.uint(index), &record) {
		return {}, _translate_error(mz_zip_get_last_error(&p.archive))
	}
	return _to_entry(&record, allocator), .NONE
}

/*
Lists everything in a pak, for mounting it or for dumping its contents.

*Allocates Using Temp Allocator*

Inputs:
- p: The pak to list
- allocator: Where the slice and the entry names are cloned to, temp by default

Returns:
- list: One `Entry` per record, in central directory order, so `list[i].index == i`
- code: `.NONE`, or why the central directory could not be walked
*/
entries :: proc(p: ^Pak, allocator := context.temp_allocator) -> (list: []Entry, code: error.Code) {
	assert(p != nil && p.is_open, "entries: pak is not open, call open first")

	total := count(p)
	list = make([]Entry, total, allocator)

	record: Zip_Archive_File_Stat
	for i in 0 ..< total {
		if !mz_zip_reader_file_stat(&p.archive, c.uint(i), &record) {
			code = _translate_error(mz_zip_get_last_error(&p.archive))
			delete(list, allocator)
			return nil, code
		}
		list[i] = _to_entry(&record, allocator)
	}
	return list, .NONE
}

/*
Decompresses an entry into a fresh buffer owned by the caller.

Unless `verify_crc` has been turned off, the bytes are checked against the
CRC-32 stored for them, so a `.NONE` return means the entry is intact.

*Allocates Using Provided Allocator*

Inputs:
- p: The pak to read from
- name: The stored path to read
- allocator: Where the returned bytes come from

Returns:
- data: The entry's contents, to be freed with `delete`, or nil on failure
- code: `.NONE`, or why the entry could not be read

Example:
	data, code := pak.read(&archive, "models/box.obj")
	if error.printf(code, "loading %q from the pak", "models/box.obj") {
		return
	}
	defer delete(data)
*/
read :: proc(p: ^Pak, name: string, allocator := context.allocator) -> (data: []byte, code: error.Code) {
	assert(p != nil && p.is_open, "read: pak is not open, call open first")

	index, found := _locate(p, name)
	if !found {
		return nil, .PAK_ENTRY_NOT_FOUND
	}
	return read_index(p, int(index), allocator)
}

/*
Decompresses an entry by index, for reading back something `entries` turned up.

*Allocates Using Provided Allocator*

Inputs:
- p: The pak to read from
- index: The entry's position in the central directory
- allocator: Where the returned bytes come from

Returns:
- data: The entry's contents, to be freed with `delete`, or nil on failure
- code: `.NONE`, or why the entry could not be read. Directory records report
  `.PAK_ENTRY_NOT_FOUND` rather than handing back an empty buffer
*/
read_index :: proc(p: ^Pak, index: int, allocator := context.allocator) -> (data: []byte, code: error.Code) {
	assert(p != nil && p.is_open, "read_index: pak is not open, call open first")
	if index < 0 || index >= count(p) {
		return nil, .PAK_ENTRY_NOT_FOUND
	}

	record: Zip_Archive_File_Stat
	if !mz_zip_reader_file_stat(&p.archive, c.uint(index), &record) {
		return nil, _translate_error(mz_zip_get_last_error(&p.archive))
	}
	if bool(record.is_directory) {
		return nil, .PAK_ENTRY_NOT_FOUND
	}
	if !bool(record.is_supported) {
		return nil, .PAK_UNSUPPORTED_FEATURE
	}

	data = make([]byte, int(record.uncomp_size), allocator)
	if !mz_zip_reader_extract_to_mem(&p.archive, c.uint(index), raw_data(data), c.size_t(len(data)), 0) {
		code = _translate_error(mz_zip_get_last_error(&p.archive))
		delete(data, allocator)
		return nil, code
	}
	if verify_crc && hash.crc32(data) != record.crc32 {
		delete(data, allocator)
		return nil, .PAK_CORRUPT
	}
	return data, .NONE
}

/*
Reports what miniz itself said about the last failure, which is finer grained
than the `error.Code` it was folded into. Worth putting in the "what:" line of
an `error.printf` when a pak read goes wrong.

Inputs:
- p: The pak that failed

Returns:
- miniz's description of the failure, a static string that needs no freeing

Example:
	data, code := pak.read(&archive, name)
	if error.printf(code, "%s: %s", name, pak.last_error_string(&archive)) {
		return
	}
*/
last_error_string :: proc(p: ^Pak) -> string {
	assert(p != nil, "last_error_string: cannot query a null pak")
	return string(mz_zip_get_error_string(mz_zip_get_last_error(&p.archive)))
}

/*
Finds an entry by path, whichever separator the caller and the archive happen to
use.

Inputs:
- p: The pak to search
- name: The path to look for

Returns:
- index: The entry's position in the central directory, when found
- found: Whether `name` is in the pak
*/
@(private)
_locate :: proc(p: ^Pak, name: string) -> (index: u32, found: bool) {
	if bool(mz_zip_reader_locate_file_v2(&p.archive, _archive_path(name, "/"), nil, 0, &index)) {
		return index, true
	}

	// The format calls for '/', but some Windows tools write nested paths with
	// backslashes anyway, PowerShell's Compress-Archive among them. Only worth a
	// second lookup for paths that actually have a separator in them.
	if strings.index_byte(name, '/') >= 0 || strings.index_byte(name, '\\') >= 0 {
		if bool(mz_zip_reader_locate_file_v2(&p.archive, _archive_path(name, "\\"), nil, 0, &index)) {
			return index, true
		}
	}
	return 0, false
}

/*
Turns a lookup path into the form the archive stores, so callers can use whatever
separator is convenient.

*Allocates Using Temp Allocator*

Inputs:
- name: The path to convert
- separator: The separator to put the path into, "/" as the format intends

Returns:
- `name` written with `separator` and NUL terminated
*/
@(private)
_archive_path :: proc(name: string, separator := "/") -> cstring {
	other := "\\" if separator == "/" else "/"
	swapped, _ := strings.replace_all(name, other, separator, context.temp_allocator)
	return strings.clone_to_cstring(swapped, context.temp_allocator)
}

/*
Copies a central directory record into the engine's own `Entry`.

*Allocates Using Provided Allocator*

Inputs:
- record: The record to copy from
- allocator: Where the name is cloned to

Returns:
- The record as an `Entry`, owning its name
*/
@(private)
_to_entry :: proc(record: ^Zip_Archive_File_Stat, allocator: mem.Allocator) -> Entry {
	return Entry {
		name = strings.clone_from_cstring(cstring(raw_data(record.filename[:])), allocator),
		index = int(record.file_index),
		size = record.uncomp_size,
		compressed_size = record.comp_size,
		crc32 = record.crc32,
		is_directory = bool(record.is_directory),
	}
}

/*
Folds miniz's error list down onto the engine's.

miniz distinguishes far more failures than the engine cares to act on, so
several map onto one code. `last_error_string` still has the exact reason when
it matters.

Inputs:
- err: The code miniz reported

Returns:
- The matching engine code
*/
@(private)
_translate_error :: proc(err: Zip_Error) -> error.Code {
	#partial switch err {
	case .NO_ERROR:
		return .NONE

	case .FILE_OPEN_FAILED, .FILE_STAT_FAILED, .FILE_SEEK_FAILED:
		return .PAK_OPEN_FAILED

	case .FILE_READ_FAILED, .FILE_CLOSE_FAILED, .ALLOC_FAILED:
		return .PAK_READ_FAILED

	case .NOT_AN_ARCHIVE, .FAILED_FINDING_CENTRAL_DIR:
		return .PAK_NOT_AN_ARCHIVE

	case .FILE_NOT_FOUND:
		return .PAK_ENTRY_NOT_FOUND

	case .UNSUPPORTED_METHOD, .UNSUPPORTED_ENCRYPTION, .UNSUPPORTED_FEATURE,
	     .UNSUPPORTED_MULTIDISK, .UNSUPPORTED_CDIR_SIZE:
		return .PAK_UNSUPPORTED_FEATURE
	}

	// Everything left is the archive not being what its central directory claims:
	// corrupt headers, a failed inflate, a CRC mismatch, a short read.
	return .PAK_CORRUPT
}
