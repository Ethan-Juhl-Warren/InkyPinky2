package config
import "core:os"
import "core:strconv"
import "../error"
import "core:strings"

@(private) engine_config: Config

CONFIG_FILE_NAME :: "./engine.cfg"

@(private)
Config :: struct {
    packed_assets: bool,
}

assets_packed :: proc() -> bool {
    return engine_config.packed_assets
}

load_config :: proc() {
    engine_config = _parse_config_file(CONFIG_FILE_NAME)
}

@(private)
_parse_config_file :: proc(path: string) -> Config {
    cfg_file := _read_file(path)
    defer delete(cfg_file)
    text := cfg_file
    config: Config
    for line in strings.split_lines_iterator(&text) {
        trimmed := strings.trim_space(line)
        if len(trimmed) == 0 || strings.has_prefix(trimmed, "#") {
            continue
        }

        parts, err := strings.split_n(trimmed, " ", 2, context.temp_allocator)
        if err != nil || len(parts) < 2 {
            error.must(.CANNOT_OPEN_FILE)
        }

        key := parts[0]
        value := strings.trim_space(parts[1])
        switch key {
            case "packed_assets": 
                val_bool, ok := strconv.parse_bool(value)
                config.packed_assets = val_bool
            case:
                error.must(.CANNOT_OPEN_FILE) 
        }
    }
    return config
}

// just avoiding a circular dependancy on file
@(private)
_read_file :: proc(path: string) -> string {
    data, err := os.read_entire_file_from_path(path, context.allocator)
    if err != os.ERROR_NONE {
        error.must(.FILE_NOT_FOUND)
    }
    return string(data)
}
