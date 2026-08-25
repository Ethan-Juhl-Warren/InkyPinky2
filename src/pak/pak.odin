package pak

/*
WRITTEN BY CLAUDE OPUS 5 (Anthropic), 2026-08-25. Not reviewed line by line by a
human. See README.md in this directory for why each decision was made, what was
actually measured, what is unverified, and a suggested order for auditing it.

Read only access to a pak, which is a zip archive used as a directory that
happens to live in one file. Mount it, read paths out of it, unmount it. The pak
handle stands in for the directory those paths are relative to, the way a file
path is relative to the folder it sits in.

This package knows nothing about loose files. Choosing between an asset on disk
and an asset in a pak belongs to the caller, and is usually one `when` in one
procedure:

	read_file :: proc(path: string) -> (data: []byte, ok: bool) {
		when RELEASE_MODE {
			bytes, code := pak.read(assets, path)
			return bytes, code == .NONE
		} else {
			bytes, err := os.read_entire_file_from_path(path, context.allocator)
			return bytes, err == nil
		}
	}

A pak is immutable once built, so the whole file is mapped into memory and never
copied out of again unless the caller asks for its own copy. Entries stored
without compression, which is how the export tooling writes them, are then just
windows onto that mapping and cost nothing to hand out.

Nothing here assumes anything about how a pak is laid out beyond it being a
valid archive. Compressed entries, nested paths, and archives from other tools
all work, they just cannot be viewed in place.

Example:
	error.must(pak.init())
	defer pak.destroy()

	archive, code := pak.mount("game.pak")
	if error.print(code) {
		return
	}
	defer pak.unmount(archive)

	// a copy the caller owns
	config, _ := pak.read_string(archive, "config/game.cfg")
	defer delete(config)

	// or a window onto the mapping, valid until unmount, nothing allocated
	pixels, _ := pak.view(archive, "assets/pig.png")
*/

import "core:c"
import "core:hash"
import "core:mem"
import "core:os"
import "core:strings"
import "../error"

/*
An open pak.

This is a handle rather than the archive itself, so it can be copied, stored in
whatever container suits, and compared, without any of the ways a struct holding
a memory mapping could be broken by being moved. `unmount` invalidates every copy
of it at once, and using a stale one is reported rather than followed.
*/
Pak :: distinct u32

// The handle no pak ever has. The zero value, so a `Pak` field starts invalid.
INVALID :: Pak(0)

/*
Whether `read` and `view` check entries against the CRC-32 stored for them.

miniz's own check is compiled out (see the Makefile) because on a pak stored
without compression it costs about ten times the read it is verifying. This one
uses `core:hash`, which is roughly a fifth of that again.

Verifying a `view` once at load and then using the slice for the lifetime of the
pak is the cheap way to keep the guarantee, since the bytes cannot change under
you afterwards.
*/
verify_crc := true

/*
One entry in a pak.

`name` is only filled in by the calls that had to read it anyway, `entries` and
`stat_index`. The calls that already took a name as an argument leave it empty
rather than allocate a copy of something the caller has.
*/
Entry :: struct {
	name: string,
	index: int,
	size: u64,
	compressed_size: u64,
	crc32: u32,
	// Stored rather than compressed. Necessary for `view` but not sufficient on
	// its own, since an encrypted entry keeps the compression method it had
	// before it was encrypted.
	stored: bool,
	// Encrypted, which this package cannot unpack. `read` and `view` both report
	// `.PAK_UNSUPPORTED_FEATURE` for it.
	encrypted: bool,
	is_directory: bool,
}

/*
An open archive and the mapping it reads from.

Heap allocated and only ever reached through `archives`, because miniz keeps a
pointer to this struct inside itself and the pool moves when it grows.
*/
@(private)
Archive :: struct {
	zip: Zip_Archive,
	mapping: []byte,
	path: string,
	// One bit per entry, set once that entry has passed its CRC check. The
	// mapping cannot change underneath us, so an entry that verified once stays
	// verified, and viewing it again is free.
	verified: []u64,
	slot: int,
	generation: u32,
	case_sensitive: bool,
	used: bool,
}

@(private)
archives: [dynamic]^Archive

/*
Where the package's own bookkeeping is allocated from.

Pinned once by `init` and used explicitly everywhere internal state is allocated
or freed. Nothing in this package reads `context.allocator` for its own use, on
purpose: a pak is usually mounted and unmounted at different points in a program, and
if those two moments saw different context allocators the pool and the paths
inside it would be freed through the wrong one.
*/
@(private)
allocator: mem.Allocator

