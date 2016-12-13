local lsocket = require "lsocket"
local md5 = require "md5"

local addr = "cookie.ejoy"
local port = 8964
local local_tool = "PVRTexToolCLI.exe"

----- block socket

local block_socket = {}; block_socket.__index = block_socket

function block_socket.new(addr, port, timeout)
	local fd = assert(lsocket.connect(addr, port))
	local fd_set = {fd}
	local rd,wt = lsocket.select(nil, fd_set, timeout)
	if not rd then
		fd:close()
		if wt == nil then
			error "timeout"
		else
			error(wt)
		end
	end
	assert(fd_set[1])
	local so = {
		_fd = fd_set,
		_rdbuf = nil,
		_rdoff = 0,
	}
	return setmetatable(so, block_socket)
end

local function reading(self, sz)
	local fd = assert(self._fd[1], "closed")
	local ok, err = lsocket.select({fd})
	if ok == false then
		return ""
	end
	assert(ok, err)
	local bytes,err = fd:recv(sz)
	if bytes == nil then
		fd:close()
		if err then
			error(err)
		end
	end
	return bytes
end

function block_socket:readline()
	local rd = self._rdbuf
	local offset = self._rdoff or 1
	while true do
		if rd then
			local from = rd:find("\n", offset, true)
			if from then
				local result = rd:sub(offset,from-1)
				self._rdoff = from + 1
				return result
			end
		end
		local bytes = reading(self)
		if bytes == nil then
			return rd
		end
		if bytes then
			if rd then
				rd = rd:sub(offset) .. bytes
				self._rdoff = 1
				offset = 1
			else
				rd = bytes
			end
			self._rdbuf = rd
		end
	end
end

function block_socket:read(size)
	local rd = self._rdbuf
	local offset = self._rdoff or 1
	while true do
		local sz = 0
		if rd then
			sz = #rd - offset + 1
			if sz >= size then
				local result = rd:sub(offset, offset + size - 1)
				self._rdoff = offset + size
				return result
			end
		end
		local bytes = reading(self, size - sz)
		if bytes == nil then
			error "disconnect"
		end
		if bytes then
			if rd then
				rd = rd:sub(offset) .. bytes
				self._rdoff = 1
				offset = 1
			else
				rd = bytes
			end
			self._rdbuf = rd
		end
	end
end

function block_socket:write(str)
	local fd = assert(self._fd[1], "closed")
	local total = #str
	while total > 0 do
		local rd,wt = lsocket.select(nil, self._fd)
		if rd == nil then
			fd:close()
			error(wt)
		end
		if rd then
			local bytes = assert(fd:send(str))
			str = str:sub(bytes+1)
			total = total - bytes
		end
	end
end

function block_socket:close()
	local fd = self._fd[1]
	if fd then
		fd:close()
		self._fd[1] = nil
	end
end

------------------------------

local function push_file(filename)
	local name, ext = filename:match("(.*)%.(%w+)$")
	local f = assert(io.open(filename, "rb"))
	local data = f:read "a"
	f:close()

	local fd = block_socket.new(addr, port, 1)
	local hash = md5(data)
	fd:write(string.format("PUT %d %s.%s\n",#data,hash,ext))
	local result = fd:readline()
	if result == "OK" then
		print("Upload", filename)
		fd:write(data)
		result = fd:readline()
		if result ~= "OK" then
			error(result)
		end
	elseif result == "EXIST" then
		print("Exist", filename)
	else
		error(result)
	end
	fd:close()
	return hash .. "." .. ext
end

local ok, err = pcall(push_file, (...))

if not ok then
	print(err)
	if not ok then
		os.exit(1)
	end
end
