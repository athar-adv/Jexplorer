--!optimize 2
--!strict

--[[
	Main manager module for keeping track of widget state
	
	Sorry for the lack of comments, i kinda just gave up ngl
]]

local plugin = script:FindFirstAncestorOfClass("Plugin")

local ScriptEditorService = game:GetService("ScriptEditorService")
local StudioService = game:GetService("StudioService")
local Selection = game:GetService("Selection")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local SerializationService = game:GetService("SerializationService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CollectionService = game:GetService('CollectionService')
local AssetService = game:GetService("AssetService")
local HttpService = game:GetService("HttpService")
local ScriptEditorService = game:GetService('ScriptEditorService')
local TextService = game:GetService("TextService")
local CoreGui = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReflectionService = game:GetService("ReflectionService")
local LocalizationService = game:GetService("LocalizationService")

local IS_EDIT = RunService:IsEdit()

local main = script.Parent

local utilities = main.Utilities
local editors = main.Editors
--local ui = main.UI

local Jecs = require(main.Jecs)
local Types = require(main.Types)

local StyleEditor = require(editors.StyleEditor)
local SettingEditor = require(editors.SettingEditor)
local OrderEditor = require(editors.OrderEditor)
local VersionControl = require(editors.VersionControl)
local InstanceVisibilityEditor = require(editors.InstanceVisibilityEditor)
local PropertyEditor = require(editors.PropertyEditor)
local ContextMenuEditor = require(editors.ContextMenuEditor)

local PluginUI = require(utilities.PluginUI)
local Style = require(utilities.Style)
local UDF = require(utilities.UDF)
local JQL = require(utilities.JQL)
local SavedState = require(utilities.SavedState)
local UITemplates = require(utilities.UITemplates)

local ItemGroup = require(utilities.Vendor.ItemGroup)
local Signal = require(utilities.Vendor.SimpleSignal)
local cleanup = ItemGroup.cleanup

local InstanceUtility = require(utilities.Small.InstanceUtility)
local Selector = require(utilities.Small.Selector)
local ClassIcon = require(utilities.Small.ClassIcon)
local childrenOf = require(utilities.Small.ChildrenOf)
local getClampedXY = require(utilities.Small.GetClampedXY)
local getClassPropMap = require(utilities.Small.GetClassPropMap)

local getId = PluginUI.getId
local rule = Style.rule
local var = Style.var

local index = InstanceUtility.index
local newindex = InstanceUtility.newindex

local rawindex = InstanceUtility.rawindex
local rawnewindex = InstanceUtility.rawnewindex

type WidgetState = Types.WidgetState
type StudioIconResult = Types.StudioIconResult
type ExplorerFrame = Types.ExplorerFrame
type ExplorerEntity = Types.ExplorerEntity
type Tab = Types.Tab

type World = Types.World
type ItemGroup<T=any> = ItemGroup.ItemGroup<T>

local downKeys: {[Enum.KeyCode]: boolean?} = {}
local activeInputs: {[Enum.UserInputType]: boolean?} = {}

local componentMap: {[string]: Jecs.Id<any>} = {}
local tagMap: {[string]: Jecs.Id} = {}
local classComponentCache: {[string]: {Jecs.Id}} = {} -- [ClassName] = { Component }

local instanceToEntity: {[Instance]: ExplorerEntity} = {}
local pooledInstanceFrames: {ExplorerFrame} = {}
local frameToInstanceFrame: {[Instance]: ExplorerFrame} = {}

local tagAssignQueue: {{frame: ExplorerFrame, entity: ExplorerEntity}} = {}
local frameReuseQueue: {ExplorerEntity} = {}
local entityPropAssignQueue: { {ty: "virtual" | "instance", ent: ExplorerEntity} } = {}
local entityCleanupQueue: {ExplorerEntity} = {}
local onChildAddedQueue: { {child: ExplorerEntity, parent: ExplorerEntity} } = {}
local onChildRemovedQueue: { {child: ExplorerEntity, parent: ExplorerEntity} } = {}
local entityCreationQueue: { {parent: ExplorerEntity, children: {Instance}} } = {}
local entityDeleteQueue: {ExplorerEntity} = {}
local currentSelectionCache: {Instance} = {}
local entityStateCache = {}
local instanceChildrenWasLoaded: {[ExplorerEntity]: boolean} = {}

local debugIdToInstance = setmetatable({}, {__mode = "v"})

local classNameCache: {[ExplorerEntity]: string} = {}
local nameCache: {[ExplorerEntity]: string} = {}
local childAmountCache: {[ExplorerEntity]: number} = {}
local tabFrameToTab: {[Instance]: Tab} = {}
local currentTabs: {Tab} = {}
local onceDebounce = {}

local selectedQuery: Jecs.Query<Instance>
local notSelectedQuery: Jecs.Query<ExplorerFrame>
local withoutIsQueried: Jecs.Query<>
local unassignedFrameQuery: Jecs.Query<>

local instTreeAbsoluteSizeY: number = 0
local allTab: Tab

-- Properties which get assigned their own tag when their value exists/is changed
local TAGGED_PROPERTIES = {
	"RunContext", "Enabled", "Name", "ClassName"
}

local PLACE_ID = tostring(game.PlaceId)

local INSTANCE_INSERT_INFO = require(utilities.Info.InstanceInsertInfo)
local RULE_NO_SAVE_TAG = "DontSaveRule"
local invisibleClasses = InstanceVisibilityEditor.InvisibleClasses

local hierarchyCache = {
	childrenMap = {} :: {[ExplorerEntity]: {ExplorerEntity}},
	roots = {} :: {ExplorerEntity},
	--expandedHeights = {} :: {[ExplorerEntity]: number}
}
local heightCache = {}
local heightCacheVersion = 0
local lastHeightCacheVersion = -1

-- Track which entities need height recalculation
local dirtyHeights = {}

local classPriorityCache = {}
local lastCacheVersion = -1
local lastPriorityVersion = -1

local recentlyReusedEntities = {}
local reuseDebounceTime = {}
local isScrolling = false
local childMapNeedsUpdate = false
local isVirtualScrollerUpdating = false
local lastScrollTime = 0

local tabInsertListener: RBXScriptConnection?
local isCurrentlyPickingTabRoots = false
local cachedFlatList, cachedFlatIndex = nil, nil
local targetTab: Tab?
local currentlyOpenTab: Tab?

local onTagAddedListeners = {}
local onTagRemovedListeners = {}

-- Target amount of pooled instance frames
local instanceFramePoolTarget = 70

local studioSettings = settings().Studio
local format = string.format

local profilebegin = debug.profilebegin
local profileend = debug.profileend
--local noop = function(...) end

--local profilebegin = noop
--local profileend = noop
--local has = Jecs._WORLD.has

local Manager = {
	InstanceToEntity = instanceToEntity,
	FrameToInstanceFrame = frameToInstanceFrame,
	Jecs = Jecs,
	SelectionChanged = Signal.new(),
	-- Will be initialized by the main plugin script before anything else runs so no problem
} :: Types.Manager

local showInsertInstanceMenu
local APIMap: {[string]: {[string]: any}}

local function createPluginAction(actionId: string, text: string, statusTip: string, iconId: string?, allowBinding: boolean?)
	local action = plugin:CreatePluginAction(
		actionId, text, statusTip, iconId, allowBinding
	)
	action.Name = actionId
	return action
end

local function ChildOf(c: ExplorerEntity)
	return Jecs.pair(Jecs.ChildOf, c)
end

local function widgetIsJexp(g: Instance)
	local state = Manager.WidgetState
	return 
		g == state.Widget
	or	g == StyleEditor.Widget
	or	g == OrderEditor.Widget
	or	g == SettingEditor.Widget
	or	g == PropertyEditor.Widget
	or	g == ContextMenuEditor.Widget
	or	g == VersionControl.VersionViewerWidget
	or	g == VersionControl.Widget
	or	g == VersionControl.SourceViewerWidget
	or	g == VersionControl.InstanceHistoryWidget
	or	g == InstanceVisibilityEditor.Widget
end

local function getGlobalConfigValue(k: string): any?
	local configs = shared.JexplorerConfigs
	if configs then
		return configs[k]
	end
	return nil
end

local function getChildAmount(entity: ExplorerEntity)
	return childAmountCache[entity] or 0
end

local function invalidateEntityStateCache(entity: ExplorerEntity)
	entityStateCache[entity] = nil
end

local function isEntityInvisible(world: World, entity: ExplorerEntity)
	profilebegin("Micro::isEntityInvisible")
	local components = Manager.Components
	local is =
		world:has(entity, components.Invisible)
		or	world:has(entity, components.QueryInvisible)
		or	invisibleClasses[classNameCache[entity]]
	profileend()
	return is
end

local function isEntityGone(world: World, entity: ExplorerEntity)
	--profilebegin("Micro::isEntityGone")
	local components = Manager.Components
	local is = world:has(entity, components.Deleted) or not world:contains(entity)
	--profileend()
	return is
end

local function isEntityExpanded(world: World, entity: ExplorerEntity)
	local components = Manager.Components
	return world:has(entity, components.Expanded) or world:has(entity, components.QueryExpanded)
end

local function parent_of(ent: ExplorerEntity): ExplorerEntity?
	local world = Manager.WidgetState.World
	local components = Manager.Components

	if world:has(ent, components.DisplayTopLevel) then
		return nil
	else
		return world:parent(ent)
	end
end

local function invalidateEntityHeightCache(world: World, entity: ExplorerEntity)
	heightCache[entity] = nil
	dirtyHeights[entity] = true
	local parent = parent_of(entity)
	while parent do
		heightCache[parent] = nil
		dirtyHeights[parent] = true
		parent = parent_of(parent)
	end

	heightCacheVersion += 1
end

local function getTaggedPropertyTag(propName: string, targetedValue: string)
	return `JEXP_TAGGED_{propName}_{targetedValue}`
end

local function instance_of(ent: ExplorerEntity): Instance?
	local world = Manager.WidgetState.World
	local components = Manager.Components
	return world:get(ent, components.Instance)
end

local function frame_of(ent: ExplorerEntity): typeof(main.__legacy.UI.InstanceFrame)?
	local world = Manager.WidgetState.FrameWorld
	local components = Manager.Components
	return world:get(ent, components.Instance)
end

local function once<T...>(fn: (T...) -> (...any), ...: T...)
	if onceDebounce[fn] then return end
	onceDebounce[fn] = true
	fn(...)
end

local function printGoneStatus(ents: {ExplorerEntity})
	local tbl = {}
	for k, v in ents do
		tbl[k] = isEntityGone(Manager.WidgetState.World, v)
	end
	print(tbl)
end

local function isInstanceJexpUi(inst: Instance): boolean
	if widgetIsJexp(inst) then return true end
	
	local g = inst:FindFirstAncestorOfClass("DockWidgetPluginGui")
	return g ~= nil and widgetIsJexp(g)
end

local function getPropertyComponentsForClass(world: World, className: string)
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
		local component = componentMap[k]
		if not component then
			component = world:entity()
			componentMap[k] = component
		end

		table.insert(components, component)
	end

	classComponentCache[className] = components
	return components
end

local function getPropertyCt(world: World, propName: string)
	local ct = componentMap[propName]
	if not ct then
		ct = world:entity()
		componentMap[propName] = ct
	end
	return ct
end

local function computedtbl(fn: (ser: {[any]: any}) -> ())
	local tbl = {}
	fn(tbl :: any)
	return tbl :: any
end

local function ensuretbl(tbl: any, k: any): any
	local v = tbl[k]
	if v then return v end
	local new = {}
	tbl[k] = new
	return new
end

local function into_hierarchy_update_queue(world: World, entity: ExplorerEntity, new_parent: ExplorerEntity?)
	local old_parent = parent_of(entity)
	if old_parent then
		table.insert(onChildRemovedQueue, {child = entity, parent = old_parent})
	end
	if new_parent then
		table.insert(onChildAddedQueue, {child = entity, parent = new_parent})
	else
		table.insert(entityCleanupQueue, entity)
	end
end

local function update_parent(world: World, entity: ExplorerEntity, new_parent: ExplorerEntity?)
	local old_parent = parent_of(entity)
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

local function deregisterFromQueryWorld(world: World, queryWorld: World, entity: ExplorerEntity)
	local components = Manager.Components

	local queryEntity = world:get(entity, components.LinkedQueryEntity)
	if queryEntity then
		local linked = queryWorld:get(queryEntity, components.QueryLinkedEntities)
		if linked then
			if #linked == 1 then
				queryWorld:delete(queryEntity)
			else
				local idx = table.find(linked, entity)
				if idx then
					table.remove(linked, idx)
				end
			end
		end
	end
	world:remove(entity, components.LinkedQueryEntity)
end

local function registerToQueryWorld(world: World, queryWorld: World, entity: ExplorerEntity, className: string, tags: {Jecs.Id<any>}?)
	if not className then
		warn("classname aint it")
		return
	end

	local components = Manager.Components
	local classComponents = table.clone(getPropertyComponentsForClass(queryWorld, className))
	if tags then
		table.move(tags, 1, #tags, #classComponents + 1, classComponents)
	end

	local queryTbl = table.clone(classComponents)
	table.insert(queryTbl, 1, components.QueryLinkedEntities)

	for queryEntity, linked in queryWorld:query(unpack(queryTbl)):iter() do
		table.insert(linked, entity)
		world:set(entity, components.LinkedQueryEntity, queryEntity)
		return queryEntity
	end

	-- Query entity not found, create new
	local queryEntity = queryWorld:entity()
	local linked = {entity}
	queryWorld:set(queryEntity, components.QueryLinkedEntities, linked)
	world:set(entity, components.LinkedQueryEntity, queryEntity)

	Jecs.bulk_insert(queryWorld, queryEntity, classComponents, {})
	return queryEntity
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

local function toggleExplorerFrameSelection(frame: ExplorerFrame, enabled: boolean)
	local frameInst = frame_of(frame)
	if not frameInst then return end

	profilebegin("ExplorerFrame::ToggleSelection")
	local has = frameInst:HasTag("JEXP_Selected")
	if enabled and not has then
		frameInst:AddTag("JEXP_Selected")
	elseif not enabled and has then
		frameInst:RemoveTag("JEXP_Selected")
	end
	profileend()
end

local function reuseExplorerFrame(frame: ExplorerFrame)
	local state = Manager.WidgetState
	local frameWorld = state.FrameWorld
	local components = Manager.Components

	local currentEntity, frameInst = frameWorld:get(frame, components.Entity, components.Instance)
	if not currentEntity or not frameInst then return end

	profilebegin("ExplorerFrame::Reuse");
	(frameInst::any).Visible = false
	if currentEntity and not table.find(frameReuseQueue, currentEntity) then
		table.insert(frameReuseQueue, currentEntity)
		frameWorld:remove(frame, components.Entity)
	end

	profileend()
end

local function getFrameTags(instance: any)
	local tags = {}
	for _, prop in TAGGED_PROPERTIES do
		local success, value = pcall(index, instance, prop)
		if success and value ~= nil then
			table.insert(tags, getTaggedPropertyTag(prop, typeof(value) == "EnumItem" and value.Name or tostring(value)))
		end
	end
	for _, tag in instance:GetTags() do
		table.insert(tags, `JEXP_TAG_{tag}`)
	end
	return tags
end

local function flushEntityPropAssignQueue()
	if #entityPropAssignQueue == 0 then return false end

	local world = Manager.WidgetState.World
	local queryWorld = Manager.WidgetState.QueryWorld
	local components = Manager.Components

	profilebegin("Manager::flushEntityPropAssignQueue")
	for _, data in entityPropAssignQueue do
		local ent = data.ent
		local instance = world:get(ent, components.Instance)
		if not instance then continue end
		
		local connections = assert(world:get(ent, components.Connections))
		
		local className = instance.ClassName
		nameCache[ent] = instance.Name
		classNameCache[ent] = className
		childAmountCache[ent] = #instance:GetChildren()
		debugIdToInstance[instance:GetDebugId()] = instance
		--hierarchyCache.expandedHeights[ent] = 1
		
		if data.ty ~= "instance" then continue end
		local appliedTaggedProps = {}
		local props = getClassPropMap(className)
		assert(props)
		
		local tags = {}
		
		for _, name in TAGGED_PROPERTIES do
			if not props[name] then continue end
			table.insert(appliedTaggedProps, name)
		end
		for _, tag in instance:GetTags() do
			local comp = tagMap[tag]
			if not comp then continue end

			table.insert(tags, comp)
		end
		
		local handlers = {}
		for _, v in appliedTaggedProps do
			local success, oldValue = pcall(rawindex, instance, v)
			if not success then continue end

			local function onChange()
				local frame = world:get(ent, components.Frame)
				if not frame then return end
				
				local frameInst = frame_of(frame)
				if not frameInst then return end

				local value = rawindex(instance, v)
				local oldTag = getTaggedPropertyTag(v, typeof(oldValue) == "EnumItem" and oldValue.Name or tostring(oldValue))
				local newTag = getTaggedPropertyTag(v, typeof(value) == "EnumItem" and value.Name or tostring(value))

				frameInst:RemoveTag(oldTag)
				frameInst:AddTag(newTag)
				oldValue = value
			end
			handlers[v] = onChange
		end

		if instance:IsA("LuaSourceContainer") then
			local src = ScriptEditorService:GetEditorSource(instance)
			VersionControl.createInstanceVersion(instance, "Source", src)
		end
		
		connections:add_many({
			rawindex(instance, "Changed"):Connect(function(prop: string)
				--VersionControl.onInstancePropChange(instance, prop, rawindex(instance, prop))

				if prop == "Name" then
					nameCache[ent] = instance.Name
					local frame = world:get(ent, components.Frame)
					if frame then
						local frameInst = frame_of(frame)
						if frameInst then
							local main = frameInst:FindFirstChild("Main")
							if main and main:FindFirstChild("InstanceName") and main.InstanceName.Text ~= instance.Name then
								main.InstanceName.Text = instance.Name
							end
						end
					end
				elseif prop == "ClassName" then
					classNameCache[ent] = instance.ClassName
				end
				local handler = handlers[prop]
				if not handler then return end
				handler()
			end),
			rawindex(instance, "ChildAdded"):Connect(function(child: Instance)
				local childEntity = instanceToEntity[child] or Manager.createInstanceEntity(child, ent)
				if not childEntity or world:has(childEntity, components.AncestryLocked) then
					return
				end

				if isInstanceJexpUi(child) then return end
				if child:IsDescendantOf(CoreGui) and child:FindFirstAncestor("DraggerUI") then return end

				into_hierarchy_update_queue(world, childEntity, ent)
			end),
			rawindex(instance, "ChildRemoved"):Connect(function(child: Instance)
				local childEntity = instanceToEntity[child] or Manager.createInstanceEntity(child, ent)
				if not childEntity or world:has(childEntity, components.AncestryLocked) then
					return
				end

				if isInstanceJexpUi(child) then return end
				if child:IsDescendantOf(CoreGui) and child:FindFirstAncestor("DraggerUI") then return end

				-- Handled in game.DescendantRemoving
				if child.Parent == nil then
					return
				end

				local new_parent = world:parent(childEntity)
				if not new_parent then return end
				
				into_hierarchy_update_queue(world, childEntity, new_parent)
			end)
		})
		
		deregisterFromQueryWorld(world, queryWorld, ent)
		registerToQueryWorld(world, queryWorld, ent, className, tags)
	end
	table.clear(entityPropAssignQueue)

	profileend()
	return true
end

local function flushTagAssignQueue()
	if #tagAssignQueue == 0 then return false end

	local state = Manager.WidgetState
	local components = Manager.Components

	local world = state.World
	local frameWorld = state.FrameWorld

	profilebegin("Manager::flushTagAssignQueue")
	for _, v in tagAssignQueue do
		local frame, entity = v.frame, v.entity
		local frameInst = frame_of(frame)
		if not frameInst then continue end
		
		local frameState = frameWorld:get(frame, components.FrameState)
		if not frameState then continue end
		
		local inst = world:get(entity, components.Instance)
		if not inst then continue end
		
		local scriptErrors = world:get(entity, components.ScriptErrors)
		local scriptWarns = world:get(entity, components.ScriptWarns)

		frameInst.Main.PendingChanges.Visible = world:has(entity, components.PendingChanges)
		for _, v in frameState.tagsToRemove do
			frameInst:RemoveTag(v)
		end
		frameState.tagsToRemove = getFrameTags(inst)
		if scriptErrors and #scriptErrors > 0 then
			table.insert(frameState.tagsToRemove, "JEXP_ScriptError")
		elseif scriptWarns and #scriptWarns > 0 then
			table.insert(frameState.tagsToRemove, "JEXP_ScriptWarn")
		end
		for _, tag in frameState.tagsToRemove do
			if frameInst:HasTag(tag) then continue end
			frameInst:AddTag(tag)
		end
	end
	table.clear(tagAssignQueue)
	profileend()
	return true
end

local function updateEntityOrder(world: World, entity: ExplorerEntity, newParent: ExplorerEntity?)
	profilebegin("Manager::updateEntityOrder")
	local state = Manager.WidgetState
	local components = Manager.Components

	local i = table.find(state.Entities, entity)
	if i then
		table.remove(state.Entities, i)
	end

	table.insert(state.Entities, entity)
	profileend()
end

local assignExplorerFrame
local function flushFrameReuseQueue(depth: number?)
	profilebegin("Manager::flushFrameReuseQueue")
	if #frameReuseQueue == 0 then return false end
	local depth = depth or 0

	local state = Manager.WidgetState
	local world = state.World
	local children = {}
	local tounassign = {}
	
	local cn = 0
	
	for _, entity in frameReuseQueue do
		--if not world:contains(entity) then continue end
		profilebegin("Manager::reuseInstanceFrames")

		local world = Manager.WidgetState.World
		local components = Manager.Components
		
		local frame = world:get(entity, components.Frame)
		if frame then
			world:remove(entity, components.Frame)
			table.insert(tounassign, frame)
			table.insert(pooledInstanceFrames, frame::any)
		end
		local entityChildren = hierarchyCache.childrenMap[entity]
		if entityChildren then
			local n = #entityChildren
			table.move(entityChildren, 1, n, cn + 1, children)
			cn += n
		end
		profileend()
	end
	for _, frame in tounassign do
		assignExplorerFrame(frame, nil)
	end
	flushTagAssignQueue()

	table.clear(frameReuseQueue)
	for _, v in children do
		table.insert(frameReuseQueue, v)
	end
	--if depth < 2 then
	--	flushFrameReuseQueue(depth + 1)
	--end
	profileend()
	return true
end

function assignExplorerFrame(frame: ExplorerFrame, entity: ExplorerEntity?, parent: ExplorerEntity?)
	local state = Manager.WidgetState
	local components = Manager.Components
	local world = state.World
	local frameWorld = state.FrameWorld

	if entity == frameWorld:get(frame, components.Entity) then
		return
	end

	if entity and isEntityGone(world, entity) then
		reuseExplorerFrame(frame)
		return
	end

	local frameState = frameWorld:get(frame, components.FrameState)
	if not frameState then return end

	local frameInst = frame_of(frame)
	if not frameInst then return end

	frameState.isAssigning = true
	local parentFrame
	if parent then
		parentFrame = world:get(parent, components.Frame)
		if not parentFrame then
			frameState.isAssigning = false
			return
		end
	end

	profilebegin("InstanceFrame::Assign")

	if not entity then
		frameWorld:remove(frame, components.Entity)
		local oldParent = frameWorld:parent(frame)
		if oldParent then
			frameWorld:remove(frame, ChildOf(oldParent))
		end

		frameInst.Main.Insert.Visible = false
		frameInst.Visible = false
		frameState.isAssigning = false
		return
	end
	--local existingFrame = world:get(entity, components.Frame)
	--if existingFrame then
	--	reuseExplorerFrame(existingFrame)
	--end
	world:set(entity, components.Frame, frame)

	frameWorld:set(frame, components.Entity, entity)
	if parentFrame then
		frameWorld:add(frame, ChildOf(parentFrame))
	end

	local instance: Instance? = world:get(entity, components.Instance)
	if not instance then
		frameState.isAssigning = false
		return
	end 
	table.insert(tagAssignQueue, {
		frame = frame,
		entity = entity
	})
	frameInst.Visible = true

	toggleExplorerFrameSelection(frame, world:has(entity, components.Selected))
	local sheet = Manager.Style

	local className = instance.ClassName
	local slctr = Selector.getIconSelector(nil, className)
	local icon = ClassIcon.getIcon(className)
	if icon and not sheet:FindRule(slctr) then
		local name = `ClassIcon_{className}`
		local image = string.match(icon.Image, "[^/]+$")
		
		local newRule = rule(name, slctr, 0, {
			ImageRectOffset = icon.ImageRectOffset,
			ImageRectSize = icon.ImageRectSize,
			Image = var(`$BackgroundColor.R > 0.5 ? 'rbxasset://studio_svg_textures/Shared/InsertableObjects/Light/Standard/{image}' : 'rbxasset://studio_svg_textures/Shared/InsertableObjects/Dark/Standard/{image}'`)
		})
		newRule:AddTag(RULE_NO_SAVE_TAG)
		
		sheet:AddRules {
			newRule
		}
	end

	frameInst.Main.InstanceName.Text = instance.Name
	local arrow = frameInst.Main.Arrow
	if world:has(entity, components.ArrowInvisible) then
		-- Handled in updateVirtualScroller
		--arrow.Visible = false
	else
		if instance == game or getChildAmount(entity) == 0 then
			arrow.Visible = false
		else
			arrow.Visible = true
		end
		if isEntityExpanded(world, entity) then
			arrow.Rotation = 0
			frameInst.Children.Visible = true
		else
			arrow.Rotation = -90
			frameInst.Children.Visible = false
		end
	end

	if not state.LastSelectedEntity then
		state.LastSelectedEntity = nil
	end

	frameState.isLMBActive = false
	frameState.hasBeenSelected = false
	frameState.shouldDeselect = false

	local newParent
	if parent and parentFrame then
		local frameInst = frame_of(parentFrame)
		if frameInst then
			local children = frameInst:FindFirstChild("Children")
			if children then
				newParent = children.List
			end
		end
	else
		newParent = state.JExplorerUI.InstanceTree
	end
	if newParent == frameWorld:parent(frame) then
		frameState.isAssigning = false
		profileend()
		return
	end

	local link = instance:FindFirstChildOfClass("PackageLink")
	local main = frameInst.Main
	if link then
		main.PackageLinkIcon.Visible = true
		frameState.packageIconConn = frameInst:GetPropertyChangedSignal("Position"):Connect(function()
			local cumulativeX = 0
			local current = frameInst
			while current do
				if current.Name ~= "InstanceFrame" then break end
				cumulativeX += current.Children.AbsolutePosition.X
				current = current.Parent.Parent
			end

			local containerWidth = state.JExplorerUI.AbsoluteSize.X
			local distanceToEdge = containerWidth - cumulativeX
			if distanceToEdge == frameState.lastPackageIconPos then return end
			frameState.lastPackageIconPos = distanceToEdge

			local padding = 10

			main.PackageLinkIcon.Position = UDim2.new(
				0,
				distanceToEdge,
				main.PackageLinkIcon.Position.Y.Scale,
				main.PackageLinkIcon.Position.Y.Offset
			)
		end)
	else
		if frameState.packageIconConn then
			frameState.packageIconConn:Disconnect()
			frameState.packageIconConn = nil
		end
		main.PackageLinkIcon.Visible = false
	end

	pcall(rawnewindex, frameInst, "Parent", newParent)

	profileend()
	frameState.isAssigning = false
end

local function cleanupEntities(queueTable: {ExplorerEntity})
	profilebegin("Manager::cleanupEntitiesInTable")
	if #queueTable == 0 then return false end

	local state = Manager.WidgetState
	local world = state.World
	local queryWorld = state.QueryWorld
	local components = Manager.Components

	local groupsToFree = {}
	local entityIndexesToRemove = {}
	local seen = {}

	--for _, entity in entityCleanupQueue do
	--	world:add(entity, components.Deleted)
	--end

	local entities = state.Entities
	for _, entity in queueTable do
		-- Prevent double cleanups
		if seen[entity] then continue end
		seen[entity] = true
		--world:add(entity, components.Deleted)

		--cascadeUpdateExpandedHeights(world, entity)
		profilebegin("Manager::processImmediateCleaningTasks")
		local inst = world:get(entity, components.Instance)
		if inst then
			instanceToEntity[inst] = nil
		end

		local entityConnections = world:get(entity, components.Connections)
		if entityConnections then
			table.insert(groupsToFree, entityConnections)
		end

		--local idx = table.find(entities, entity)
		--if idx then
		--	table.insert(entityIndexesToRemove, idx)
		--end

		local frame = world:get(entity, components.Frame)
		if frame then
			reuseExplorerFrame(frame)
		end
		
		world:add(entity, components.Deleted)
		
		invalidateEntityHeightCache(world, entity)
		local parent = world:parent(entity)
		if parent then
			world:remove(entity, ChildOf(parent))
		end
		profileend()
	end

	profilebegin("Manager::cleanupEntity::processDeferredCleaningTasks")
	profilebegin("freeGroups")
	for _, group in groupsToFree do
		(group::ItemGroup):free()
	end
	profileend()
	profilebegin("removeEntityData")
	for _, entity in queueTable do
		classNameCache[entity] = nil
		nameCache[entity] = nil
		childAmountCache[entity] = nil
	end
	profileend()

	profilebegin("deregisterFromQueryWorld")
	for _, entity in queueTable do
		local linked = world:get(entity, components.LinkedQueryEntity)
		if not linked then continue end

		local list = queryWorld:get(linked, components.QueryLinkedEntities)
		if not list then continue--[[error("unexpected error: querylist not found")]] end

		local idx = table.find(list, entity)
		if idx then
			local n = #list
			list[idx] = list[n]
			list[n] = nil
		end
	end
	profileend()

	-- Handled in a seperate thread
	--flushFrameReuseQueue()

	profilebegin("deleteEntities")
	for _, entity in queueTable do
		--world:delete(entity)
		table.insert(entityDeleteQueue, entity)
	end
	profileend()

	table.clear(queueTable)
	profileend()
	profileend()
	return true
end

local function cleanupEntity(ent: ExplorerEntity)
	local state = Manager.WidgetState
	local world, components = state.World, Manager.Components
	world:add(ent, components.Deleted)

	table.insert(entityCleanupQueue, ent)
end

local function getScrollingOffsetFromTop(world: World, entity: ExplorerEntity, idx: number)
	local state = Manager.WidgetState
	local components = Manager.Components
	local sheet = Manager.Style

	local jexplorerUi = state.JExplorerUI

	local size: UDim2 = sheet:GetToken("InstanceFrameSize")
	local height = size.Y.Offset

	return height * (idx - 1)
end

local function calculateMatchScore(text: string, search: string)
	if search == "" then return 1 end

	local lowerText = text:lower()
	local lowerSearch = search:lower()
	if lowerText == lowerSearch then
		return 1000
	end

	if lowerText:sub(1, #lowerSearch) == lowerSearch then
		return 100
	end

	if lowerText:find(lowerSearch, 1, true) then
		return 50
	end

	local textIndex = 1
	local searchIndex = 1
	local matches = 0

	while textIndex <= #lowerText and searchIndex <= #lowerSearch do
		if lowerText:sub(textIndex, textIndex) == lowerSearch:sub(searchIndex, searchIndex) then
			matches = matches + 1
			searchIndex = searchIndex + 1
		end
		textIndex = textIndex + 1
	end

	if matches == #lowerSearch then
		return 10 + matches
	end

	return 0
end

local function getClassPriority(className: string): number
	profilebegin("Manager::getClassPriorityUncached")
	local priority = table.find(OrderEditor.ClassPriorities, className) or OrderEditor.DefaultPriority
	classPriorityCache[className] = priority
	profileend()
	return priority
end

local function addEntityPriorities(world: World, children: {ExplorerEntity}, priorities: any)
	profilebegin("Manager::getEntityPriorities")
	local components = Manager.Components

	if OrderEditor.PriorityVersion and OrderEditor.PriorityVersion ~= lastPriorityVersion then
		table.clear(classPriorityCache)
		lastPriorityVersion = OrderEditor.PriorityVersion
	end

	profilebegin("Manager::getEntityPriorities::collectEntityPriority")
	profilebegin("Manager::getEntityPriorities::collectEntityPriority::loop1")
	local n = 0
	for i, child in children do
		n += 1
		local classname = classNameCache[child]
		if classname then
			priorities[child] = classPriorityCache[classname] or getClassPriority(classname)
		end
	end
	profileend()
	profilebegin("Manager::getEntityPriorities::collectEntityPriority::loop2")
	for i = #children, 1, -1 do
		if not priorities[children[i]] then
			children[i] = children[n]
			children[n] = nil
			n -= 1
		end
	end
	profileend()

	profileend()
	profileend()

	return priorities
end

local function rebuildHierarchyCache()
	local state = Manager.WidgetState
	local components = Manager.Components
	local world = state.World

	local roots, childrenMap = {}, {}

	profilebegin("Manager::rebuildHierarchyCache")
	profilebegin("Manager::rebuildHierarchyCache::buildChildrenMap")
	
	for _, eid in state.Entities do
		if isEntityGone(world, eid) then continue end

		local parent = parent_of(eid)
		if not parent then
			table.insert(roots, eid)
		else
			local tbl = childrenMap[parent]
			if not tbl then
				tbl = {}
				childrenMap[parent] = tbl
			end
			table.insert(tbl, eid)
		end
	end

	profileend()
	profilebegin("Manager::rebuildHierarchyCache::collectPriorities")

	local tosort = {roots}

	local mergedPriorities = {}
	addEntityPriorities(world, roots, mergedPriorities)
	for parent, children in childrenMap do
		addEntityPriorities(world, children, mergedPriorities)
	end

	for parent, children in childrenMap do
		table.insert(tosort, children)
	end

	profileend()
	profilebegin("sort")
	local function sort(a, b)
		local priorityA = mergedPriorities[a]
		local priorityB = mergedPriorities[b]
		if priorityA ~= priorityB then
			return priorityA < priorityB
		end
		return nameCache[a] < nameCache[b]
	end

	-- Sort all at once for best performance
	for _, v in tosort do
		table.sort(v, sort)
	end

	profileend()

	hierarchyCache.childrenMap = childrenMap
	hierarchyCache.roots = roots
	lastCacheVersion = state.HierarchyVersion
	profileend()
	return childrenMap, roots
end

local function calculateDeepHeightOptimized(
	world: World, 
	expanded: Jecs.Id, 
	queryExpanded: Jecs.Id, 
	childrenMap: {[ExplorerEntity]: {ExplorerEntity}}, 
	entity: ExplorerEntity
): number
	if childAmountCache[entity] == 0 then return 1 end
	local isExpanded = world:has(entity, expanded) or world:has(entity, queryExpanded)
	if not isExpanded then
		return 1
	end
	if not dirtyHeights[entity] and heightCache[entity] then
		return heightCache[entity]
	end
	local children = childrenMap[entity]
	if not children or #children == 0 then
		heightCache[entity] = 1
		dirtyHeights[entity] = nil
		return 1
	end
	local totalHeight = 1
	for _, child in children do
		if not (isEntityInvisible(world, child) or isEntityGone(world, child)) then
			local childIsExpanded = world:has(child, expanded) or world:has(child, queryExpanded)
			if childIsExpanded then
				totalHeight += calculateDeepHeightOptimized(world, expanded, queryExpanded, childrenMap, child)
			else
				totalHeight += 1
			end
		end
	end

	heightCache[entity] = totalHeight
	dirtyHeights[entity] = nil
	return totalHeight
end

local function getFlattenedVisibleEntities(world: World, invisible: {ExplorerEntity}, isScroller: boolean): ({ExplorerEntity}, {[ExplorerEntity]: number})
	if isScroller and cachedFlatList and cachedFlatIndex then
		return cachedFlatList, cachedFlatIndex
	end
	profilebegin("Manager::getFlattenedVisibleEntities")
	local state = Manager.WidgetState
	local components = Manager.Components
	local currentVersion = state.HierarchyVersion
	local childrenMap: any, roots: any
	if currentVersion == lastCacheVersion then
		childrenMap = hierarchyCache.childrenMap
		roots = hierarchyCache.roots
	else
		childrenMap, roots = rebuildHierarchyCache()
	end

	local flatList = table.create(1000)
	local entityToIndex = {}
	local flatIndex = 0
	local invisibleIndex = #invisible
	local stack = table.create(200)
	local stackSize = 0

	-- Cache component lookups outside the loop
	local stateCache = entityStateCache

	profilebegin("traverse")

	-- Unroll root insertion (minor optimization)
	local rootCount = #roots
	for i = rootCount, 1, -1 do
		stackSize += 1
		stack[stackSize] = roots[i]
	end

	while stackSize > 0 do
		local entity = stack[stackSize]
		stackSize -= 1
		
		local state = stateCache[entity]
		if not state then
			profilebegin("generateentitystate")
			local invisible = isEntityInvisible(world, entity) or isEntityGone(world, entity)
			local expanded = isEntityExpanded(world, entity)
			state = {invisible = invisible, expanded = expanded}
			stateCache[entity] = state
			profileend()
		end
		
		if state.invisible then
			invisibleIndex += 1
			invisible[invisibleIndex] = entity
		else
			flatIndex += 1
			flatList[flatIndex] = entity
			
			if state.expanded then
				local children = childrenMap[entity]
				if children then
					local childCount = #children
					for i = 1, childCount do
						stackSize += 1
						stack[stackSize] = children[childCount - i + 1]
					end
				end
			end
		end
	end
	profileend()
	profilebegin("fillentitytoindex")
	for idx, v in flatList do
		entityToIndex[v] = idx
	end
	profileend()
	profileend()
	cachedFlatList, cachedFlatIndex = flatList, entityToIndex
	return flatList, entityToIndex
end

local function filterVisible(world: World, top: number, viewportHeight: number, isScroller: boolean)
	profilebegin("Manager::filterVisible")

	local components = Manager.Components
	local sheet = Manager.Style

	local size: UDim2 = sheet:GetToken("InstanceFrameSize")
	local height = size.Y.Offset

	local visible = {}
	local invisible = {}
	local expandedHeightIndex = {}

	local frameBuffer = Manager.getSetting("VirtualScrollFrameBuffer")

	local viewportBuffer = height * frameBuffer
	local effectiveViewportHeight = viewportHeight + viewportBuffer

	local flattenedEntities, entityToIndex = getFlattenedVisibleEntities(world, invisible, isScroller)
	local flatCount = #flattenedEntities
	local expandedStates = {} -- Sparse table, populated on-demand

	local topBound = top - viewportBuffer
	local bottomBound = top + effectiveViewportHeight
	local invisI = #invisible
	local visI = 0

	local componentsExpanded = components.Expanded
	local componentsQueryExpanded = components.QueryExpanded
	local childrenMap = hierarchyCache.childrenMap

	local startIndex = math.max(1, math.floor(topBound / height) + 1)
	
	for index = startIndex, flatCount do
		profilebegin("visiblecheck")
		local entity = flattenedEntities[index]
		local absoluteYOffset = height * (index - 1)

		-- Lazy load expanded state only when needed
		local isExpanded = expandedStates[index]
		if isExpanded == nil then
			isExpanded = isEntityExpanded(world, entity)
			expandedStates[index] = isExpanded
		end

		-- Early exit: if we're past the viewport and not expanded, we're done
		if absoluteYOffset > bottomBound then
			if not isExpanded then
				-- Add remaining entities to invisible and break
				for i = index, flatCount do
					invisI += 1
					invisible[invisI] = flattenedEntities[i]
				end
				profileend()
				break
			end
		end

		local shouldBeVisible

		if not isExpanded then
			shouldBeVisible = absoluteYOffset >= topBound and absoluteYOffset <= bottomBound
		else
			local expandedHeight = calculateDeepHeightOptimized(
				world,
				componentsExpanded,
				componentsQueryExpanded,
				childrenMap,
				entity
			)
			local expandedBottomOffset = absoluteYOffset + (height * expandedHeight)
			expandedHeightIndex[entity] = expandedHeight
			shouldBeVisible = (absoluteYOffset <= bottomBound and expandedBottomOffset >= topBound)

			-- Early exit: if expanded item is completely past viewport, we're done
			if absoluteYOffset > bottomBound then
				for i = index, flatCount do
					invisI += 1
					invisible[invisI] = flattenedEntities[i]
				end
				profileend()
				break
			end
		end

		if shouldBeVisible then
			visI += 1
			visible[visI] = {
				entity = entity,
				yoffset = absoluteYOffset
			}
		else
			-- Only add to invisible if before viewport (after viewport handled by break)
			if absoluteYOffset < topBound then
				invisI += 1
				invisible[invisI] = entity
			end
		end
		profileend()
	end

	profileend()
	return visible, invisible, entityToIndex, height, expandedHeightIndex
end

local function clearHeightCache()
	table.clear(heightCache)
	table.clear(dirtyHeights)
	heightCacheVersion += 1
end

local function updateVirtualScroller(isScroller: boolean?)
	local state = Manager.WidgetState
	local components = Manager.Components

	local jexplorerUi = state.JExplorerUI
	local world = state.World

	--if not Manager.getSetting("VirtualScrollingEnabled") then
	--	for entity, frame in world:query(components.Frame, components.Invisible):iter() do
	--		frame:Reuse()
	--	end
	--	for entity, frame in world:query(components.Frame, components.ArrowInvisible):iter() do
	--		frame.Instance.Main.Arrow.Visible = false
	--	end
	--	flushFrameReuseQueue()
	--	return
	--end
	if isScroller and isVirtualScrollerUpdating then
		--task.defer(updateVirtualScroller)
		return
	end
	profilebegin("Manager::updateVirtualScroller")

	isVirtualScrollerUpdating = true
	local top = jexplorerUi.InstanceTree.CanvasPosition.Y
	local visible, invisible, entityToIndex, height, expandedHeightIndex = filterVisible(world, top, instTreeAbsoluteSizeY, isScroller == true)

	local currentTime = os.clock()
	for _, entity in invisible do
		local frame = world:get(entity, components.Frame)
		if frame and not isScrolling then
			local lastReuseTime = reuseDebounceTime[entity] or 0

			if currentTime - lastReuseTime > Manager.getSetting("VirtualReuseCooldown") then
				reuseExplorerFrame(frame)
				reuseDebounceTime[entity] = currentTime
			end
		end
	end
	flushFrameReuseQueue()
	
	local assignLayoutOrders = {}
	local aloI = 1
	
	for _, info in visible do
		local entity, absoluteYOffset = info.entity, info.yoffset
		local instance = world:get(entity, components.Instance) :: Instance

		local frame = world:get(entity, components.Frame)
		
		reuseDebounceTime[entity] = nil
		
		local parent = parent_of(entity)
		if frame then
			assignExplorerFrame(frame, entity, parent)
		else
			local f = getExplorerFrame()
			assignExplorerFrame(f, entity, parent)
			frame = f
		end
		if not frame then continue end
		
		local frameInst = frame_of(frame)
		if not frameInst then continue end
		
		aloI += 1
		assignLayoutOrders[aloI] = {
			frame = frameInst,
			idx = entityToIndex[entity]
		}
		
		local children = hierarchyCache.childrenMap[entity]
		if not isScroller and children then
			local n = 0
			for _, child in children do
				if isEntityInvisible(world, child) then continue end
				n += 1
			end
			childAmountCache[entity] = n
		end
		
		if world:has(entity, components.ArrowInvisible) then
			frameInst.Main.Arrow.Visible = false
		else
			local arrowVisible = getChildAmount(entity) > 0
			frameInst.Main.Arrow.Visible = arrowVisible
		end

		if parent then
			local parentIndex = entityToIndex[parent]
			if parentIndex then
				local parentAbsoluteYOffset = height * parentIndex
				local relativeYOffset = absoluteYOffset - parentAbsoluteYOffset
				frameInst.Position = UDim2.fromOffset(0, relativeYOffset)
			else
				frameInst.Position = UDim2.fromOffset(0, absoluteYOffset)
			end
		else
			frameInst.Position = UDim2.fromOffset(0, absoluteYOffset)
		end
		local expandedHeight = expandedHeightIndex[entity]
		if expandedHeight then
			frameInst.Children.List.Size = UDim2.new(1, 0, 0, (expandedHeight - 1) * height)
		else
			frameInst.Children.List.Size = UDim2.new(1, 0, 1, 0)
		end
	end
	
	profilebegin("assignlayoutorder")
	
	local LAYOUT_ORDER = "LayoutOrder"
	for _, v in assignLayoutOrders do
		rawnewindex(v.frame, LAYOUT_ORDER, v.idx)
	end
	profileend()
	
	for frame in unassignedFrameQuery:iter() do
		reuseExplorerFrame(frame)
	end

	flushTagAssignQueue()
	isVirtualScrollerUpdating = false
	profileend()
end

local function updateExpandedVisuals(world: World, update: boolean, expandedCt: Jecs.Id?)
	profilebegin("Manager::toggleExpand")

	local components = Manager.Components
	local state = Manager.WidgetState
	local expandedCt = expandedCt or components.Expanded
	
	local anyCreated = false
	for entity, instance, frame in world:query(components.Instance, components.Frame, expandedCt):iter() do
		local frameInst = frame_of(frame)
		if not frameInst then continue end
		
		if instance == game then return end
		--for _, v in instance:GetChildren() do
		--	if instanceToEntity[v] then continue end
		--	anyCreated = true
		--	Manager.createInstanceEntity(v, entity)
		--end
		
		invalidateEntityHeightCache(world, entity)
		local arrow = frameInst.Main.Arrow
		local n = getChildAmount(entity)
		if not world:has(entity, components.ArrowInvisible) then
			arrow.Rotation = 0
			arrow.Visible = n > 0
		end
		
		local children = frameInst.Children
		children.Visible = true
		--hierarchyCache.expandedHeights[entity] = calculateDeepHeight(
		--	world,
		--	components.Expanded,
		--	hierarchyCache.childrenMap,
		--	{},
		--	entity
		--)
	end
	
	--if anyCreated then
	--	state.HierarchyVersion += 1
	--	flushEntityPropAssignQueue()
	--end
	if update then
		updateVirtualScroller()
	end
	profileend()
end

local function flushEntityCreationQueue()
	if #entityCreationQueue == 0 then return end
	local state = Manager.WidgetState
	local world = state.World
	local components = Manager.Components
	
	local clone = table.clone(entityCreationQueue)
	table.clear(entityCreationQueue)
	
	for _, v in clone do
		local parent = v.parent
		for _, child in v.children do
			if isInstanceJexpUi(child) then continue end
			if instanceToEntity[child] then continue end
			
			Manager.createInstanceEntity(child, parent)
		end
	end
	flushEntityPropAssignQueue()
	
	Manager.WidgetState.HierarchyVersion += 1
	updateVirtualScroller()
end

local function updateCollapsedVisuals(world: World, update: boolean)
	profilebegin("Manager::toggleExpand")

	local components = Manager.Components
	for entity, instance, frame in world:query(components.Instance, components.Frame):without(components.Expanded, components.QueryExpanded):iter() do
		local frameInst = frame_of(frame)
		if not frameInst then continue end
		
		local children = frameInst.Children
		world:remove(entity, components.Expanded)
		world:remove(entity, components.QueryExpanded)
		children.Visible = false
		
		frameInst.Main.Arrow.Rotation = -90
		
		for child, frame, _ in world:query(components.Frame, ChildOf(entity)):iter() do
			reuseExplorerFrame(frame)
		end
		invalidateEntityHeightCache(world, entity)
	end

	if update then
		updateVirtualScroller()
	end
	profileend()
end

-- TODO: Should probably make another version of this since i dont know how the hell this even works, but for now keep it
local function getEntitiesBetween(world: World, e1: ExplorerEntity, e2: ExplorerEntity): {ExplorerEntity}
	profilebegin("Manager::getEntitiesBetween")
	local visible = getFlattenedVisibleEntities(world, {}, false)
	local i1, i2
	for i, eid: any in visible do
		if eid == e1 then i1 = i end
		if eid == e2 then i2 = i end
	end
	if not i1 or not i2 then return {} end
	if i1 > i2 then i1, i2 = i2, i1 end
	local slice = {}
	for i = i1, i2 do
		table.insert(slice, visible[i])
	end
	profileend()
	return slice
end

local function updateSelectionVisuals(world: World, updateSelection: boolean)
	profilebegin("Manager::updateSelectionVisuals")
	local state = Manager.WidgetState
	local components = Manager.Components

	table.clear(state.CurrentSelection)
	local currentSelection = {}

	profilebegin("Manager::updateSelectionVisuals::iter")
	for entityId, instance in selectedQuery:iter() do
		local frame = world:get(entityId, components.Frame)

		if typeof(instance) == "Instance" then
			table.insert(currentSelection, instance)
		end
		table.insert(state.CurrentSelection, entityId)

		if frame then
			toggleExplorerFrameSelection(frame, true)
		end
	end
	for entityId, frame in notSelectedQuery:iter() do
		toggleExplorerFrameSelection(frame, false)
	end
	flushTagAssignQueue()

	profileend()
	if updateSelection then
		profilebegin("Manager::updateSelectionVisuals::setSelection")
		Selection:Set(currentSelection)
		profileend()
	end
end

local function setSelection(world: World, entities: {ExplorerEntity}, updateSelection: boolean)
	profilebegin("Manager::setSelection")
	local state = Manager.WidgetState
	local components = Manager.Components

	for entity in selectedQuery:iter() do
		world:remove(entity, components.Selected)
	end
	for _, entity in entities do
		world:add(entity, components.Selected)
	end

	state.CurrentSelection = entities
	state.LastSelectedEntity = entities[#entities]

	updateSelectionVisuals(world, updateSelection)
end

local function addEntitiesToSelection(world: World, entities: {ExplorerEntity}, updateSelection: boolean)
	local state = Manager.WidgetState
	local components = Manager.Components

	for _, entity in entities do
		world:add(entity, components.Selected)
	end
	table.move(entities, 1, #entities, #state.CurrentSelection + 1, state.CurrentSelection)
	state.LastSelectedEntity = entities[#entities]
	updateSelectionVisuals(world, updateSelection)
end

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

	state.HierarchyVersion += 1
	updateVirtualScroller()
	if id then
		ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
	end
end

local function toggleSelection(world: World, entity: ExplorerEntity, isCtrlHeld: boolean, isShiftHeld: boolean)
	profilebegin("Manager::toggleSelection")
	local components = Manager.Components
	local state = Manager.WidgetState

	if isCtrlHeld then
		-- Control select
		local currentlySelected = world:has(entity, components.Selected)
		if currentlySelected then
			world:remove(entity, components.Selected)
		else
			world:add(entity, components.Selected)
		end

		if not currentlySelected then
			state.LastSelectedEntity = entity
		end
	elseif isShiftHeld and state.LastSelectedEntity then
		-- Shift select
		local range = getEntitiesBetween(world, state.LastSelectedEntity, entity)
		profilebegin("Manager::toggleSelection::shiftSelect::addSelectedComponents")
		for _, eid in range do
			world:add(eid, components.Selected)
		end
		profileend()
	else
		-- Normal click
		for entityId in selectedQuery:iter() do
			world:remove(entityId, components.Selected)
		end

		world:add(entity, components.Selected)
		state.LastSelectedEntity = entity
	end

	updateSelectionVisuals(world, true)
	profileend()
end

local function startDraggingInstance(frame: ExplorerFrame)
	local state = Manager.WidgetState
	local components = Manager.Components
	profilebegin("InstanceFrame::beginDrag")

	local frameInst = frame_of(frame)
	local connections = state.FrameWorld:get(frame, components.Connections)
	assert(connections)

	-- Start drag operation
	local dragFrame = UITemplates.DragFrame()
	dragFrame:AddTag("JEXP_Selected")
	
	local amt = #state.CurrentSelection
	if amt == 0 then return end
	
	for _, v in state.CurrentSelection do
		local inst = instance_of(v)
		if not inst then continue end
		if inst.Parent == game then return end -- Cant drag a service
	end
	if amt == 1 then
		local instance = instance_of(state.CurrentSelection[1])
		if not instance then return end
		
		dragFrame.Main.InstanceName.Text = instance.Name
		local iconImage = dragFrame.Main.ClassIcon
		local icon = ClassIcon.getIcon(instance.ClassName)
		if not icon then
			profileend()
			return
		end

		iconImage.Image = icon.Image
		iconImage.ImageRectOffset = icon.ImageRectOffset
		iconImage.ImageRectSize = icon.ImageRectSize
	else
		dragFrame.Main.InstanceName.Text = `Instances x{amt}`
	end
	
	dragFrame.AnchorPoint = Vector2.new(0.2, 0)

	for _, v in dragFrame:GetDescendants() do
		if not v:IsA("GuiObject") then continue end
		v.Active = false
	end

	local dragConnections = connections:extend(cleanup.disconnect)

	do
		local pos = state.Widget:GetRelativeMousePosition()
		dragFrame.Position = UDim2.fromOffset(pos.X, pos.Y)
	end
	dragConnections:add_many({
		RunService.RenderStepped:Connect(function()
			local pos = state.Widget:GetRelativeMousePosition()
			dragFrame.Position = UDim2.fromOffset(pos.X, pos.Y)
			if not state.CurrentDrag then
				dragConnections:free()
			end
		end)
	})
	dragFrame.Parent = state.JExplorerUI

	local dragInstances = dragConnections:extend(cleanup.destroy, {
		dragFrame
	})
	state.CurrentDrag = {
		Frame = dragFrame,
		Connections = dragConnections,
		Entities = table.clone(state.CurrentSelection)
	}
	profileend()

end

local function trackScrolling()
	local jexplorerUi = Manager.WidgetState.JExplorerUI
	local lastPosition = jexplorerUi.InstanceTree.CanvasPosition

	local c = jexplorerUi.InstanceTree:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		local currentPosition = jexplorerUi.InstanceTree.CanvasPosition
		if (currentPosition - lastPosition).Magnitude > 1 then
			isScrolling = true
			lastScrollTime = os.clock()
			lastPosition = currentPosition
		end
	end)

	-- Check if scrolling has stopped
	local t = task.spawn(function()
		while true do
			task.wait(1/30)
			if isScrolling and os.clock() - lastScrollTime > Manager.getSetting("VirtualScrollSettleTime") then
				isScrolling = false
			end
		end
	end)
	return c, t
end

local function createExplorerFrame(frame: typeof(script.Parent.__legacy.UI.InstanceFrame))
	local state = Manager.WidgetState
	local components = Manager.Components

	local world = state.World
	local frameWorld = state.FrameWorld
	local jexplorerUi = state.JExplorerUI

	local main = frame.Main

	local iconImage = main.ClassIcon
	local instanceName = main.InstanceName
	local arrow = main.Arrow

	local overlayFrame = main.Overlay
	local selectInstanceButton = overlayFrame.Select
	local insertInstanceButton = main.Insert
	
	local connections = state.Connections:extend(cleanup.disconnect)
	local frameState: Types.FrameState = {
		isLMBActive = false,
		shouldDeselect = false,
		tagsToRemove = {},
		lastClickTime = 0,
		hasBeenSelected = false,
		isAssigning = false,
		lastPackageIconPos = 0,
	}
	
	local frameEntity = frameWorld:entity()
	Jecs.bulk_insert(frameWorld, frameEntity, {
		components.Instance,
		components.Connections,
		components.Entity,
		components.FrameState
	}, {
		frame,
		connections,
		nil,
		frameState
	})
	
	frameToInstanceFrame[frame] = frameEntity
	overlayFrame:AddTag("JEXP_Hover")
	
	connections:extend(cleanup.call, {
		function()
			if frameState.packageIconConn then frameState.packageIconConn:Disconnect() end
		end
	})
	
	connections:add_many({
		instanceName:GetPropertyChangedSignal("TextBounds"):Connect(function()
			if frameState.isAssigning then return end
			local bounds: Vector2 = rawindex(instanceName, "TextBounds")
			local x = instanceName:GetStyled("Position").X.Offset + bounds.X
			insertInstanceButton.Position = UDim2.new(0, x + 10, 0.5)
			frame.Main.PendingChanges.Position = UDim2.new(0, x + 26, 0.5)
		end),
		instanceName.Focused:Connect(function()
			local entity = frameWorld:get(frameEntity, components.Entity)
			if not entity then return end

			state.CurrentlyRenaming = entity
			instanceName.BackgroundTransparency = 0
		end),
		instanceName.FocusLost:Connect(function(enterPressed)
			local entity = frameWorld:get(frameEntity, components.Entity)
			if not entity then return end
			
			local instance = world:get(entity, components.Instance)
			if not instance then return end

			state.CurrentlyRenaming = nil
			instanceName.BackgroundTransparency = 1
			--if not enterPressed then return end
			instance.Name = instanceName.Text
		end),

		selectInstanceButton.InputBegan:Connect(function(input)
			local entity = frameWorld:get(frameEntity, components.Entity)
			if not entity then return end
			
			local instance = world:get(entity, components.Instance)
			if not instance then return end

			if input.UserInputState ~= Enum.UserInputState.Begin then return end
			if input.UserInputType ~= Enum.UserInputType.MouseMovement then
				Manager.ItemLists.InsertInstance:Hide()
			end
			if input.UserInputType == Enum.UserInputType.MouseMovement then
			elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
				state.ContextTarget = entity
				-- If this entity is already selected don't set selection so any other selected instances dont get deselected
				if not world:has(entity, components.Selected) then
					setSelection(world, {entity}, true)
				end
				
				local chosenMenus = {}
				for _, info in state.InstanceContextMenus do
					local pass = info.Condition(Manager, entity, instance)
					if pass then table.insert(chosenMenus, info) end
				end
				if #chosenMenus > 0 then
					table.sort(chosenMenus, function(a, b)
						return a.Priority > b.Priority
					end)
					chosenMenus[1].Menu.Menu:ShowAsync()
				end
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
				profilebegin("InstanceFrame::onInput::LMB (click)")
				frameState.isLMBActive = true
				frameState.hasBeenSelected = world:has(entity, components.Selected)
				frameState.shouldDeselect = false

				local currentTime = os.clock()
				local timeSinceLastClick = currentTime - frameState.lastClickTime
				frameState.lastClickTime = currentTime

				-- Check for double-click
				if timeSinceLastClick <= Manager.getSetting("DoubleClickToOpenScriptTime") and instance:IsA("LuaSourceContainer") then
					--plugin:OpenScript(instance)
					local success, err = ScriptEditorService:OpenScriptDocumentAsync(instance)
					if not success then warn(`Couldn't open LuaSourceContainer '{instance.Name}': '{err}'`) end
					return
				elseif timeSinceLastClick <= Manager.getSetting("DoubleClickToRenameTime") then
					instanceName.TextEditable = true
					instanceName.Interactable = true
					instanceName:CaptureFocus()
					return
				end

				local isCtrlHeld = Manager.isKeyDown(Enum.KeyCode.LeftControl)
				local isShiftHeld = Manager.isKeyDown(Enum.KeyCode.LeftShift)

				-- Handle selection logic immediately (don't wait for drag)
				if not frameState.hasBeenSelected then
					-- First click on unselected item - select it
					toggleSelection(world, entity, isCtrlHeld, isShiftHeld)
					return -- Don't proceed to drag logic
				elseif isCtrlHeld then
					-- Ctrl+click on selected item - mark for deselection on mouse up
					frameState.shouldDeselect = true
					return -- Don't start drag
				elseif isShiftHeld then
					-- Shift+click on selected item - handle shift selection
					toggleSelection(world, entity, isCtrlHeld, isShiftHeld)
					return -- Don't start drag
				elseif #state.CurrentSelection > 1 then
					-- Multiple items selected, clicking on one should deselect others
					-- But we need to wait to see if this is a drag or just a click
					-- Don't call toggleSelection here - handle it in InputEnded
				else
					-- Single item selected, clicking on it again - could be drag or deselect
					-- Wait to see if it's a drag
				end

				-- Wait to distinguish between click and drag
				task.wait(0.1)

				if not frameState.isLMBActive then return end -- User released mouse quickly
				startDraggingInstance(frameEntity)
			end
		end),
		
		selectInstanceButton.InputEnded:Connect(function(input)
			local entity = frameWorld:get(frameEntity, components.Entity)
			if not entity then return end

			local instance = world:get(entity, components.Instance)
			if not instance then return end

			if input.UserInputState ~= Enum.UserInputState.End then return end
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

			frameState.isLMBActive = false

			-- Handle deselection for ctrl+click
			if frameState.shouldDeselect then
				world:remove(entity, components.Selected)
				updateSelectionVisuals(world, true)
				frameState.shouldDeselect = false
				return
			end
			-- If we have multiple selections and this was just a click (not drag), 
			-- then deselect others and select only this one
			if not state.CurrentDrag and frameState.hasBeenSelected and #state.CurrentSelection > 1 then
				local isCtrlHeld = Manager.isKeyDown(Enum.KeyCode.LeftControl)
				local isShiftHeld = Manager.isKeyDown(Enum.KeyCode.LeftShift)

				if not isCtrlHeld and not isShiftHeld then
					-- Normal click on multi-selection - select only this one
					for entityId in selectedQuery:iter() do
						world:remove(entityId, components.Selected)
					end
					world:add(entity, components.Selected)
					state.LastSelectedEntity = entity
					updateSelectionVisuals(world, true)
				end
			end

			-- Handle drag drop
			if not state.CurrentDrag then return end

			profilebegin("InstanceFrame::dropCurrentlyDragged")

			-- Clean up drag state first
			state.CurrentDrag.Connections:free()
			local dragEntities = state.CurrentDrag.Entities

			local mousePos = state.Widget:GetRelativeMousePosition()
			local foundDropInst, newParentEntity, tab = Manager.getEntityAt(mousePos.X, mousePos.Y, state.CurrentDrag.Frame:FindFirstChild("Main"))

			if tab then
				for _, ent in dragEntities do
					state.CurrentDrag = nil
					local parentTabs = world:get(ent, components.ParentTabs)
					assert(parentTabs)

					local tabStorage = tab.Roots
					if table.find(tabStorage, ent) then return end
					table.insert(tabStorage, ent)
					parentTabs[tab] = true
				end

				return
			end

			if not newParentEntity then 
				state.CurrentDrag = nil
				return
			end

			local newParentInstance = world:get(newParentEntity, components.Instance)
			if not newParentInstance then 
				state.CurrentDrag = nil
				return 
			end
			for _, dragEntity in dragEntities do
				local child = world:get(dragEntity, components.Instance)
				if not child then continue end
				-- Attempting to reparent a selection into one of its members is illegal
				if newParentInstance == child or child:IsAncestorOf(newParentInstance) then 
					state.CurrentDrag = nil
					return 
				end
			end

			for _, e in dragEntities do
				world:add(e, components.AncestryLocked)
			end

			local id = ChangeHistoryService:TryBeginRecording("Drop", "Drop")
			local isExpanded = isEntityExpanded(world, newParentEntity)
			for _, dragEntity in dragEntities do
				local child = world:get(dragEntity, components.Instance)
				if not child then continue end
				
				local oldParentEntity = parent_of(dragEntity)
				update_parent(world, dragEntity, newParentEntity)
				
				if oldParentEntity then
					invalidateEntityHeightCache(world, oldParentEntity)
				end
				
				pcall(rawnewindex, child, "Parent", newParentInstance)
				updateEntityOrder(world, dragEntity, newParentEntity)
				
				local dragFrame = world:get(dragEntity, components.Frame)
				if dragFrame then
					reuseExplorerFrame(dragFrame)
				end
			end
			
			flushTagAssignQueue()
			
			if not isExpanded then
				--toggleExpand(world, newParentEntity, true, true)
				world:add(newParentEntity, components.Expanded)
				invalidateEntityStateCache(newParentEntity)
				
				updateExpandedVisuals(world, false)
			else
				invalidateEntityHeightCache(world, newParentEntity)
			end
			
			for _, e in dragEntities do
				world:remove(e, components.AncestryLocked)
			end
			
			state.CurrentDrag = nil
			state.HierarchyVersion += 1
			updateVirtualScroller()
			
			if id then
				ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
			end
			updateSelectionVisuals(world, false)
			profileend()
		end),
		selectInstanceButton.MouseEnter:Connect(function()
			local entity = frameWorld:get(frameEntity, components.Entity)
			if not entity then return end

			insertInstanceButton.Visible = true
			if state.CurrentDrag then
				--frame.SelectionTargetOutline.Enabled = true
				frame:AddTag("JEXP_DropTarget")
			end
		end),
		selectInstanceButton.MouseLeave:Connect(function()
			local entity = frameWorld:get(frameEntity, components.Entity)
			if not entity then return end

			insertInstanceButton.Visible = false
			--frame.SelectionTargetOutline.Enabled = false
			if frame:HasTag("JEXP_DropTarget") then
				frame:RemoveTag("JEXP_DropTarget")
			end
		end),
		insertInstanceButton.Activated:Connect(function()
			local entity = frameWorld:get(frameEntity, components.Entity)
			if not entity then return end

			state.ContextTarget = entity

			showInsertInstanceMenu(insertInstanceButton.AbsolutePosition, insertInstanceButton.AbsoluteSize)
		end),
		instanceName.FocusLost:Connect(function()
			instanceName.TextEditable = false
			instanceName.Interactable = false
		end),
		arrow.Activated:Connect(function()
			local entity = frameWorld:get(frameEntity, components.Entity)
			if not entity then return end

			--toggleExpand(world, entity, not isEntityExpanded(world, entity), true)
			local expanded = isEntityExpanded(world, entity)
			if expanded then
				world:remove(entity, components.QueryExpanded)
				world:remove(entity, components.Expanded)
				invalidateEntityStateCache(entity)
				updateCollapsedVisuals(world, true)
			else
				world:add(entity, components.QueryExpanded)
				world:add(entity, components.Expanded)
				invalidateEntityStateCache(entity)
				updateExpandedVisuals(world, true)
			end
		end)
	})

	return frameEntity
end

local function fillInstanceFramePoolToLimit()
	profilebegin("Manager::fillInstanceFramePoolToLimit")
	if #pooledInstanceFrames >= instanceFramePoolTarget then return end

	local framesToCreate = instanceFramePoolTarget - #pooledInstanceFrames
	for _ = 1, framesToCreate do
		local clone = UITemplates.InstanceFrame()
		
		local frame = createExplorerFrame(clone)
		clone.Visible = false
		clone.Parent = Manager.WidgetState.JExplorerUI.InstanceTree

		table.insert(pooledInstanceFrames, frame)
	end
	profileend()
end

function getExplorerFrame(): ExplorerFrame
	if #pooledInstanceFrames == 0 then
		-- Attempt to reuse any pending frames before creating new ones
		local success = flushFrameReuseQueue()
		if not success or #pooledInstanceFrames == 0 then
			fillInstanceFramePoolToLimit()
		end
	end
	return table.remove(pooledInstanceFrames)::any
end

local function onInstChildRemoved(world: World, entity: ExplorerEntity, child: ExplorerEntity, isAncestryChanged: boolean)
	local components = Manager.Components
	local state = Manager.WidgetState

	if isAncestryChanged and world:has(entity, components.AncestryLocked) then return false end
	local frame = world:get(entity, components.Frame)
	if not frame then return false end
	
	local frameInst = frame_of(frame)

	profilebegin("Manager::onInstChildRemoved")
	if frameInst then
		local main = frameInst:FindFirstChild("Main")
		if main and not world:has(entity, components.ArrowInvisible) then
			main.Arrow.Visible = getChildAmount(entity) > 0
		end
	end
	
	--cascadeUpdateExpandedHeights(world, childEntity)
	local parent = parent_of(child)
	if not parent then
		table.insert(entityCleanupQueue, child)
		return false
	end
	
	if isEntityExpanded(world, parent) then
		invalidateEntityHeightCache(world, parent)
	end
	local frame = world:get(child, components.Frame)
	if frame then
		assignExplorerFrame(frame, child, parent)
	end
	updateEntityOrder(world, child, parent)
	--cascadeUpdateExpandedHeights(world, childEntity)

	profileend()
	return true
end

local function onInstChildAdded(world: World, entity: ExplorerEntity, child_entity: ExplorerEntity, isAncestryChanged: boolean)
	local components = Manager.Components
	local state = Manager.WidgetState

	if isAncestryChanged and world:has(entity, components.AncestryLocked) then
		return false
	end
	if not parent_of(child_entity) then return false end

	profilebegin("Manager::onInstChildAdded")

	local frame = world:get(entity, components.Frame)
	if not frame then return false end
	
	local frameInst = frame_of(frame)
	
	if frameInst then 
		local main = frameInst:FindFirstChild("Main")
		if main then
			-- If a child is added, the entity always has atleast 1 child so just set to true always
			--main.Arrow.Visible = #instance:GetChildren() > 0
			main.Arrow.Visible = true
		end
	end

	local ancestryChanged = false
	
	local parent = parent_of(child_entity)
	if parent and isEntityExpanded(world, parent) then
		invalidateEntityHeightCache(world, parent)
	end
	if parent::any ~= entity then
		--cascadeUpdateExpandedHeights(world, existingChildEntity)
		if parent then
			world:remove(child_entity, ChildOf(parent))
		end
		world:add(child_entity, ChildOf(entity))
		ancestryChanged = true
	end
	
	updateEntityOrder(world, child_entity, entity)
	return ancestryChanged
end

local function flushOnChildAddedQueue()
	if #onChildAddedQueue == 0 then return false end
	profilebegin("Manager::flushOnChildAddedQueue")

	local state = Manager.WidgetState
	local world = state.World

	local anyChanged = false
	local seen = {}
	for _, info in onChildAddedQueue do
		if seen[info.child] then continue end
		local changed = onInstChildAdded(world, info.parent, info.child, false)
		if changed then
			anyChanged = true
		end
	end
	table.clear(onChildAddedQueue)
	flushEntityPropAssignQueue()

	if anyChanged then
		childMapNeedsUpdate = true
	end

	profileend()
	return anyChanged
end

local function flushOnChildRemovedQueue()
	if #onChildRemovedQueue == 0 then return false end
	profilebegin("Manager::flushOnChildRemovedQueue")

	local state = Manager.WidgetState
	local world = state.World

	local anyChanged = false
	local seen = {}
	for _, info in onChildRemovedQueue do
		if seen[info.child] then continue end
		local changed = onInstChildRemoved(world, info.parent, info.child, false)
		if changed then
			anyChanged = true
		end
	end
	table.clear(onChildRemovedQueue)

	if anyChanged then
		childMapNeedsUpdate = true
	end

	profileend()
	return anyChanged
end

local function triggerEscapeTarget()
	local state = Manager.WidgetState
	local world = state.World
	local components = Manager.Components

	profilebegin("Manager::ESCAPE (unselect all)")
	if state.CurrentlyRenaming then
		local frame = world:get(state.CurrentlyRenaming, components.Frame)
		if not frame then return end

		local inst = frame_of(frame)
		if inst then
			inst.Main.InstanceName:ReleaseFocus(false)
		end
		state.CurrentlyRenaming = nil
		return
	end

	for entityId in selectedQuery:iter() do
		world:remove(entityId, components.Selected)
	end

	updateSelectionVisuals(world, true)
	state.LastSelectedEntity = nil
	profileend()
end

local function triggerDeleteTarget()
	local state = Manager.WidgetState
	local world = state.World
	local components = Manager.Components
	
	local id = ChangeHistoryService:TryBeginRecording("Destroy", "Destroy")
	profilebegin("Manager::BACKSPACE/DELETE (remove)")

	local selection = state.CurrentSelection
	for _, entity in selection do
		world:add(entity, components.AncestryLocked)
	end
	for _, entity in selection do
		world:add(entity, components.Deleted)
		local instance = world:get(entity, components.Instance)
		assert(instance)

		instance.Parent = nil
		invalidateEntityHeightCache(world, entity)
		update_parent(world, entity, nil)
		table.insert(entityCleanupQueue, entity)
	end
	for _, entity in selection do
		world:remove(entity, components.AncestryLocked)
	end

	if id then
		ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
	end

	profileend()
end

local function triggerDuplicateTarget()
	local state = Manager.WidgetState
	local world = state.World
	local components = Manager.Components
	
	local id = ChangeHistoryService:TryBeginRecording("Clone", "Clone")
	profilebegin("Manager::D (duplicate)")
	
	local cloned = {}
	for _, entity in state.CurrentSelection do
		local parent = parent_of(entity)
		if parent == nil then continue end

		local instance = world:get(entity, components.Instance)
		if not instance then continue end
		
		world:add(parent, components.AncestryLocked)

		local clone = instance:Clone()
		--clone.Parent = instance.Parent
		clone.Parent = instance.Parent
		local cloneEntity = Manager.createInstanceEntity(clone, entity)
		invalidateEntityHeightCache(world, cloneEntity)
		
		world:remove(parent, components.AncestryLocked)
	end
	
	if id then
		ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
	end

	profileend()
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
	return debugIdToInstance[id]
end

function Manager.updateSelectionVisuals(updateSelection)
	updateSelectionVisuals(Manager.WidgetState.World, updateSelection)
end

function Manager.updateExpandedVisuals(update, expandedCt)
	updateExpandedVisuals(Manager.WidgetState.World, update, expandedCt)
end

function Manager.updateCollapsedVisuals(update)
	updateCollapsedVisuals(Manager.WidgetState.World, update)
end

function Manager.getDragInfo(inst, propName)
	return {
		Sender = `jprops:{propName}`,
		MimeType = "text/plain",
		Data = Manager.getInstId(inst),
		MouseIcon = "",
		DragIcon = "",
		HotSpot = Vector2.new(0, 0)
	}
end

function Manager.unpackDragInfo(info)
	local propName = string.match(info.Sender, "jprops:(%w*)")
	assert(propName)

	local id = info.Data
	local targetInst = Manager.getInstFromId(id)
	assert(targetInst)

	return targetInst, propName
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

function Manager.getOrCreateInstanceEntity(instance, ...)
	if instanceToEntity[instance] then
		return instanceToEntity[instance]
	end
	return Manager.createInstanceEntity(instance, ...)
end

function Manager.registerRightClickContextMenu(menu, condition, priority)
	Manager.WidgetState.InstanceContextMenus[menu.Id] = {
		Menu = menu,
		Condition = condition,
		Priority = priority
	}
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
			return v, nil, tabFrameToTab[v]
		end
	end
	if not newParentFrame then return end

	local instFrame = frameToInstanceFrame[newParentFrame]
	if not instFrame then return end
	
	local entity = Manager.WidgetState.FrameWorld:get(instFrame, Manager.Components.Entity)
	if not entity then 
		return
	end

	return newParentFrame, entity
end

function Manager.createVirtualEntity(options, extra)
	assert(options.ClassName, "ClassName required")
	assert(options.Name, 'Name required')
	assert(options.ChildAmount, "ChildAmount required")

	local state = Manager.WidgetState
	local components = Manager.Components
	local queryWorld = state.QueryWorld
	local world = state.World

	local connections: ItemGroup<RBXScriptConnection> = options.Parent and world:get(options.Parent, components.Connections)::any or state.Connections

	local tbl = {
		ClassName = options.ClassName,
		Name = options.Name,
	}

	for k, v in extra do
		tbl[k] = v
	end
	local ent = world:entity()
	
	table.insert(entityPropAssignQueue, {ty = "virtual", ent = ent})
	table.insert(state.Entities, ent)
	
	local instConnections = connections:extend(cleanup.call)
	Jecs.bulk_insert(world, ent, {
		components.Instance,
		components.Connections
	}, {
		tbl,
		instConnections
	})
	
	return ent
end

function Manager.createInstanceEntity(instance, parent, dontSetInInstanceToEntity)
	profilebegin("Manager::createInstanceEntity")
	local state = Manager.WidgetState
	local components = Manager.Components

	local world = state.World
	local queryWorld = state.QueryWorld
	local jexplorerUi = state.JExplorerUI

	local components = Manager.Components
	local state = Manager.WidgetState

	local parentConnections = state.Connections
	if parent then
		local connections = world:get(parent, components.Connections)
		if not connections then
			connections = ItemGroup.create(cleanup.disconnect)
			world:set(parent, components.Connections, connections::any)
		end
		parentConnections = connections::any
	end

	local connections = parentConnections:extend(cleanup.disconnect)
	local className = instance.ClassName
	
	local entity = world:entity()
	Jecs.bulk_insert(world, entity, {
		components.Instance,
		components.Connections,
		components.ParentTabs,
		if parent then ChildOf(parent) else nil
	},
	{
		instance,
		connections,
		{}
	})
	
	table.insert(entityPropAssignQueue, {ty = "instance", ent = entity})
	local children = instance:GetChildren()
	if #children > 0 then
		table.insert(entityCreationQueue, {parent = entity, children = children})
	end
	
	table.insert(state.Entities, entity)
	if not dontSetInInstanceToEntity then
		instanceToEntity[instance] = entity
	end
	profileend()
	
	return entity
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
	local tabFrame = Instance.new("Frame")
	tabFrame.Name = "InstanceTab"
	tabFrame.Size = UDim2.new(0, 70, 1, 0)
	tabFrame:AddTag("JEXP_LightBackground")
	tabFrame:AddTag("JEXP_Border")

	local nameBox = Instance.new("TextBox")
	nameBox.Name = "NameBox"
	nameBox.Text = name
	nameBox.Position = UDim2.new(0, 2, 0.5, 0)
	nameBox.Size = UDim2.new(0, 0, 1, 0)
	nameBox.AnchorPoint = Vector2.new(0, 0.5)
	nameBox.TextXAlignment = Enum.TextXAlignment.Left
	nameBox.TextYAlignment = Enum.TextYAlignment.Center
	nameBox.ClearTextOnFocus = false
	nameBox.Interactable = true
	nameBox.TextSize = 6
	nameBox.Active = false
	nameBox.BackgroundTransparency = 1
	nameBox:AddTag("JEXP_Text")
	nameBox.Parent = tabFrame

	local bounds = nameBox.TextBounds
	nameBox.Size = UDim2.new(0, bounds.X, 1, 0)

	local button = Instance.new("TextButton")
	button.Name = "Button"
	button.Transparency = 1
	button.Size = UDim2.new(1, 0, 1, 0)
	button.Parent = tabFrame

	tabFrame.Parent = tabBar.Tabs

	local tab = {
		Roots = stored,
		Name = name,

		TabFrame = tabFrame,
		Button = button,
		NameBox = nameBox,
	} :: Tab
	tabFrameToTab[tabFrame] = tab
	if registerIntoTabs then
		table.insert(currentTabs, tab)
	end

	function tab.Toggle()
		-- Already selected
		if currentlyOpenTab == tab then
			return
		end

		jexplorerUi.InstanceTree.CanvasPosition = Vector2.zero

		if tabInsertListener then
			tabInsertListener:Disconnect()
			tabInsertListener = nil
			isCurrentlyPickingTabRoots = false
		end

		for entity in world:query(components.Instance):without(ChildOf(Jecs.Wildcard)):iter() do
			world:add(entity, components.Invisible)
			invalidateEntityStateCache(entity)
			
			world:remove(entity, components.DisplayTopLevel)
		end
		for entity in world:query(components.DisplayTopLevel):iter() do
			world:remove(entity, components.DisplayTopLevel)
		end
		if currentlyOpenTab then
			local background = currentlyOpenTab.TabFrame
			background:RemoveTag("JEXP_DarkerBackground")
			background:AddTag("JEXP_LightBackground")
			currentlyOpenTab.InsertButton.BackgroundTransparency = 1
			for _,v in currentlyOpenTab.Roots do
				local frame = world:get(v, components.Frame)
				if not frame then continue end
				
				reuseExplorerFrame(frame)
			end
		end
		tabFrame:RemoveTag("JEXP_LightBackground")
		tabFrame:AddTag("JEXP_DarkerBackground")
		currentlyOpenTab = tab

		for _, entity in stored do
			world:remove(entity, components.Invisible)
			invalidateEntityStateCache(entity)
			
			world:add(entity, components.DisplayTopLevel)
			--updateEntityOrder(world, entity, nil)
		end

		task.wait(0.1)
		state.HierarchyVersion += 1
		updateVirtualScroller()
	end

	function tab.Remove()
		tabConnections:free()
		for _, v in stored do
			local parentTabs = world:get(v, components.ParentTabs)
			assert(parentTabs)
			parentTabs[tab] = nil
		end
		table.clear(stored)
		tabFrameToTab[tabFrame] = nil
		tabFrame:Destroy()
		
		local idx = table.find(currentTabs, tab)
		if idx then table.remove(currentTabs, idx) end

		if currentlyOpenTab == tab then
			if tabInsertListener then
				tabInsertListener:Disconnect()
				tabInsertListener = nil
				isCurrentlyPickingTabRoots = false
			end
			for entity in world:query(components.Instance):without(ChildOf(Jecs.Wildcard)):iter() do
				world:add(entity, components.Invisible)
				invalidateEntityStateCache(entity)
				
				world:remove(entity, components.DisplayTopLevel)
			end
			for entity in world:query(components.DisplayTopLevel):iter() do
				world:remove(entity, components.DisplayTopLevel)
			end

			currentlyOpenTab = nil
			allTab.Toggle()
		end
	end

	if createInsertButton then
		local insertButton
		insertButton = PluginUI.createInsertButton(button, function()
			if isCurrentlyPickingTabRoots then return end
			if currentlyOpenTab ~= allTab then
				allTab.Toggle()
			end
			insertButton.BackgroundTransparency = 0

			isCurrentlyPickingTabRoots = true

			tabInsertListener = Manager.connectInputBegan(function(input)
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
					setSelection(world, {}, true)
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
			
			targetTab = tab
			state.MiscContextMenus.Tab.Menu:ShowAsync()
		end),
		button.MouseEnter:Connect(function()
			if not state.CurrentDrag then return end
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
		Id = id
	}
end

local function init_register_item_lists(
	state: Types.WidgetState,
	components: typeof(Manager.Components)
)
	local world = state.World
	local connections = state.Connections
	local jexplorerUi = state.JExplorerUI
	local topbar = jexplorerUi.Topbar

	local insertInstanceList do
		insertInstanceList = PluginUI.createItemList {
			Name = "InsertInstanceList"
		}
		local allButtons: {
			{
				button: Frame,
				className: string,
				category: string
			}
		} = {}
		local categories: {[string]: Frame} = {}
		local originalOrders: {
			buttons: {[string]: number},
			headers: {[string]: number}
		} = {
			buttons = {},
			headers = {}
		}
		local currentVisibleButtons: {
			{
				button: Frame,
				className: string,
				category: string
			}
		} = {}

		local topFrame = Instance.new("Frame")
		topFrame:AddTag("JEXP_Border")
		topFrame:AddTag("JEXP_Background")

		topFrame.Name = "TopFrame"
		topFrame.AnchorPoint = Vector2.new(0, 1)
		topFrame.BorderSizePixel = 0
		topFrame.Size = UDim2.new(1, 0, 0, 28)
		topFrame.Parent = insertInstanceList.Backdrop

		local searchbar = Instance.new("TextBox")
		searchbar:AddTag("JEXP_Border")
		searchbar:AddTag("JEXP_DarkBackground")
		searchbar:AddTag("JEXP_Text")

		searchbar.Name = "SearchBar"
		searchbar.AnchorPoint = Vector2.new(0, 0.5)
		searchbar.BorderSizePixel = 0
		searchbar.Position = UDim2.new(0.025, 0, 0.5, 0)
		searchbar.Size = UDim2.fromScale(0.8, 0.6)
		searchbar.Text = ""
		searchbar.TextSize = 8
		searchbar.PlaceholderText = "Search object..."
		searchbar.TextXAlignment = Enum.TextXAlignment.Left
		searchbar.TextYAlignment = Enum.TextYAlignment.Center
		searchbar.Parent = topFrame

		local highlightFrame = Instance.new("Frame")
		highlightFrame.Size = UDim2.fromScale(1, 1)
		highlightFrame.BackgroundColor3 = Color3.new(100, 100, 100)
		highlightFrame.BackgroundTransparency = 0.8

		searchbar:GetPropertyChangedSignal("Text"):Connect(function()
			local searchText = searchbar.Text
			local matches = {}
			for _, buttonData in allButtons do
				local score = calculateMatchScore(buttonData.className, searchText)
				if score > 0 then
					table.insert(matches, {
						button = buttonData.button,
						score = score,
						className = buttonData.className,
						category = buttonData.category
					})
				end
			end

			table.sort(matches, function(a, b)
				return a.score > b.score
			end)
			for _, buttonData in allButtons do
				buttonData.button.Visible = false
			end
			for _, header in categories do
				header.Visible = false
			end
			if searchText == "" then
				-- Reset to show all buttons
				currentVisibleButtons = {}
				for _, buttonData in allButtons do
					buttonData.button.Visible = true
					buttonData.button.LayoutOrder = originalOrders.buttons[buttonData.className]
					table.insert(currentVisibleButtons, buttonData)
				end
				for category, header in categories do
					header.Visible = true
					header.LayoutOrder = originalOrders.headers[category]
				end
				return
			end

			-- Clear and rebuild visible buttons list
			currentVisibleButtons = {}
			local layoutOrder = 1
			local visibleCategories = {}
			local categoryOrder = {}
			for _, match in matches do
				if not visibleCategories[match.category] then
					visibleCategories[match.category] = true
					table.insert(categoryOrder, match.category)
				end
			end
			for _, category in categoryOrder do
				if categories[category] then
					categories[category].Visible = true
					categories[category].LayoutOrder = layoutOrder
					layoutOrder = layoutOrder + 1
				end
				for _, match in matches do
					if match.category == category then
						match.button.Visible = true
						match.button.LayoutOrder = layoutOrder
						layoutOrder = layoutOrder + 1
						-- Add to visible buttons in display order
						table.insert(currentVisibleButtons, match)
					end
				end
			end
		end)

		local function insert(class: string)
			insertInstanceList:Hide()

			local entity = state.ContextTarget
			if not entity then return end

			local id = ChangeHistoryService:TryBeginRecording("CreateInstance", "Create Instance")

			local entityInst = world:get(entity, components.Instance)
			if not entityInst then
				if id then
					ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Cancel)
				end
				return 
			end

			local success, inst = pcall(Instance.new, class)
			if not success then warn(inst) return end

			local infos = {}
			for k, v in INSTANCE_INSERT_INFO do
				if inst:IsA(k) then table.insert(infos, v) end
			end
			for _, info in infos do
				for k, v in info.Props do
					pcall(rawnewindex, inst, k, v)
				end
				if info.SideEffect then
					info.SideEffect(inst)
				end
			end

			inst.Parent = entityInst
			if not isEntityExpanded(world, entity) then
				--toggleExpand(world, entity, true, true)
				world:add(entity, components.Expanded)
				invalidateEntityStateCache(entity)
				state.HierarchyVersion += 1
				
				--updateExpandedVisuals(world, false)
				updateVirtualScroller()
			end
			
			local childEntity = assert(Manager.createInstanceEntity(inst, entity))
			
			table.insert(onChildAddedQueue, {parent = entity, child = childEntity})
			Selection:Set({inst})

			if id then
				ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
			end
		end

		local layoutOrder = 0
		for category, tbl in require(utilities.Info.InstanceCategories) do
			local header = PluginUI.createHeader(insertInstanceList, category)
			layoutOrder += 1
			header.LayoutOrder = layoutOrder

			categories[category] = header
			originalOrders.headers[category] = layoutOrder

			for _, class in tbl do
				local success, icon: StudioIconResult = xpcall(
					StudioService.GetClassIcon, function()end, StudioService, class
				)
				if not success then return end

				local buttonItem = PluginUI.createButtonWithIcon(
					insertInstanceList, class, icon.Image, icon.ImageRectOffset, icon.ImageRectSize, 
					function()
						insert(class)
					end
				)

				layoutOrder += 1

				local button = buttonItem.Instance
				button.LayoutOrder = layoutOrder

				button:RemoveTag("JEXP_DarkBackground")
				button:AddTag("JEXP_Background")
				originalOrders.buttons[class] = layoutOrder
				table.insert(allButtons, {
					button = button,
					className = class,
					category = category
				})
			end
		end
		currentVisibleButtons = {}
		for _, buttonData in allButtons do
			table.insert(currentVisibleButtons, buttonData)
		end

		local currentInsertTarget: number
		showInsertInstanceMenu = function(pos: Vector2, size: Vector2)
			local frameSize = insertInstanceList.Backdrop.AbsoluteSize

			insertInstanceList:SetAnchor(
				Vector2.new(0, 0), 
				UDim2.fromOffset(
					getClampedXY(
						frameSize,
						pos, 
						size,
						jexplorerUi.AbsolutePosition,
						jexplorerUi.AbsoluteSize
					)
				)
			)

			insertInstanceList:Show()
			searchbar:CaptureFocus()
			searchbar.Text = ""
			currentInsertTarget = 1
			-- Set initial highlight
			if #currentVisibleButtons > 0 then
				highlightFrame.Parent = currentVisibleButtons[1].button
			end
		end

		local function onInputBegan(input)
			if not insertInstanceList.Backdrop.Visible then return end
			if input.UserInputState ~= Enum.UserInputState.Begin then return end
			if input.KeyCode == Enum.KeyCode.Return then
				insertInstanceList:Hide()
				if currentInsertTarget > 0 and currentInsertTarget <= #currentVisibleButtons then
					insert(currentVisibleButtons[currentInsertTarget].className)
				end
			elseif input.KeyCode == Enum.KeyCode.Up then
				if #currentVisibleButtons > 0 then
					currentInsertTarget = math.max(1, currentInsertTarget - 1)
					highlightFrame.Parent = currentVisibleButtons[currentInsertTarget].button
				end
			elseif input.KeyCode == Enum.KeyCode.Down then
				if #currentVisibleButtons > 0 then
					currentInsertTarget = math.min(#currentVisibleButtons, currentInsertTarget + 1)
					highlightFrame.Parent = currentVisibleButtons[currentInsertTarget].button
				end
			end
		end

		connections:add_many({
			Manager.connectInputBegan(onInputBegan),
			searchbar.FocusLost:Connect(function(_, input)
				onInputBegan(input)
			end),
			searchbar.InputBegan:Connect(onInputBegan)
		})
		insertInstanceList.Backdrop.Parent = jexplorerUi
	end
	
	Manager.ItemLists = {
		InsertInstance = insertInstanceList
	}
end

local function init_register_context_menus_and_actions(
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
			if not targetTab then return end

			local box: TextBox = targetTab.NameBox
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
				
				local frameInst = frame_of(frame)
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
				local childEntity = assert(Manager.createInstanceEntity(v, entity))

				table.insert(onChildAddedQueue, {parent = entity, child = childEntity})
			end

			state.HierarchyVersion += 1
			updateVirtualScroller()

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
			showInsertInstanceMenu(mousePos, Vector2.zero)
		end)
	end

	local selectChildrenAction do
		selectChildrenAction = createPluginAction(
			getId("Jexplorer_ContextMenu_SelectChildren", true), "Select Children", "Selects all children of an Instance."
		)
		selectChildrenAction.Triggered:Connect(function()
			for _, target in state.CurrentSelection do
				local children = {}
				for child in childrenOf(world, target):iter() do
					table.insert(children, child)
				end

				if not world:has(target, components.Expanded) then
					--toggleExpand(world, target, true, true)
					world:add(target, components.Expanded)
					invalidateEntityStateCache(target)
					updateExpandedVisuals(world, true)
				end
				addEntitiesToSelection(world, children, true)
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
			if target then name = nameCache[target] end

			setSelection(world, state.CurrentSelection, true)
			plugin:PromptSaveSelection(name)
		end)
	end

	local saveToRobloxAction do
		saveToRobloxAction = createPluginAction(
			getId("Jexplorer_ContextMenu_SaveToRoblox", true), "Save to Roblox...", "Saves an Instance to Roblox."
		)
		saveToRobloxAction.Triggered:Connect(function()
			setSelection(world, state.CurrentSelection, true)
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
					local child = instanceToEntity[v]
					if not child then continue end
					if not world:has(child, components.Expanded) then continue end
					
					world:remove(child, components.Expanded)
					invalidateEntityStateCache(child)
					updateCollapsedVisuals(world, false)
				end
				--toggleExpand(world, entity, false, false)
				world:remove(entity, components.Expanded)
				invalidateEntityStateCache(entity)
				updateCollapsedVisuals(world, false)
			end
			updateVirtualScroller()
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

					cleanupEntity(entity)
					continue
				end
				local instance = world:get(entity, components.Instance)
				if not instance then return end
				if Manager.AbstractEntClasses[instance.ClassName] then continue end
				if existingProxy == nil then
					-- Add proxy
					local proxy = Manager.createInstanceEntity(instance, favoritedInstancesEntity, true)
					if not proxy then continue end
					world:add(proxy, components.ArrowInvisible)

					if not proxy then
						warn(`could not create favorite proxy for '{instance}'`)
						return
					end

					world:set(entity, components.FavoriteProxy, proxy)
					world:set(proxy, components.FavoriteProxySource, entity)

					if world:has(favoritedInstancesEntity, components.Expanded) then
						local frame = getExplorerFrame()
						assignExplorerFrame(frame, proxy, favoritedInstancesEntity)
						flushTagAssignQueue()
					end
					updateEntityOrder(world, proxy, favoritedInstancesEntity)

					table.insert(state.Favorited, proxy)
				else
					-- Remove proxy
					local idx = table.find(state.Favorited, existingProxy)
					if idx then
						table.remove(state.Favorited, idx)
					end
					world:remove(entity, components.FavoriteProxy)

					cleanupEntity(entity)
				end
			end

			flushEntityPropAssignQueue()
			state.HierarchyVersion += 1
			updateVirtualScroller()
		end)
	end

	local hideClassAction do
		hideClassAction = createPluginAction(
			getId("Jexplorer_ContextMenu_HideClass", true), "Hide Class", "Hides all Instances with the ClassName of the selected Instance."
		)
		hideClassAction.Triggered:Connect(function()
			for _, v in state.CurrentSelection do
				local className = classNameCache[v]
				if not className then continue end

				InstanceVisibilityEditor.setInvisible(className, true)
				updateVirtualScroller()
			end
		end)
	end

	local deleteAction do
		deleteAction = createPluginAction(
			getId("Jexplorer_ContextMenu_Delete", true), "Delete", "Deletes this Instance."
		)
		deleteAction.Triggered:Connect(triggerDeleteTarget)
	end
	
	local escapeAction do
		escapeAction = createPluginAction(
			getId("Jexplorer_ContextMenu_Escape", true), "Escape", "Escapes this Instance."
		)
		escapeAction.Triggered:Connect(triggerEscapeTarget)
	end
	
	local duplicateAction do
		duplicateAction = createPluginAction(
			getId("Jexplorer_ContextMenu_Duplicate", true), "Duplicate", "Duplicates this Instance."
		)
		duplicateAction.Triggered:Connect(triggerDuplicateTarget)
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
			if not currentlyOpenTab then return end
			if currentlyOpenTab == allTab then return end
			local stored = currentlyOpenTab.Roots

			local selection = state.CurrentSelection
			for _, ent in selection do
				local parentTabs = world:get(ent, components.ParentTabs)
				assert(parentTabs)

				parentTabs[currentlyOpenTab] = nil
				world:remove(ent, components.DisplayTopLevel)

				local frame = world:get(ent, components.Frame)
				if frame then reuseExplorerFrame(frame) end
				local idx = table.find(stored, ent)
				if idx then
					table.remove(stored, idx)
				end

				--updateEntityOrder(world, ent, world:parent(ent))
			end

			state.HierarchyVersion += 1
			updateVirtualScroller()
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

			local containerEntity = Manager.getOrCreateInstanceEntity(container, targetParentEnt)

			assert(containerEntity)
			world:add(containerEntity, components.AncestryLocked)

			for _, ent in entities do
				world:add(ent, components.AncestryLocked)
			end

			for _, ent in entities do
				local inst = world:get(ent, components.Instance)
				if not inst then continue end
				
				update_parent(world, ent, containerEntity)
				pcall(rawnewindex, inst, "Parent", container)

				local frame = world:get(ent, components.Frame)
				if frame then
					reuseExplorerFrame(frame)
				end
			end

			for _, ent in entities do
				world:remove(ent, components.AncestryLocked)
			end

			world:remove(containerEntity, components.AncestryLocked)

			state.HierarchyVersion += 1
			updateVirtualScroller()

			if id then
				ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
			end
			task.delay(0.1, function()
				Selection:Set({container})
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
			
			local parent = parent_of(target)
			local targetInst = instance_of(target)
			if not parent then return end
			if not targetInst then return end
			
			local children = hierarchyCache.childrenMap[target]
			if not children then return end
			
			local id = ChangeHistoryService:TryBeginRecording("Ungroup", "Ungroup")
			
			for _, child in children do
				local inst = instance_of(child)
				if not inst then continue end
				
				update_parent(world, child, parent)
				inst.Parent = instance_of(parent)
				table.insert(entities, child)
			end
			
			targetInst.Parent = nil
			update_parent(world, target, nil)
			
			updateVirtualScroller()
			setSelection(world, entities, true)
			
			if id then
				ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
			end
		end)
	end
	
	local toFolderAction, toModelAction do
		local function convertInstTo(className: string)
			local id = ChangeHistoryService:TryBeginRecording("ConvertInstTo", `Convert Instance To {className}`)
			
			local childrens: {{name: string, parent: Instance?, parentEntity: ExplorerEntity?, inst: Instance, entity: any, children: {ExplorerEntity}}} = {}
			for _, entity in state.CurrentSelection do
				local inst = world:get(entity, components.Instance)
				if not inst then continue end
				
				local childInstances = {}
				local tbl: {ExplorerEntity} = {}
				local children = hierarchyCache.childrenMap[entity]
				if children then
					for _, v in children do
						table.insert(tbl, v)
					end
				end
				
				world:add(entity, components.AncestryLocked)
				table.insert(childrens, {
					name = inst.Name,
					parent = inst.Parent,
					parentEntity = world:parent(entity),
					entity = entity,
					children = tbl,
					inst = inst,
				})
			end
			
			local modelEntities = {}
			for _, info in childrens do
				if not info.parent then continue end
				local model = Instance.new(className)
				model.Name = info.name
				
				local modelEnt = Manager.createInstanceEntity(model, info.parentEntity)
				assert(modelEnt)
				
				local frame = world:get(info.entity, components.Frame)
				if frame then
					reuseExplorerFrame(frame)
				end
				
				world:add(modelEnt, components.AncestryLocked)
				table.insert(modelEntities, modelEnt)
				
				for _, childEntity in info.children do
					world:add(childEntity, components.AncestryLocked)
				end
				for _, childEntity in info.children do
					local childInst = instance_of(childEntity)
					if not childInst then continue end
					
					update_parent(world, childEntity, modelEnt)
					pcall(rawnewindex, childInst, "Parent", model)
					
					local frame = world:get(childEntity, components.Frame)
					if frame then
						reuseExplorerFrame(frame)
					end
				end
				for _, childEntity in info.children do
					world:remove(childEntity, components.AncestryLocked)
				end
				
				if world:has(info.entity, components.Expanded) then
					world:add(modelEnt, components.Expanded)
					invalidateEntityStateCache(modelEnt)
				end
				
				update_parent(world, info.entity, nil)
				model.Parent = info.parent
				
				info.inst.Parent = nil
				table.insert(entityCleanupQueue, info.entity)
			end
			
			updateExpandedVisuals(world, false)

			state.HierarchyVersion += 1
			updateVirtualScroller()
			
			for _, v in modelEntities do
				world:remove(v, components.AncestryLocked)
			end

			if id then
				ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
			end

			task.delay(0.1, function()
				setSelection(world, modelEntities, true)
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
			
			local inst = instance_of(target)
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
			
			startDraggingInstance(frame)
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

local function init_create_topbar_dropdown_menu(state: Types.WidgetState, components: typeof(Manager.Components), topbar: Instance, onClose: any)
	local topbarMenuDropdown do
		topbarMenuDropdown = PluginUI.createItemList {
			Name = "TopbarMenuDropdown"
		}

		local WIP_COLOR = Color3.fromRGB(79, 79, 79)
		if IS_EDIT then
			PluginUI.createButtonWithIcon(
				topbarMenuDropdown,
				"Open Version Control",
				"rbxasset://studio_svg_textures/Shared/InsertableObjects/Dark/Standard/PackageLink.png",
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
				"rbxasset://studio_svg_textures/Shared/InsertableObjects/Dark/Standard/StyleSheet.png", 
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
			"rbxasset://studio_svg_textures/Shared/InsertableObjects/Dark/Standard/Configuration.png",
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
				"rbxasset://studio_svg_textures/Shared/InsertableObjects/Dark/Standard/SelectionBox.png",
				Vector2.zero, Vector2.new(16, 16),
				function()
					InstanceVisibilityEditor.Widget.Enabled = true
					topbarMenuDropdown:Hide()
				end
			)
			PluginUI.createButtonWithIcon(
				topbarMenuDropdown,
				"Open Order Editor",
				"rbxasset://studio_svg_textures/Shared/InsertableObjects/Dark/Standard/UIListLayout.png",
				Vector2.zero, Vector2.new(16, 16),
				function()
					OrderEditor.Widget.Enabled = true
					topbarMenuDropdown:Hide()
				end
			)
			PluginUI.createButtonWithIcon(
				topbarMenuDropdown, 
				"Open Context Menu Editor",
				"rbxasset://studio_svg_textures/Shared/InsertableObjects/Dark/Standard/UITableLayout.png",
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
					state.HierarchyVersion += 1
					updateVirtualScroller()
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

				oldStyle:Replace(Manager.Style)

				state.HierarchyVersion += 1
				updateVirtualScroller()
			end)
			PluginUI.createButton(topbarMenuDropdown, "Reset Styles to Default", function()
				topbarMenuDropdown:Hide()

				local tokens, rules = require(utilities.Defaults.DefaultStyle)(Manager)
				local style = Style.fromRulesTokens(rules, tokens)
				Manager.Style:Replace(style)
				Manager.Style = style

				updateVirtualScroller()
			end)
			PluginUI.createButton(topbarMenuDropdown, "Reset Settings to Default", function()
				topbarMenuDropdown:Hide()
				local settings = require(utilities.Defaults.DefaultSettings)
				for _, t in settings do
					for k, v in t do
						Manager.setSetting(k, v.Default)
					end
				end

				updateVirtualScroller()
			end)
			PluginUI.createButton(topbarMenuDropdown, "Reset Order to Default", function()
				topbarMenuDropdown:Hide()

				OrderEditor.ClassPriorities = require(utilities.Defaults.DefaultOrder)(Manager)
				OrderEditor.DefaultPriority = 999

				state.HierarchyVersion += 1
				updateVirtualScroller()
			end)
			PluginUI.createButton(topbarMenuDropdown, "Reset Versions", function()
				topbarMenuDropdown:Hide()

				VersionControl.Versions = {}
			end)
			PluginUI.createSeparator(topbarMenuDropdown)
			PluginUI.createButton(topbarMenuDropdown, "Kill Jexplorer", function()
				onClose()
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

local function init_register_tag_listeners(
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

			local tag = tagMap[tag_str]
			if not tag then
				-- Tag entity doesn't exist yet, create it
				tag = queryWorld:entity()
				tagMap[tag_str] = tag
			end
			if table.find(tags, tag) then continue end
			table.insert(tags, tag)
		end
		deregisterFromQueryWorld(world, queryWorld, entity)
		registerToQueryWorld(world, queryWorld, entity, classNameCache[entity], tags)
	end

	local tagAddedSignals = {}
	local tagRemovedSignals = {}
	local function onTag(tag: string)
		if tag:match("JEXP") then return end

		local tagComponent = queryWorld:entity()
		world:set(tagComponent, Jecs.Name, tag)
		tagMap[tag] = tagComponent

		local function onAdded(inst: Instance)
			if isInstanceJexpUi(inst) then return end
			
			local listener = onTagAddedListeners[inst]
			if listener then listener(tag) end

			local entity = instanceToEntity[inst]
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
			if isInstanceJexpUi(inst) then return end

			local listener = onTagRemovedListeners[inst]
			if listener then listener(tag) end

			local entity = instanceToEntity[inst]
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

			local tagEnt = tagMap[tag]
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

local function init_start_track_scrolling(state: Types.WidgetState)
	local jexplorerUi = state.JExplorerUI
	local scrollTrackerConnection, scrollTrackerThread = trackScrolling()
	local instanceTree = jexplorerUi.InstanceTree
	instTreeAbsoluteSizeY = instanceTree.AbsoluteSize.Y
	return scrollTrackerConnection, scrollTrackerThread
end

local function init_create_entities(state: Types.WidgetState, components: typeof(Manager.Components), entities: {ExplorerEntity})
	local world = state.World
	-->> Initialize entities
	-- Initialize services
	for _, service in game:GetChildren() do
		-- Prevent a specific FilteredSelection instance with no classname from showing up
		if not service.ClassName:match("%w+") then continue end
		
		local entity = Manager.createInstanceEntity(service)
		table.insert(entities, entity)
	end
	flushEntityPropAssignQueue()
	
	for _, entity in entities do
		local frame = getExplorerFrame()
		assignExplorerFrame(frame, entity)
	end
	flushTagAssignQueue()
	profileend()
end

local function init_connections(state: Types.WidgetState, components: typeof(Manager.Components), topbarMenuDropdown: PluginUI.ItemList): {RBXScriptConnection}
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
			instTreeAbsoluteSizeY = instanceTree.AbsoluteSize.Y
		end),
		jexplorerUi.InstanceTree:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			updateVirtualScroller(true)
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
			sheet:UpdateTokens()
		end),
		jexplorerWidget.PluginDragDropped:Connect(function(dragData)
			local targetInst, propName = Manager.unpackDragInfo(dragData)

			local mousePos = jexplorerWidget:GetRelativeMousePosition()
			local _, entity = Manager.getEntityAt(mousePos.X, mousePos.Y)
			if not entity then return end

			local inst = world:get(entity, components.Instance)
			if not inst then return end

			rawnewindex(targetInst, propName, inst)
		end),
		game.DescendantRemoving:Connect(function(descendant)
			local childEntity = instanceToEntity[descendant]
			if not childEntity then return end
			
			if world:has(childEntity, components.AncestryLocked) then
				return
			end
			
			table.insert(entityCleanupQueue, childEntity)
		end),
		Selection.SelectionChanged:Connect(function()
			profilebegin("Manager::onSelectionChanged")
			local selection = Selection:Get()
			currentSelectionCache = selection

			local entities = {}
			local n = 0
			for _, v in selection do
				while not instanceToEntity[v] do
					task.wait()
				end

				local ent = instanceToEntity[v]
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
				setSelection(world, {}, false)
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

					local textSize = TextService:GetTextSize(cumulativeText, size, font, absSize)
					table.insert(segmentBounds, {bound = textSize.X, entity = entities[i]})
				end

				pathClickConnection = pathButton.Activated:Connect(function(input: InputObject)
					local relativeX = input.Position.X - pathButton.AbsolutePosition.X
					for _, item in segmentBounds do
						if relativeX <= item.bound then
							Selection:Set {item.entity}
							break
						end
					end
				end)

				pathButton.Text = table.concat(pathParts, " / ")
				pathSegments.CanvasPosition = pathSegments.AbsoluteCanvasSize
			end

			for v in selectedQuery:iter() do
				world:remove(v, components.Selected)
			end
			for _, ent in entities do
				world:add(ent, components.Selected)
			end
			if n == 0 then return end

			local autoExpand = Manager.getSetting("AutoExpandOnSelect")
			-- I am a genius for this
			if autoExpand then
				profilebegin("Manager::onSelectionChanged::expandAncestorsToSelection")
				for _, entity in entities do
					local unexpanded
					local currentParent = parent_of(entity)
					while currentParent do
						if not world:has(currentParent, components.Expanded) then
							unexpanded = currentParent
						end
						world:add(currentParent, components.Expanded)
						currentParent = parent_of(currentParent)
						if currentParent then
							invalidateEntityStateCache(currentParent)
						end
					end
					if unexpanded then
						--toggleExpand(world, unexpanded, true, false)
						world:add(unexpanded, components.Expanded)
						invalidateEntityStateCache(unexpanded)
					end
				end
				updateExpandedVisuals(world, false)
				profileend()
			end

			-- Jump the canvas position to the middle entity
			local middle = entities[math.max(#entities // 2, 1)]
			local _, entityIndex = getFlattenedVisibleEntities(world, {}, false)
			local idx = entityIndex[middle]
			if idx then
				local currentViewportTop = instanceTree.CanvasPosition.Y
				local currentViewportBottom = currentViewportTop + instTreeAbsoluteSizeY
				
				local size: UDim2 = Manager.Style:GetToken("InstanceFrameSize")

				local targetFrameY = (idx - 1) * size.Y.Offset
				local targetFrameBottom = targetFrameY + size.Y.Offset

				if targetFrameY < currentViewportTop or targetFrameBottom > currentViewportBottom then
					local target = Vector2.new(
						0,
						math.max(
							0,
							targetFrameY - (instTreeAbsoluteSizeY - size.Y.Offset) / 2
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
			
			updateVirtualScroller()
			updateSelectionVisuals(world, false)
			profileend()
		end),
		Manager.connectInputBegan(function(input)
			if input.UserInputState ~= Enum.UserInputState.Begin then return end
			downKeys[input.KeyCode] = true
			activeInputs[input.UserInputType] = true
			
			-- If theres somehow still ongoing drag after input can be recieved here, stop it
			if state.CurrentDrag then
				state.CurrentDrag.Connections:free()
				state.CurrentDrag = nil
			end
			if input.UserInputType ~= Enum.UserInputType.MouseMovement then
				Manager.ItemLists.InsertInstance:Hide()
			end
			
			if input.KeyCode == Enum.KeyCode.Escape or (Manager.isKeyDown(Enum.KeyCode.Backspace) and Manager.isKeyDown(Enum.KeyCode.LeftShift)) then
				triggerEscapeTarget()
			elseif input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
				triggerDeleteTarget()
			elseif Manager.isKeyDown(Enum.KeyCode.LeftControl) and Manager.isKeyDown(Enum.KeyCode.D) then
				triggerDuplicateTarget()
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

		-- Optimized Query Handler
		queryInput.FocusLost:Connect(function(enterPressed)
			if not enterPressed then return end
			profilebegin("Manager::query")
			
			local queryText = queryInput.Text
			clearHeightCache()
			
			for _, entity in state.Entities do
				local frame = world:get(entity, components.Frame)
				if frame then
					local inst = frame_of(frame)
					if inst then
						inst.Main.Arrow.Visible = getChildAmount(entity) > 0
					end
				end
			end

			-- Collapse ancestors from previous queries
			for entity in world:query(components.QueryExpanded):iter() do
				world:remove(entity, components.QueryExpanded)
				invalidateEntityStateCache(entity)
			end
			for entity in world:query(components.QueryAncestor):iter() do
				world:remove(entity, components.QueryAncestor)
			end
			for entity in world:query(components.IsQueried):iter() do
				world:remove(entity, components.ArrowInvisible)
			end
			
			updateCollapsedVisuals(world, false)

			if queryText == "" then
				queryInput.QueryCount.Text = "0"
				for _, entity in state.Entities do
					world:remove(entity, components.QueryInvisible)
					invalidateEntityStateCache(entity)
					world:remove(entity, components.IsQueried)
				end
				updateVirtualScroller()
				return
			end

			profilebegin("Manager::query::hideEntities")
			for _, entity in state.Entities do
				world:add(entity, components.QueryInvisible)
				invalidateEntityStateCache(entity)
				world:remove(entity, components.IsQueried)
			end
			profileend()

			local success, result = pcall(function()
				profilebegin("Manager::query::parse")
				local conditions = JQL.parseQuery(queryText)
				profileend()
				profilebegin("Manager::query::execute")
				local queryResult = JQL.executeQuery(world, queryWorld, components, componentMap, tagMap, conditions)
				profileend()
				return queryResult
			end)
			
			if not success then
				if not success then
					warn("JEXPLORER Query error: " .. tostring(result))
				end
				profilebegin("Manager::query::showEntities")
				for entity in world:query(components.QueryInvisible):iter() do
					world:remove(entity, components.QueryInvisible)
					invalidateEntityStateCache(entity)
					world:remove(entity, components.IsQueried)
				end
				profileend()
				clearHeightCache()
				updateVirtualScroller()
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

			profilebegin("Manager::query::optimizedVisibility")

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
				invalidateEntityStateCache(entity)
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
						invalidateEntityStateCache(parent)
					end

					world:add(last, components.QueryAncestor)
				end
			end
			
			clearHeightCache()
			updateExpandedVisuals(world, true, components.QueryExpanded)

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
			setSelection(world, queried, true)
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

	local c = Jecs.component
	local tag = Jecs.tag
	Manager.Components = {
		PendingChanges 		= tag(),
		Deleted 			= tag(),
		Selected			= tag(),
		Expanded			= tag(),
		Invisible			= tag(),
		QueryInvisible		= tag(),
		IsQueried 			= tag(),
		AncestryLocked 		= tag(),
		ArrowInvisible 		= tag(),
		QueryAncestor 		= tag(),
		QueryExpanded 		= tag(),
		DisplayTopLevel		= tag(),
		HasInvisRoot		= tag(),

		Instance			= c(),
		Frame 				= c(),
		Entity				= c(),
		FrameState			= c(),
		Connections 		= c(),
		FavoriteProxy		= c(),
		FavoriteProxySource = c(),
		ScriptErrors 		= c(),
		ScriptWarns 		= c(),
		QueryLinkedEntities = c(),
		LinkedQueryEntity 	= c(),
		Tab					= c(),
		ParentTabs			= c(),
	}

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
		Tabs = currentTabs,
		RepoProxies = {},
		CurrentSelection = {},
		Favorited = {},
		HierarchyVersion = 0,
		JExplorerUI = jexplorerUi,
		SavedState = nil :: any,
		DefaultInstanceActionsArray = nil :: any,
		InstanceContextMenus = nil :: any,
		MiscContextMenus = nil :: any
	}
	Manager.AbstractEntClasses = {
		Favorited = "JEXP_ABSTRACT_Favorited"
	}

	local state = Manager.WidgetState
	local components = Manager.Components
	local topbar = jexplorerUi.Topbar
	
	local queryInput = topbar.QueryInput
	local selectQueried = queryInput.SelectQueried
	
	--#assignqueries
	selectedQuery = world:query(components.Instance, components.Selected):cached()
	notSelectedQuery = world:query(components.Frame):without(components.Selected):cached()
	withoutIsQueried = world:query(components.Instance):without(components.IsQueried):cached()
	unassignedFrameQuery = state.FrameWorld:query(components.Instance):without(components.Entity):cached()
	
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

	local favoritedInstancesEntity = Manager.createVirtualEntity(
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
	
	local topbarMenuDropdown = init_create_topbar_dropdown_menu(state, components, topbar, onClose)
	
	init_register_context_menus_and_actions(state, components, favoritedInstancesEntity)
	init_register_item_lists(state, components)
	
	local tagAddedSignals, tagRemovedSignals, tagAdded, tagRemoved = init_register_tag_listeners(state, components)
	local scrollTrackerConnection, scrollTrackerThread = init_start_track_scrolling(state)
	
	local entities = {favoritedInstancesEntity}
	init_create_entities(state, components, entities)

	ContextMenuEditor.init(Manager)
	
	allTab = Manager.registerTab("All", entities, false, false, false)
	-- Wait until robloxs scrollingframe update
	task.delay(1.5, allTab.Toggle)
	
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
	
	local scriptConnections = init_connections(state, components, topbarMenuDropdown)
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
		local suc1 = flushOnChildAddedQueue()
		local suc2 = flushOnChildRemovedQueue()
		local suc3 = cleanupEntities(entityCleanupQueue)

		if suc1 or suc2 or suc3 then
			childMapNeedsUpdate = true
		end
	end

	local function reuseCycle()
		flushFrameReuseQueue()
		if childMapNeedsUpdate then
			childMapNeedsUpdate = false
			state.HierarchyVersion += 1
			updateVirtualScroller()
		end
	end
	
	local function entityDeletionCycle()
		local n = #entityDeleteQueue
		if n == 0 then return end
		
		local start = math.max(1, n - 30)
		for i = n, start, -1 do
			local entity = entityDeleteQueue[i]
			entityDeleteQueue[i] = nil

			local idx = table.find(state.Entities, entity)
			if idx then table.remove(state.Entities, idx) end

			local queryEntity = world:get(entity, components.LinkedQueryEntity)
			world:delete(entity)

			if not queryEntity then continue end
			local linked = queryWorld:get(queryEntity, components.QueryLinkedEntities)

			if not linked then continue end
			
			local n = #linked
			if n > 1 then
				local idx = table.find(linked, entity)
				if idx then linked[idx] = linked[n];linked[n] = nil end
				continue
			end

			queryWorld:delete(queryEntity)
		end
	end

	local threads = connections:extend(task.cancel, {
		scrollTrackerThread,
		task.spawn(function()
			while true do
				task.wait(Manager.getSetting("FlushCycleInterval"))
				flushCycle()
			end
		end),
		task.spawn(function()
			while true do
				task.wait(Manager.getSetting("FrameReuseCycleInterval"))
				reuseCycle()
			end
		end),
		task.spawn(function()
			while true do
				task.wait(Manager.getSetting("EntityCleanupCycleInterval"))
				entityDeletionCycle()
			end
		end),
		task.spawn(function()
			while true do
				task.wait(Manager.getSetting("EntityCreationCycleInterval"))
				flushEntityCreationQueue()
			end
		end),
	})
	
	jexplorerUi.Parent = jexplorerWidget
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
		invisible = invisibleClasses,
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

			SavedState._serialize_rules(style.Rules, rules, RULE_NO_SAVE_TAG)
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
					table.insert(destination, rule(r.display_name, r.selector, r.priority, props))
				end
			end
			deserialize_rules(savedState.style.rules, rules)
			for k, v in savedState.style.tokens do
				tokens[k] = UDF.from(v)
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
			invisibleClasses = savedState.invisible
		end,
	}, savedState
end

Manager.getExplorerFrame = getExplorerFrame
function Manager.setInstanceFramePoolTarget(n)
	instanceFramePoolTarget = n
end
Manager.fillInstanceFramePoolToLimit = fillInstanceFramePoolToLimit
Manager.addEntitiesToSelection = addEntitiesToSelection
Manager.setEntitiesAsSelection = setSelection
Manager.updateVirtualScroller = updateVirtualScroller
Manager.getPropertyTag = getPropertyCt
Manager.frameOf = frame_of
Manager.ChildOf = ChildOf

return Manager