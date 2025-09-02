--!optimize 2
--!strict

--[[
	Main manager module for keeping track of widget state
	
	Sorry for the lack of comments, i kinda just gave up ngl
]]

local plugin = script:FindFirstAncestorOfClass("Plugin")

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

local IS_EDIT = RunService:IsEdit()

local main = script.Parent

local utilities = main.Utilities
local editors = main.Editors
local ui = main.UI

local Jecs = require(main.Jecs)
local Types = require(main.Types)

local StyleEditor = require(editors.StyleEditor)
local SettingEditor = require(editors.SettingEditor)
local OrderEditor = require(editors.OrderEditor)
local VersionControl = require(editors.VersionControl)
local InstanceVisibilityEditor = require(editors.InstanceVisibilityEditor)
local PropertyEditor = require(editors.PropertyEditor)
local ContextMenuEditor = require(editors.ContextMenuEditor)

local Group = require(utilities.Group)
local PluginUI = require(utilities.PluginUI)
local Transform = require(utilities.Transform)
local Style = require(utilities.Style)
local JDF = require(utilities.JDF)
local JQL = require(utilities.JQL)
local Signal = require(utilities.SimpleSignal)
local JState = require(utilities.JState)
local InstanceUtility = require(utilities.InstanceUtility)
local BuildAPIMap = require(utilities.APIMap)
local Selector = require(utilities.Selector)
local ClassIcon = require(utilities.ClassIcon)
local childrenOf = require(utilities.ChildrenOf)
local getClampedXY = require(utilities.GetClampedXY)
local Converter = require(utilities.Converter)
local d = Converter.data

local getId = PluginUI.getId
local tween = Transform.tween
local rule = Style.rule
local var = Style.var

local index = InstanceUtility.index
local newindex = InstanceUtility.newindex

local rawindex = InstanceUtility.rawindex
local rawnewindex = InstanceUtility.rawnewindex

type WidgetState = Types.WidgetState
type StudioIconResult = Types.StudioIconResult
type InstanceFrame = Types.InstanceFrame
type InstanceEntity = Types.InstanceEntity
type Tab = Types.Tab

type World = Types.World

local downKeys: {[Enum.KeyCode]: boolean?} = {}
local activeInputs: {[Enum.UserInputType]: boolean?} = {}

local componentMap: {[string]: Jecs.Id<any>} = {}
local tagMap: {[string]: Jecs.Id} = {}
local classComponentCache: {[string]: {Jecs.Id}} = {} -- [ClassName] = { Component }

local instanceToEntity: {[Instance]: InstanceEntity} = {}
local pooledInstanceFrames: {InstanceFrame} = {}
local frameToInstanceFrame: {[Instance]: InstanceFrame} = {}

local tagAssignQueue: {{frame: InstanceFrame, entity: InstanceEntity}} = {}
local frameReuseQueue: {InstanceEntity} = {}
local entityPropAssignQueue: { {entity: InstanceEntity, tags: {Jecs.Id}} } = {}
local entityCleanupQueue: {InstanceEntity} = {}
local onChildAddedQueue: { {child: Instance, parent: InstanceEntity} } = {}
local onChildRemovedQueue: { {child: Instance, parent: InstanceEntity} } = {}
local entityDeleteQueue: {InstanceEntity} = {}

local debugIdToInstance = setmetatable({}, {__mode = "v"})

local classNameCache: {[InstanceEntity]: string} = {}
local nameCache: {[InstanceEntity]: string} = {}
local childAmountCache: {[InstanceEntity]: number} = {}
local tabFrameToTab: {[Instance]: Tab} = {}
local currentTabs: {Tab} = {}

local selectedQuery: Jecs.Query<Instance>
local notSelectedQuery: Jecs.Query<InstanceFrame>
local withoutIsQueried: Jecs.Query<>

local instTreeAbsoluteSizeY: number = 0
local allTab: Tab

-- Properties which get assigned their own tag when their value exists/is changed
local TAGGED_PROPERTIES = {
	"RunContext", "Enabled", "Name", "ClassName"
}

-- TODO: Change this when the APIMap format changes
local API_MAP_VERSION = 5

local CLEANUP_LOOP_INTERVAL = 1/30
local REUSE_LOOP_INTERVAL = 1/30
local ENT_DELETE_LOOP_INTERVAL = 0.5

local INSTANCE_INSERT_INFO = require(script.InstanceInsertInfo)

local API_MAP_SCHEMA = d.dict_64(
	d.str_u8(),
	d.dict_8(
		d.str_u8(),
		d.struct {
			Category = d.str_u8(),
			Type = d.str_u8(),
			Readable = d.boolean(),
			Writable = d.boolean(),
		}
	)
)

local hierarchyCache = {
	childrenMap = {} :: {[InstanceEntity]: {InstanceEntity}},
	roots = {} :: {InstanceEntity},
	--expandedHeights = {} :: {[InstanceEntity]: number}
}
local classPriorityCache = {}
local lastCacheVersion = -1
local lastPriorityVersion = -1

local recentlyReusedEntities = {}
local reuseDebounceTime = {}
local isScrolling = false
local childMapNeedsUpdate = false
local lastScrollTime = 0

local tabInsertListener: RBXScriptConnection?
local isCurrentlyPickingTabRoots = false
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

local Manager = {
	InstanceToEntity = instanceToEntity,
	FrameToInstanceFrame = frameToInstanceFrame,
	SelectionChanged = Signal.new()
	-- Will be initialized by the main plugin script before anything else runs so no problem
} :: Types.Manager

local showInsertInstanceMenu
local APIMap: {[string]: {[string]: any}}

local function loop(interval: number, fn: () -> ())
	while true do task.wait(interval) fn() end
end

local function ChildOf(c: InstanceEntity)
	return Jecs.pair(Jecs.ChildOf, c)
end

local function widgetIsJexp(g: Instance)
	local state = Manager.WidgetState
	return g == state.Widget or g == StyleEditor.Widget or g == OrderEditor.Widget or g == SettingEditor.Widget or g == PropertyEditor.Widget or g == ContextMenuEditor.Widget
end

local function getChildAmount(entity: InstanceEntity)
	return childAmountCache[entity] or 0
end

local function isEntityInvisible(world: World, entity: InstanceEntity)
	local components = Manager.Components
	return
		world:has(entity, components.Invisible)
		or	world:has(entity, components.QueryInvisible)
		or	InstanceVisibilityEditor.InvisibleClasses[classNameCache[entity]]
end

local function isEntityGone(world: World, entity: InstanceEntity)
	local components = Manager.Components
	return world:has(entity, components.Deleted) or not world:contains(entity)
end

local function getTaggedPropertyTag(propName: string, targetedValue: string)
	return `JEXP_TAGGED_{propName}_{targetedValue}`
end

local function parent_of(ent: InstanceEntity): InstanceEntity?
	local world = Manager.WidgetState.World
	local components = Manager.Components

	if world:has(ent, components.DisplayTopLevel) then
		return nil
	else
		return world:parent(ent)
	end
end

local onceDebounce = {}
local function once<T...>(fn: (T...) -> (...any), ...: T...)
	if onceDebounce[fn] then return end
	onceDebounce[fn] = true
	fn(...)
end

local function printGoneStatus(ents: {InstanceEntity})
	local tbl = {}
	for k, v in ents do
		tbl[k] = isEntityGone(Manager.WidgetState.World, v)
	end
	print(tbl)
end

local function getPropertyComponentsForClass(world: World, className: string)
	local cached = classComponentCache[className]
	if cached then return cached end

	local components = {}
	local props = APIMap[className]
	if not props then
		classComponentCache[className] = components
		return components
	end

	for k in props do
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

local function deregisterFromQueryWorld(world: World, queryWorld: World, entity: InstanceEntity)
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

local function registerToQueryWorld(world: World, queryWorld: World, entity: InstanceEntity, className: string, tags: {Jecs.Id<any>}?)
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

local function calculateDeepHeight(world: World, expanded: Jecs.Id, childrenMap: {[InstanceEntity]: {InstanceEntity}}, heightCache: {[InstanceEntity]: number}, entity: InstanceEntity): number
	if isEntityInvisible(world, entity) or isEntityGone(world, entity) then return 0 end
	-- Check cache first
	if heightCache[entity] then
		return heightCache[entity]
	end
	-- If not expanded, height is just 1 (the entity itself)
	if not world:has(entity, expanded) then
		heightCache[entity] = 1
		return 1
	end
	-- Get direct children
	local children = childrenMap[entity]
	if not children or #children == 0 then
		heightCache[entity] = 1
		return 1
	end

	-- Calculate total height: 1 (self) + sum of all children heights
	local totalHeight = 1
	for _, child in children do
		totalHeight += calculateDeepHeight(world, expanded, childrenMap, heightCache, child)
	end

	heightCache[entity] = totalHeight
	return totalHeight
end

local function calculateDirectHeight(world: World, expanded: Jecs.Id, childrenMap: {[InstanceEntity]: {InstanceEntity}}, entity: InstanceEntity): number
	if isEntityInvisible(world, entity) or isEntityGone(world, entity) then return 0 end

	-- If not expanded, height is just 1 (the entity itself)
	if not world:has(entity, expanded) then
		return 1
	end

	-- Get direct children
	local children = childrenMap[entity]
	if not children or #children == 0 then
		return 1
	end

	-- Calculate height: 1 (self) + count of direct visible children
	local totalHeight = 1
	for _, child in children do
		if not isEntityInvisible(world, child) and not isEntityGone(world, child) then
			totalHeight += 1  -- Each direct child contributes 1 to height
		end
	end

	return totalHeight
end

-- Goes up expanded parents to update their expanded heights
--local function cascadeUpdateExpandedHeights(world: World, entity: InstanceEntity): number
--	profilebegin("Manager::getExpandedEntityHeight")
--	local components = Manager.Components
--	local childrenMap = hierarchyCache.childrenMap

