--!strict

local global = shared
local plugin = script:FindFirstAncestorOfClass("Plugin")

local HttpService = game:GetService("HttpService")
local ReflectionService = game:GetService("ReflectionService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local StudioService = game:GetService("StudioService")
local SerializationService = game:GetService("SerializationService")
local CollectionService = game:GetService("CollectionService")
local ScriptEditorService = game:GetService("ScriptEditorService")

local Jecs = require("./Jecs")
local Types = require("./Types")

type World = Types.World
type ExplorerFrame = Types.ExplorerFrame
type ExplorerEntity = Types.ExplorerEntity
type Tab = Types.Tab

local ItemGroup = require("./Shared/Vendor/ItemGroup")
local PluginUI = require("./Shared/PluginUI")
local UDF = require("./Shared/UDF")
local JQL = require("./Shared/JQL")
local Style = require("./Shared/Style")
local SavedState = require("./Shared/SavedState")
local UITemplates = require("./Shared/UITemplates")
local ClassIcon = require("./Shared/Small/ClassIcon")
local RawInst = require("./Shared/Small/RawInst")

local SettingEditor = require("./Editors/SettingEditor")
local StyleEditor = require("./Editors/StyleEditor")
local VersionControl = require("./Editors/VersionControl")
local PropertyEditor = require("./Editors/PropertyEditor")
local OrderEditor = require("./Editors/OrderEditor")
local InstanceVisibilityEditor = require("./Editors/InstanceVisibilityEditor")
local ContextMenuEditor = require("./Editors/ContextMenuEditor")

local HierarchyState = require("./Shared/HierarchyState")
local ExplorerFrame = require("./Shared/ExplorerFrame")
local VirtualScroller = require("./Shared/VirtualScroller")
local InsertMenu = require("./Shared/InsertMenu")
local CreateOptionsDropdown = require("./Shared/CreateOptionsDropdown")

local rule = Style.rule
local cleanup = ItemGroup.cleanup
local profilebegin, profileend = debug.profilebegin, debug.profileend
local getId = PluginUI.getId
local rawnewindex = RawInst.rawnewindex

local downKeys: {[Enum.KeyCode]: boolean?} = {}
local activeInputs: {[Enum.UserInputType]: boolean?} = {}

local onTagAddedListeners = {}
local onTagRemovedListeners = {}

local classComponentCache: {[string]: {Jecs.Id}} = {}

local studioSettings = settings().Studio
local pluginMouse = plugin:GetMouse()

local sharedTabState = {
	isCurrentlyPickingTabRoots = false,
	tabInsertListener = nil :: RBXScriptConnection?,
	currentlyOpenTab = nil :: Tab?,
	contextTargetTab = nil :: Tab?
}

local PLACE_ID = tostring(game.PlaceId)
local IS_EDIT = game:GetService("RunService"):IsEdit()

local components: Types.Components do
	local comp = Jecs.component
	local tag = Jecs.tag
	
	components = {
		Selected = tag(),
		Expanded = tag(),
		AncestryLocked = tag(),
		ArrowInvisible = tag(),
		QueryAncestor = tag(),
		QueryExpanded = tag(),
		QueryInvisible = tag(),
		Invisible = tag(),
		IsQueried = tag(),
		PendingChanges = tag(),
		Deleted = tag(),
		DisplayTopLevel = tag(),
		
		CleanupTicket = comp(),
		DeletionTicket = comp(),
		ChildAddedTicket = comp(),
		ChildMovedTicket = comp(),
		CreationTicket = comp(),
		PropAssignTicket = comp(),
		FrameReuseTicket = comp(),
		FrameTagAssignTicket = comp(),
		
		FRAMEWORLD_FrameSetParentTicket = comp(),

		Instance = comp(),
		Frame = comp(),
		Entity = comp(),
		FrameState = comp(),

		Connections = comp(),
		FavoriteProxy = comp(),
		FavoriteProxySource = comp(),
		ScriptErrors = comp(),
		ScriptWarns = comp(),
		QueryLinkedEntities = comp(),
		LinkedQueryEntity = comp(),
		ParentTabs = comp(),
	}
end

local Manager = {
	CleanupFns = ItemGroup.cleanup,
	Components = components,
	
	QueryTagMap = {},
	QueryCtMap = {},
	
	ExplorerFrame = ExplorerFrame,
	HierarchyState = HierarchyState,
	VirtualScroller = VirtualScroller,
	InsertMenu = InsertMenu,
	DeferredTaskScheduler = {
		HierarchyChildrenMapNeedsUpdate = false
	},
	
	InstanceToEntity = {},
	FrameToInstanceFrame = {},

	ChildAmountCache = {},
	ClassNameCache = {},
	NameCache = {},
	DebugIdToInstance = setmetatable({}, {__mode = "v"}) :: any,
	TabFrameToTab = {}
} :: Types.Manager

local function copySelection(world: World)
	local state = Manager.WidgetState
	local components = Manager.Components

	local instances = {}
	for _, entity in state.CurrentSelection do
		local inst = world:get(entity, components.Instance)
		if not inst then continue end
		table.insert(instances, inst)
	end
	plugin:SetSetting("CopiedInstances", 
		HttpService:JSONEncode(
			SerializationService:SerializeInstancesAsync(instances)
		)
	)
end

local function getCommonAncestor(instances: {Instance}): Instance?
	if #instances == 0 then
		return nil
	elseif #instances == 1 then
		return instances[1].Parent
	end

	local ancestorChains = {}
	for _, inst in instances do
		local ancestors = {}
		while inst do
			table.insert(ancestors, inst)
			if not inst.Parent then break end
			inst = inst.Parent
		end
		table.insert(ancestorChains, ancestors)
	end

	for i, chain in ancestorChains do
		local reversed = {}
		for j = #chain, 1, -1 do
			table.insert(reversed, chain[j])
		end
		ancestorChains[i] = reversed
	end

	local lca = nil
	local index = 1
	while true do
		local current = ancestorChains[1][index]
		if not current then
			break
		end

		for i = 2, #ancestorChains do
			if ancestorChains[i][index] ~= current then
				return lca
			end
		end

		lca = current
		index += 1
	end

	return lca
end

local function pasteCopiedInstances(world: World)
	local state = Manager.WidgetState
	local components = Manager.Components
	local targetEntity = state.ContextTarget
	if not targetEntity then return end
	local targetInstance = world:get(targetEntity, components.Instance)
	assert(targetInstance, "target instance not found")

	local success, instances = pcall(
		SerializationService.DeserializeInstancesAsync, SerializationService, 
		HttpService:JSONDecode(
			plugin:GetSetting("CopiedInstances")
		)
	)

	if not success then return end
	local id = ChangeHistoryService:TryBeginRecording("Paste", "Paste")

	for _, v in instances do
		local success = pcall(function()
			v.Parent = targetInstance
		end)
		if not success then
			if id then
				ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Cancel)
			end
			return
		end
	end

	Manager.DeferredTaskScheduler.HierarchyChildrenMapNeedsUpdate = true
	if id then
		ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
	end
end

local function getGlobalConfigValue(k: string): any?
	local configs = global.JexplorerConfigs
	if configs then
		return configs[k]
	end
	return nil
end

local function computedtbl(fn: (ser: {[any]: any}) -> ())
	local tbl = {}
	fn(tbl :: any)
	return tbl :: any
end

local function ChildOf(c: ExplorerEntity)
	return Jecs.pair(Jecs.ChildOf, c)
end

local function getPropertyCt(world: World, propName: string)
	local ct = Manager.QueryCtMap[propName]
	if not ct then
		ct = world:entity()
		Manager.QueryCtMap[propName] = ct
	end
	return ct
end

local function createPluginAction(actionId: string, text: string, statusTip: string, iconId: string?, allowBinding: boolean?)
	local action = plugin:CreatePluginAction(
		actionId, text, statusTip, iconId, allowBinding
	)
	action.Name = actionId
	return action
end

function Manager.triggerEscapeTarget()
	local state = Manager.WidgetState
	local world = state.World
	local components = Manager.Components

	profilebegin("Jexplorer::ESCAPE (unselect all)")
	if state.CurrentlyRenaming then
		local frame = world:get(state.CurrentlyRenaming, components.Frame)
		if not frame then return end

		local inst = Manager.frameOf(frame)
		if inst then
			inst.Main.InstanceName:ReleaseFocus(false)
		end
		state.CurrentlyRenaming = nil
		return
	end

	for entityId in world:query(components.Instance, components.Selected):iter() do
		world:remove(entityId, components.Selected)
	end

	ExplorerFrame.updateSelectionVisuals(Manager, true)
	state.LastSelectedEntity = nil
	profileend()
end

function Manager.triggerDeleteTarget()
	local state = Manager.WidgetState
	local world = state.World
	local components = Manager.Components

	local id = ChangeHistoryService:TryBeginRecording("Destroy", "Destroy")
	profilebegin("Jexplorer::BACKSPACE/DELETE (remove)")

	local selection = state.CurrentSelection
	for _, entity in selection do
		world:add(entity, components.AncestryLocked)
	end
	for _, entity in selection do
		world:add(entity, components.Deleted)
		local instance = world:get(entity, components.Instance)
		assert(instance)
		
		instance.Parent = nil
		VirtualScroller.invalidateEntityHeightCache(Manager, entity)
		Manager.updateParent(entity, nil)
		HierarchyState.cleanupEntity(Manager, entity)
	end
	
	HierarchyState.flushEntityCleanupQueue(Manager)
	Manager.DeferredTaskScheduler.HierarchyChildrenMapNeedsUpdate = true

	for _, entity in selection do
		world:remove(entity, components.AncestryLocked)
	end

	if id then
		ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
	end

	profileend()
end

function Manager.triggerDuplicateTarget()
	local state = Manager.WidgetState
	local world = state.World
	local components = Manager.Components

	local id = ChangeHistoryService:TryBeginRecording("Clone", "Clone")
	profilebegin("Jexplorer::D (duplicate)")

	local cloned = {}
	for _, entity in state.CurrentSelection do
		local parent = Manager.parentOf(entity)
		if parent == nil then continue end

		local instance = world:get(entity, components.Instance)
		if not instance then continue end
		
		world:add(parent, components.AncestryLocked)

		local clone = instance:Clone()
		--clone.Parent = instance.Parent
		clone.Parent = instance.Parent
		local cloneEntity = HierarchyState.createInstanceEntity(Manager, clone, parent)
		VirtualScroller.invalidateEntityHeightCache(Manager, cloneEntity)

		world:remove(parent, components.AncestryLocked)
	end

	Manager.DeferredTaskScheduler.HierarchyChildrenMapNeedsUpdate = true	
	if id then
		ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
	end

	profileend()
end

function Manager.isExplorerEntityInvisible(entity: ExplorerEntity)
	profilebegin("Micro::isEntityInvisible")
	local world = Manager.WidgetState.World
	local components = Manager.Components
	
	local is =
		world:has(entity, components.Invisible)
		or	world:has(entity, components.QueryInvisible)
		or	InstanceVisibilityEditor.InvisibleClasses[Manager.ClassNameCache[entity]]
	profileend()
	return is
end

