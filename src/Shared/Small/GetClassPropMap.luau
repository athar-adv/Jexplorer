local ReflectionService = game:GetService("ReflectionService")

local propMapCache: {[string]: ReflectedProperties} = {}

return function(className: string): {[string]: ReflectedProperty}
	local cached = propMapCache[className]
	if cached then return cached end
	
	local props = ReflectionService:GetPropertiesOfClass(className, {
		Security = SecurityCapabilities.fromCurrent()
	})
	
	if not props then
		local propMap = {
			["ClassName"] = {},
			["Name"] = {}
		}
		propMapCache[className] = propMap
		return propMap
	end
	local propMap = {}
	for _, info in props do
		propMap[info.Name] = info
	end
	propMapCache[className] = propMap
	return propMap
end