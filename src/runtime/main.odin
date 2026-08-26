package main

// "system:" means the linker resolves this by name instead of Odin resolving it
// as a path relative to this file. Where the library actually is stays in the
// Makefile as a search path, so nothing here has to know the build layout.
when ODIN_OS == .Windows {
    foreign import engine "system:engine.lib"
}  else {
    foreign import engine "system:engine"
}

foreign engine {
    engine_init :: proc "c" () -> bool ---
    engine_tick :: proc "c" () -> bool ---
    engine_destroy :: proc "c" () -> bool ---
    engine_stop :: proc "c" () -> bool ---

}

main :: proc() {
    if !engine_init() do return
    defer engine_destroy()

    for !engine_stop() {
        engine_tick()
    }
}