--!strict
--!optimize 2

local main = script.Parent.Parent.Parent
local shared = main.Shared

local PluginUI = require(shared.PluginUI)
local RawInst = require(shared.Small.RawInst)

local rawindex = RawInst.rawindex

local Types = require(main.Types)

local PropertyFrame = {
	PluginUI = PluginUI,
	RawInst = RawInst,
}

type CallbackInfo = {
	PropertyEditor: Types.PropertyEditor,
	Manager: Types.Manager,
	InstanceCleanup: {Instance}
}

function PropertyFrame.create(callback: (info: CallbackInfo, list: PluginUI.ItemList, inst: Instance, item: Types.PropertyItem, initValue: any) -> PluginUI.ValueUIItem?)
	return function(info, list, inst, item): PluginUI.ValueUIItem?
		local success, initValue = pcall(rawindex, inst, item.name)
		if not success then return end
		
		return callback(info, list, inst, item, initValue)
	end
end

return PropertyFrame