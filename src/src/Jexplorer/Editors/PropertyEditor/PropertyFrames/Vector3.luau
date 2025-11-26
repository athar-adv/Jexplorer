--!strict
--!optimize 2

local PropertyFrame = require("../PropertyFrame")
local xyz = require("../xyz")
local PluginUI = PropertyFrame.PluginUI

return PropertyFrame.create(function(_, list, inst, item, initValue)
	local items: any = {
		function(parent)
			local box
			box = PluginUI.createAttributeBox(nil, "X", string.format("%.3f", initValue.X), function(newValue: any)
				local curr = parent:Get()
				local x, y, z = xyz(curr)
				
				local str = `{string.format("%.3f", newValue)}, {string.format("%.3f", y)}, {string.format("%.3f", z)}`
				parent:Set(str)
				box:Set(string.format("%.3f", x))
			end)
			return box
		end,
		function(parent)
			local box
			box = PluginUI.createAttributeBox(nil, "Y", string.format("%.3f", initValue.Y), function(newValue: any)
				local curr = parent:Get()
				local x, y, z = xyz(curr)
				local str = `{string.format("%.3f", x)}, {string.format("%.3f", newValue)}, {string.format("%.3f", z)}`
				parent:Set(str)
				box:Set(string.format("%.3f", y))
			end)
			return box
		end,
		function(parent)
			local box
			box = PluginUI.createAttributeBox(nil, "Z", string.format("%.3f", initValue.Z), function(newValue: any)
				local curr = parent:Get()
				local x, y, z = xyz(curr)
				local str = `{string.format("%.3f", x)}, {string.format("%.3f", y)}, {string.format("%.3f", newValue)}`
				parent:Set(str)
				box:Set(string.format("%.3f", z))
			end)
			return box
		end,
	}
	local box
	box = PluginUI.createDropdownBox(list, item.name, `{string.format("%.3f", initValue.X)}, {string.format("%.3f", initValue.Y)}, {string.format("%.3f", initValue.Z)}`, function(newValue)
		
	end, items)
	
	return box
end)