@(private)
initialized: bool

// A handle packs the pool slot into the low bits and a generation into the rest,
// so a slot that gets reused does not answer to handles from its previous life.
@(private) _SLOT_BITS :: 16
@(private) _SLOT_MASK :: u32(1 << _SLOT_BITS) - 1

/*
Prepares the package, pinning the allocator its handle pool and per pak
bookkeeping will use for as long as it is up.

Required before `mount`. It is not optional and does not happen lazily, because
an allocator captured by whichever call happened to open the first pak is not
something a caller can see or control.

This does not affect where `read` puts the bytes it hands back. Those still come
from the allocator passed to the call, defaulting to `context.allocator`.

Inputs:
- allocator: Where the pool and each open pak's bookkeeping is allocated from

Returns:
- `.NONE`, or `.MANAGER_ALREADY_INITIALIZED` if the package is already up
*/
init :: proc(alloc := context.allocator) -> error.Code {
	if initialized {
		return .MANAGER_ALREADY_INITIALIZED
	}
	allocator = alloc
	archives = make([dynamic]^Archive, allocator)
	initialized = true
	return .NONE
}

/*
Unmounts every pak still mounted and releases the handle pool.

Call this on shutdown. Handles do not survive it, and `mount` cannot be called
again until `init` has been.

Returns:
- `.NONE`, or `.DESTROYING_UNINITIALIZED_MANAGER` if the package was never up
*/
destroy :: proc() -> error.Code {
	if !initialized {
		return .DESTROYING_UNINITIALIZED_MANAGER
	}

	for archive in archives {
		if archive.used {
			mz_zip_reader_end(&archive.zip)
			_release(archive)
		}
		free(archive, allocator)
	}
	delete(archives)

	archives = nil
	allocator = {}
	initialized = false
	return .NONE
}

/*
Mounts a pak by mapping it and reading its central directory.

Nothing is decompressed and nothing is copied. The file itself is closed before
this returns, since the mapping keeps the pages alive on its own.

Inputs:
- path: The archive on disk
- case_sensitive: Whether entry names are matched exactly. On by default, so a
  name that is wrong only in its case fails here rather than on the first
  case sensitive filesystem the game is shipped to

Returns:
- p: A handle to the mounted pak, or `INVALID` on failure
- code: `.NONE`, or why the archive could not be opened
*/
mount :: proc(path: string, case_sensitive := true) -> (p: Pak, code: error.Code) {
	assert(initialized, "mount: pak package not initialized, call pak.init first")

	file, open_err := os.open(path, {.Read})
	if open_err != nil {
		return INVALID, .PAK_OPEN_FAILED
	}

	size, size_err := os.file_size(file)
	if size_err != nil {
		os.close(file)
		return INVALID, .PAK_OPEN_FAILED
	}

	mapping, mapped := _map_read_only(os.fd(file), size)
	os.close(file)
	if !mapped {
		return INVALID, .PAK_OPEN_FAILED
	}

	archive := _acquire()
	archive.mapping = mapping
	archive.path = strings.clone(path, allocator)
	archive.case_sensitive = case_sensitive

	mz_zip_zero_struct(&archive.zip)
	if !mz_zip_reader_init_mem(&archive.zip, raw_data(mapping), c.size_t(len(mapping)), 0) {
		code = _translate_error(mz_zip_get_last_error(&archive.zip))
		_release(archive)
		return INVALID, code
	}

	total := int(mz_zip_reader_get_num_files(&archive.zip))
	archive.verified = make([]u64, (total + 63) / 64, allocator)
	return _handle(archive), .NONE
}

/*
Unmounts a pak and releases its mapping.

Every handle to it becomes stale at once. Anything `view` handed out points into
the mapping and must not be touched afterwards. Unmounting an already unmounted pak
does nothing, so this is safe to `defer` after a `mount` that may have failed.

Inputs:
- p: The pak to close
*/
unmount :: proc(p: Pak) {
	archive := _archive(p)
	if archive == nil {
		return
	}
	mz_zip_reader_end(&archive.zip)
	_release(archive)
}

/*
Reports whether a handle still refers to a mounted pak.

Inputs:
- p: The handle to check

Returns:
- true when `p` is mounted
*/
is_open :: proc(p: Pak) -> bool {
	return _archive(p) != nil
}

