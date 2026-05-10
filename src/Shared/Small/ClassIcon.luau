--!strict
local StudioService = game:GetService('StudioService')
local getclassicon = StudioService.GetClassIcon

local Types = require(script.Parent.Parent.Parent.Types)

local ClassIcon = {
	CachedIcons = {
		["Pointer"] = {
			ImageRectSize = Vector2.zero,
			ImageRectOffset = Vector2.zero,
			Image = "rbxassetid://125136040625563"
		}
	} :: {[string]: Types.StudioIconResult}
}

function ClassIcon.getIcon(className: string): Types.StudioIconResult?
	local cached = ClassIcon.CachedIcons[className]
	if cached then return cached end

	local icon = getclassicon(StudioService, className)
	ClassIcon.CachedIcons[className] = icon

	return icon
end

function ClassIcon.loadIcons(classes: {ReflectedClass})
	for _, v in classes do
		ClassIcon.getIcon(v.Name)
	end
end

return ClassIcon