--!strict

local ScriptEditorService = game:GetService("ScriptEditorService")

local Types = require("../Types")
local Jecs = require("../Jecs")
local RawInst = require("./Small/RawInst")
local JexpTags = require("./Small/JexpTags")
local Constants = require("../Constants")

local getClassPropMap = require("./Small/GetClassPropMap")
local cachedQuery = require("./Small/CachedQuery")

local ItemGroup = require("./Vendor/ItemGroup")

local OrderEditor = require("../Editors/OrderEditor")
local VersionControl = require("../Editors/VersionControl")

local profilebegin, profileend = debug.profilebegin, debug.profileend
local rbxconnect = RawInst.rbxconnect
local getpropertychangedsignal = RawInst.getpropertychangedsignal
local rawindex = RawInst.rawindex
local index = RawInst.index

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
		return nameCache[a] < nameCache[b]
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

	local state = Manager.WidgetState
	local components = Manager.Components

	local childrenMap = hierarchyCache.childrenMap
	local roots = hierarchyCache.roots

	local flatList = table.create(100)
	local indexToIndentOffset = {}
	local entityToIndex = {}
	local flatIndex = 0
	local invisibleIndex = #invisible
	local stack = table.create(200)
	local stackSize = 0
	local indentStack = table.create(200) -- Track indent level for each stack item

	profilebegin("traverse")

	-- Unroll root insertion (minor optimization)
	local rootCount = #roots
	for i = rootCount, 1, -1 do
		stackSize += 1
		stack[stackSize] = roots[i]
		indentStack[stackSize] = 0 -- Roots have indent offset 0
	end

	local entityinvisible = Manager.isExplorerEntityInvisible
	local entitydeleted = Manager.isExplorerEntityDeleted
	local entityexpanded = Manager.isExplorerEntityExpanded

	while stackSize > 0 do
		local entity = stack[stackSize]
		local currentIndent = indentStack[stackSize]
		stackSize -= 1

		local state = entityStateCache[entity]
		if not state then
			profilebegin("generateentitystate")
			local invisible = entityinvisible(entity) or entitydeleted(entity)
			local expanded = entityexpanded(entity)
			state = {invisible = invisible, expanded = expanded}
			entityStateCache[entity] = state
			profileend()
		end

		if state.invisible then
			invisibleIndex += 1
			invisible[invisibleIndex] = entity
		else
			flatIndex += 1
			flatList[flatIndex] = entity
			indexToIndentOffset[flatIndex] = currentIndent -- Store indent offset
			if state.expanded then
				local children = childrenMap[entity]
				if children then
					local childCount = #children
					local childIndent = currentIndent + 1 -- Children have +1 indent
					for i = 1, childCount do
						stackSize += 1
						stack[stackSize] = children[childCount - i + 1]
						indentStack[stackSize] = childIndent
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
	return flatList, entityToIndex, indexToIndentOffset
end

function HierarchyState.flushEntityCreationQueue(Manager)
	local state = Manager.WidgetState
	local world = state.World
	local components = Manager.Components
	
	local query = cachedQuery(world, "creation-ticket", components.CreationTicket)
	
	local any = false
	for parent, ticketData in query:iter() do
		any = true
		world:remove(parent, components.CreationTicket)
		
		for _, child in ticketData.children do
			if Manager.isInstanceExcluded(child) then continue end
			if Manager.InstanceToEntity[child] then continue end

			HierarchyState.createInstanceEntity(Manager, child, parent)
		end
	end
	if not any then return false end
	
	HierarchyState.flushEntityPropAssignQueue(Manager)
	
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
	
	local query = cachedQuery(world, "cleanup-ticket", components.CleanupTicket)

	for entity, ticketData in query:iter() do
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
	
	local query = cachedQuery(world, "child-added-ticket", components.ChildAddedTicket)
	
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
	
	local query = cachedQuery(world, "child-moved-ticket", components.ChildMovedTicket)

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
						Manager.updateParent(childEntity, newParent)
						if Manager.isExplorerEntityExpanded(newParent) then
							Manager.VirtualScroller.invalidateEntityHeightCache(Manager, childEntity)
						end

						HierarchyState.updateEntityOrder(Manager, childEntity)
						local childFrame = world:get(childEntity, components.Frame)
						if childFrame then
							Manager.ExplorerFrame.queueForExplorerFrameReuse(Manager, childFrame)
						end
						anyChanged = true
					end
				end
			end
		end

		-- Invalidate old parent's cache
		if Manager.isExplorerEntityExpanded(oldParent) then
			Manager.VirtualScroller.invalidateEntityHeightCache(Manager, oldParent)
		end
	end

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
	
	return any
end

function HierarchyState.queueForEntityDeletion(Manager, entity)
	local state = Manager.WidgetState
	local world = state.World
	local components = Manager.Components
	
	world:set(entity, components.DeletionTicket, {})
