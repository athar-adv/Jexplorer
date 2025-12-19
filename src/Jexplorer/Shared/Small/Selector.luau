local StudioService = game:GetService('StudioService')

local JexpTags = require("./JexpTags")
local format = string.format

local function getTaggedPropertySelector(propName: string, targetedValue: string)
	return `.{JexpTags.getTaggedPropertyTag(propName, targetedValue)}`
end

local function getIconSelector(name: string?, class: string?)
	if not name and not class then
		return "#ClassIcon"
	elseif not name and class then
		return `{getTaggedPropertySelector("ClassName", class)} > #Main > #ClassIcon`
	elseif name and not class then
		return `{getTaggedPropertySelector("Name", name)} > #Main > #ClassIcon`
	elseif name and class then
		return `{getTaggedPropertySelector("ClassName", class)} {getTaggedPropertySelector("Name", name)} > #Main > #ClassIcon`
	end
end

local function getClassTagSlctr(tag: string, ...: string)
	local selector = {}
	for _, class in {...} do
		table.insert(selector, `{tag} {class}`)
	end
	return table.concat(selector, ",")
end

local function parseSelectorMacro(selector: string): (string?, string)
	selector = selector:gsub("%s", "")
	if selector:sub(1, 1) == "@" then
		local parens = selector:match("%b()")
		assert(parens, "macro must contain parens")
		selector = selector:sub(2, #selector - #parens)
		parens = parens:sub(2, #parens - 1)

		local values = string.split(parens, ",")
		if selector == "icon" then
			return getIconSelector(
				values[1] ~= "nil" and values[1] or nil,
				values[2] ~= "nil" and values[2] or nil
			), "icon"
		elseif selector == "prop" then
			return getTaggedPropertySelector(
				values[1],
				values[2]
			), "prop"
		elseif selector == "tag" then
			return `.JEXP_TAG_{values[1]}`, "tag"
		end
	end
	return nil, "none"
end

return {
	getClassTagSlctr = getClassTagSlctr,
	parseSelectorMacro = parseSelectorMacro,
	getTaggedPropertySelector = getTaggedPropertySelector,
	getIconSelector = getIconSelector
}