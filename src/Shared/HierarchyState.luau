--!strict
--!optimize 2

local ScriptEditorService = game:GetService("ScriptEditorService")

local Types = require("../Types")
local Jecs = require("../Jecs")
local RawInst = require("./Small/RawInst")
local JexpTags = require("./Small/JexpTags")
local Constants = require("../Constants")

local getClassPropMap = require("./Small/GetClassPropMap")

local ItemGroup = require("./Vendor/ItemGroup")

local OrderEditor = require("../Editors/OrderEditor")
local VersionControl = require("../Editors/VersionControl")

local profilebegin, profileend = debug.profilebegin, debug.profileend
local rbxconnect = RawInst.rbxconnect
local getpropertychangedsignal = RawInst.getpropertychangedsignal
local getattributes = game.GetAttributes
local rawindex = RawInst.rawindex
local index = RawInst.index
local bulkinsert = Jecs.bulk_insert
local pair = Jecs.pair
local childof = Jecs.ChildOf
local getchildren = game.GetChildren

local match = string.match

local move = table.move
local sort = table.sort
local concat = table.concat
local clear = table.clear
local insert = table.insert
local clone = table.clone

type Manager = Types.Manager
type ExplorerEntity = Types.ExplorerEntity
type World = Types.World

local hierarchyCache = {
	childrenMap = {} :: {[ExplorerEntity]: {ExplorerEntity}},
	roots = {} :: {ExplorerEntity},
}
local classPriorityCache = {}
--local lastCacheVersion = -1
local lastPriorityVersion = -1
local SUFFIX_PATTERN = "(%d+)$"

local flatCache = {
	flattenedEntities = nil :: any,
	entityToIndex = nil :: any,
	indexToIndentOffset = nil :: any,
	version = 0
}

local entityStateCache = {}

local function getClassPriority(className: string): number
	profilebegin("Jexplorer::getClassPriorityUncached")
	local priority = table.find(OrderEditor.ClassPriorities, className) or OrderEditor.DefaultPriority
	classPriorityCache[className] = priority
	profileend()
	return priority
end

local function addEntityPriorities(Manager: Manager, children: {ExplorerEntity}, priorities: any)
	profilebegin("Jexplorer::getEntityPriorities")
	local components = Manager.Components
	local state = Manager.WidgetState
	local world = state.World
	
	if OrderEditor.PriorityVersion and OrderEditor.PriorityVersion ~= lastPriorityVersion then
		table.clear(classPriorityCache)
		lastPriorityVersion = OrderEditor.PriorityVersion
	end

	profilebegin("Jexplorer::getEntityPriorities::collectEntityPriority")
	profilebegin("Jexplorer::getEntityPriorities::collectEntityPriority::loop1")
	local n = 0
	for i, child in children do
		n += 1
		local classname = Manager.ClassNameCache[child]
		if classname then
			priorities[child] = classPriorityCache[classname] or getClassPriority(classname)
		end
	end
	profileend()
	profilebegin("Jexplorer::getEntityPriorities::collectEntityPriority::loop2")
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

local HierarchyState = {
	StateCache = entityStateCache,
	ChildrenMap = hierarchyCache.childrenMap
} :: Types.HierarchyState

function HierarchyState.cleanupEntity(Manager, ent)
	local state = Manager.WidgetState
	local world, components = state.World, Manager.Components
	world:add(ent, components.Deleted)

	HierarchyState.queueForEntityCleanup(Manager, ent)
	
	local idx = table.find(state.Entities, ent)
	if idx then table.remove(state.Entities, idx) end
	
	local function addchildren(entity: ExplorerEntity)
		for _, v in HierarchyState.getChildren(entity) do
			HierarchyState.cleanupEntity(Manager, v)
			addchildren(v)
		end
	end
	addchildren(ent)
	
	Manager.DeferredTaskScheduler.EntityCleanupQueuePending = true
end

