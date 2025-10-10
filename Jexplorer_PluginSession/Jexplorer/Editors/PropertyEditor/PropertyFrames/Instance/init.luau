--!strict
--!optimize 2

local plugin = script:FindFirstAncestorOfClass("Plugin")

local PropertyFrame = require("../PropertyFrame")
local PluginUI = PropertyFrame.PluginUI

return PropertyFrame.create(function(info, list, inst, item, initValue)
	local PropertyEditor, Manager = info.PropertyEditor, info.Manager
	
	local uiItem = PluginUI.createAttributeBox(list, item.name, initValue and initValue.Name or "")
	local valueBox = uiItem.Instance:FindFirstChild("ValueBox") :: TextBox
	if not valueBox then return end
	
	valueBox.PlaceholderText = "Click, hold & drop to assign..."
	
	local button = Instance.new("TextButton")
	button.BorderSizePixel = 0
	button.Transparency = 1
	button.Size = UDim2.fromScale(1, 1)
	button.ZIndex = 10
	button.Parent = valueBox
	
	button.InputBegan:Connect(function(input)
		if input.UserInputState ~= Enum.UserInputState.Begin then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			plugin:StartDrag(Manager.getDragInfo(inst, item.name))
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			PropertyEditor.CurrentSetNilTarget = {inst = inst, name = item.name}
			PropertyEditor.SetNilMenu:ShowAsync()
		end
	end)
	
	return uiItem
end)