--!strict
--!optimize 2

local PropertyFrame = require("../PropertyFrame")

local RawInst = PropertyFrame.RawInst

return PropertyFrame.create(
	"string",
	function(info, list, item, initValue)
		local box = PropertyFrame.PluginUI.createCheckBox(list, item.name, initValue)
		return box, {
			box = box
		}
	end,
	function(info, item, initValue, data)
		local box = data.box
		
		box:Set(initValue)
		box:SetName(item.name)
		
		local function onChanged(newValue: boolean)
			box:Set(newValue)
		end
		local function onChangedInner(newValue: boolean)
			onChanged(newValue)
			
			local id = PropertyFrame.beginRecording("bool")
			for _, inst in info.Instances do
				RawInst.rawnewindex(inst, item.name, newValue)
				info.VersionControl.addPendingChange(inst, item.name, newValue)
			end
			PropertyFrame.finishRecording(id)
		end
		
		local changedConn = box:OnChange(onChangedInner)
		
		return function()
			changedConn:Disconnect()
		end, onChanged
	end
)