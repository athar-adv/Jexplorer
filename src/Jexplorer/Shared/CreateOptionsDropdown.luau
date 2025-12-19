--!strict

local VersionControl = require("../Editors/VersionControl")
local StyleEditor = require("../Editors/StyleEditor")
local SettingEditor = require("../Editors/SettingEditor")
local OrderEditor = require("../Editors/OrderEditor")
local InstanceVisibilityEditor = require("../Editors/InstanceVisibilityEditor")
local ContextMenuEditor = require("../Editors/ContextMenuEditor")

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

			PluginUI.createSeparator(topbarMenuDropdown)
			PluginUI.createButtonWithIcon(
				topbarMenuDropdown,
				"Refresh",
				"rbxassetid://13825976376",
				Vector2.zero, Vector2.zero,
				function()
					Manager.DeferredTaskScheduler.HierarchyChildrenMapNeedsUpdate = true
				end
			)
			PluginUI.createSeparator(topbarMenuDropdown)
			PluginUI.createButton(topbarMenuDropdown, "Save State", function()
				Manager.saveState()
				topbarMenuDropdown:Hide()
			end)
			PluginUI.createButton(topbarMenuDropdown, "Load State", function()
				local loaders = Manager.loadState(SavedState.load(Manager))
				for _, v: any in loaders do v() end
				topbarMenuDropdown:Hide()
			end)
			PluginUI.createButton(topbarMenuDropdown, "Reset State to Default", function()
				topbarMenuDropdown:Hide()
				for _, tab in state.Tabs do
					tab.Remove()
				end
				table.clear(state.Tabs)

				for _, repo in state.RepoProxies do
					repo.Remove()
				end
				table.clear(state.RepoProxies)

				local oldStyle = Manager.Style
				local loaders = Manager.loadState(SavedState.get_default(Manager))
				for _, v: any in loaders do
					v()
				end

				local customRules = {}
				for _, v in oldStyle:GetWithoutTags("Default") do
					table.insert(customRules, v)
				end
				oldStyle:Replace(Manager.Style)
				oldStyle:AddRules(customRules)

				Manager.DeferredTaskScheduler.HierarchyChildrenMapNeedsUpdate = true
			end)
			PluginUI.createButton(topbarMenuDropdown, "Reset Styles to Default", function()
				topbarMenuDropdown:Hide()

				local customRules = {}
				for _, v in Manager.Style:GetWithoutTags("Default") do
					table.insert(customRules, v)
				end
				local tokens, rules = require("./Defaults/DefaultStyle")(Manager)
				local style = Style.fromRulesTokens(rules, tokens)

				style:AddRules(customRules)
				Manager.Style:Replace(style)

				local style = Manager.Style

				Manager.VirtualScroller.update(Manager, false)
			end)
			PluginUI.createButton(topbarMenuDropdown, "Reset Settings to Default", function()
				topbarMenuDropdown:Hide()
				local settings = require("./Defaults/DefaultSettings")
				for _, t in settings do
					for k, v in t do
						Manager.setSetting(k, v.Default)
					end
				end

				Manager.VirtualScroller.update(Manager, false)
			end)
			PluginUI.createButton(topbarMenuDropdown, "Reset Order to Default", function()
				topbarMenuDropdown:Hide()

				OrderEditor.ClassPriorities = require("./Defaults/DefaultOrder")(Manager)
				OrderEditor.DefaultPriority = 999

				Manager.DeferredTaskScheduler.HierarchyChildrenMapNeedsUpdate = true
			end)
			PluginUI.createButton(topbarMenuDropdown, "Reset Versions", function()
				topbarMenuDropdown:Hide()

				VersionControl.Versions = {}
			end)
			PluginUI.createSeparator(topbarMenuDropdown)
			PluginUI.createButton(topbarMenuDropdown, "Kill Jexplorer", function()
				local onClose = state.OnClose
				if onClose then
					onClose()
				end
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