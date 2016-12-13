# link lua static lib
LUA_INC=/usr/local/include
LUA_LIB=-L/usr/local/lib -llua

mingw : fakepvr.exe

fakepvr.exe : fakepvr.c lsocket.c win_compat.c lmd5.c
	gcc -g -Wall -o $@ $^ -I$(LUA_INC) $(LUA_LIB) -lws2_32 $(SCRIPT)

pvrformat : fakepvr.c lsocket.c lmd5.c
	gcc -g -Wall -o $@ $^ -I$(LUA_INC) $(LUA_LIB) -DSCRIPT=\"pvrformat.lua\"

pvrpush : fakepvr.c lsocket.c lmd5.c
	gcc -g -Wall -o $@ $^ -I$(LUA_INC) $(LUA_LIB) -DSCRIPT=\"pvrpush.lua\"

clean :
	rm -f fakepvr.exe
	rm -f pvrformat