function HierarchyState.rebuildHierarchyCache(Manager)
	local state = Manager.WidgetState
	local components = Manager.Components
	local world = state.World

	local roots, childrenMap = {}, {}

	profilebegin("Jexplorer::rebuildHierarchyCache")
	profilebegin("Jexplorer::rebuildHierarchyCache::buildChildrenMap")

	for _, eid in state.Entities do
		if Manager.isExplorerEntityDeleted(eid) then
			continue
		end
		
		HierarchyState.invalidateEntityStateCache(eid)
		local parent = Manager.parentOf(eid)
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
	profilebegin("Jexplorer::rebuildHierarchyCache::collectPriorities")

	local tosort = {roots}

	local mergedPriorities = {}
	addEntityPriorities(Manager, roots, mergedPriorities)
	for parent, children in childrenMap do
		addEntityPriorities(Manager, children, mergedPriorities)
	end

	for parent, children in childrenMap do
		table.insert(tosort, children)
	end

	profileend()
	profilebegin("sort")
	
	local nameCache = Manager.NameCache
	local function sort(a, b)
		local priorityA = mergedPriorities[a]
		local priorityB = mergedPriorities[b]
		if priorityA ~= priorityB then
			return priorityA < priorityB
		end
		local nameA = nameCache[a]
		local nameB = nameCache[b]
		
		local numA = match(nameA, SUFFIX_PATTERN)
		local numB = match(nameB, SUFFIX_PATTERN)
		
		if numA and numB then
			return tonumber(numA) < tonumber(numB)
		end
		return nameA < nameB
	end

	-- Sort all at once for best performance
	for _, v in tosort do
		table.sort(v, sort)
	end

	profileend()

	hierarchyCache.childrenMap = childrenMap
	hierarchyCache.roots = roots
	HierarchyState.ChildrenMap = childrenMap
	
	profileend()
	return childrenMap, roots
end

function HierarchyState.getFlattenedVisibleEntities(Manager, invisible, isScroller)
	profilebegin("Jexplorer::getFlattenedVisibleEntities")

	-- Return cached result if valid
	if flatCache.flattenedEntities then
		profileend()
		return flatCache.flattenedEntities, flatCache.entityToIndex, flatCache.indexToIndentOffset
	end

	local state = Manager.WidgetState
	local components = Manager.Components
	local childrenMap = hierarchyCache.childrenMap
	local roots = hierarchyCache.roots
	local world = state.World

	local flatList = table.create(1000) -- Pre-allocate larger
	local indexToIndentOffset = table.create(1000)
	local entityToIndex = {}
	local flatIndex = 0

	local stack = table.create(500)
	local stackSize = 0
	local indentStack = table.create(500)

	-- flatCache function references (avoid lookups)
	local entityinvisible = Manager.isExplorerEntityInvisible
	local entitydeleted = Manager.isExplorerEntityDeleted
	local entityexpanded = Manager.isExplorerEntityExpanded

	profilebegin("traverse")

	-- Push roots onto stack
	local rootCount = #roots
	for i = rootCount, 1, -1 do
		stackSize += 1
		stack[stackSize] = roots[i]
		indentStack[stackSize] = 0
	end

	while stackSize > 0 do
		local entity = stack[stackSize]
		local currentIndent = indentStack[stackSize]
		stackSize -= 1

		-- Get cached state
		local state = entityStateCache[entity]
		if not state then
			profilebegin("generateentitystate")
			local invisible = entityinvisible(entity) or entitydeleted(entity)
			local expanded = entityexpanded(entity)
			state = {invisible = invisible, expanded = expanded, isTopLevel = world:has(entity, components.DisplayTopLevel)}
			entityStateCache[entity] = state
			profileend()
		end

		if not state.invisible then -- Skip invisible entirely
			flatIndex += 1
			flatList[flatIndex] = entity
			indexToIndentOffset[flatIndex] = currentIndent
			entityToIndex[entity] = flatIndex -- Build inline

			if state.expanded then
				local children = childrenMap[entity]
				if children then
					local childCount = #children
					if childCount > 0 then
						local childIndent = currentIndent + 1
						-- Push in reverse order for correct traversal
						for i = childCount, 1, -1 do
							stackSize += 1
							stack[stackSize] = children[i]
							indentStack[stackSize] = childIndent
						end
					end
				end
			end
		end
	end

	profileend()
	
	flatCache.flattenedEntities = flatList
	flatCache.entityToIndex = entityToIndex
	flatCache.indexToIndentOffset = indexToIndentOffset

	profileend()
	return flatList, entityToIndex, indexToIndentOffset
