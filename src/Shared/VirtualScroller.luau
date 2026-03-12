--!strict
--!optimize 2

local Jecs = require("../Jecs")
local Types = require("../Types")

local RawInst = require("./Small/RawInst")
local Constants = require("../Constants")
local stickToRightEdge = require("./Small/StickToRightEdge")

local rawnewindex = RawInst.rawnewindex
local rawindex = RawInst.rawindex

local profilebegin, profileend = debug.profilebegin, debug.profileend

type Manager = Types.Manager
type World = Types.World
type ExplorerEntity = Types.ExplorerEntity

local lastScrollTime = 0

local heightCache = {}
local heightCacheVersion = 0
local lastHeightCacheVersion = -1
-- Track which entities need height recalculation
local dirtyHeights = {}

local function calculateDeepHeightOptimized(
	world: World, 
	expanded: Jecs.Id, 
	queryExpanded: Jecs.Id, 
	childrenMap: {[ExplorerEntity]: {ExplorerEntity}}, 
	childAmountCache: {[ExplorerEntity]: number},
	isExplorerEntityInvisible: (ExplorerEntity) -> boolean,
	isExplorerEntityDeleted: (ExplorerEntity) -> boolean,
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
		if not (isExplorerEntityInvisible(child) or isExplorerEntityDeleted(child)) then
			local childIsExpanded = world:has(child, expanded) or world:has(child, queryExpanded)
			if childIsExpanded then
				totalHeight += calculateDeepHeightOptimized(world, expanded, queryExpanded, childrenMap, childAmountCache, isExplorerEntityInvisible, isExplorerEntityDeleted, child)
			else
				totalHeight += 1
			end
		end
	end

	heightCache[entity] = totalHeight
	dirtyHeights[entity] = nil
	return totalHeight
end

local VirtualScroller = {IsScrolling = false, IsVirtualScrollerUpdating = false} :: Types.VirtualScroller

function VirtualScroller.clearHeightCache()
	table.clear(heightCache)
	table.clear(dirtyHeights)
	heightCacheVersion += 1
end

function VirtualScroller.invalidateEntityHeightCache(Manager, entity)
	heightCache[entity] = nil
	dirtyHeights[entity] = true
	local parent = Manager.parentOf(entity)
	while parent do
		heightCache[parent] = nil
		dirtyHeights[parent] = true
		parent = Manager.parentOf(parent)
	end

	heightCacheVersion += 1
end

local lastVisible: {any} = {}
local function filterVisible(Manager: Manager, top: number, viewportHeight: number, isScroller: boolean)
	profilebegin("Jexplorer::filterVisible")
	local height: number = Manager.getSetting("FrameHeight")
	local indentWidth: number = Manager.getSetting("IndentWidth")
	local frameBuffer = Manager.getSetting("VirtualScrollFrameBuffer")

	local viewportBuffer = height * frameBuffer
	local viewportTop = top - viewportBuffer
	local viewportBottom = top + viewportHeight + viewportBuffer
	local effectiveViewportHeight = viewportHeight + viewportBuffer

	local flattenedEntities, entityToIndex, indexToIndentOffset = 
		Manager.HierarchyState.getFlattenedVisibleEntities(Manager, {}, isScroller)
	local flatCount = #flattenedEntities

	local startIndex = math.max(1, math.floor(viewportTop / height) + 1)
	local endIndex = math.min(flatCount, math.ceil(viewportBottom / height) + 1)

	local visible = {}--table.create(endIndex - startIndex + 1)
	local invisible = {}
	local visibleN = 1
	
	local expandedHeightIndex = {}

	local isEntityExpanded = Manager.isExplorerEntityExpanded
	local isEntityInvisible = Manager.isExplorerEntityInvisible
	local isEntityDeleted = Manager.isExplorerEntityDeleted
	local components = Manager.Components
	local world = Manager.WidgetState.World
	local HierarchyState = Manager.HierarchyState
	local stateCache = HierarchyState.StateCache
	
	local expandedParents = {}
	local expandedParentsSet = {}
	
	profilebegin("visible check")
	local visibleSet = {}
	for index = startIndex, endIndex do
		local entity = flattenedEntities[index]
		local absoluteYOffset = height * (index - 1)
		
		local parent = Manager.parentOf(entity)
		if parent and not expandedParentsSet[parent] and isEntityExpanded(parent) then
			table.insert(expandedParents, parent)
			expandedParentsSet[parent] = true
		end
		
		visibleSet[entity] = true
		visible[visibleN] = {
			entity = entity,
			yoffset = absoluteYOffset,
			indentoffset = indexToIndentOffset[index] * indentWidth,
		}
		visibleN += 1
	end
	profileend()
	
	profilebegin("expanded check")
	for _, entity in expandedParents do
		local parent = Manager.parentOf(entity)
		if parent and not expandedParentsSet[parent] and isEntityExpanded(parent) then
			table.insert(expandedParents, parent)
			expandedParentsSet[parent] = true
		end
	end
	for _, entity in expandedParents do
		local index = entityToIndex[entity]
		local absoluteYOffset = height * (index - 1)
		
		local expandedHeight = calculateDeepHeightOptimized(
			world, components.Expanded, components.QueryExpanded,
			HierarchyState.ChildrenMap, Manager.ChildAmountCache,
			isEntityInvisible, isEntityDeleted, entity
		)
		local expandedBottomOffset = absoluteYOffset + (height * expandedHeight)
		expandedHeightIndex[entity] = expandedHeight

		local viewportBottom = top + effectiveViewportHeight
		local viewportTop = top - viewportBuffer

		local topIsVisible =
			absoluteYOffset >= viewportTop
			and	absoluteYOffset <= viewportBottom
		local bottomIsVisible =
			expandedBottomOffset >= viewportTop
			and	expandedBottomOffset <= viewportBottom
		local spanIsVisible1 =
			absoluteYOffset >= viewportTop
			and	expandedBottomOffset <= viewportBottom
		local spanIsVisible2 =
			expandedBottomOffset >= viewportTop
			and	absoluteYOffset <= viewportBottom

		if topIsVisible or bottomIsVisible or spanIsVisible1 or spanIsVisible2 then
			visibleSet[entity] = true
			visible[visibleN] = {
				entity = entity,
				yoffset = absoluteYOffset,
				indentoffset = indexToIndentOffset[index] * indentWidth
			}
			visibleN += 1
		end
	end
	profileend()
	
	profilebegin("invisible check")
	for _, info in lastVisible do
		local entity = info.entity
		if not visibleSet[entity] then
			table.insert(invisible, entity)
		end
	end
	lastVisible = visible
	profileend()

	profileend()
	return visible, invisible, entityToIndex, height, expandedHeightIndex, flatCount
end

local isModifyingInstances = false
local lastCanvasPos = Vector2.zero
function VirtualScroller.update(Manager, isScroller: boolean, forceUpdateIcons: boolean?)
	local state = Manager.WidgetState
	local components = Manager.Components

	local jexplorerUi = state.JExplorerUI
	local frameWorld = state.FrameWorld
	local world = state.World

	local ExplorerFrame = Manager.ExplorerFrame
	local HierarchyState = Manager.HierarchyState

	if isScroller and VirtualScroller.IsVirtualScrollerUpdating then
		--task.defer(VirtualScroller.update, Manager, true)
		return
	end
	
	profilebegin("Jexplorer::updateVirtualScroller")

	VirtualScroller.IsVirtualScrollerUpdating = true
	local scrollStep = Manager.getSetting("ScrollStep")
	local rawPos = state.TreeScroller.CanvasPosition
	local top = math.floor(rawPos.Y / scrollStep) * scrollStep
	
	local visible, invisible, entityToIndex, height, expandedHeightIndex, flatCount = filterVisible(Manager, top, Manager.InstTreeAbsoluteSizeY, isScroller)

	local currentTime = os.clock()
	local any = false
	for _, entity in invisible do
		local frame = world:get(entity, components.Frame)
		if frame then
			ExplorerFrame.queueForExplorerFrameReuse(Manager, frame, entity)
			any = true
		end
	end
	if any then
		ExplorerFrame.flushFrameReuseQueue(Manager)
	end

	local parentOf = Manager.parentOf
	local frameOf = Manager.frameOf
	local assign = ExplorerFrame.assignExplorerFrame
	local reuse = ExplorerFrame.queueForExplorerFrameReuse
	local allocateFrame = ExplorerFrame.getExplorerFrame
	
	local isEntityInvisible = Manager.isExplorerEntityInvisible
	local childAmountCache = Manager.ChildAmountCache
	local stateCache = HierarchyState.StateCache
	local scrollContainer = state.InstanceTree
	local childrenMap = HierarchyState.ChildrenMap
	
	local scrollPos = Vector2.new(rawPos.X, top)
	local smoothed = lastCanvasPos:Lerp(scrollPos, 0.8)
	local xMoved = math.abs(lastCanvasPos.X - scrollPos.X) > 0
	
	lastCanvasPos = scrollPos
	
	local lockedInstanceModification = not isModifyingInstances
	isModifyingInstances = true

	local classNameCache = Manager.ClassNameCache
	local nameCache = Manager.NameCache
	
	local scrollingFrame = state.TreeScroller
	local containerWidth = scrollingFrame.AbsoluteSize.X

--	local frameInfo = {}
--	local ftamI = 1

	for _, info in visible do
		local entity, absoluteYOffset = info.entity, info.yoffset
		local instance = world:get(entity, components.Instance) :: Instance

		local frame = world:get(entity, components.Frame)

		if not frame then
			local f = allocateFrame(Manager)
			world:set(entity, components.Frame, f)
			frame = f
		end
		
		if not frame then continue end

		local frameInst = frameOf(frame)
		if not frameInst then continue end
		
		local frameState = state.FrameWorld:get(frame, components.FrameState)
		if not frameState then continue end
		
		if not isScroller then
			local children = childrenMap[entity]
			if children then
				childAmountCache[entity] = #children
			else
				childAmountCache[entity] = 0
			end
		end

--		frameInfo[ftamI] = {frameX = frameX, frameY = frameY, entity = entity, inst = instance, frameInst = frameInst, frameState = frameState, frame = frame}
--		ftamI += 1
		
		if lockedInstanceModification then
			local frameX = -smoothed.X + info.indentoffset
			local frameY = -smoothed.Y + absoluteYOffset
			
			frameState.lastFrameX = frameState.currentFrameX
			frameState.currentFrameX = frameX
			
			local className = classNameCache[entity]
			
			-- position
			frameInst.Position = UDim2.fromOffset(frameX, frameY)
			
			-- ruler
			local expandedHeight = expandedHeightIndex[entity]
			if expandedHeight then
				local ruler = frameState.ruler
				ruler.Visible = true
				ruler.Size = UDim2.fromOffset(1, (expandedHeight - 1) * height)
			else
				local ruler = frameState.ruler
				ruler.Visible = false
			end
			
			-- arrow
			do 
				local arrow = frameState.arrow
				if world:has(entity, components.ArrowInvisible) then
					arrow.Visible = false
				else
					if className == "DataModel" or childAmountCache[entity] == 0 then
						arrow.Visible = false
					else
						arrow.Visible = true
					end
					if Manager.isExplorerEntityExpanded(entity) then
						arrow.Rotation = 0
					else
						arrow.Rotation = -90
					end
				end
			end 
			
			-- special name states
			do 
				local newName

				if className == "Script" then
					newName = Constants.ExplorerFrameScriptClassNameFormat:format(
						rawindex(instance, "RunContext").Name
					)
				else
					newName = Constants.ExplorerFrameNameFormat:format(className)
				end

				if newName ~= frameState.currentFrameName then
					rawnewindex(frameInst, "Name", newName)
					frameState.currentFrameName = newName
				end
			end

			-- text
			rawnewindex(frameState.instanceName, "Text", nameCache[entity])

			-- assign frame
			local entityState = stateCache[entity]
			local isTopLevel = if entityState ~= nil then entityState.isTopLevel else world:has(entity, components.DisplayTopLevel)
	
			local isnewlyassigned = assign(Manager, frame, entity, parentOf(entity), instance.Parent == game or isTopLevel, true)
		
			-- frame icons

			if (not isnewlyassigned) and (forceUpdateIcons or world:has(entity, components.HasSideIcons)) then
				ExplorerFrame.updateRightEdgeIcons(Manager,
					frame, containerWidth, if isScroller then frameX else nil, entity, frameState
				)
			end
			
		end
	end
	
	if lockedInstanceModification then
		isModifyingInstances = false
	end
	
	for frame in state.FrameWorld:query(components.Instance):without(components.Entity) do
		ExplorerFrame.queueForExplorerFrameReuse(Manager, frame)
	end
	Manager.DeferredTaskScheduler.FrameTagAssignQueuePending = true
	
	local size = UDim2.new(5, 0, 0, (flatCount + 3) * height)
	state.TreeScroller.CanvasSize = size

	VirtualScroller.IsVirtualScrollerUpdating = false
	profileend()
end

function VirtualScroller.rebuildAndUpdate(Manager, isScroller)
	Manager.HierarchyState.rebuildHierarchyCache(Manager)
	VirtualScroller.update(Manager, isScroller, true)
end

function VirtualScroller.trackScrolling(Manager)
	local state = Manager.WidgetState
	local lastScrollTime = -math.huge -- never triggered yet
	local settleTime = Manager.getSetting("VirtualScrollSettleTime")

	local c = state.TreeScroller:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		-- Any signal fire = scrolling. Let the settle timer decide when it stops.
		lastScrollTime = os.clock()

		if not VirtualScroller.IsScrolling then
			VirtualScroller.IsScrolling = true
		end
	end)

	local t = task.spawn(function()
		while true do
			task.wait(1/30)
			-- Only flip to false if we were scrolling AND enough time has passed
			-- without a new scroll event
			if VirtualScroller.IsScrolling and (os.clock() - lastScrollTime) > settleTime then
				VirtualScroller.IsScrolling = false
			end
		end
	end)

	return c, t
end

return VirtualScroller