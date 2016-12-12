local lsocket = require "lsocket"
local md5 = require "md5"

local addr = "127.0.0.1"
local port = 8964

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

------------args -------------

local function args_group(...)
	local args = table.pack(...)
	local key
	local result = {}
	for i = 1, args.n do
		local opt = args[i]
		if opt:byte() == 45 then	-- '-'
			key = opt
			if result[key] == nil then
				result[key] = {}
			else
				table.insert(result[key], opt)
			end
		else
			assert(key ~= nil)
			table.insert(result[key], opt)
		end
	end
	return result
end

------------------------------

local function strip_space(s)
	return s:match("[%s,]*(.*)[%s,]*$")
end

local function get_ext(s)
	return assert(s:match("%.(%w+)$"))
end

local function args_input(input)
	local result = {}
	for _, v in ipairs(input) do
		v = strip_space(v)
		if v ~= "-i" then
			for name in v:gmatch("[^,]+") do
				table.insert(result, name)
			end
		end
	end
	return result
end

local function sort_args(args)
	local keys = {}
	for k in pairs(args) do
		table.insert(keys, k)
	end
	table.sort(keys)
	local result = {}
	for _, key in ipairs(keys) do
		table.insert(result, key)
		local value = args[key]
		for _, v in ipairs(value) do
			v = v:gsub('"' , '\\"')
			if v:find "%s" then
				table.insert(result, '"' .. v .. '"')
			else
				table.insert(result, v)
			end
		end
	end
	return table.concat(result, " ")
end

local function request_convert(input, output, cl)
	local fd = block_socket.new(addr, port , 1)
	fd:write(string.format("TEX %s O:%s !%s\n",
		table.concat(input, " "),
		output,
		cl))
	local result = fd:readline()
	fd:close()
	return result
end

local function hash_input(filename)
	local name, ext = filename:match("([%da-f]+)%.upload%.(%w+)")
	return name .. "." .. ext
end

local function meta_info(filename)
	local f = assert(io.open(filename,"rb"))
	local meta = f:read "l"
	f:close()
	meta = meta:match("%s+(.*)$")
	local args = {}
	for arg in meta:gmatch("%S+") do	-- todo: quote args
		table.insert(args, arg)
	end
	return args_group(table.unpack(args))
end

local meta_filename = (...)
local format_list = {}

for _, v in ipairs({select(2, ...)}) do
	format_list[v] = true
end

local args = meta_info(meta_filename)

local function main()
	local input = args_input(args["-i"])
	local output = strip_space(args["-o"][1])

	args["-i"] = nil
	args["-o"] = nil

	for idx , name in ipairs(input) do
		input[idx] = "I:" .. hash_input(name)
	end

	local f = args["-f"][1]

	if not format_list[f] then
		print("Format not in list", f)
		return
	end

	format_list[f] = nil

	for fm in pairs(format_list) do
		args["-f"][1] = fm
		local cl = sort_args(args)
		print("Command Line:", cl)
		print("Result:", request_convert(input, get_ext(output), cl))
	end

end

local ok, err = pcall(main)

if not ok then
	print(err)
	os.exit(1)
end