end

function HierarchyState.flushEntityCreationQueue(Manager)
	local state = Manager.WidgetState
	local world = state.World
	local components = Manager.Components
	
	local query = Jecs.cached_query(world, components.CreationTicket)
	
	local any = false
	local anyEntities = false
	for parent, ticketData in query:iter() do
		any = true
		world:remove(parent, components.CreationTicket)
		
		for _, child in ticketData.children do
			if Manager.isInstanceExcluded(child) then continue end
			if Manager.InstanceToEntity[child] then continue end
			anyEntities = true

			HierarchyState.createInstanceEntity(Manager, child, parent)
		end
	end
	if not any then return false end
	
	if anyEntities then
		Manager.DeferredTaskScheduler.EntityCreationQueuePending = true
	end
	
	return true
end

function HierarchyState.queueForEntityCreation(Manager, parent, children)
	local state = Manager.WidgetState
	local components = Manager.Components
	local world = state.World
	
	world:set(parent, components.CreationTicket, {children = children})
end

function HierarchyState.flushEntityCleanupQueue(Manager)
	profilebegin("Jexplorer::cleanupEntitiesInTable")

	local state = Manager.WidgetState
	local world = state.World
	local queryWorld = state.QueryWorld
	local components = Manager.Components

	local groupsToFree = {}
	local entityIndexesToRemove = {}
	local seen = {}
	local any = false

	local entities = state.Entities
	local entitiesWithTicket = {}
	
	local query = Jecs.cached_query(world, components.CleanupTicket)

	for entity, ticketData in query:iter() do
		world:remove(entity, components.CleanupTicket)
		-- Prevent double cleanups
		if seen[entity] then continue end
		seen[entity] = true
		world:add(entity, components.Deleted)

		any = true

		table.insert(entitiesWithTicket, entity)

		--cascadeUpdateExpandedHeights(world, entity)
		profilebegin("Jexplorer::processImmediateCleaningTasks")
		local inst = world:get(entity, components.Instance)
		if inst then
			Manager.InstanceToEntity[inst] = nil
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
			Manager.ExplorerFrame.queueForExplorerFrameReuse(Manager, frame)
		end
		
		world:add(entity, components.Deleted)

		Manager.VirtualScroller.invalidateEntityHeightCache(Manager, entity)
		Manager.updateParent(entity, nil)
		profileend()
	end
	if not any then profileend() return false end
	
	-- If there wasn't any loops then theres no frames queued, now that we're here it means theres no gaurantee theres no frames queued so need to let scheduler know
	Manager.DeferredTaskScheduler.FrameReuseQueuePending = true

	profilebegin("Jexplorer::cleanupEntity::processDeferredCleaningTasks")
		profilebegin("freeGroups")
		for _, group in groupsToFree do
			(group::ItemGroup.ItemGroup):free()
		end
		profileend()
		
		profilebegin("removeEntityData")
		for _, entity in entitiesWithTicket do
			Manager.ClassNameCache[entity] = nil
			Manager.NameCache[entity] = nil
			Manager.ChildAmountCache[entity] = nil
		end
		profileend()

		profilebegin("deleteEntities")
		for _, entity in entitiesWithTicket do
			--world:delete(entity)
			HierarchyState.queueForEntityDeletion(Manager, entity)
		end
		--Manager.DeferredTaskScheduler.EntityDeletionQueuePending = true
		profileend()
	profileend()
	
	profileend()
	return true
end

function HierarchyState.queueForEntityCleanup(Manager, entity)
	local state = Manager.WidgetState
	local components = Manager.Components
	local world = state.World
	
	world:set(entity, components.CleanupTicket, {})
end

