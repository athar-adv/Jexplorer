--!strict
--!optimize 2

local PropertyFrame = require("../PropertyFrame")

return PropertyFrame.create(function(_, list, inst, item, initValue)
	return PropertyFrame.PluginUI.createAttributeBox(list, item.name, string.format("%.3f", initValue))
end)