local ReflectionService = game:GetService("ReflectionService")

local propMapCache: {[string]: ReflectedProperties} = {
	-- This is just for TaggedProperty validation checks
	-- For some reason these classes arent present in ReflectionService
	["PluginGuiService"] = {
		["ClassName"] = {},
		["Name"] = {}
	},
	["CoreGui"] = {
		["ClassName"] = {},
		["Name"] = {}
	},
	["DockWidgetPluginGui"] = {
		["ClassName"] = {},
		["Name"] = {}
	}
}

return function(className: string): {[string]: ReflectedProperty}
	local cached = propMapCache[className]
	if cached then return cached end
	
	local props = ReflectionService:GetPropertiesOfClass(className)
	local propMap = {}
	
	if not props then
		propMapCache[className] = propMap
		return propMap
	end
	for _, info in props do
		propMap[info.Name] = info
	end
	propMapCache[className] = propMap
	return propMap
end