--!strict
--!optimize 2

local ScriptEditorService = game:GetService("ScriptEditorService")

local Types = require("../Types")
local Jecs = require("../Jecs")
local RawInst = require("./Small/RawInst")
local UITemplates = require("./UITemplates")
local Selector = require("./Small/Selector")
local ClassIcon = require("./Small/ClassIcon")
local Style = require("./Style")
local JexpTags = require("./Small/JexpTags")
local Constants = require("../Constants")

local getClassPropMap = require("./Small/GetClassPropMap")

local addTag, removeTag = game.AddTag, game.RemoveTag

local var = Style.var
local rule = Style.rule
local rawindex = RawInst.rawindex
local rawnewindex = RawInst.rawnewindex
local index = RawInst.index

local profilebegin, profileend = debug.profilebegin, debug.profileend

type ExplorerFrame = Types.ExplorerFrame
type ExplorerEntity = Types.ExplorerEntity
type Manager = Types.Manager

local GLOBAL_FRAME_CACHE_SIZE = 500  -- L2 cache: large, slower (parented to nil)
local globalFramePool = {}

local function setFrameSelected(Manager: Manager, frame: ExplorerFrame, selected: boolean)
	local frameInst = assert(Manager.frameOf(frame))
	
	profilebegin("ExplorerFrame::ToggleSelection")
	if selected then
		frameInst:AddTag("JEXP_Selected")
	else
		frameInst:RemoveTag("JEXP_Selected")
	end
	profileend()
end

local function switchSelection(Manager: Manager, entity: ExplorerEntity, isCtrlHeld: boolean, isShiftHeld: boolean)
	profilebegin("Jexplorer::toggleSelection")
	local VirtualScroller = Manager.VirtualScroller
	local HierarchyState = Manager.HierarchyState
	local ExplorerFrame = Manager.ExplorerFrame
	local components = Manager.Components
	local state = Manager.WidgetState
	local world = state.World

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
		local range = Manager.HierarchyState.getEntitiesBetween(Manager, state.LastSelectedEntity, entity)
		profilebegin("Jexplorer::toggleSelection::shiftSelect::addSelectedComponents")
		for _, eid in range do
			world:add(eid, components.Selected)
		end
		profileend()
	else
		-- Normal click
		for entityId in world:query(components.Instance, components.Selected):iter() do
			world:remove(entityId, components.Selected)
		end

		world:add(entity, components.Selected)
		state.LastSelectedEntity = entity
	end

	ExplorerFrame.updateSelectionVisuals(Manager, true)
	VirtualScroller.update(Manager, false)
	profileend()
end

