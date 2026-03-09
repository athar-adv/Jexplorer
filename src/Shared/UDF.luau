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

local function evalMathExpression(expr: string): number
	local trimmed = expr:match("^%s*(.-)%s*$")
	assert(trimmed)

	-- Fast path: plain integer  (optional leading minus, digits only)
	do
		local n = trimmed:match("^%-?%d+$")
		if n then return tonumber(n) :: number end
	end

	-- Fast path: plain decimal  (optional leading minus, digits with ONE dot)
	do
		local n = trimmed:match("^%-?%d*%.%d+$") or trimmed:match("^%-?%d+%.%d*$")
		if n then return tonumber(n) :: number end
	end

	-- Fast path: hex literal    0x / 0X prefix, optional leading minus
	do
		local sign, digits = trimmed:match("^(%-?)0[xX]([%x]+)$")
		if digits then
			local value = tonumber(digits, 16) :: number
			return (sign == "-") and -value or value
		end
	end

	-- Fast path: binary literal  0b / 0B prefix, optional leading minus
	do
		local sign, digits = trimmed:match("^(%-?)0[bB]([01]+)$")
		if digits then
			local value = 0
			for i = 1, #digits do
				value = value * 2 + (digits:sub(i, i) == "1" and 1 or 0)
			end
			return (sign == "-") and -value or value
		end
	end

	-- ── Full recursive-descent parser ─────────────────────────────────────────
	local pos = 1
	local s = expr:gsub("%s+", "") -- strip all whitespace

	local function peek(): string?
		return s:sub(pos, pos) ~= "" and s:sub(pos, pos) or nil
	end

	local function consume(n: number?): string
		local chunk = s:sub(pos, pos + (n or 1) - 1)
		pos += (n or 1)
		return chunk
	end

	local parseExpr -- forward declaration

	-- Parses one numeric literal at the current position.
	-- Handles: hex (0x…), binary (0b…), plain integer/decimal.
	local function parseNumber(): number
		-- Hex: 0x…
		if s:sub(pos, pos + 1):lower() == "0x" then
			pos += 2
			local start = pos
			while s:sub(pos, pos):match("[%x]") do pos += 1 end
			local digits = s:sub(start, pos - 1)
			assert(#digits > 0, "Empty hex literal")
			return tonumber(digits, 16) :: number
		end

		-- Binary: 0b…
		if s:sub(pos, pos + 1):lower() == "0b" then
			pos += 2
			local start = pos
			while s:sub(pos, pos):match("[01]") do pos += 1 end
			local digits = s:sub(start, pos - 1)
			assert(#digits > 0, "Empty binary literal")
			local value = 0
			for i = 1, #digits do
				value = value * 2 + (digits:sub(i, i) == "1" and 1 or 0)
			end
			return value
		end

		-- Plain integer / decimal
		local start = pos
		while s:sub(pos, pos):match("[%d%.]") do pos += 1 end
		local numStr = s:sub(start, pos - 1)
		local n = tonumber(numStr)
		assert(n, "Invalid number: '" .. numStr .. "'")
		return n :: number
	end

	local function parsePrimary(): number
		local ch = peek()
		assert(ch, "Unexpected end of expression")

		if ch == "(" then
			consume()                               -- '('
			local val = parseExpr()
			assert(peek() == ")", "Expected closing ')'")
			consume()                               -- ')'
			return val
		elseif ch == "-" then
			consume()                               -- unary minus
			return -parsePrimary()
		elseif ch == "+" then
			consume()                               -- unary plus (no-op)
			return parsePrimary()
		else
			return parseNumber()
		end
	end

	-- Power (right-associative): 2^2^3 = 2^(2^3) = 256
	local function parsePower(): number
		local base = parsePrimary()
		if peek() == "^" then
			consume()
			return base ^ parsePower()
		end
		return base
	end

	-- *, /, %
	local function parseTerm(): number
		local left = parsePower()
		while true do
			local ch = peek()
			if ch == "*" then
				consume(); left = left * parsePower()
			elseif ch == "/" then
				consume()
				local divisor = parsePower()
				assert(divisor ~= 0, "Division by zero")
				left = left / divisor
			elseif ch == "%" then
				consume(); left = left % parsePower()
			else
				break
			end
		end
		return left
	end

	-- +, -
	parseExpr = function(): number
		local left = parseTerm()
		while true do
			local ch = peek()
			if ch == "+" then
				consume(); left = left + parseTerm()
			elseif ch == "-" then
				consume(); left = left - parseTerm()
			else
				break
			end
		end
		return left
	end

	local result = parseExpr()
	assert(pos > #s,
		"Unexpected token at position " .. pos .. ": '" .. s:sub(pos) .. "'")
	return result
end

local tonumber = evalMathExpression
function UDF.from(input: string, expectedType: string?): any
	if input == "" then return "" end
	-- Truncate leading whitespace
	input = input:match("^%s*(.*)") or input

	local function checkType(got: string)
		if expectedType and expectedType ~= got then
			error(`Expected '{expectedType}', got '{got}'`)
		end
	end

	-- Check if input starts with a shorthand punctuation
	local shorthand = input:sub(1, 1)

	if shorthand:match("%p") then
		local val = input:sub(2)
		if shorthand == "%" then
			checkType("string")
			return val
		elseif shorthand == "#" then
			checkType("number")
			return tonumber(val)
		elseif shorthand == "?" then
			checkType("boolean")
			return val == "true"
		elseif shorthand == "$" then
			checkType("Expression")
			return Style.var(val)
		elseif shorthand == "@" then
			checkType("selector")
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
		checkType("string")
		return input
	elseif datatype == "rgb" then
		checkType("Color3")
		local values = string.split(input, ",")
		return Color3.fromRGB(
			tonumber(values[1]),
			tonumber(values[2]),
			tonumber(values[3])
		)
	elseif datatype == "hex" then
		checkType("Color3")
		return Color3.fromHex(input)
	elseif datatype:match("^enum%.") then
		local enumName = datatype:sub(6)
		checkType(`Enum.{enumName}`)
		local success, enum = pcall(function()
			return Enum[enumName]
		end)
		if not success then
			warn(`[{enumName}] is not a valid enum.`)
			return
		end

		local item = (enum :: any):FromName(input)
		if not item then
			warn(`'{input}' is not a valid member of 'Enum.{enumName}'`)
			return
		end

		return item
	elseif datatype == "num" then
		checkType("number")
		return tonumber(input)
	elseif datatype == "bool" then
		checkType("boolean")
		return input == "true"
	elseif datatype == "vec2" then
		checkType("Vector2")
		local values = string.split(input, ",")
		return Vector2.new(
			tonumber(values[1]),
			tonumber(values[2])
		)
	elseif datatype == "udim2" then
		checkType("UDim2")
		local values = string.split(input, ",")
		return UDim2.new(
			tonumber(values[1]),
			tonumber(values[2]),
			tonumber(values[3]),
			tonumber(values[4])
		)
	elseif datatype == "udim" then
		checkType("UDim")
		local values = string.split(input, ",")
		return UDim.new(
			tonumber(values[1]),
			tonumber(values[2])
		)
	elseif datatype == "vec3" then
		checkType("Vector3")
		local values = string.split(input, ",")
		return vector.create(
			tonumber(values[1]) :: number,
			tonumber(values[2]) :: number,
			tonumber(values[3]) :: number
		)
	elseif datatype == "expr" then
		checkType("Expression")
		return Style.var(input)
	elseif datatype == "json" then
		checkType("table")
		return HttpService:JSONDecode(input)
	elseif datatype == "selector" then
		checkType("selector")
		local value = Selector.parseSelectorMacro(input)
		assert(value, `'{input}' is not a valid selector macro`)
		return value
	elseif datatype == "slctr" then
		checkType("string")
		local processed = input:gsub("(@[^(]+%b())", function(macro)
			local expanded, kind = Selector.parseSelectorMacro(macro)
			assert(expanded and kind ~= "none", `'{macro}' is not a valid selector macro`)
			return expanded
		end)

		assert(#processed > 0, `[slctr] value '{input}' produced an empty selector`)
		return processed
	elseif datatype == "font_asset" then
		checkType("Font")
		local values = string.split(input, " ")
		if #values < 3 then
			return Font.fromEnum(Enum.Font.SourceSans)
		end
		return Font.new(values[3], Enum.FontWeight:FromName(values[1]), Enum.FontStyle:FromName(values[2]))
	elseif datatype == "font" then
		checkType("Font")
		local values = string.split(input, " ")
		if #values < 3 then
			return Font.fromEnum(Enum.Font.SourceSans)
		end
		return Font.fromName(values[3], Enum.FontWeight:FromName(values[1]), Enum.FontStyle:FromName(values[2]))
	elseif datatype == "font_enum" then
		checkType("Font")
		return Font.fromEnum(
			assert(Enum.Font:FromName(input))
		)
	elseif datatype == "content_asset" then
		checkType("Content")
		return Content.fromAssetId(
			assert(tonumber(input))
		)
	elseif datatype == "content_uri" then
		checkType("Content")
		return Content.fromUri(input)
	elseif datatype == "region3" then
		checkType("Region3")
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
		checkType("Ray")
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
	elseif datatype == "inst" then
		checkType("Instance")
		local values = string.split(input, "/")
		local current = game
		for _, part in values do
			current = current[part]
			if not current then
				error(`Path '{input}' cannot be parsed fully: Instance '{current.Name}' does not have property '{part}'`)
			end
		end
		return current
	else
		error(`[{datatype}] is not a valid datatype tag.`)
	end
end

return UDF