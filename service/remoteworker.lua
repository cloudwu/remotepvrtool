local skynet = require "skynet"
local socket = require "socket"
local md5 = require "md5"
local lfs = require "lfs"
local cache = require "cachefile"

local pvr_path = skynet.getenv "pvr"

local config = {
	path = pvr_path .. "/pvrtex/",
	pvrtool = pvr_path .. "/pvr/PVRTexToolCLI",
	slave = skynet.getenv("thread") - 2,
}

local command = {}
local convert = {}
local queue = {}

local function init_convert()
	for i = 1, config.slave do
		local s = skynet.newservice("textool")
		skynet.call(s, "lua", "init", config)
		convert[i] = s
		queue[i] = 0
	end
	skynet.info_func(function()
		return queue
	end)
end

local function convert_call(...)
	local idx = 1
	local min = queue[1]
	if min > 0 then
		for i = 2, config.slave do
			local ql = queue[i]
			if ql == 0 then
				idx = i
				break
			end
			if ql < min then
				min = ql
				idx = i
			end
		end
	end

	local s = convert[idx]
	queue[idx] = queue[idx] + 1
	local ok, err = pcall(skynet.call, s, "lua", "convert", ...)
	queue[idx] = queue[idx] - 1
	return err
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

local function exist_file(fullpath, fd, size)
	local sz = lfs.attributes(fullpath, "size")
	if sz then
		if sz ~= size then
			socket.write(fd, "ERROR Invalid size\n")
			error (string.format("Invalid size %d | %d", size, sz))
		else
			lfs.touch(fullpath)
			socket.write(fd, "EXIST\n")
			return true
		end
	end
	return false
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
	if exist_file(fullpath, fd, size) then
		return
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
	local remove_ok, err2 = os.remove(tn)
	if not remove_ok then
		skynet.error("Remove failed: " .. tn .. " " .. err2)
	end
	if not ok then
		if exist_file(fullpath, fd, size) then
			return
		end
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
	local err = convert_call(fd, args, download_hash)
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
	skynet.newservice("debug_console",8000)
	cache.init(config.path)
	local port = skynet.getenv("port") or 8964
	skynet.error("Listen 0.0.0.0:"..port)
	local fd = assert(socket.listen("0.0.0.0", port))
	skynet.error("Worker:"..config.slave)
	init_convert()
	socket.start(fd, function(cfd, addr)
		skynet.error(addr .. " connected")
		dispatch(cfd)
	end)
end)
