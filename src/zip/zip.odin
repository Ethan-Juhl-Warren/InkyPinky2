package zip

/*
WRITTEN BY CLAUDE OPUS 5 (Anthropic), 2026-08-25. Not reviewed line by line by a
human. See src/pak/README.md.

Reading a zip archive that is already in memory.

This package knows the zip format and nothing else. It does not open files, map
them, cache anything or decide what an asset is. Hand it bytes and it will tell
you what entries are in them and where. `src/pak` is what maps a file, holds the
handles and builds the indexes, and it is the only caller this expects.

The split is worth keeping: everything here is a pure function of a byte slice,
which makes it the layer that can be reasoned about without a filesystem.

miniz does the actual parsing. Its bindings are private to this package, so
`mz_zip_*` never appears anywhere else in the engine.
*/

import "core:c"
import "../error"

// Longest entry name an archive will report. Names past this are truncated by
// miniz rather than reported, which is a limitation of its stat record.
MAX_NAME :: MAX_FILENAME_SIZE

/*
An open archive.

miniz stores a pointer to this struct inside itself when the archive is opened,
so once open it must not be moved or copied. Callers keep it somewhere stable
and pass it by pointer, which is why `pak` heap allocates one per mounted pak.
*/
Archive :: struct {
	_zip: Zip_Archive,
}

/*
What an archive records about one entry.

`name` is not a field because a string pointing into this struct would dangle
the moment the struct was copied. Call `name_of` on a `File_Info` you are
holding, which slices the copy you already have.
*/
File_Info :: struct {
	index: int,
	size: u64,
	compressed_size: u64,
	crc32: u32,
	// 0 is stored, 8 is deflate. Anything else this package will not unpack.
	method: u16,
	// Encrypted entries keep the compression method they had before encryption,
	// so a stored one looks readable and is not. Always check this first.
	encrypted: bool,
	supported: bool,
	is_directory: bool,
	// Where the entry's local header starts, which is what `data_offset` needs.
	local_header_offset: u64,

	_name: [MAX_FILENAME_SIZE]u8,
}

/*
Reads the central directory of an archive held in memory.

Nothing is decompressed and the bytes are not copied. `data` must stay valid and
unchanged for as long as the archive is open, since everything read afterwards
points into it.

Inputs:
- a: Storage for the open archive, which must not move afterwards
- data: The whole archive

Returns:
- `.NONE`, or why it could not be read
*/
open_from_memory :: proc(a: ^Archive, data: []byte) -> error.Code {
	mz_zip_zero_struct(&a._zip)
	if !mz_zip_reader_init_mem(&a._zip, raw_data(data), c.size_t(len(data)), 0) {
		return translate_error(mz_zip_get_last_error(&a._zip))
	}
	return .NONE
}

/*
Releases what `open_from_memory` allocated. The bytes it was reading are the
caller's and are not touched.

Inputs:
- a: The archive to close
*/
close :: proc(a: ^Archive) {
	mz_zip_reader_end(&a._zip)
}

/*
Counts the entries in an archive, directory records included.

Inputs:
- a: The archive to count

Returns:
- The number of entries
*/
count :: proc(a: ^Archive) -> int {
	return int(mz_zip_reader_get_num_files(&a._zip))
}

/*
Finds an entry by name.

Inputs:
- a: The archive to search
- name: The path inside it, with forward slashes
- case_sensitive: Whether the name must match exactly

Returns:
- index: The entry's position in the central directory
- found: Whether the archive holds it
*/
locate :: proc(a: ^Archive, name: cstring, case_sensitive: bool) -> (index: int, found: bool) {
	flags := MZ_ZIP_FLAG_CASE_SENSITIVE if case_sensitive else c.uint(0)

	raw: u32
	found = bool(mz_zip_reader_locate_file_v2(&a._zip, name, nil, flags, &raw))
	return int(raw), found
}