end

function HierarchyState.flushEntityPropAssignQueue(Manager)
	local world = Manager.WidgetState.World
	local queryWorld = Manager.WidgetState.QueryWorld
	local components = Manager.Components
	
	local nameCache = Manager.NameCache
	local classNameCache = Manager.ClassNameCache
	local childAmountCache = Manager.ChildAmountCache
	local debugIdToInstance = Manager.DebugIdToInstance
	local any = false
	
	local query = cachedQuery(world, "prop-assign-ticket", components.PropAssignTicket)
	
	profilebegin("Jexplorer::flushEntityPropAssignQueue")
	for ent, ticketData in query:iter() do
		any = true
		world:remove(ent, components.PropAssignTicket)
		
		local instance = world:get(ent, components.Instance)
		if not instance then continue end
		
		local connections = assert(world:get(ent, components.Connections))

		local className = instance.ClassName
		nameCache[ent] = instance.Name
		classNameCache[ent] = className
		childAmountCache[ent] = #instance:GetChildren()
		debugIdToInstance[instance:GetDebugId()] = instance
		--hierarchyCache.expandedHeights[ent] = 1

		if ticketData.ty ~= "instance" then continue end
		local appliedTaggedProps = {}
		local props = getClassPropMap(className)
		assert(props)

		local tags = {}

		for _, name in Constants.TaggedProperties do
			if not props[name] then continue end
			table.insert(appliedTaggedProps, name)
		end
		for _, tag in instance:GetTags() do
			local comp = Manager.QueryTagMap[tag]
			if not comp then continue end

			table.insert(tags, comp)
		end

		local handlers = {}
		for _, v in appliedTaggedProps do
			local oldValue = rawindex(instance, v)
			local function onChange()
				local frame = world:get(ent, components.Frame)
				if not frame then return end

				local frameInst = Manager.frameOf(frame)
				if not frameInst then return end

				local value = rawindex(instance, v)
				local oldTag = JexpTags.getTaggedPropertyTag(v, typeof(oldValue) == "EnumItem" and oldValue.Name or tostring(oldValue))
				local newTag = JexpTags.getTaggedPropertyTag(v, typeof(value) == "EnumItem" and value.Name or tostring(value))

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
			rbxconnect(rawindex(instance, "Changed"), function(prop: string)
				--VersionControl.onInstancePropChange(instance, prop, rawindex(instance, prop))

				if prop == "Name" then
					nameCache[ent] = instance.Name
					local frame = world:get(ent, components.Frame)
					if frame then
						local frameInst = Manager.frameOf(frame)
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
			rbxconnect(rawindex(instance, "ChildAdded"), function(child: Instance)
				if Manager.isInstanceExcluded(child) then return end
				
				local existing = Manager.InstanceToEntity[child]
				if existing and world:has(existing, components.AncestryLocked) then
					return
				end
				
				HierarchyState.queueForOnChildAdded(Manager, ent, child)
			end),
			rbxconnect(rawindex(instance, "ChildRemoved"), function(child: Instance)
				local existing = Manager.InstanceToEntity[child]
				if existing and world:has(existing, components.AncestryLocked) then
					return
				end
				
				-- Handled in the parent changed connection
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
			end),
			rbxconnect(getpropertychangedsignal(instance, "Parent"), function()
				if rawindex(instance, "Parent") == nil then
					HierarchyState.cleanupEntity(Manager, ent)
				end
			end)
		})

		HierarchyState.deregisterFromQueryWorld(Manager, ent)
		HierarchyState.registerIntoQueryWorld(Manager, ent, className, tags)
	end
	
	profileend()
	return any
end

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

function HierarchyState.registerIntoQueryWorld(Manager, entity, className, tags)
	if not className then
		warn("classname aint it")
		return
	end
	
	local state = Manager.WidgetState
	local world = state.World
	local queryWorld = state.QueryWorld
	local components = Manager.Components
	
	local classComponents = table.clone(Manager.getPropertyComponentsForClass(queryWorld, className))
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
	
	Jecs.bulk_insert(queryWorld::World, queryEntity, classComponents, {})
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

	local instConnections = connections:extend(cleanup.call)
	Jecs.bulk_insert(world, ent, {
		components.Instance,
		components.Connections,
		components.PropAssignTicket
	}, {
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

	local entity = world:entity()
	Jecs.bulk_insert(world, entity, {
		components.Instance,
		components.Connections,
		components.ParentTabs,
		components.PropAssignTicket,
		if parent then Manager.ChildOf(parent) else nil
	},
	{
		instance,
		connections,
		{},
		{ty = "instance"}
	})
	
	local children = instance:GetChildren()
	if #children > 0 then
		world:set(entity, components.CreationTicket, {children = children})
	end

	table.insert(state.Entities, entity)
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
end

return HierarchyState