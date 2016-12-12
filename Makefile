lualib/lfs.so : luafilesystem/src/lfs.c
	gcc -O2 -Wall $^ -fPIC --shared -o $@ -Iluafilesystem/src -Iskynet/3rd/lua

clean :
	rm -f lualib/lfs.so