function Manager.isExplorerEntityDeleted(entity: ExplorerEntity)
	--profilebegin("Micro::isEntityGone")
	local world = Manager.WidgetState.World
	local components = Manager.Components
	local is = world:has(entity, components.Deleted) or not world:contains(entity)
	--profileend()
	return is
end

function Manager.isExplorerEntityExpanded(entity: ExplorerEntity)
	local world = Manager.WidgetState.World
	local components = Manager.Components
	return world:has(entity, components.Expanded) or world:has(entity, components.QueryExpanded)
end

function Manager.updateParent(entity: ExplorerEntity, new_parent: ExplorerEntity?)
	local world = Manager.WidgetState.World
	local childAmountCache = Manager.ChildAmountCache
	
	local old_parent = Manager.parentOf(entity)
	if old_parent then
		world:remove(entity, ChildOf(old_parent))
		if childAmountCache[old_parent] then
			childAmountCache[old_parent] -= 1
		end
	end
	if new_parent then
		world:add(entity, ChildOf(new_parent))
		if childAmountCache[new_parent] then
			childAmountCache[new_parent] += 1
		end
	end
end

function Manager.parentOf(ent: ExplorerEntity): ExplorerEntity?
	local world = Manager.WidgetState.World
	local components = Manager.Components

	if world:has(ent, components.DisplayTopLevel) then
		return nil
	else
		return world:parent(ent)
	end
end

function Manager.instanceOf(ent: ExplorerEntity): Instance?
	local world = Manager.WidgetState.World
	local components = Manager.Components
	return world:get(ent, components.Instance)
end

function Manager.frameOf(ent: ExplorerEntity): typeof(script.Parent.__legacy.UI.InstanceFrame)?
	local world = Manager.WidgetState.FrameWorld
	local components = Manager.Components
	return world:get(ent, components.Instance)
end

function Manager.getSetting(name)
	return SettingEditor.getSetting(Manager, name)
end

function Manager.setSetting(name, value)
	return SettingEditor.setSetting(Manager, name, value)
end

-- Connects input began for widget
function Manager.connectInputBegan(fn)
	local state = Manager.WidgetState

	return state.JExplorerUI.InputBegan:Connect(fn)
end

-- Connects input ended for widget
function Manager.connectInputEnded(fn)
	local state = Manager.WidgetState

	return state.JExplorerUI.InputEnded:Connect(fn)
end

function Manager.isKeyDown(key)
	return downKeys[key] == true
end

function Manager.isInputActive(input)
	return activeInputs[input] == true
end

function Manager.getInstId(inst)
	return inst:GetDebugId()
end

function Manager.getInstFromId(id)
	return Manager.DebugIdToInstance[id]
end

function Manager.getSetPropertyDragInfo(instances, propName)
	local ids = {}
	for _, v in instances do
		table.insert(ids, Manager.getInstId(v))
	end
	return {
		Sender = "setproperty",
		MimeType = "text/plain",
		Data = HttpService:JSONEncode({
			ids = ids,
			propName = propName
		}),
		MouseIcon = "",
		DragIcon = "",
		HotSpot = Vector2.new(0, 0)
	}
end

function Manager.getDragEntitiesDragInfo(entities)
	local icon
	local theme = assert(studioSettings.Theme) :: StudioTheme
	local themeExtension = theme:GetColor(Enum.StudioStyleGuideColor.MainBackground).R > 0.5 and "Light" or "Dark"
	
	if #entities == 1 then
		local entity = entities[1]
		local className = Manager.ClassNameCache[entity]
		
		icon = `rbxasset://studio_svg_textures/Shared/InsertableObjects/{themeExtension}/Standard/{className}@2x.png`
	else
		icon = `rbxasset://studio_svg_textures/Shared/Navigation/{themeExtension}/Standard/More@2x.png`
	end
	return {
		Sender = "reparent",
		MimeType = "text/plain",
		Data = HttpService:JSONEncode(entities),
		MouseIcon = "",
		DragIcon = icon,
		HotSpot = Vector2.new(-0.1, -0.1)
	}
end

function Manager.unpackDragInfo(info)
	local sender = info.Sender
	if sender == "setproperty" then
		local data = HttpService:JSONDecode(info.Data)
		local instances = {}
		for _, id in data.ids do
			table.insert(instances, assert(Manager.getInstFromId(id)))
		end

		return {
			Type = "setproperty",
			TargetInstances = instances,
			PropertyName = data.propName
		}
	elseif sender == "reparent" then
		return {
			Type = "reparent",
			Entities = HttpService:JSONDecode(info.Data)
		}
	else
		error(`drag info type '{sender}' unknown`)
	end
end

function Manager.onTagRemoved(inst, callback)
	onTagRemovedListeners[inst] = callback
	return {
		Connected = false,
		Disconnect = function(self)
			self.Connected = false
			onTagRemovedListeners[inst] = nil
		end,
	} :: any
end

function Manager.onTagAdded(inst, callback)
	onTagAddedListeners[inst] = callback
	return {
		Connected = false,
		Disconnect = function(self)
			self.Connected = false
			onTagAddedListeners[inst] = nil
		end,
	} :: any
end

function Manager.registerRightClickContextMenu(menu, condition, priority)
	Manager.WidgetState.InstanceContextMenus[menu.Id] = {
		Menu = menu,
		Condition = condition,
		Priority = priority
	}
end

function Manager.createContextMenu(id, actions, title, icon)
	local menu = plugin:CreatePluginMenu(id, title, icon)
	local pluginActions = {}
	local subMenus = {}

	for _, name: any in actions do
		if name == "---" then
			menu:AddSeparator()
			continue
		end
		-- Submenu case
		if typeof(name) == "table" then
			assert(name.Id, "submenu must contain id")
			assert(name.Title, "submenu must contain title")
			assert(name[1], "submenu must contain actions")
			local submenu = Manager.createContextMenu(
				getId(name.Id, true), name[1], name.Title, name.Icon
			)
			menu:AddMenu(submenu.Menu)
			table.insert(subMenus, submenu)
			continue
		end

		local pluginAction = Manager.PluginActions[name]
		assert(pluginAction, `PluginAction '{name}' not found for context menu creation`)

		menu:AddAction(pluginAction)
		table.insert(pluginActions, pluginAction)
	end

	return table.freeze {
		Actions = pluginActions,
		SubMenus = subMenus,
		Menu = menu,
		Id = id,
		UnprocessedContents = table.clone(actions)
	}
end

function Manager.startDraggingSelected()
	local state = Manager.WidgetState
	local components = Manager.Components

	state.IsDragging = true
	local info = Manager.getDragEntitiesDragInfo(state.CurrentSelection)
	plugin:StartDrag(info)
end

