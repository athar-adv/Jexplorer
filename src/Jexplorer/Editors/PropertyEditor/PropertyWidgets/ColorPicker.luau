--!strict
local shared = script.Parent.Parent.Parent.Parent.Shared

local PluginColorPicker = require(shared.Vendor.PluginColorPicker)
local PluginUI = require(shared.PluginUI)

return PluginColorPicker.new(script:FindFirstAncestorOfClass("Plugin"), PluginUI.getId("JexplorerColor3Picker", true))