local lfs = require "lfs"
local cachefile = {}

local path

local function pathname(name)
	local p = path .. name:sub(1,3)
	if not lfs.attributes(p, "mode") then
		lfs.mkdir(p)
	end
	return p .. "/" .. name
end

function cachefile.upload_name(name, ext)
	return pathname(name) .. ".upload." .. ext
end

function cachefile.download_meta(name)
	return pathname(name) .. ".meta"
end

function cachefile.download_name(name)
	return pathname(name) .. ".download"
end

function cachefile.init(config)
	path = config
end

return cachefile
