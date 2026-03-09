local xyz = require("./xyz")

local ToStringUtils = {
	Color3 = {},
}

local COL3_FMT = "%.2f, %.2f, %.2f"
local FLOAT_FMT = "%.2f"
local VEC2_MT = "%.2f, %.2f"

local XY_PATT = "%s*([%d.-]*)%s*,%s*([%d.-]*)%s*"

function ToStringUtils.fromVec2String(str: string)
	local x, y = str:match(XY_PATT)
	return Vector2.new(
		assert(tonumber(x)),
		assert(tonumber(y))
	)
end

function ToStringUtils.toVec2String(vec2: Vector2)
	return VEC2_MT:format(vec2.X, vec2.Y)
end

function ToStringUtils.fromRGBString(str: string)
	local r, g, b = xyz(str)
	return Color3.fromRGB(
		assert(tonumber(r)),
		assert(tonumber(g)),
		assert(tonumber(b))
	)
end

function ToStringUtils.toRGBString(col: Color3)
	return COL3_FMT:format(col.R * 255, col.G * 255, col.B * 255)
end

function ToStringUtils.toFloatString(num: number)
	return FLOAT_FMT:format(num)
end

function ToStringUtils.fromFloatString(str: string)
	return assert(tonumber(str))
end

return ToStringUtils