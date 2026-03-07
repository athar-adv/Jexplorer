--!strict
local StudioService = game:GetService('StudioService')
local getclassicon = StudioService.GetClassIcon

local Types = require(script.Parent.Parent.Parent.Types)

local ClassIcon = {
	CachedIcons = {}
}

function ClassIcon.getIcon(className: string): Types.StudioIconResult?
	local cached = ClassIcon.CachedIcons[className]
	if cached then return cached end

	local icon = getclassicon(StudioService, className)
	ClassIcon.CachedIcons[className] = icon

	return icon
end

function ClassIcon.loadIcons(classes: ReflectedClasses)
	for _, v in classes do
		ClassIcon.getIcon(v.Name)
	end
end

return ClassIcon