function HierarchyState.flushOnChildAddedQueue(Manager)
	profilebegin("Jexplorer::flushOnChildAddedQueue")
	local state = Manager.WidgetState
	local components = Manager.Components
	local world = state.World
	
	local anyChanged = false
	local seen = {}
	
	local query = Jecs.cached_query(world, components.ChildAddedTicket)
	
	for newParent, ticketData in query:iter() do
		world:remove(newParent, components.ChildAddedTicket)
		
		for _, childInst in ticketData.children do
			if seen[childInst] then continue end
			seen[childInst] = true  -- ADD THIS LINE!

			local childEntity = HierarchyState.getOrCreateInstanceEntity(Manager, childInst, newParent)

			local frame = world:get(newParent, components.Frame)
			if not frame then continue end
			local frameInst = Manager.frameOf(frame)
			if frameInst then 
				local main = frameInst:FindFirstChild("Main")
				if main then
					-- If a child is added, the entity always has atleast 1 child so just set to true always
					--main.Arrow.Visible = #instance:GetChildren() > 0
					main.Arrow.Visible = true
				end
			end
			HierarchyState.updateEntityOrder(Manager, childEntity)
		end
		
		if Manager.isExplorerEntityExpanded(newParent) then
			Manager.VirtualScroller.invalidateEntityHeightCache(Manager, newParent)
		end
		anyChanged = true
	end
	if not anyChanged then return false end
	
	HierarchyState.flushEntityPropAssignQueue(Manager)
	
	profileend()
	return anyChanged
end

function HierarchyState.queueForOnChildAdded(Manager, newParent, childEntity)
	local state = Manager.WidgetState
	local world = state.World
	local components = Manager.Components

	local ticket: {children: {Instance}}
	local existing = world:get(newParent, components.ChildAddedTicket)
	if existing then
		ticket = existing
	else
		ticket = {children = {}}
		world:set(newParent, components.ChildAddedTicket, ticket)
	end
	table.insert(ticket.children, childEntity)
end

function HierarchyState.flushOnChildRemovedQueue(Manager)
	profilebegin("Jexplorer::flushOnChildRemovedQueue")

	local components = Manager.Components
	local state = Manager.WidgetState
	local world = state.World
	local anyChanged = false
	local seen = {}
	
	local query = Jecs.cached_query(world, components.ChildMovedTicket)

	for oldParent, ticketData in query:iter() do
		world:remove(oldParent, components.ChildMovedTicket)
		
		for _, childInst in ticketData.children do
			if seen[childInst] then continue end
			seen[childInst] = true

			-- Update OLD parent's arrow visibility
			local frame = world:get(oldParent, components.Frame)
			if frame then
				local frameInst = Manager.frameOf(frame)
				if frameInst then
					local main = frameInst:FindFirstChild("Main")
					if main then
						local parentInstance = world:get(oldParent, components.Instance)
						-- Check if OLD parent still has remaining children
						main.Arrow.Visible = parentInstance and #parentInstance:GetChildren() > 0
					end
				end
			end

			-- Handle the child entity if it was reparented (not deleted)
			if childInst.Parent then
				local newParent = Manager.InstanceToEntity[childInst.Parent]
				if newParent then
					local childEntity = Manager.InstanceToEntity[childInst]
					if childEntity then
						if Manager.isExplorerEntityExpanded(newParent) then
							Manager.VirtualScroller.invalidateEntityHeightCache(Manager, childEntity)
						end
						Manager.updateParent(childEntity, newParent)

						HierarchyState.updateEntityOrder(Manager, childEntity)
						--local childFrame = world:get(childEntity, components.Frame)
						--if childFrame then
						--	Manager.ExplorerFrame.queueForExplorerFrameReuse(Manager, childFrame)
						--end
						anyChanged = true
					end
				end
			end
		end

		-- Invalidate old parent's flatCache
		if Manager.isExplorerEntityExpanded(oldParent) then
			Manager.VirtualScroller.invalidateEntityHeightCache(Manager, oldParent)
		end
	end
	if not anyChanged then return false end
	
	HierarchyState.flushEntityPropAssignQueue(Manager)
	
	profileend()
	return anyChanged
end

function HierarchyState.queueForOnChildRemoved(Manager, oldParent, childEntity)
	local state = Manager.WidgetState
	local world = state.World
	local components = Manager.Components
	
	local ticket: {children: {Instance}}
	local existing = world:get(oldParent, components.ChildMovedTicket)
	if existing then
		ticket = existing
	else
		ticket = {children = {}}
		world:set(oldParent, components.ChildMovedTicket, ticket)
	end
	table.insert(ticket.children, childEntity)
end

