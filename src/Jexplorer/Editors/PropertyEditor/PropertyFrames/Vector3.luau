--!strict
--!optimize 2

local PropertyFrame = require("../PropertyFrame")
local xyz = require("../../../Shared/Small/xyz")
local PluginUI = PropertyFrame.PluginUI
local RawInst = PropertyFrame.RawInst

return PropertyFrame.create(
	"Vector3",
	function(info, list, item, initValue)
		local axisToUi = {}
		local items: any = {
			function(parent)
				local box = PluginUI.createAttributeBox(nil, "X", string.format("%.3f", initValue.X))
				axisToUi["x"] = box
				return box
			end,
			function(parent)
				local box = PluginUI.createAttributeBox(nil, "Y", string.format("%.3f", initValue.Y))
				axisToUi["y"] = box
				return box
			end,
			function(parent)
				local box = PluginUI.createAttributeBox(nil, "Z", string.format("%.3f", initValue.Z))
				axisToUi["z"] = box
				return box
			end,
		}
		local box, items = PluginUI.createDropdownBox(list, item.name, `{string.format("%.3f", initValue.X)}, {string.format("%.3f", initValue.Y)}, {string.format("%.3f", initValue.Z)}`, nil, items)
		
		return box, {
			box = box,
			axisToUi = axisToUi
		}
	end,
	function(info, item, initValue, data)
		local box = data.box
		local axisToUi = data.axisToUi
		
		local function onChanged(newValue: Vector3)
			box:Set(`{string.format("%.3f", newValue.X)}, {string.format("%.3f", newValue.Y)}, {string.format("%.3f", newValue.Z)}`)
			axisToUi["x"]:Set(string.format("%.3f", newValue.X))
			axisToUi["y"]:Set(string.format("%.3f", newValue.Y))
			axisToUi["z"]:Set(string.format("%.3f", newValue.Z))
		end
		local function onChangedInner(newValue: Vector3)
			onChanged(newValue)
			local id = PropertyFrame.beginRecording("Vector3")
			for _, inst in info.Instances do
				RawInst.rawnewindex(inst, item.name, newValue)
				info.VersionControl.addPendingChange(inst, item.name, newValue)
			end
			PropertyFrame.finishRecording(id)
		end
		
		local conns = {
			box:OnChange(function(str: string)
				local x, y, z = xyz(str)
				local vec = Vector3.new(
					PropertyFrame.tonumber(x),
					PropertyFrame.tonumber(y),
					PropertyFrame.tonumber(z)
				)
				onChangedInner(vec)
			end),
			axisToUi["x"]:OnChange(function(newValue: any)
				local curr = box:Get()
				local x, y, z = xyz(curr)
				local str = `{string.format("%.3f", newValue)}, {string.format("%.3f", y)}, {string.format("%.3f", z)}`
				box:Set(str)
				axisToUi["x"]:Set(string.format("%.3f", newValue))
				
				local vec = Vector3.new(
					PropertyFrame.tonumber(newValue),
					PropertyFrame.tonumber(y),
					PropertyFrame.tonumber(z)
				)
				onChangedInner(vec)
			end),
			axisToUi["y"]:OnChange(function(newValue: any)
				local curr = box:Get()
				local x, y, z = xyz(curr)
				local str = `{string.format("%.3f", x)}, {string.format("%.3f", newValue)}, {string.format("%.3f", z)}`
				box:Set(str)
				axisToUi["y"]:Set(string.format("%.3f", newValue))
				
				local vec = Vector3.new(
					PropertyFrame.tonumber(x),
					PropertyFrame.tonumber(newValue),
					PropertyFrame.tonumber(z)
				)
				onChangedInner(vec)
			end),
			axisToUi["z"]:OnChange(function(newValue: any)
				local curr = box:Get()
				local x, y, z = xyz(curr)
				local str = `{string.format("%.3f", x)}, {string.format("%.3f", y)}, {string.format("%.3f", newValue)}`
				box:Set(str)
				axisToUi["z"]:Set(string.format("%.3f", newValue))
				
				local vec = Vector3.new(
					PropertyFrame.tonumber(x),
					PropertyFrame.tonumber(y),
					PropertyFrame.tonumber(newValue)
				)
				onChangedInner(vec)
			end)
		}
		onChanged(initValue)
		return function()
			for _, conn in conns do
				conn:Disconnect()
			end
		end, onChanged
	end
)