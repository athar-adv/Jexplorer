--!strict
--!optimize 2

--[[
	JExplorer
	This plugin is distributed under the MIT license (2025).
	
	Author: athar_adv
]]

if not plugin then return end
local VERSION = "b0.21.5"

local utilities = script.Utilities
local editors = script.Editors
local ui = script.UI

local Jecs = require(script.Jecs)
local Manager = require(script.Manager)

local PluginUI = require(utilities.PluginUI)
local Group = require(utilities.Group)
local JState = require(utilities.JState)

local connections = Group.new("Disconnect")

local function onClose()
	shared.Jexplorer.__close:Fire()
	
	if JState.Initialized and Manager.getSetting("SaveOnClose") then
		JState.save()
	end
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

shared.Jexplorer = {
	Manager = Manager,
	StyleEditor = require(editors.StyleEditor),
	SettingEditor = require(editors.SettingEditor),
	OrderEditor = require(editors.OrderEditor),
	Dependencies = {
		Selector = require(utilities.Selector),
		Style = require(utilities.Style),
		PluginUI = require(utilities.PluginUI),
		ClassIcon = require(utilities.ClassIcon),
		JDF = require(utilities.JDF),
		JState = JState,
	},

	OnLoad = onLoadEvent.Event,
	OnClose = onCloseEvent.Event,
	ModifyIconStep = modifyIconEvent.Event,

	__load = onLoadEvent,
	__close = onCloseEvent,
	__modify = modifyIconEvent
}

Manager.init(onClose, VERSION, connections)

onLoadEvent:Fire()