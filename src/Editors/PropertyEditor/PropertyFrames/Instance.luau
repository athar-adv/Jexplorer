--!strict
--!optimize 2

local plugin = script:FindFirstAncestorOfClass("Plugin")

local PropertyFrame = require("../PropertyFrame")
local PluginUI = PropertyFrame.PluginUI

return PropertyFrame.create(
	"Instance",
	function(info, list, item, initValue)
		local PropertyEditor, Manager = info.PropertyEditor, info.Manager
		
		local uiItem = PluginUI.createAttributeBox(list, item.name, initValue and initValue.Name or "")
		local valueBox = uiItem.Instance:FindFirstChild("ValueBox") :: TextBox
		assert(valueBox)
		
		valueBox.PlaceholderText = "Click, hold & drop to assign..."
		
		local button = Instance.new("TextButton")
		button.BorderSizePixel = 0
		button.Transparency = 1
		button.Size = UDim2.fromScale(1, 1)
		button.ZIndex = 10
		button.Parent = valueBox
		
		return uiItem, {
			button = button,
			valueBox = valueBox
		}
	end,
	function(info, item, initValue, data)
		local PropertyEditor, Manager = info.PropertyEditor, info.Manager
		local button: TextButton = data.button
		local valueBox: TextBox = data.valueBox
		
		local function onChanged(newValue: Instance?)
			valueBox.Text = newValue and newValue.Name or ""
		end
		
		local inputConnection = button.InputBegan:Connect(function(input)
			if input.UserInputState ~= Enum.UserInputState.Begin then return end
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				plugin:StartDrag(Manager.getSetPropertyDragInfo(info.Instances, item.name))
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
				PropertyEditor.CurrentSetNilTarget = {instances = info.Instances, name = item.name}
				PropertyEditor.SetNilMenu:ShowAsync()
			end
		end)
		
		return function()
			inputConnection:Disconnect()
		end, onChanged
	end
)