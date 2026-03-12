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
type ExplorerFrame = Types.ExplorerFrame

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

	local flattenedEntities, entityToIndex, indexToIndentOffset = 
		Manager.HierarchyState.getFlattenedVisibleEntities(Manager, {}, isScroller)
	local flatCount = #flattenedEntities

	local startIndex = math.max(1, math.floor(viewportTop / height) + 1)
	local endIndex = math.min(flatCount, math.ceil(viewportBottom / height) + 1)

	local visible = {}
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
	local numExpandedParents = 0

	profilebegin("visible check")
	local visibleSet = {}
	for index = startIndex, endIndex do
		local entity = flattenedEntities[index]
		local absoluteYOffset = height * (index - 1)

		local parent = Manager.parentOf(entity)
		if parent and not expandedParentsSet[parent] and isEntityExpanded(parent) then
			numExpandedParents += 1
			expandedParents[numExpandedParents] = parent
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
			numExpandedParents += 1
			expandedParents[numExpandedParents] = parent
			
			expandedParentsSet[parent] = true
		end
	end
	
	local stickyStackDepth = 0
	local visibleExpandedAncestors
	if numExpandedParents > 0 then
		if numExpandedParents >= 2 then
			table.sort(expandedParents, function(a, b)
				return (entityToIndex[a] or 0) < (entityToIndex[b] or 0)
			end)
		end
		visibleExpandedAncestors = {}

		for _, entity in expandedParents do
			local index = entityToIndex[entity]
			if not index then continue end

			local absoluteYOffset = height * (index - 1)

			local expandedHeight = calculateDeepHeightOptimized(
				world, components.Expanded, components.QueryExpanded,
				HierarchyState.ChildrenMap, Manager.ChildAmountCache,
				isEntityInvisible, isEntityDeleted, entity
			)
			expandedHeightIndex[entity] = expandedHeight

			local expandedBottomOffset = absoluteYOffset + (height * expandedHeight)

			local childrenAreVisible =
				expandedBottomOffset > top                    -- real, no buffer
				and absoluteYOffset < (top + viewportHeight)  -- real, no buffer

			if not childrenAreVisible then continue end

			local indentOffset = indexToIndentOffset[index] * indentWidth
			local stickyStackBottom = stickyStackDepth  * height  -- bottom of all currently pinned frames

			local isScrolledPast = absoluteYOffset <= (top + stickyStackBottom)

			local stickyY: number? = nil
			local rulerHeight: number

			if isScrolledPast then
				local nextStickyBottom = (stickyStackDepth + 1) * height
				local tailTop = expandedBottomOffset - top - height

				if nextStickyBottom > tailTop then
					rulerHeight = (expandedHeight - 1) * height
					stickyY = nil
				else
					local _stickyY = stickyStackDepth * height
					stickyStackDepth += 1
					rulerHeight = (expandedBottomOffset - top - _stickyY) - height
					stickyY = _stickyY
				end
			else
				rulerHeight = (expandedHeight - 1) * height
			end

			if not visibleSet[entity] or isScrolledPast then
				visibleSet[entity] = true
				visible[visibleN] = {
					entity = entity,
					yoffset = absoluteYOffset,
					indentoffset = indentOffset,
				}
				visibleExpandedAncestors[visibleN] = {
					stickyY = stickyY,
					rulerHeight = rulerHeight,
				}
				visibleN += 1
			end
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
	return visible, invisible, entityToIndex, height, expandedHeightIndex, flatCount, visibleExpandedAncestors or {}, stickyStackDepth
end

local RULER_POOL_SIZE = 20
local rulerPool: {GuiObject} = {}

local RulerPool = {}

function RulerPool.fillToLimit(Manager: Manager)
	if #rulerPool >= RULER_POOL_SIZE then return end
	local framesToCreate = RULER_POOL_SIZE - #rulerPool
	for _ = 1, framesToCreate do
		local ruler = Instance.new("Frame")
		ruler.Name = "StickyRuler"
		ruler.BorderSizePixel = 0
		
		table.insert(rulerPool, ruler)
	end
end

function RulerPool.getRuler(Manager: Manager): Frame
	if #rulerPool == 0 then
		RulerPool.fillToLimit(Manager)
	end
	return table.remove(rulerPool) :: Frame
end

function RulerPool.releaseRuler(Manager: Manager, frame: ExplorerFrame)
	local state = Manager.WidgetState
	local frameWorld = state.FrameWorld
	local components = Manager.Components

	local ruler = frameWorld:get(frame, components.FRAMEWORLD_Ruler)
	if not ruler then return end

	--ruler.Visible = false
	ruler.Size = UDim2.fromOffset(0, 0)
	ruler.Parent = nil
	frameWorld:remove(frame, components.FRAMEWORLD_Ruler)
	table.insert(rulerPool, ruler)
end

