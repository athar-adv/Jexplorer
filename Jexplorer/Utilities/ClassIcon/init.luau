local StudioService = game:GetService('StudioService')

local Types = require(script.Parent.Parent.Types)

local ClassIcon = {
	CachedIcons = {}
}

function ClassIcon.getIcon(className: string): Types.StudioIconResult?
	local cached = ClassIcon.CachedIcons[className]
	if cached then return cached end

	local success, icon = xpcall(
		StudioService.GetClassIcon, function()end, StudioService, className
	)
	if not success then return end
	ClassIcon.CachedIcons[className] = icon

	return icon
end

function ClassIcon.loadIcons(apiMap: {[string]: any})
	for k in apiMap do
		ClassIcon.getIcon(k)
	end
end

return ClassIcon