function Manager.setExplorerEntitiesAsSelection(entities: {ExplorerEntity}, updateSelection: boolean)
	profilebegin("Jexplorer::setSelection")
	local state = Manager.WidgetState
	local world = state.World
	local components = Manager.Components

	for entity in world:query(components.Instance, components.Selected):iter() do
		world:remove(entity, components.Selected)
	end
	for _, entity in entities do
		world:add(entity, components.Selected)
	end

	state.CurrentSelection = entities
	state.LastSelectedEntity = entities[#entities]

	ExplorerFrame.updateSelectionVisuals(Manager, updateSelection)
	profileend()
end

function Manager.addExplorerEntitiesToSelection(entities: {ExplorerEntity}, updateSelection: boolean)
	local state = Manager.WidgetState
	local world = state.World
	local components = Manager.Components

	for _, entity in entities do
		world:add(entity, components.Selected)
	end
	table.move(entities, 1, #entities, #state.CurrentSelection + 1, state.CurrentSelection)
	state.LastSelectedEntity = entities[#entities]
	ExplorerFrame.updateSelectionVisuals(Manager, updateSelection)
end

local function isDescendantOfJexpWidget(g: Instance)
	local widgets = CollectionService:GetTagged("JEXP_Widget")
	for _, v in widgets do
		if g:IsDescendantOf(v) then
			return true
		end
	end
	return false
end

function Manager.isInstanceExcluded(g)
	local state = Manager.WidgetState
	local isincoregui = g:IsDescendantOf(game:GetService("CoreGui"))
	return 
		g:HasTag("JEXP_Widget") or isDescendantOfJexpWidget(g) 
	or	(isincoregui and g:FindFirstAncestor("DraggerUI") ~= nil)
	or	(isincoregui and g.Name == "DraggerUI")
end

function Manager.getPropertyComponentsForClass(world, className)
	local cached = classComponentCache[className]
	if cached then return cached end

	local components = {}
	local props = ReflectionService:GetPropertiesOfClass(className)
	if not props then
		classComponentCache[className] = components
		return components
	end

	for _, info in props do
		local k = info.Name
		--TODO: Move assignment of componentMap ids outside of this getter
		local component = Manager.QueryCtMap[k]
		if not component then
			component = world:entity()
			Manager.QueryCtMap[k] = component
		end

		table.insert(components, component)
	end

	classComponentCache[className] = components
	return components
end

--[[
	@return The selected Frame, the ExplorerEntity associated with it and a Tab if what was selected was a tab
]]
function Manager.getEntityAt(x, y, filteredParent)
	local objects = PluginUI.getGuiObjectsAtPosition(Manager.WidgetState.JExplorerUI, x, y)

	-- Dont ask me how this works it just does
	local newParentFrame: any?
	for _, v: Instance in objects do
		if v.Name == "Overlay" and (filteredParent and v.Parent ~= filteredParent) then
			if not v.Parent then continue end
			newParentFrame = v.Parent.Parent
			break
		elseif v.Name == "Select" then
			if not v.Parent then continue end
			if not v.Parent.Parent then continue end
			newParentFrame = v.Parent.Parent.Parent
			break
		elseif v.Name == "InstanceTab" then -- For instance tabs
			return v, nil, Manager.TabFrameToTab[v]
		end
	end
	if not newParentFrame then return end

	local instFrame = Manager.FrameToInstanceFrame[newParentFrame]
	if not instFrame then return end

	local entity = Manager.WidgetState.FrameWorld:get(instFrame, Manager.Components.Entity)
	if not entity then 
		return
	end
	
	return newParentFrame, entity
end

function Manager.registerTab(name, stored, createDeleteButton, createInsertButton, registerIntoTabs)
	local state = Manager.WidgetState
	local jexplorerUi = state.JExplorerUI
	local topbar = jexplorerUi.Topbar

	local components = Manager.Components
	local world = state.World
	local connections = state.Connections
	local tabConnections = connections:extend(cleanup.disconnect)

	local tabBar = topbar.TabBar
	local tabFrame = UITemplates.TabFrame()

	local nameBox = assert(tabFrame:FindFirstChild("NameBox")) :: TextBox

	nameBox.Text = name
	local bounds = nameBox.TextBounds
	nameBox.Size = UDim2.new(0, bounds.X, 1, 0)

	local button = assert(tabFrame:FindFirstChild("Button")) :: TextButton

	tabFrame.Parent = tabBar.Tabs

	local tab = {
		Roots = stored,
		Name = name,

		TabFrame = tabFrame,
		Button = button,
		NameBox = nameBox,
	} :: Tab
	Manager.TabFrameToTab[tabFrame] = tab
	if registerIntoTabs then
		table.insert(state.Tabs, tab)
	end

	function tab.Toggle()
		-- Already selected
		if sharedTabState.currentlyOpenTab == tab then
			return
		end

		jexplorerUi.InstanceTree.CanvasPosition = Vector2.zero
		
		local listener = sharedTabState.tabInsertListener
		if listener then
			listener:Disconnect()
			listener = nil
			sharedTabState.isCurrentlyPickingTabRoots = false
		end

		for entity in world:query(components.Instance):without(ChildOf(Jecs.Wildcard)):iter() do
			world:add(entity, components.Invisible)
			HierarchyState.invalidateEntityStateCache(entity)

			world:remove(entity, components.DisplayTopLevel)
		end
		for entity in world:query(components.DisplayTopLevel):iter() do
			world:remove(entity, components.DisplayTopLevel)
		end
		local currentlyOpenTab = sharedTabState.currentlyOpenTab
		if currentlyOpenTab then
			local background = currentlyOpenTab.TabFrame
			background:RemoveTag("JEXP_SelectedColor")
			background:AddTag("JEXP_LightBackground")
			if currentlyOpenTab.InsertButton then
				currentlyOpenTab.InsertButton.BackgroundTransparency = 1
			end
			for _,v in currentlyOpenTab.Roots do
				local frame = world:get(v, components.Frame)
				if not frame then continue end

				ExplorerFrame.queueForExplorerFrameReuse(Manager, frame)
			end
		end
		tabFrame:RemoveTag("JEXP_LightBackground")
		tabFrame:AddTag("JEXP_SelectedColor")
		sharedTabState.currentlyOpenTab = tab

		for _, entity in stored do
			world:remove(entity, components.Invisible)
			HierarchyState.invalidateEntityStateCache(entity)

			world:add(entity, components.DisplayTopLevel)
			--updateEntityOrder(world, entity, nil)
		end
		
		task.delay(0.1, VirtualScroller.rebuildAndUpdate, Manager, false)
	end

	function tab.Remove()
		tabConnections:free()
		for _, v in stored do
			local parentTabs = world:get(v, components.ParentTabs)
			assert(parentTabs)
			parentTabs[tab] = nil
		end
		table.clear(stored)
		Manager.TabFrameToTab[tabFrame] = nil
		
		local currentTabs = state.Tabs
		tabFrame:Destroy()
		
		local idx = table.find(currentTabs, tab)
		if idx then table.remove(currentTabs, idx) end

		if sharedTabState.currentlyOpenTab == tab then
			local listener = sharedTabState.tabInsertListener
			if listener then
				listener:Disconnect()
				listener = nil
				sharedTabState.isCurrentlyPickingTabRoots = false
			end
			for entity in world:query(components.Instance):without(ChildOf(Jecs.Wildcard)):iter() do
				world:add(entity, components.Invisible)
				HierarchyState.invalidateEntityStateCache(entity)

				world:remove(entity, components.DisplayTopLevel)
			end
			for entity in world:query(components.DisplayTopLevel):iter() do
				world:remove(entity, components.DisplayTopLevel)
			end

			sharedTabState.currentlyOpenTab = nil
			Manager.AllTab.Toggle()
		end
	end

	if createInsertButton then
		local insertButton
		insertButton = PluginUI.createInsertButton(button, function()
			if sharedTabState.isCurrentlyPickingTabRoots then return end
			if sharedTabState.currentlyOpenTab ~= Manager.AllTab then
				Manager.AllTab.Toggle()
			end
			insertButton.BackgroundTransparency = 0

			sharedTabState.isCurrentlyPickingTabRoots = true
			sharedTabState.tabInsertListener = Manager.connectInputBegan(function(input)
				if input.UserInputState ~= Enum.UserInputState.Begin then return end

				local sink = false
				if input.KeyCode == Enum.KeyCode.Escape then
					-- Do nothing, let toggle back to this tab
					sink = true
				elseif input.KeyCode == Enum.KeyCode.Return then
					for _, v in state.CurrentSelection do
						local parentTabs = world:get(v, components.ParentTabs)
						assert(parentTabs)
						if parentTabs[tab] then continue end

						table.insert(stored, v)
						parentTabs[tab] = true
					end
					sink = true
				end
				if sink then
					Manager.setExplorerEntitiesAsSelection({}, true)
					tab.Toggle()

					insertButton.BackgroundTransparency = 1
				end
			end) 
		end)
		tab.InsertButton = insertButton

		if createDeleteButton then
			insertButton.Position = UDim2.new(1, -18, 0.5, 0)
		else
			insertButton.Position = UDim2.new(1, -2, 0.5, 0)
		end
		insertButton.Name = "Insert"
		insertButton.Size = UDim2.fromOffset(16, 16)
		insertButton.AnchorPoint = Vector2.new(1, 0.5)
	end

	if createDeleteButton then
		local deleteButton = PluginUI.createDeleteButton(button, tab.Remove)
		tab.RemoveButton = deleteButton

		deleteButton.Name = "Delete"
		deleteButton.Position = UDim2.new(1, -2, 0.5, 0)
		deleteButton.Size = UDim2.fromOffset(16, 16)
		deleteButton.AnchorPoint = Vector2.new(1, 0.5)
	end

	tabConnections:add_many({
		nameBox:GetPropertyChangedSignal("TextBounds"):Connect(function()
			local bounds = nameBox.TextBounds
			nameBox.Size = UDim2.new(0, bounds.X, 1, 0)

			if bounds.X == 0 then
				tabFrame.Size = UDim2.new(0, 70, 1, 0)
				return
			end
			tabFrame.Size = UDim2.new(0, bounds.X + 32 + 10, 1, 0)
		end),
		nameBox:GetPropertyChangedSignal("Text"):Connect(function()
			tab.Name = nameBox.Text
		end),
		button.Activated:Connect(tab.Toggle),
		button.InputBegan:Connect(function(input)
			if input.UserInputState ~= Enum.UserInputState.Begin then return end
			if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end

			sharedTabState.contextTargetTab = tab
			state.MiscContextMenus.Tab.Menu:ShowAsync()
		end),
		button.MouseEnter:Connect(function()
			if not state.IsDragging then return end
			tabFrame:AddTag("JEXP_DropTarget")
		end),
		button.MouseLeave:Connect(function()
			if tabFrame:HasTag("JEXP_DropTarget") then
				tabFrame:RemoveTag("JEXP_DropTarget")
			end
		end)
	})

	return tab
end

function Manager.saveState()
	local state = Manager.WidgetState
	local world = state.World
	local ct = Manager.Components
	local curr_state = state.SavedState

	local savedState: SavedState.SavedState = {
		repo_proxies = computedtbl(function(ser)
			for k, v in curr_state.repo_proxies do
				ser[k] = v
			end

			local proxies = state.RepoProxies
			ser[PLACE_ID] = {}
			for _, v in proxies do
				table.insert(ser[PLACE_ID], {
					display_name = v.DisplayName,
					repo_id = v.RepoId,
					root_inst_id = Manager.getInstId(v.Root),
				})
			end
		end),
		tabs = computedtbl(function(ser)
			for k, v in curr_state.tabs do
				ser[k] = v
			end

			local tabs = state.Tabs
			ser[PLACE_ID] = {}
			for _, v in tabs do
				local inst_ids = {}
				for _, ent in v.Roots do
					local inst = world:get(ent, ct.Instance)
					if not inst then continue end

					table.insert(inst_ids, Manager.getInstId(inst))
				end
				table.insert(ser[PLACE_ID], {
					display_name = v.Name,
					inst_ids = inst_ids
				})
			end
		end),
		display_order = computedtbl(function(ser)
			ser.default_order = OrderEditor.DefaultPriority
			ser.class_order = OrderEditor.ClassPriorities
		end),
		invisible = InstanceVisibilityEditor.InvisibleClasses,
		settings = computedtbl(function(ser)
			for k, v in SettingEditor.Configs do
				local udf = UDF.to(v)
				ser[k] = udf
			end
		end),
		style = computedtbl(function(ser)
			local style = Manager.Style
			local rules: {Types.SerializedStyleRule} = {}
			local tokens = {}
			
			SavedState._serialize_rules(style.Rules, rules, "DontSaveRule")
			for k, v in style.Tokens do
				tokens[k] = UDF.to(v)
			end
			ser.rules = rules
			ser.tokens = tokens
		end),
		versions = computedtbl(function(ser)
			local inst_vers = {}
			ser[PLACE_ID] = inst_vers

			for inst_id, versions in VersionControl.Versions do
				local ser_versions = {}
				for i, version in versions do
					local ser_props = {}
					for k, v in version.props do
						ser_props[k] = UDF.to(v)
					end
					ser_versions[i] = {
						timestamp = version.timestamp:ToUniversalTime(),
						props = ser_props
					}
				end
				inst_vers[inst_id] = ser_versions
			end
		end),
		data_version = SavedState.data_version
	}
	SavedState.save(savedState)
	return savedState
end

function Manager.loadState(savedState)
	local state = Manager.WidgetState
	local world = state.World
	local ct = Manager.Components

	return {
		tabs = function()
			local tabs = savedState.tabs[PLACE_ID]
			if not tabs then return end

			for _, t in tabs do
				local roots = {}
				for _, uid in t.inst_ids do
					local inst = Manager.getInstFromId(uid)
					if not inst then continue end

					local ent = Manager.InstanceToEntity[inst]
					if not ent then continue end

					table.insert(roots, ent)
				end
				Manager.registerTab(t.display_name, roots, true, true, true)
			end
		end,
		repo_proxies = function()
			local proxies = savedState.repo_proxies[PLACE_ID]
			if not proxies then return end

			for _, r in proxies do
				VersionControl.createRepoProxy(r.display_name, r.repo_id, assert(Manager.getInstFromId(r.root_inst_id)), true)
			end
		end,
		settings = function()
			for k, v in savedState.settings do
				Manager.setSetting(k, UDF.from(v))
			end
		end,
		style = function()
			local rules, tokens = {}, {}
			local function deserialize_rules(source: any, destination: any)
				for _, r in source do
					local props = {}
					for k, v in r.props do
						props[k] = UDF.from(v)
					end
					if #r.rules > 0 then
						deserialize_rules(r.rules, props)
					end
					local newrule = rule(r.display_name, r.selector, r.priority, props)
					for _, tag in r.tags do
						newrule:AddTag(tag)
					end
					table.insert(destination, newrule)
				end
			end
			deserialize_rules(savedState.style.rules, rules)
			for k, v in savedState.style.tokens do
				tokens[k] = UDF.from(v)
			end
			
			local default_tokens, default_rules = require("./Shared/Defaults/DefaultStyle")(Manager)
			for k, v in default_tokens do
				tokens[k] = v
			end
			for _, v in default_rules do
				table.insert(rules, v)
			end
			return Style.fromRulesTokens(rules, tokens)
		end,
		order = function()
			OrderEditor.ClassPriorities = savedState.display_order.class_order
			OrderEditor.DefaultPriority = savedState.display_order.default_order
		end,
		versions = function()
			local ser = savedState.versions[PLACE_ID]
			if not ser then return {} end

			local de = {}
			for inst_id, versions in ser do
				local de_versions = {}
				for i, version in versions do
					local t = version.timestamp
					local de_props = {}
					for k, v in version.props do
						de_props[k] = UDF.from(v)
					end
					de_versions[i] = {
						timestamp = DateTime.fromUniversalTime(t.Year, t.Month, t.Day, t.Hour, t.Minute, t.Second, t.Millisecond),
						props = de_props
					}
				end
				de[inst_id] = de_versions
			end
			return de
		end,
		invisible = function()
			InstanceVisibilityEditor.InvisibleClasses = savedState.invisible
		end,
	}, savedState
end

local function initRegisterPluginMenusAndActions(
	state: Types.WidgetState,
	components: typeof(Manager.Components),
	favoritedInstancesEntity: ExplorerEntity
)
	local world = state.World
	local connections = state.Connections
	local jexplorerUi = state.JExplorerUI
	local topbar = jexplorerUi.Topbar

	local tabEditName do
		tabEditName = createPluginAction(
			getId("EditName", true), "Edit Name", "Edits the name of a tab."
		)

		tabEditName.Triggered:Connect(function()
			if not sharedTabState.contextTargetTab then return end

			local box: TextBox = sharedTabState.contextTargetTab.NameBox
			box:CaptureFocus()
		end)
	end

	local tabBar = topbar.TabBar

	do
		local insertButton = PluginUI.createInsertButton(tabBar.Tabs, function()
			Manager.registerTab("Tab", {}, true, true, true)
		end)

		insertButton.LayoutOrder = math.huge
	end

	local renameAction do
		renameAction = createPluginAction(
			getId("Jexplorer_ContextMenu_Rename", true), "Rename", "Rename selected instance."
		) :: PluginAction
		renameAction.Triggered:Connect(function()
			for _, entity in state.CurrentSelection do
				local frame = world:get(entity, components.Frame)
				if not frame then continue end

				local frameInst = Manager.frameOf(frame)
				if not frameInst then continue end

				local n = frameInst.Main.InstanceName

				n.TextEditable = true
				n.Interactable = true
				n:CaptureFocus()
			end
		end)
	end

	local insertFromFileAction do
		insertFromFileAction = createPluginAction(
			getId("Jexplorer_ContextMenu_InsertFromFile", true), "Insert from File...", "Inserts a file into an Instance.", "rbxasset://textures/StudioSharedUI/import@2x.png"
		)
		insertFromFileAction.Triggered:Connect(function()
			local entity = state.ContextTarget
			if not entity then return end

			local instance = world:get(entity, components.Instance)
			if not instance then return end

			local file = StudioService:PromptImportFile({"lua", "luau", "rbxm"}) :: File?
			if not file then return end

			local success, instances = pcall(game.GetObjects, game, file:GetTemporaryId())
			if not success then
				-- File is a text file
				local src = file:GetBinaryContents()
				local luaSourceContainer = Instance.new("Script")
				luaSourceContainer.Source = src
				luaSourceContainer.Name = file.Name

				instances = {luaSourceContainer}
			end

			local id = ChangeHistoryService:TryBeginRecording("Import", "Import from File")
			for _, v in instances do
				local success, err = pcall(function()
					v.Parent = instance
				end)
				if not success then
					warn(err)
					if id then
						ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Cancel)
					end
					state.CurrentlyInserting = nil
					return
				end
				HierarchyState.queueForOnChildAdded(Manager, entity, v)
			end
			
			Manager.DeferredTaskScheduler.HierarchyChildrenMapNeedsUpdate = true
			
			if id then
				ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
			end
		end)
	end

	local insertObjectAction do
		insertObjectAction = createPluginAction(
			getId("Jexplorer_ContextMenu_InsertObject", true), "Insert Object...", "Inserts a chosen Instance into an Instance.", (ClassIcon.getIcon("Part")::any).Image
		)
		insertObjectAction.Triggered:Connect(function()
			local mousePos = state.Widget:GetRelativeMousePosition()
			InsertMenu.show(Manager, mousePos, Vector2.zero)
		end)
	end

	local selectChildrenAction do
		selectChildrenAction = createPluginAction(
			getId("Jexplorer_ContextMenu_SelectChildren", true), "Select Children", "Selects all children of an Instance."
		)
		selectChildrenAction.Triggered:Connect(function()
			for _, target in state.CurrentSelection do
				local children = {}
				for _, child in HierarchyState.getChildren(target) do
					table.insert(children, child)
				end

				if not world:has(target, components.Expanded) then
					--toggleExpand(world, target, true, true)
					world:add(target, components.Expanded)
					
					HierarchyState.invalidateEntityStateCache(target)
					ExplorerFrame.updateExpandedVisuals(Manager)
					VirtualScroller.update(Manager, false)
				end
				Manager.addExplorerEntitiesToSelection(children, true)
			end
		end)
	end

	local saveToFileAction do
		saveToFileAction = createPluginAction(
			getId("Jexplorer_ContextMenu_SaveToFile", true), "Save to File...", "Saves an Instance as a local file."
		)
		saveToFileAction.Triggered:Connect(function()
			local target = state.ContextTarget
			local name = "Instance"
			if target then name = Manager.NameCache[target] end

			Manager.setExplorerEntitiesAsSelection(state.CurrentSelection, true)
			plugin:PromptSaveSelection(name)
		end)
	end

	local saveToRobloxAction do
		saveToRobloxAction = createPluginAction(
			getId("Jexplorer_ContextMenu_SaveToRoblox", true), "Save to Roblox...", "Saves an Instance to Roblox."
		)
		saveToRobloxAction.Triggered:Connect(function()
			Manager.setExplorerEntitiesAsSelection(state.CurrentSelection, true)
			plugin:SaveSelectedToRoblox()
		end)
	end

	local copyAction do
		copyAction = createPluginAction(
			getId("Jexplorer_ContextMenu_Copy", true), "Copy", "Copies all Instances to your clipboard."
		)
		copyAction.Triggered:Connect(function()
			copySelection(world)
		end)
	end

	local pasteIntoAction do
		pasteIntoAction = createPluginAction(
			getId("Jexplorer_ContextMenu_PasteInto", true), "Paste Into", "Pastes all copied Instances into the first currently selected Instance."
		)
		pasteIntoAction.Triggered:Connect(function()
			pasteCopiedInstances(world)
		end)
	end

	local collapseAllAction do
		collapseAllAction = createPluginAction(
			getId("Jexplorer_ContextMenu_CollapseAll", true), "Collapse All", "Collapses all expanded descendants."
		)
		collapseAllAction.Triggered:Connect(function()
			for _, entity in state.CurrentSelection do
				local inst = world:get(entity, components.Instance)
				if not inst then return end

				for _, v in inst:GetDescendants() do
					local child = Manager.InstanceToEntity[v]
					if not child then continue end
					if not Manager.isExplorerEntityExpanded(child) then continue end

					world:remove(child, components.Expanded)
					world:remove(child, components.QueryExpanded)
					HierarchyState.invalidateEntityStateCache(child)
					ExplorerFrame.updateCollapsedVisuals(Manager)
				end
				--toggleExpand(world, entity, false, false)
				world:remove(entity, components.Expanded)
				world:remove(entity, components.QueryExpanded)
				HierarchyState.invalidateEntityStateCache(entity)
				ExplorerFrame.updateCollapsedVisuals(Manager)
			end
			VirtualScroller.update(Manager, false)
		end)
	end

	local toggleFavoriteAction do
		toggleFavoriteAction = createPluginAction(
			getId("Jexplorer_ContextMenu_ToggleFavorite", true), "Toggle Favorite", "Puts this instance into the favorited list.", "rbxassetid://12982756171"
		)
		toggleFavoriteAction.Triggered:Connect(function()
			for _, entity in state.CurrentSelection do
				local existingProxy = world:get(entity, components.FavoriteProxy)
				local proxySource = world:get(entity, components.FavoriteProxySource)
				if proxySource then
					world:remove(proxySource, components.FavoriteProxy)

					local idx = table.find(state.Favorited, entity)
					if idx then
						table.remove(state.Favorited, idx)
					end

					HierarchyState.cleanupEntity(Manager, entity)
					continue
				end
				local instance = world:get(entity, components.Instance)
				if not instance then return end
				if Manager.AbstractEntClasses[instance.ClassName] then continue end
				if existingProxy == nil then
					-- Add proxy
					local proxy = HierarchyState.createInstanceEntity(Manager, instance, favoritedInstancesEntity, true)
					if not proxy then continue end
					world:add(proxy, components.ArrowInvisible)

					if not proxy then
						warn(`could not create favorite proxy for '{instance}'`)
						return
					end

					world:set(entity, components.FavoriteProxy, proxy)
					world:set(proxy, components.FavoriteProxySource, entity)

					if world:has(favoritedInstancesEntity, components.Expanded) then
						local frame = ExplorerFrame.getExplorerFrame(Manager)
						ExplorerFrame.assignExplorerFrame(Manager, frame, proxy, favoritedInstancesEntity, false)
					end
					HierarchyState.updateEntityOrder(Manager, proxy)

					table.insert(state.Favorited, proxy)
				else
					-- Remove proxy
					local idx = table.find(state.Favorited, existingProxy)
					if idx then
						table.remove(state.Favorited, idx)
					end
					world:remove(entity, components.FavoriteProxy)

					HierarchyState.cleanupEntity(Manager, entity)
				end
			end
			ExplorerFrame.flushExplorerFrameTagAssignQueue(Manager)
			ExplorerFrame.flushFrameSetParentQueueIfConfigured(Manager)

			HierarchyState.flushEntityPropAssignQueue(Manager)
			Manager.DeferredTaskScheduler.HierarchyChildrenMapNeedsUpdate = true
		end)
	end

	local hideClassAction do
		hideClassAction = createPluginAction(
			getId("Jexplorer_ContextMenu_HideClass", true), "Hide Class", "Hides all Instances with the ClassName of the selected Instance."
		)
		hideClassAction.Triggered:Connect(function()
			for _, v in state.CurrentSelection do
				local className = Manager.ClassNameCache[v]
				if not className then continue end

				InstanceVisibilityEditor.setInvisible(className, true)
				VirtualScroller.update(Manager, false)
			end
		end)
	end

	local deleteAction do
		deleteAction = createPluginAction(
			getId("Jexplorer_ContextMenu_Delete", true), "Delete", "Deletes this Instance."
		)
		deleteAction.Triggered:Connect(Manager.triggerDeleteTarget)
	end

	local escapeAction do
		escapeAction = createPluginAction(
			getId("Jexplorer_ContextMenu_Escape", true), "Escape", "Escapes this Instance."
		)
		escapeAction.Triggered:Connect(Manager.triggerEscapeTarget)
	end

	local duplicateAction do
		duplicateAction = createPluginAction(
			getId("Jexplorer_ContextMenu_Duplicate", true), "Duplicate", "Duplicates this Instance."
		)
		duplicateAction.Triggered:Connect(Manager.triggerDuplicateTarget)
	end
	local openVersionHistoryAction do
		openVersionHistoryAction = createPluginAction(
			getId("Jexplorer_ContextMenu_OpenVersionHistory", true), "Open Version History", "Opens the version history viewer."
		)
		openVersionHistoryAction.Triggered:Connect(function()
			local target = state.ContextTarget
			if not target then return end

			local inst = world:get(target, components.Instance)
			if not inst then return end

			VersionControl.showInstanceHistoryWidget(inst)
		end)
	end

	local appendAction do
		appendAction = createPluginAction(
			getId("Jexplorer_ContextMenu_Append", true), "Append Changes", "Saves pending changes made to this Instance, appends to the latest version."
		)
		appendAction.Triggered:Connect(function()
			for _, entity in state.CurrentSelection do
				local inst = world:get(entity, components.Instance) :: Instance
				VersionControl.appendPendingChanges(inst)
			end
		end)
	end

	local commitAction do
		commitAction = createPluginAction(
			getId("Jexplorer_ContextMenu_Commit", true), "Commit Changes", "Commits pending changes made to this Instance, saves as a new version."
		)
		commitAction.Triggered:Connect(function()
			for _, entity in state.CurrentSelection do
				local inst = world:get(entity, components.Instance) :: Instance
				VersionControl.createPendingChanges(inst)
			end
		end)
	end

	local removeFromTabAction do
		removeFromTabAction = createPluginAction(
			getId("Jexplorer_ContextMenu_RemoveFromTab", true), "Remove from Tab", "Removes this instance from this tab. Can be readded via the tabs + menu"
		)
		removeFromTabAction.Triggered:Connect(function()
			local currentlyOpenTab = sharedTabState.currentlyOpenTab
			if not currentlyOpenTab then return end
			if currentlyOpenTab == Manager.AllTab then return end
			local stored = currentlyOpenTab.Roots

			local selection = state.CurrentSelection
			for _, ent in selection do
				local parentTabs = world:get(ent, components.ParentTabs)
				assert(parentTabs)

				parentTabs[currentlyOpenTab] = nil
				world:remove(ent, components.DisplayTopLevel)

				local frame = world:get(ent, components.Frame)
				if frame then ExplorerFrame.queueForExplorerFrameReuse(Manager, frame) end
				local idx = table.find(stored, ent)
				if idx then
					table.remove(stored, idx)
				end

				--updateEntityOrder(world, ent, world:parent(ent))
			end

			Manager.DeferredTaskScheduler.HierarchyChildrenMapNeedsUpdate = true
		end)
	end

	local groupAsFolderAction, groupAsModelAction do
		local function groupAs(className: string)
			local pathArray = {}
			local pathMap = {}
			local entities = {}

			for _, ent in state.CurrentSelection do
				local inst = world:get(ent, components.Instance)
				if not inst then continue end

				table.insert(entities, ent)

				local path = inst:GetFullName()
				table.insert(pathArray, path)
				pathMap[path] = ent
			end
			table.sort(pathArray)
			local shortest = pathArray[1]
			if not shortest then return end

			local targetParentEnt = world:parent(pathMap[shortest])
			assert(targetParentEnt)
			local targetParent = world:get(targetParentEnt, components.Instance)
			assert(targetParent)

			local id = ChangeHistoryService:TryBeginRecording("GroupAs", "Group As")

			local container = Instance.new(className)
			container.Parent = targetParent

			local containerEntity = HierarchyState.getOrCreateInstanceEntity(Manager, container, targetParentEnt)

			assert(containerEntity)
			world:add(containerEntity, components.AncestryLocked)

			for _, ent in entities do
				world:add(ent, components.AncestryLocked)
			end

			for _, ent in entities do
				local inst = world:get(ent, components.Instance)
				if not inst then continue end

				Manager.updateParent(ent, containerEntity)
				pcall(rawnewindex, inst, "Parent", container)

				local frame = world:get(ent, components.Frame)
				if frame then
					ExplorerFrame.queueForExplorerFrameReuse(Manager, frame)
				end
			end

			for _, ent in entities do
				world:remove(ent, components.AncestryLocked)
			end

			world:remove(containerEntity, components.AncestryLocked)

			Manager.DeferredTaskScheduler.HierarchyChildrenMapNeedsUpdate = true

			if id then
				ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
			end
			task.delay(0.1, function()
				game.Selection:Set({container})
			end)
		end
		groupAsFolderAction = createPluginAction(
			getId("Jexplorer_ContextMenu_GroupAsFolder", true), "Group as Folder", "Groups the selected Instances inside 1 Folder.",
			"rbxasset://studio_svg_textures/Shared/InsertableObjects/Dark/Standard/Folder.png"
		)
		groupAsModelAction = createPluginAction(
			getId("Jexplorer_ContextMenu_GroupAsModel", true), "Group as Model", "Groups the selected Instances inside 1 Model.",
			"rbxasset://studio_svg_textures/Shared/InsertableObjects/Dark/Standard/Model.png"
		)
		groupAsFolderAction.Triggered:Connect(function()
			groupAs("Folder")
		end)
		groupAsModelAction.Triggered:Connect(function()
			groupAs("Model")
		end)
	end

	local ungroupAction do
		ungroupAction = createPluginAction(
			getId("Jexplorer_ContextMenu_Ungroup", true), "Ungroup", "Ungroups the selected Instances."
		)
		ungroupAction.Triggered:Connect(function()
			local target = state.ContextTarget
			if not target then return end

			local entities = {}

			local parent = Manager.parentOf(target)
			local targetInst = Manager.instanceOf(target)
			if not parent then return end
			if not targetInst then return end

			local children = HierarchyState.getChildren(target)
			if not children then return end

			local id = ChangeHistoryService:TryBeginRecording("Ungroup", "Ungroup")

			for _, child in children do
				local inst = Manager.instanceOf(child)
				if not inst then continue end

				Manager.updateParent(child, parent)
				inst.Parent = Manager.instanceOf(parent)
				table.insert(entities, child)
			end

			targetInst.Parent = nil
			Manager.updateParent(target, nil)

			VirtualScroller.update(Manager, false)
			Manager.setExplorerEntitiesAsSelection(entities, true)

			if id then
				ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
			end
		end)
	end

	local toFolderAction, toModelAction do
		local function convertInstTo(className: string)
			local id = ChangeHistoryService:TryBeginRecording("ConvertInstTo", `Convert Instance To {className}`)

			local toConvert: {{name: string, parent: Instance?, parentEntity: ExplorerEntity?, inst: Instance, entity: any, children: {ExplorerEntity}}} = {}
			for _, entity in state.CurrentSelection do
				local inst = world:get(entity, components.Instance)
				if not inst then continue end

				local childInstances = {}
				local tbl: {ExplorerEntity} = {}
				local children = HierarchyState.getChildren(entity)
				if children then
					for _, v in children do
						table.insert(tbl, v)
					end
				end

				--world:add(entity, components.AncestryLocked)
				table.insert(toConvert, {
					name = inst.Name,
					parent = inst.Parent,
					parentEntity = world:parent(entity),
					entity = entity,
					children = tbl,
					inst = inst,
				})
			end

			local modelEntities = {}
			for _, info in toConvert do
				if not info.parent then continue end
				local model = Instance.new(className)
				model.Name = info.name

				local modelEnt = HierarchyState.createInstanceEntity(Manager, model, info.parentEntity)
				assert(modelEnt)

				local frame = world:get(info.entity, components.Frame)
				if frame then
					ExplorerFrame.queueForExplorerFrameReuse(Manager, frame)
				end

				world:add(modelEnt, components.AncestryLocked)
				table.insert(modelEntities, modelEnt)

				for _, childEntity in info.children do
					world:add(childEntity, components.AncestryLocked)
				end
				local isExpanded = Manager.isExplorerEntityExpanded(info.entity)
				for _, childEntity in info.children do
					local childInst = world:get(childEntity, components.Instance)
					if not childInst then continue end

					local oldParentEntity = Manager.parentOf(childEntity)
					Manager.updateParent(childEntity, modelEnt)

					if oldParentEntity then
						VirtualScroller.invalidateEntityHeightCache(Manager, oldParentEntity)
					end

					childInst.Parent = model
					HierarchyState.updateEntityOrder(Manager, childEntity)

					local dragFrame = world:get(childEntity, components.Frame)
					if dragFrame then
						ExplorerFrame.queueForExplorerFrameReuse(Manager, dragFrame)
					end
				end

				ExplorerFrame.flushExplorerFrameTagAssignQueue(Manager)
				if isExpanded then
					world:add(modelEnt, components.Expanded)
					HierarchyState.invalidateEntityStateCache(modelEnt)
					ExplorerFrame.updateExpandedVisuals(Manager)
				else
					VirtualScroller.invalidateEntityHeightCache(Manager, modelEnt)
				end
				
				Manager.updateParent(info.entity, nil)
				info.inst.Parent = nil
				HierarchyState.cleanupEntity(Manager, info.entity)
				
				model.Parent = info.parent
				for _, childEntity in info.children do
					world:remove(childEntity, components.AncestryLocked)
				end
			end

			Manager.DeferredTaskScheduler.HierarchyChildrenMapNeedsUpdate = true

			for _, v in modelEntities do
				world:remove(v, components.AncestryLocked)
			end

			if id then
				ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
			end

			task.delay(0.1, function()
				Manager.setExplorerEntitiesAsSelection(modelEntities, true)
			end)
		end

		toFolderAction = createPluginAction(
			getId("IntoFolder", true), "Into Folder", "Turns selected instances into Folders.", 
			"rbxasset://studio_svg_textures/Shared/InsertableObjects/Dark/Standard/Folder.png"
		)
		toFolderAction.Triggered:Connect(function()
			convertInstTo("Folder")
		end)
		toModelAction = createPluginAction(
			getId("IntoModel", true), "Into Model", "Turns selected instances into Models.", 
			"rbxasset://studio_svg_textures/Shared/InsertableObjects/Dark/Standard/Model.png"
		)
		toModelAction.Triggered:Connect(function()
			convertInstTo("Model")
		end)
	end

	local helpAction do
		helpAction = createPluginAction(
			getId("Help", true), "Open Documentation", "Opens the API wiki page for this Instance."
		)
		helpAction.Triggered:Connect(function()
			local target = state.ContextTarget
			if not target then return end

			local inst = Manager.instanceOf(target)
			if not inst then return end

			plugin:OpenWikiPage(`en-us/api-reference/class/{inst.ClassName}`)
		end)
	end

	local dragAction do
		dragAction = createPluginAction(
			getId("Drag", true), "Start Dragging", "Starts dragging selected Instances."
		)
		dragAction.Triggered:Connect(function()
			local entity = state.ContextTarget
			if not entity then return end

			local frame = world:get(entity, components.Frame)
			if not frame then return end

			Manager.startDraggingSelected()
		end)
	end


	Manager.PluginActions = {
		OpenVersionHistory = openVersionHistoryAction,
		Append = appendAction,
		Commit = commitAction,

		Copy = copyAction,
		PasteInto = pasteIntoAction,
		Escape = escapeAction,
		Duplicate = duplicateAction,
		Delete = deleteAction,
		Rename = renameAction,
		Drag = dragAction,

		Help = helpAction,

		HideClass = hideClassAction,

		SelectChildren = selectChildrenAction,
		CollapseAll = collapseAllAction,

		InsertFromFile = insertFromFileAction,
		InsertObject = insertObjectAction,

		SaveToFile = saveToFileAction,
		SaveToRoblox = saveToRobloxAction,

		ToggleFavorite = toggleFavoriteAction,
		RemoveFromTab = removeFromTabAction,

		GroupAsModel = groupAsModelAction,
		GroupAsFolder = groupAsFolderAction,

		IntoFolder = toFolderAction,
		IntoModel = toModelAction,

		Ungroup = ungroupAction,

		Tab_EditName = tabEditName
	}

	state.DefaultInstanceActionsArray = {
		"OpenVersionHistory",
		"Append",
		"Commit",

		"---",

		"Copy",
		"PasteInto",
		"Delete",
		"Duplicate",

		"---",

		"Escape",
		"Rename",

		"---",

		{
			Id = "Menu.GroupAs",
			Title = "Group As",
			{
				"GroupAsFolder",
				"GroupAsModel"
			}
		},
		{
			Id = "Menu.ConvertInto",
			Title = "Convert Into",
			{
				"IntoModel",
				"IntoFolder"
			}
		},

		"HideClass",
		"Ungroup",

		"---",

		"SelectChildren",
		"CollapseAll",
		"Drag",

		"---",

		"InsertFromFile",
		"InsertObject",

		"---",

		"SaveToFile",
		"SaveToRoblox",

		"---",

		"ToggleFavorite",
		"RemoveFromTab",

		"---",

		"Help"
	}
	local instanceContextMenu = Manager.createContextMenu(
		getId("Jexplorer_InstanceContextMenu", true),
		state.DefaultInstanceActionsArray
	)

	local serviceContextMenu = Manager.createContextMenu(
		getId("Jexplorer_ServiceContextMenu", true),
		{
			"PasteInto",
			"Rename",

			"---",

			"HideClass",

			"---",

			"SelectChildren",
			"CollapseAll",

			"---",

			"InsertFromFile",
			"InsertObject",

			"---",

			"ToggleFavorite",
			"RemoveFromTab",

			"---",

			"Help"
		}
	)

	local tabMenu = Manager.createContextMenu(
		getId("Jexplorer_TabContextMenu", true),
		{
			"Tab_EditName"
		}
	)

	state.InstanceContextMenus = {
		DefaultInstance = {
			Menu = instanceContextMenu,
			Condition = function(_, target)
				local inst = world:get(target, components.Instance)
				if not inst then return false end
				return inst:IsA("Instance")
			end,
			Priority = 0
		},
		Service = {
			Menu = serviceContextMenu,
			Condition = function(_, target)
				local inst = world:get(target, components.Instance)
				if not inst then return false end
				return inst.Parent == game
			end,
			Priority = 1
		},
	}
	state.MiscContextMenus = {
		Tab = tabMenu
	}
end

local function initRegisterTagListeners(
	state: Types.WidgetState,
	components: typeof(Manager.Components)
)
	local world = state.World
	local frameWorld = state.FrameWorld
	local queryWorld = state.QueryWorld

	local function refresh_tags(inst: Instance, entity: ExplorerEntity, tag_ent: Jecs.Id?)
		local tags: {Jecs.Id} = {}
		if tag_ent then
			table.insert(tags, tag_ent)
		end
		for _, tag_str in inst:GetTags() do
			if tag_str:match("JEXP") then continue end  -- Skip internal tags

			local tag = Manager.QueryTagMap[tag_str]
			if not tag then
				-- Tag entity doesn't exist yet, create it
				tag = queryWorld:entity()
				Manager.QueryTagMap[tag_str] = tag
			end
			if table.find(tags, tag) then continue end
			table.insert(tags, tag)
		end
		HierarchyState.deregisterFromQueryWorld(Manager, entity)
		HierarchyState.registerIntoQueryWorld(Manager, entity, Manager.ClassNameCache[entity], tags)
	end

	local tagAddedSignals = {}
	local tagRemovedSignals = {}
	local function onTag(tag: string)
		if tag:match("JEXP") then return end

		local tagComponent = queryWorld:entity()
		world:set(tagComponent, Jecs.Name, tag)
		Manager.QueryTagMap[tag] = tagComponent

		local function onAdded(inst: Instance)
			if Manager.isInstanceExcluded(inst) then return end

			local listener = onTagAddedListeners[inst]
			if listener then listener(tag) end

			local entity = Manager.InstanceToEntity[inst]
			if not entity then return end

			refresh_tags(inst, entity, tagComponent)

			local frame = world:get(entity, components.Frame)
			if not frame then return end

			local frameState, frameInst = frameWorld:get(frame, components.FrameState, components.Instance)
			if not frameState or not frameInst then return end

			local tag = `JEXP_TAG_{tag}`
			table.insert(frameState.tagsToRemove, tag)
			frameInst:AddTag(tag)
		end

		for _, v in CollectionService:GetTagged(tag) do
			onAdded(v)
		end
		tagAddedSignals[tag] = CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst: Instance)
			onAdded(inst)
		end)
		tagRemovedSignals[tag] = CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst: Instance)
			if Manager.isInstanceExcluded(inst) then return end

			local listener = onTagRemovedListeners[inst]
			if listener then listener(tag) end

			local entity = Manager.InstanceToEntity[inst]
			if not entity then return end

			refresh_tags(inst, entity, tagComponent)

			local frame = world:get(entity, components.Frame)
			if not frame then return end

			local frameState, frameInst = frameWorld:get(frame, components.FrameState, components.Instance)
			if not frameState or not frameInst then return end

			local tag = `JEXP_TAG_{tag}`
			local idx = table.find(frameState.tagsToRemove, tag)
			if not idx then return end

			frameInst:RemoveTag(tag)
			table.remove(frameState.tagsToRemove, idx)
		end)
	end

	for _, tag in CollectionService:GetAllTags() do
		task.defer(onTag, tag)
	end

	return
		tagAddedSignals, tagRemovedSignals, 
		CollectionService.TagAdded:Connect(onTag),
		CollectionService.TagRemoved:Connect(function(tag)
			local added, removed = tagAddedSignals[tag], tagRemovedSignals[tag]
			if added then added:Disconnect() end
			if removed then removed:Disconnect() end

			tagAddedSignals[tag] = nil
			tagRemovedSignals[tag] = nil

			local tagEnt = Manager.QueryTagMap[tag]
			if not tagEnt then return end

			for queryEnt, linked in queryWorld:query(components.QueryLinkedEntities, tagEnt):iter() do
				for _, ent in linked do
					local inst = world:get(ent, components.Instance)
					if not inst then continue end
					refresh_tags(inst, ent, nil)
				end
			end
		end)
