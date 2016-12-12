#include <string.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#ifndef SCRIPT
#define SCRIPT "pvrtextool.lua"
#endif

int luaopen_md5(lua_State *L);
int luaopen_lsocket(lua_State *L);

static int
init(lua_State *L) {
	luaL_openlibs(L);
	luaL_requiref(L, "lsocket", luaopen_lsocket, 0);
	luaL_requiref(L, "md5", luaopen_md5, 0);
	return 0;
}

int
main(int argc, char *argv[]) {
	int sz = strlen(argv[0]);
	char script[sz + sizeof(SCRIPT)];
	int i;
	for (i=sz-1;i>=0;i--) {
		char c = argv[0][i];
		if (c == '/' || c == '\\') {
			break;
		}
	}
	++i;
	memcpy(script, argv[0], i);
	memcpy(script+i, SCRIPT, sizeof(SCRIPT));
	lua_State *L = luaL_newstate();
	lua_pushcfunction(L, init);
	if (lua_pcall(L,0,0,0) != LUA_OK) {
		printf("Err: %s", lua_tostring(L, -1));
		lua_close(L);
		return 1;
	}
	int ok = luaL_loadfile(L, script);
	if (ok != LUA_OK) {
		printf("Err: %s", lua_tostring(L, -1));
		lua_close(L);
		return 1;
	}
	luaL_checkstack(L, argc, NULL);
	for (i=1;i<argc;i++) {
		lua_pushstring(L, argv[i]);
	}
	if (lua_pcall(L, argc-1, 0, 0) != LUA_OK) {
		printf("Err: %s", lua_tostring(L, -1));
		lua_close(L);
		return 1;
	}

	lua_close(L);
	
	return 0;
}