function HierarchyState.stepFlushEntityDeletionQueue(Manager)
	local state = Manager.WidgetState
	local components = Manager.Components
	local world = state.World
	local queryWorld = state.QueryWorld

	local n = 0
	local any = false
	
	local stepSize = Manager.getSetting("EntityDeletionFlushStep")
	for entity, ticketData in world:query(components.DeletionTicket):iter() do
		if n >= stepSize then break end
		any = true
		n += 1
		world:remove(entity, components.DeletionTicket)
		
		local idx = table.find(state.Entities, entity)
		if idx then table.remove(state.Entities, idx) end

		HierarchyState.deregisterFromQueryWorld(Manager, entity)
	end
	
	return any
end

function HierarchyState.queueForEntityDeletion(Manager, entity)
	local state = Manager.WidgetState
	local world = state.World
	local components = Manager.Components
	
	world:set(entity, components.DeletionTicket, {})
end

local function onChange(world: World, components: Types.Components, Manager: Manager, ent: ExplorerEntity, instance: Instance, v: string, oldValueCache: {[string]: any})
	local frame = world:get(ent, components.Frame)
	if not frame then return end

	local frameInst = Manager.frameOf(frame)
	if not frameInst then return end

	local oldValue = oldValueCache[v]
	local value = rawindex(instance, v)
	local oldTag = JexpTags.getTaggedPropertyTag(v, typeof(oldValue) == "EnumItem" and oldValue.Name or tostring(oldValue))
	local newTag = JexpTags.getTaggedPropertyTag(v, typeof(value) == "EnumItem" and value.Name or tostring(value))

	frameInst:RemoveTag(oldTag)
	frameInst:AddTag(newTag)
	oldValueCache[v] = value
end

local function onChangeRunContext(world: World, components: Types.Components, Manager: Manager, ent: ExplorerEntity, instance: Instance, oldValueCache: {[string]: any})
	local frame = world:get(ent, components.Frame)
	if not frame then return end

	local frameInst = Manager.frameOf(frame)
	if not frameInst then return end

	local value = rawindex(instance, "RunContext")
	frameInst.Name = Constants.ExplorerFrameScriptClassNameFormat:format(value.Name)
	oldValueCache.RunContext = value
end

local function onChanged(
	world: World, components: Types.Components, Manager: Manager, ent: ExplorerEntity, instance: Instance,
	handlers: {[string]: () -> ()}, nameCache: {[ExplorerEntity]: string}, classNameCache: {[ExplorerEntity]: string}, prop: string
)
	if prop == "Name" then
		nameCache[ent] = instance.Name
		local frame = world:get(ent, components.Frame)
		if frame then
			local frameInst = Manager.frameOf(frame)
			if frameInst then
				local main = frameInst:FindFirstChild("Main")
				if main and main:FindFirstChild("InstanceName") and main.InstanceName.Text ~= instance.Name then
					local instanceName = main.InstanceName
					instanceName.Text = instance.Name
					local bounds: Vector2 = rawindex(instanceName, "TextBounds")
					local x = instanceName:GetStyled("Position").X.Offset + bounds.X
					main.Insert.Position = UDim2.new(0, x + 10, 0.5)
					main.PendingChanges.Position = UDim2.new(0, x + 26, 0.5)
				end
			end
		end
	elseif prop == "ClassName" then
		classNameCache[ent] = instance.ClassName
	end
	local handler = handlers[prop]
	if not handler then return end
	handler()
end

local function onChildAdded(Manager: Manager, ent: ExplorerEntity, child: Instance)
	if Manager.isInstanceExcluded(child) then return end

	local existing = Manager.InstanceToEntity[child]
	if existing and Manager.WidgetState.World:has(existing, Manager.Components.AncestryLocked) then
		return
	end

	HierarchyState.queueForOnChildAdded(Manager, ent, child)
	Manager.DeferredTaskScheduler.EntityChildAddedQueuePending = true
end