end

function initStartTrackScrolling(state: Types.WidgetState)
	local jexplorerUi = state.JExplorerUI
	local scrollTrackerConnection, scrollTrackerThread = VirtualScroller.trackScrolling(Manager)
	
	return scrollTrackerConnection, scrollTrackerThread
end

function initCreateEntities(state: Types.WidgetState, components: typeof(Manager.Components), entities: {ExplorerEntity})
	profilebegin("Jexplorer::initCreateEntities")
	local world = state.World
	-->> Initialize entities
	-- Initialize services
	for _, service in game:GetChildren() do
		-- Prevent a specific FilteredSelection instance with no classname from showing up
		if not service.ClassName:match("%w+") then continue end

		local entity = HierarchyState.createInstanceEntity(Manager, service)
		table.insert(entities, entity)
	end
	HierarchyState.flushEntityPropAssignQueue(Manager)
	
	for _, entity in entities do
		local frame = ExplorerFrame.getExplorerFrame(Manager)
		ExplorerFrame.assignExplorerFrame(Manager, frame, entity, nil, true)
	end
	
	ExplorerFrame.flushFrameSetParentQueueIfConfigured(Manager)
	ExplorerFrame.flushExplorerFrameTagAssignQueue(Manager)
	VirtualScroller.rebuildAndUpdate(Manager, false)
	profileend()