function RulerPool.assignRuler(Manager: Manager, frame: ExplorerFrame, frameX: number, stickyY: number, rulerHeight: number, indentWidth: number)
	local state = Manager.WidgetState
	local frameWorld = state.FrameWorld
	local components = Manager.Components

	local ruler = frameWorld:get(frame, components.FRAMEWORLD_Ruler)
	if not ruler then
		local _ruler = RulerPool.getRuler(Manager)
		_ruler.Parent = state.InstanceTree
		frameWorld:set(frame, components.FRAMEWORLD_Ruler, _ruler)
		ruler = _ruler
	end
	local ruler = assert(ruler)
	
	ruler.Position = UDim2.fromOffset(frameX + indentWidth, stickyY + Manager.getSetting("FrameHeight"))
	ruler.Size = UDim2.fromOffset(1, math.max(0, rulerHeight))
	--ruler.Visible = rulerHeight > 0
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
		return
	end

	profilebegin("Jexplorer::updateVirtualScroller")

	VirtualScroller.IsVirtualScrollerUpdating = true
	
	local indentWidth: number = Manager.getSetting("IndentWidth")
	local scrollStep = Manager.getSetting("ScrollStep")
	local rawPos = state.TreeScroller.CanvasPosition
	local top = math.floor(rawPos.Y / scrollStep) * scrollStep

	local visible, invisible, entityToIndex, height, expandedHeightIndex, flatCount, visibleExpandedAncestors, stickyStackDepth =
		filterVisible(Manager, top, Manager.InstTreeAbsoluteSizeY, isScroller)

	local currentTime = os.clock()
	local any = false
	for _, entity in invisible do
		local frame = world:get(entity, components.Frame)
		if frame then
			local frameState = frameWorld:get(frame, components.FrameState)
			if frameState then
				frameState.isSticky = false
			end
			RulerPool.releaseRuler(Manager, frame)  -- release before reuse
			ExplorerFrame.queueForExplorerFrameReuse(Manager, frame, entity)
			any = true
		end
	end
	if any then
		ExplorerFrame.flushFrameReuseQueue(Manager)
	end
	
	local stickyStackHeight = stickyStackDepth * height

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
	local maxNameBoundsX = 0
	
	local stickyStacksEnabled = Manager.getSetting("StickyStacksEnabled")
	
	local updateRightEdgeIcons = {}
	
	for i, info in visible do
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
		if not lockedInstanceModification then continue end
		
		local frameX = -smoothed.X + info.indentoffset
		local frameY
		local ancestorInfo = visibleExpandedAncestors[i]
		
		local isSticky
		if ancestorInfo and ancestorInfo.stickyY then
			if stickyStacksEnabled then
				isSticky = true
				frameWorld:add(frame, components.FRAMEWORLD_IsSticky)
				frameY = ancestorInfo.stickyY
				RulerPool.assignRuler(Manager, frame, frameX, ancestorInfo.stickyY, ancestorInfo.rulerHeight, indentWidth)
			else
				frameY = -smoothed.Y + absoluteYOffset
				local expandedHeight = expandedHeightIndex[entity]
				if expandedHeight then
					RulerPool.assignRuler(Manager, frame, frameX, frameY, (expandedHeight - 1) * height, indentWidth)
				else
					RulerPool.releaseRuler(Manager, frame)
				end
			end
		else
			isSticky = false
			frameWorld:remove(frame, components.FRAMEWORLD_IsSticky)
			frameY = -smoothed.Y + absoluteYOffset
			local expandedHeight = expandedHeightIndex[entity]
			if expandedHeight then
				if frameY > stickyStackHeight then
					RulerPool.assignRuler(Manager, frame, frameX, frameY, (expandedHeight - 1) * height, indentWidth)
				elseif frameWorld:has(frame, components.FRAMEWORLD_Ruler) then
					RulerPool.releaseRuler(Manager, frame)
				end
			else
				RulerPool.releaseRuler(Manager, frame)
			end
		end
		
		do
			local nameBoundsX = info.indentoffset + frameState.currentNameBoundX
			if nameBoundsX > maxNameBoundsX then
				maxNameBoundsX = nameBoundsX
			end
		end

		frameState.lastFrameX = frameState.currentFrameX
		frameState.currentFrameX = frameX

		local className = classNameCache[entity]

		frameInst.Position = UDim2.fromOffset(frameX, frameY)

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
		if (not isnewlyassigned) and (forceUpdateIcons or world:has(entity, components.HasSideIcons)) then
			table.insert(updateRightEdgeIcons, {frame = frame, frameX = if isScroller then frameX else nil, entity = entity, frameState = frameState})
		end
		if stickyStacksEnabled then
			if isSticky then
				frameState.overlayFrame.BackgroundTransparency = 0.01
				frameInst.ZIndex = 10
			else
				frameState.overlayFrame.BackgroundTransparency = 0
				frameInst.ZIndex = 0
			end
		end
	end
	for _, args in updateRightEdgeIcons do
		ExplorerFrame.updateRightEdgeIcons(Manager,
			args.frame, containerWidth, args.frameX, args.entity, args.frameState
		)
	end

	if lockedInstanceModification then
		isModifyingInstances = false
	end

	for frame in state.FrameWorld:query(components.Instance):without(components.Entity) do
		ExplorerFrame.queueForExplorerFrameReuse(Manager, frame)
	end
	Manager.DeferredTaskScheduler.FrameTagAssignQueuePending = true

	local size = UDim2.new(
		0, maxNameBoundsX + 80, -- Enough padding for 3 right edge icons
		0, (flatCount + 3) * height
	)
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