local function createExplorerFrame(Manager: Manager, frame: Instance & any)
	local VirtualScroller = Manager.VirtualScroller
	local HierarchyState = Manager.HierarchyState
	local ExplorerFrame = Manager.ExplorerFrame
	local components = Manager.Components
	local state = Manager.WidgetState
	local world = state.World
	
	local cleanup = Manager.CleanupFns
	local frameWorld = state.FrameWorld
	local jexplorerUi = state.JExplorerUI

	local main = frame.Main

	local iconImage = main.ClassIcon
	local instanceName: TextBox = main.InstanceName
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
		packageIconConns = {}
	}

	local frameEntity = frameWorld:entity()
	Jecs.bulk_insert(frameWorld, frameEntity, {
		components.Instance,
		components.Connections,
		components.Entity,
		components.FrameState,
		components.FRAMEWORLD_Main
	}, {
		frame,
		connections,
		nil,
		frameState,
		main
	})

	Manager.FrameToInstanceFrame[frame] = frameEntity
	overlayFrame:AddTag("JEXP_Hover")
	
	local currentTypingConn: RBXScriptConnection?

	connections:extend(cleanup.call, {
		function()
			for _, v in frameState.packageIconConns do
				v:Disconnect()
			end
			table.clear(frameState.packageIconConns)
			if currentTypingConn then
				currentTypingConn:Disconnect()
			end
		end
	})
	
	connections:add_many({
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
					Manager.setExplorerEntitiesAsSelection({entity}, true)
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
				
				task.defer(function()
					frameState.isLMBActive = true
				end)
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
					switchSelection(Manager, entity, isCtrlHeld, isShiftHeld)
					return -- Don't proceed to drag logic
				elseif isCtrlHeld then
					-- Ctrl+click on selected item - mark for deselection on mouse up
					frameState.shouldDeselect = true
					return -- Don't start drag
				elseif isShiftHeld then
					-- Shift+click on selected item - handle shift selection
					switchSelection(Manager, entity, isCtrlHeld, isShiftHeld)
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
				Manager.startDraggingSelected()
			end
		end),

		selectInstanceButton.InputEnded:Connect(function(input)
			local entity = frameWorld:get(frameEntity, components.Entity)
			if not entity then return end

			local instance = world:get(entity, components.Instance)
			if not instance then return end

			if input.UserInputState ~= Enum.UserInputState.End then return end
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
			
			task.defer(function()
				frameState.isLMBActive = false
			end)

			-- Handle deselection for ctrl+click
			if frameState.shouldDeselect then
				world:remove(entity, components.Selected)
				ExplorerFrame.updateSelectionVisuals(Manager, true)
				frameState.shouldDeselect = false
				return
			end
			-- If we have multiple selections and this was just a click (not drag), 
			-- then deselect others and select only this one
			if not state.IsDragging and frameState.hasBeenSelected and #state.CurrentSelection > 1 then
				local isCtrlHeld = Manager.isKeyDown(Enum.KeyCode.LeftControl)
				local isShiftHeld = Manager.isKeyDown(Enum.KeyCode.LeftShift)

				if not isCtrlHeld and not isShiftHeld then
					-- Normal click on multi-selection - select only this one
					for entityId in world:query(components.Instance, components.Selected):iter() do
						world:remove(entityId, components.Selected)
					end
					world:add(entity, components.Selected)
					state.LastSelectedEntity = entity
					
					ExplorerFrame.updateSelectionVisuals(Manager, true)
					VirtualScroller.update(Manager, false)
				end
			end
		end),
		selectInstanceButton.MouseEnter:Connect(function()
			local entity = frameWorld:get(frameEntity, components.Entity)
			if not entity then return end
			
			local bounds: Vector2 = rawindex(instanceName, "TextBounds")
			local x = instanceName:GetStyled("Position").X.Offset + bounds.X
			insertInstanceButton.Position = UDim2.new(0, x + 10, 0.5)
			
			insertInstanceButton.Visible = true
			if state.IsDragging then
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

			Manager.InsertMenu.show(Manager, insertInstanceButton.AbsolutePosition, insertInstanceButton.AbsoluteSize)
		end),
		instanceName.Focused:Connect(function()
			currentTypingConn = instanceName:GetPropertyChangedSignal("TextBounds"):Connect(function()
				local bounds: Vector2 = rawindex(instanceName, "TextBounds")
				local x = instanceName:GetStyled("Position").X.Offset + bounds.X
				insertInstanceButton.Position = UDim2.new(0, x + 10, 0.5)
				frame.Main.PendingChanges.Position = UDim2.new(0, x + 26, 0.5)
			end)
		end),
		instanceName.FocusLost:Connect(function()
			if currentTypingConn then
				currentTypingConn:Disconnect()
			end
			instanceName.TextEditable = false
			instanceName.Interactable = false
		end),
		arrow.Activated:Connect(function()
			local entity = frameWorld:get(frameEntity, components.Entity)
			if not entity then return end

			--toggleExpand(world, entity, not isEntityExpanded(world, entity), true)
			local expanded = Manager.isExplorerEntityExpanded(entity)
			if expanded then
				world:remove(entity, components.QueryExpanded)
				world:remove(entity, components.Expanded)
				
				HierarchyState.invalidateEntityStateCache(entity)
				ExplorerFrame.updateCollapsedVisuals(Manager)
			else
				world:add(entity, components.Expanded)
				
				HierarchyState.invalidateEntityStateCache(entity)
				ExplorerFrame.updateExpandedVisuals(Manager)
			end
			
			VirtualScroller.update(Manager, false)
		end)
	})

	return frameEntity
end

local ExplorerFrame = {} :: Types.ExplorerFrameLib