--	local accumulatedHeight = 0
--	local currentParent = parent_of(entity)

--	while currentParent and world:has(currentParent, components.Expanded) do
--		local parentDirectHeight = calculateDirectHeight(world, components.Expanded, childrenMap, currentParent)
--		local totalParentHeight = parentDirectHeight + accumulatedHeight
--		accumulatedHeight = totalParentHeight
--		hierarchyCache.expandedHeights[currentParent] = accumulatedHeight

--		currentParent = parent_of(currentParent)
--	end

--	profileend()
--	return accumulatedHeight
--end

local function flushEntityPropAssignQueue()
	if #entityPropAssignQueue == 0 then return false end

	local world = Manager.WidgetState.World
	local queryWorld = Manager.WidgetState.QueryWorld
	local components = Manager.Components

	profilebegin("Manager::flushEntityPropAssignQueue")
	for _, data in entityPropAssignQueue do
		local ent = data.entity

		local instance = world:get(ent, components.Instance)
		if not instance then continue end

		local className = instance.ClassName

		nameCache[ent] = instance.Name
		classNameCache[ent] = className
		childAmountCache[ent] = #instance:GetChildren()
		debugIdToInstance[instance:GetDebugId()] = instance
		--hierarchyCache.expandedHeights[ent] = 1

		deregisterFromQueryWorld(world, queryWorld, ent)
		registerToQueryWorld(world, queryWorld, ent, className, data.tags)
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

	profilebegin("Manager::flushTagAssignQueue")
	for _, v in tagAssignQueue do
		local frame, entity = v.frame, v.entity
		local inst = world:get(entity, components.Instance) :: Instance
		local scriptErrors = world:get(entity, components.ScriptErrors)
		local scriptWarns = world:get(entity, components.ScriptWarns)

		frame.Instance.Main.PendingChanges.Visible = world:has(entity, components.PendingChanges)
		for _, v in frame.TagsToRemove do
			frame.Instance:RemoveTag(v)
		end
		frame.TagsToRemove = getFrameTags(inst)
		if scriptErrors and #scriptErrors > 0 then
			table.insert(frame.TagsToRemove, "JEXP_ScriptError")
		elseif scriptWarns and #scriptWarns > 0 then
			table.insert(frame.TagsToRemove, "JEXP_ScriptWarn")
		end
		for _, tag in frame.TagsToRemove do
			if frame.Instance:HasTag(tag) then continue end
			frame.Instance:AddTag(tag)
		end
	end
	table.clear(tagAssignQueue)
	profileend()
	return true
end

local function updateEntityOrder(world: World, entity: InstanceEntity, newParent: InstanceEntity?)
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

local function flushFrameReuseQueue(depth: number?)
	profilebegin("Manager::flushFrameReuseQueue")
	if #frameReuseQueue == 0 then return false end
	local depth = depth or 0

	local state = Manager.WidgetState
	local world = state.World
	local children = {}
	local tounassign = {}

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
		for child in world:children(entity) do
			table.insert(children, child)
		end
		profileend()
	end
	for _, frame in tounassign do
		frame:Assign(nil)
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

local function cleanupEntities(queueTable: {InstanceEntity})
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
			frame:Reuse()
		end
		
		profileend()
	end
	
	profilebegin("Manager::cleanupEntity::processDeferredCleaningTasks")
	profilebegin("freeGroups")
	for _, group in groupsToFree do
		group:Free()
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

local function cleanupEntity(ent: InstanceEntity)
	local state = Manager.WidgetState
	local world, components = state.World, Manager.Components
	world:add(ent, components.Deleted)

	table.insert(entityCleanupQueue, ent)
end

local function getScrollingOffsetFromTop(world: World, entity: InstanceEntity, idx: number)
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

local function addEntityPriorities(world: World, children: {InstanceEntity}, priorities: any)
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

local function getFlattenedVisibleEntities(world: World, invisible: {InstanceEntity}): {InstanceEntity}
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
	
	local flatList = {}
	local flatIndex = 0
	local invisibleIndex = #invisible
	local stack = {}
	local stackSize = 0
	local invisibilityCache = {}
	local function isInvisibleCached(entity)
		if invisibilityCache[entity] == nil then
			invisibilityCache[entity] = isEntityInvisible(world, entity) or isEntityGone(world, entity)
		end
		return invisibilityCache[entity]
	end
	profilebegin("Manager::getFlattenedVisibleEntities::traverse")
	for i = #roots, 1, -1 do
		stackSize += 1
		stack[stackSize] = roots[i]
	end

	while stackSize > 0 do
		local entity = stack[stackSize]
		stackSize -= 1

		if isInvisibleCached(entity) then
			invisibleIndex += 1
			invisible[invisibleIndex] = entity
		else
			flatIndex += 1
			flatList[flatIndex] = entity

			if world:has(entity, components.Expanded) then
				local children = childrenMap[entity]
				if children then
					for i = #children, 1, -1 do
						stackSize += 1
						stack[stackSize] = children[i]
					end
				end
			end
		end
	end
	
	profileend()
	profileend()
	return flatList
end

local function filterVisible(world: World, top: number, viewportHeight: number)
	profilebegin("Manager::filterVisible")
	local components = Manager.Components
	local state = Manager.WidgetState
	local sheet = Manager.Style

	local size: UDim2 = sheet:GetToken("InstanceFrameSize")
	local height = size.Y.Offset

	local visible = {}
	local invisible = {}
	local expandedHeightIndex = {}
	local flattenedEntities = getFlattenedVisibleEntities(world, invisible)
	local entityToIndex = {}
	for index, entity in flattenedEntities do
		entityToIndex[entity] = index
	end
	
	local frameBuffer = Manager.getSetting("VirtualScrollFrameBuffer")
	local viewportBuffer = height * frameBuffer
	local viewportHeight = viewportHeight + viewportBuffer
	local heightCache = {}

	for index, entity in flattenedEntities do
		profilebegin("Manager::filterVisible::visibleCheck")
		local frame = world:get(entity, components.Frame)

		local absoluteYOffset = height * (index - 1)
		local shouldBeVisible = false
		if not world:has(entity, components.Expanded) then
			shouldBeVisible = absoluteYOffset >= (top - viewportBuffer) and absoluteYOffset <= (top + viewportHeight)
		else
			local expandedHeight =  calculateDeepHeight(
				world,
				components.Expanded,
				hierarchyCache.childrenMap,
				heightCache,
				entity
			)
			local expandedBottomOffset = absoluteYOffset + (height * expandedHeight)
			expandedHeightIndex[entity] = expandedHeight
			
			-- Frame is visible if either:
			-- 1. The top of the frame is in viewport, OR
			-- 2. The bottom of the expanded frame (including all children) is in viewport, OR  
			-- 3. The frame spans the entire viewport (top above, bottom below)
			local topInView = absoluteYOffset >= (top - viewportBuffer) and absoluteYOffset <= (top + viewportHeight)
			local bottomInView = expandedBottomOffset >= (top - viewportBuffer) and expandedBottomOffset <= (top + viewportHeight)
			local spansView = absoluteYOffset < (top - viewportBuffer) and expandedBottomOffset > (top + viewportHeight)

			shouldBeVisible = topInView or bottomInView or spansView
		end

		if not shouldBeVisible then
			table.insert(invisible, entity)
		else
			table.insert(visible, {
				entity = entity,
				yoffset = absoluteYOffset
			})
		end
		profileend()
	end
	profileend()
	return visible, invisible, entityToIndex, height, expandedHeightIndex
end

local isVirtualScrollerUpdating = false
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
	local visible, invisible, entityToIndex, height, expandedHeightIndex = filterVisible(world, top, instTreeAbsoluteSizeY)

	local currentTime = os.clock()
	for _, entity in invisible do
		local frame = world:get(entity, components.Frame)
		if frame and not isScrolling then
			local lastReuseTime = reuseDebounceTime[entity] or 0

			if currentTime - lastReuseTime > Manager.getSetting("VirtualReuseCooldown") then
				frame:Reuse()
				reuseDebounceTime[entity] = currentTime
			end
		end
	end
	flushFrameReuseQueue()

	for _, info in visible do
		local entity, absoluteYOffset = info.entity, info.yoffset
		local instance = world:get(entity, components.Instance) :: Instance

		local frame = world:get(entity, components.Frame)
		reuseDebounceTime[entity] = nil

		local parent = parent_of(entity)
		if frame then
			frame:Assign(entity, parent)
		else
			local f = getInstanceFrame()
			world:set(entity, components.Frame, f)
			f:Assign(entity, parent)
			frame = f
		end
		if not frame then continue end

		frame.Instance.LayoutOrder = entityToIndex[entity]
		if not isScroller then
			local n = 0
			for child in world:query(ChildOf(entity)):without(components.Deleted):iter() do
				if isEntityInvisible(world, child) then continue end
				n += 1
			end
			childAmountCache[entity] = n
		end

		if world:has(entity, components.ArrowInvisible) then
			frame.Instance.Main.Arrow.Visible = false
		else
			local visible = getChildAmount(entity) > 0
			frame.Instance.Main.Arrow.Visible = visible
			frame.Instance.Children.Visible = visible
		end

		if parent then
			local parentIndex = entityToIndex[parent]
			if parentIndex then
				local parentAbsoluteYOffset = height * parentIndex
				local relativeYOffset = absoluteYOffset - parentAbsoluteYOffset
				frame.Instance.Position = UDim2.fromOffset(0, relativeYOffset)
			else
				frame.Instance.Position = UDim2.fromOffset(0, absoluteYOffset)
			end
		else
			frame.Instance.Position = UDim2.fromOffset(0, absoluteYOffset)
		end
		local expandedHeight = expandedHeightIndex[entity]
		if expandedHeight and world:has(entity, components.Expanded) then
			frame.Instance.Children.List.Size = UDim2.new(1, 0, 0, (expandedHeight - 1) * height)
		else
			frame.Instance.Children.List.Size = UDim2.new(1, 0, 1, 0)
		end
	end

	flushTagAssignQueue()
	isVirtualScrollerUpdating = false
	profileend()
