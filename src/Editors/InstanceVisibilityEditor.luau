--!strict
--!optimize 2
local plugin = script:FindFirstAncestorOfClass("Plugin")
local ReflectionService = game:GetService("ReflectionService")
local HttpService = game:GetService("HttpService")

local main = script.Parent.Parent
local shared = main.Shared

local UITemplates = require(shared.UITemplates)
local PluginUI = require(shared.PluginUI)
local ClassIcon = require(shared.Small.ClassIcon)
local ItemGroup = require(shared.Vendor.ItemGroup)
local cleanup = ItemGroup.cleanup
local Types = require(main.Types)

local items = {}
local init = false

local InstanceVisibilityEditor = {
	InvisibleClasses = {},
	InvisibleInstances = {}
} :: Types.InstanceVisibilityEditor

function InstanceVisibilityEditor.setInvisible(className, invisible)
	if not init then return false end
	local item = items[className]
	if not item then
		warn(`class '{className}' has no designated item.`)
		return false
	end
	item.toggle(invisible)
	return true
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

	local list = PluginUI.createItemListFromExisting(mainframe, mainframe.Items.Content, mainframe.Items)

	local classVisibilityDropdown = PluginUI.createDropDownItemList({Name = "InvisibleClassesDropdown", Visible = true}, "Invisible Classes")
	classVisibilityDropdown:Parent(list)
	
	local instIcon = ClassIcon.getIcon("Instance")
	assert(instIcon)
	
	local jsonBox
	local thread = task.spawn(function()
		local i = 1
		local classes = ReflectionService:GetClasses({
			Security = SecurityCapabilities.new(unpack(Enum.SecurityCapability:GetEnumItems()))
		})
		
		local customclasses = {}
		local function insertclass(f: ReflectedClass)
			table.insert(customclasses, f)
		end
		
		insertclass({
			Name = "InstanceFileSyncService",
			Permits = {},
			Subclasses = {}
		})
		
		local buttons: {GuiObject} = {}
		local function onClass(info: ReflectedClass)
			local className = info.Name
			local icon = ClassIcon.getIcon(className) or instIcon
			--if i % 2 == 0 then task.wait(0.1) end

			-- Now invisible is the primary state
			local invisible = InstanceVisibilityEditor.InvisibleClasses[className]
			if invisible == nil then
				invisible = false
			end

			local button

			local function toggle(_invisible: boolean?)
				invisible = if _invisible ~= nil then _invisible else not invisible
				if invisible then
					-- Invisible: dark background
					button.Instance:RemoveTag("JEXP_Background")
					button.Instance.Label:AddTag("JEXP_SelectedColor")
					button.Instance.Label:RemoveTag("JEXP_Text")
					button.Instance:AddTag("JEXP_SelectedColor")
				else
					-- Visible: normal background
					button.Instance:RemoveTag("JEXP_SelectedColor")
					button.Instance.Label:RemoveTag("JEXP_SelectedColor")
					button.Instance.Label:AddTag("JEXP_Text")
					button.Instance:AddTag("JEXP_Background")
				end
				InstanceVisibilityEditor.InvisibleClasses[className] = (invisible or nil) :: any
				if _invisible == nil then
					-- Update JSON box with invisible classes
					jsonBox:Set(HttpService:JSONEncode(InstanceVisibilityEditor.InvisibleClasses))
					Manager.VirtualScroller.rebuildAndUpdate(Manager, false)
				end
			end

			button = PluginUI.createButtonWithIcon(nil, className, icon.Image, icon.ImageRectOffset, icon.ImageRectSize, toggle)
			table.insert(buttons, button.Instance)
			if invisible then
				button.Instance:RemoveTag("JEXP_Background")
				button.Instance.Label:RemoveTag("JEXP_Text")
				button.Instance:AddTag("JEXP_SelectedColor")
				button.Instance.Label:AddTag("JEXP_SelectedColor")
			end

			items[className] = {
				className = className,
				button = button.Instance,
				toggle = toggle
			}
			i += 1
		end
		
		for _, info in customclasses do
			onClass(info)
		end
		for _, info in classes do
			onClass(info)
			task.wait()
		end
		classVisibilityDropdown:AddBulkItem(buttons)
	end)
	connections:extend(task.cancel, {thread})

	-- JSON box now stores invisible classes directly
	jsonBox = PluginUI.createAttributeBox(list, "Invisible Classes JSON", HttpService:JSONEncode(InstanceVisibilityEditor.InvisibleClasses), function(newValue)
		if newValue == "" then
			InstanceVisibilityEditor.InvisibleClasses = {}
			Manager.VirtualScroller.update(Manager, false)
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
		Manager.VirtualScroller.rebuildAndUpdate(Manager, false)
	end)
end

return InstanceVisibilityEditor