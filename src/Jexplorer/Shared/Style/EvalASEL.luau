local supportedTypes = {
	Color3 = true,
	Vector2 = true,
	Vector3 = true,
	UDim2 = true,
	UDim = true,
	number = true,
	boolean = true,
	["nil"] = true,
}

local constants = {
	pi = math.pi,
	tau = math.pi * 2,
	inf = math.huge,
	["math.pi"] = math.pi,
	["math.huge"] = math.huge,
	["true"] = true,
	["false"] = false,
}

-- Component-wise min for compound types
local function componentMin(a, b)
	local t = typeof(a)

	if t == "UDim" then
		return UDim.new(math.min(a.Scale, b.Scale), math.min(a.Offset, b.Offset))
	elseif t == "UDim2" then
		return UDim2.new(
			math.min(a.X.Scale, b.X.Scale), math.min(a.X.Offset, b.X.Offset),
			math.min(a.Y.Scale, b.Y.Scale), math.min(a.Y.Offset, b.Y.Offset)
		)
	elseif t == "Vector2" then
		return Vector2.new(math.min(a.X, b.X), math.min(a.Y, b.Y))
	elseif t == "Vector3" then
		return Vector3.new(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
	elseif t == "Color3" then
		return Color3.new(math.min(a.R, b.R), math.min(a.G, b.G), math.min(a.B, b.B))
	elseif t == "NumberRange" then
		return NumberRange.new(math.min(a.Min, b.Min), math.min(a.Max, b.Max))
	elseif t == "Rect" then
		return Rect.new(
			math.min(a.Min.X, b.Min.X), math.min(a.Min.Y, b.Min.Y),
			math.min(a.Max.X, b.Max.X), math.min(a.Max.Y, b.Max.Y)
		)
	end

	return a
end

-- Component-wise max for compound types
local function componentMax(a, b)
	local t = typeof(a)

	if t == "UDim" then
		return UDim.new(math.max(a.Scale, b.Scale), math.max(a.Offset, b.Offset))
	elseif t == "UDim2" then
		return UDim2.new(
			math.max(a.X.Scale, b.X.Scale), math.max(a.X.Offset, b.X.Offset),
			math.max(a.Y.Scale, b.Y.Scale), math.max(a.Y.Offset, b.Y.Offset)
		)
	elseif t == "Vector2" then
		return Vector2.new(math.max(a.X, b.X), math.max(a.Y, b.Y))
	elseif t == "Vector3" then
		return Vector3.new(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
	elseif t == "Color3" then
		return Color3.new(math.max(a.R, b.R), math.max(a.G, b.G), math.max(a.B, b.B))
	elseif t == "NumberRange" then
		return NumberRange.new(math.max(a.Min, b.Min), math.max(a.Max, b.Max))
	elseif t == "Rect" then
		return Rect.new(
			math.max(a.Min.X, b.Min.X), math.max(a.Min.Y, b.Min.Y),
			math.max(a.Max.X, b.Max.X), math.max(a.Max.Y, b.Max.Y)
		)
	end

	return a
end

local function universalmin(values: {any})
	local first = type(values[1])
	if first == "number" then
		return math.min(unpack(values))
	elseif first == "vector" then
		return vector.min(unpack(values))
	else
		-- Check if it's a compound numeric type
		local firstType = typeof(values[1])
		if firstType == "UDim" or firstType == "UDim2" or firstType == "Vector2" 
			or firstType == "Vector3" or firstType == "Color3" or firstType == "NumberRange" 
			or firstType == "Rect" then

			local result = values[1]
			for i = 2, #values do
				result = componentMin(result, values[i])
			end
			return result
		else
			-- Fallback for comparable types
			local least
			for i, v in values do
				if not least or v < least then
					least = v
				end
			end
			return least
		end
	end
end

local function universalmax(values: {any})
	local first = type(values[1])
	if first == "number" then
		return math.max(unpack(values))
	elseif first == "vector" then
		return vector.max(unpack(values))
	else
		-- Check if it's a compound numeric type
		local firstType = typeof(values[1])
		if firstType == "UDim" or firstType == "UDim2" or firstType == "Vector2" 
			or firstType == "Vector3" or firstType == "Color3" or firstType == "NumberRange" 
			or firstType == "Rect" then

			local result = values[1]
			for i = 2, #values do
				result = componentMax(result, values[i])
			end
			return result
		else
			-- Fallback for comparable types
			local greatest
			for i, v in values do
				if not greatest or v > greatest then
					greatest = v
				end
			end
			return greatest
		end
	end
end

local function coloradd(a: Color3, b: Color3)
	return universalmax({Color3.fromRGB(0, 0, 0), universalmin({Color3.fromRGB(255, 255, 255), Color3.new(a.R + b.R, a.G + b.G, a.B + b.B)})})
end

local function colorsub(a: Color3, b: Color3)
	return universalmax({Color3.fromRGB(0, 0, 0), universalmin({Color3.fromRGB(255, 255, 255), Color3.new(a.R - b.R, a.G - b.G, a.B - b.B)})})
end

local function getType(v)
	local t = typeof(v)
	if supportedTypes[t] then return t else error(`unsupported type '{t}' ; '{v}'`) end
end

local function typeAdd(a, b)
	local ta, tb = getType(a), getType(b)
	if ta == "number" and tb == "number" then return a + b end
	if ta == "Color3" and tb == "Color3" then
		return coloradd(a, b)
	end
	if ta == "Vector2" and tb == "Vector2" then return a + b end
	if ta == "Vector3" and tb == "Vector3" then return a + b end
	if ta == "UDim2" and tb == "UDim2" then return a + b end
	if ta == "UDim" and tb == "UDim" then return a + b end
	error("Cannot add " .. ta .. " and " .. tb)
end

local function typeSub(a, b)
	local ta, tb = getType(a), getType(b)
	if ta == "number" and tb == "number" then return a - b end
	if ta == "Color3" and tb == "Color3" then
		return colorsub(a, b)
	end
	if ta == "Vector2" and tb == "Vector2" then return a - b end
	if ta == "Vector3" and tb == "Vector3" then return a - b end
	if ta == "UDim2" and tb == "UDim2" then return a - b end
	if ta == "UDim" and tb == "UDim" then return a - b end
	error("Cannot subtract " .. ta .. " and " .. tb)
end

local function typeMul(a, b)
	if typeof(a) == "number" then
		if typeof(b) == "number" then return a * b end
		if supportedTypes[typeof(b)] then return b * a end
	elseif typeof(b) == "number" then
		if supportedTypes[typeof(a)] then return a * b end
	end
	error("Cannot multiply " .. typeof(a) .. " and " .. typeof(b))
end

local function typeDiv(a, b)
	if typeof(a) == "number" then
		if typeof(b) == "number" then return a / b end
		if supportedTypes[typeof(b)] then return b / a end
	elseif typeof(b) == "number" then
		if supportedTypes[typeof(a)] then return a / b end
	end
	error("Cannot divide " .. typeof(a) .. " and " .. typeof(b))
end

local function typeNegate(a)
	local ta = getType(a)
	if ta == "number" then return -a
		elseif ta == "Color3" then return Color3.new(-a.R, -a.G, -a.B)
		elseif ta == "Vector2" then return -a
		elseif ta == "Vector3" then return -a
		elseif ta == "UDim2" then return -a 
		elseif ta == "UDim" then return -a
	end
	error("Cannot negate " .. ta)
end

local function typeCmp(a, b, op)
	if op == "==" then return a == b
	elseif op == "~=" or op == "!=" then return a ~= b
	elseif typeof(a) == "number" and typeof(b) == "number" then
		if op == "<" then return a < b
			elseif op == "<=" then return a <= b
			elseif op == ">" then return a > b
			elseif op == ">=" then return a >= b
		end
	end
	error(`Cannot compare {typeof(a)} and {typeof(b)} with {op}`)
end

local function toBool(val)
	if typeof(val) == "boolean" then return val end
	if typeof(val) == "number" then return val ~= 0 end
	return val ~= nil
end

local function getColorBrightness(color)
	if typeof(color) ~= "Color3" then
		error("Cannot get brightness of non-Color3 value")
	end
	-- Use luminance formula: 0.299*R + 0.587*G + 0.114*B (scaled to 0-1)
	return (0.299 * color.R + 0.587 * color.G + 0.114 * color.B)
end

local function valueToString(val)
	local t = typeof(val)
	if t == "string" then return val
	elseif t == "number" then return tostring(val)
	elseif t == "boolean" then return tostring(val)
	elseif t == "nil" then return "nil"
	elseif t == "Vector2" then return `{val.X}, {val.Y}`
	elseif t == "Vector3" then return `{val.X}, {val.Y}, {val.Z}`
	elseif t == "Color3" then return `{math.floor(val.R*255)}, {math.floor(val.G*255)}, {math.floor(val.B*255)}`
	elseif t == "UDim" then return `{val.Scale}, {val.Offset}`
	elseif t == "UDim2" then return `{val.X.Scale}, {val.X.Offset}, {val.Y.Scale}, {val.Y.Offset}`
	else return tostring(val)
	end
end

local aselFuncs = {} :: {[string]: (unpackArgs: (count: number) -> ...any) -> ...any}

function aselFuncs.vec2(args)
	return Vector2.new(args(3))
end

function aselFuncs.vec3(args)
	return Vector3.new(args(3))
end

function aselFuncs.rgb(args)
	return Color3.fromRGB(args(3))
end

function aselFuncs.invert(args)
	local color: Color3 = args(1)
	return Color3.new(1 - color.R, 1 - color.G, 1 - color.B)
end

function aselFuncs.hex(args)
	local v = args(1)
	return Color3.fromHex(v)
end

function aselFuncs.udim2(args)
	return UDim2.new(args(4))
end

function aselFuncs.udim(args)
	return UDim.new(args(2))
end

-- Component-wise abs for compound types
local function componentAbs(a)
	local t = typeof(a)

	if t == "UDim" then
		return UDim.new(math.abs(a.Scale), math.abs(a.Offset))
	elseif t == "UDim2" then
		return UDim2.new(
			math.abs(a.X.Scale), math.abs(a.X.Offset),
			math.abs(a.Y.Scale), math.abs(a.Y.Offset)
		)
	elseif t == "Vector2" then
		return Vector2.new(math.abs(a.X), math.abs(a.Y))
	elseif t == "Vector3" then
		return Vector3.new(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
	elseif t == "Color3" then
		return Color3.new(math.abs(a.R), math.abs(a.G), math.abs(a.B))
	elseif t == "NumberRange" then
		return NumberRange.new(math.abs(a.Min), math.abs(a.Max))
	elseif t == "Rect" then
		return Rect.new(
			math.abs(a.Min.X), math.abs(a.Min.Y),
			math.abs(a.Max.X), math.abs(a.Max.Y)
		)
	end

	return a
end

-- Component-wise floor for compound types
local function componentFloor(a)
	local t = typeof(a)

	if t == "UDim" then
		return UDim.new(math.floor(a.Scale), math.floor(a.Offset))
	elseif t == "UDim2" then
		return UDim2.new(
			math.floor(a.X.Scale), math.floor(a.X.Offset),
			math.floor(a.Y.Scale), math.floor(a.Y.Offset)
		)
	elseif t == "Vector2" then
		return Vector2.new(math.floor(a.X), math.floor(a.Y))
	elseif t == "Vector3" then
		return Vector3.new(math.floor(a.X), math.floor(a.Y), math.floor(a.Z))
	elseif t == "Color3" then
		return Color3.new(math.floor(a.R), math.floor(a.G), math.floor(a.B))
	elseif t == "NumberRange" then
		return NumberRange.new(math.floor(a.Min), math.floor(a.Max))
	elseif t == "Rect" then
		return Rect.new(
			math.floor(a.Min.X), math.floor(a.Min.Y),
			math.floor(a.Max.X), math.floor(a.Max.Y)
		)
	end

	return a
end

-- Component-wise ceil for compound types
local function componentCeil(a)
	local t = typeof(a)

	if t == "UDim" then
		return UDim.new(math.ceil(a.Scale), math.ceil(a.Offset))
	elseif t == "UDim2" then
		return UDim2.new(
			math.ceil(a.X.Scale), math.ceil(a.X.Offset),
			math.ceil(a.Y.Scale), math.ceil(a.Y.Offset)
		)
	elseif t == "Vector2" then
		return Vector2.new(math.ceil(a.X), math.ceil(a.Y))
	elseif t == "Vector3" then
		return Vector3.new(math.ceil(a.X), math.ceil(a.Y), math.ceil(a.Z))
	elseif t == "Color3" then
		return Color3.new(math.ceil(a.R), math.ceil(a.G), math.ceil(a.B))
	elseif t == "NumberRange" then
		return NumberRange.new(math.ceil(a.Min), math.ceil(a.Max))
	elseif t == "Rect" then
		return Rect.new(
			math.ceil(a.Min.X), math.ceil(a.Min.Y),
			math.ceil(a.Max.X), math.ceil(a.Max.Y)
		)
	end

	return a
end

-- Component-wise round for compound types
local function componentRound(a)
	local t = typeof(a)

	if t == "UDim" then
		return UDim.new(math.round(a.Scale), math.round(a.Offset))
	elseif t == "UDim2" then
		return UDim2.new(
			math.round(a.X.Scale), math.round(a.X.Offset),
			math.round(a.Y.Scale), math.round(a.Y.Offset)
		)
	elseif t == "Vector2" then
		return Vector2.new(math.round(a.X), math.round(a.Y))
	elseif t == "Vector3" then
		return Vector3.new(math.round(a.X), math.round(a.Y), math.round(a.Z))
	elseif t == "Color3" then
		return Color3.new(math.round(a.R), math.round(a.G), math.round(a.B))
	elseif t == "NumberRange" then
		return NumberRange.new(math.round(a.Min), math.round(a.Max))
	elseif t == "Rect" then
		return Rect.new(
			math.round(a.Min.X), math.round(a.Min.Y),
			math.round(a.Max.X), math.round(a.Max.Y)
		)
	end

	return a
end

function aselFuncs.min(args)
	return universalmin({args(-1)})
end

function aselFuncs.max(args)
	return universalmax({args(-1)})
end

function aselFuncs.abs(args)
	local value = args(1)
	local t = type(value)

	if t == "number" then
		return math.abs(value)
	else
		local valueType = typeof(value)
		if valueType == "UDim" or valueType == "UDim2" or valueType == "Vector2" 
			or valueType == "Vector3" or valueType == "Color3" or valueType == "NumberRange" 
			or valueType == "Rect" then
			return componentAbs(value)
		end
	end

	return value
end

function aselFuncs.floor(args)
	local value = args(1)
	local t = type(value)

	if t == "number" then
		return math.floor(value)
	else
		local valueType = typeof(value)
		if valueType == "UDim" or valueType == "UDim2" or valueType == "Vector2" 
			or valueType == "Vector3" or valueType == "Color3" or valueType == "NumberRange" 
			or valueType == "Rect" then
			return componentFloor(value)
		end
	end

	return value
end

function aselFuncs.ceil(args)
	local value = args(1)
	local t = type(value)

	if t == "number" then
		return math.ceil(value)
	else
		local valueType = typeof(value)
		if valueType == "UDim" or valueType == "UDim2" or valueType == "Vector2" 
			or valueType == "Vector3" or valueType == "Color3" or valueType == "NumberRange" 
			or valueType == "Rect" then
			return componentCeil(value)
		end
	end

	return value
end

function aselFuncs.round(args)
	local value = args(1)
	local t = type(value)

	if t == "number" then
		return math.round(value)
	else
		local valueType = typeof(value)
		if valueType == "UDim" or valueType == "UDim2" or valueType == "Vector2" 
			or valueType == "Vector3" or valueType == "Color3" or valueType == "NumberRange" 
			or valueType == "Rect" then
			return componentRound(value)
		end
	end

	return value
end

function aselFuncs.clamp(args)
	local x, min, max = args(3)
	return universalmax({min, universalmin({max, x})})
end

function aselFuncs.brightness(args)
	return getColorBrightness(args(1))
end

local function callFunc(name, args)
	local function unpackArgs(count)
		if count == -1 then
			return table.unpack(args)
		end
		if #args ~= count then error(name .. " expects " .. count .. " arguments") end
		return table.unpack(args, 1, count)
	end
	local fn = aselFuncs[name]
	assert(fn, `ASEL function '{name}' not found`)
	
	return fn(unpackArgs)
end

local function evaluateExpression(expr: string, tokens: { [string]: any }): any
	local pos = 1
	local parseExpr

	local function peek(n)
		n = n or 0
		return expr:sub(pos, pos + n)
	end
	local function nextChar() local c = peek(); pos += 1; return c end
	local function skipWhitespace() while peek():match("%s") do pos += 1 end end
	local function match(str) return expr:sub(pos, pos + #str - 1) == str end

	local function parseIdentifier()
		local start = pos
		while peek():match("[%w_]") do pos += 1 end
		return expr:sub(start, pos - 1)
	end

	local function parseArguments()
		assert(nextChar() == "(", "Expected (")
		local args = {}
		while true do
			skipWhitespace()
			if peek() == ")" then pos += 1; break end
			table.insert(args, parseExpr())
			skipWhitespace()
			if peek() == "," then pos += 1
			elseif peek() == ")" then pos += 1; break
			else error("Expected ',' or ')'") end
		end
		return args
	end

	local function parseVariable()
		pos += 1
		local name = parseIdentifier()
		local val = tokens[name]
		while type(val) == "table" and val.__stylevar do
			val = evaluateExpression(val.__expr, tokens)
		end
		--if val == nil then return NULL end
		return val
	end

	local function parseNumber()
		local start = pos
		while peek():match("[%d%.]") do pos += 1 end
		local val = tonumber(expr:sub(start, pos - 1))
		if not val then error("Invalid number") end
		return val
	end

	local function parseString()
		assert(nextChar() == "'", "Expected '")
		local result = ""
		while true do
			local ch = peek()
			if ch == "" then error("Unterminated string") end
			if ch == "'" then
				pos += 1
				break
			elseif ch == "\\" then
				pos += 1
				local escaped = peek()
				if escaped == "n" then result = result .. "\n"
				elseif escaped == "t" then result = result .. "\t"
				elseif escaped == "r" then result = result .. "\r"
				elseif escaped == "\\" then result = result .. "\\"
				elseif escaped == "'" then result = result .. "'"
				else result = result .. escaped end
				pos += 1
			elseif peek(1) == "![" then
				-- Interpolation syntax: ![$variable] or ![expression]
				pos += 2 -- Skip "!["
				local interpolatedValue = parseExpr()
				skipWhitespace()
				if peek() ~= "]" then error("Expected ']' to close interpolation") end
				pos += 1 -- Skip "]"
				result = result .. valueToString(interpolatedValue)
			else
				result = result .. ch
				pos += 1
			end
		end
		return result
	end

	local function parseValue()
		skipWhitespace()
		local ch = peek()
		if ch == "$" then return parseVariable()
		elseif ch == "'" then return parseString()
		elseif ch:match("%d") then return parseNumber()
		elseif ch:match("[%a_]") then
			local id = parseIdentifier()
			if peek() == "(" then
				local args = parseArguments()
				return callFunc(id, args)
			end
			return if id == "nil" then nil else constants[id] or error("Unknown identifier: " .. id)
		elseif ch == "(" then
			pos += 1
			local v = parseExpr()
			skipWhitespace()
			assert(peek() == ")", "Expected ')'")
			pos += 1
			return v
		else error("Unexpected character: " .. ch)
		end
	end

	local function parseFactor()
		skipWhitespace()

		-- Handle unary minus operator
		if peek() == "-" then
			pos += 1
			local v = parseFactor() -- Recursively parse the factor to negate
			return typeNegate(v)
		elseif peek() == "!" and peek(1) ~= "[" then
			-- Only treat ! as NOT operator if not followed by [
			pos += 1
			local v = parseFactor()
			return not v
		end

		local v = parseValue()
		while peek() == "." do
			pos += 1
			local key = parseIdentifier()
			if v == nil then break end
			v = v[key]
		end
		return v
	end

	local function parseTerm()
		local left = parseFactor()
		while true do
			skipWhitespace()
			local op = peek()
			if op == "*" or op == "/" then
				pos += 1
				local right = parseFactor()
				left = (op == "*") and typeMul(left, right) or typeDiv(left, right)
			else break end
		end
		return left
	end

	local function parseArithmetic()
		local left = parseTerm()
		while true do
			skipWhitespace()
			local op = peek()
			if op == "+" or op == "-" then
				pos += 1
				local right = parseTerm()
				left = (op == "+") and typeAdd(left, right) or typeSub(left, right)
			else break end
		end
		return left
	end

	local function parseComparison()
		local left = parseArithmetic()
		while true do
			skipWhitespace()
			local op
			if match("==") then op = "=="; pos += 2
			elseif match("~=") then op = "~="; pos += 2
			elseif match("!=") then op = "!="; pos += 2
			elseif match(">=") then op = ">="; pos += 2
			elseif match("<=") then op = "<="; pos += 2
			elseif peek() == ">" then op = ">"; pos += 1
			elseif peek() == "<" then op = "<"; pos += 1
			else break end
			local right = parseArithmetic()
			left = typeCmp(left, right, op)
		end
		return left
	end

	local function parseLogicalAnd()
		local left = parseComparison()
		while true do
			skipWhitespace()
			if peek() == "&" then
				pos += 1
				local right = parseComparison()
				left = toBool(left) and toBool(right)
			else break end
		end
		return left
	end

	local function parseLogicalOr()
		local left = parseLogicalAnd()
		while true do
			skipWhitespace()
			if peek() == "|" then
				pos += 1
				local right = parseLogicalAnd()
				left = toBool(left) or toBool(right)
			else break end
		end
		return left
	end

	local function parseTernary()
		local condition = parseLogicalOr()
		skipWhitespace()
		if peek() == "?" then
			pos += 1
			local trueValue = parseLogicalOr()
			skipWhitespace()
			assert(peek() == ":", "Expected ':' in ternary operator")
			pos += 1
			local falseValue = parseTernary() -- Right-associative
			return if toBool(condition) then trueValue else falseValue
		end
		return condition
	end

	function parseExpr()
		return parseTernary()
	end	
	local result = parseExpr()
	skipWhitespace()
	if pos <= #expr then error("Unexpected characters: " .. expr:sub(pos)) end
	if type(result) == "table" and result.__stylevar then
		return evaluateExpression(result.__expr, tokens)
	else
		return result
	end
end

return function(expr: string, tokens: {[string]: any}): any
	local success, result = pcall(evaluateExpression, expr, tokens)
	if not success then
		error(`Error when evaluating ASEL expression '{expr}': '{result}'`)
	end
	return result
end