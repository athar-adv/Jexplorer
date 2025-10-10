local utilities = script.Parent.Parent.Parent.Parent.Utilities

local PluginColorPicker = require(utilities.PluginColorPicker)
local PluginUI = require(utilities.PluginUI)

return PluginColorPicker.new(script:FindFirstAncestorOfClass("Plugin"), PluginUI.getId("JexplorerColor3Picker", true))