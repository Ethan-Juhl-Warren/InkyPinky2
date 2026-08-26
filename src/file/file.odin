package file
import "../pak"
import "../error"
import "../config"
import "core:os"

@(private) assets: pak.Pak
@(private) ASSET_PACK_PATH :: "./assets.pak"

read_file :: proc(path: string) -> (string, error.Code) {
    data, err := read_file_bytes(path)
    if err != .NONE {
        return "", err
    } else {
        return string(data), err
    }
}

read_file_bytes :: proc(path: string) -> ([]byte, error.Code) {
    data, err := os.read_entire_file_from_path(path, context.allocator)
    if err != os.ERROR_NONE {
        return nil, .FILE_NOT_FOUND
    }
    return data, .NONE
}

load_asset_pack :: proc() {
    if config.assets_packed() {
        init_error := pak.init()
        error.must(init_error)
        pack, err := pak.mount(ASSET_PACK_PATH)
        error.must(err)
        assets = pack
    }
}

release_asset_pack :: proc() {
    if config.assets_packed() {
        pak.unmount(assets)
        pak.destroy()
    }
}

read_asset :: proc{read_asset_by_path, read_asset_by_hash}

read_asset_by_path :: proc(path: string) -> ([]byte, error.Code) {
    if config.assets_packed() {
        return pak.read(assets, path)
    } else {
        return read_file_bytes(path)
    }
    
}

read_asset_by_hash :: proc(hash: pak.Hash) -> ([]byte, error.Code) {
    if config.assets_packed() {
        return pak.read(assets, hash)
    } else {
        error.must(.INVALID_READ_TO_ASSET_PACK)
        return nil, .INVALID_READ_TO_ASSET_PACK // kkk unreachable
    }
}
