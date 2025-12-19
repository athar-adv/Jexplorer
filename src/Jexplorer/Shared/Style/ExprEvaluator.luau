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

local function getType(v)
	local t = typeof(v)
	if supportedTypes[t] then return t else error(`unsupported type '{t}' ; '{v}'`) end
end

local function typeAdd(a, b)
	local ta, tb = getType(a), getType(b)
	if ta == "number" and tb == "number" then return a + b end
	if ta == "Color3" and tb == "Color3" then
		return Color3.new(a.R + b.R, a.G + b.G, a.B + b.B)
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
		return Color3.new(a.R - b.R, a.G - b.G, a.B - b.B)
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
	if ta == "number" then return -a end
	if ta == "Color3" then
		return Color3.new(-a.R, -a.G, -a.B)
	end
	if ta == "Vector2" then return -a end
	if ta == "Vector3" then return -a end
	if ta == "UDim2" then return -a end
	if ta == "UDim" then return -a end
	error("Cannot negate " .. ta)
end

local function typeCmp(a, b, op)
	if op == "==" then return a == b
	elseif op == "~=" or op == "!=" then return a ~= b
	elseif typeof(a) == "number" and typeof(b) == "number" then
		if op == "<" then return a < b end
		if op == "<=" then return a <= b end
		if op == ">" then return a > b end
		if op == ">=" then return a >= b end
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
	-- Use luminance formula: 0.299*R + 0.587*G + 0.114*B (scaled to 0-255)
	return (0.299 * color.R + 0.587 * color.G + 0.114 * color.B) * 255
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

local function callFunc(name, args)
	local function unpackArgs(count)
		if #args ~= count then error(name .. " expects " .. count .. " arguments") end
		return table.unpack(args)
	end
	if name == "vec2" then return Vector2.new(unpackArgs(2)) end
	if name == "vec3" then return Vector3.new(unpackArgs(3)) end
	if name == "rgb" then return Color3.fromRGB(unpackArgs(3)) end
	if name == "hex" then
		local v = unpackArgs(1)
		--return Color3.fromRGB(bit32.rshift(v, 16), bit32.band(bit32.rshift(v, 8), 0xFF), bit32.band(v, 0xFF))
		return Color3.fromHex(v)
	end
	if name == "udim2" then return UDim2.new(unpackArgs(4)) end
	if name == "udim" then return UDim.new(unpackArgs(2)) end
	if name == "min" then return math.min(table.unpack(args)) end
	if name == "max" then return math.max(table.unpack(args)) end
	if name == "abs" then return math.abs(unpackArgs(1)) end
	if name == "floor" then return math.floor(unpackArgs(1)) end
	if name == "ceil" then return math.ceil(unpackArgs(1)) end
	if name == "round" then return math.floor(unpackArgs(1) + 0.5) end
	if name == "clamp" then
		local a, min, max = unpackArgs(3)
		return math.max(min, math.min(max, a))
	end
	if name == "brightness" then return getColorBrightness(unpackArgs(1)) end
	error("Unknown function: " .. name)
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

return evaluateExpression