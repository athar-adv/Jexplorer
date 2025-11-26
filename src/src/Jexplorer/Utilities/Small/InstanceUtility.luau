local _, newindex: (Instance, string, ...any) -> () = xpcall(function()
	game[""] = nil
end, function()
	return debug.info(2, "f")
end)
local _, index: (Instance, string) -> ...any = xpcall(function()
	local b = game[""]
end, function()
	return debug.info(2, "f")
end)

return {
	index = function(self, k)
		if typeof(self) == "Instance" then
			return index(self, k)
		end
		return self[k]
	end,
	newindex = function(self, k, v)
		if typeof(self) == "Instance" then
			newindex(self, k, v)
			return
		end
		self[k] = v
	end,
	
	rawindex = index,
	rawnewindex = newindex
}