--!strict
--!optimize 2

local StudioService = game:GetService("StudioService")

local PropertyFrame = require("../PropertyFrame")
local PluginUI = PropertyFrame.PluginUI
local RawInst = require("../../../Shared/Small/RawInst")

return PropertyFrame.create(
	"ContentId",
	function(info, list, item, initValue)
		local ui = PluginUI.createAttributeBox(list, item.name, initValue)
		local importFromFileButton = PluginUI.createSideButtonImage("rbxassetid://13544220123", Vector2.zero, Vector2.zero, ui.Instance.ValueBox)
		importFromFileButton:AddTag("JEXP_MonochromeImage")
		importFromFileButton.BackgroundTransparency = 1
		
		return ui, {
			ui = ui,
			importFromFileButton = importFromFileButton
		}
	end,
	function(info, item, initValue, data)
		local ui = data.ui
		local importFromFileButton: ImageButton = data.importFromFileButton
		
		local function onChanged(newValue: string)
			ui:Set(newValue)
		end
		local function onChangedInner(newValue: string)
			onChanged(newValue)
			local id = PropertyFrame.beginRecording("ContentId")
			for _, inst in info.Instances do
				RawInst.rawnewindex(inst, item.name, newValue)
				info.VersionControl.addPendingChange(inst, item.name, newValue)
			end
			PropertyFrame.finishRecording(id)
		end
		
		local activatedConn = importFromFileButton.Activated:Connect(function()
			local file = StudioService:PromptImportFile({"png", "jpg", "jpeg"}) :: File?
			if not file then return end
			
			local id = file:GetTemporaryId()
			onChangedInner(id)
		end)
		local onChangedConn = ui:OnChange(function(txt)
			if txt:match("(%d+)") == txt then
				txt = `rbxassetid://{txt}`
				ui:Set(txt)
			end
			onChangedInner(txt)
		end)
		
		return function()
			activatedConn:Disconnect()
			onChangedConn:Disconnect()
		end, onChanged
	end
)