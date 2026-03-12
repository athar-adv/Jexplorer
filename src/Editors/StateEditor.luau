--!strict
--!optimize 2

local plugin = script:FindFirstAncestorOfClass("Plugin")

local main = script.Parent.Parent

local shared = main.Shared

local PluginUI = require(shared.PluginUI)
local UITemplates = require(shared.UITemplates)
local ItemGroup = require(shared.Vendor.ItemGroup)
local SavedState = require(shared.SavedState)
local Style = require(shared.Style)
local Constants = require(main.Constants)
local cleanup = ItemGroup.cleanup

local DefaultStyle = require(shared.Defaults.DefaultStyle)
local DefaultSettings = require(shared.Defaults.DefaultSettings)
local DefaultInvisible = require(shared.Defaults.DefaultInvisibleClasses)
local DefaultOrder = require(shared.Defaults.DefaultOrder)

local OrderEditor = require("./OrderEditor")
local VersionControl = require("./VersionControl")
local InstanceVisibilityEditor = require("./InstanceVisibilityEditor")

local Types = require(main.Types)

local PRINT_SAVEDSTATE_PREFIX = "SavedState: "

local StateEditor = {} :: Types.StateEditor

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

function StateEditor.init(Manager)
	local state = Manager.WidgetState
	local components = Manager.Components

	local jexplorerUi = state.JExplorerUI
	local topbar = jexplorerUi.Topbar
	
	local world = state.World
	
	local connections = state.Connections
	local instances = connections:extend(cleanup.destroy)

	local widget, mainframe = PluginUI.createEditorWidget(UITemplates.EditorFrame(), "StateEditor", "State Editor")
	StateEditor.Widget = widget
	Manager.Style:Link(widget)
	
	local function resetStyles()
		local customRules = {}
		for _, v in Manager.Style:GetWithoutTags("Default") do
			table.insert(customRules, v)
		end
		local tokens, rules = DefaultStyle(Manager)
		local style = Style.fromRulesTokens(rules, tokens)
		for _, token in style.Tokens do
			token:AddTag(Constants.DefaultTokenTag)
		end

		style:AddRules(customRules)
		Manager.Style:Replace(style)

		local style = Manager.Style
		style:UpdateTokens()

		Manager.VirtualScroller.update(Manager, false)
	end
	local function resetSettings()
		for _, t in DefaultSettings do
			for k, v in t do
				Manager.setSetting(k, v.Default)
			end
		end

		Manager.VirtualScroller.update(Manager, false, true)
	end
	local function resetOrder()
		OrderEditor.ClassPriorities = DefaultOrder(Manager)
		OrderEditor.DefaultPriority = 999

		Manager.DeferredTaskScheduler.ChildGraphDirty = true
	end
	local function resetVersions()
		VersionControl.Versions = {}
	end
	local function resetTabs()
		for _, v in table.clone(state.Tabs) do
			v.Remove()
		end
		table.clear(state.Tabs)
	end
	local function resetIconColors()
		for entity in world:query(components.FrameIconColor) do
			world:remove(entity, components.FrameIconColor)
			local frame = world:get(entity, components.Frame)
			if frame then
				Manager.ExplorerFrame.setExplorerFrameIconColor(Manager, frame, nil)
			end
		end
	end
	local function resetRepoProxies()
		for _, v in table.clone(state.RepoProxies) do
			v.Remove()
		end
		table.clear(state.RepoProxies)
	end
	local function resetInvisible()
		local tbl = {}
		for _, class in DefaultInvisible do
			InstanceVisibilityEditor.setInvisible(class, true)
			tbl[class] = true
		end
		InstanceVisibilityEditor.InvisibleClasses = tbl
		task.wait()
		Manager.VirtualScroller.rebuildAndUpdate(Manager, false)
	end
	
	local mainList = PluginUI.createItemListFromExisting(mainframe, mainframe.Items.Content, mainframe.Items)
	
	local function onsaved()
		print(PRINT_SAVEDSTATE_PREFIX, getPrintableTable(SavedState.load(Manager)))
	end
	
	local function onload()
		print(PRINT_SAVEDSTATE_PREFIX, getPrintableTable(state.SavedState))
	end
	
	PluginUI.createHeader(mainList, `Latest DataVersion: {SavedState.data_version}`)
	PluginUI.createButton(mainList, "Save State", function()
		local saver = Manager.saveState()
		saver.all()
		saver.save()
		
		onsaved()
		widget.Enabled = false
	end)
	PluginUI.createButton(mainList, "Load State", function()
		local loaders = Manager.loadState(SavedState.load(Manager))
		for _, v: any in loaders do v() end
		
		onload()
		widget.Enabled = false
	end)
	PluginUI.createButton(mainList, "Reset All To Default", function()
		resetStyles()
		resetSettings()
		resetOrder()
		resetVersions()
		resetIconColors()
		resetTabs()
		resetRepoProxies()
		resetInvisible()
	end)
	
	do
		local list = PluginUI.createDropDownItemList({
			Visible = true
		}, "SavedState: Styles")
		list:Parent(mainList)
		
		PluginUI.createButton(list, "Reset To Default", function()
			resetStyles()
			widget.Enabled = false
		end)
		PluginUI.createButton(list, "Save", function()
			local saver = Manager.saveState()
			saver.style()
			saver.save()
			
			onsaved()
			widget.Enabled = false
		end)
		PluginUI.createButton(list, "Load", function()
			local loaders = Manager.loadState(SavedState.load(Manager))
			Manager.Style:Replace(loaders.style())
			
			onload()
			widget.Enabled = false
		end)
	end
	do
		local list = PluginUI.createDropDownItemList({
			Visible = true
		}, "SavedState: Settings")
		list:Parent(mainList)

		PluginUI.createButton(list, "Reset To Default", function()
			resetSettings()
			widget.Enabled = false
		end)
		PluginUI.createButton(list, "Save", function()
			local saver = Manager.saveState()
			saver.settings()
			saver.save()
			
			onsaved()
			widget.Enabled = false
		end)
		PluginUI.createButton(list, "Load", function()
			local loaders = Manager.loadState(SavedState.load(Manager))
			loaders.settings()
			
			onload()
			widget.Enabled = false
		end)
	end
	do
		local list = PluginUI.createDropDownItemList({
			Visible = true
		}, "SavedState: Sorting Order")
		list:Parent(mainList)

		PluginUI.createButton(list, "Reset To Default", function()
			resetOrder()
			widget.Enabled = false
		end)
		PluginUI.createButton(list, "Save", function()
			local saver = Manager.saveState()
			saver.order()
			saver.save()
			
			onsaved()
			widget.Enabled = false
		end)
		PluginUI.createButton(list, "Load", function()
			local loaders = Manager.loadState(SavedState.load(Manager))
			loaders.order()
			
			onload()
			widget.Enabled = false
		end)
	end
	do
		local list = PluginUI.createDropDownItemList({
			Visible = true
		}, "SavedState: Versions")
		list:Parent(mainList)

		PluginUI.createButton(list, "Reset To Default", function()
			resetVersions()
			widget.Enabled = false
		end)
		PluginUI.createButton(list, "Save", function()
			local saver = Manager.saveState()
			saver.versions()
			saver.save()
			
			onsaved()
			widget.Enabled = false
		end)
		PluginUI.createButton(list, "Load", function()
			local loaders = Manager.loadState(SavedState.load(Manager))
			VersionControl.Versions = loaders.versions()
			
			onload()
			widget.Enabled = false
		end)
	end
	do
		local list = PluginUI.createDropDownItemList({
			Visible = true
		}, "SavedState: Icon Colors")
		list:Parent(mainList)

		PluginUI.createButton(list, "Reset To Default", function()
			resetIconColors()
			widget.Enabled = false
		end)
		PluginUI.createButton(list, "Save", function()
			local saver = Manager.saveState()
			saver.icon_colors()
			saver.save()
			
			onsaved()
			widget.Enabled = false
		end)
		PluginUI.createButton(list, "Load", function()
			local loaders = Manager.loadState(SavedState.load(Manager))
			VersionControl.Versions = loaders.icon_colors()
			
			onload()
			widget.Enabled = false
		end)
	end
	do
		local list = PluginUI.createDropDownItemList({
			Visible = true
		}, "SavedState: Tabs")
		list:Parent(mainList)

		PluginUI.createButton(list, "Reset To Default", function()
			resetTabs()
			widget.Enabled = false
		end)
		PluginUI.createButton(list, "Save", function()
			local saver = Manager.saveState()
			saver.tabs()
			saver.save()
			
			onsaved()
			widget.Enabled = false
		end)
		PluginUI.createButton(list, "Load", function()
			local loaders = Manager.loadState(SavedState.load(Manager))
			VersionControl.Versions = loaders.tabs()
			
			onload()
			widget.Enabled = false
		end)
	end
	do
		local list = PluginUI.createDropDownItemList({
			Visible = true
		}, "SavedState: Repo Proxies")
		list:Parent(mainList)

		PluginUI.createButton(list, "Reset To Default", function()
			resetRepoProxies()
			widget.Enabled = false
		end)
		PluginUI.createButton(list, "Save", function()
			local saver = Manager.saveState()
			saver.repo_proxies()
			saver.save()
			
			onsaved()
			widget.Enabled = false
		end)
		PluginUI.createButton(list, "Load", function()
			local loaders = Manager.loadState(SavedState.load(Manager))
			VersionControl.Versions = loaders.repo_proxies()
			
			onload()
			widget.Enabled = false
		end)
	end
	do
		local list = PluginUI.createDropDownItemList({
			Visible = true
		}, "SavedState: Invisible Classes")
		list:Parent(mainList)

		PluginUI.createButton(list, "Reset To Default", function()
			resetInvisible()
			widget.Enabled = false
		end)
		PluginUI.createButton(list, "Save", function()
			local saver = Manager.saveState()
			saver.invisible()
			saver.save()
			
			onsaved()
			widget.Enabled = false
		end)
		PluginUI.createButton(list, "Load", function()
			local loaders = Manager.loadState(SavedState.load(Manager))
			VersionControl.Versions = loaders.invisible()
			
			onload()
			widget.Enabled = false
		end)
	end
end

return StateEditor