--!strict
--!optimize 2

--[[
	JExplorer
	This plugin is distributed under the MIT license (2026). 
	
	Author: athar_adv
]]

if not plugin then return end

local CoreGui = game:GetService("CoreGui")

local VERSION = "3.3.0"

local global = shared
local shared = script.Shared
local editors = script.Editors
--local ui = script.UI

local Jecs = require(script.Jecs)
local Manager = require(script.Manager)

local PluginUI = require(shared.PluginUI)
local ItemGroup = require(shared.Vendor.ItemGroup)
local SavedState = require(shared.SavedState)
local Types = require(script.Types)
local UniPlugin = require(script.UniPlugin)(plugin)
local cleanup = ItemGroup.cleanup

local running = coroutine.running()
local connections = ItemGroup.create(cleanup.disconnect)
local instances = connections:extend(cleanup.destroy)
connections:extend(cleanup.call, {function()
	repeat
		local success = pcall(task.cancel, running)
		task.wait()
	until success
end})

local finished_init = false
UniPlugin:onClose(function()
	if Manager.Storage then
		if Manager.Storage.repoRoots then
			Manager.Storage.repoRoots:ClearAllChildren()
		end
	end

	if finished_init and Manager.getSetting("SaveOnClose") then
		Manager.saveState()
	end 
	connections:free()
end)

-- Public jexplorer plugin api
UniPlugin:setApi("manager", Manager)
UniPlugin:setApi("editors", {
	StyleEditor = require(editors.StyleEditor),
	SettingEditor = require(editors.SettingEditor),
	OrderEditor = require(editors.OrderEditor),
	VersionControl = require(editors.VersionControl),
	PropertyEditor = require(editors.PropertyEditor),
})
UniPlugin:setApi("dependencies", {
	Selector = require(shared.Small.Selector),
	Style = require(shared.Style),
	PluginUI = require(shared.PluginUI),
	ClassIcon = require(shared.Small.ClassIcon),
	UDF = require(shared.UDF),
	SavedState = SavedState,
	GitAPI = require(shared.GitAPI)
})
UniPlugin:exportAs("athar-adv/Jexplorer")

local function pluginui<T>(name: string, create: () -> T): T
	local success
	local item: any
	while true do
		success, item = pcall(create)
		if success then break end
		task.wait()
	end
	item.Name = "Jexplorer_TOOLBAR"
	return item
end

local getId = PluginUI.getId
local pluginToolbar = pluginui("TOOLBAR", function()
	return plugin:CreateToolbar("athar_adv's tools")
end)

local uiToggleButton = pluginui("UITOGGLE", function()
	return pluginToolbar:CreateButton(
		getId("ToggleUI"), "Toggle the explorer widget visibility",
		"rbxassetid://112696382020883", "Jexplorer"
	)
end)

local jexplorerWidget = pluginui("", function()
	return plugin:CreateDockWidgetPluginGuiAsync(
		getId("Jexplorer"), DockWidgetPluginGuiInfo.new(
			Enum.InitialDockState.Left,
			false,
			false
		)
	)
end)

jexplorerWidget:AddTag("JEXP_Widget")
jexplorerWidget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
jexplorerWidget.Title = `Jexplorer [{VERSION}]`
jexplorerWidget.Name = "Jexplorer"

jexplorerWidget:BindToClose(function()
	jexplorerWidget.Enabled = not jexplorerWidget.Enabled
end)
jexplorerWidget:GetPropertyChangedSignal("Enabled"):Connect(function()
	uiToggleButton:SetActive(jexplorerWidget.Enabled)
end)

local function init()
	finished_init = true
	Manager.Toolbar = pluginToolbar
	Manager.init(connections, jexplorerWidget)
	
	jexplorerWidget.Enabled = true
	uiToggleButton:SetActive(true)
end

uiToggleButton.ClickableWhenViewportHidden = true
uiToggleButton.Click:Connect(function()
	if not finished_init then
		uiToggleButton:SetActive(false)
		init()
	else
		local state = Manager.WidgetState
		local widget = state.Widget
		
		widget.Enabled = not widget.Enabled
	end
end)

if jexplorerWidget.HostWidgetWasRestored and not finished_init then
	init()
end