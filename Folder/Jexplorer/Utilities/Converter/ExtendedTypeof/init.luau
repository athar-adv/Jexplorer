local function isArray(t)
	if type(t) ~= "table" then
		return false
	end
	local len = #t
	if len == 0 then return false end

	return next(t, len) == nil
end

local function areValuesOfSameType(t, size)
	size = size or 1000

	if type(t) ~= "table" then
		return false
	end

	local firstKey, firstValue = next(t)
	if firstValue == nil then return false end

	local expectedType = typeof(firstValue)

	local value = firstValue
	local key = firstKey

	for i = 1, size do
		key, value = next(t, key)
		if value == nil then return true end
		if typeof(value) ~= expectedType then return false end
	end

	return true  -- In case table is huge
end

local function areKeysOfSameType(t, size, expectedType: string?)
	size = size or 1000

	if type(t) ~= "table" then
		return false
	end

	local firstKey = next(t)
	if firstKey == nil then return false end

	local expectedType = expectedType or typeof(firstKey)
	local key = firstKey

	for i = 1, size do
		key = next(t, key)
		if key == nil then return true end
		if typeof(key) ~= expectedType then return false end
	end

	return true  -- In case table is huge
end

-- Extended Typeof
local function extypeof(v)
	local t = typeof(v)
	if t ~= "table" then
		return t
	end
	if getmetatable(v) ~= nil then
		return "Class"
	end
	if isArray(v) then
		return "array"
	end
	if areValuesOfSameType(v) then
		return "map"
	else
		if areKeysOfSameType(v, nil, "string") then
			return "struct"
		elseif areKeysOfSameType(v, nil, "number") then
			return "tuple"
		else
			return "table"
		end
	end
end

return extypeof