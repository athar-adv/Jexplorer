--!strict
--!optimize 2

local StudioService = game:GetService("StudioService")

local PropertyFrame = require("../PropertyFrame")
local xyz = require("../xyz")
local ColorPicker = require("../PropertyWidgets/ColorPicker")

local PluginUI = PropertyFrame.PluginUI
local InstanceUtility = PropertyFrame.InstanceUtility

local currentOnClose: any

return PropertyFrame.create(function(_, list, inst, item, initValue)
	local ui = PluginUI.createAttributeBox(list, item.name, `{math.round(initValue.R * 255)}, {math.round(initValue.G * 255)}, {math.round(initValue.B * 255)}`)
	local chooseColorButton = PluginUI.createSideButton("", Vector2.zero, Vector2.zero, ui.Instance.ValueBox)
	chooseColorButton:AddTag("JEXP_Border")
	chooseColorButton.BackgroundColor3 = initValue
	
	local function colorChanged(newColor: Color3)
		ui:Set(`{math.round(newColor.R * 255)}, {math.round(newColor.G * 255)}, {math.round(newColor.B * 255)}`)
		chooseColorButton.BackgroundColor3 = newColor
	end
	
	chooseColorButton.Activated:Connect(function()
		if currentOnClose then
			currentOnClose()
		end
		ColorPicker:Show()
		local originalColor = InstanceUtility.rawindex(inst, item.name)
		ColorPicker:Set(originalColor)
		
		ColorPicker:BindToChange(colorChanged)
		local function onClose()
			ColorPicker:BindToCancel(nil)
			ColorPicker:BindToConfirm(nil)
			currentOnClose = nil
		end
		ColorPicker:BindToCancel(function()
			colorChanged(originalColor)
			ColorPicker:Close()
			onClose()
		end)
		ColorPicker:BindToConfirm(function()
			ColorPicker:Close()
			onClose()
		end)
		currentOnClose = onClose
	end)
	
	ui:OnChange(function(newValue)
		local r, g, b = xyz(newValue)
		chooseColorButton.BackgroundColor3 = Color3.fromRGB(
			tonumber(r),
			tonumber(g),
			tonumber(b)
		)
	end)
	
	return ui
end)