/*
Reports the path a pak was mounted from, for diagnostics.

Inputs:
- p: The pak to ask about

Returns:
- The path given to `mount`, valid until the pak is unmounted, or "" for a
  stale handle
*/
path_of :: proc(p: Pak) -> string {
	archive := _archive(p)
	return archive.path if archive != nil else ""
}

/*
Counts the entries in a pak, directory records included.

Inputs:
- p: The pak to count

Returns:
- The number of entries, which bounds the indices `read_index` accepts
*/
count :: proc(p: Pak) -> int {
	archive := _archive(p)
	if archive == nil {
		return 0
	}
	return int(mz_zip_reader_get_num_files(&archive.zip))
}

/*
Reports whether a pak holds an entry.

Inputs:
- p: The pak to search
- name: The path inside the pak

Returns:
- true when `name` is present
*/
contains :: proc(p: Pak, name: string) -> bool {
	archive := _archive(p)
	if archive == nil {
		return false
	}
	_, found := _locate(archive, name)
	return found
}

/*
Reports how large an entry is once unpacked, without allocating anything.

Inputs:
- p: The pak to search
- name: The path inside the pak

Returns:
- size: The entry's size in bytes
- code: `.NONE`, or why it could not be looked up
*/
size_of_entry :: proc(p: Pak, name: string) -> (size: u64, code: error.Code) {
	record := _record(p, name) or_return
	return record.uncomp_size, .NONE
}

/*
Looks an entry up without unpacking it.

Inputs:
- p: The pak to search
- name: The path inside the pak

Returns:
- entry: The entry's record, with `name` left empty since the caller supplied it
- code: `.NONE`, or why it could not be looked up
*/
stat :: proc(p: Pak, name: string) -> (entry: Entry, code: error.Code) {
	record := _record(p, name) or_return
	return _to_entry(&record, "", nil), .NONE
}

/*
Looks an entry up by index, for walking a pak alongside `count`.

*Allocates Using Temp Allocator*

Inputs:
- p: The pak to read from
- index: The entry's position in the central directory
- allocator: Where `Entry.name` is cloned to, temp by default

Returns:
- entry: The entry's record
- code: `.NONE`, or why it could not be read
*/
stat_index :: proc(p: Pak, index: int, allocator := context.temp_allocator) -> (entry: Entry, code: error.Code) {
	archive := _archive(p)
	if archive == nil {
		return {}, .PAK_INVALID_HANDLE
	}
	if index < 0 || index >= int(mz_zip_reader_get_num_files(&archive.zip)) {
		return {}, .PAK_ENTRY_NOT_FOUND
	}

	record: Zip_Archive_File_Stat
	if !mz_zip_reader_file_stat(&archive.zip, c.uint(index), &record) {
		return {}, _translate_error(mz_zip_get_last_error(&archive.zip))
	}
	return _to_entry(&record, "", allocator), .NONE
}

/*
Lists everything in a pak, for mounting it or dumping its contents.

*Allocates Using Temp Allocator*

Inputs:
- p: The pak to list
- allocator: Where the slice and the entry names are cloned to, temp by default

Returns:
- list: One `Entry` per record, in central directory order
- code: `.NONE`, or why the directory could not be walked
*/
entries :: proc(p: Pak, allocator := context.temp_allocator) -> (list: []Entry, code: error.Code) {
	archive := _archive(p)
	if archive == nil {
		return nil, .PAK_INVALID_HANDLE
	}

	total := int(mz_zip_reader_get_num_files(&archive.zip))
	list = make([]Entry, total, allocator)

	record: Zip_Archive_File_Stat
	for i in 0 ..< total {
		if !mz_zip_reader_file_stat(&archive.zip, c.uint(i), &record) {
			code = _translate_error(mz_zip_get_last_error(&archive.zip))
			delete(list, allocator)
			return nil, code
		}
		list[i] = _to_entry(&record, "", allocator)
	}
	return list, .NONE
}

