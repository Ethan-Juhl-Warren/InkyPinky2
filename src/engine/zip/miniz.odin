#+private
package zip

import "core:c"

/*
WRITTEN BY CLAUDE OPUS 5 (Anthropic), 2026-08-25. Not reviewed line by line by a
human. The structs below mirror C structs field by field, so a mismatch produces
plausible looking garbage rather than a crash. See README.md.

Bindings for the vendored miniz, which supplies the zip container handling and
the DEFLATE codec that `pak` is built on.

The static library has to exist before this package will link, so build it first
with `nmake windows` or `make linux` (see the Makefile in the repo root).

Only the memory reader is bound. A pak is opened by mapping the file and handing
miniz the mapping, so the file based reader is never used, and the writer is not
bound at all because a pak is built by the export tooling rather than the engine.

Everything here is package private, the rest of the engine talks to `pak.odin`.
*/
when ODIN_OS == .Windows {
	foreign import miniz "../../../vendor/miniz/miniz.lib"
} else {
	foreign import miniz "../../../vendor/miniz/libminiz.a"
}

// Passed to `mz_zip_reader_locate_file_v2` to match entry names exactly rather
// than case insensitively.
MZ_ZIP_FLAG_CASE_SENSITIVE :: c.uint(0x0100)

// Longest filename `Zip_Archive_File_Stat` can hold, names past this are truncated.
MAX_FILENAME_SIZE :: 512

// Longest per-entry comment `Zip_Archive_File_Stat` can hold.
MAX_COMMENT_SIZE :: 512

/*
What the archive is currently open for. Mirrors miniz's `mz_zip_mode`.
*/
Zip_Mode :: enum c.int {
	INVALID = 0,
	READING = 1,
	WRITING = 2,
	WRITING_HAS_BEEN_FINALIZED = 3,
}

/*
Where the archive's bytes come from. Mirrors miniz's `mz_zip_type`.
*/
Zip_Type :: enum c.int {
	INVALID = 0,
	USER,
	MEMORY,
	HEAP,
	FILE,
	CFILE,
	TOTAL_TYPES,
}

/*
Why the last miniz call failed. Mirrors miniz's `mz_zip_error`, so the order of
these members has to stay exactly as it is in miniz.h.
*/
Zip_Error :: enum c.int {
	NO_ERROR = 0,
	UNDEFINED_ERROR,
	TOO_MANY_FILES,
	FILE_TOO_LARGE,
	UNSUPPORTED_METHOD,
	UNSUPPORTED_ENCRYPTION,
	UNSUPPORTED_FEATURE,
	FAILED_FINDING_CENTRAL_DIR,
	NOT_AN_ARCHIVE,
	INVALID_HEADER_OR_CORRUPTED,
	UNSUPPORTED_MULTIDISK,
	DECOMPRESSION_FAILED,
	COMPRESSION_FAILED,
	UNEXPECTED_DECOMPRESSED_SIZE,
	CRC_CHECK_FAILED,
	UNSUPPORTED_CDIR_SIZE,
	ALLOC_FAILED,
	FILE_OPEN_FAILED,
	FILE_CREATE_FAILED,
	FILE_WRITE_FAILED,
	FILE_READ_FAILED,
	FILE_CLOSE_FAILED,
	FILE_SEEK_FAILED,
	FILE_STAT_FAILED,
	INVALID_PARAMETER,
	INVALID_FILENAME,
	BUF_TOO_SMALL,
	INTERNAL_ERROR,
	FILE_NOT_FOUND,
	ARCHIVE_TOO_LARGE,
	VALIDATION_FAILED,
	WRITE_CALLBACK_FAILED,
	TOTAL_ERRORS,
}

/*
An open archive, mirroring miniz's `mz_zip_archive`.

miniz parks a pointer to this struct inside itself when the reader is
initialised, so once opened it must not be moved or copied. `Pak` owns one by
value and is only ever passed around by pointer for that reason.
*/
Zip_Archive :: struct {
	archive_size: u64,
	central_directory_file_ofs: u64,
	total_files: u32,
	zip_mode: Zip_Mode,
	zip_type: Zip_Type,
	last_error: Zip_Error,
	file_offset_alignment: u64,

	alloc: rawptr,
	free: rawptr,
	realloc: rawptr,
	alloc_opaque: rawptr,

	read: rawptr,
	write: rawptr,
	needs_keepalive: rawptr,
	io_opaque: rawptr,

	state: rawptr,
}

/*
One entry's central directory record, mirroring miniz's
`mz_zip_archive_file_stat`.

`filename` and `comment` are fixed size and always NUL terminated, so this is a
little over a kilobyte, big enough that it is worth keeping on the stack rather
than in a long lived list.
*/
Zip_Archive_File_Stat :: struct {
	file_index: u32,
	central_dir_ofs: u64,

	version_made_by: u16,
	version_needed: u16,
	bit_flag: u16,
	method: u16,

	crc32: u32,
	comp_size: u64,
	uncomp_size: u64,

	internal_attr: u16,
	external_attr: u32,
	local_header_ofs: u64,
	comment_size: u32,

	is_directory: b32,
	is_encrypted: b32,
	is_supported: b32,

	filename: [MAX_FILENAME_SIZE]u8,
	comment: [MAX_COMMENT_SIZE]u8,

	time: i64,
}

@(default_calling_convention="c")
foreign miniz {
	mz_zip_zero_struct :: proc(pZip: ^Zip_Archive) ---
	mz_zip_reader_init_mem :: proc(pZip: ^Zip_Archive, pMem: rawptr, size: c.size_t, flags: c.uint) -> b32 ---
	mz_zip_reader_end :: proc(pZip: ^Zip_Archive) -> b32 ---
	mz_zip_reader_get_num_files :: proc(pZip: ^Zip_Archive) -> c.uint ---
	mz_zip_reader_file_stat :: proc(pZip: ^Zip_Archive, file_index: c.uint, pStat: ^Zip_Archive_File_Stat) -> b32 ---
	mz_zip_reader_locate_file_v2 :: proc(pZip: ^Zip_Archive, pName: cstring, pComment: cstring, flags: c.uint, pFile_index: ^u32) -> b32 ---
	mz_zip_reader_extract_to_mem :: proc(pZip: ^Zip_Archive, file_index: c.uint, pBuf: rawptr, buf_size: c.size_t, flags: c.uint) -> b32 ---
	mz_zip_get_last_error :: proc(pZip: ^Zip_Archive) -> Zip_Error ---
	mz_zip_get_error_string :: proc(mz_err: Zip_Error) -> cstring ---
}
