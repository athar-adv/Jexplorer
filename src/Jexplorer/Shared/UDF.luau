--!strict
--[[
	Universal Datatype Format
]]

local HttpService = game:GetService('HttpService')

local Style = require(script.Parent.Style)
local Selector = require(script.Parent.Small.Selector)

local UDF = {}

function UDF.to(input: any): string
	if typeof(input) == "Color3" then
		return `[rgb] {math.round(input.R*255)}, {math.round(input.G*255)}, {math.round(input.B*255)}`
	elseif typeof(input) == "string" then
		return `[str] {input}`
	elseif typeof(input) == "EnumItem" then
		return `[enum.{tostring(input.EnumType)}] {input.Name}`
	elseif typeof(input) == "number" then
		return `[num] {input}`
	elseif typeof(input) == "boolean" then
		return `[bool] {input}`
	elseif typeof(input) == "Vector2" then
		return `[vec2] {input.X}, {input.Y}`
	elseif type(input) == "vector" then
		return `[vec3] {input.X}, {input.Y}, {input.Z}`
	elseif typeof(input) == "UDim2" then
		return `[udim2] {input.X.Scale}, {input.X.Offset}, {input.Y.Scale}, {input.Y.Offset}`
	elseif typeof(input) == "UDim" then
		return `[udim] {input.Scale}, {input.Offset}`
	elseif typeof(input) == "table" and input.__stylevar then
		return `[expr] {input.__expr}`
	elseif typeof(input) == "table" then
		return `[json] {HttpService:JSONEncode(input)}`
	elseif typeof(input) == "Font" then
		local input: Font = input
		return `[font_asset] {input.Weight.Name} {input.Style.Name} {input.Family}`
	elseif typeof(input) == "Content" then
		if input.Uri then
			return `[content_uri] {input.Uri}`
		else
			error("cannot use object as content for udf")
		end
	elseif typeof(input) == "Region3" then
		local min = input.CFrame.Position - input.Size / 2
		local max = input.CFrame.Position + input.Size / 2
		return `[region3] {min.X}, {min.Y}, {min.Z}, {max.X}, {max.Y}, {max.Z}`
	elseif typeof(input) == "Ray" then
		return `[ray] {input.Origin.X}, {input.Origin.Y}, {input.Origin.Z}, {input.Direction.X}, {input.Direction.Y}, {input.Direction.Z}`
	end
	return "[nil]"
end

function UDF.from(input: string): any
	if input == "" then return "" end
	-- Truncate leading whitespace
	input = input:match("^%s*(.*)") or input

	-- Check if input starts with a shorthand punctuation
	local shorthand = input:sub(1, 1)

	if shorthand:match("%p") then
		local val = input:sub(2)
		if shorthand == "%" then
			return val -- String
		elseif shorthand == "#" then
			return tonumber(val) -- Number
		elseif shorthand == "?" then
			return val == "true" -- boolean
		elseif shorthand == "$" then
			return Style.var(val) -- JSLExpression
		elseif shorthand == "@" then
			-- Selector macro
			local value = Selector.parseSelectorMacro(val)
			assert(value, `'{val}' is not a valid selector macro`)
			return value
		end
	end

	-- Check if input starts with [DATATYPE] format
	local datatype = input:match("^%b[]")
	if datatype == "[nil]" then return "" end
	
	if not datatype then 
		error(`UDFValue '{input}' must start with [DATATYPE] tag or shorthand punctuation`)
	end

	-- Remove whitespace from datatype tag
	datatype = datatype:gsub("%s", "")

	-- Extract the value after the datatype tag and truncate leading whitespace
	input = input:sub(#datatype + 1)
	input = input:match("^%s*(.*)") or input

	-- Remove the brackets from datatype
	datatype = datatype:sub(2, #datatype - 1)

	if datatype == "str" then
		return input
	elseif datatype == "rgb" then
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

		local item = (enum::any):FromName(input)
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
			tonumber(values[1])::number,
			tonumber(values[2])::number,
			tonumber(values[3])::number
		)
	elseif datatype == "expr" then
		return Style.var(input)
	elseif datatype == "json" then
		return HttpService:JSONDecode(input)
	elseif datatype == "selector" then
		local value = Selector.parseSelectorMacro(input)
		assert(value, `'{input}' is not a valid selector macro`)

		return value
	elseif datatype == "font_asset" then
		local values = string.split(input, " ")
		if #values < 3 then
			return Font.fromEnum(Enum.Font.SourceSans)
		end
		return Font.new(values[3], Enum.FontWeight:FromName(values[1]), Enum.FontStyle:FromName(values[2]))
	elseif datatype == "font_enum" then
		return Font.fromEnum(
			assert(Enum.Font:FromName(input))
		)
	elseif datatype == "content_asset" then
		return Content.fromAssetId(
			assert(tonumber(input))
		)
	elseif datatype == "content_uri" then
		return Content.fromUri(input)
	elseif datatype == "region3" then
		local values = string.split(input, ",")
		local min = Vector3.new(
			tonumber(values[1]),
			tonumber(values[2]),
			tonumber(values[3])
		)
		local max = Vector3.new(
			tonumber(values[4]),
			tonumber(values[5]),
			tonumber(values[6])
		)
		return Region3.new(min, max)
	elseif datatype == "ray" then
		local values = string.split(input, ",")
		local origin = Vector3.new(
			tonumber(values[1]),
			tonumber(values[2]),
			tonumber(values[3])
		)
		local direction = Vector3.new(
			tonumber(values[4]),
			tonumber(values[5]),
			tonumber(values[6])
		)
		return Ray.new(origin, direction)
	else
		error(`[{datatype}] is not a valid datatype tag.`)
	end
end

return UDF