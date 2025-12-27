--!strict
--!optimize 2

local Jecs = require("../Jecs")
local Types = require("../Types")

local RawInst = require("./Small/RawInst")

local rawnewindex = RawInst.rawnewindex

local profilebegin, profileend = debug.profilebegin, debug.profileend

type Manager = Types.Manager
type World = Types.World
type ExplorerEntity = Types.ExplorerEntity

local recentlyReusedEntities = {}
local reuseDebounceTime = {}
local isScrolling = false
local isVirtualScrollerUpdating = false
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

local VirtualScroller = {} :: Types.VirtualScroller

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

	local visible = table.create(endIndex - startIndex + 1)
	local invisible = {}
	
	local expandedHeightIndex = {}

	local isEntityExpanded = Manager.isExplorerEntityExpanded
	local isEntityInvisible = Manager.isExplorerEntityInvisible
	local isEntityDeleted = Manager.isExplorerEntityDeleted
	local components = Manager.Components
	local world = Manager.WidgetState.World
	local HierarchyState = Manager.HierarchyState
	local stateCache = HierarchyState.StateCache
	
	profilebegin("fill expanded states")
	local expandedStates = {}
	for index = startIndex, endIndex do
		local entity = flattenedEntities[index]
		local state = stateCache[entity]
		expandedStates[index] = if state then state.expanded else isEntityExpanded(entity)
	end
	profileend()
	
	profilebegin("visible check")
	local visibleSet = {}
	for index = startIndex, endIndex do
		local entity = flattenedEntities[index]
		local absoluteYOffset = height * (index - 1)
		local shouldBeVisible = false
		local isExpanded = expandedStates[index]

		if not isExpanded then
			shouldBeVisible = true
		else
			local expandedHeight = calculateDeepHeightOptimized(
				world, components.Expanded, components.QueryExpanded,
				HierarchyState.ChildrenMap, Manager.ChildAmountCache,
				isEntityInvisible, isEntityDeleted, entity
			)
			local expandedBottomOffset = absoluteYOffset + (height * expandedHeight)
			expandedHeightIndex[entity] = expandedHeight

			shouldBeVisible =  expandedBottomOffset >= viewportTop and absoluteYOffset <= viewportBottom
		end
		
		if not shouldBeVisible then
			table.insert(invisible, entity)
		else
			visibleSet[entity] = true
			table.insert(visible, {
				entity = entity,
				yoffset = absoluteYOffset,
				indentoffset = indexToIndentOffset[index] * indentWidth,
			})
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

function VirtualScroller.update(Manager, isScroller)
	local state = Manager.WidgetState
	local components = Manager.Components

	local jexplorerUi = state.JExplorerUI
	local world = state.World

	local ExplorerFrame = Manager.ExplorerFrame
	local HierarchyState = Manager.HierarchyState

	if isScroller and isVirtualScrollerUpdating then
		--task.defer(updateVirtualScroller)
		return
	end
	profilebegin("Jexplorer::updateVirtualScroller")

	isVirtualScrollerUpdating = true
	local top = jexplorerUi.InstanceTree.CanvasPosition.Y
	local visible, invisible, entityToIndex, height, expandedHeightIndex, flatCount = filterVisible(Manager, top, Manager.InstTreeAbsoluteSizeY, isScroller)

	local currentTime = os.clock()
	local any = false
	for _, entity in invisible do
		local frame = world:get(entity, components.Frame)
		if frame and not isScrolling then
			local lastReuseTime = reuseDebounceTime[entity] or 0

			if currentTime - lastReuseTime > Manager.getSetting("VirtualReuseCooldown") then
				ExplorerFrame.queueForExplorerFrameReuse(Manager, frame)
				any = true
				reuseDebounceTime[entity] = currentTime
			end
		end
	end
	if any and not isScroller then
		ExplorerFrame.flushFrameReuseQueue(Manager)
	end

	local parentOf = Manager.parentOf
	local frameOf = Manager.frameOf
	local assign = ExplorerFrame.assignExplorerFrame
	local reuse = ExplorerFrame.queueForExplorerFrameReuse
	local allocateFrame = ExplorerFrame.getExplorerFrame

	local childrenMap = HierarchyState.ChildrenMap
	local isEntityInvisible = Manager.isExplorerEntityInvisible
	local childAmountCache = Manager.ChildAmountCache
	local instanceTree = jexplorerUi.InstanceTree

	for _, info in visible do
		local entity, absoluteYOffset = info.entity, info.yoffset
		local instance = world:get(entity, components.Instance) :: Instance

		local frame = world:get(entity, components.Frame)

		reuseDebounceTime[entity] = nil

		local parent = parentOf(entity)
		if frame then
			assign(Manager, frame, entity, parent, instance.Parent == game)
		else
			local f = allocateFrame(Manager)
			world:set(entity, components.Frame, f)
			assign(Manager, f, entity, parent, instance.Parent == game)
			frame = f
		end
		if not frame then continue end

		local frameInst = frameOf(frame)
		if not frameInst then continue end

		frameInst.LayoutOrder = entityToIndex[entity]

		local children = childrenMap[entity]
		if not isScroller and children then
			childAmountCache[entity] = #children
		end

		if world:has(entity, components.ArrowInvisible) then
			frameInst.Main.Arrow.Visible = false
		else
			local visible = (childAmountCache[entity] or 0) > 0
			frameInst.Main.Arrow.Visible = visible
		end

		frameInst.Position = UDim2.fromOffset(info.indentoffset, absoluteYOffset)
		local expandedHeight = expandedHeightIndex[entity]
		if expandedHeight then
			local ruler = frameInst.Ruler
			ruler.Visible = true
			ruler.Size = UDim2.fromOffset(1, (expandedHeight - 1) * height)
		else
			local ruler = frameInst.Ruler
			ruler.Visible = false
		end
		state.FrameWorld:set(frame, components.FRAMEWORLD_FrameSetParentTicket, {newParent = instanceTree})
	end

	jexplorerUi.InstanceTree.CanvasSize = UDim2.new(5, 0, 0, flatCount * height)

	isVirtualScrollerUpdating = false
	profileend()
end

function VirtualScroller.rebuildAndUpdate(Manager, isScroller)
	Manager.HierarchyState.rebuildHierarchyCache(Manager)
	VirtualScroller.update(Manager, isScroller)
end

function VirtualScroller.trackScrolling(Manager)
	local jexplorerUi = Manager.WidgetState.JExplorerUI
	local lastPosition = jexplorerUi.InstanceTree.CanvasPosition
	local lastScrollTime = os.clock()
	local isScrolling = false

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

return VirtualScroller