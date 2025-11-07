--!optimize 2
--!strict

local Data = require(script.Data)
local t = require(script.t)
local t_assert = t.t_assert

local Converter = {
	data = Data.data,
	isSerializedItem = function(item: any)
		return Data.SerializedItemValidator(item)
	end,
}

export type Schema<T=any> = Data.Schema<T>
export type SerializedItem = Data.SerializedItem

function Converter.serialize<T>(schema: Schema<T>, value: T|any): (boolean, SerializedItem?, string?)
	t_assert("schema", schema, Data.SchemaValidator, "Schema")
	t_assert("value", value, schema.Validator, schema.Type)
	
	local len = 1
	local stype = type(schema.Size)
	if stype == "function" then
		len = (schema.Size :: any)(value)
	elseif stype == "number" then
		len = schema.Size :: number
	end
	
	local b = buffer.create(len)
	
	local ref = {buf = b}
	local success, result = pcall(schema.Write, ref, 0, value)
	
	if not success then
		return false, nil, result :: any
	end
	
	return true, ref
end

function Converter.deserialize<T>(schema: Schema<T>, serialized: SerializedItem): (boolean, T|any?, string?)
	t_assert("schema", schema, Data.SchemaValidator, "Schema")
	t_assert("serialized", serialized, Data.SerializedItemValidator, "SerializedItem")
	
	local success, result, _ = pcall(schema.Read, serialized, 0)
	
	if not success then
		return false, nil, result :: any
	end
	
	return true, result
end

return Converter