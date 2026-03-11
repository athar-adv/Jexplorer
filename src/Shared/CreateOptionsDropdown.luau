--!strict

local plugin = script:FindFirstAncestorOfClass("Plugin")

local VersionControl = require("../Editors/VersionControl")
local StyleEditor = require("../Editors/StyleEditor")
local SettingEditor = require("../Editors/SettingEditor")
local OrderEditor = require("../Editors/OrderEditor")
local InstanceVisibilityEditor = require("../Editors/InstanceVisibilityEditor")
local ContextMenuEditor = require("../Editors/ContextMenuEditor")
local JextensionEditor = require("../Editors/JextensionEditor")
local StateEditor = require("../Editors/StateEditor")
local ExplorerFrameEditor = require("../Editors/ExplorerFrameEditor")

local UniPlugin = require("../UniPlugin")(plugin)

local Types = require("../Types")

local PluginUI = require("./PluginUI")
local SavedState = require("./SavedState")
local Style = require("./Style")

local studioSettings = settings().Studio

local IS_EDIT = game:GetService("RunService"):IsEdit()

return function(Manager: Types.Manager, components: Types.Components, topbar: Instance)
	local state = Manager.WidgetState
	local topbarMenuDropdown do
		topbarMenuDropdown = PluginUI.createItemList {
			Name = "TopbarMenuDropdown"
		}

		local theme = assert(studioSettings.Theme) :: StudioTheme
		local backgroundColor = theme:GetColor(Enum.StudioStyleGuideColor.MainBackground)
		local isLight = backgroundColor.R > 0.5
		local themeExtension = isLight and "Light" or "Dark"

		local WIP_COLOR = Color3.fromRGB(79, 79, 79)
		if IS_EDIT then
			PluginUI.createButtonWithIcon(
				topbarMenuDropdown,
				"Open Version Control",
				`rbxasset://studio_svg_textures/Shared/InsertableObjects/{themeExtension}/Standard/PackageLink.png`,
				Vector2.zero, Vector2.new(16, 16),
				function()
					VersionControl.Widget.Enabled = true
					topbarMenuDropdown:Hide()
				end
			)
			PluginUI.createSeparator(topbarMenuDropdown)
			PluginUI.createButtonWithIcon(
				topbarMenuDropdown, 
				"Open Style Editor", 
				`rbxasset://studio_svg_textures/Shared/InsertableObjects/{themeExtension}/Standard/StyleSheet.png`, 
				Vector2.zero, Vector2.new(16, 16), 
				function()
					StyleEditor.Widget.Enabled = true
					topbarMenuDropdown:Hide()
				end
			)
		end
		PluginUI.createButtonWithIcon(
			topbarMenuDropdown,
			"Open Setting Editor",
			`rbxasset://studio_svg_textures/Shared/InsertableObjects/{themeExtension}/Standard/Configuration.png`,
			Vector2.zero, Vector2.new(16, 16),
			function()
				SettingEditor.Widget.Enabled = true
				topbarMenuDropdown:Hide()
			end
		)
		if IS_EDIT then
			PluginUI.createButtonWithIcon(
				topbarMenuDropdown,
				"Open Instance Visibility Editor",
				`rbxasset://studio_svg_textures/Shared/InsertableObjects/{themeExtension}/Standard/SelectionBox.png`,
				Vector2.zero, Vector2.new(16, 16),
				function()
					InstanceVisibilityEditor.Widget.Enabled = true
					topbarMenuDropdown:Hide()
				end
			)
			PluginUI.createButtonWithIcon(
				topbarMenuDropdown,
				"Open Order Editor",
				`rbxasset://studio_svg_textures/Shared/InsertableObjects/{themeExtension}/Standard/UIListLayout.png`,
				Vector2.zero, Vector2.new(16, 16),
				function()
					OrderEditor.Widget.Enabled = true
					topbarMenuDropdown:Hide()
				end
			)
			PluginUI.createButtonWithIcon(
				topbarMenuDropdown, 
				"Open Context Menu Editor",
				`rbxasset://studio_svg_textures/Shared/InsertableObjects/{themeExtension}/Standard/UITableLayout.png`,
				Vector2.zero, Vector2.new(16, 16),
				function()
					ContextMenuEditor.Widget.Enabled = true
					topbarMenuDropdown:Hide()
				end
			)
			PluginUI.createButtonWithIcon(
				topbarMenuDropdown, 
				"Open Jextension Editor",
				`rbxasset://studio_svg_textures/Shared/InsertableObjects/{themeExtension}/Standard/Weld.png`,
				Vector2.zero, Vector2.new(16, 16),
				function()
					JextensionEditor.Widget.Enabled = true
					topbarMenuDropdown:Hide()
				end
			)
			PluginUI.createButtonWithIcon(
				topbarMenuDropdown, 
				"Open State Editor",
				`rbxasset://studio_svg_textures/Shared/InsertableObjects/{themeExtension}/Standard/Actor.png`,
				Vector2.zero, Vector2.new(16, 16),
				function()
					StateEditor.Widget.Enabled = true
					topbarMenuDropdown:Hide()
				end
			)
			PluginUI.createButtonWithIcon(
				topbarMenuDropdown, 
				"Open ExplorerFrame Editor",
				`rbxasset://studio_svg_textures/Shared/InsertableObjects/{themeExtension}/Standard/Frame.png`,
				Vector2.zero, Vector2.new(16, 16),
				function()
					ExplorerFrameEditor.Widget.Enabled = true
					topbarMenuDropdown:Hide()
				end
			)

			PluginUI.createSeparator(topbarMenuDropdown)
			PluginUI.createButtonWithIcon(
				topbarMenuDropdown,
				"Refresh",
				"rbxassetid://13825976376",
				Vector2.zero, Vector2.zero,
				function()
					Manager.VirtualScroller.rebuildAndUpdate(Manager, false)
				end
			)
			PluginUI.createButton(topbarMenuDropdown, "Reassign ExplorerFrames", function()
				local world = state.World
				for entity, frame in world:query(components.Frame):iter() do
					Manager.ExplorerFrame.queueForExplorerFrameReuse(Manager, frame)
				end
				task.wait(1/30)
				Manager.VirtualScroller.update(Manager, false, true)
			end)
			PluginUI.createSeparator(topbarMenuDropdown)
			PluginUI.createButton(topbarMenuDropdown, "Save State", function()
				topbarMenuDropdown:Hide()
				local saver = Manager.saveState()
				saver.all()
				saver.save()
				
				local PRINT_SAVEDSTATE_PREFIX = "SavedState: "
				local function getPrintableTable(tbl): {[any]: any}
					local newtbl = {}
					for k, v in tbl do
						if typeof(v) == "table" then
							if #v > 10 then
								v = "Array"
							else
								v = getPrintableTable(v)
							end
						end
						newtbl[k] = v
					end
					return newtbl
				end
				local function onsaved()
					print(PRINT_SAVEDSTATE_PREFIX, getPrintableTable(SavedState.load(Manager)))
				end
				onsaved()
			end)
			PluginUI.createButton(topbarMenuDropdown, "Kill Jexplorer", function()
				UniPlugin:close()
				plugin:Destroy()
			end)
			PluginUI.createButton(topbarMenuDropdown, "Insert Plugin Src", function()
				plugin.Parent = workspace
			end)
		end
		topbarMenuDropdown.Backdrop.MouseLeave:Connect(function()
			topbarMenuDropdown:Hide()
		end)
		topbarMenuDropdown.Backdrop.Parent = topbar
	end
	return topbarMenuDropdown
end