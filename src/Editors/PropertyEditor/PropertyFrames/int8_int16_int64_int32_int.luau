--!strict
--!optimize 2

local PropertyFrame = require("../PropertyFrame")

local RawInst = PropertyFrame.RawInst

return PropertyFrame.create(
	"number",
	function(info, list, item, initValue)
		local box = PropertyFrame.PluginUI.createAttributeBox(list, item.name, initValue)
		return box, {
			box = box
		}
	end,
	function(info, item, initValue, data)
		local box = data.box

		box:Set(initValue)
		box:SetName(item.name)

		local function onChanged(newValue: number)
			box:Set(newValue)
		end
		local function onChangedInner(newValue: number)
			onChanged(newValue)

			local id = PropertyFrame.beginRecording("Change")
			for _, inst in info.Instances do
				RawInst.rawnewindex(inst, item.name, newValue)
				info.VersionControl.addPendingChange(inst, item.name, newValue)
			end
			PropertyFrame.finishRecording(id)
		end

		local changedConn = box:OnChange(function(newValue)
			onChangedInner(PropertyFrame.tonumber(newValue))
		end)

		return function()
			changedConn:Disconnect()
		end, onChanged
	end
)