local function onChildRemoved(Manager: Manager, ent: ExplorerEntity, child: Instance)
	local world = Manager.WidgetState.World
	local components = Manager.Components
	local existing = Manager.InstanceToEntity[child]
	if existing and world:has(existing, components.AncestryLocked) then
		return
	end

	if child.Parent == nil then return end
	if existing then
		local parent = Manager.parentOf(existing)
		if parent then
			local inst = Manager.instanceOf(parent)
			if inst and Manager.isInstanceExcluded(inst) then
				return
			end
		end
	end

	HierarchyState.queueForOnChildRemoved(Manager, ent, child)
	Manager.DeferredTaskScheduler.EntityChildRemovedQueuePending = true
end

local function onParentChanged(Manager: Manager, ent: ExplorerEntity, instance: Instance)
	if rawindex(instance, "Parent") == nil then
		HierarchyState.cleanupEntity(Manager, ent)
	end
end

local function onAttributeChanged(Manager: Manager, ent: ExplorerEntity, instance: Instance, currentAttributes: {[string]: any}, attrName: string)
	local queryWorld = Manager.WidgetState.QueryWorld
	local components = Manager.Components
	local usages = Manager.AttributeUsageAmounts
	local attrValue = instance:GetAttribute(attrName)

	if attrValue ~= nil and not currentAttributes[attrName] then
		currentAttributes[attrName] = true
		if usages[attrName] then
			usages[attrName] += 1
		else
			usages[attrName] = 1
		end
		local attrComp = Manager.QueryAttrMap[attrName]
		if not attrComp then
			attrComp = queryWorld:entity()
			queryWorld:set(attrComp::any, Jecs.Name, attrName)
			Manager.QueryAttrMap[attrName] = attrComp
		end

		Manager.refreshQueryAttributes(ent, attrComp)
	elseif attrValue == nil and currentAttributes[attrName] then
		currentAttributes[attrName] = nil
		if usages[attrName] then
			usages[attrName] -= 1
		else
			usages[attrName] = 0
		end
		Manager.refreshQueryAttributes(ent, nil)

		if usages[attrName] == 0 then
			local attrComp = Manager.QueryAttrMap[attrName]
			if attrComp then
				for queryEnt, linked in queryWorld:query(components.QueryLinkedEntities, attrComp):iter() do
					for _, ent in linked do
						Manager.refreshQueryTags(ent, nil)
					end
					if #linked == 0 then
						queryWorld:delete(queryEnt)
					end
				end
				queryWorld:delete(attrComp)
			end
			Manager.QueryAttrMap[attrName] = nil
			usages[attrName] = nil
		end
	end
end