/*
Hands back an entry's bytes where they already sit in the mapping, without
copying or allocating anything.

This only works for entries stored without compression, which is how the export
tooling writes them. A compressed entry has no contiguous plain bytes to point
at, so this reports `.PAK_ENTRY_COMPRESSED` and the caller should use `read`.

The returned slice belongs to the pak and stays valid until it is closed. It
must not be written to or freed.

Inputs:
- p: The pak to read from
- name: The path inside the pak

Returns:
- data: A window onto the mapping, valid until the pak is unmounted
- code: `.NONE`, or why the entry could not be viewed

Example:
	pixels, code := pak.view(archive, "assets/pig.png")
	if code == .PAK_ENTRY_COMPRESSED {
		// fall back to a copy for archives packed by something else
		pixels, code = pak.read(archive, "assets/pig.png")
	}
*/
view :: proc(p: Pak, name: string) -> (data: []byte, code: error.Code) {
	archive := _archive(p)
	if archive == nil {
		return nil, .PAK_INVALID_HANDLE
	}

	index, found := _locate(archive, name)
	if !found {
		return nil, .PAK_ENTRY_NOT_FOUND
	}
	return view_index(p, int(index))
}

/*
Hands back an entry's bytes in place by index, for viewing what `entries` turned
up. See `view`.

Inputs:
- p: The pak to read from
- index: The entry's position in the central directory

Returns:
- data: A window onto the mapping, valid until the pak is unmounted
- code: `.NONE`, or why the entry could not be viewed
*/
view_index :: proc(p: Pak, index: int) -> (data: []byte, code: error.Code) {
	archive := _archive(p)
	if archive == nil {
		return nil, .PAK_INVALID_HANDLE
	}

	record: Zip_Archive_File_Stat
	if index < 0 || index >= int(mz_zip_reader_get_num_files(&archive.zip)) {
		return nil, .PAK_ENTRY_NOT_FOUND
	}
	if !mz_zip_reader_file_stat(&archive.zip, c.uint(index), &record) {
		return nil, _translate_error(mz_zip_get_last_error(&archive.zip))
	}
	if bool(record.is_directory) {
		return nil, .PAK_ENTRY_NOT_FOUND
	}

	// Before the compression check, not after. An entry encrypted with ZipCrypto
	// still reports its original compression method, so a stored one looks
	// perfectly viewable and would otherwise hand the caller raw ciphertext
	// dressed up as the asset. AES entries are caught here too, and report being
	// unsupported rather than merely compressed.
	if bool(record.is_encrypted) || !bool(record.is_supported) {
		return nil, .PAK_UNSUPPORTED_FEATURE
	}
	if record.method != 0 {
		return nil, .PAK_ENTRY_COMPRESSED
	}

	start := _data_offset(archive, &record) or_return
	end := start + record.uncomp_size
	if end > u64(len(archive.mapping)) {
		return nil, .PAK_CORRUPT
	}

	data = archive.mapping[start:end]
	if !_verify(archive, index, data, record.crc32) {
		return nil, .PAK_CORRUPT
	}
	return data, .NONE
}

/*
Unpacks an entry into a buffer the caller owns.

Works whatever the entry's compression, so this is the call that does not care
how a pak was built. For a stored entry it is a copy out of the mapping, for a
compressed one it inflates.

*Allocates Using Provided Allocator*

Inputs:
- p: The pak to read from
- name: The path inside the pak
- allocator: Where the returned bytes come from

Returns:
- data: The entry's contents, to be freed with `delete`, or nil on failure
- code: `.NONE`, or why the entry could not be read
*/
read :: proc(p: Pak, name: string, allocator := context.allocator) -> (data: []byte, code: error.Code) {
	archive := _archive(p)
	if archive == nil {
		return nil, .PAK_INVALID_HANDLE
	}

	index, found := _locate(archive, name)
	if !found {
		return nil, .PAK_ENTRY_NOT_FOUND
	}
	return read_index(p, int(index), allocator)
}