/*
Reads what the central directory records about one entry.

Inputs:
- a: The archive to read from
- index: The entry's position in the central directory

Returns:
- info: The entry's record
- code: `.NONE`, or why it could not be read
*/
stat :: proc(a: ^Archive, index: int) -> (info: File_Info, code: error.Code) {
	if index < 0 || index >= count(a) {
		return {}, .PAK_ENTRY_NOT_FOUND
	}

	record: Zip_Archive_File_Stat
	if !mz_zip_reader_file_stat(&a._zip, c.uint(index), &record) {
		return {}, translate_error(mz_zip_get_last_error(&a._zip))
	}

	info = File_Info {
		index = int(record.file_index),
		size = record.uncomp_size,
		compressed_size = record.comp_size,
		crc32 = record.crc32,
		method = record.method,
		encrypted = bool(record.is_encrypted),
		supported = bool(record.is_supported),
		is_directory = bool(record.is_directory),
		local_header_offset = record.local_header_ofs,
	}
	copy(info._name[:], record.filename[:])
	return info, .NONE
}

/*
Reads an entry's name out of a record you are holding.

Takes a pointer because the result points into `info`, so it lives exactly as
long as the copy the caller has.

Inputs:
- info: The record to read the name from

Returns:
- The entry's path inside the archive
*/
name_of :: proc(info: ^File_Info) -> string {
	return string(cstring(raw_data(info._name[:])))
}

/*
Unpacks an entry into a buffer, whatever its compression.

Inputs:
- a: The archive to read from
- index: The entry's position in the central directory
- buffer: Where the bytes go, which must be at least the entry's unpacked size

Returns:
- `.NONE`, or why the entry could not be unpacked
*/
extract :: proc(a: ^Archive, index: int, buffer: []byte) -> error.Code {
	if !mz_zip_reader_extract_to_mem(&a._zip, c.uint(index), raw_data(buffer), c.size_t(len(buffer)), 0) {
		return translate_error(mz_zip_get_last_error(&a._zip))
	}
	return .NONE
}

/*
Works out where an entry's bytes start.

The central directory only records where the local header is, and that header
carries its own copy of the name and its own extra field, whose lengths differ
from the ones in the directory. So the payload offset can only be found by
reading the local header.

Inputs:
- data: The whole archive
- local_header_offset: Where the entry's local header starts, from its record

Returns:
- offset: Where the entry's bytes start within `data`
- code: `.NONE`, or `.PAK_CORRUPT` when the header is not where it should be
*/
data_offset :: proc(data: []byte, local_header_offset: u64) -> (offset: u64, code: error.Code) {
	if local_header_offset + LOCAL_HEADER_SIZE > u64(len(data)) {
		return 0, .PAK_CORRUPT
	}

	local := data[local_header_offset:]
	if read_u32(local, 0) != SIG_LOCAL_FILE_HEADER {
		return 0, .PAK_CORRUPT
	}

	name_length := u64(read_u16(local, 26))
	extra_length := u64(read_u16(local, 28))
	return local_header_offset + LOCAL_HEADER_SIZE + name_length + extra_length, .NONE
}

/*
Reports what miniz said about the last failure on this archive.

Not safe to read while another thread might be failing on the same archive,
since miniz keeps it in the archive struct.

Inputs:
- a: The archive that failed

Returns:
- miniz's description, a static string that needs no freeing
*/
last_error_string :: proc(a: ^Archive) -> string {
	return string(mz_zip_get_error_string(mz_zip_get_last_error(&a._zip)))
}

@(private) SIG_LOCAL_FILE_HEADER :: u32(0x04034b50)
@(private) LOCAL_HEADER_SIZE :: u64(30)

@(private)
read_u16 :: proc(b: []byte, offset: int) -> u16 {
	return u16(b[offset]) | u16(b[offset + 1]) << 8
}

@(private)
read_u32 :: proc(b: []byte, offset: int) -> u32 {
	return u32(b[offset]) | u32(b[offset + 1]) << 8 | u32(b[offset + 2]) << 16 | u32(b[offset + 3]) << 24
}

/*
Folds miniz's error list down onto the engine's.

miniz distinguishes far more failures than the engine acts on, so several map
onto one code. `last_error_string` still has the exact reason when it matters.

Inputs:
- err: The code miniz reported

Returns:
- The matching engine code
*/
translate_error :: proc(err: Zip_Error) -> error.Code {
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