function ExplorerFrame.fillGlobalPoolToLimit(Manager)
	profilebegin("Jexplorer::fillInstanceFramePoolToLimit")
	if #globalFramePool >= GLOBAL_FRAME_CACHE_SIZE then return end

	local framesToCreate = GLOBAL_FRAME_CACHE_SIZE - #globalFramePool
	for _ = 1, framesToCreate do
		local clone = UITemplates.InstanceFrame()

		local frame = createExplorerFrame(Manager, clone)
		clone.Visible = true
		--clone.Parent = Manager.WidgetState.JExplorerUI.InstanceTree

		table.insert(globalFramePool, frame)
	end
	profileend()
end

function ExplorerFrame.getExplorerFrame(Manager): ExplorerFrame
	profilebegin("Jexplorer::allocateExplorerFrame")
	
	local state = Manager.WidgetState
	local components = Manager.Components
	local frameWorld = state.FrameWorld
	
	if #globalFramePool == 0 then
		-- Attempt to reuse any pending frames before creating new ones
		local success = ExplorerFrame.flushFrameReuseQueue(Manager)
		if not success or #globalFramePool == 0 then
			ExplorerFrame.fillGlobalPoolToLimit(Manager)
		end
	end
	local reused = table.remove(globalFramePool)::any
	--local frameInst = Manager.frameOf(reused)
	--if frameInst then
	--	frameWorld:set(reused, components.FRAMEWORLD_FrameSetParentTicket, {newParent = state.JExplorerUI.InstanceTree})
	--end
	profileend()
	return reused
end

function ExplorerFrame.flushFrameReuseQueue(Manager)
	profilebegin("Jexplorer::flushFrameReuseQueue")
	
	local state = Manager.WidgetState
	local world = state.World
	local components = Manager.Components
	local tounassign = {}
	local tomutate = {}
	
	local query = Jecs.cached_query(world, components.FrameReuseTicket)
	
	local touI = 1
	local tomuI = 1
	local fpI = #globalFramePool + 1
	local move = table.move
	
	local any = false
	for entity, ticketData in query:iter() do
		any = true
		
		local frame = ticketData.frame
		world:remove(entity, components.FrameReuseTicket)
		
		tounassign[touI] = frame
		globalFramePool[fpI] = frame
		tomutate[tomuI] = entity
		
		fpI += 1
		touI += 1
		tomuI += 1
	end
	if not any then profileend() return false end
	
	for _, entity in tomutate do
		world:remove(entity, components.Frame)
		--local entityChildren = Manager.HierarchyState.getChildren(entity)
		--if entityChildren then
		--	for _, v in entityChildren do
		--		local frame = world:get(v, components.Frame)
		--		if not frame then continue end
				
		--		world:set(v, components.FrameReuseTicket, {frame = frame})
		--	end
		--end
	end
	for _, frame in tounassign do
		ExplorerFrame.assignExplorerFrame(Manager, frame, nil, nil, false)
	end
	
	ExplorerFrame.flushExplorerFrameTagAssignQueue(Manager)
	
	profileend()
	return true
end

function ExplorerFrame.stepFlushFrameSetParentQueue(Manager)
	local state = Manager.WidgetState
	local components = Manager.Components
	local world = state.World
	local frameWorld = state.FrameWorld
	
	local any = false
	local query = Jecs.cached_query(frameWorld, components.Instance, components.FRAMEWORLD_FrameSetParentTicket)
	
	profilebegin("Jexplorer::stepFlushFrameSetParentQueue")
	
	local withoutParents: {Instance} = {}
	local withParents: {{inst: Instance, parent: Instance}} = {}
	local n = 0
	
	local stepSize = Manager.getSetting("FrameSetParentFlushStep")
	for frame: ExplorerFrame, frameInst, ticketData in query:iter() do
		if n >= stepSize then break end
		any = true
		n += 1
		frameWorld:remove(frame, components.FRAMEWORLD_FrameSetParentTicket)
		if ticketData.newParent then
			table.insert(withParents, {inst = frameInst, parent = ticketData.newParent})
		else
			table.insert(withoutParents, frameInst)
		end
	end
	
	local PARENT = "Parent"
	profilebegin("withoutParents")
	for _, v in withoutParents do
		rawnewindex(v, PARENT, nil)
	end
	profileend()
	profilebegin("withParents")
	for _, v in withParents do
		rawnewindex(v.inst, PARENT, v.parent)
	end
	profileend()
	profileend()
	
	return any
end

