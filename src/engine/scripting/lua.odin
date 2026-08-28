package scripting
import lua "vendor:lua/5.4"

make_env :: proc(L: ^lua.State) {
    lua.createtable(L, 0, 0)
    lua.createtable(L, 0, 1)
    lua.pushglobaltable(L)
    lua.setfield(L, -2, "__index")
    lua.setmetatable(L, -2)
}

load_lua :: proc(L: ^lua.State, src: []byte, name: cstring) -> i32 {
    make_env(L)
    lua.L_loadbuffer(L, raw_data(src), uint(len(src)), name)
    lua.pushvalue(L, -2)
    lua.setupvalue(L, -2, 1)
    lua.pcall(L, 0, 0, 0)
    return lua.L_ref(L, lua.REGISTRYINDEX)
}

update_lua :: proc(L: ^lua.State, ref: i32, dt: f64) {
    lua.rawgeti(L, lua.REGISTRYINDEX, lua.Integer(ref))
    lua.getfield(L, -1, "update")
    lua.pushnumber(L, lua.Number(dt))
    lua.pcall(L, 1, 0, 0)
    lua.pop(L, 1)
}