# pak

Read-only access to game assets stored in a zip archive.

---

## Provenance

**This package was written by Claude Opus 5 (Anthropic), in a session with Ethan
Warren on 2026-08-25.** Every `.odin` file in `src/pak`, the vendored miniz
build wiring in the repository `Makefile`, and this document are machine
written.

That matters, so it is stated plainly rather than buried:

- **Nobody has reviewed this line by line.** It compiles, and the behaviour
  described under [What was actually measured](#what-was-actually-measured) was
  observed on a real machine, but "it passed the tests I also wrote" is a weaker
  claim than "a person understands it".
- **The design decisions below are argued, not authoritative.** Several were
  reversed mid-session after measurement contradicted the reasoning. They could
  be wrong again in ways no test here would catch.
- **Treat [Landmines](#landmines) and [What is not verified](#what-is-not-verified)
  as the priority reading.** They are where the cost of not having written this
  yourself is actually paid.

[How to review this](#how-to-review-this) at the end is a suggested audit order
if you want to take ownership of it.

---

## What this is

A pak is a plain zip file used as a read-only directory that happens to live in
one file. Where a loose asset is `C:/assets/pig.png`, the same asset inside a
pak is `game.pak:assets/pig.png`.

Odin's standard library has no zip support — `core:compress` provides raw
DEFLATE and zlib, but nothing that understands the zip container. So this
package binds **miniz 3.0.2** (MIT), vendored in `vendor/miniz`, compiled to a
static library by the repository `Makefile`.

The package **reads only**. It cannot create a pak. That is deliberate — see
[Why there is no writer](#why-there-is-no-writer).

### Build requirement

The static library must exist before this package will link:

```
Windows   nmake windows      (from a Developer Command Prompt)
Linux     make linux
```

Without it you get `LNK1181: cannot open input file ... miniz.lib`, or the
equivalent missing `libminiz.a`.

---

## Quick start

```odin
import "core:fmt"
import "pak"
import "error"

archive, code := pak.open("game.pak")
if error.print(code) {
    return
}
defer pak.close(archive)

// A window onto the mapped file. No allocation, no copy.
// Valid until the pak is closed. Do not write to it or free it.
config, _ := pak.view_string(archive, "config/game.cfg")
fmt.println(config)

// A copy the caller owns, works whatever the entry's compression.
pixels, _ := pak.read(archive, "assets/pig.png")
defer delete(pixels)
```

Call `pak.destroy()` once at shutdown to release the handle pool.

---

## The mental model

Three things are worth internalising before reading the API.

**A pak has no directories.** The central directory is a flat, sorted table of
names. `dialogue/city1/vendor.txt` is one name that happens to contain slashes
— there is nothing to descend into. Looking an asset up is a lookup, not a
scan, regardless of how deeply "nested" the path looks. Some zip tools also
write zero-length entries whose names end in `/`; those are records *about*
directories, they are not readable, and `read` reports `PAK_ENTRY_NOT_FOUND`
for them rather than handing back an empty asset.

**`Pak` is a handle, not the archive.** It is a `distinct u32` naming a slot in
a package-level pool. Copy it, store it in a map, compare it — all safe.
`close` invalidates every copy of it at once. A handle to a closed pak returns
`PAK_INVALID_HANDLE` rather than following a dead pointer.

**`view` and `read` are genuinely different operations.** `view` hands back a
slice pointing *into the memory-mapped file*: nothing is allocated, nothing is
copied, and the bytes stay valid only until the pak is closed. `read` hands
back a copy the caller owns and must `delete`. `view` only works for entries
stored without compression; `read` works for anything. Prefer `view` for assets
you parse and discard, `read` when the bytes must outlive the pak or be
modified.

---

## API

### Lifetime

| | |
|---|---|
| `open(path, case_sensitive := true) -> (Pak, error.Code)` | Maps the file, reads the central directory. Nothing is decompressed. |
| `close(p)` | Releases the mapping. Invalidates every copy of the handle. Safe to call on an already-closed pak, so safe to `defer` after a failed open. |
| `destroy()` | Closes everything still open and frees the pool. Call at shutdown. |
| `is_open(p) -> bool` | Whether a handle still refers to an open pak. |
| `path_of(p) -> string` | The path it was opened from. Valid until closed. |

### Reading

| | |
|---|---|
| `view(p, name) -> ([]byte, error.Code)` | Zero-copy window onto the mapping. Stored entries only. |
| `view_string(p, name) -> (string, error.Code)` | Same, as a string. |
| `view_index(p, index) -> ([]byte, error.Code)` | By central-directory index. |
| `read(p, name, allocator) -> ([]byte, error.Code)` | Owned copy. Any compression method. `delete` it. |
| `read_string(p, name, allocator) -> (string, error.Code)` | Same, as a string. |
| `read_index(p, index, allocator) -> ([]byte, error.Code)` | By central-directory index. |

`view` on a compressed entry returns `PAK_ENTRY_COMPRESSED`. That is a
`WARNING`-severity code, not a failure — it means "use `read` instead":

```odin
pixels, code := pak.view(archive, "assets/pig.png")
if code == .PAK_ENTRY_COMPRESSED {
    pixels, code = pak.read(archive, "assets/pig.png")   // now owned, must delete
}
```

Note the ownership asymmetry in that pattern: the fallback allocates and the
fast path does not. If you write that branch, track which one you took.

### Inspection

| | |
|---|---|
| `contains(p, name) -> bool` | Presence without unpacking. |
| `size_of_entry(p, name) -> (u64, error.Code)` | Unpacked size, allocates nothing. |
| `stat(p, name) -> (Entry, error.Code)` | Record for a known name. `Entry.name` is left empty — you already have it. |
| `stat_index(p, index, allocator) -> (Entry, error.Code)` | Record by index. Clones `name`. |
| `entries(p, allocator) -> ([]Entry, error.Code)` | Every record, central-directory order. Clones names. |
| `count(p) -> int` | Number of entries, directory records included. |

`stat_index` and `entries` default to **`context.temp_allocator`** for the names
they clone. Fine within a frame; pass a real allocator if the list outlives one.

```odin
Entry :: struct {
    name:            string,   // only filled by entries() and stat_index()
    index:           int,
    size:            u64,
    compressed_size: u64,
    crc32:           u32,
    stored:          bool,     // true => view() will work
    is_directory:    bool,
}
```

### References

`split_reference("game.pak:assets/pig.png")` splits a combined reference into
the archive path and the entry path. It splits on the **last** colon so
`C:/game/game.pak:assets/pig.png` survives. `find(archive_path)` returns an
already-open pak by the path it was opened from, so a reference can be resolved
without reopening.

These are deliberately minimal. There is no mount stack, no search path, no
override ordering — that belongs in a layer above this one.

### Integrity

`verify_crc` (package-level, default `true`) controls whether entries are checked
against their stored CRC-32. Checking is **cached per entry per open pak**: the
mapping cannot change underneath you, so an entry that verified once is not
checked again. Set to `false` for a shipping build reading paks it trusts.

It is global mutable state. Flipping it affects every pak in the process, and it
is not thread-safe — see [Landmines](#landmines).

---

## Why it is built this way

Decisions where the obvious choice was wrong, or where the reasoning is not
recoverable from reading the code.

### Why miniz rather than hand-parsing zip

The first implementation attempt hand-parsed the zip container in Odin. That is
genuinely doable — the format is not complicated — but it means owning ZIP64,
data descriptors, extra-field parsing, and the edge cases of every tool that has
ever written an archive. miniz is one vendored C file with an MIT licence and
those cases already handled.

### Why the C library is built `/MT` on Windows

**This one was measured, and the intuitive answer was wrong.**

Odin's `vendor:raylib` passes `/NODEFAULTLIB:libcmt` to the linker, which reads
as "raylib expects the dynamic CRT", suggesting miniz should be `/MD` to match.
Building it `/MD` **fails to link** with 14 unresolved `__imp_*` externals
(`__imp__wfopen_s`, `__imp_realloc`, `__imp__ftelli64`, …).

The reason: Odin links the *static UCRT* (`libucrt.lib`). raylib's flag excludes
only `libcmt`, the older static CRT startup library — not `libucrt`. So `/MT` is
correct and `/MD` is broken. The `Makefile` records this; do not "fix" it.

### Why `Pak` is a handle and not a struct

`mz_zip_reader_init_mem` executes `pZip->m_pIO_opaque = pZip` — miniz stores a
pointer to its own struct inside itself. A `Pak` holding that struct by value
would break the moment it was copied or moved: `a := b`, a `[dynamic]Pak` that
reallocates, a `map[string]Pak` that rehashes. All silent corruption, no
compile error, because Odin copies structs freely.

Earlier drafts pushed this onto callers (`^pak.Pak` everywhere, with a comment
explaining why). The handle absorbs it instead: the archive lives in a
heap-allocated pool entry that never moves, and the handle is an integer that is
meaningless to copy incorrectly. The generation counter means a reused slot does
not answer to handles from its previous occupant.

### Why the file is memory-mapped

A pak is immutable once built. That means the OS can share one set of physical
pages between every reader and drop them under memory pressure without writing
anything back — and, more importantly here, it means a stored entry is a
*contiguous run of plain bytes already in the address space*. Handing it out
costs a slice construction. That is what `view` is.

The mapping is also what miniz reads from: `mz_zip_reader_init_mem` parses the
central directory straight out of it, so no separate file I/O path exists. The
file descriptor is closed immediately after mapping, since the mapping holds its
own reference.

### Why the CRC check moved out of miniz, and is cached

miniz verifies CRC-32 byte-at-a-time. On a pak stored without compression that
verification is **most of the cost of a load**. Measured on a 32 MB stored entry,
before the mapping rewrite:

| | per read | throughput |
|---|---|---|
| miniz's CRC | 74.7 ms | 428 MB/s |
| `core:hash` CRC | 22.5 ms | 1422 MB/s |
| no CRC at all | 6.7 ms | 4800 MB/s |

So miniz's check is compiled out (`MINIZ_DISABLE_ZIP_READER_CRC32_CHECKS` in the
`Makefile`) and the package does it with `core:hash`, which is slice-by-8 rather
than byte-at-a-time. **Removing that define does not disable checking — it just
pays for it twice.**

Caching came later, and mattered more. Verifying on every `view` defeated the
entire point of mapping: ten views of a 32 MB entry took 163 ms, all of it
CRC. Since the mapping cannot change while it is open, an entry only needs
verifying once, so there is now a bit per entry recording it. Same guarantee,
and ten views became 2.6 µs.

### Why lookups are case-sensitive by default

The first version was case-insensitive, which is friendlier on Windows and hides
a bug that only appears on Linux: develop on Windows, everything resolves, ship
to a case-sensitive filesystem, `Models/Box.obj` stops matching `models/box.obj`.
Defaulting to strict means the mistake fails on the machine that made it.
`open(path, case_sensitive = false)` opts back out.

An earlier version also silently retried lookups with backslashes, because
PowerShell's `Compress-Archive` writes non-conformant paths. That was removed
for the same reason: it accepted malformed paks rather than reporting them.

### Why the encryption check comes before the compression check

In `view_index` the order of those two checks is load-bearing, and reversing it
looks like a harmless tidy-up.

ZipCrypto encrypts an entry's bytes but leaves the compression method field
reading whatever it was before encryption. So a stored, encrypted entry reports
`method == 0` and looks perfectly viewable. Checking the method first meant
`view` computed an offset into the mapping and handed back **raw ciphertext
presented as the asset** — silently, when `verify_crc` was off, and as a
misleading `PAK_CORRUPT` when it was on.

Checking `is_encrypted` and `is_supported` first also makes AES entries report
being unsupported rather than merely compressed, which is the more useful
diagnosis. This was a real bug, found by testing against 7-Zip archives; the
tests are described under [What was actually measured](#what-was-actually-measured).

### Why there is no writer

Packing is an export-tooling step, run once when the game is built, not an
engine feature. It lives in a Python script rather than here.

The second-order reason matters more: keeping this package read-only is what
makes the mapping safe. A mutable archive cannot share a stable read-only
mapping, so a writer here would fight `view` directly.

Save data is a separate concern and should **not** go in a pak. A zip cannot be
updated in place — adding an entry rewrites the archive — so a mid-game save
would rewrite the whole file. Saves also need atomic write-and-rename for crash
safety, live in a user directory, and are per-slot and versioned. None of that is
what an asset archive is good at. miniz's writer is compiled into the static
library and simply not bound; if a save *bundle* is ever wanted, it is available.

---

## Landmines

Ranked by how likely they are to cause a bad afternoon.

**1. None of this is thread-safe.** The archive pool is global mutable state, and
`view`/`read` write to the per-entry verification bitset. Two threads touching
the same pak — or `open`/`close` on any thread while another reads — is a data
race. `verify_crc` is a global too. If asset loading ever moves to a worker
thread, this needs a lock or per-thread pools, and nothing here will warn you.

**2. `view` results die with the pak.** They point into the mapping. After
`close` they are dangling, and nothing detects this. Anything outliving the pak
must be `read` or cloned. The `pak_scene` example clones every string it keeps
for exactly this reason.

**3. Views are not writable.** The mapping is read-only. Writing through a
`view` slice is an access violation on Windows and a `SIGSEGV` on Linux, at the
write, with no indication the memory came from a pak. Odin has no way to express
"const slice", so nothing stops you.

**4. Temp-allocator defaults.** `entries` and `stat_index` clone names into
`context.temp_allocator`. Hold one past a `free_all(context.temp_allocator)` and
it is garbage. Pass an explicit allocator for anything kept.

**5. `PAK_ENTRY_COMPRESSED` changes ownership.** The `view`-then-fall-back-to-
`read` pattern returns borrowed bytes on one path and owned bytes on the other.
Free the wrong one and you have either a leak or a crash.

**6. The pak must not change on disk while open.** The mapping reflects the file.
Rewriting a pak that a running process has mapped is undefined — on Windows the
open mapping usually prevents it, on Linux it will not.

---

## What was actually measured

On the development machine (Windows 11, Odin `dev-2026-07-nightly`, MSVC 14.51),
and in WSL2 Ubuntu 26.04 with Odin `dev-2026-08-nightly` and gcc 15.2.

**Current implementation**, 32 MB stored entry, ten iterations:

| | Windows | Linux |
|---|---|---|
| `view` ×10 | 2.6 µs | 37.8 µs |
| `read` ×10 | 60.6 ms (5281 MB/s) | 164 ms (1951 MB/s) |

The Linux `read` figure is depressed because the file sat on WSL's `/mnt/e`
bridge rather than ext4; it is not a fair Linux number. The `view` figures touch
none of the bytes, so a MB/s figure for them would be measuring work that never
happens.

**Behaviour verified on both platforms**, by a test harness that has since been
deleted (it lived in the gitignored `test/`):

- Two views of the same entry return the same address; a `read` returns a
  different address holding identical bytes.
- Closing through one handle invalidates a copy of it; a reused pool slot
  rejects the old handle; reads through a stale handle return
  `PAK_INVALID_HANDLE`.
- Strict matching rejects wrong case; `case_sensitive = false` accepts it.
- A DEFLATE entry returns `PAK_ENTRY_COMPRESSED` from `view` and reads correctly
  via `read`; `Entry.stored` reports `false`.
- Encrypted entries are rejected by both `read` and `view`, with
  `PAK_UNSUPPORTED_FEATURE`, for ZipCrypto and AES-256 archives produced by
  7-Zip. `Entry.encrypted` reports `true` for both. Tested with `verify_crc`
  both on and off, since the CRC check would otherwise mask the failure.
- Tracking allocator: 0 leaks, 0 bad frees, after `pak.destroy()`.

**Other measurements from the session:**

- Corruption is caught: flipping one byte inside a stored entry gives
  `PAK_CORRUPT` with `verify_crc = true`, and passes the bad bytes through with
  it `false`.
- Linking cost: a raylib + box3d binary went 898,560 → 929,280 bytes with pak
  linked, about 30 KB.
- DLL dependencies: miniz adds exactly one,
  `api-ms-win-crt-time-l1-1-0.dll`, a UCRT forwarder present on Windows 10/11.
  `VCRUNTIME140.dll` also appears but comes from Odin's prebuilt `raylib.lib`
  and is there with or without this package.

---

## What is not verified

Be suspicious of all of the following. None of it has been exercised.

- **macOS.** `map_posix.odin` carries a `darwin` build tag and `core:sys/posix`
  should cover it, but it has never been compiled or run there. The `Makefile`
  has no macOS target; `make linux` would probably work, except
  `-D_LARGEFILE64_SOURCE` is glibc-specific.
- **ZIP64.** Archives over 4 GB, or with more than 65535 entries. miniz handles
  ZIP64 and the code paths exist, but nothing that large was ever built.
- **Paks larger than available address space.** The whole file is mapped. On
  64-bit this is academic; it is still an assumption nothing checks.
- **Threading.** See landmine 1. Never tested, and expected to be broken.
- **Decrypting anything.** Encrypted entries are *detected and rejected*, which
  is tested (see below), but this package cannot read a password-protected pak
  and there are no plans for it to.
- **Archives from tools other than Python's `zipfile` and .NET's
  `System.IO.Compression`.** Notably untested against 7-zip, Info-ZIP, and
  WinRAR output.
- **Use by the engine.** Nothing in `src/` imports this package. It has only
  ever been driven by examples and a test harness.

---

## How to review this

A suggested order, cheapest and highest-value first.

1. **`Makefile`** (~30 lines). Two targets, four commands. Confirms exactly what
   the C library is built with and why.
2. **`map_windows.odin` / `map_posix.odin`** (~50 lines each). The only
   platform-specific code. Small enough to check against the Win32 and POSIX
   documentation directly.
3. **`Landmines` above.** Decide which of them actually apply to your usage.
   Thread safety is the one most likely to become real.
4. **`pak.odin`, the handle machinery** — `_handle`, `_archive`, `_acquire`,
   `_release`. About 60 lines. If the generation logic is wrong, stale handles
   silently resolve to the wrong archive, which is the worst failure mode in the
   package.
5. **`pak.odin`, `view_index` and `_data_offset`.** This is where a bad offset
   would hand out the wrong bytes, or bytes outside the entry. `_data_offset`
   parses the local file header by hand — check the offsets (26 and 28) against
   the zip specification.
6. **`miniz.odin`, the struct layouts.** `Zip_Archive` and
   `Zip_Archive_File_Stat` mirror C structs field by field. A mismatch here
   produces plausible-looking garbage rather than a crash. Worth checking
   against `vendor/miniz/miniz.h` if anything ever reads wrong.
7. **`vendor/miniz/miniz.c`** is upstream 3.0.2, unmodified. It is not machine
   written and does not need reviewing as such — but it is 300 KB of C that now
   parses your asset files.

The fastest way to build confidence is to rebuild the deleted test harness: it
is described in [What was actually measured](#what-was-actually-measured) and
every assertion there is a few lines of Odin.
