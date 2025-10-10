--[[
	Jexplorer Datatype Format
]]

local HttpService = game:GetService('HttpService')

local Style = require(script.Parent.Style)
local Selector = require(script.Parent.Selector)

local JDF = {}

function JDF.to(input: any): string
	if typeof(input) == "Color3" then
		return `[rgb] {math.round(input.R*255)}, {math.round(input.G*255)}, {math.round(input.B*255)}`
	elseif typeof(input) == "string" then
		return input
	elseif typeof(input) == "EnumItem" then
		return `[enum.{tostring(input.EnumType)}] {input.Name}`
	elseif typeof(input) == "number" then
		return `[num] {input}`
	elseif typeof(input) == "boolean" then
		return `[bool] {input}`
	elseif typeof(input) == "Vector2" then
		return `[vec2] {input.X}, {input.Y}`
	elseif type(input) == "vector" then
		return `[vec3] {input.x}, {input.y}, {input.z}`
	elseif typeof(input) == "UDim2" then
		return `[udim2] {input.X.Scale}, {input.X.Offset}, {input.Y.Scale}, {input.Y.Offset}`
	elseif typeof(input) == "UDim" then
		return `[udim] {input.Scale}, {input.Offset}`
	elseif typeof(input) == "table" and input.__stylevar then
		return `[expr] {input.__expr}`
	elseif typeof(input) == "table" then
		return `[json] {HttpService:JSONEncode(input)}`
	end
	return ""
end

function JDF.from(input: string): any
	input = input:gsub("%s", "")
	local datatype = input:match("%b[]")
	
	-- Is a normal string
	if not datatype then
		return input
	end
	input = input:sub(#datatype + 1)
	datatype = datatype:sub(2, #datatype - 1)
	
	if datatype == "rgb" then
		local values = string.split(input, ",")
		return Color3.fromRGB(
			tonumber(values[1]),
			tonumber(values[2]),
			tonumber(values[3])
		)
	elseif datatype == "hex" then
		return Color3.fromHex(input)
	elseif datatype:match("enum.") then
		datatype = datatype:sub(6)
		local success, enum = pcall(function()
			return Enum[datatype]
		end)
		if not success then
			warn(`[{datatype}] is not a valid enum.`)
			return
		end
		
		local item = enum:FromName(input)
		if not item then
			warn(`'{input}' is not a valid member of 'Enum.{datatype}'`)
			return
		end
		
		return item
	elseif datatype == "num" then
		return tonumber(input)
	elseif datatype == "bool" then
		return input == "true"
	elseif datatype == "vec2" then
		local values = string.split(input, ",")
		return Vector2.new(
			tonumber(values[1]),
			tonumber(values[2])
		)
	elseif datatype == "udim2" then
		local values = string.split(input, ",")
		
		return UDim2.new(
			tonumber(values[1]), 
			tonumber(values[2]),
			tonumber(values[3]), 
			tonumber(values[4])
		)
	elseif datatype == "udim" then
		local values = string.split(input, ",")
		return UDim.new(
			tonumber(values[1]),
			tonumber(values[2])
		)
	elseif datatype == "vec3" then
		local values = string.split(input, ",")
		return vector.create(
			tonumber(values[1]),
			tonumber(values[2]),
			tonumber(values[3])
		)
	elseif datatype == "expr" then
		return Style.var(input)
	elseif datatype == "json" then
		return HttpService:JSONDecode(input)
	elseif datatype == "selector" then
		local value = Selector.parseSelectorMacro(input)
		assert(value, `'{input}' is not a valid selector macro`)
		
		return value
	else
		warn(`[{datatype}] is not a valid datatype for styles.`)
	end
end

return JDF