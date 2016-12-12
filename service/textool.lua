local skynet = require "skynet"
local socket = require "socket"
local md5 = require "md5"
local lfs = require "lfs"
local cache = require "cachefile"

local config

local function remove(filename)
	local ok, err = os.remove(filename)
	if not ok then
		skynet.error("Remove failed: " .. filename .. " " .. err)
	end
end

local function convert(fd, args, download_hash)
	local download_name = cache.download_name(download_hash)
	local input
	local missing
	local from = args:find("!", 1, true)
	if not from then
		socket.write(fd, "ERROR invalid command line\n")
		error("Invalid command line")
	end
	local output_ext
	for t, hash, ext in args:sub(1, from-1):gmatch("(%u):(%w+)%.?([%w]*)") do
		if t == "I" then
			input = input or {}
			local fullpath = cache.upload_name(hash, ext)
			if not lfs.attributes(fullpath, "size") then
				missing = missing or {}
				table.insert(missing, hash)
			else
				table.insert(input, fullpath)
			end
		elseif t == "O" then
			output_ext = hash
		end
	end
	if not input or not output_ext then
		skynet.error("ERROR Need input")
		socket.write(fd, "ERROR Need input\n")
		return
	end
	if missing then
		skynet.error("MISSING input file")
		socket.write(fd, "MISSING " .. table.concat(missing, " ") .. "\n")
		return
	end
	local cl = args:sub(from+1)
	local tmp_download_noext = os.tmpname()
	local tmp_download = tmp_download_noext .. "." .. output_ext
	cl = string.format("%s %s -i %s -o %s", config.pvrtool, cl, table.concat(input, ","), tmp_download)
	skynet.error(cl)
	local ok = os.execute(cl)
	if not ok then
		remove(tmp_download_noext)
		remove(tmp_download)
		skynet.error("Call failed")
		socket.write(fd, "ERROR command run failed\n")
		return
	end
	local ok, err = lfs.link(tmp_download, download_name)
	remove(tmp_download_noext)
	remove(tmp_download)
	if not ok then
		socket.write(fd, "ERROR rename failed\n")
		error (err)
	end
	local f = io.open(cache.download_meta(download_hash), "wb")
	f:write(cl)
	f:close()
	skynet.error("Gen file : " .. download_hash)
	socket.write(fd, "OK " .. download_hash .. "\n")
end

local command = {}

function command.convert(fd, ...)
	socket.start(fd)
	local ok, err = xpcall(convert, debug.traceback, fd, ...)
	socket.abandon(fd)
	if ok then
		skynet.ret()
	else
		skynet.ret(skynet.pack(err))
	end
end

function command.init(cf)
	config = cf
	cache.init(cf.path)
	skynet.ret()
end

skynet.start(function()
	skynet.dispatch("lua", function(_,_, cmd, fd, ...)
		local f = assert(command[cmd])
		f(fd, ...)
	end)
end)