end

local function toggleExpand(world: World, entity: InstanceEntity, expanded: boolean, update: boolean)
	profilebegin("Manager::toggleExpand")

	local components = Manager.Components
	local instance, frame = world:get(entity, components.Instance, components.Frame)
	if not frame then
		return
	end
	assert(instance)

	local components = Manager.Components
	local arrow = frame.Instance.Main.Arrow
	local children = frame.Instance.Children

	if instance == game then return end

	local n = getChildAmount(entity)
	if not world:has(entity, components.ArrowInvisible) then
		arrow.Rotation = 0
		arrow.Visible = n > 0
	end
	if not expanded then
		world:remove(entity, components.Expanded)
		children.Visible = false

		for child, frame in world:query(components.Frame, ChildOf(entity)):iter() do
			frame:Reuse()
		end
	else
		world:add(entity, components.Expanded)
		children.Visible = true
		--hierarchyCache.expandedHeights[entity] = calculateDeepHeight(
		--	world,
		--	components.Expanded,
		--	hierarchyCache.childrenMap,
		--	{},
		--	entity
		--)
	end

	if update then
		updateVirtualScroller()
	end
	profileend()
end

-- TODO: Should probably make another version of this since i dont know how the hell this even works, but for now keep it
local function getEntitiesBetween(world: World, e1: InstanceEntity, e2: InstanceEntity): {InstanceEntity}
	profilebegin("Manager::getEntitiesBetween")
	local visible = getFlattenedVisibleEntities(world, {})
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

local function createEntityWithChildren(inst: Instance, parent: InstanceEntity?)
	profilebegin("Manager::createEntityWithChildren")
	local world = Manager.WidgetState.World
	local components = Manager.Components

	local getOrCreate = Manager.getOrCreateInstanceEntity
	local worldGet = world.get
	local instanceComp = components.Instance

	local stack: {any} = {{inst::any, parent::any}}
	local stackSize = 1

	while stackSize > 0 do
		local current = stack[stackSize]
		stackSize -= 1

		local currentInst, currentParent = current[1], current[2]

		local children = currentInst:GetChildren()
		local childCount = #children

		local entities = table.create(childCount)
		local entityCount = 0

		for i = 1, childCount do
			local v = children[i]
			if not instanceToEntity[v] then
				local entity = getOrCreate(v, currentParent)
				if entity then
					entityCount += 1
					entities[entityCount] = entity
					updateEntityOrder(world, entity, currentParent)
				end
			end
		end

		for i = entityCount, 1, -1 do
			local entity = entities[i]
			local v = worldGet(world, entity, instanceComp)
			if v then
				if stackSize >= #stack then
					stack[stackSize + 1] = {}
				end
				stackSize += 1
				stack[stackSize][1] = v
				stack[stackSize][2] = entity
			end
		end
	end

	profileend()
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
			frame:ToggleSelection(true)
		end
	end
	for entityId, frame in notSelectedQuery:iter() do
		frame:ToggleSelection(false)
	end
	flushTagAssignQueue()

	profileend()
	if updateSelection then
		profilebegin("Manager::updateSelectionVisuals::setSelection")
		Selection:Set(currentSelection)
		profileend()
	end
end

local function setSelection(world: World, entities: {InstanceEntity}, updateSelection: boolean)
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