local appliedTaggedProps = {}
function HierarchyState.flushEntityPropAssignQueue(Manager)
	local world = Manager.WidgetState.World
	local queryWorld = Manager.WidgetState.QueryWorld
	local components = Manager.Components

	local nameCache = Manager.NameCache
	local classNameCache = Manager.ClassNameCache
	local childAmountCache = Manager.ChildAmountCache
	local any = false

	local query = Jecs.cached_query(world, components.PropAssignTicket)

	profilebegin("Jexplorer::flushEntityPropAssignQueue")
	for ent, ticketData in query:iter() do
		any = true
		world:remove(ent, components.PropAssignTicket)

		local instance = world:get(ent, components.Instance)
		if not instance then continue end

		local connections = assert(world:get(ent, components.Connections))
		local id = Manager.getInstId(instance)
		if id then
			local color = Manager.IconColorMap[id]
			if color then
				world:set(ent, components.FrameIconColor, color)
			end
		end

		local className = instance.ClassName
		nameCache[ent] = instance.Name
		classNameCache[ent] = className
		childAmountCache[ent] = #instance:GetChildren()

		if ticketData.ty ~= "instance" then continue end
		
		local currentAttributes = {}
		local oldValueCache = {}
		local handlers = {}
		
		local props = getClassPropMap(className)
		assert(props)
		
		local n = 0
		for _, name in Constants.TaggedProperties do
			if not props[name] then continue end
			n += 1
			appliedTaggedProps[n] = name
		end
		
		for attrName in getattributes(instance) do
			currentAttributes[attrName] = true
			local usages = Manager.AttributeUsageAmounts
			if usages[attrName] then
				usages[attrName] += 1
			else
				usages[attrName] = 1
			end
			local attrComp = Manager.QueryAttrMap[attrName]
			if not attrComp then
				attrComp = queryWorld:entity()
				queryWorld:set(attrComp::any, Jecs.Name, attrName)
				Manager.QueryAttrMap[attrName] = attrComp
			end
		end
		for _, v in appliedTaggedProps do
			oldValueCache[v] = rawindex(instance, v)
			handlers[v] = function() onChange(world, components, Manager, ent, instance, v, oldValueCache) end
		end
		clear(appliedTaggedProps)
		
		if className == "Script" then
			-- RunContext needs to be special cased because its ExplorerFrames are named differently
			handlers.RunContext = function() onChangeRunContext(world, components, Manager, ent, instance, oldValueCache) end
		end
		
		local packageLink = instance:FindFirstChildOfClass("PackageLink")
		if packageLink then
			world:add(ent, components.HasPackageLink)
		end
		
		local n = #connections.items
		connections.items[n+1] = rbxconnect(rawindex(instance, "Changed"), function(prop: string)
			onChanged(world, components, Manager, ent, instance, handlers, nameCache, classNameCache, prop)
		end)
		connections.items[n+2] = rbxconnect(rawindex(instance, "ChildAdded"), function(child: Instance)
			if rawindex(child, "ClassName") == "PackageLink" then
				packageLink = child :: any
				world:add(ent, components.HasPackageLink)
			end
			onChildAdded(Manager, ent, child)
		end)
		connections.items[n+3] = rbxconnect(rawindex(instance, "ChildRemoved"), function(child: Instance)
			if child == packageLink then
				world:remove(ent, components.HasPackageLink)
			end
			onChildRemoved(Manager, ent, child)
		end)
		connections.items[n+4] = rbxconnect(getpropertychangedsignal(instance, "Parent"), function()
			onParentChanged(Manager, ent, instance)
		end)
		connections.items[n+5] = rbxconnect(rawindex(instance, "AttributeChanged"), function(attrName: string)
			onAttributeChanged(Manager, ent, instance, currentAttributes, attrName)
		end)

		Manager.refreshQueryAttributes(ent, nil)
	end

	profileend()
	return any
end

local archetypeToQueryEntity: {[string]: Jecs.Id} = {}

function HierarchyState.deregisterFromQueryWorld(Manager, entity)
	local components = Manager.Components
	local state = Manager.WidgetState
	local world = state.World
	local queryWorld = state.QueryWorld

	local queryEntity = world:get(entity, components.LinkedQueryEntity)
	if queryEntity then
		local linked = queryWorld:get(queryEntity, components.QueryLinkedEntities)
		if linked then
			if #linked == 1 then
				queryWorld:delete(queryEntity)
				local hash = queryWorld:get(queryEntity, components.QUERYWORLD_ComponentHash)
				if hash then
					archetypeToQueryEntity[hash] = nil
				end
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

