--!strict
--!optimize 2

--[[
	JExplorer
	This plugin is distributed under the MIT license (2025). 
	
	Author: athar_adv
]]

if not plugin then return end
local VERSION = "pr2.2"

local utilities = script.Utilities
local editors = script.Editors
--local ui = script.UI

local Jecs = require(script.Jecs)
local Manager = require(script.Manager)

local PluginUI = require(utilities.PluginUI)
local Group = require(utilities.Vendor.Group)
local SavedState = require(utilities.SavedState)
local Types = require(script.Types)

local connections = Group.new("Disconnect")

local finished_init = false
local function onClose()
	if Manager.Storage then
		Manager.Storage:Destroy()
	end
	shared.Jexplorer.__close:Fire()
	
	if finished_init and Manager.getSetting("SaveOnClose") then
		Manager.saveState()
	end 
	plugin:Destroy()
	connections:Free()
end

connections:Insert {
	plugin.Unloading:Connect(onClose),
	plugin.Destroying:Connect(onClose),
	script.Destroying:Connect(onClose)
}

local function getevent(name: string): BindableEvent
	local ev
	if shared.Jexplorer and shared.Jexplorer[name] then
		ev = shared.Jexplorer[name]
	else
		ev = Instance.new("BindableEvent")
	end
	return ev
end

-- Public jexplorer plugin api
local onLoadEvent = getevent("__load")
local onCloseEvent = getevent("__close")
local modifyIconEvent = getevent("__modify")

local jexplorerApi: Types.Jexplorer = {
	Manager = Manager,
	StyleEditor = require(editors.StyleEditor),
	SettingEditor = require(editors.SettingEditor),
	OrderEditor = require(editors.OrderEditor),
	VersionControl = require(editors.VersionControl),
	PropertyEditor = require(editors.PropertyEditor),
	
	Dependencies = {
		Selector = require(utilities.Small.Selector),
		Style = require(utilities.Style),
		PluginUI = require(utilities.PluginUI),
		ClassIcon = require(utilities.Small.ClassIcon),
		UDF = require(utilities.UDF),
		SavedState = SavedState,
		GitAPI = require(utilities.GitAPI)
	},
	
	OnLoad = onLoadEvent.Event,
	OnClose = onCloseEvent.Event,
	ModifyIconStep = modifyIconEvent.Event,
	
	__load = onLoadEvent,
	__close = onCloseEvent,
	__modify = modifyIconEvent
}

local getId = PluginUI.getId

shared.Jexplorer = jexplorerApi
local success
local pluginToolbar
while true do
	success, pluginToolbar = pcall(plugin.CreateToolbar, plugin, "athar_adv's tools")
	if success then break end
	task.wait()
end
local uiToggleButton
while true do
	success, uiToggleButton = pcall(pluginToolbar.CreateButton, pluginToolbar,
		getId("ToggleUI"), "Toggle the explorer widget visibility",
		"rbxassetid://112696382020883", "Jexplorer"
	)
	if success then break end
	task.wait()
end

local jexplorerWidget
while true do
	success, jexplorerWidget = pcall(plugin.CreateDockWidgetPluginGuiAsync, plugin,
		getId("Jexplorer"), DockWidgetPluginGuiInfo.new(
			Enum.InitialDockState.Left,
			false,
			false
		)
	)
	if success then break end
	task.wait()
end

jexplorerWidget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
jexplorerWidget.Title = `Jexplorer [{VERSION}]`
jexplorerWidget.Name = "Jexplorer"

jexplorerWidget:BindToClose(function()
	uiToggleButton:SetActive(false)
	jexplorerWidget.Enabled = not jexplorerWidget.Enabled
end)

local function init()
	finished_init = true
	Manager.Toolbar = pluginToolbar
	Manager.init(onClose, connections, jexplorerWidget)
	onLoadEvent:Fire()
	
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