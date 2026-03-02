--!strict
--!optimize 2

local PropertyFrame = require("../PropertyFrame")
local getClampedXY = require("../../../Shared/Small/GetClampedXY")
local RawInst = require("../../../Shared/Small/RawInst")

return PropertyFrame.create(
	"Enum",
	function(info, list, item, initValue)
		local editorFrame = info.PropertyEditor.Widget:FindFirstChild("Frame") :: any
		assert(editorFrame)
		
		local overlay = editorFrame.Items.Overlay
		
		local box, dropdownList
		box, dropdownList = PropertyFrame.PluginUI.createEnumBox(list, item.name, initValue.EnumType, initValue, nil, overlay, nil, function(pos, size)
			dropdownList.Backdrop.Parent = overlay
			dropdownList.Backdrop.Size = UDim2.fromOffset(size.X, dropdownList.Backdrop.Size.Y.Offset)
			
			local overlayAbsPos = overlay.AbsolutePosition
			
			local x, y = getClampedXY(
				dropdownList.Backdrop.AbsoluteSize,
				pos,
				size,
				editorFrame.AbsolutePosition,
				editorFrame.AbsoluteSize
			)
			local relativeX = x - overlayAbsPos.X
			local relativeY = y - overlayAbsPos.Y
			
			return Vector2.new(0, 0), UDim2.fromOffset(relativeX, relativeY)
		end)
		
		return box, {
			box = box,
			dropdownList = dropdownList
		}
	end,
	function(info, item, initValue, data)
		local box = data.box
		
		local function onChanged(newValue: EnumItem)
			box:ReconstructEnumList(newValue.EnumType, newValue)
		end
		local function onChangedInner(newValue: EnumItem)
			onChanged(newValue)
			local id = PropertyFrame.beginRecording("Enum")
			for _, inst in info.Instances do
				RawInst.rawnewindex(inst, item.name, newValue)
				info.VersionControl.addPendingChange(inst, item.name, newValue)
			end
			PropertyFrame.finishRecording(id)
		end
		
		onChanged(initValue)
		local changedConn = box:OnChange(onChangedInner)
		
		return function()
			changedConn:Disconnect()
		end, onChanged
	end
)