local temporaryComponentArray: {Jecs.Id} = {}
function HierarchyState.registerIntoQueryWorld(Manager, entity, className, tags, attributes)
	if not className then
		warn("classname aint it")
		return
	end
	
	local state = Manager.WidgetState
	local world = state.World
	local queryWorld = state.QueryWorld
	local components = Manager.Components
	
	local classComponents = Manager.getPropertyComponentsForClass(queryWorld, className)
	
	local n = #classComponents
	local tn = #tags
	move(classComponents, 1, n, 1, temporaryComponentArray)
	move(tags, 1, tn, n + 1, temporaryComponentArray)
	move(attributes, 1, #attributes, n + tn + 1, temporaryComponentArray)
	
	sort(temporaryComponentArray)
	local hash = concat(temporaryComponentArray, ",")
	
	local existingQueryEntity = archetypeToQueryEntity[hash]
	if existingQueryEntity then
		clear(temporaryComponentArray)
		local linked = queryWorld:get(existingQueryEntity, components.QueryLinkedEntities)
		if not linked then
			world:set(entity, components.PropAssignTicket, {ty = "instance"})
			return
		end
		
		world:set(entity, components.LinkedQueryEntity, existingQueryEntity)
		table.insert(linked, entity)
		return existingQueryEntity
	end
	
	local linked = {entity}
	
	-- Query entity not found, create new
	local queryEntity = Jecs.entity_with_archetype(queryWorld, true, temporaryComponentArray)
	queryWorld:set(queryEntity, components.QUERYWORLD_ComponentHash, hash)
	queryWorld:set(queryEntity, components.QueryLinkedEntities, linked)
	
	world:set(entity, components.LinkedQueryEntity, queryEntity)
	
	archetypeToQueryEntity[hash] = queryEntity
	
	clear(temporaryComponentArray)
	return queryEntity
end

-- TODO: Should probably make another version of this since i dont know how the hell this even works, but for now keep it
function HierarchyState.getEntitiesBetween(Manager, e1, e2)
	profilebegin("Jexplorer::getEntitiesBetween")
	local visible = HierarchyState.getFlattenedVisibleEntities(Manager, {}, false)
	local i1, i2
	for i, eid: any in visible do
		if eid == e1 then i1 = i end
		if eid == e2 then i2 = i end
		if i1 and i2 then break end
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

function HierarchyState.updateEntityOrder(Manager, entity)
	profilebegin("Jexplorer::updateEntityOrder")
	local state = Manager.WidgetState
	local world = state.World
	local components = Manager.Components

	local i = table.find(state.Entities, entity)
	if i then
		table.remove(state.Entities, i)
	end

	table.insert(state.Entities, entity)
	profileend()
end

function HierarchyState.getChildren(entity)
	return hierarchyCache.childrenMap[entity] or {}
end

local VIRTUAL_ENTITY_PREFAB: {Jecs.Id}
function HierarchyState.createVirtualEntity(Manager, options, extra)
	assert(options.ClassName, "ClassName required")
	assert(options.Name, 'Name required')
	assert(options.ChildAmount, "ChildAmount required")

	local state = Manager.WidgetState
	local components = Manager.Components
	local queryWorld = state.QueryWorld
	local world = state.World
	local cleanup = Manager.CleanupFns

	local connections: Types.ItemGroup<RBXScriptConnection> = options.Parent and world:get(options.Parent, components.Connections)::any or state.Connections

	local tbl = {
		ClassName = options.ClassName,
		Name = options.Name,
	}

	for k, v in extra do
		tbl[k] = v
	end
	local ent = world:entity()
	
	table.insert(state.Entities, ent)
	if not VIRTUAL_ENTITY_PREFAB then
		VIRTUAL_ENTITY_PREFAB = {
			components.Instance,
			components.Connections,
			components.PropAssignTicket
		}
	end
	local instConnections = connections:extend(cleanup.call)
	bulkinsert(world, ent, VIRTUAL_ENTITY_PREFAB, {
		tbl,
		instConnections,
		{ty = "virtual"}
	})

	return ent
end

function HierarchyState.createInstanceEntity(Manager, instance, parent, dontSetInInstanceToEntity)
	profilebegin("Jexplorer::createInstanceEntity")
	local state = Manager.WidgetState
	local components = Manager.Components
	local cleanup = Manager.CleanupFns

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
	
	local entity = Jecs.entity_with_archetype(world,
		false,
		{
			components.Instance,
			components.Connections,
			components.ParentTabs,
			components.PropAssignTicket,
			if parent then pair(childof, parent) :: any else nil,
		}, 
		instance,
		connections,
		{},
		{ty = "instance"}
	)
	
	local children = getchildren(instance)
	if #children > 0 then
		world:set(entity, components.CreationTicket, {children = children})
	end
	if parent then
		local value = Manager.ChildAmountCache[parent]
		
		Manager.ChildAmountCache[parent] = value and value + 1 or 1
	end

	insert(state.Entities, entity)
	if not dontSetInInstanceToEntity then
		Manager.InstanceToEntity[instance] = entity
	end
	profileend()

	return entity
end

function HierarchyState.getOrCreateInstanceEntity(Manager, instance, ...)
	local instanceToEntity = Manager.InstanceToEntity
	local cached = instanceToEntity[instance]
	
	if cached then
		return cached
	end
	return HierarchyState.createInstanceEntity(Manager, instance, ...)
end

function HierarchyState.invalidateEntityStateCache(entity: ExplorerEntity)
	entityStateCache[entity] = nil
	flatCache.version += 1
	flatCache.flattenedEntities = nil
end

return HierarchyState