function ExplorerFrame.assignExplorerFrame(Manager, frame, entity, parent, parentIsGame)
	local state = Manager.WidgetState
	local components = Manager.Components
	local world = state.World
	local frameWorld = state.FrameWorld
	
	if frameWorld:get(frame, components.Entity) == entity then
		if parent and Manager.frameOf(parent) == frameWorld:parent(frame) then
			return
		end
	end

	local frameState = frameWorld:get(frame, components.FrameState)
	if not frameState then return end
	
	local frameInst = Manager.frameOf(frame)
	if not frameInst then return end
	
	frameState.isAssigning = true
	
	local main = frameWorld:get(frame, components.FRAMEWORLD_Main)
	if not main then return end
	
	local parentFrame
	if parent then
		parentFrame = world:get(parent, components.Frame)
	end
	profilebegin("InstanceFrame::Assign")
	if not entity or (not parent and not parentIsGame) or Manager.isExplorerEntityDeleted(entity) then
		frameWorld:remove(frame, components.Entity)
		local oldParent = frameWorld:parent(frame)
		if oldParent then
			frameWorld:remove(frame, Manager.ChildOf(oldParent))
		end
		main.Insert.Visible = false
		frameWorld:set(frame, components.FRAMEWORLD_FrameSetParentTicket, {newParent = nil})
		
		for _, v in frameState.packageIconConns do
			v:Disconnect()
		end
		table.clear(frameState.packageIconConns)

		frameState.isAssigning = false
		profileend()
		return
	end
	
	world:set(entity, components.Frame, frame)
	frameWorld:set(frame, components.Entity, entity)
	if parentFrame then
		frameWorld:add(frame, Manager.ChildOf(parentFrame))
	end
	local instance: Instance? = world:get(entity, components.Instance)
	if not instance then
		frameState.isAssigning = false
		return
	end
	world:set(entity, components.FrameTagAssignTicket, {frame = frame})

	local isSelected = world:has(entity, components.Selected)
	setFrameSelected(Manager, frame, isSelected)

	local sheet = Manager.Style
	local className = instance.ClassName
	local slctr = Selector.getIconSelector(nil, className)
	local icon = ClassIcon.getIcon(className)
	
	if icon and not sheet:FindRule(slctr) and not Manager.isExplorerEntityInvisible(entity) then
		local name = `ClassIcon_{className}`
		if className == "Script" or className == "LocalScript" then
			-- Do nothing, handled in default style
		else
			local image = string.match(icon.Image, "[^/]+$")
			local normalIcon = rule(name, slctr, 0, {
				ImageRectOffset = icon.ImageRectOffset,
				ImageRectSize = icon.ImageRectSize,
				Image = var(`'rbxasset://studio_svg_textures/Shared/InsertableObjects/![$Theme]/Standard/{image}'`)
			})
			local lightIcon = rule(name.."_Selected", ".JEXP_Selected "..slctr, 100, {
				ImageRectOffset = icon.ImageRectOffset,
				ImageRectSize = icon.ImageRectSize,
				Image = var(`'rbxasset://studio_svg_textures/Shared/InsertableObjects/![$SelectedTheme]/Standard/{image}'`)
			})
			normalIcon:AddTag("DontSaveRule")
			lightIcon:AddTag("DontSaveRule")
			sheet:AddRules({normalIcon, lightIcon})
		end
	end

	rawnewindex(main.InstanceName, "Text", instance.Name)

	local arrow = main.Arrow
	if world:has(entity, components.ArrowInvisible) then
		-- Handled in updateVirtualScroller
		--arrow.Visible = false
	else
		if instance == game or Manager.ChildAmountCache[entity] == 0 then
			arrow.Visible = false
		else
			arrow.Visible = true
		end
		if Manager.isExplorerEntityExpanded(entity) then
			arrow.Rotation = 0
			--frameInst.Children.Visible = true
		else
			arrow.Rotation = -90
			--frameInst.Children.Visible = false
		end
	end
	if not state.LastSelectedEntity then
		state.LastSelectedEntity = nil
	end
	frameState.isLMBActive = false
	frameState.hasBeenSelected = false
	frameState.shouldDeselect = false

	local link = instance:FindFirstChildOfClass("PackageLink")
	
	for _, v in frameState.packageIconConns do
		v:Disconnect()
	end
	table.clear(frameState.packageIconConns)
	
	if link then
		local function updatePackageIconPosition()
			local scrollingFrame = state.JExplorerUI.InstanceTree
			local containerWidth = scrollingFrame.AbsoluteSize.X
			local canvasPosition = scrollingFrame.CanvasPosition.X
			
			local frameCanvasX = frameInst.Position.X.Offset
			local visibleRightEdge = canvasPosition + containerWidth
			local distanceToEdge = visibleRightEdge - frameCanvasX

			local padding = 20
			main.PackageLinkIcon.Position = UDim2.new(
				0,
				distanceToEdge - padding,
				0.5,
				0
			)
		end
		frameState.packageIconConns = {
			state.JExplorerUI.InstanceTree:GetPropertyChangedSignal("CanvasPosition"):Connect(updatePackageIconPosition),
			frameInst:GetPropertyChangedSignal("Position"):Connect(updatePackageIconPosition)
		}
		updatePackageIconPosition()
		main.PackageLinkIcon.Visible = true
	else
		main.PackageLinkIcon.Visible = false
	end
	
	profileend()
	frameState.isAssigning = false
