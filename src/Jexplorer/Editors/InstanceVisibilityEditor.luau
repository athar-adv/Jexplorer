--!strict
--!optimize 2
local plugin = script:FindFirstAncestorOfClass("Plugin")
local ReflectionService = game:GetService("ReflectionService")
local HttpService = game:GetService("HttpService")

local main = script.Parent.Parent
local utilities = main.Utilities

local UITemplates = require(utilities.UITemplates)
local PluginUI = require(utilities.PluginUI)
local ClassIcon = require(utilities.Small.ClassIcon)
local ItemGroup = require(utilities.Vendor.ItemGroup)
local cleanup = ItemGroup.cleanup
local Types = require(main.Types)

local items = {}
local init = false

local InstanceVisibilityEditor = {
	InvisibleClasses = {},
	InvisibleInstances = {}
} :: Types.InstanceVisibilityEditor

function InstanceVisibilityEditor.setInvisible(className, invisible)
	if not init then return end
	local item = items[className]
	assert(item)

	item.toggle(invisible)
end

function InstanceVisibilityEditor.init(Manager)
	init = true
	local state = Manager.WidgetState
	local components = Manager.Components

	local jexplorerUi = state.JExplorerUI
	local topbar = jexplorerUi.Topbar

	local connections = state.Connections
	local instances = connections:extend(cleanup.destroy)

	local widget, mainframe = PluginUI.createEditorWidget(UITemplates.EditorFrame(), "InstanceVisibilityEditor", "Instance Visibility Editor")
	InstanceVisibilityEditor.Widget = widget
	Manager.Style:Link(widget)

	local list = PluginUI.createItemListFromExisting(mainframe, mainframe.Items)

	local classVisibilityDropdown = PluginUI.createDropDownItemList({Name = "InvisibleClassesDropdown", Visible = true}, "Invisible Classes")
	classVisibilityDropdown:Parent(list)

	local i = 1
	local jsonBox
	for _, info in ReflectionService:GetClasses() do
		local className = info.Name
		local icon = ClassIcon.getIcon(className)
		if not icon then continue end

		-- Now invisible is the primary state
		local invisible = InstanceVisibilityEditor.InvisibleClasses[className]
		if invisible == nil then
			invisible = false
			InstanceVisibilityEditor.InvisibleClasses[className] = false
		end

		local button

		local function toggle(_invisible: boolean?)
			invisible = if _invisible ~= nil then _invisible else not invisible
			if invisible then
				-- Invisible: dark background
				button.Instance:RemoveTag("JEXP_Background")
				button.Instance:AddTag("JEXP_DarkBackground")
			else
				-- Visible: normal background
				button.Instance:RemoveTag("JEXP_DarkBackground")
				button.Instance:AddTag("JEXP_Background")
			end
			InstanceVisibilityEditor.InvisibleClasses[className] = invisible
			if _invisible == nil then
				-- Update JSON box with invisible classes
				jsonBox:Set(HttpService:JSONEncode(InstanceVisibilityEditor.InvisibleClasses))
				Manager.updateVirtualScroller()
			end
		end

		button = PluginUI.createButtonWithIcon(classVisibilityDropdown, className, icon.Image, icon.ImageRectOffset, icon.ImageRectSize, toggle)
		if invisible then
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

	-- JSON box now stores invisible classes directly
	jsonBox = PluginUI.createAttributeBox(list, "Invisible Classes JSON", HttpService:JSONEncode(InstanceVisibilityEditor.InvisibleClasses), function(newValue)
		if newValue == "" then
			InstanceVisibilityEditor.InvisibleClasses = {}
			Manager.updateVirtualScroller()
			return
		end

		local tbl = HttpService:JSONDecode(newValue)
		for className, item in items do
			local invisible = tbl[className]
			if invisible == nil then
				invisible = false
			end

			item.toggle(invisible)
		end
		Manager.updateVirtualScroller()
	end)
end

return InstanceVisibilityEditor