--!strict
--!optimize 2

local ChangeHistoryService = game:GetService("ChangeHistoryService")

local main = script.Parent.Parent.Parent
local shared = main.Shared

local PluginUI = require(shared.PluginUI)
local RawInst = require(shared.Small.RawInst)

local rawindex = RawInst.rawindex

local Types = require(main.Types)

local PropertyFrame = {
	PluginUI = PluginUI,
	RawInst = RawInst,
	tonumber = function(a: any)
		return assert(tonumber(a))
	end,
	beginRecording = function(name: string): string?
		return ChangeHistoryService:TryBeginRecording(name, name)
	end,
	finishRecording = function(id: string?, operation: Enum.FinishRecordingOperation?)
		if not id then return end
		ChangeHistoryService:FinishRecording(id, operation or Enum.FinishRecordingOperation.Commit)
	end,
}

type CallbackInfo = {
	PropertyEditor: Types.PropertyEditor,
	Manager: Types.Manager,
	InstanceCleanup: {Instance},
	VersionControl: Types.VersionControl,
	Plugin: Plugin,
	Instances: {Instance}
}

export type PropertyFrame = {
	createUI: (info: CallbackInfo, list: PluginUI.ItemList, item: Types.PropertyItem, initValue: any) -> (PluginUI.ValueUIItem<any> & any, {[string]: any}),
	applyBehavior: (info: CallbackInfo, item: Types.PropertyItem, initValue: any, data: {[string]: any}) -> (() -> (), (changedValue: any) -> ()),
	typeId: string
}

local typeIdToFrame: {[string]: PropertyFrame} = {}

function PropertyFrame.create(type_id: string, ui_callback: (info: CallbackInfo, list: PluginUI.ItemList, item: Types.PropertyItem, initValue: any) -> (PluginUI.ValueUIItem & any, {[string]: any}), behavior_callback: (info: CallbackInfo, item: Types.PropertyItem, initValue: any, uiData: {[string]: any}) -> (() -> (), (changedValue: any) -> ())): PropertyFrame
	local frame = {
		createUI = ui_callback,
		applyBehavior = behavior_callback,
		typeId = type_id
	}:: PropertyFrame
	typeIdToFrame[type_id] = frame
	return frame
end

function PropertyFrame.fromTypeId(type_id: string): PropertyFrame
	return assert(typeIdToFrame[type_id])
end

function PropertyFrame.isAllValuesSame(instances: {Instance}, propName: string)
	local firstValue = rawindex(instances[1], propName)
	local allSame = true

	for j = 2, #instances do
		if rawindex(instances[j], propName) ~= firstValue then
			allSame = false
			break
		end
	end
	
	return allSame, firstValue
end

return PropertyFrame