end

function ExplorerFrame.queueForExplorerFrameReuse(Manager, frame)
	local state = Manager.WidgetState
	local frameWorld = state.FrameWorld
	local world = state.World
	local components = Manager.Components

	local currentEntity, frameInst: any = frameWorld:get(frame, components.Entity, components.Instance)
	if not currentEntity and frameInst then
		return
	end
	if not currentEntity and not frameInst then return end
	
	profilebegin("ExplorerFrame::Reuse");
	if currentEntity and not world:has(currentEntity, components.FrameReuseTicket) then
		world:set(currentEntity, components.FrameReuseTicket, {frame = frame})
		frameWorld:remove(frame, components.Entity)
	end

	profileend()
end

function ExplorerFrame.initializeFrameCaches(Manager)
	ExplorerFrame.fillGlobalPoolToLimit(Manager)  -- Fill L2
	--ExplorerFrame.fillLocalPoolToLimit(Manager)  -- Fill L1 from L2
end

function ExplorerFrame.updateSelectionVisuals(Manager, updateSelection)
	profilebegin("Jexplorer::updateSelectionVisuals")
	local state = Manager.WidgetState
	local world = state.World
	local components = Manager.Components

	table.clear(state.CurrentSelection)
	local currentSelection = {}

	profilebegin("Jexplorer::updateSelectionVisuals::deselectFrames")
	for entityId, frame in world:query(components.Frame):without(components.Selected):iter() do
		setFrameSelected(Manager, frame, false)
	end
	profileend()
	
	profilebegin("Jexplorer::updateSelectionVisuals::mainLoop")
	for entityId, instance in world:query(components.Instance, components.Selected):iter() do
		local frame = world:get(entityId, components.Frame)

		if typeof(instance) == "Instance" then
			table.insert(currentSelection, instance)
		end
		table.insert(state.CurrentSelection, entityId)

		if frame then
			setFrameSelected(Manager, frame, true)
		end
	end
	ExplorerFrame.flushExplorerFrameTagAssignQueue(Manager)
	profileend()
	if updateSelection then
		profilebegin("Jexplorer::updateSelectionVisuals::setSelection")
		game.Selection:Set(currentSelection)
		profileend()
	end
end

function ExplorerFrame.updateExpandedVisuals(Manager)
	profilebegin("Jexplorer::toggleExpand")

	local components = Manager.Components
	local state = Manager.WidgetState
	local world = state.World
	
	local function update(entity: ExplorerEntity, instance: Instance, frame: ExplorerFrame)
		local frameInst = Manager.frameOf(frame)
		if not frameInst then return end

		if instance == game then return end
		
		Manager.VirtualScroller.invalidateEntityHeightCache(Manager, entity)
	end
	for entity, instance, frame in world:query(components.Instance, components.Frame, components.Expanded):iter() do
		update(entity, instance, frame)
	end
	for entity, instance, frame in world:query(components.Instance, components.Frame, components.QueryExpanded):iter() do
		update(entity, instance, frame)
	end
	
	profileend()
end