local function addEntitiesToSelection(world: World, entities: {InstanceEntity})
	local state = Manager.WidgetState
	local components = Manager.Components

	for _, entity in entities do
		world:add(entity, components.Selected)
	end
	table.move(entities, 1, #entities, #state.CurrentSelection + 1, state.CurrentSelection)
	state.LastSelectedEntity = entities[#entities]
	updateSelectionVisuals(world, true)
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
	pcall(function()
		plugin:SetSetting("CopiedInstances", 
			HttpService:JSONEncode(
				SerializationService:SerializeInstancesAsync(instances)
			)
		)
	end)
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

local function toggleSelection(world: World, entity: InstanceEntity, isCtrlHeld: boolean, isShiftHeld: boolean)
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

local function createAbstractEntity(instance: any): InstanceEntity
	local world = Manager.WidgetState.World
	local ent = world:entity()
	world:set(ent, Manager.Components.Instance, instance)
	return ent
end

local function createInstanceFrame(frame: typeof(ui.InstanceFrame))
	local state = Manager.WidgetState
	local components = Manager.Components

	local world = state.World
	local jexplorerUi = state.JExplorerUI

	local main = frame.Main

	local iconImage = main.ClassIcon
	local instanceName = main.InstanceName
	local arrow = main.Arrow

	local overlayFrame = main.Overlay
	local selectInstanceButton = overlayFrame.Select
	local insertInstanceButton = main.Insert

	local instanceFrame = {
		Instance = frame,
		Connections = Group.new("Disconnect"),
		CurrentEntity = nil,
		TagsToRemove = {}
	} :: InstanceFrame

	local lastClickTime = 0

	local isLMBActive = false
	local hasBeenSelected = false
	local shouldDeselect = false

	frameToInstanceFrame[frame] = instanceFrame
	overlayFrame:AddTag("JEXP_Hover")

	function instanceFrame:ToggleSelection(enabled)
		profilebegin("InstanceFrame::ToggleSelection")
		local has = frame:HasTag("JEXP_Selected")
		if enabled and not has then
			frame:AddTag("JEXP_Selected")
		elseif not enabled and has then
			frame:RemoveTag("JEXP_Selected")
		end
		profileend()
	end

	function instanceFrame:Reuse()
		profilebegin("InstanceFrame::Reuse")

		frame.Visible = false
		if self.CurrentEntity and not table.find(frameReuseQueue, self.CurrentEntity) then
			table.insert(frameReuseQueue, self.CurrentEntity)
		end

		profileend()
	end

	local isAssigning = false
	function instanceFrame:Assign(entity: InstanceEntity?, parent: InstanceEntity?)
		if entity and isEntityGone(world, entity) then
			self:Reuse()
			return
		end
		isAssigning = true
		local parentFrame
		if parent then
			parentFrame = world:get(parent, components.Frame)
			if not parentFrame then
				isAssigning = false
				return
			end
		end

		profilebegin("InstanceFrame::Assign")
		instanceFrame.CurrentEntity = entity
		if not entity then
			insertInstanceButton.Visible = false
			frame.Visible = false
			isAssigning = false
			return
		end
		local instance: Instance? = world:get(entity, components.Instance)
		if not instance then
			isAssigning = false
			return
		end
		table.insert(tagAssignQueue, {
			frame = self,
			entity = entity
		})
		frame.Visible = true
		
		self:ToggleSelection(world:has(entity, components.Selected))

		local sheet = Manager.Style
		
		local className = instance.ClassName
		local icon = ClassIcon.getIcon(className)
		local slctr = Selector.getIconSelector(nil, className)
		if icon and not sheet:FindRule(slctr) then
			local name = `ClassIcon_{className}`
			sheet:AddRules {
				rule(name, slctr, 0, icon)
			}
		end
		
		instanceName.Text = instance.Name
		if world:has(entity, components.ArrowInvisible) then
			-- Handled in updateVirtualScroller
			--arrow.Visible = false
		else
			if instance == game or getChildAmount(entity) == 0 then
				arrow.Visible = false
			else
				arrow.Visible = true
			end
			if world:has(entity, components.Expanded) then
				arrow.Rotation = 0
				frame.Children.Visible = true
			else
				arrow.Rotation = -90
				frame.Children.Visible = false
			end
		end

		if not state.LastSelectedEntity then
			state.LastSelectedEntity = nil
		end

		isLMBActive = false
		hasBeenSelected = false
		shouldDeselect = false

		local newParent
		if parent and parentFrame then
			local children = parentFrame.Instance:FindFirstChild("Children")
			if children then
				newParent = children.List
			end
		else
			newParent = jexplorerUi.InstanceTree
		end
		if newParent == frame.Parent then
			isAssigning = false
			profileend()
			return
		end

		pcall(rawnewindex, frame, "Parent", newParent)

		profileend()
		isAssigning = false
	end

	instanceFrame.Connections.Items = {
		instanceName:GetPropertyChangedSignal("TextBounds"):Connect(function()
			if isAssigning then return end
			local bounds: Vector2 = rawindex(instanceName, "TextBounds")
			local x = instanceName:GetStyled("Position").X.Offset + bounds.X
			insertInstanceButton.Position = UDim2.new(0, x + 10, 0.5)
			frame.Main.PendingChanges.Position = UDim2.new(0, x + 26, 0.5)
		end),
		instanceName.Focused:Connect(function()
			local entity = instanceFrame.CurrentEntity
			if not entity then return end

			state.CurrentlyRenaming = entity
			instanceName.BackgroundTransparency = 0
		end),
		instanceName.FocusLost:Connect(function(enterPressed)
			local entity = instanceFrame.CurrentEntity
			if not entity then return end
			local instance = world:get(entity, components.Instance)
			if not instance then return end

			state.CurrentlyRenaming = nil
			instanceName.BackgroundTransparency = 1
			--if not enterPressed then return end
			instance.Name = instanceName.Text
		end),

		selectInstanceButton.InputBegan:Connect(function(input)
			local entity = instanceFrame.CurrentEntity
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
				Manager.ContextMenus.Instance.Menu:ShowAsync()
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
				profilebegin("InstanceFrame::onInput::LMB (click)")
				isLMBActive = true
				hasBeenSelected = world:has(entity, components.Selected)
				shouldDeselect = false

				local currentTime = os.clock()
				local timeSinceLastClick = currentTime - lastClickTime
				lastClickTime = currentTime

				-- Check for double-click
				if timeSinceLastClick <= Manager.getSetting("DoubleClickToOpenScriptTime") and instance:IsA("LuaSourceContainer") then
					plugin:OpenScript(instance)
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
				if not hasBeenSelected then
					-- First click on unselected item - select it
					toggleSelection(world, entity, isCtrlHeld, isShiftHeld)
					return -- Don't proceed to drag logic
				elseif isCtrlHeld then
					-- Ctrl+click on selected item - mark for deselection on mouse up
					shouldDeselect = true
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

				if not isLMBActive then return end -- User released mouse quickly
				if instance.Parent == game then return end -- Can't drag game
				profilebegin("InstanceFrame::beginDrag")

				-- Start drag operation
				local dragFrame = ui.DragFrame:Clone()
				dragFrame:AddTag("JEXP_Selected")

				local amt = #state.CurrentSelection
				if amt == 1 then
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

				local dragConnections = instanceFrame.Connections:Extend("Disconnect")

				do
					local pos = state.Widget:GetRelativeMousePosition()
					dragFrame.Position = UDim2.fromOffset(pos.X, pos.Y)
				end
				dragConnections.Items = {
					RunService.RenderStepped:Connect(function()
						local pos = state.Widget:GetRelativeMousePosition()
						dragFrame.Position = UDim2.fromOffset(pos.X, pos.Y)
						if not state.CurrentDrag then
							dragConnections:Free()
						end
					end)
				}
				dragFrame.Parent = jexplorerUi

				local dragInstances = dragConnections:Extend("Destroy", {
					dragFrame
				})
				state.CurrentDrag = {
					Frame = dragFrame,
					Connections = dragConnections,
					Entities = table.clone(state.CurrentSelection)
				}
				profileend()
			end
		end),

		selectInstanceButton.InputEnded:Connect(function(input)
			local entity = instanceFrame.CurrentEntity
			if not entity then return end

			local instance = world:get(entity, components.Instance)
			if not instance then return end

			if input.UserInputState ~= Enum.UserInputState.End then return end
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end

			isLMBActive = false

			-- Handle deselection for ctrl+click
			if shouldDeselect then
				world:remove(entity, components.Selected)
				updateSelectionVisuals(world, true)
				shouldDeselect = false
				return
			end
			-- If we have multiple selections and this was just a click (not drag), 
			-- then deselect others and select only this one
			if not state.CurrentDrag and hasBeenSelected and #state.CurrentSelection > 1 then
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
			state.CurrentDrag.Connections:Free()
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
			local isExpanded = world:has(newParentEntity, components.Expanded)
			for _, dragEntity in dragEntities do
				local child = world:get(dragEntity, components.Instance)
				if not child then continue end

				local parent = parent_of(dragEntity)
				if not parent then continue end

				world:remove(dragEntity, ChildOf(parent))
				world:add(dragEntity, ChildOf(newParentEntity))

				pcall(rawnewindex, child, "Parent", newParentInstance)

				local dragFrame = world:get(dragEntity, components.Frame)
				if not isExpanded then
					if dragFrame then
						dragFrame:Reuse()
					end
				else
					if dragFrame then
						dragFrame:Assign(dragEntity, newParentEntity)
					elseif not dragFrame then
						local dragFrame = getInstanceFrame()
						world:set(dragEntity, components.Frame, dragFrame)
						dragFrame:Assign(dragEntity, newParentEntity)
					end
					updateEntityOrder(world, dragEntity, newParentEntity)
				end
			end

			flushTagAssignQueue()

			if not isExpanded then
				toggleExpand(world, newParentEntity, true, true)
			end

			for _, e in dragEntities do
				world:remove(e, components.AncestryLocked)
			end

			state.CurrentDrag = nil
			if id then
				ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
			end
			updateSelectionVisuals(world, false)
			profileend()
		end),
		selectInstanceButton.MouseEnter:Connect(function()
			local entity = instanceFrame.CurrentEntity
			if not entity then return end

			insertInstanceButton.Visible = true
			if state.CurrentDrag then
				--frame.SelectionTargetOutline.Enabled = true
				frame:AddTag("JEXP_DropTarget")
			end
		end),
		selectInstanceButton.MouseLeave:Connect(function()
			local entity = instanceFrame.CurrentEntity
			if not entity then return end

			insertInstanceButton.Visible = false
			--frame.SelectionTargetOutline.Enabled = false
			if frame:HasTag("JEXP_DropTarget") then
				frame:RemoveTag("JEXP_DropTarget")
			end
		end),
		insertInstanceButton.Activated:Connect(function()
			local entity = instanceFrame.CurrentEntity
			if not entity then return end

			state.ContextTarget = entity

			showInsertInstanceMenu(insertInstanceButton.AbsolutePosition, insertInstanceButton.AbsoluteSize)
		end),
		instanceName.FocusLost:Connect(function()
			instanceName.TextEditable = false
			instanceName.Interactable = false
		end),
		arrow.Activated:Connect(function()
			local entity = instanceFrame.CurrentEntity
			if not entity then return end

			toggleExpand(world, entity, not world:has(entity, components.Expanded), true)
		end)
	}

	return instanceFrame
end

local function fillInstanceFramePoolToLimit()
	profilebegin("Manager::fillInstanceFramePoolToLimit")
	if #pooledInstanceFrames >= instanceFramePoolTarget then return end

	local framesToCreate = instanceFramePoolTarget - #pooledInstanceFrames
	for _ = 1, framesToCreate do
		local clone = ui.InstanceFrame:Clone()
		local frame = createInstanceFrame(clone)
		clone.Visible = false
		clone.Parent = Manager.WidgetState.JExplorerUI.InstanceTree

		table.insert(pooledInstanceFrames, frame)
	end
	profileend()
end

function getInstanceFrame(): InstanceFrame
	if #pooledInstanceFrames == 0 then
		-- Attempt to reuse any pending frames before creating new ones
		local success = flushFrameReuseQueue()
		if not success or #pooledInstanceFrames == 0 then
			fillInstanceFramePoolToLimit()
		end
	end
	return table.remove(pooledInstanceFrames)::any
end

local function onInstChildRemoved(world: World, entity: InstanceEntity, child: Instance, isAncestryChanged: boolean)
	local components = Manager.Components
	local state = Manager.WidgetState

	if isAncestryChanged and world:has(entity, components.AncestryLocked) then return false end
	local frame = world:get(entity, components.Frame)

	profilebegin("Manager::onInstChildRemoved")
	if frame then
		local main = frame.Instance:FindFirstChild("Main")
		if main and not world:has(entity, components.ArrowInvisible) then
			main.Arrow.Visible = getChildAmount(entity) > 0
		end
	end

	local childEntity = instanceToEntity[child]
	if not childEntity then
		profileend()
		return false
	end

	local newParent = child.Parent
	if not newParent then
		profileend()
		return false
	end

	local newParentEntity = instanceToEntity[newParent]
	if not newParentEntity then
		profileend()
		return false
	end

	--cascadeUpdateExpandedHeights(world, childEntity)
	local parent = parent_of(childEntity)
	if parent then
		world:remove(childEntity, ChildOf(parent))
	end
	world:add(childEntity, ChildOf(newParentEntity))

	local frame = world:get(childEntity, components.Frame)
	if frame then 
		frame:Assign(childEntity, newParentEntity)
	end
	updateEntityOrder(world, childEntity, newParentEntity)
	--cascadeUpdateExpandedHeights(world, childEntity)

	profileend()
	return true
end

local function onInstChildAdded(world: World, entity: InstanceEntity, child: Instance, isAncestryChanged: boolean)
	local components = Manager.Components
	local state = Manager.WidgetState

	if isAncestryChanged and world:has(entity, components.AncestryLocked) then
		return false
	end

	profilebegin("Manager::onInstChildAdded")

	local frame = world:get(entity, components.Frame)
	if frame then 
		local main = frame.Instance:FindFirstChild("Main")
		if main then
			-- If a child is added, the entity always has atleast 1 child so just set to true always
			--main.Arrow.Visible = #instance:GetChildren() > 0
			main.Arrow.Visible = true
		end
	end

	local ancestryChanged = false
	-- Check if a frame already exists for this child (reuse case)
	local existingChildEntity = instanceToEntity[child]
	if existingChildEntity and world:contains(existingChildEntity) then
		local parent = parent_of(existingChildEntity)
		if parent::any ~= entity then
			--cascadeUpdateExpandedHeights(world, existingChildEntity)
			if parent then
				world:remove(existingChildEntity, ChildOf(parent))
			end
			world:add(existingChildEntity, ChildOf(entity))
			ancestryChanged = true
		end
		if frame and world:has(entity, components.Expanded) then
			local existingChildFrame = world:get(existingChildEntity, components.Frame)
			if not existingChildFrame then
				local frame = getInstanceFrame()
				world:set(existingChildEntity, components.Frame, frame)
				frame:Assign(existingChildEntity, entity)
			else
				existingChildFrame:Assign(existingChildEntity, entity)
			end
		else
			local childFrame = world:get(existingChildEntity, components.Frame)
			if childFrame then
				childFrame:Reuse()
			end
		end

		updateEntityOrder(world, existingChildEntity, entity)
		--cascadeUpdateExpandedHeights(world, existingChildEntity)
		return ancestryChanged
	end

	local childEntity = Manager.createInstanceEntity(child, entity)
	if not childEntity then 
		profileend()
		return ancestryChanged
	end

	ancestryChanged = true
	createEntityWithChildren(child, childEntity)
	
	if world:has(entity, components.Expanded) then
		local frame = getInstanceFrame()
		world:set(childEntity, components.Frame, frame)
		frame:Assign(childEntity, entity)
	end

	updateEntityOrder(world, childEntity, entity)
	--cascadeUpdateExpandedHeights(world, childEntity)

	profileend()
	return ancestryChanged
end

local function flushOnChildAddedQueue()
	if #onChildAddedQueue == 0 then return false end
	profilebegin("Manager::flushOnChildAddedQueue")

	local state = Manager.WidgetState
	local world = state.World

	local anyChanged = false
	for _, info in onChildAddedQueue do
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
	for _, info in onChildRemovedQueue do
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

function Manager.getEntityAt(x, y, filteredParent)
	local objects = PluginUI.getGuiObjectsAtPosition(Manager.WidgetState.JExplorerUI, x, y)

	-- Dont ask me how this works it just does
	local newParentFrame: typeof(ui.InstanceFrame)?
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

	local entity = instFrame.CurrentEntity
	if not entity then 
		return
	end

	return newParentFrame, entity
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
		-- Realistically never nil
		assert(connections, "This error should never happen, please report it: Parent entity has no connection group")
		parentConnections = connections
	end

	local connections = parentConnections:Extend("Disconnect")
	local className = instance.ClassName

	local entity = createAbstractEntity(instance)
	world:set(entity, components.Connections, connections)
	world:set(entity, components.ParentTabs, {})
	
	if parent then
		world:add(entity, ChildOf(parent))
	end
	
	profilebegin("Manager::createInstanceEntity::getPropertyComponents")
	local appliedTaggedProps = {}
	local props = APIMap[className]
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
	
	table.insert(entityPropAssignQueue, {entity = entity, tags = tags})
	profileend()

	table.insert(state.Entities, entity)
	if not dontSetInInstanceToEntity then
		instanceToEntity[instance] = entity
	end
	
	local handlers = {}
	for _, v in appliedTaggedProps do
		local success, oldValue = pcall(rawindex, instance, v)
		if not success then continue end
		
		local function onChange()
			local frame = world:get(entity, components.Frame)
			if not frame then return end
			
			local value = rawindex(instance, v)
			local oldTag = getTaggedPropertyTag(v, typeof(oldValue) == "EnumItem" and oldValue.Name or tostring(oldValue))
			local newTag = getTaggedPropertyTag(v, typeof(value) == "EnumItem" and value.Name or tostring(value))

			frame.Instance:RemoveTag(oldTag)
			frame.Instance:AddTag(newTag)
			oldValue = value
		end
		handlers[v] = onChange
	end
	
	if instance:IsA("LuaSourceContainer") then
		local src = ScriptEditorService:GetEditorSource(instance)
		VersionControl.createInstanceVersion(instance, "Source", src)
	end

	connections.Items = {
		rawindex(instance, "Changed"):Connect(function(prop: string)
			--VersionControl.onInstancePropChange(instance, prop, rawindex(instance, prop))
			
			if prop == "Name" then
				nameCache[entity] = instance.Name
				local frame = world:get(entity, components.Frame)
				if frame then
					local main = frame.Instance:FindFirstChild("Main")
					if main and main:FindFirstChild("InstanceName") and main.InstanceName.Text ~= instance.Name then
						main.InstanceName.Text = instance.Name
					end
				end
			elseif prop == "ClassName" then
				classNameCache[entity] = instance.ClassName
			end
			local handler = handlers[prop]
			if not handler then return end
			handler()
		end),
		rawindex(instance, "ChildAdded"):Connect(function(child: Instance)
			local childEntity = instanceToEntity[child]
			if childEntity and world:has(childEntity, components.AncestryLocked) then
				return
			end

			local g = child:FindFirstAncestorOfClass("DockWidgetPluginGui")
			if g and widgetIsJexp(g) then
				return
			end
			if child:IsDescendantOf(CoreGui) and child:FindFirstAncestor("DraggerUI") then return end
			
			table.insert(onChildAddedQueue, {parent = entity, child = child})
		end),
		rawindex(instance, "ChildRemoved"):Connect(function(child: Instance)
			local childEntity = instanceToEntity[child]
			if childEntity and world:has(childEntity, components.AncestryLocked) then
				return
			end

			local g = child:FindFirstAncestorOfClass("DockWidgetPluginGui")
			if g and widgetIsJexp(g) then
				return
			end
			if child:IsDescendantOf(CoreGui) and child:FindFirstAncestor("DraggerUI") then return end
			
			-- Handled in game.DescendantRemoving
			if child.Parent == nil then
				return
			end

			table.insert(onChildRemovedQueue, {parent = entity, child = child})
		end)
	}
	profileend()

	return entity
end

function Manager.registerTab(name, stored, createDeleteButton, registerIntoTabs)
	local state = Manager.WidgetState
	local jexplorerUi = state.JExplorerUI
	local topbar = jexplorerUi.Topbar

	local components = Manager.Components
	local world = state.World
	local connections = state.Connections
	local tabConnections = connections:Extend("Disconnect")

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

				frame:Reuse()
			end
		end
		tabFrame:RemoveTag("JEXP_LightBackground")
		tabFrame:AddTag("JEXP_DarkerBackground")
		currentlyOpenTab = tab

		for _, entity in stored do
			world:remove(entity, components.Invisible)
			world:add(entity, components.DisplayTopLevel)
			--updateEntityOrder(world, entity, nil)
		end

		task.wait(0.1)
		state.HierarchyVersion += 1
		updateVirtualScroller()
	end

	function tab.Remove()
		tabConnections:Free()
		for _, v in stored do
			local parentTabs = world:get(v, components.ParentTabs)
			assert(parentTabs)
			parentTabs[tab] = nil
		end
		table.clear(stored)
		tabFrameToTab[tabFrame] = nil
		tabFrame:Destroy()

		if currentlyOpenTab == tab then
			if tabInsertListener then
				tabInsertListener:Disconnect()
				tabInsertListener = nil
				isCurrentlyPickingTabRoots = false
			end
			for entity in world:query(components.Instance):without(ChildOf(Jecs.Wildcard)):iter() do
				world:add(entity, components.Invisible)
				world:remove(entity, components.DisplayTopLevel)
			end
			for entity in world:query(components.DisplayTopLevel):iter() do
				world:remove(entity, components.DisplayTopLevel)
			end

			currentlyOpenTab = nil
			allTab.Toggle()
		end
	end

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

	if createDeleteButton then
		local deleteButton = PluginUI.createDeleteButton(button, tab.Remove)
		tab.RemoveButton = deleteButton

		deleteButton.Name = "Delete"
		deleteButton.Position = UDim2.new(1, -2, 0.5, 0)
		deleteButton.Size = UDim2.fromOffset(16, 16)
		deleteButton.AnchorPoint = Vector2.new(1, 0.5)
	end

	tabConnections.Items = {
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
			Manager.ContextMenus.Tab.Menu:ShowAsync()
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
	}

	return tab
end

function Manager.createContextMenu(id, actions)
	local menu = plugin:CreatePluginMenu(id)
	local pluginActions = {}

	for _, name: any in actions do
		if name == "---" then
			menu:AddSeparator()
			continue
		end

		local pluginAction = Manager.PluginActions[name]
		assert(pluginAction, `PluginAction '{name}' not found for context menu creation`)

		menu:AddAction(pluginAction)
		table.insert(pluginActions, pluginAction)
	end

	return table.freeze {
		Actions = pluginActions,
		Menu = menu,
		Id = id
	}
end

function Manager.replaceContextMenu(name, newActions)
	local menu = Manager.ContextMenus[name]
	assert(menu, `ContextMenu '{name}' not found`)

	Manager.ContextMenus[name] = Manager.createContextMenu(menu.Id, newActions)
end

function Manager.init(onClose, pluginVersion, connections)
	local instances = connections:Extend("Destroy")
	local pluginToolbar = plugin:CreateToolbar("athar_adv's tools")

	local uiToggleButton = pluginToolbar:CreateButton(
		getId("ToggleUI"), "Toggle the explorer widget visibility",
		"rbxassetid://112696382020883", "Jexplorer"
	)
	uiToggleButton.ClickableWhenViewportHidden = true
	local jexplorerWidget = plugin:CreateDockWidgetPluginGui(
		getId("Jexplorer"), DockWidgetPluginGuiInfo.new(
			Enum.InitialDockState.Left,
			false,
			false
		)
	)
	jexplorerWidget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	jexplorerWidget.Title = `Jexplorer [{pluginVersion}]`
	jexplorerWidget.Name = "Jexplorer"

	jexplorerWidget:BindToClose(function()
		uiToggleButton:SetActive(false)
		jexplorerWidget.Enabled = not jexplorerWidget.Enabled
	end)

	uiToggleButton.Click:Connect(function()
		jexplorerWidget.Enabled = not jexplorerWidget.Enabled
	end)

	local jexplorerUi = ui.JExplorerUi:Clone()

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

	Manager.Toolbar = pluginToolbar
	Manager.WidgetState = {
		World = world,
		QueryWorld = queryWorld,
		Connections = connections,
		Widget = jexplorerWidget,
		Entities = {},
		Tabs = currentTabs,
		CurrentSelection = {},
		Favorited = {},
		HierarchyVersion = 0,
		JExplorerUI = jexplorerUi,
	}
	Manager.AbstractEntClasses = {
		Favorited = "JEXP_ABSTRACT_Favorited"
	}

	local state = Manager.WidgetState
	local components = Manager.Components
	local topbar = jexplorerUi.Topbar

	local queryInput = topbar.QueryInput
	local selectQueried = queryInput.SelectQueried

	selectedQuery = world:query(components.Instance, components.Selected):cached()
	notSelectedQuery = world:query(components.Frame):without(components.Selected):cached()
	withoutIsQueried = world:query(components.Instance):without(components.IsQueried):cached()

	local cachedMap = plugin:GetSetting("APIMap")
	local ver = plugin:GetSetting("APIMapVersion")
	if not cachedMap or ver ~= API_MAP_VERSION then
		local map = BuildAPIMap()
		APIMap = map
		local success, encoded, msg = Converter.serialize(API_MAP_SCHEMA, map::any)
		assert(success, msg)
		
		local str = HttpService:JSONEncode(encoded)
		plugin:SetSetting("APIMap", str)
	else
		local success, map, msg = Converter.deserialize(API_MAP_SCHEMA, HttpService:JSONDecode(cachedMap))
		assert(success and map, msg)
		APIMap = map
	end
	plugin:SetSetting("APIMapVersion", API_MAP_VERSION)
	Manager.APIMap = APIMap

	JState.init(Manager)

	local loadedState = JState.load()
	OrderEditor.ClassPriorities = loadedState.Order.ClassPriorities
	OrderEditor.DefaultPriority = loadedState.Order.DefaultPriority
	InstanceVisibilityEditor.InvisibleClasses = loadedState.InvisibleClasses

	local sheet = loadedState.Style
	Manager.Style = sheet
	sheet.Sheet.Parent = jexplorerWidget

	--sheet:SetToken("QueryInputTextSize", jexplorerUi.Topbar.QueryInput.AbsoluteSize.Y - 1, true)
	sheet:Link(jexplorerUi)

	SettingEditor.Configs = {}
	for name, value in loadedState.Settings do
		Manager.setSetting(name, value)
	end

	if IS_EDIT then
		StyleEditor.init(Manager)
	end
	SettingEditor.init(Manager)
	if IS_EDIT then
		OrderEditor.init(Manager)
		VersionControl.init(Manager)
		InstanceVisibilityEditor.init(Manager)
		PropertyEditor.init(Manager)
	end
	--ContextMenuEditor.init(Manager)

	shared.Jexplorer.__modify:Fire()

	local favoritedInstancesEntity do
		favoritedInstancesEntity = createAbstractEntity {
			ClassName = Manager.AbstractEntClasses.Favorited,
			Name = "Favorites",
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
		}
		classNameCache[favoritedInstancesEntity] = Manager.AbstractEntClasses.Favorited
		nameCache[favoritedInstancesEntity] = "Favorites"
		childAmountCache[favoritedInstancesEntity] = 0
		ClassIcon.CachedIcons[Manager.AbstractEntClasses.Favorited] = {
			Image = "rbxassetid://12982756171",
			ImageRectOffset = Vector2.zero,
			ImageRectSize = Vector2.zero
		}
		table.insert(state.Entities, favoritedInstancesEntity)
		
		local instConnections = connections:Extend("Disconnect")
		world:set(favoritedInstancesEntity, components.Connections, instConnections)
		
		componentMap.Name = world:entity()
		componentMap.ClassName = world:entity()
		local queryEntity = queryWorld:entity()
		queryWorld:set(queryEntity, components.QueryLinkedEntities, {
			favoritedInstancesEntity
		})
		queryWorld:add(queryEntity, componentMap.Name)
		queryWorld:add(queryEntity, componentMap.ClassName)
		
		world:set(favoritedInstancesEntity, components.LinkedQueryEntity, queryEntity)
	end

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
				JState.save()
				topbarMenuDropdown:Hide()
			end)
			PluginUI.createButton(topbarMenuDropdown, "Reset State to Default", function()
				topbarMenuDropdown:Hide()

				local loadedState = JState.getDefaultState()
				Manager.Style:Replace(loadedState.Style)
				Manager.Style = loadedState.Style

				for name, value in loadedState.Settings do
					Manager.setSetting(name, value)
				end

				OrderEditor.ClassPriorities = loadedState.Order.ClassPriorities
				OrderEditor.DefaultPriority = loadedState.Order.DefaultPriority
				InstanceVisibilityEditor.InvisibleClasses = loadedState.InvisibleClasses
				for _, tab in state.Tabs do
					tab.Remove()
				end
				table.clear(state.Tabs)

				state.HierarchyVersion += 1
				updateVirtualScroller()
			end)
			PluginUI.createButton(topbarMenuDropdown, "Reset Styles to Default", function()
				topbarMenuDropdown:Hide()

				local default = JState.getDefaultStyle()
				Manager.Style:Replace(default)
				Manager.Style = default
				updateVirtualScroller()
			end)
			PluginUI.createButton(topbarMenuDropdown, "Reset Settings to Default", function()
				topbarMenuDropdown:Hide()

				local loadedState = JState.getDefaultState()
				for name, value in loadedState.Settings do
					Manager.setSetting(name, value)
				end

				updateVirtualScroller()
			end)
			PluginUI.createButton(topbarMenuDropdown, "Reset Order to Default", function()
				topbarMenuDropdown:Hide()

				local loadedState = JState.getDefaultState()

				OrderEditor.ClassPriorities = loadedState.Order.ClassPriorities
				OrderEditor.DefaultPriority = loadedState.Order.DefaultPriority

				state.HierarchyVersion += 1
				updateVirtualScroller()
			end)
			PluginUI.createSeparator(topbarMenuDropdown)
			PluginUI.createButton(topbarMenuDropdown, "Kill Jexplorer", function()
				onClose()
			end)
		end
		topbarMenuDropdown.Backdrop.MouseLeave:Connect(function()
			topbarMenuDropdown:Hide()
		end)
		topbarMenuDropdown.Backdrop.Parent = topbar
	end

	local editName do
		editName = plugin:CreatePluginAction(
			getId("EditName", true), "Edit Name", "Edits the name of a tab."
		)

		editName.Triggered:Connect(function()
			if not targetTab then return end

			local box: TextBox = targetTab.NameBox
			box:CaptureFocus()
		end)
	end

	local tabBar = topbar.TabBar

	do
		local insertButton = PluginUI.createInsertButton(tabBar.Tabs, function()
			Manager.registerTab("Tab", {}, true, true)
		end)

		insertButton.LayoutOrder = math.huge
	end

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
			
			local info: typeof(((nil :: any) :: typeof(INSTANCE_INSERT_INFO))[""])?
			for k, v in INSTANCE_INSERT_INFO do
				if inst:IsA(k) then info = v break end
			end
			if info then
				for k, v in info.Props do
					pcall(rawnewindex, inst, k, v)
				end
				if info.SideEffect then
					info.SideEffect(inst)
				end
			end
			
			inst.Parent = entityInst

			if not world:has(entity, components.Expanded) then
				toggleExpand(world, entity, true, true)
			end

			table.insert(onChildAddedQueue, {parent = entity, child = inst})

			if id then
				ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
			end
		end

		local layoutOrder = 0
		for category, tbl in require(script.InstanceCategories) do
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

		connections:Insert {
			Manager.connectInputBegan(onInputBegan),
			searchbar.FocusLost:Connect(function(_, input)
				onInputBegan(input)
			end),
			searchbar.InputBegan:Connect(onInputBegan)
		}
		insertInstanceList.Backdrop.Parent = jexplorerUi
	end

	local renameAction do
		renameAction = plugin:CreatePluginAction(
			getId("Jexplorer_ContextMenu_Rename", true), "Rename Instance", "Rename selected instance."
		) :: PluginAction
		renameAction.Triggered:Connect(function()
			for _, entity in state.CurrentSelection do
				local frame = world:get(entity, components.Frame)
				if not frame then return end
				local n = frame.Instance.Main.InstanceName

				n.TextEditable = true
				n.Interactable = true
				n:CaptureFocus()
			end
		end)
	end

	local insertFromFileAction do
		insertFromFileAction = plugin:CreatePluginAction(
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

				table.insert(onChildAddedQueue, {parent = entity, child = v})
			end

			state.HierarchyVersion += 1
			updateVirtualScroller()

			if id then
				ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
			end
		end)
	end

	local insertObjectAction do
		insertObjectAction = plugin:CreatePluginAction(
			getId("Jexplorer_ContextMenu_InsertObject", true), "Insert Object...", "Inserts a chosen Instance into an Instance.", (ClassIcon.getIcon("Part")::any).Image
		)
		insertObjectAction.Triggered:Connect(function()
			local mousePos = state.Widget:GetRelativeMousePosition()
			showInsertInstanceMenu(mousePos, Vector2.zero)
		end)
	end

	local selectChildrenAction do
		selectChildrenAction = plugin:CreatePluginAction(
			getId("Jexplorer_ContextMenu_SelectChildren", true), "Select Children", "Selects all children of an Instance."
		)
		selectChildrenAction.Triggered:Connect(function()
			for _, target in state.CurrentSelection do
				local children = {}
				for child in childrenOf(world, target):iter() do
					table.insert(children, child)
				end

				if not world:has(target, components.Expanded) then
					toggleExpand(world, target, true, true)
				end
				addEntitiesToSelection(world, children)
			end
		end)
	end

	local saveToFileAction do
		saveToFileAction = plugin:CreatePluginAction(
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
		saveToRobloxAction = plugin:CreatePluginAction(
			getId("Jexplorer_ContextMenu_SaveToRoblox", true), "Save to Roblox...", "Saves an Instance to Roblox."
		)
		saveToRobloxAction.Triggered:Connect(function()
			setSelection(world, state.CurrentSelection, true)
			plugin:SaveSelectedToRoblox()
		end)
	end

	local copyAction do
		copyAction = plugin:CreatePluginAction(
			getId("Jexplorer_ContextMenu_Copy", true), "Copy", "Copies all Instances to your clipboard."
		)
		copyAction.Triggered:Connect(function()
			copySelection(world)
		end)
	end

	local pasteIntoAction do
		pasteIntoAction = plugin:CreatePluginAction(
			getId("Jexplorer_ContextMenu_PasteInto", true), "Paste Into", "Pastes all copied Instances into the first currently selected Instance."
		)
		pasteIntoAction.Triggered:Connect(function()
			pasteCopiedInstances(world)
		end)
	end

	local collapseAllAction do
		collapseAllAction = plugin:CreatePluginAction(
			getId("Jexplorer_ContextMenu_CollapseAll", true), "Collapse All", "Collapses all expanded descendants."
		)
		collapseAllAction.Triggered:Connect(function()
			for _, entity in state.CurrentSelection do
				local inst = world:get(entity, components.Instance)
				if not inst then return end

				for _, v in inst:GetDescendants() do
					local child = instanceToEntity[v]
					if not child then continue end

					world:remove(child, components.Expanded)
				end
				toggleExpand(world, entity, false, false)
			end
			updateVirtualScroller()
		end)
	end

	local toggleFavoriteAction do
		toggleFavoriteAction = plugin:CreatePluginAction(
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
						local frame = getInstanceFrame()
						world:set(proxy, components.Frame, frame)
						frame:Assign(proxy, favoritedInstancesEntity)
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
		hideClassAction = plugin:CreatePluginAction(
			getId("Jexplorer_ContextMenu_HideClass", true), "Hide Class", "Hides all Instances with the ClassName of the selected Instance."
		)
		hideClassAction.Triggered:Connect(function()
			for _, v in state.CurrentSelection do
				local className = classNameCache[v]
				if not className then continue end

				InstanceVisibilityEditor.setVisible(className, false)
				updateVirtualScroller()
			end
		end)
	end

	local deleteAction do
		deleteAction = plugin:CreatePluginAction(
			getId("Jexplorer_ContextMenu_Delete", true), "Delete", "Deletes this Instance."
		)
		deleteAction.Triggered:Connect(function()
			local id = ChangeHistoryService:TryBeginRecording("Delete", "Delete")
			for _, v in state.CurrentSelection do
				local inst = world:get(v, components.Instance)
				if not inst then continue end

				local success = pcall(function()
					inst.Parent = nil
				end)
			end
			if id then
				ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
			end
		end)
	end

	local openVersionHistoryAction do
		openVersionHistoryAction = plugin:CreatePluginAction(
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
		appendAction = plugin:CreatePluginAction(
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
		commitAction = plugin:CreatePluginAction(
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
		removeFromTabAction = plugin:CreatePluginAction(
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
				if frame then frame:Reuse() end
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
			for _, ent in state.CurrentSelection do
				local inst = world:get(ent, components.Instance)
				if not inst then continue end

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

			local id = ChangeHistoryService:TryBeginRecording("GroupAsFolder", "Group As Folder")

			local container = Instance.new(className)
			container.Parent = targetParent

			local containerEntity = Manager.getOrCreateInstanceEntity(container, targetParentEnt)

			assert(containerEntity)
			world:add(containerEntity, components.AncestryLocked)

			for _, ent in pathMap do
				world:add(ent, components.AncestryLocked)
			end

			for _, ent in pathMap do
				local inst = world:get(ent, components.Instance)
				if not inst then continue end

				local parent = parent_of(ent)
				if not parent then continue end

				world:remove(ent, ChildOf(parent))
				world:add(ent, ChildOf(containerEntity))

				pcall(rawnewindex, inst, "Parent", container)

				local frame = world:get(ent, components.Frame)
				if frame then
					frame:Reuse()
				end
			end

			for _, ent in pathMap do
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
		groupAsFolderAction = plugin:CreatePluginAction(
			getId("Jexplorer_ContextMenu_GroupAsFolder", true), "Group as Folder", "Groups the selected Instances inside 1 Folder."
		)
		groupAsModelAction = plugin:CreatePluginAction(
			getId("Jexplorer_ContextMenu_GroupAsModel", true), "Group as Model", "Groups the selected Instances inside 1 Model."
		)
		groupAsFolderAction.Triggered:Connect(function()
			groupAs("Folder")
		end)
		groupAsModelAction.Triggered:Connect(function()
			groupAs("Model")
		end)
	end

	Manager.PluginActions = {
		OpenVersionHistory = openVersionHistoryAction,
		Append = appendAction,
		Commit = commitAction,

		Copy = copyAction,
		PasteInto = pasteIntoAction,
		Delete = deleteAction,
		Rename = renameAction,

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

		Tab_EditName = editName
	}

	local instanceContextMenu = Manager.createContextMenu(
		getId("Jexplorer_InstanceContextMenu", true),
		{
			"OpenVersionHistory",
			"Append",
			"Commit",

			"---",

			"Copy",
			"PasteInto",
			"Delete",
			"Rename",

			"---",

			"GroupAsFolder",
			"GroupAsModel",
			"HideClass",

			"---",

			"SelectChildren",
			"CollapseAll",

			"---",

			"InsertFromFile",
			"InsertObject",

			"---",

			"SaveToFile",
			"SaveToRoblox",

			"---",

			"ToggleFavorite",
			"RemoveFromTab"
		}
	)

	local serviceContextMenu = Manager.createContextMenu(
		getId("Jexplorer_ServiceContextMenu", true),
		{

		}
	)

	local tabMenu = Manager.createContextMenu(
		getId("Jexplorer_TabContextMenu", true),
		{
			"Tab_EditName"
		}
	)

	Manager.ItemLists = {
		InsertInstance = insertInstanceList
	}
	Manager.ContextMenus = {
		Instance = instanceContextMenu,
		Service = serviceContextMenu,
		Tab = tabMenu
	}

	if IS_EDIT then
		ContextMenuEditor.init(Manager)
	end

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

	instances:Insert {
		function()
			for _, v in widgets do
				v.Enabled = false
			end
			for _, v in Manager.PluginActions do
				v:Destroy()
			end
		end,

		instanceContextMenu.Menu,
		serviceContextMenu.Menu,

		pluginToolbar,
		uiToggleButton,
	}

	local scrollTrackerConnection, scrollTrackerThread = trackScrolling()
	local instanceTree = jexplorerUi.InstanceTree
	instTreeAbsoluteSizeY = instanceTree.AbsoluteSize.Y

	local allTags: {string} = CollectionService:GetAllTags()
	local tagAddedSignals = {}
	local tagRemovedSignals = {}
	local function onTag(tag: string)
		if tag:match("JEXP_TAGGED") then return end

		local tagComponent = tagMap[tag] or queryWorld:entity()
		tagMap[tag] = tagComponent

		local function onAdded(inst: Instance)
			local listener = onTagAddedListeners[inst]
			if listener then listener(tag) end

			local entity = instanceToEntity[inst]
			if not entity then return end

			deregisterFromQueryWorld(world, queryWorld, entity)
			registerToQueryWorld(world, queryWorld, entity, classNameCache[entity])

			local frame = world:get(entity, components.Frame)
			if not frame then return end

			local tag = `JEXP_TAG_{tag}`
			table.insert(frame.TagsToRemove, tag)
			frame.Instance:AddTag(tag)
		end

		for _, v in CollectionService:GetTagged(tag) do
			onAdded(v)
		end
		tagAddedSignals[tag] = CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst: Instance)
			onAdded(inst)
		end)
		tagRemovedSignals[tag] = CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst: Instance)
			local listener = onTagRemovedListeners[inst]
			if listener then listener(tag) end

			local entity = instanceToEntity[inst]
			if not entity then return end

			deregisterFromQueryWorld(world, queryWorld, entity)
			registerToQueryWorld(world, queryWorld, entity, classNameCache[entity])

			local frame = world:get(entity, components.Frame)
			if not frame then return end

			local tag = `JEXP_TAG_{tag}`
			local idx = table.find(frame.TagsToRemove, tag)
			if not idx then return end

			frame.Instance:RemoveTag(tag)
			table.remove(frame.TagsToRemove, idx)
		end)
	end

	for _, tag in allTags do
		onTag(tag)
	end

	--ScriptEditorService:RegisterScriptAnalysisCallback("JEXP_diagnostics_listener", 0, function(request, response: any)
	--	local response = response or {diagnostics = {}}

	--	local inst: LuaSourceContainer? = request.script
	--	if not inst then return response end

	--	local scriptEntity = instanceToEntity[inst]
	--	if not scriptEntity then return response end

	--	local fn, err = 

	--	-- Errors take display priority over warns
	--	local errors, warns = {}, {}

	--	world:set(scriptEntity, components.ScriptWarns, warns)
	--	world:set(scriptEntity, components.ScriptErrors, errors)

	--	local frame = world:get(scriptEntity, components.Frame)
	--	if not frame then return response end

	--	if #errors == 0 and #warns == 0 then
	--		frame.Instance:RemoveTag("JEXP_ScriptError")
	--		frame.Instance:RemoveTag("JEXP_ScriptWarn")
	--		return response
	--	end

	--	if #errors > 0 then
	--		local last = table.remove(errors)
	--		if not table.find(frame.TagsToRemove, "JEXP_ScriptError") then
	--			frame.Instance:AddTag("JEXP_ScriptError")
	--			table.insert(frame.TagsToRemove, "JEXP_ScriptError")
	--		end
	--		return response
	--	end
	--	local last = table.remove(warns)
	--	if not table.find(frame.TagsToRemove, "JEXP_ScriptWarn") then
	--		frame.Instance:AddTag("JEXP_ScriptWarn")
	--		table.insert(frame.TagsToRemove, "JEXP_ScriptWarn")
	--	end

	--	return response
	--end)

	-->> Initialize entities
	local entities = {favoritedInstancesEntity}
	-- Initialize services
	for _, service in game:GetChildren() do
		-- Prevent a specific FilteredSelection instance with no classname from showing up
		if not service.ClassName:match("%w+") then continue end

		local entity = Manager.getOrCreateInstanceEntity(service)
		if not entity then continue end
		table.insert(entities, entity)
	end

	profilebegin("Manager::initEntities")
	for _, entity in entities do
		local inst = world:get(entity, components.Instance)
		if not inst then continue end

		createEntityWithChildren(inst,entity)
	end
	flushEntityPropAssignQueue()

	for _, entity in entities do
		local frame = getInstanceFrame()
		frame:Assign(entity)
		world:set(entity, components.Frame, frame)
	end
	flushTagAssignQueue()
	profileend()

	jexplorerUi.Parent = jexplorerWidget

	allTab = Manager.registerTab("All", entities, false, false)
	-- Wait until robloxs scrollingframe update
	task.delay(1.5, allTab.Toggle)

	for _, tabInfo in loadedState.Tabs do
		local ents = {}
		for _, id in tabInfo.ids do
			local inst = Manager.getInstFromId(id)
			if not inst then continue end

			local ent = instanceToEntity[inst]
			if not ent then continue end
			table.insert(ents, ent)
		end
		Manager.registerTab(tabInfo.name, ents, true, true)
	end

	-->> Initialize connections
	local pathClickConnection: RBXScriptConnection?
	connections:Insert {
		function()
			for _, v in tagRemovedSignals do
				v:Disconnect()
			end
			for _, v in tagAddedSignals do
				v:Disconnect()
			end

			--ScriptEditorService:DeregisterScriptAnalysisCallback("JEXP_diagnostics_listener")
		end,
		CollectionService.TagAdded:Connect(function(tag)
			onTag(tag)
		end),
		--TODO: This serves as a reminder that the most benign things can break your entire plugin
		-- THIS THING WAS BREAKING QUERIES AND LITERALLY EVERYTHING AND I ONLY SOLVED IT BY DIFFING 2 FILES
		-- OH MY GOD I HATE THIS CONNECTION

		--CollectionService.TagRemoved:Connect(function(tag)
		--	local comp = tagMap[tag]
		--	if not comp then return end

		--	world:delete(comp)
		--	tagMap[tag] = nil

		--	local added, removed = tagAddedSignals[tag], tagRemovedSignals[tag]
		--	if not added or not removed then return end

		--	added:Disconnect()
		--	removed:Disconnect()
		--	tagAddedSignals[tag], tagRemovedSignals[tag] = nil, nil
		--end),
		ScriptEditorService.TextDocumentDidChange:Connect(function(document, changes)
			local docScript = document:GetScript()
			if not docScript then return end

			VersionControl.addPendingChange(docScript, "Source", document:GetText())
		end),
		instanceTree:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			instTreeAbsoluteSizeY = instanceTree.AbsoluteSize.Y
		end),
		scrollTrackerConnection,
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

			for _, rule in sheet.Rules do
				local class = rule.Rule.Selector:match("%.JEXP_TAGGED_ClassName_(%w-)[^%w]")
				if not class then continue end

				local icon = ClassIcon.getIcon(class)
				if not icon then return end

				for k: any, v: any in icon do
					rule:SetProperty(k, v)
					--sheet:SetToken(k, v, false)
				end
			end
			--sheet:UpdateTokens()
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
			-- Lock this to prevent interference with .ChildRemoved
			world:add(childEntity, components.AncestryLocked)

			local entity = instanceToEntity[descendant]
			if not entity then
				world:remove(childEntity, components.AncestryLocked)
				return
			end

			cleanupEntity(entity)
			world:remove(childEntity, components.AncestryLocked)
		end),
		Selection.SelectionChanged:Connect(function()
			profilebegin("Manager::onSelectionChanged")
			local selection = Selection:Get()
			local entities = {}
			local n = 0
			for _, v in selection do
				local ent = instanceToEntity[v]
				if not ent then continue end
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
				while current do
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

			if n == 0 then return end
			
			for v in selectedQuery:iter() do
				world:remove(v, components.Selected)
			end
			for _, ent in entities do
				world:add(ent, components.Selected)
			end

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
					end
					if unexpanded then
						toggleExpand(world, unexpanded, true, false)
					end
				end
				profileend()
			end

			-- Jump the canvas position to the middle entity
			local middle = entities[math.max(#entities // 2, 1)]
			local entityIndex = getFlattenedVisibleEntities(world, {})
			local idx = table.find(entityIndex, middle)
			if idx then
				local currentViewportTop = instanceTree.CanvasPosition.Y
				local currentViewportBottom = currentViewportTop + instTreeAbsoluteSizeY

				local size: UDim2 = sheet:GetToken("InstanceFrameSize")

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
				state.CurrentDrag.Connections:Free()
				state.CurrentDrag = nil
			end
			if input.UserInputType ~= Enum.UserInputType.MouseMovement then
				insertInstanceList:Hide()
			end

			-- TODO: Probably should turn stuff like this into PluginActions so they can be rebound, but i cant assign a default shortcut :/
			if input.KeyCode == Enum.KeyCode.Escape or (Manager.isKeyDown(Enum.KeyCode.Backspace) and Manager.isKeyDown(Enum.KeyCode.LeftShift)) then
				profilebegin("Manager::onInput::ESCAPE (unselect all)")
				if state.CurrentlyRenaming then
					local frame = world:get(state.CurrentlyRenaming, components.Frame)
					if not frame then return end
					frame.Instance.Main.InstanceName:ReleaseFocus(false)
					state.CurrentlyRenaming = nil
					return
				end

				for entityId in selectedQuery:iter() do
					world:remove(entityId, components.Selected)
				end

				updateSelectionVisuals(world, true)
				state.LastSelectedEntity = nil
				profileend()
			elseif input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.Delete then
				local id = ChangeHistoryService:TryBeginRecording("Destroy", "Destroy")
				profilebegin("Manager::onInput::BACKSPACE/DELETE (remove)")
				
				local selection = state.CurrentSelection
				for _, entity in selection do
					world:add(entity, components.AncestryLocked)
				end
				for _, entity in selection do
					world:add(entity, components.Deleted)
					local instance = world:get(entity, components.Instance)
					assert(instance)
					
					instance:Destroy()
				end
				for _, entity in selection do
					world:remove(entity, components.AncestryLocked)
				end
				
				cleanupEntities(selection)
				
				state.HierarchyVersion += 1
				updateVirtualScroller()
				
				if id then
					ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
				end

				profileend()
			elseif Manager.isKeyDown(Enum.KeyCode.LeftControl) and Manager.isKeyDown(Enum.KeyCode.D) then
				local id = ChangeHistoryService:TryBeginRecording("Clone", "Clone")
				profilebegin("Manager::onInput::D (duplicate)")

				local cloned = {}
				for _, entity in state.CurrentSelection do
					local parent = parent_of(entity)
					if parent == nil then continue end

					local instance = world:get(entity, components.Instance)
					if not instance then continue end

					local clone = instance:Clone()
					clone.Parent = instance.Parent
				end

				if id then
					ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
				end

				profileend()
			elseif Manager.isKeyDown(Enum.KeyCode.LeftControl) and Manager.isKeyDown(Enum.KeyCode.C) then
				copySelection(world)
			elseif Manager.isKeyDown(Enum.KeyCode.LeftControl) and Manager.isKeyDown(Enum.KeyCode.V) then
				pasteCopiedInstances(world)
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

			-- Update arrow visibility for all entities
			for _, entity in state.Entities do
				local frame = world:get(entity, components.Frame)
				if frame then
					frame.Instance.Main.Arrow.Visible = getChildAmount(entity) > 0
				end
			end

			-- Collapse ancestors from previous queries
			for entity in world:query(components.QueryExpanded):iter() do
				world:remove(entity, components.QueryExpanded)
				world:remove(entity, components.Expanded)
			end
			for entity in world:query(components.QueryAncestor):iter() do
				world:remove(entity, components.QueryAncestor)
				toggleExpand(world, entity, false, false)
			end
			for entity in world:query(components.IsQueried):iter() do
				world:remove(entity, components.ArrowInvisible)
			end

			if queryText == "" then
				queryInput.QueryCount.Text = "0"
				for _, entity in state.Entities do
					world:remove(entity, components.QueryInvisible)
					world:remove(entity, components.IsQueried)
				end
				updateVirtualScroller()
				return
			end

			profilebegin("Manager::query::hideEntities")
			for _, entity in state.Entities do
				world:add(entity, components.QueryInvisible)
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

			if not success or #result == 0 then
				if not success then
					warn("JEXPLORER Query error: " .. tostring(result))
				end
				profilebegin("Manager::query::showEntities")
				for entity in world:query(components.QueryInvisible):iter() do
					world:remove(entity, components.QueryInvisible)
					world:remove(entity, components.IsQueried)
				end
				profileend()
				updateVirtualScroller()
				profileend()
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
			end

			for _, entity in validEntities do
				local parentTree = parentTreesCache[entity]
				if #parentTree > 0 then
					local last = parentTree[#parentTree]
					for i = #parentTree, 2, -1 do
						local parent = parentTree[i]
						world:remove(parent, components.QueryInvisible)
						world:remove(parent, components.ArrowInvisible)
						world:add(parent, components.Expanded)
						world:add(parent, components.QueryExpanded)
					end

					world:add(last, components.QueryAncestor)
					toggleExpand(world, last, true, false)
				end
			end

			profileend()

			-- Small delay to prevent frame drops
			task.wait(1/60) -- Reduced from 1/30 for smoother performance
			updateVirtualScroller()
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

	local function cleanupCycle()
		local suc1 = flushOnChildAddedQueue()
		local suc2 = flushOnChildRemovedQueue()
		local suc3 = cleanupEntities(entityCleanupQueue)

		if suc1 or suc2 or suc3 then
			state.HierarchyVersion += 1
			updateVirtualScroller()
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

	local threads = connections:Extend(task.cancel, {
		scrollTrackerThread,
		task.spawn(loop, CLEANUP_LOOP_INTERVAL, cleanupCycle),
		task.spawn(loop, REUSE_LOOP_INTERVAL, reuseCycle),
		task.spawn(loop, ENT_DELETE_LOOP_INTERVAL, entityDeletionCycle)
	})
end

Manager.getInstanceFrame = getInstanceFrame
function Manager.setInstanceFramePoolTarget(n)
	instanceFramePoolTarget = n
end
Manager.fillInstanceFramePoolToLimit = fillInstanceFramePoolToLimit
Manager.addEntitiesToSelection = addEntitiesToSelection
Manager.updateVirtualScroller = updateVirtualScroller

return Manager