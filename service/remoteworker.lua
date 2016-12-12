local skynet = require "skynet"
local socket = require "socket"
local md5 = require "md5"
local lfs = require "lfs"
local cache = require "cachefile"

local config = {
	path = "/home/cloud/pvrtex/",
	pvrtool = "/home/cloud/pvr/PVRTexToolCLI",
	slave = 8,
}

local command = {}
local convert = {}

local function init_convert()
	convert.n = 1
	for i = 1, config.slave do
		local s = skynet.newservice("textool")
		skynet.call(s, "lua", "init", config)
		convert[i] = s
	end
end

local function choose_convert()
	local s = convert[convert.n]
	convert.n = convert.n + 1
	if convert.n > config.slave then
		convert.n = 1
	end
	return s
end

-- c->s md5
-- c<-s OK size
--      size of bytes
-- c<-s NOTFOUND
-- c<-s ERROR string
function command.GET(fd, hash)
	local fullpath = cache.download_name(hash)
	local sz = lfs.attributes(fullpath, "size")
	if not sz then
		socket.write(fd, "NOTFOUND\n")
		return
	end
	local f = io.open(fullpath, "rb")
	if f == nil then
		socket.write("ERROR Can't open\n")
		error("Can't open " .. fullpath)
	end
	socket.write(fd, "OK " .. sz .. "\n")
	local data = f:read "a"
	f:close()
	assert(#data == sz , "Invalid size")
	socket.write(fd, data)
end

-- c->s size md5.ext
-- c<-s EXIST
--      OK
-- c->s size of bytes
-- c<-s ERROR string
function command.PUT(fd, args)
	local size, hash, ext = args:match("(%d+) ([%da-f]+)%.([%w]+)")
	if size == nil or hash == nil or ext == nil then
		socket.write(fd, "ERROR Invalid command\n")
		error ( "Invalid command " .. args )
	end
	size = tonumber(size)
	local fullpath = cache.upload_name(hash, ext)
	local sz = lfs.attributes(fullpath, "size")
	if sz then
		if sz ~= size then
			socket.write(fd, "ERROR Invalid size\n")
			error (string.format("Invalid size %d | %d", size, sz))
		else
			lfs.touch(fullpath)
			socket.write(fd, "EXIST\n")
			return
		end
	end
	socket.write(fd, "OK\n")
	local data = assert(socket.read(fd, size), "size invalid")
	local h = md5.sumhexa(data)
	if h~=hash then
		socket.write(fd, "ERROR Invalid md5\n")
		error "Invalid md5"
	end
	local tn = os.tmpname()
	local f = io.open(tn,"wb")
	if f == nil then
		socket.write(fd, "ERROR create file failed\n")
		error ("create " .. tn .. " failed")
	end
	f:write(data)
	f:close()
	local ok, err = lfs.link(tn, fullpath)
	os.remove(tn)
	if not ok then
		socket.write(fd, "ERROR write failed\n")
		error (err)
	else
		socket.write(fd, "OK\n")
	end
end

local working = {}

local function wait(hash)
	if working[hash] then
		local co = coroutine.running()
		skynet.error("Queue " .. hash)
		if working[hash] == true then
			working[hash] = { co }
		else
			table.insert(working[hash], co)
		end
		skynet.wait(co)
	end
end

local function wakeup(hash)
	local w = working[hash]
	if w ~= true then
		for _,co in ipairs(w) do
			skynet.wakeup(co)
		end
	end
	working[hash] = nil
end

-- c->s I:md5 I:md5 ... O:ext !...(command line)
-- c<-s MISSING md5 md5 ...
-- c<-s OK md5 (result file)
-- c<-s ERROR string
function command.TEX(fd, args)	-- pvrtextools
	local download_hash = md5.sumhexa(args)
	wait(download_hash)
	local download_name = cache.download_name(download_hash)
	local download_size =  lfs.attributes(download_name, "size")
	if download_size then
		-- already convert
		lfs.touch(download_name)
		skynet.error("Cache file : " .. download_hash)
		socket.write(fd, "OK " .. download_hash .. "\n")
		return
	end
	working[download_hash] = true
	socket.abandon(fd)
	local err = skynet.call(choose_convert(), "lua", "convert", fd, args, download_hash)
	socket.start(fd)
	wakeup(download_hash)
	if err then
		error(err)
	end
end

local function dispatch(cfd)
	socket.start(cfd)
	local req = socket.readline(cfd)
	if not req then
		socket.close(cfd)
		skynet.error("disconnect")
		return
	end
	skynet.error(req)
	local cmd, args = req:match("(%u+)%s+(.*)")
	local f = command[cmd]
	if f == nil or args == nil then
		skynet.error "Invalid request"
		socket.close(cfd)
	end

	local ok , err = pcall(f , cfd, args)
	if not ok then
		socket.close(cfd)
		skynet.error("Failed " .. err)
	end
	socket.close(cfd)
end

skynet.start(function()
	cache.init(config.path)
	local port = skynet.getenv("port") or 8964
	skynet.error("Listen 0.0.0.0:"..port)
	local fd = assert(socket.listen("0.0.0.0", port))
	init_convert()
	socket.start(fd, function(cfd, addr)
		skynet.error(addr .. " connected")
		dispatch(cfd)
	end)
end)
