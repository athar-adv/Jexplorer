--!strict
--!optimize 2

local PropertyFrame = require("../PropertyFrame")
local getClampedXY = require("../../../Shared/Small/GetClampedXY")

return PropertyFrame.create(function(info, list, inst, item, initValue)
	local enumName = string.match(item.type, "Enum%.(%w+)")
	if not enumName then return end
	
	local editorFrame = info.PropertyEditor.Widget:FindFirstChild("EditorFrame") :: any
	if not editorFrame then return end
	
	local box, dropdownList
	box, dropdownList = PropertyFrame.PluginUI.createEnumBox(list, item.name, Enum[enumName], initValue, nil, editorFrame, function(v)
		table.insert(info.InstanceCleanup, v)
	end, function(pos, size)
		local x, y = getClampedXY(
			dropdownList.Backdrop.AbsoluteSize,
			box.Instance.AbsolutePosition,
			Vector2.zero,
			editorFrame.AbsolutePosition,
			editorFrame.AbsoluteSize
		)
		return Vector2.new(0, 0), UDim2.fromOffset(x, y)
	end)
	return box
end)