function ExplorerFrame.updateCollapsedVisuals(Manager)
	profilebegin("Jexplorer::toggleExpand")
	
	local components = Manager.Components
	local state = Manager.WidgetState
	local world = state.World
	
	local components = Manager.Components
	for entity, instance, frame in world:query(components.Instance, components.Frame):without(components.Expanded, components.QueryExpanded):iter() do
		local frameInst = Manager.frameOf(frame)
		if not frameInst then continue end

		--local children = frameInst.Children
		--children.Visible = false
		
		world:remove(entity, components.Expanded)
		world:remove(entity, components.QueryExpanded)

		frameInst.Main.Arrow.Rotation = -90

		local function reuseChildren(entity: ExplorerEntity)
			for child, frame, _ in world:query(components.Frame, Manager.ChildOf(entity)):iter() do
				ExplorerFrame.queueForExplorerFrameReuse(Manager, frame)
				state.FrameWorld:set(frame, components.FRAMEWORLD_FrameSetParentTicket, {newParent = nil})
				if not Manager.isExplorerEntityExpanded(child) then continue end
				reuseChildren(child)
			end
		end
		reuseChildren(entity)
		
		repeat
			local success = ExplorerFrame.stepFlushFrameSetParentQueue(Manager)
		until not success
		
		Manager.VirtualScroller.invalidateEntityHeightCache(Manager, entity)
	end
	
	profileend()
end

function ExplorerFrame.flushExplorerFrameTagAssignQueue(Manager)
	local state = Manager.WidgetState
	local components = Manager.Components
	local world = state.World
	local frameWorld = state.FrameWorld

	local query = Jecs.cached_query(world, components.FrameTagAssignTicket)
	local any = false
	profilebegin("Jexplorer::flushTagAssignQueue")
	
	for entity, ticketData in query:iter() do
		world:remove(entity, components.FrameTagAssignTicket)
		any = true
		local frame = ticketData.frame

		local frameInst = Manager.frameOf(frame)
		if not frameInst then continue end
		local frameState = frameWorld:get(frame, components.FrameState)
		if not frameState then continue end
		local inst = world:get(entity, components.Instance)
		if not inst then continue end
		
		local hasPendingChanges = world:has(entity, components.PendingChanges)
		local scriptErrors = world:get(entity, components.ScriptErrors)
		local scriptWarns = world:get(entity, components.ScriptWarns)
		
		local newTags = {}
		if typeof(inst) == "Instance" then
			local propmap = getClassPropMap(Manager.ClassNameCache[entity])
			for _, prop in Constants.TaggedProperties do
				if not propmap[prop] then continue end
				
				local value = rawindex(inst, prop)
				table.insert(newTags, JexpTags.getTaggedPropertyTag(prop, typeof(value) == "EnumItem" and value.Name or tostring(value)))
			end
		end
		for _, tag in inst:GetTags() do
			table.insert(newTags, `JEXP_TAG_{tag}`)
		end
		local hasScriptError = scriptErrors and #scriptErrors > 0
		local hasScriptWarn = not hasScriptError and scriptWarns and #scriptWarns > 0

		if hasScriptError then
			table.insert(newTags, "JEXP_ScriptError")
		elseif hasScriptWarn then
			table.insert(newTags, "JEXP_ScriptWarn")
		end
		local newTagSet = {}
		for _, tag in newTags do
			newTagSet[tag] = true
		end
		local tagsToAdd = {}
		local tagsToRemove = {}
		local addCount = 0
		local removeCount = 0

		for _, oldTag in frameState.tagsToRemove do
			if not newTagSet[oldTag] then
				removeCount += 1
				tagsToRemove[removeCount] = oldTag
			end
		end

		for _, newTag in newTags do
			local alreadyHas = false
			for _, oldTag in frameState.tagsToRemove do
				if oldTag == newTag then
					alreadyHas = true
					break
				end
			end
			if not alreadyHas then
				addCount += 1
				tagsToAdd[addCount] = newTag
			end
		end
		if hasPendingChanges ~= frameInst.Main.PendingChanges.Visible then
			frameInst.Main.PendingChanges.Visible = hasPendingChanges
		end
		if removeCount > 0 or addCount > 0 then
			for i = 1, removeCount do
				removeTag(frameInst, tagsToRemove[i])
			end
			for i = 1, addCount do
				addTag(frameInst, tagsToAdd[i])
			end
		end
		frameState.tagsToRemove = newTags
	end

	profileend()
	return any
end
return ExplorerFrame