/*
Unpacks an entry by index, for reading what `entries` turned up.

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
read_index :: proc(p: Pak, index: int, allocator := context.allocator) -> (data: []byte, code: error.Code) {
	archive := _archive(p)
	if archive == nil {
		return nil, .PAK_INVALID_HANDLE
	}
	if index < 0 || index >= int(mz_zip_reader_get_num_files(&archive.zip)) {
		return nil, .PAK_ENTRY_NOT_FOUND
	}

	record: Zip_Archive_File_Stat
	if !mz_zip_reader_file_stat(&archive.zip, c.uint(index), &record) {
		return nil, _translate_error(mz_zip_get_last_error(&archive.zip))
	}
	if bool(record.is_directory) {
		return nil, .PAK_ENTRY_NOT_FOUND
	}
	if bool(record.is_encrypted) || !bool(record.is_supported) {
		return nil, .PAK_UNSUPPORTED_FEATURE
	}

	data = make([]byte, int(record.uncomp_size), allocator)
	if !mz_zip_reader_extract_to_mem(&archive.zip, c.uint(index), raw_data(data), c.size_t(len(data)), 0) {
		code = _translate_error(mz_zip_get_last_error(&archive.zip))
		delete(data, allocator)
		return nil, code
	}
	if !_verify(archive, index, data, record.crc32) {
		delete(data, allocator)
		return nil, .PAK_CORRUPT
	}
	return data, .NONE
}

/*
Unpacks a text entry into a string the caller owns.

*Allocates Using Provided Allocator*

Inputs:
- p: The pak to read from
- name: The path inside the pak
- allocator: Where the returned string comes from

Returns:
- text: The entry's contents, to be freed with `delete`, or "" on failure
- code: `.NONE`, or why the entry could not be read
*/
read_string :: proc(p: Pak, name: string, allocator := context.allocator) -> (text: string, code: error.Code) {
	data := read(p, name, allocator) or_return
	return string(data), .NONE
}

/*
Hands back a text entry in place, without copying. See `view` for how long the
result stays valid.

Inputs:
- p: The pak to read from
- name: The path inside the pak

Returns:
- text: A window onto the mapping, valid until the pak is unmounted
- code: `.NONE`, or why the entry could not be viewed
*/
view_string :: proc(p: Pak, name: string) -> (text: string, code: error.Code) {
	data := view(p, name) or_return
	return string(data), .NONE
}

/*
Returns the pool entry a handle refers to, or nil when the handle is stale.

Inputs:
- p: The handle to resolve

Returns:
- The archive, or nil
*/
@(private)
_archive :: proc(p: Pak) -> ^Archive {
	raw := u32(p)
	slot := raw & _SLOT_MASK
	if slot == 0 || int(slot) > len(archives) {
		return nil
	}

	archive := archives[slot - 1]
	if !archive.used || archive.generation != raw >> _SLOT_BITS {
		return nil
	}
	return archive
}

/*
Builds the handle for a pool entry.

Inputs:
- archive: The pool entry

Returns:
- Its handle
*/
@(private)
_handle :: proc(archive: ^Archive) -> Pak {
	return Pak(archive.generation << _SLOT_BITS | u32(archive.slot + 1))
}

/*
Takes a free pool slot, reusing a closed one when there is one.

Returns:
- A slot ready to be filled in, with its generation already moved on so handles
  from its previous life no longer resolve
*/
@(private)
_acquire :: proc() -> ^Archive {
	for archive in archives {
		if !archive.used {
			archive.used = true
			archive.generation += 1
			return archive
		}
	}

	archive := new(Archive, allocator)
	archive.slot = len(archives)
	archive.generation = 1
	archive.used = true
	append(&archives, archive)
	return archive
}

/*
Returns a slot to the pool, releasing the mapping it held.

Inputs:
- archive: The slot to release
*/
@(private)
_release :: proc(archive: ^Archive) {
	_unmap(archive.mapping)
	delete(archive.path, allocator)
	delete(archive.verified, allocator)
	archive.mapping = nil
	archive.path = ""
	archive.verified = nil
	archive.used = false
}

/*
Checks an entry against its stored CRC-32, at most once per entry per open pak.

The bytes behind a pak cannot change while it is mapped, so once an entry has
been verified there is nothing to gain by checking it again. That is what makes
viewing the same asset repeatedly free rather than linear in its size.

Inputs:
- archive: The archive the entry belongs to
- index: The entry's position in the central directory
- data: The entry's unpacked bytes
- crc: The CRC-32 the archive records for it

Returns:
- true when the entry is intact, or when checking is turned off
*/
@(private)
_verify :: proc(archive: ^Archive, index: int, data: []byte, crc: u32) -> bool {
	if !verify_crc {
		return true
	}

	word, bit := index / 64, u64(1) << u32(index % 64)
	if word < len(archive.verified) && archive.verified[word] & bit != 0 {
		return true
	}
	if hash.crc32(data) != crc {
		return false
	}
	if word < len(archive.verified) {
		archive.verified[word] |= bit
	}
	return true
}


