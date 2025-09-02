--!strict
--!optimize 2

local plugin = script:FindFirstAncestorOfClass("Plugin")

local HttpService = game:GetService("HttpService")

local main = script.Parent.Parent

local utilities = main.Utilities
local ui = main.UI

local PluginUI = require(utilities.PluginUI)
local ClassIcon = require(utilities.ClassIcon)

local Types = require(main.Types)

local items = {}

local init = false

local InstanceVisibilityEditor = {
	InvisibleClasses = {},
	InvisibleInstances = {}
} :: Types.InstanceVisibilityEditor

function InstanceVisibilityEditor.setVisible(className, visible)
	if not init then return end
	local item = items[className]
	assert(item)
	
	item.toggle(visible)
end

function InstanceVisibilityEditor.init(Manager)
	init = true
	local state = Manager.WidgetState
	local components = Manager.Components
	
	local jexplorerUi = state.JExplorerUI
	local topbar = jexplorerUi.Topbar
	
	local connections = state.Connections
	local instances = connections:Extend("Destroy")
	
	local widget, mainframe = PluginUI.createEditorWidget(ui.EditorFrame, "InstanceVisibilityEditor", "Instance Visibility Editor")
	InstanceVisibilityEditor.Widget = widget
	Manager.Style:Link(widget)
	
	local list = PluginUI.createItemListFromExisting(mainframe, mainframe.Items)
	
	local classVisibilityDropdown = PluginUI.createDropDownItemList({Name = "InvisibleClassesDropdown", Visible = true}, "Invisible Classes")
	classVisibilityDropdown:Parent(list)
	
	local i = 1
	local jsonBox
	
	for className in Manager.APIMap do
		local icon = ClassIcon.getIcon(className)
		if not icon then continue end
		
		local _visible = InstanceVisibilityEditor.InvisibleClasses[className]
		local visible = if _visible ~= nil then not _visible else true
		local button
		
		if InstanceVisibilityEditor.InvisibleClasses[className] == nil then
			InstanceVisibilityEditor.InvisibleClasses[className] = not visible
		end
		
		local function toggle(_visible: boolean?)
			visible = if _visible ~= nil then _visible else not visible
			if visible then
				button.Instance:RemoveTag("JEXP_DarkBackground")
				button.Instance:AddTag("JEXP_Background")
			else
				button.Instance:RemoveTag("JEXP_Background")
				button.Instance:AddTag("JEXP_DarkBackground")
			end

			InstanceVisibilityEditor.InvisibleClasses[className] = not visible
			if _visible == nil then
				local jsonTbl = {}
				for k, v in InstanceVisibilityEditor.InvisibleClasses do
					jsonTbl[k] = not v
				end
				jsonBox:Set(HttpService:JSONEncode(jsonTbl))
				Manager.updateVirtualScroller()
			end
		end
		
		button = PluginUI.createButtonWithIcon(classVisibilityDropdown, className, icon.Image, icon.ImageRectOffset, icon.ImageRectSize, toggle)
		if not visible then
			button.Instance:RemoveTag("JEXP_Background")
			button.Instance:AddTag("JEXP_DarkBackground")
		end
		
		items[className] = {
			className = className,
			button = button.Instance,
			toggle = toggle
		}
		i += 1
	end
	
	local jsonTbl = {}
	for k, v in InstanceVisibilityEditor.InvisibleClasses do
		jsonTbl[k] = not v
	end
	jsonBox = PluginUI.createAttributeBox(list, "Visible Classes JSON", HttpService:JSONEncode(jsonTbl), function(newValue)
		if newValue == "" then
			InstanceVisibilityEditor.InvisibleClasses = {}
			Manager.updateVirtualScroller()
			return
		end
		
		local tbl = HttpService:JSONDecode(newValue)
		for className, item in items do
			local visible = tbl[className]
			if visible == nil then
				visible = false
			end
			
			item.toggle(visible)
		end
		Manager.updateVirtualScroller()
	end)
end

return InstanceVisibilityEditor