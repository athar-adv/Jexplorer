--!strict
--!optimize 2

local main = script.Parent.Parent.Parent
local utilities = main.Utilities

local PluginUI = require(utilities.PluginUI)
local InstanceUtility = require(utilities.Small.InstanceUtility)

local rawindex = InstanceUtility.rawindex

local Types = require(main.Types)

local PropertyFrame = {
	PluginUI = PluginUI,
	InstanceUtility = InstanceUtility,
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