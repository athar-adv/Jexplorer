--!strict
--!optimize 2

local StudioService = game:GetService("StudioService")

local PropertyFrame = require("../PropertyFrame")
local xyz = require("../../../Shared/Small/xyz")
local ColorPicker = require("../../../Shared/Vendor/PluginColorPicker")

local PluginUI = PropertyFrame.PluginUI
local RawInst = PropertyFrame.RawInst
local getId = PluginUI.getId

return PropertyFrame.create(
	"Color3",
	function(info, list, item, initValue)
		local ui = PluginUI.createAttributeBox(list, item.name, "")
		local chooseColorButton = PluginUI.createSideButtonImage("", Vector2.zero, Vector2.zero, ui.Instance.ValueBox)
		chooseColorButton:AddTag("JEXP_Border")
		chooseColorButton.BackgroundColor3 = initValue
		
		return ui, {
			ui = ui,
			chooseColorButton = chooseColorButton
		}
	end,
	function(info, item, initValue, data)
		local ui = data.ui
		local chooseColorButton: ImageButton = data.chooseColorButton
		
		ui:Set(`{math.round(initValue.R * 255)}, {math.round(initValue.G * 255)}, {math.round(initValue.B * 255)}`)
		ui:SetName(item.name)
		
		chooseColorButton.BackgroundColor3 = initValue
		
		local function colorChanged(newColor: Color3)
			ui:Set(`{math.round(newColor.R * 255)}, {math.round(newColor.G * 255)}, {math.round(newColor.B * 255)}`)
			chooseColorButton.BackgroundColor3 = newColor
		end
		local function colorChangedInner(newColor: Color3)
			colorChanged(newColor)
			for _, inst in info.Instances do
				RawInst.rawnewindex(inst, item.name, newColor)
				info.VersionControl.addPendingChange(inst, item.name, newColor)
			end
		end
		local picker
		local activatedConn = chooseColorButton.Activated:Connect(function()
			if picker then
				picker:Close()
				picker:Destroy()
			end
			
			picker = ColorPicker.new(info.Plugin, getId("PropertyColorPicker", true))
			picker:Show()
			
			local originalColor
			local allSame, firstValue = PropertyFrame.isAllValuesSame(info.Instances, item.name)
			if allSame then
				originalColor = firstValue
			else
				originalColor = initValue
			end
			
			picker:Set(originalColor)
			
			local operation = Enum.FinishRecordingOperation.Commit
			picker:BindToChange(function(newColor)
				local id = PropertyFrame.beginRecording("Try Color3")
				colorChangedInner(newColor)
				PropertyFrame.finishRecording(id, operation)
				operation = Enum.FinishRecordingOperation.Append
			end)
			picker:BindToCancel(function()
				local id = PropertyFrame.beginRecording("Cancel")
				colorChangedInner(originalColor)
				PropertyFrame.finishRecording(id)
				
				picker:Close()
				picker:Destroy()
			end)
			picker:BindToConfirm(function()
				picker:Close()
				picker:Destroy()
			end)
		end)
		
		local changedConn = ui:OnChange(function(newValue)
			local r, g, b = xyz(newValue)
			local color = Color3.fromRGB(
				PropertyFrame.tonumber(r),
				PropertyFrame.tonumber(g),
				PropertyFrame.tonumber(b)
			)
			chooseColorButton.BackgroundColor3 = color
			
			local id = PropertyFrame.beginRecording("Change Color3")
			for _, inst in info.Instances do
				RawInst.rawnewindex(inst, item.name, color)
				info.VersionControl.addPendingChange(inst, item.name, color)
			end
			PropertyFrame.finishRecording(id)
		end)
		
		return function()
			changedConn:Disconnect()
			activatedConn:Disconnect()
		end, colorChanged
	end
)