end

local function initConnections(state: Types.WidgetState, components: typeof(Manager.Components), topbarMenuDropdown: PluginUI.ItemList): {RBXScriptConnection}
	local world = state.World
	local queryWorld = state.QueryWorld
	local jexplorerUi = state.JExplorerUI
	local instanceTree = jexplorerUi.InstanceTree
	local jexplorerWidget = state.Widget
	local topbar = jexplorerUi.Topbar
	local queryInput = topbar.QueryInput
	local selectQueried = queryInput.SelectQueried
	
	-->> Initialize connections
	local pathClickConnection: RBXScriptConnection?
	return {
		ScriptEditorService.TextDocumentDidChange:Connect(function(document, changes)
			local docScript = document:GetScript()
			if not docScript then return end

			VersionControl.addPendingChange(docScript, "Source", document:GetText())
		end),
		instanceTree:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			Manager.InstTreeAbsoluteSizeY = instanceTree.AbsoluteSize.Y
		end),
		instanceTree:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			VirtualScroller.update(Manager, true)
		end),
		jexplorerUi.InstanceTree.InputChanged:Connect(function(input)
			if jexplorerUi.InstanceTree.ScrollingEnabled then return end
			if input.UserInputType ~= Enum.UserInputType.MouseWheel then return end
			local scrollDir = input.Position.Z
			if math.abs(scrollDir) < Manager.getSetting("ScrollThreshold") then return end

			jexplorerUi.InstanceTree.CanvasPosition += Vector2.new(
				0,
				Manager.getSetting("ScrollStep") * -math.sign(scrollDir)
			)
		end),
		studioSettings.ThemeChanged:Connect(function()
			ClassIcon.CachedIcons = {}
			local sheet = Manager.Style
			local theme = studioSettings.Theme :: StudioTheme

			sheet:SetToken("BackgroundColor", theme:GetColor(Enum.StudioStyleGuideColor.MainBackground), false)
			sheet:SetToken("TextColor", theme:GetColor(Enum.StudioStyleGuideColor.MainText), false)

			topbarMenuDropdown:Destroy()
			topbarMenuDropdown = CreateOptionsDropdown(Manager, components, topbar)
			sheet:UpdateTokens()
		end),
		jexplorerWidget.PluginDragDropped:Connect(function(dragData)
			local info = Manager.unpackDragInfo(dragData)

			local mousePos = jexplorerWidget:GetRelativeMousePosition()

			local foundDropInst, foundDropEntity, foundTab = Manager.getEntityAt(mousePos.X, mousePos.Y)
			
			if not foundDropEntity then return end
			if info.Type == "setproperty" then
				local instances, propName = info.TargetInstances, info.PropertyName
				local id = ChangeHistoryService:TryBeginRecording("Set Instance", "Set Instance")
				for _, inst in instances do
					rawnewindex(inst, propName, Manager.instanceOf(foundDropEntity))
				end
				if id then
					ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
				end
			elseif info.Type == "reparent" then
				state.IsDragging = false
				local dragEntities = info.Entities
				profilebegin("InstanceFrame::dropCurrentlyDragged")

				if foundTab then
					for _, ent in dragEntities do
						local parentTabs = world:get(ent, components.ParentTabs)
						assert(parentTabs)

						local tabStorage = foundTab.Roots
						if table.find(tabStorage, ent) then return end
						table.insert(tabStorage, ent)
						parentTabs[foundTab] = true
					end

					return
				end

				if not foundDropEntity then
					return
				end

				local newParentInstance = world:get(foundDropEntity, components.Instance)
				if not newParentInstance then
					return 
				end
				for _, dragEntity in dragEntities do
					local child = world:get(dragEntity, components.Instance)
					if not child then continue end
					-- Attempting to reparent a selection into one of its members is illegal
					if newParentInstance == child or child:IsAncestorOf(newParentInstance) then
						return
					end
					if newParentInstance == child.Parent then
						return
					end
				end

				for _, e in dragEntities do
					world:add(e, components.AncestryLocked)
				end

				local id = ChangeHistoryService:TryBeginRecording("Drop", "Drop")
				local isExpanded = Manager.isExplorerEntityExpanded(foundDropEntity)
				for _, dragEntity in dragEntities do
					local child = world:get(dragEntity, components.Instance)
					if not child then continue end

					local oldParentEntity = Manager.parentOf(dragEntity)
					Manager.updateParent(dragEntity, foundDropEntity)

					if oldParentEntity then
						VirtualScroller.invalidateEntityHeightCache(Manager, oldParentEntity)
					end

					pcall(rawnewindex, child, "Parent", newParentInstance)
					HierarchyState.updateEntityOrder(Manager, dragEntity)

					local dragFrame = world:get(dragEntity, components.Frame)
					if dragFrame then
						ExplorerFrame.queueForExplorerFrameReuse(Manager, dragFrame)
					end
				end

				ExplorerFrame.flushExplorerFrameTagAssignQueue(Manager)
				if not isExpanded then
					world:add(foundDropEntity, components.Expanded)
					HierarchyState.invalidateEntityStateCache(foundDropEntity)

					ExplorerFrame.updateExpandedVisuals(Manager)
				else
					VirtualScroller.invalidateEntityHeightCache(Manager, foundDropEntity)
				end

				for _, e in dragEntities do
					world:remove(e, components.AncestryLocked)
				end
				Manager.DeferredTaskScheduler.HierarchyChildrenMapNeedsUpdate = true

				if id then
					ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
				end
				ExplorerFrame.updateSelectionVisuals(Manager, false)
				profileend()
			end
		end),
		game.Selection.SelectionChanged:Connect(function()
			profilebegin("Jexplorer::onSelectionChanged")
			local selection = game.Selection:Get()
			
			local entities = {}
			local n = 0
			for _, v in selection do
				while not Manager.InstanceToEntity[v] do
					task.wait()
				end

				local ent = Manager.InstanceToEntity[v]
				if not table.find(state.CurrentSelection, ent) then
					n += 1
				end
				table.insert(entities, ent)
			end
			state.CurrentSelection = entities

			if Manager.getSetting("PropertyEditorUpdatedOnSelect") then
				PropertyEditor.updateProperties(selection)
			end

			local pathSegments = topbar.PathBar.Segments
			if pathClickConnection then
				pathClickConnection:Disconnect()
			end
			if #selection == 0 then
				local pathButton = pathSegments.PathSegment
				pathButton.Text = ""
				Manager.setExplorerEntitiesAsSelection({}, false)
				return
			end

			-- Update path bar
			local commonAncestor = getCommonAncestor(selection)
			if commonAncestor then
				local pathButton = pathSegments.PathSegment
				local current: Instance? = commonAncestor
				local segmentBounds = {}

				local pathParts = {}
				local size = pathButton.TextSize
				local font = pathButton.Font
				local entities = {}
				while current and current ~= game do
					--local entity = instanceToEntity[current]
					table.insert(pathParts, 1, current.Name)
					table.insert(entities, 1, current)
					current = current.Parent
				end

				local cumulativeText = ""
				local absSize = Vector2.new(math.huge, pathButton.AbsoluteSize.Y)
				for i, part in pathParts do
					if i > 1 then
						cumulativeText = cumulativeText .. " / "
					end
					cumulativeText = cumulativeText .. part

					local textSize = game:GetService("TextService"):GetTextSize(cumulativeText, size, font, absSize)
					table.insert(segmentBounds, {bound = textSize.X, entity = entities[i]})
				end

				pathClickConnection = pathButton.Activated:Connect(function(input: InputObject)
					local relativeX = input.Position.X - pathButton.AbsolutePosition.X
					for _, item in segmentBounds do
						if relativeX <= item.bound then
							game.Selection:Set {item.entity}
							break
						end
					end
				end)

				pathButton.Text = table.concat(pathParts, " / ")
				pathSegments.CanvasPosition = pathSegments.AbsoluteCanvasSize
			end

			for v in world:query(components.Instance, components.Selected):iter() do
				world:remove(v, components.Selected)
			end
			for _, ent in entities do
				world:add(ent, components.Selected)
			end
			if n == 0 then return end

			local autoExpand = Manager.getSetting("AutoExpandOnSelect")
			-- I am a genius for this
			if autoExpand then
				profilebegin("Jexplorer::onSelectionChanged::expandAncestorsToSelection")
				for _, entity in entities do
					local unexpanded
					local currentParent = Manager.parentOf(entity)
					while currentParent do
						if not world:has(currentParent, components.Expanded) then
							unexpanded = currentParent
						end
						world:add(currentParent, components.Expanded)
						currentParent = Manager.parentOf(currentParent)
						if currentParent then
							HierarchyState.invalidateEntityStateCache(currentParent)
						end
					end
					if unexpanded then
						--toggleExpand(world, unexpanded, true, false)
						world:add(unexpanded, components.Expanded)
						HierarchyState.invalidateEntityStateCache(unexpanded)
					end
				end
				ExplorerFrame.updateExpandedVisuals(Manager)
				
				profileend()
			end

			-- Jump the canvas position to the middle entity
			local middle = entities[math.max(#entities // 2, 1)]
			local _, entityIndex = HierarchyState.getFlattenedVisibleEntities(Manager, {}, false)
			local idx = entityIndex[middle]
			if idx then
				local currentViewportTop = instanceTree.CanvasPosition.Y
				local currentViewportBottom = currentViewportTop + Manager.InstTreeAbsoluteSizeY

				local size: UDim2 = Manager.Style:GetToken("InstanceFrameSize")

				local targetFrameY = (idx - 1) * size.Y.Offset
				local targetFrameBottom = targetFrameY + size.Y.Offset

				if targetFrameY < currentViewportTop or targetFrameBottom > currentViewportBottom then
					local target = Vector2.new(
						0,
						math.max(
							0,
							targetFrameY - (Manager.InstTreeAbsoluteSizeY - size.Y.Offset) / 2
						)
					)
					instanceTree.CanvasPosition = target
					if not instanceTree.CanvasPosition:FuzzyEq(target, 0.01) then
						local lastPosition = instanceTree.CanvasPosition
						repeat
							task.wait()
							lastPosition = instanceTree.CanvasPosition
							instanceTree.CanvasPosition = target
						until instanceTree.CanvasPosition:FuzzyEq(lastPosition, 0.01)
					end
				end
			end

			VirtualScroller.update(Manager, false)
			ExplorerFrame.updateSelectionVisuals(Manager, false)
			profileend()
		end),
		Manager.connectInputBegan(function(input)
			if input.UserInputState ~= Enum.UserInputState.Begin then return end
			downKeys[input.KeyCode] = true
			activeInputs[input.UserInputType] = true

			state.IsDragging = false
			if input.UserInputType ~= Enum.UserInputType.MouseMovement then
				Manager.ItemLists.InsertInstance:Hide()
			end

			if input.KeyCode == Enum.KeyCode.Escape or (Manager.isKeyDown(Enum.KeyCode.Backspace) and Manager.isKeyDown(Enum.KeyCode.LeftShift)) then
				Manager.triggerEscapeTarget()
			elseif input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
				Manager.triggerDeleteTarget()
			elseif Manager.isKeyDown(Enum.KeyCode.LeftControl) and Manager.isKeyDown(Enum.KeyCode.D) then
				Manager.triggerDuplicateTarget()
			elseif Manager.isKeyDown(Enum.KeyCode.LeftControl) and Manager.isKeyDown(Enum.KeyCode.C) then
				copySelection(world)
			elseif Manager.isKeyDown(Enum.KeyCode.LeftControl) and Manager.isKeyDown(Enum.KeyCode.V) then
				pasteCopiedInstances(world)
			elseif Manager.isKeyDown(Enum.KeyCode.LeftControl) and Manager.isKeyDown(Enum.KeyCode.Z) then
				ChangeHistoryService:Undo()
			elseif Manager.isKeyDown(Enum.KeyCode.LeftControl) and Manager.isKeyDown(Enum.KeyCode.Y) then
				ChangeHistoryService:Redo()
			end
		end),
		Manager.connectInputEnded(function(input)
			if input.UserInputState ~= Enum.UserInputState.End then return end
			downKeys[input.KeyCode] = nil
			activeInputs[input.UserInputType] = nil
		end),

		topbar.Options.Activated:Connect(function()
			topbarMenuDropdown:SetAnchor(Vector2.zero, topbar.Options.Position)
			topbarMenuDropdown:Show()
		end),

		pluginMouse.Button1Up:Connect(function()
			print("mouse released")
		end),

		-- Optimized Query Handler
		queryInput.FocusLost:Connect(function(enterPressed)
			if not enterPressed then return end
			profilebegin("Jexplorer::query")

			local queryText = queryInput.Text
			VirtualScroller.clearHeightCache(Manager)

			for _, entity in state.Entities do
				local frame = world:get(entity, components.Frame)
				if frame then
					local inst = Manager.frameOf(frame)
					if inst then
						inst.Main.Arrow.Visible = Manager.ChildAmountCache[entity] > 0
					end
				end
			end

			-- Collapse ancestors from previous queries
			for entity in world:query(components.QueryExpanded):iter() do
				world:remove(entity, components.QueryExpanded)
				HierarchyState.invalidateEntityStateCache(entity)
			end
			for entity in world:query(components.QueryAncestor):iter() do
				world:remove(entity, components.QueryAncestor)
			end
			for entity in world:query(components.IsQueried):iter() do
				world:remove(entity, components.ArrowInvisible)
			end

			ExplorerFrame.updateCollapsedVisuals(Manager)

			if queryText == "" then
				queryInput.QueryCount.Text = "0"
				for _, entity in state.Entities do
					world:remove(entity, components.QueryInvisible)
					HierarchyState.invalidateEntityStateCache(entity)
					world:remove(entity, components.IsQueried)
				end
				jexplorerUi.InstanceTree.CanvasSize = UDim2.fromScale(0, 0)
				VirtualScroller.update(Manager, false)
				return
			end

			profilebegin("Jexplorer::query::hideEntities")
			for _, entity in state.Entities do
				world:add(entity, components.QueryInvisible)
				HierarchyState.invalidateEntityStateCache(entity)
				world:remove(entity, components.IsQueried)
			end
			profileend()

			local success, result = pcall(function()
				profilebegin("Jexplorer::query::parse")
				local conditions = JQL.parseQuery(queryText)
				profileend()
				profilebegin("Jexplorer::query::execute")
				local queryResult = JQL.executeQuery(world, queryWorld, components, Manager.QueryCtMap, Manager.QueryCtMap, conditions)
				profileend()
				return queryResult
			end)

			if not success then
				if not success then
					warn("JEXPLORER Query error: " .. tostring(result))
				end
				profilebegin("Jexplorer::query::showEntities")
				for entity in world:query(components.QueryInvisible):iter() do
					world:remove(entity, components.QueryInvisible)
					HierarchyState.invalidateEntityStateCache(entity)
					world:remove(entity, components.IsQueried)
				end
				profileend()
				VirtualScroller.clearHeightCache(Manager)
				VirtualScroller.update(Manager, false)
				profileend()
				return
			end
			-- Everything is invisible if no results
			if #result == 0 then
				queryInput.QueryCount.Text = "0"
				return
			end

			local validEntities = result
			local n = #validEntities
			queryInput.QueryCount.Text = n

			profilebegin("Jexplorer::query::optimizedVisibility")

			local visibilityMap = {}
			local parentTreesCache = {}

			for _, entity in validEntities do
				world:add(entity, components.IsQueried)
				world:add(entity, components.ArrowInvisible)
				visibilityMap[entity] = true
				if not parentTreesCache[entity] then
					parentTreesCache[entity] = JQL.collectParentTree(world, entity)
				end

				local parentTree = parentTreesCache[entity]
				for _, parentEntity in parentTree do
					visibilityMap[parentEntity] = true
				end
			end

			for _, entity in state.Entities do
				if visibilityMap[entity] then
					world:remove(entity, components.QueryInvisible)
				else
					world:add(entity, components.QueryInvisible)
				end
				HierarchyState.invalidateEntityStateCache(entity)
			end

			for _, entity in validEntities do
				local parentTree = parentTreesCache[entity]
				if #parentTree > 0 then
					local last = parentTree[#parentTree]
					for i = #parentTree, 2, -1 do
						local parent = parentTree[i]
						world:remove(parent, components.QueryInvisible)
						world:remove(parent, components.ArrowInvisible)
						world:add(parent, components.QueryExpanded)
						HierarchyState.invalidateEntityStateCache(parent)
					end

					world:add(last, components.QueryAncestor)
				end
			end

			VirtualScroller.clearHeightCache(Manager)
			ExplorerFrame.updateExpandedVisuals(Manager)
			VirtualScroller.rebuildAndUpdate(Manager, false)

			profileend()
			profileend()
		end),

		queryInput.Focused:Connect(function()

		end),
		selectQueried.Activated:Connect(function()
			local queried = {}
			for eid in world:query(components.IsQueried):iter() do
				table.insert(queried, eid)
			end
			Manager.setExplorerEntitiesAsSelection(queried, true)
		end),
	}
end

function Manager.init(onClose, connections, jexplorerWidget)
	local instances = connections:extend(cleanup.destroy)

	local jexplorerUi = UITemplates.JexplorerUi {
		Parent = jexplorerWidget
	}

	local instanceTree = jexplorerUi.InstanceTree

	local name = "jexplorer_instance_storage"
	local storage = game:GetService("ServerStorage"):FindFirstChild(name) or Instance.new("Folder")
	storage.Name = name
	storage.Parent = game:GetService("ServerStorage")
	Manager.Storage = storage
	
	local world = Jecs.world()
	local queryWorld = Jecs.world()

	world:remove(Jecs.ChildOf, Jecs.pair(Jecs.OnDeleteTarget, Jecs.Delete))
	Manager.WidgetState = {
		World = world,
		QueryWorld = queryWorld,
		FrameWorld = Jecs.world(),

		Connections = connections,
		Widget = jexplorerWidget,
		Entities = {},
		Tabs = {},
		RepoProxies = {},
		CurrentSelection = {},
		Favorited = {},
		HierarchyVersion = 0,
		JExplorerUI = jexplorerUi,
		SavedState = nil :: any,
		DefaultInstanceActionsArray = nil :: any,
		InstanceContextMenus = nil :: any,
		MiscContextMenus = nil :: any,
		OnClose = onClose,
		IsDragging = false
	}
	Manager.AbstractEntClasses = {
		Favorited = "JEXP_ABSTRACT_Favorited"
	}

	local state = Manager.WidgetState
	local components = Manager.Components
	local topbar = jexplorerUi.Topbar

	local queryInput = topbar.QueryInput
	local selectQueried = queryInput.SelectQueried
	
	Manager.InstTreeAbsoluteSizeY = instanceTree.AbsoluteSize.Y
	
	if getGlobalConfigValue("reset_state") == true then
		SavedState.save(SavedState.get_default(Manager))
	end

	if getGlobalConfigValue("data_version") then
		local tbl = plugin:GetSetting("Jexplorer_SavedState")
		tbl.data_version = getGlobalConfigValue("data_version")
	end
	local loaders, savedState = Manager.loadState(SavedState.load(Manager))
	local sheet = loaders.style()
	VersionControl.Versions = loaders.versions()
	loaders.order()
	loaders.invisible()
	
	Manager.WidgetState.SavedState = savedState

	Manager.Style = sheet
	sheet.Sheet.Parent = jexplorerWidget

	--sheet:SetToken("QueryInputTextSize", jexplorerUi.Topbar.QueryInput.AbsoluteSize.Y - 1, true)
	sheet:Link(jexplorerUi)

	StyleEditor.init(Manager)
	SettingEditor.init(Manager)
	if IS_EDIT then
		OrderEditor.init(Manager)
		VersionControl.init(Manager)
		InstanceVisibilityEditor.init(Manager)
		PropertyEditor.init(Manager)
	end
	--ContextMenuEditor.init(Manager)

	loaders.settings()
	loaders.repo_proxies()
	shared.Jexplorer.__modify:Fire()

	local settings = getGlobalConfigValue("settings")
	if settings then
		for k, v in settings do
			Manager.setSetting(k, v)
		end
	end

	local favoritedInstancesEntity = HierarchyState.createVirtualEntity(
		Manager,
		{
			ClassName = Manager.AbstractEntClasses.Favorited,
			Name = "Favorites",
			ChildAmount = 0,
			ClassIcon = {
				Image = "rbxassetid://12982756171",
				ImageRectOffset = Vector2.zero,
				ImageRectSize = Vector2.zero
			},
			PropTags = {
				getPropertyCt(world, "ClassName"),
				getPropertyCt(world, "Name")
			}
		},
		{
			GetChildren = function(self)
				return state.Favorited
			end,
			IsDescendantOf = function(self)
				return false
			end,
			IsA = function(self, classname)
				return classname == Manager.AbstractEntClasses.Favorited
			end,
			GetTags = function()
				return {}
			end,
			FindFirstChildOfClass = function()
				return nil
			end,
			GetDebugId = function()
				return "JEXP_FAVORITED"
			end,
		}
	)
	
	ExplorerFrame.initializeFrameCaches(Manager)
	local topbarMenuDropdown = CreateOptionsDropdown(Manager, components, topbar)

	initRegisterPluginMenusAndActions(state, components, favoritedInstancesEntity)
	
	InsertMenu.init(Manager)

	local tagAddedSignals, tagRemovedSignals, tagAdded, tagRemoved = initRegisterTagListeners(state, components)
	local scrollTrackerConnection, scrollTrackerThread = initStartTrackScrolling(state)

	local entities = {favoritedInstancesEntity}
	initCreateEntities(state, components, entities)

	ContextMenuEditor.init(Manager)

	Manager.AllTab = Manager.registerTab("All", entities, false, false, false)
	-- Wait until robloxs scrollingframe update
	task.delay(1.5, Manager.AllTab.Toggle)

	loaders.tabs()

	local widgets: {DockWidgetPluginGui} = {
		jexplorerWidget,
		StyleEditor.Widget,
		SettingEditor.Widget,
		OrderEditor.Widget,
		VersionControl.Widget,
		VersionControl.InstanceHistoryWidget,
		VersionControl.SourceViewerWidget,
		VersionControl.VersionViewerWidget,
		InstanceVisibilityEditor.Widget,
		PropertyEditor.Widget,
		ContextMenuEditor.Widget
	}

	instances:add_many({
		plugin,
		storage
	})

	local scriptConnections = initConnections(state, components, topbarMenuDropdown)
	connections:add_many(scriptConnections)
	connections:add_many({
		tagAdded,
		tagRemoved,
		scrollTrackerConnection
	})
	connections:extend(cleanup.call, {
		function()
			for _, v in widgets do
				v.Enabled = false
			end
			for _, v in Manager.PluginActions do
				v:Destroy()
			end
		end,
		function()
			for _, v in tagRemovedSignals do
				v:Disconnect()
			end
			for _, v in tagAddedSignals do
				v:Disconnect()
			end
			--ScriptEditorService:DeregisterScriptAnalysisCallback("JEXP_diagnostics_listener")
		end,
	})

	local function flushCycle()
		local suc1 = HierarchyState.flushOnChildAddedQueue(Manager)
		local suc2 = HierarchyState.flushOnChildRemovedQueue(Manager)
		local suc3 = HierarchyState.flushEntityCleanupQueue(Manager)
		ExplorerFrame.stepFlushFrameSetParentQueue(Manager)
		ExplorerFrame.flushFrameReuseQueue(Manager)
		ExplorerFrame.flushExplorerFrameTagAssignQueue(Manager)
		
		if suc1 or suc2 or suc3 then
			Manager.DeferredTaskScheduler.HierarchyChildrenMapNeedsUpdate = true
		end
	end

	local function reuseCycle()
		if Manager.DeferredTaskScheduler.HierarchyChildrenMapNeedsUpdate then
			Manager.DeferredTaskScheduler.HierarchyChildrenMapNeedsUpdate = false
			VirtualScroller.rebuildAndUpdate(Manager, false)
		end
	end
	
	local function cycleInterval(t: number)
		if t == 0 then
			task.wait()
		else
			task.wait(t)
		end
	end

	local threads = connections:extend(task.cancel, {
		scrollTrackerThread,
		task.spawn(function()
			while true do
				cycleInterval(Manager.getSetting("FlushCycleInterval"))
				flushCycle()
			end
		end),
		task.spawn(function()
			while true do
				cycleInterval(Manager.getSetting("FrameReuseCycleInterval"))
				reuseCycle()
			end
		end),
		task.spawn(function()
			while true do
				cycleInterval(Manager.getSetting("EntityCleanupCycleInterval"))
				HierarchyState.stepFlushEntityDeletionQueue(Manager)
			end
		end),
		task.spawn(function()
			while true do
				cycleInterval(Manager.getSetting("EntityCreationCycleInterval"))
				local changed = HierarchyState.flushEntityCreationQueue(Manager)
				if changed then
					Manager.DeferredTaskScheduler.HierarchyChildrenMapNeedsUpdate = true
				end
			end
		end),
	})

	jexplorerUi.Parent = jexplorerWidget
end

Manager.ChildOf = ChildOf

return Manager