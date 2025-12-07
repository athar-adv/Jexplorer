--!strict
--!optimize 2

local plugin = script:FindFirstAncestorOfClass("Plugin")

local main = script.Parent.Parent
local utilities = main.Utilities

local UITemplates = require(utilities.UITemplates)
local Types = require(main.Types)
local PluginUI = require(utilities.PluginUI)
local Style = require(utilities.Style)
local DefaultSettings = require(utilities.Defaults.DefaultSettings)
local JDF = require(utilities.UDF)

local getId = PluginUI.getId

local init = false
local SettingEditor = {
	Configs = {}
} :: Types.SettingEditor

local settingNameToData = {}
local settingNameToFrame = {}

function SettingEditor.getSetting(Manager, name)
	if not init then return nil end
	local configs = SettingEditor.Configs

	local value = configs[name]
	if type(value) == "table" and value.__stylevar then
		value = Style.eval(value.__expr, Manager.Style.Tokens)
	end
	return value
end

function SettingEditor.setSetting(Manager, name, value)
	if not init then return nil end
	local configs = SettingEditor.Configs
	configs[name] = value
	
	local frame = settingNameToFrame[name]
	if frame then
		local data = settingNameToData[name]
		if data and data.Type == "boolean" then
			frame:Set(value)
		else
			frame:Set(JDF.to(value))
		end
	end

	local data = settingNameToData[name]
	if data and data.OnChange then
		data.OnChange(Manager, value)
	end
end

function SettingEditor.createSetting(list, settingName, displayName, valueType, defaultValue, onChange)
	if not init then return end
	local configs = SettingEditor.Configs

	configs[settingName] = defaultValue
	if valueType == "boolean" then
		local box = PluginUI.createCheckBox(list, displayName, defaultValue, function(newValue)
			assert(typeof(newValue) == valueType)
			configs[settingName] = newValue

			if not onChange then return end
			onChange(newValue)
		end)
		settingNameToFrame[settingName] = box
	else
		local box
		box = PluginUI.createAttributeBox(list, displayName, JDF.to(defaultValue), function(newValue)
			local realVal = JDF.from(newValue)
			if not (type(realVal) == "table" and realVal.__stylevar) and (typeof(realVal) ~= valueType) then
				configs[settingName] = defaultValue
				box:Set(JDF.to(defaultValue))
				return
			end
			configs[settingName] = realVal

			if not onChange then return end
			onChange(realVal)
		end)
		settingNameToFrame[settingName] = box
	end
end

function SettingEditor.init(Manager)
	init = true
	assert(SettingEditor.Configs, "configs must be initialized by manager")

	local state = Manager.WidgetState
	local components = Manager.Components
	local jexplorerUi = state.JExplorerUI
	local connections = state.Connections

	local widget, mainframe = PluginUI.createEditorWidget(UITemplates.EditorFrame(), "SettingEditor", "Setting Editor")
	SettingEditor.Widget = widget
	Manager.Style:Link(widget)

	local createSetting = SettingEditor.createSetting
	local behaviors = {
		ExpandBehavior = PluginUI.createDropDownItemList({
			Name = "ExpandBehavior",
			Visible = true,
			Parent = mainframe.Items
		}, "Expand Behavior"),

		ScrollBehavior = PluginUI.createDropDownItemList({
			Name = "ScrollBehavior",
			Visible = true,
			Parent = mainframe.Items
		}, "Scrolling Behavior"),

		SelectBehavior = PluginUI.createDropDownItemList({
			Name = "SelectBehavior",
			Visible = true,
			Parent = mainframe.Items
		}, "Select Behavior"),

		SavingBehavior = PluginUI.createDropDownItemList({
			Name = "SavingBehavior",
			Visible = true,
			Parent = mainframe.Items
		}, "Saving Behavior"),
		
		InternalBehavior = PluginUI.createDropDownItemList({
			Name = "InternalBehavior",
			Visible = true,
			Parent = mainframe.Items
		}, "Internal Behavior"),
	}
	
	for behaviorName, list in DefaultSettings do
		local behavior = behaviors[behaviorName]
		for name, data in list do
			local existingValue = SettingEditor.Configs[name]
			settingNameToData[name] = data
			createSetting(
				behavior,
				name,
				data.Display,
				data.Type,
				existingValue or data.Default,
				data.OnChange ~= nil and function(newValue)
					data.OnChange(Manager, newValue)
				end or nil
			)
		end
	end
end

return SettingEditor