/*
Looks up an entry's central directory record by name.

Inputs:
- p: The pak to search
- name: The path inside the pak

Returns:
- record: The entry's record
- code: `.NONE`, or why it could not be looked up
*/
@(private)
_record :: proc(p: Pak, name: string) -> (record: Zip_Archive_File_Stat, code: error.Code) {
	archive := _archive(p)
	if archive == nil {
		return {}, .PAK_INVALID_HANDLE
	}

	index, found := _locate(archive, name)
	if !found {
		return {}, .PAK_ENTRY_NOT_FOUND
	}
	if !mz_zip_reader_file_stat(&archive.zip, c.uint(index), &record) {
		return {}, _translate_error(mz_zip_get_last_error(&archive.zip))
	}
	return record, .NONE
}

/*
Finds where an entry's bytes start in the mapping.

The central directory only records where the local header is, and that header
carries its own name and extra field whose lengths differ from the ones in the
directory, so the payload offset can only be worked out from the header itself.

Inputs:
- archive: The archive to look in
- record: The entry's central directory record

Returns:
- offset: The byte offset of the entry's data within the mapping
- code: `.NONE`, or `.PAK_CORRUPT` when the header is not where it should be
*/
@(private)
_data_offset :: proc(archive: ^Archive, record: ^Zip_Archive_File_Stat) -> (offset: u64, code: error.Code) {
	header := record.local_header_ofs
	if header + _LOCAL_HEADER_SIZE > u64(len(archive.mapping)) {
		return 0, .PAK_CORRUPT
	}

	local := archive.mapping[header:]
	if _u32(local, 0) != _SIG_LOCAL_FILE_HEADER {
		return 0, .PAK_CORRUPT
	}

	name_len := u64(_u16(local, 26))
	extra_len := u64(_u16(local, 28))
	return header + _LOCAL_HEADER_SIZE + name_len + extra_len, .NONE
}

@(private) _SIG_LOCAL_FILE_HEADER :: u32(0x04034b50)
@(private) _LOCAL_HEADER_SIZE :: u64(30)

@(private)
_u16 :: proc(b: []byte, offset: int) -> u16 {
	return u16(b[offset]) | u16(b[offset + 1]) << 8
}

@(private)
_u32 :: proc(b: []byte, offset: int) -> u32 {
	return u32(b[offset]) | u32(b[offset + 1]) << 8 | u32(b[offset + 2]) << 16 | u32(b[offset + 3]) << 24
}

/*
Finds an entry by name, honouring the archive's case sensitivity.

*Allocates Using Temp Allocator*

Inputs:
- archive: The archive to search
- name: The path inside the pak

Returns:
- index: The entry's position in the central directory
- found: Whether the archive holds it
*/
@(private)
_locate :: proc(archive: ^Archive, name: string) -> (index: u32, found: bool) {
	flags := MZ_ZIP_FLAG_CASE_SENSITIVE if archive.case_sensitive else c.uint(0)
	key := strings.clone_to_cstring(name, context.temp_allocator)

	// Written out rather than returned inline, so `index` is not read while the
	// call that fills it in is still an argument being evaluated.
	found = bool(mz_zip_reader_locate_file_v2(&archive.zip, key, nil, flags, &index))
	return index, found
}

/*
Copies a central directory record into the package's own `Entry`.

Inputs:
- record: The record to copy from
- name: The name to give the entry when it is already known
- allocator: Where to clone the record's name to, or nil to leave it empty

Returns:
- The record as an `Entry`
*/
@(private)
_to_entry :: proc(record: ^Zip_Archive_File_Stat, name: string, allocator: Maybe(mem.Allocator)) -> Entry {
	entry := Entry {
		name = name,
		index = int(record.file_index),
		size = record.uncomp_size,
		compressed_size = record.comp_size,
		crc32 = record.crc32,
		stored = record.method == 0,
		encrypted = bool(record.is_encrypted),
		is_directory = bool(record.is_directory),
	}
	if allocator != nil {
		entry.name = strings.clone_from_cstring(cstring(raw_data(record.filename[:])), allocator.?)
	}
	return entry
}

/*
Folds miniz's error list down onto the engine's.

miniz distinguishes far more failures than the engine acts on, so several map
onto one code.

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

	// Everything left is the archive not being what its central directory
	// claims: corrupt headers, a failed inflate, a CRC mismatch, a short read.
	return .PAK_CORRUPT
}
