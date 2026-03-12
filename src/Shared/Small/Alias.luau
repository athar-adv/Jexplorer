return function<T>(tbl: T, name: string): T
	return setmetatable(tbl, {
		__tostring = function()
			return name
		end,
	})
end