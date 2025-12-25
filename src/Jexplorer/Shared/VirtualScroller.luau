--!strict

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

local function filterVisible(Manager: Manager, top: number, viewportHeight: number, isScroller: boolean)
	profilebegin("Jexplorer::filterVisible")
	local components = Manager.Components
	local sheet = Manager.Style
	local state = Manager.WidgetState
	local world = state.World

	local HierarchyState = Manager.HierarchyState

	local isEntityExpanded = Manager.isExplorerEntityExpanded
	local isEntityInvisible = Manager.isExplorerEntityInvisible
	local isEntityDeleted = Manager.isExplorerEntityDeleted

	local height: number = Manager.getSetting("FrameHeight")
	local indentWidth: number = Manager.getSetting("IndentWidth")
	
	local visible = {}
	local invisible = {}
	local expandedHeightIndex = {}

	local frameBuffer = Manager.getSetting("VirtualScrollFrameBuffer")
	local viewportBuffer = height * frameBuffer
	local effectiveViewportHeight = viewportHeight + viewportBuffer

	local flattenedEntities, entityToIndex, indexToIndentOffset = HierarchyState.getFlattenedVisibleEntities(Manager, invisible, isScroller)
	
	local flatCount = #flattenedEntities
	--local visibleList = table.create(math.min(flatCount, 100))
	
	local expandedStates = {}
	for index, entity in flattenedEntities do
		expandedStates[index] = isEntityExpanded(entity)
	end
	
	for index, entity in flattenedEntities do
		profilebegin("Jexplorer::filterVisible::visibleCheck")
		
		local absoluteYOffset = height * (index - 1)
		local shouldBeVisible = false
		local isExpanded = expandedStates[index]
		
		if not isExpanded then
			shouldBeVisible = absoluteYOffset >= (top - viewportBuffer) and absoluteYOffset <= (top + effectiveViewportHeight)
		else
			local expandedHeight = calculateDeepHeightOptimized(
				world,
				components.Expanded,
				components.QueryExpanded,
				HierarchyState.ChildrenMap,
				Manager.ChildAmountCache,
				isEntityInvisible,
				isEntityDeleted,
				entity
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
			
			shouldBeVisible = topIsVisible or bottomIsVisible or spanIsVisible1 or spanIsVisible2
		end
		
		if not shouldBeVisible then
			table.insert(invisible, entity)
		else
			table.insert(visible, {
				entity = entity,
				yoffset = absoluteYOffset,
				indentoffset = indexToIndentOffset[index] * indentWidth,
			})
		end
		profileend()
	end
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
	for _, entity in invisible do
		local frame = world:get(entity, components.Frame)
		if frame and not isScrolling then
			local lastReuseTime = reuseDebounceTime[entity] or 0

			if currentTime - lastReuseTime > Manager.getSetting("VirtualReuseCooldown") then
				ExplorerFrame.queueForExplorerFrameReuse(Manager, frame)
				reuseDebounceTime[entity] = currentTime
			end
		end
	end
	
	local parentOf = Manager.parentOf
	local frameOf = Manager.frameOf
	local assign = ExplorerFrame.assignExplorerFrame
	local reuse = ExplorerFrame.queueForExplorerFrameReuse
	local allocateFrame = ExplorerFrame.getExplorerFrame
	
	local childrenMap = HierarchyState.ChildrenMap
	local isEntityInvisible = Manager.isExplorerEntityInvisible
	local childAmountCache = Manager.ChildAmountCache

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
			local n = 0
			for _, child in children do
				if isEntityInvisible(child) then continue end
				n += 1
			end
			childAmountCache[entity] = n
		end

		if world:has(entity, components.ArrowInvisible) then
			frameInst.Main.Arrow.Visible = false
		else
			local visible = (childAmountCache[entity] or 0) > 0
			frameInst.Main.Arrow.Visible = visible
			--frameInst.Children.Visible = visible
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
	end
	ExplorerFrame.flushFrameSetParentQueueIfConfigured(Manager)
	
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