--!strict
--!optimize 2

local StudioService = game:GetService("StudioService")

local PropertyFrame = require("../PropertyFrame")
local PluginUI = PropertyFrame.PluginUI

return PropertyFrame.create(function(_, list, inst, item, initValue)
	local ui = PluginUI.createAttributeBox(list, item.name, initValue)
	local importFromFileButton = PluginUI.createSideButton("rbxassetid://13544220123", Vector2.zero, Vector2.zero, ui.Instance.ValueBox)
	importFromFileButton:AddTag("JEXP_MonochromeImage")
	importFromFileButton.BackgroundTransparency = 1
	
	importFromFileButton.Activated:Connect(function()
		local file = StudioService:PromptImportFile({"png", "jpg", "jpeg"}) :: File?
		if not file then return end
		
		ui:Set(file:GetTemporaryId())
	end)
	ui:OnChange(function(txt)
		if txt:match("(%d+)") == txt then
			txt = `rbxassetid://{txt}`
			ui:Set(txt)
		end
	end)
	
	return ui
end)