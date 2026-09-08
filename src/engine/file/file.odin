package file
import "../pak"
import "../error"
import "../config"
import "core:os"

@(private) assets: pak.Pak
@(private) ASSET_PACK_PATH :: "./assets.pak"

/*
Assets can be refrenced as a path: string. or a pak hash: pak.Hash
*/
AssetRefrence :: union {
	string,
	pak.Hash
}

/*
Reads a loose file from disk as a string

Input:
- path: string the path to the file on disk

Output:
The contents of the file as a string
An error code

Note:
read_asset is prefered for actual game assets like textures which could be in a pak file
*/
read_file :: proc(path: string) -> (string, error.Code) {
    data, err := read_file_bytes(path)
    if err != .NONE {
        return "", err
    } else {
        return string(data), err
    }
}

/*
Reads a loose file from disk as a byte array

Input:
- path: string the path to the file on disk

Output:
The contents of the file as a byte array
An error code
read_asset is prefered for actual game assets like textures which could be in a pak file
*/
read_file_bytes :: proc(path: string) -> ([]byte, error.Code) {
    data, err := os.read_entire_file_from_path(path, context.allocator)
    if err != os.ERROR_NONE {
        return nil, .FILE_NOT_FOUND
    }
    return data, .NONE
}

/*
Attempts to mount an asset pack if the engine is configured to do so
*/
load_asset_pack :: proc() {
    if config.assets_packed() {
        init_error := pak.init()
        error.must(init_error)
        pack, err := pak.mount(ASSET_PACK_PATH)
        error.must(err)
        assets = pack
    }
}

/*
Attempts to release a pak if the engine is configured to do so
*/
release_asset_pack :: proc() {
    if config.assets_packed() {
        pak.unmount(assets)
        pak.destroy()
    }
}

/*
Reads an asset from the mounted pak file and returns its contents as a byte array
*/
read_asset :: proc{
    read_asset_by_refrence, 
    read_asset_by_path, 
    read_asset_by_hash
}

/*
Reads an asset from the mounted pak file and returns its contents as a byte array

Input:
- path: string Path to asset in pak or on disk

Outputs:
A byte array containing file contents
An Error code

Note:
Should only be used for files that will be packed into a pak on build
*/
read_asset_by_path :: proc(path: string) -> ([]byte, error.Code) {
    if config.assets_packed() {
        return pak.read(assets, path)
    } else {
        return read_file_bytes(path)
    }
    
}

/*
Reads an asset from the mounted pak file and returns its contents as a byte array

Input:
- hash: string Hash of asset in pak

Outputs:
A byte array containing file contents
An Error code

Note:
Should only be used for files that will be packed into a pak on build
Calling this while not using an asset pack will cause the engine to panic
*/
read_asset_by_hash :: proc(hash: pak.Hash) -> ([]byte, error.Code) {
    if config.assets_packed() {
        return pak.read(assets, hash)
    } else {
        error.throw(.INVALID_READ_TO_ASSET_PACK)
        return nil, .INVALID_READ_TO_ASSET_PACK // unreachable
    }
}

/*
Reads an asset from the mounted pak file and returns its contents as a byte array

Input:
- regrence: AssetRefrence Refrence to asset in pak

Outputs:
A byte array containing file contents
An Error code

Note:
Should only be used for files that will be packed into a pak on build
Calling this while not using an asset pack will cause the engine to panic
*/
read_asset_by_refrence :: proc(refrence: AssetRefrence) -> ([]byte, error.Code) {
    switch r in refrence {
        case string: return read_asset_by_path(r)
        case pak.Hash: return read_asset_by_hash(r)
    }
    return nil, .CANNOT_OPEN_FILE
}