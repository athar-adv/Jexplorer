--!strict
--!optimize 2

local global = shared
local plugin = script:FindFirstAncestorOfClass("Plugin")

local HttpService = game:GetService("HttpService")
local ReflectionService = game:GetService("ReflectionService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local StudioService = game:GetService("StudioService")
local SerializationService = game:GetService("SerializationService")
local CollectionService = game:GetService("CollectionService")
local ScriptEditorService = game:GetService("ScriptEditorService")
local TextService = game:GetService("TextService")

local Jecs = require("./Jecs")
local Types = require("./Types")

type World = Types.World
type ExplorerFrame = Types.ExplorerFrame
type ExplorerEntity = Types.ExplorerEntity
type Tab = Types.Tab

local ItemGroup = require("./Shared/Vendor/ItemGroup")
local ColorPicker = require("./Shared/Vendor/PluginColorPicker")
local PluginUI = require("./Shared/PluginUI")
local UDF = require("./Shared/UDF")
local JQL = require("./Shared/JQL")
local Style = require("./Shared/Style")
local SavedState = require("./Shared/SavedState")
local UITemplates = require("./Shared/UITemplates")
local ClassIcon = require("./Shared/Small/ClassIcon")
local RawInst = require("./Shared/Small/RawInst")
local InstanceRecord = require("./Shared/Small/InstanceRecord")
local PluginManager = require("./Shared/PluginManager")
local xyz = require("./Shared/Small/xyz")
local getClassPropMap = require("./Shared/Small/GetClassPropMap")
local getClampedXY = require("./Shared/Small/GetClampedXY")

local UniPlugin = require("./UniPlugin")(plugin)

local SettingEditor = require("./Editors/SettingEditor")
local StyleEditor = require("./Editors/StyleEditor")
local VersionControl = require("./Editors/VersionControl")
local PropertyEditor = require("./Editors/PropertyEditor")
local OrderEditor = require("./Editors/OrderEditor")
local StateEditor = require("./Editors/StateEditor")
local InstanceVisibilityEditor = require("./Editors/InstanceVisibilityEditor")
local ContextMenuEditor = require("./Editors/ContextMenuEditor")
local JextensionEditor = require("./Editors/JextensionEditor")
local HierarchyState = require("./Shared/HierarchyState")
local ExplorerFrame = require("./Shared/ExplorerFrame")
local VirtualScroller = require("./Shared/VirtualScroller")
local InsertMenu = require("./Shared/InsertMenu")
local CreateOptionsDropdown = require("./Shared/CreateOptionsDropdown")

local rule = Style.rule
local cleanup = ItemGroup.cleanup
local profilebegin, profileend = debug.profilebegin, debug.profileend
local beginRecording, finishRecording = InstanceRecord.beginRecording, InstanceRecord.finishRecording
local getId = PluginUI.getId
local rawnewindex = RawInst.rawnewindex

local downKeys: {[Enum.KeyCode]: boolean?} = {}
local activeInputs: {[Enum.UserInputType]: boolean?} = {}

local onTagAddedListeners = {}
local onTagRemovedListeners = {}

local classComponentCache: {[string]: {Jecs.Id}} = {}

local studioSettings = settings().Studio
local pluginMouse = plugin:GetMouse()

local sharedTabState: {
	currentlyPickingTabRoots: Tab?,
	tabInsertListener: RBXScriptConnection?,
	currentlyOpenTab: Tab?,
	contextTargetTab: Tab?
} = {
	currentlyPickingTabRoots = nil,
	tabInsertListener = nil,
	currentlyOpenTab = nil,
	contextTargetTab = nil
}

local PLACE_ID = tostring(game.PlaceId)
local IS_EDIT = game:GetService("RunService"):IsEdit()
local ID_ATTR = "JexId"
local ID_FORMAT = "JexId(%s)"

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
		FRAMEWORLD_Main = comp(),
		QUERYWORLD_ComponentHash = comp(),

		Instance = comp(),
		Frame = comp(),
		Entity = comp(),
		FrameState = comp(),
		FrameIconColor = comp(),

		Connections = comp(),
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
	QueryAttrMap = {},
	AttributeUsageAmounts = {},
	
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
	IdToInstance = {},
	InstanceToId = {},
	IdToObjectValue = {},
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

local function checkCombo(str: string): boolean
	str = str:gsub("%s+", "")

	local function parseExpr(s, i): (any, number)
		-- Forward declaration for mutual recursion
		local function parseAtom(i: number): (any, number)
			if s:sub(i, i) == "(" then
				local val, ni = parseExpr(s, i + 1)
				if s:sub(ni, ni) ~= ")" then
					error("Expected ')' at position " .. ni)
				end
				return val, ni + 1
			end

			-- Read key name (letters, digits, underscores)
			local key = s:match("^([%w_]+)", i)
			if not key then
				error("Expected key name at position " .. i)
			end

			local enumVal = Enum.KeyCode[key]
			local result = enumVal ~= nil and Manager.isKeyDown(enumVal)
			return result, i + #key
		end

		local function parseAnd(i): (any, number)
			local left, ni = parseAtom(i)
			while s:sub(ni, ni) == "&" do
				local right, nni = parseAtom(ni + 1)
				left = left and right
				ni = nni
			end
			return left, ni
		end

		local left, ni = parseAnd(i)
		while s:sub(ni, ni) == "|" do
			local right, nni = parseAnd(ni + 1)
			left = left or right
			ni = nni
		end
		return left, ni
	end

	local ok, result = pcall(function()
		local val, _ = parseExpr(str, 1)
		return val
	end)

	return ok and result or false
end

local pendingKeybind: thread? = nil
local pendingCombo: string? = nil
local pendingCount: number = -1
local pendingAction: (() -> ())? = nil

local function checkKeybinds(keybinds: {[string]: () -> ()}, input: InputObject)
	local function countKeys(str: string): number
		local count = 0
		for _ in str:gmatch("[%w_]+") do
			count += 1
		end
		return count
	end

	local triggerKey = input.KeyCode.Name

	local bestCombo: string? = nil
	local bestCount = -1
	local bestAction: (() -> ())? = nil

	for combo, action in keybinds do
		local containsTrigger = false
		for token in combo:gmatch("[%w_]+") do
			if token == triggerKey then
				containsTrigger = true
				break
			end
		end
		if not containsTrigger then continue end

		if checkCombo(combo) then
			local count = countKeys(combo)
			if count > bestCount then
				bestCount = count
				bestCombo = combo
				bestAction = action
			end
		end
	end

	if not bestCombo then return end

	-- Check if any combo in the table is a strict superset of the matched one
	-- (i.e. contains all the same key tokens plus more)
	local function getTokenSet(str: string): {[string]: boolean}
		local set = {}
		for token in str:gmatch("[%w_]+") do
			set[token] = true
		end
		return set
	end

	local matchedTokens = getTokenSet(bestCombo)
	local hasCompetitor = false

	for combo, _ in keybinds do
		if combo == bestCombo then continue end
		local tokens = getTokenSet(combo)
		local tokenCount = countKeys(combo)
		if tokenCount <= bestCount then continue end

		-- Check if matched combo's tokens are all present in this longer combo
		local isSuperset = true
		for token in pairs(matchedTokens) do
			if not tokens[token] then
				isSuperset = false
				break
			end
		end

		if isSuperset then
			hasCompetitor = true
			break
		end
	end

	if hasCompetitor then
		-- A longer combo exists that could still be triggered, wait and see
		if pendingCombo and bestCount > pendingCount then
			if pendingKeybind then
				task.cancel(pendingKeybind)
				pendingKeybind = nil
			end
		elseif pendingCombo and bestCount <= pendingCount then
			return
		end

		pendingCombo = bestCombo
		pendingCount = bestCount
		pendingAction = bestAction

		pendingKeybind = task.delay(0.1, function()
			pendingKeybind = nil
			pendingCombo = nil
			pendingCount = -1
			pendingAction = nil
			if bestAction then
				bestAction()
			end
		end)
	else
		-- No competitor, fire immediately and cancel any pending lesser combo
		if pendingKeybind then
			task.cancel(pendingKeybind)
			pendingKeybind = nil
			pendingCombo = nil
			pendingCount = -1
			pendingAction = nil
		end
		if bestAction then
			bestAction()
		end
	end
end

local function truncate(num: number)
	return string.format("%.2f", num)
end

local function asnumber(x)
	return assert(tonumber(x))
end

type diff = {[any]: {nested: false, old: any?, new: any?} | {nested: true, [any]: diff}}
local function deepDiff(a: {[any]: any}, b: {[any]: any}): diff
	local diff: {[any]: any} = {}

	-- Keys in a
	for k, v in a do
		local bv = b[k]
		if type(v) == "table" and type(bv) == "table" then
			local nested: {[any]: any} = deepDiff(v, bv)
			if next(nested) ~= nil then
				nested.nested = true
				diff[k] = nested
			end
		elseif v ~= bv then
			diff[k] = { nested = false, old = v, new = bv }
		end
	end

	-- Keys only in b
	for k, v in b do
		if a[k] == nil then
			diff[k] = { nested = false, old = nil, new = v }
		end
	end

	return diff
end

local function findOrCreateInstance(parent: Instance, name: string, classIfNotFound: string)
	local child = parent:FindFirstChild(name)
	if child then return child end
	local new = Instance.new(classIfNotFound)
	new.Name = name
	new.Parent = parent
	return new
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

local pathClickConnection: RBXScriptConnection?
local pathAncestryChangedConns: {RBXScriptConnection} = {}
local function refreshPathBar(instances: {Instance}, state: Types.WidgetState, components: typeof(Manager.Components))
	local world = state.World
	local jexplorerUi = state.JExplorerUI
	local jexplorerWidget = state.Widget
	local topbar = jexplorerUi.Topbar
	local pathSegments = topbar.PathBar.Segments

	if state.OverridePathBarText then
		local pathButton = pathSegments.PathSegment
		pathButton.Text = state.OverridePathBarText
		return
	end

	if pathClickConnection then
		pathClickConnection:Disconnect()
	end
	for _, v in pathAncestryChangedConns do
		v:Disconnect()
	end
	if #instances == 0 then
		local pathButton = pathSegments.PathSegment
		pathButton.Text = ""
		Manager.setExplorerEntitiesAsSelection({}, false)
		return
	end

	-- Update path bar
	local commonAncestor = getCommonAncestor(instances)
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
		for _, inst in instances do
			local conn = inst.AncestryChanged:Once(function()
				refreshPathBar(instances, state, components)
			end)
			table.insert(pathAncestryChangedConns, conn)
		end

		pathButton.Text = table.concat(pathParts, " / ")
		pathSegments.CanvasPosition = pathSegments.AbsoluteCanvasSize
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
	return Jecs.pair(Jecs.ChildOf, c) :: Jecs.Pair<any, any>
end

local function getPropertyCt(world: World, propName: string)
	local ct = Manager.QueryCtMap[propName]
	if not ct then
		ct = world:entity()
		Manager.QueryCtMap[propName] = ct
	end
	return ct
end

local function createPluginAction(actionId: string, text: string, statusTip: string, iconId: string?)
	local success
	local action: PluginAction
	
	while true do
		success, action = pcall(function()
			return plugin:CreatePluginAction(getId(actionId), text, "[Jexplorer] "..statusTip, iconId, true)
		end)
		if success then break end
		warn(`Failed to create PluginAction '{actionId}' with error '{action}', retrying...`)
		task.wait(0.5)
	end
	action.Name = actionId
	--action.Parent = Manager.Storage.pluginActions
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

function Manager.triggerDuplicateTargetWithIncrementName()
	local state = Manager.WidgetState
	local world = state.World
	local components = Manager.Components
	local id = ChangeHistoryService:TryBeginRecording("Clone", "Clone")
	profilebegin("Jexplorer::D (duplicate with increment name)")

	-- Pre-scan: find the highest existing number for each base name per parent
	-- so all clones get consistent incremented names even in a batch
	local nameCounters: {[Instance]: {[string]: number}} = {} -- [parent][baseName] = nextNumber

	local function getBaseName(name)
		return name:match("^(.*%D)(%d+)$") or name, nil
	end

	local function initCounterForParent(parentInstance, baseName)
		if not nameCounters[parentInstance] then
			nameCounters[parentInstance] = {}
		end
		if nameCounters[parentInstance][baseName] then
			return
		end

		local maxNum = 0
		for _, sibling in parentInstance:GetChildren() do
			local sibBase, sibNum = sibling.Name:match("^(.*%D)(%d+)$")
			if sibBase == baseName and sibNum then
				local n = tonumber(sibNum)
				if n and n > maxNum then
					maxNum = n
				end
			end
		end
		nameCounters[parentInstance][baseName] = maxNum + 1
	end

	for _, entity in state.CurrentSelection do
		local parent = Manager.parentOf(entity)
		if parent == nil then continue end
		local instance = world:get(entity, components.Instance)
		if not instance then continue end
		
		local baseName
		local _baseName, numPart = instance.Name:match("^(.*%D)(%d+)$")
		if not _baseName then
			-- Name has no trailing number (e.g. "Part"), treat whole name as base
			baseName = instance.Name
		else
			baseName = _baseName
		end

		world:add(parent, components.AncestryLocked)
		local clone = instance:Clone()
		clone.Parent = instance.Parent
		
		local incrementNameIfNoNumPart = Manager.getSetting("IncrementNamesWithNoNumberSuffix")
		
		if clone.Parent and (numPart ~= nil or (numPart == nil and incrementNameIfNoNumPart)) then
			initCounterForParent(clone.Parent, baseName)
			local nextNum = nameCounters[clone.Parent][baseName]

			clone.Name = baseName .. nextNum
			nameCounters[clone.Parent][baseName] = nextNum + 1
		end

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

function Manager.getOrCreateInstId(inst)
	local id = Manager.InstanceToId[inst]
	if id then return id end
	
	local id = ID_FORMAT:format(HttpService:GenerateGUID(false))
	Manager.InstanceToId[inst] = id
	Manager.IdToInstance[id] = inst
	
	local obj = Instance.new("ObjectValue")
	obj.Value = inst
	obj:SetAttribute(ID_ATTR, id)
	obj.Parent = Manager.Storage.idObjects
	
	Manager.IdToObjectValue[id] = obj
	
	return id
end

function Manager.getInstId(inst)
	return Manager.InstanceToId[inst]
end

function Manager.getInstFromId(id)
	return Manager.IdToInstance[id]
end

function Manager.getTempId(inst)
	local id = Manager.InstanceToTempId[inst]
	if id then return id end
	
	local id = inst:GetDebugId()
	Manager.InstanceToTempId[inst] = id
	Manager.TempIdToInstance[id] = inst
	
	return id
end

function Manager.getInstFromTempId(id)
	return Manager.TempIdToInstance[id]
end

function Manager.getSetPropertyDragInfo(instances, propName)
	local ids = {}
	for _, v in instances do
		table.insert(ids, Manager.getTempId(v))
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
			table.insert(instances, assert(Manager.getInstFromTempId(id)))
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

	--state.IsDragging = true
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
	local props = getClassPropMap(className)
	if not props then
		classComponentCache[className] = components
		return components
	end

	for k, info in props do
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

local function getColorBrightness(color)
	if typeof(color) ~= "Color3" then
		error("Cannot get brightness of non-Color3 value")
	end
	-- Use luminance formula: 0.299*R + 0.587*G + 0.114*B (scaled to 0-1)
	return (0.299 * color.R + 0.587 * color.G + 0.114 * color.B)
end

local function convertToContrastCategory(str: string, light: string, dark: string, contrast: string)
	if str:match(light) then
		str = str:gsub(light, contrast)
	end
	if str:match(dark) then
		str = str:gsub(dark, contrast)
	end
	return str
end

local function getTabImageIcon(tab: Tab, oldIcon: string)
	local iconLabel = tab.IconLabel
	local icon
	if sharedTabState.currentlyOpenTab == tab then
		local backgroundColor: Color3 = Manager.Style:GetToken("SelectedColor")
		if getColorBrightness(backgroundColor) > 0.5 then
			-- Background is light so icon is dark
			-- Light mode icon is dark
			icon = convertToContrastCategory(oldIcon, "/Light/", "/Dark/", "/Light/")
		else
			icon = convertToContrastCategory(oldIcon, "/Light/", "/Dark/", "/Dark/")
		end
	else
		local backgroundColor: Color3 = tab.TabFrame:GetStyled("BackgroundColor3")
		if getColorBrightness(backgroundColor) > 0.5 then
			-- Background is light so icon is dark
			-- Light mode icon is dark
			icon = convertToContrastCategory(oldIcon, "/Light/", "/Dark/", "/Light/")
		else
			icon = convertToContrastCategory(oldIcon, "/Light/", "/Dark/", "/Dark/")
		end
	end
	return icon
end

function Manager.registerTab(name, icon, stored, registerIntoTabs)
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
	local iconLabel = assert(tabFrame:FindFirstChild("Icon")) :: ImageLabel
	
	iconLabel.Image = icon

	nameBox.Text = name
	local bounds = nameBox.TextBounds
	nameBox.Size = UDim2.new(0, bounds.X, 1, 0)

	local button = assert(tabFrame:FindFirstChild("Button")) :: TextButton

	tabFrame.Parent = tabBar.Tabs

	local tab = {
		Roots = stored,
		Name = name,
		Icon = icon,
		IconColor = Color3.fromRGB(255, 255, 255),
		IconLabel = iconLabel,

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

		state.TreeScroller.CanvasPosition = Vector2.zero
		
		local listener = sharedTabState.tabInsertListener
		if listener then
			listener:Disconnect()
			sharedTabState.tabInsertListener = nil
			local pickingTab = sharedTabState.currentlyPickingTabRoots
			if pickingTab then
				tabFrame:RemoveTag("JEXP_SelectingRoots")
			end
			state.OverridePathBarText = nil
			refreshPathBar(game.Selection:Get(), state, components)
			sharedTabState.currentlyPickingTabRoots = nil
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
			local iconLabel = currentlyOpenTab.IconLabel
			background:RemoveTag("JEXP_SelectedColor")
			iconLabel.Image = getTabImageIcon(tab, iconLabel.Image)
			
			for _,v in currentlyOpenTab.Roots do
				local frame = world:get(v, components.Frame)
				if not frame then continue end

				ExplorerFrame.queueForExplorerFrameReuse(Manager, frame)
			end
		end
		tabFrame:AddTag("JEXP_SelectedColor")
		
		sharedTabState.currentlyOpenTab = tab
		iconLabel.Image = getTabImageIcon(tab, iconLabel.Image)

		for _, entity in stored do
			world:remove(entity, components.Invisible)
			HierarchyState.invalidateEntityStateCache(entity)
			
			world:add(entity, components.DisplayTopLevel)
			HierarchyState.updateEntityOrder(Manager, entity)
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
				sharedTabState.tabInsertListener = nil
				local pickingTab = sharedTabState.currentlyPickingTabRoots
				if pickingTab then
					tabFrame:RemoveTag("JEXP_SelectingRoots")
				end
				state.OverridePathBarText = nil
				refreshPathBar(game.Selection:Get(), state, components)
				sharedTabState.currentlyPickingTabRoots = nil
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
	
	local function updateSize()
		local text = nameBox.Text
		if text == "" then
			tabFrame.Size = UDim2.new(0, 70, 1, -2)
			nameBox.Size = UDim2.new(0, 0, 1, 0)
			return
		end

		local bounds = nameBox.TextBounds
		local textWidth = math.ceil(bounds.X) + 2

		nameBox.Size = UDim2.fromOffset(textWidth, nameBox.AbsoluteSize.Y)
		local tabWidth = textWidth + 30
		
		tabFrame.Size = UDim2.fromOffset(tabWidth, tabBar.AbsoluteSize.Y - 1)
	end
	tabConnections:add_many({
		nameBox:GetPropertyChangedSignal("Text"):Connect(updateSize),
		nameBox:GetPropertyChangedSignal("TextBounds"):Connect(updateSize),
		jexplorerUi:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateSize),
		nameBox:GetPropertyChangedSignal("Text"):Connect(function()
			tab.Name = nameBox.Text
		end),
		button.Activated:Connect(tab.Toggle),
		button.InputBegan:Connect(function(input)
			if input.UserInputState ~= Enum.UserInputState.Begin then return end
			if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end

			sharedTabState.contextTargetTab = tab
			if tab == Manager.AllTab then
				state.MiscContextMenus.AllTab.Menu:ShowAsync()
			else
				state.MiscContextMenus.Tab.Menu:ShowAsync()
			end
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
	task.delay(0.1,updateSize)
	
	return tab
end

function Manager.saveState()
	local state = Manager.WidgetState
	local world = state.World
	local ct = Manager.Components
	local curr_state = state.SavedState

	-- Collect all IDs that will be referenced in the new save
	local usedIds: {[Types.InstanceId]: true} = {}

	local savedState = table.clone(curr_state)
	savedState.data_version = SavedState.data_version
	
	local tbl; tbl = {
		save = function()
			for id in table.clone(Manager.IdToObjectValue) do
				if not usedIds[id] then
					local inst = Manager.IdToInstance[id]
					Manager.IdToInstance[id] = nil
					if inst then
						Manager.InstanceToId[inst] = nil
					end
					local obj = Manager.IdToObjectValue[id]
					Manager.IdToObjectValue[id] = nil
					if obj then
						obj:Destroy()
					end
				end
			end
			
			SavedState.save(savedState)
		end,
		all = function()
			for k, v in tbl do
				-- forgot to add k == "all" here which caused infinite recursion :sob:
				if k == "save" or k == "all" then continue end
				v()
			end
		end,
		icon_colors = function()
			savedState.icon_colors = computedtbl(function(ser)
				local icons = {}
				ser[PLACE_ID] = icons

				for entity, inst, color in world:query(components.Instance, components.FrameIconColor):iter() do
					local id = Manager.getOrCreateInstId(inst)
					icons[id] = UDF.to(color)
					usedIds[id] = true
				end
			end)
		end,
		repo_proxies = function() 
			savedState.repo_proxies = computedtbl(function(ser)
				for k, v in curr_state.repo_proxies do
					ser[k] = v
				end
				local proxies = state.RepoProxies
				ser[PLACE_ID] = {}
				for _, v in proxies do
					local id = Manager.getOrCreateInstId(v.Root)
					usedIds[id] = true
					table.insert(ser[PLACE_ID], {
						display_name = v.DisplayName,
						repo_id = v.RepoId,
						root_inst_id = id,
					})
				end
			end)
		end,
		tabs = function()
			savedState.tabs = computedtbl(function(ser)
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
						local id = Manager.getOrCreateInstId(inst)
						usedIds[id] = true
						table.insert(inst_ids, id)
					end
					table.insert(ser[PLACE_ID], {
						display_name = v.Name,
						icon = v.Icon,
						icon_color = UDF.to(v.IconColor),
						inst_ids = inst_ids
					})
				end
			end)
		end,
		versions = function()
			savedState.versions = computedtbl(function(ser)
				local inst_vers = {}
				ser[PLACE_ID] = inst_vers
				for inst, versions in VersionControl.Versions do
					local inst_id = Manager.getOrCreateInstId(inst)
					usedIds[inst_id] = true
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
			end)
		end,
		order = function()
			savedState.display_order = computedtbl(function(ser)
				ser.default_order = OrderEditor.DefaultPriority
				ser.class_order = OrderEditor.ClassPriorities
			end)
		end,
		invisible = function()
			savedState.invisible = InstanceVisibilityEditor.InvisibleClasses
		end,
		settings = function()
			savedState.settings = computedtbl(function(ser)
				for k, v in SettingEditor.Configs do
					ser[k] = UDF.to(v)
				end
			end)
		end,
		style = function()
			savedState.style = computedtbl(function(ser)
				local style = Manager.Style
				local rules: {Types.SerializedStyleRule} = {}
				local tokens = {}
				SavedState._serialize_rules(style.Rules, rules, "DontSaveRule")
				for k, v in style.Tokens do
					tokens[k] = UDF.to(v)
				end
				ser.rules = rules
				ser.tokens = tokens
			end)
		end,
	}
	return tbl
end

function Manager.loadState(savedState)
	local state = Manager.WidgetState
	local world = state.World
	local ct = Manager.Components
	state.SavedState = savedState

	return {
		icon_colors = function()
			local iconColors = savedState.icon_colors and savedState.icon_colors[PLACE_ID]
			if not iconColors then
				Manager.IconColorMap = {}
				return
			end
			local des = {}
			for k, v in iconColors do
				des[k] = UDF.from(v)
			end
			
			Manager.IconColorMap = des
		end,
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
				local tab = Manager.registerTab(t.display_name, t.icon, roots, true)
				tab.IconLabel.ImageColor3 = UDF.from(t.icon_color)
			end
		end,
		repo_proxies = function()
			local proxies = savedState.repo_proxies[PLACE_ID]
			if not proxies then return end

			for _, r in proxies do
				local inst = Manager.getInstFromId(r.root_inst_id)
				if not inst then continue end
				local proxy = VersionControl.createRepoProxy(r.display_name, r.repo_id, inst, true)
				table.insert(state.RepoProxies, proxy)
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
					if table.find(r.tags, "Default") then continue end
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
				local inst = Manager.getInstFromId(inst_id)
				if not inst then continue end
				
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
				de[inst] = de_versions
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
	components: typeof(Manager.Components)
)
	local world = state.World
	local connections = state.Connections
	local jexplorerUi = state.JExplorerUI
	local topbar = jexplorerUi.Topbar

	local tabEditName do
		tabEditName = createPluginAction(
			"EditName", "Edit Name", "Edits the name of a tab."
		)

		tabEditName.Triggered:Connect(function()
			if not sharedTabState.contextTargetTab then return end

			local box: TextBox = sharedTabState.contextTargetTab.NameBox
			box:CaptureFocus()
		end)
	end

	local tabDelete do
		tabDelete = createPluginAction(
			"TabDelete", "Delete Tab", "Deletes this tab."
		)
		
		tabDelete.Triggered:Connect(function()
			local tab = sharedTabState.contextTargetTab
			if not tab then return end
			
			tab.Remove()
		end)
	end
	
	local tabInsert do
		tabInsert = createPluginAction(
			"InsertTabRoots", "Insert Roots", "Prompts user to insert tab roots."
		)
		
		tabInsert.Triggered:Connect(function()
			local tab = sharedTabState.contextTargetTab
			if not tab then return end
			if sharedTabState.currentlyPickingTabRoots then return end
			if sharedTabState.currentlyOpenTab ~= Manager.AllTab then
				Manager.AllTab.Toggle()
			end
			
			local tabFrame = tab.TabFrame
			tabFrame:AddTag("JEXP_SelectingRoots")
			local iconLabel = tab.IconLabel
			task.defer(function()
				iconLabel.Image = getTabImageIcon(tab, iconLabel.Image)
			end)
			
			state.OverridePathBarText = "Press [Enter] to confirm selection, [Escape] to cancel."
			refreshPathBar({}, state, components)
			
			sharedTabState.currentlyPickingTabRoots = tab
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

						table.insert(tab.Roots, v)
						parentTabs[tab] = true
					end
					sink = true
				end
				if sink then
					tabFrame:RemoveTag("JEXP_SelectingRoots")
					task.defer(function()
						iconLabel.Image = getTabImageIcon(tab, iconLabel.Image)
					end)
					
					state.OverridePathBarText = nil
					refreshPathBar(game.Selection:Get(), state, components)
					Manager.setExplorerEntitiesAsSelection({}, true)
					tab.Toggle()
				end
			end) 
		end)
	end
	
	local tabEditIcon do
		tabEditIcon = createPluginAction(
			"EditIcon", "Edit Icon", "Edits the icon of a tab."
		)

		tabEditIcon.Triggered:Connect(function()
			local tab = sharedTabState.contextTargetTab
			if not tab then return end
			
			local colorBox = PluginUI.createAttributeBox(nil, "Icon Color", `{truncate(tab.IconColor.R * 255)}, {truncate(tab.IconColor.G * 255)}, {truncate(tab.IconColor.B * 255)}`)
			local iconBox = PluginUI.createAttributeBox(nil, "Icon Image", tab.Icon)
			
			local widget, cancel, confirm, close = PluginUI.createCreatorWidget("Edit Tab Icon", {
				iconBox, colorBox
			})
			Manager.Style:Link(widget)
			
			cancel:OnTrigger(function()
				close()
			end)
			confirm:OnTrigger(function()
				local icon: string = iconBox:Get()
				local r, g, b = xyz(colorBox:Get())
				local color = Color3.fromRGB(
					asnumber(r),
					asnumber(g),
					asnumber(b)
				)
				local rbxclass = icon:match("@rbxclass%((.-)%)")
				if rbxclass then
					local result = ClassIcon.getIcon(rbxclass)
					if not result then
						warn(`'@rbxclass({rbxclass})' is not a valid Roblox Class`)
					else
						icon = getTabImageIcon(tab, result.Image)
					end
				end
				
				tab.IconLabel.Image = icon
				tab.Icon = icon
				
				tab.IconLabel.ImageColor3 = color
				tab.IconColor = color
				
				close()
			end)
		end)
	end

	local tabBar = topbar.TabBar

	do
		local insertButton = PluginUI.createInsertButton(tabBar.Tabs, function()
			Manager.registerTab("Tab", "", {}, true)
		end)
		insertButton.Name = "InsertTabButton"
	end

	local renameAction do
		renameAction = createPluginAction(
			"Jexplorer_ContextMenu_Rename", "Rename", "Rename selected instance."
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
			"Jexplorer_ContextMenu_InsertFromFile", "Insert from File...", "Inserts a file into an Instance.", "rbxasset://textures/StudioSharedUI/import@2x.png"
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
			"Jexplorer_ContextMenu_InsertObject", "Insert Object...", "Inserts a chosen Instance into an Instance.", (ClassIcon.getIcon("Part")::any).Image
		)
		insertObjectAction.Triggered:Connect(function()
			local mousePos = state.Widget:GetRelativeMousePosition()
			InsertMenu.show(Manager, mousePos, Vector2.zero)
		end)
	end

	local selectChildrenAction do
		selectChildrenAction = createPluginAction(
			"Jexplorer_ContextMenu_SelectChildren", "Select Children", "Selects all children of an Instance."
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
			"Jexplorer_ContextMenu_SaveToFile", "Save to File...", "Saves an Instance as a local file."
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
			"Jexplorer_ContextMenu_SaveToRoblox", "Save to Roblox...", "Saves an Instance to Roblox."
		)
		saveToRobloxAction.Triggered:Connect(function()
			Manager.setExplorerEntitiesAsSelection(state.CurrentSelection, true)
			plugin:SaveSelectedToRoblox()
		end)
	end

	local copyAction do
		copyAction = createPluginAction(
			"Jexplorer_ContextMenu_Copy", "Copy", "Copies all Instances to your clipboard."
		)
		copyAction.Triggered:Connect(function()
			copySelection(world)
		end)
	end

	local pasteIntoAction do
		pasteIntoAction = createPluginAction(
			"Jexplorer_ContextMenu_PasteInto", "Paste Into", "Pastes all copied Instances into the first currently selected Instance."
		)
		pasteIntoAction.Triggered:Connect(function()
			pasteCopiedInstances(world)
		end)
	end

	local collapseAllAction do
		collapseAllAction = createPluginAction(
			"Jexplorer_ContextMenu_CollapseAll", "Collapse All", "Collapses all expanded descendants."
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
	
	local hideClassAction do
		hideClassAction = createPluginAction(
			"Jexplorer_ContextMenu_HideClass", "Hide Class", "Hides all Instances with the ClassName of the selected Instance."
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
			"Jexplorer_ContextMenu_Delete", "Delete", "Deletes this Instance."
		)
		deleteAction.Triggered:Connect(Manager.triggerDeleteTarget)
	end

	local escapeAction do
		escapeAction = createPluginAction(
			"Jexplorer_ContextMenu_Escape", "Escape", "Escapes this Instance."
		)
		escapeAction.Triggered:Connect(Manager.triggerEscapeTarget)
	end

	local duplicateAction do
		duplicateAction = createPluginAction(
			"Jexplorer_ContextMenu_Duplicate", "Duplicate", "Duplicates this Instance."
		)
		duplicateAction.Triggered:Connect(Manager.triggerDuplicateTarget)
	end
	local openVersionHistoryAction do
		openVersionHistoryAction = createPluginAction(
			"Jexplorer_ContextMenu_OpenVersionHistory", "Open Version History", "Opens the version history viewer."
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
			"Jexplorer_ContextMenu_Append", "Append Changes", "Saves pending changes made to this Instance, appends to the latest version."
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
			"Jexplorer_ContextMenu_Commit", "Commit Changes", "Commits pending changes made to this Instance, saves as a new version."
		)
		commitAction.Triggered:Connect(function()
			for _, entity in state.CurrentSelection do
				local inst = world:get(entity, components.Instance) :: Instance
				VersionControl.createPendingChanges(inst)
			end
		end)
	end
	
	local discardAction do
		discardAction = createPluginAction(
			"Jexplorer_ContextMenu_Discard", "Discard Changes", "Discard pending changes made to this Instance."
		)
		discardAction.Triggered:Connect(function()
			for _, entity in state.CurrentSelection do
				local inst = world:get(entity, components.Instance) :: Instance
				VersionControl.discardPendingChanges(inst)
			end
		end)
	end

	local removeFromTabAction do
		removeFromTabAction = createPluginAction(
			"Jexplorer_ContextMenu_RemoveFromTab", "Remove from Tab", "Removes this instance from this tab. Can be readded via the tabs + menu"
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
				if not world:has(ent, ChildOf(Jecs.Wildcard)) then
					world:add(ent, components.Invisible)
					HierarchyState.invalidateEntityStateCache(ent)
				end

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
			"Jexplorer_ContextMenu_GroupAsFolder", "Group as Folder", "Groups the selected Instances inside 1 Folder.",
			"rbxasset://studio_svg_textures/Shared/InsertableObjects/Dark/Standard/Folder.png"
		)
		groupAsModelAction = createPluginAction(
			"Jexplorer_ContextMenu_GroupAsModel", "Group as Model", "Groups the selected Instances inside 1 Model.",
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
			"Jexplorer_ContextMenu_Ungroup", "Ungroup", "Ungroups the selected Instances."
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
				world:add(child, components.AncestryLocked)
			end
			for _, child in children do
				local inst = Manager.instanceOf(child)
				if not inst then continue end

				Manager.updateParent(child, parent)
				inst.Parent = Manager.instanceOf(parent)
				table.insert(entities, child)
			end

			targetInst.Parent = nil
			Manager.updateParent(target, nil)
			
			VirtualScroller.rebuildAndUpdate(Manager, false)
			Manager.setExplorerEntitiesAsSelection(entities, true)
			
			for _, child in children do
				world:remove(child, components.AncestryLocked)
			end

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
				
				for _, tag in info.inst:GetTags() do
					model:AddTag(tag)
				end
				for k, v in info.inst:GetAttributes() do
					model:SetAttribute(k, v)
				end

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

					--local dragFrame = world:get(childEntity, components.Frame)
					--if dragFrame then
					--	ExplorerFrame.queueForExplorerFrameReuse(Manager, dragFrame)
					--end
				end
				HierarchyState.ChildrenMap[info.entity] = nil

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
			"IntoFolder", "Into Folder", "Turns selected instances into Folders.", 
			"rbxasset://studio_svg_textures/Shared/InsertableObjects/Dark/Standard/Folder.png"
		)
		toFolderAction.Triggered:Connect(function()
			convertInstTo("Folder")
		end)
		toModelAction = createPluginAction(
			"IntoModel", "Into Model", "Turns selected instances into Models.", 
			"rbxasset://studio_svg_textures/Shared/InsertableObjects/Dark/Standard/Model.png"
		)
		toModelAction.Triggered:Connect(function()
			convertInstTo("Model")
		end)
	end

	local helpAction do
		helpAction = createPluginAction(
			"Help", "Open Documentation", "Opens the API wiki page for this Instance."
		)
		helpAction.Triggered:Connect(function()
			local target = state.ContextTarget
			if not target then return end

			local inst = Manager.instanceOf(target)
			if not inst then return end
			
			local Localization = game:GetService("LocalizationService")
			local localeId
			local lang = Manager.getSetting("DocumentationLanguage")
			if lang == "Roblox" then
				localeId = Localization.RobloxLocaleId
			elseif lang == "System" then
				localeId = Localization.SystemLocaleId
			else
				localeId = lang
			end
			plugin:OpenWikiPage(`{localeId}/api-reference/class/{inst.ClassName}`)
		end)
	end

	local dragAction do
		dragAction = createPluginAction(
			"Drag", "Start Dragging", "Starts dragging selected Instances."
		)
		dragAction.Triggered:Connect(Manager.startDraggingSelected)
	end
	
	local changeIconColorAction do
		changeIconColorAction = createPluginAction(
			"ChangeIconColor",
			"Change Icon Color",
			"Prompts to change the icon color of selected Instances."
		)
		
		changeIconColorAction.Triggered:Connect(function()
			local currentColor = Color3.fromRGB(255, 255, 255)

			local box = PluginUI.createAttributeBox(nil, "Custom Icon Color", "")
			local chooseColorButton = PluginUI.createSideButtonImage("", Vector2.zero, Vector2.zero, box.Instance.ValueBox)
			chooseColorButton:AddTag("JEXP_Border")
			chooseColorButton.BackgroundColor3 = currentColor

			local toggleUseColor
			local function refreshFromSelection()
				local sel = state.CurrentSelection
				if not sel or #sel == 0 then return end

				local entity = sel[1]
				local iconColor = world:get(entity, components.FrameIconColor)
				if iconColor then
					currentColor = iconColor
					chooseColorButton.BackgroundColor3 = currentColor
				end

				-- sync checkbox: enabled = component exists (not nil)
				local allSameEnabled = true
				local firstEnabled = nil
				for _, ent in sel do
					local ic = world:get(ent, components.FrameIconColor)
					local enabled = ic ~= nil
					if firstEnabled == nil then
						firstEnabled = enabled
					elseif firstEnabled ~= enabled then
						allSameEnabled = false
						break
					end
				end
				toggleUseColor:Set(allSameEnabled and (firstEnabled or false))
			end

			toggleUseColor = PluginUI.createCheckBox(nil, "Use Custom Icon Color", false, function(enabled)
				if enabled then
					for _, entity in state.CurrentSelection do
						world:set(entity, components.FrameIconColor, currentColor)
						local frame = world:get(entity, components.Frame)
						if frame then
							ExplorerFrame.setExplorerFrameIconColor(Manager, frame, currentColor)
						end
					end
				else
					for _, entity in state.CurrentSelection do
						world:remove(entity, components.FrameIconColor)
						local frame = world:get(entity, components.Frame)
						if frame then
							ExplorerFrame.setExplorerFrameIconColor(Manager, frame, nil)
						end
					end
				end
			end)

			local widget, destroy = PluginUI.createPopupWidget("Change Icon Color", { box, toggleUseColor })
			Manager.Style:Link(widget)

			local picker
			local activatedConn = chooseColorButton.Activated:Connect(function()
				if picker then
					picker:Close()
					picker:Destroy()
				end

				picker = ColorPicker.new(plugin, getId("PropertyColorPicker", true))
				picker:Show()
				picker:Set(currentColor)

				-- snapshot: nil means disabled, Color3 means enabled+color
				local originalStates = {}
				for _, entity in state.CurrentSelection do
					originalStates[entity] = world:get(entity, components.FrameIconColor) -- Color3 or nil
				end

				picker:BindToChange(function(newColor)
					currentColor = newColor
					chooseColorButton.BackgroundColor3 = newColor
					box:SetText(`{truncate(newColor.R * 255)}, {truncate(newColor.G * 255)}, {truncate(newColor.B * 255)}`)
					for _, entity in state.CurrentSelection do
						if originalStates[entity] ~= nil then
							world:set(entity, components.FrameIconColor, newColor)
							local frame = world:get(entity, components.Frame)
							if frame then
								ExplorerFrame.setExplorerFrameIconColor(Manager, frame, newColor)
							end
						end
					end
				end)

				picker:BindToCancel(function()
					for _, entity in state.CurrentSelection do
						local original = originalStates[entity]
						local frame = world:get(entity, components.Frame)
						if original ~= nil then
							world:set(entity, components.FrameIconColor, original)
							if frame then
								ExplorerFrame.setExplorerFrameIconColor(Manager, frame, original)
							end
						else
							world:remove(entity, components.FrameIconColor)
							if frame then
								ExplorerFrame.setExplorerFrameIconColor(Manager, frame, nil)
							end
						end
					end
					-- restore button to whatever the first entity had
					currentColor = originalStates[state.CurrentSelection[1]] or currentColor
					chooseColorButton.BackgroundColor3 = currentColor
					picker:Close()
					picker:Destroy()
				end)

				picker:BindToConfirm(function()
					picker:Close()
					picker:Destroy()
				end)
			end)

			local selectionChangedConn = game.Selection.SelectionChanged:Connect(function()
				refreshFromSelection()
			end)

			box:OnChange(function(newValue)
				local x, y, z = xyz(newValue)
				local color = Color3.fromRGB(asnumber(x), asnumber(y), asnumber(z))
				currentColor = color
				chooseColorButton.BackgroundColor3 = color
				for _, entity in state.CurrentSelection do
					-- only update entities that have color enabled
					if world:get(entity, components.FrameIconColor) ~= nil then
						world:set(entity, components.FrameIconColor, color)
					end
				end
			end)
			refreshFromSelection()
			
			local function cleanupUi()
				if picker then
					picker:Destroy()
				end
				selectionChangedConn:Disconnect()
				activatedConn:Disconnect()
				widget:Destroy()
				--destroy()
			end
			local childConnections = connections:extend(cleanup.call, {cleanupUi})
			widget:BindToClose(function()
				childConnections:free()
			end)
		end)
	end
	
	local saveAsObjAction do
		saveAsObjAction = createPluginAction(
			"SaveAsObj",
			"Export as .obj...",
			"Prompts to save selection as .obj file."
		)
		
		saveAsObjAction.Triggered:Connect(function()
			PluginManager:ExportSelection("Object")
		end)
	end

	Manager.PluginActions = {
		OpenVersionHistory = openVersionHistoryAction,
		Append = appendAction,
		Commit = commitAction,
		Discard = discardAction,

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
		ExportAsObj = saveAsObjAction,
		
		RemoveFromTab = removeFromTabAction,

		GroupAsModel = groupAsModelAction,
		GroupAsFolder = groupAsFolderAction,

		IntoFolder = toFolderAction,
		IntoModel = toModelAction,

		Ungroup = ungroupAction,
		ChangeIconColor = changeIconColorAction,

		Tab_EditName = tabEditName,
		Tab_EditIcon = tabEditIcon,
		Tab_Delete = tabDelete,
		Tab_InsertRoots = tabInsert,
	}

	state.DefaultInstanceActionsArray = {
		{
			Id = "Menu.VersionControl",
			Title = "Version Control",
			{
				"OpenVersionHistory",
				"Append",
				"Commit",
				"Discard"
			}
		},

		"---",

		"Copy",
		"PasteInto",
		"Delete",
		"Duplicate",
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

		"---",

		"InsertFromFile",
		"InsertObject",
		"SaveToFile",
		"SaveToRoblox",
		
		{
			Id = "Menu.ExportAs",
			Title = "Export As",
			{
				"ExportAsObj"
			}
			
		},

		"---",
		
		"RemoveFromTab",
		"ChangeIconColor",

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
			
			"RemoveFromTab",

			"---",

			"Help"
		}
	)

	local tabMenu = Manager.createContextMenu(
		getId("Jexplorer_TabContextMenu", true),
		{
			"Tab_InsertRoots",
			"Tab_EditName",
			"Tab_EditIcon",
			"Tab_Delete"
		}
	)

	local allTabMenu = Manager.createContextMenu(
		getId("Jexplorer_AllTabContextMenu", true),
		{
			"Tab_EditName",
			"Tab_EditIcon",
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
		Tab = tabMenu,
		AllTab = allTabMenu
	}
end

local function refreshQueryEntity(queryWorld: World, inst: Instance, entity: ExplorerEntity, tags: {Jecs.Id}, attrs: {Jecs.Id})
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
	for attr_name in inst:GetAttributes() do
		local id = Manager.QueryAttrMap[attr_name]
		if not id then
			id = queryWorld:entity()
			Manager.QueryAttrMap[attr_name] = id
		end
		if table.find(attrs, id) then continue end
		table.insert(attrs, id)
	end
	HierarchyState.deregisterFromQueryWorld(Manager, entity)
	HierarchyState.registerIntoQueryWorld(Manager, entity, Manager.ClassNameCache[entity], tags, attrs)
end

function Manager.refreshQueryTags(entity, tag_ent)
	local state = Manager.WidgetState
	local queryWorld = state.QueryWorld
	
	local inst = Manager.instanceOf(entity)
	assert(inst)
	
	local tags: {Jecs.Id} = {}
	local attrs: {Jecs.Id} = {}
	if tag_ent then
		table.insert(tags, tag_ent)
	end
	refreshQueryEntity(queryWorld, inst, entity, tags, attrs)
end

function Manager.refreshQueryAttributes(entity, attr_ent)
	local state = Manager.WidgetState
	local queryWorld = state.QueryWorld

	local inst = Manager.instanceOf(entity)
	assert(inst)

	local tags: {Jecs.Id} = {}
	local attrs: {Jecs.Id} = {}
	if attr_ent then
		table.insert(attrs, attr_ent)
	end
	refreshQueryEntity(queryWorld, inst, entity, tags, attrs)
end

local function initRegisterTagListeners(
	state: Types.WidgetState,
	components: typeof(Manager.Components)
)
	local world = state.World
	local frameWorld = state.FrameWorld
	local queryWorld = state.QueryWorld
	
	local tagAddedSignals = {}
	local tagRemovedSignals = {}
	local function onTag(tag: string)
		if tag:match("JEXP") then return end

		local tagComponent = queryWorld:entity()
		queryWorld:set(tagComponent, Jecs.Name, tag)
		Manager.QueryTagMap[tag] = tagComponent
		
		local function onAdded(inst: Instance)
			if Manager.isInstanceExcluded(inst) then return end

			local listener = onTagAddedListeners[inst]
			if listener then listener(tag) end

			local entity = Manager.InstanceToEntity[inst]
			if not entity then return end

			Manager.refreshQueryTags(entity, tagComponent)

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

			Manager.refreshQueryTags(entity, nil)

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
			if tag:match("JEXP") then return end
			
			local added, removed = tagAddedSignals[tag], tagRemovedSignals[tag]
			if added then added:Disconnect() end
			if removed then removed:Disconnect() end

			tagAddedSignals[tag] = nil
			tagRemovedSignals[tag] = nil

			local tagEnt = Manager.QueryTagMap[tag]
			if not tagEnt then return end
			
			for queryEnt, linked in queryWorld:query(components.QueryLinkedEntities, tagEnt):iter() do
				for _, ent in linked do
					Manager.refreshQueryTags(ent, nil)
				end
				if #linked == 0 then
					queryWorld:delete(queryEnt)
				end
			end
			
			Manager.QueryTagMap[tag] = nil
			queryWorld:delete(tagEnt)
		end)
end

local function initStartTrackScrolling(state: Types.WidgetState)
	local jexplorerUi = state.JExplorerUI
	local scrollTrackerConnection, scrollTrackerThread = VirtualScroller.trackScrolling(Manager)
	
	return scrollTrackerConnection, scrollTrackerThread
end

local function initCreateEntities(state: Types.WidgetState, components: typeof(Manager.Components), entities: {ExplorerEntity})
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
	
	ExplorerFrame.flushExplorerFrameTagAssignQueue(Manager)
	VirtualScroller.rebuildAndUpdate(Manager, false)
	
	profileend()
end

local function initConnections(state: Types.WidgetState, components: typeof(Manager.Components), topbarMenuDropdown: PluginUI.ItemList): {RBXScriptConnection}
	local world = state.World
	local queryWorld = state.QueryWorld
	local jexplorerUi = state.JExplorerUI
	local jexplorerWidget = state.Widget
	local topbar = jexplorerUi.Topbar
	local queryInput: TextBox = topbar.QueryInputFrame.Scroll.QueryInput
	local selectQueried = topbar.QueryInputFrame.SelectQueried

	local autocompleteGroup: ItemGroup.ItemGroup?
	local suppressAutocomplete = false
	
	-->> Initialize connections
	return {
		Manager.connectInputBegan(function(input)
			if input.UserInputState ~= Enum.UserInputState.Begin then return end
			downKeys[input.KeyCode] = true
			activeInputs[input.UserInputType] = true

			state.IsDragging = false
			if input.UserInputType ~= Enum.UserInputType.MouseMovement then
				Manager.ItemLists.InsertInstance:Hide()
			end
			if autocompleteGroup and input.UserInputType == Enum.UserInputType.MouseButton1 then
				autocompleteGroup:free()
			end
			local v = Manager.getSetting
			checkKeybinds({
				[v "KeybindEscapeTarget"] = Manager.triggerEscapeTarget,
				[v "KeybindDeleteTarget"] = Manager.triggerDeleteTarget,
				[v "KeybindDuplicateTarget"] = v "NormalDuplicateIncrementsName" and Manager.triggerDuplicateTargetWithIncrementName or Manager.triggerDuplicateTarget,
				[v "KeybindDuplicateTargetWithIncrementName"] = Manager.triggerDuplicateTargetWithIncrementName,
				[v "KeybindCopy"] = function() copySelection(world) end,
				[v "KeybindPaste"] = function() pasteCopiedInstances(world) end,
				[v "KeybindUndo"] = function() ChangeHistoryService:Undo() end,
				[v "KeybindRedo"] = function() ChangeHistoryService:Redo() end,
			}, input)
		end),
		Manager.connectInputEnded(function(input)
			if input.UserInputState ~= Enum.UserInputState.End then return end
			downKeys[input.KeyCode] = nil
			activeInputs[input.UserInputType] = nil
		end),
		ScriptEditorService.TextDocumentDidChange:Connect(function(document, changes)
			local docScript = document:GetScript()
			if not docScript then return end

			VersionControl.addPendingChange(docScript, "Source", document:GetText())
		end),
		state.TreeScroller:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
			VirtualScroller.update(Manager, true)
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
			
			for _, v in state.Tabs do
				local iconLabel = v.IconLabel
				iconLabel.Image = getTabImageIcon(v, iconLabel.Image)
			end
		end),
		jexplorerWidget.PluginDragDropped:Connect(function(dragData)
			local info = Manager.unpackDragInfo(dragData)

			local mousePos = jexplorerWidget:GetRelativeMousePosition()
			local dropFrame, foundDropEntity, foundTab = Manager.getEntityAt(mousePos.X, mousePos.Y)
			
			if info.Type == "setproperty" then
				local instances, propName = info.TargetInstances, info.PropertyName
				local value: Instance?
				if foundDropEntity then
					value = Manager.instanceOf(foundDropEntity)
				else
					value = nil
				end
				
				local id = ChangeHistoryService:TryBeginRecording("Set Instance", "Set Instance")
				for _, inst in instances do
					rawnewindex(inst, propName, value)
				end
				if id then
					ChangeHistoryService:FinishRecording(id, Enum.FinishRecordingOperation.Commit)
				end
			elseif info.Type == "reparent" then
				if not foundDropEntity then return end
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
					VirtualScroller.invalidateEntityHeightCache(Manager, dragEntity)
				end
				
				ExplorerFrame.flushExplorerFrameTagAssignQueue(Manager)
				
				world:add(foundDropEntity, components.Expanded)
				HierarchyState.invalidateEntityStateCache(foundDropEntity)
				ExplorerFrame.updateExpandedVisuals(Manager)
				
				for _, e in dragEntities do
					world:remove(e, components.AncestryLocked)
				end
				VirtualScroller.rebuildAndUpdate(Manager, false)

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
			
			refreshPathBar(selection, state, components)
			
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
				local scroller = state.TreeScroller
				local currentViewportTop = scroller.CanvasPosition.Y
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
					scroller.CanvasPosition = target
					if not scroller.CanvasPosition:FuzzyEq(target, 0.01) then
						local lastPosition = scroller.CanvasPosition
						repeat
							task.wait()
							lastPosition = scroller.CanvasPosition
							scroller.CanvasPosition = target
						until scroller.CanvasPosition:FuzzyEq(lastPosition, 0.01)
					end
				end
			end
			
			VirtualScroller.update(Manager, false)
			ExplorerFrame.updateSelectionVisuals(Manager, false)
			profileend()
		end),

		topbar.Options.Activated:Connect(function()
			topbarMenuDropdown:SetAnchor(Vector2.zero, topbar.Options.Position)
			topbarMenuDropdown:Show()
		end),
		
		queryInput:GetPropertyChangedSignal("Text"):Connect(function()
			if not Manager.getSetting("QueryAutocompleteEnabled") then return end
			if suppressAutocomplete then return end
			if autocompleteGroup then
				autocompleteGroup:free()
			end

			local autocompleteResults: {{
				label: string,
				priority: number,
				insert: () -> ()
			}} = {}

			local queryText = queryInput.Text
			local tokenStart = 1
			for i = #queryText, 1, -1 do
				local c = queryText:sub(i, i)
				if c == " " or c == "&" or c == "|" or c == "<" or c == ">" or c == "*" then
					tokenStart = i + 1
					break
				end
			end
			local currentToken = queryText:sub(tokenStart)
			local prefix = queryText:sub(1, tokenStart - 1)
			-- Get the last logical segment (after the last | or & combinator)
			local lastSegment = prefix:match("[^|&<>*]*$") or prefix
			local inValueContext = lastSegment:match("[%w_]+%s*=") ~= nil

			local UDF_READ_TAGS = {
				"%",
				"#",
				"?",
				"[str] ",
				"[num] ",
				"[bool] ",
				"[rgb] ",
				"[hex] ",
				"[vec2] ",
				"[vec3] ",
				"[udim] ",
				"[udim2] ",
				"[json] ",
				"[region3] ",
				"[ray] ",
				"[enum.Material] ",
				"[enum.NormalId] ",
				"[enum.PartType] ",
				"[enum.SurfaceType] ",
				"[enum.BrickColor] ",
				"[enum.Font] ",
				"[enum.KeyCode] ",
			}

			local function addResult(label: string, insertText: string, priority: number?)
				table.insert(autocompleteResults, {
					label = label,
					priority = priority or 0,
					insert = function()
						suppressAutocomplete = true
						queryInput.Text = prefix .. insertText
						queryInput:CaptureFocus()
						task.defer(function()
							queryInput.CursorPosition = #queryInput.Text + 1
							suppressAutocomplete = false
						end)
					end
				})
			end

			local function matchesPartial(name: string, partial: string): boolean
				return name:sub(1, #partial):lower() == partial:lower()
			end
			
			local function suggestUDFTags(valuePartial: string, pairPrefix: string)
				for _, tag in UDF_READ_TAGS do
					if matchesPartial(tag, valuePartial) then
						addResult(tag, tag, 8)
					end
				end
			end
			
			local function detectContext(): boolean
				do
					local propAndEq, valuePartial = queryText:match("([%w_]+%s*=%s*)([^%s&|]*)$")
					if propAndEq and valuePartial ~= nil and (valuePartial:sub(1,1) == "[" or #valuePartial == 0) then
						local pairStart = #queryText - #propAndEq - #valuePartial + 1
						local pairPrefix = queryText:sub(1, pairStart - 1) .. propAndEq
						suggestUDFTags(valuePartial, pairPrefix)
						return true
					end
				end

				-- @has(partial
				do
					local partial = currentToken:match("^@has%((.*)$")
					if partial then
						for name, _ in Manager.QueryCtMap do
							if type(name) == "string" and matchesPartial(name, partial) then
								addResult(name, "@has(" .. name .. ")", 9)
							end
						end
						return true
					end
				end

				-- @is(prop, typePartial
				do
					local prop, partial = currentToken:match("^@is%(([^,]+),(.*)$")
					if prop and partial then
						partial = partial:gsub("^%s+", "")
						local types = {
							"string", "number", "boolean", "Vector2", "Vector3",
							"UDim", "UDim2", "Color3", "CFrame", "Rect",
							"EnumItem", "Enum.Material", "Enum.NormalId",
							"Enum.PartType", "Enum.SurfaceType", "Enum.BrickColor"
						}
						for _, t in types do
							if matchesPartial(t, partial) then
								addResult(t, "@is(" .. prop .. ", " .. t .. ")", 8)
							end
						end
						return true
					end
				end

				-- @is(partial  (first arg, property name)
				do
					local partial = currentToken:match("^@is%((.*)$")
					if partial then
						for name, _ in Manager.QueryCtMap do
							if type(name) == "string" and matchesPartial(name, partial) then
								addResult(name, "@is(" .. name .. ", ", 9)
							end
						end
						return true
					end
				end

				-- @matches(prop, patternPartial  OR  @pattern(prop, patternPartial
				do
					local macro, prop, partial = currentToken:match("^(@matches%()([^,]+),(.*)$")
					if not macro then
						macro, prop, partial = currentToken:match("^(@pattern%()([^,]+),(.*)$")
					end
					if macro and prop and partial then
						-- Second arg is a free-form string/pattern, nothing to suggest
						return true
					end
				end

				-- @matches(partial  OR  @pattern(partial  (first arg, property name)
				do
					local macro, partial = currentToken:match("^(@matches%()(.*)$")
					if not macro then
						macro, partial = currentToken:match("^(@pattern%()(.*)$")
					end
					if macro and partial then
						for name, _ in Manager.QueryCtMap do
							if type(name) == "string" and matchesPartial(name, partial) then
								addResult(name, macro .. name .. ", ", 9)
							end
						end
						return true
					end
				end

				-- @ prefix: suggest macro names
				do
					local partial = currentToken:match("^@(.*)$")
					if partial then
						local macros = {"has(", "matches(", "is(", "pattern("}
						for _, macro in macros do
							if matchesPartial(macro, partial) then
								addResult("@" .. macro, "@" .. macro, 10)
							end
						end
						return true
					end
				end

				-- . prefix: suggest tag names
				do
					local partial = currentToken:match("^%.(.*)$")
					if partial and not inValueContext then
						for name, _ in Manager.QueryTagMap do
							if type(name) == "string" and matchesPartial(name, partial) then
								addResult("." .. name, "." .. name, 7)
							end
						end
						return true
					end
				end

				-- # prefix: suggest instance names
				do
					local partial = currentToken:match("#([^?].*)$")
					if partial and not inValueContext then
						local seen: {[string]: boolean} = {}
						for entity in world:query(components.Instance):iter() do
							local inst = world:get(entity, components.Instance)
							if inst and not seen[inst.Name] then
								if matchesPartial(inst.Name, partial) then
									seen[inst.Name] = true
									addResult("#" .. inst.Name, "#" .. inst.Name, 7)
								end
							end
						end
						return true
					end
				end

				-- $ prefix: suggest attribute names
				do
					local partial = currentToken:match("^%$(.*)$")
					if partial and not inValueContext then
						for name, _ in Manager.QueryAttrMap do
							if type(name) == "string" and matchesPartial(name, partial) then
								addResult("$" .. name, "$" .. name .. " = ", 7)
							end
						end
						return true
					end
				end
				
				if not inValueContext and currentToken:match("^[%a_][%w_]*$") then
					local partial = currentToken
					for name, _ in Manager.QueryCtMap do
						if type(name) == "string" and matchesPartial(name, partial) then
							addResult(name .. " = ", name .. " = ", 5)
						end
					end
				end

				return false
			end

			detectContext()
			
			table.sort(autocompleteResults, function(a, b)
				if a.priority ~= b.priority then
					return a.priority > b.priority
				end
				return a.label < b.label
			end)

			-- Cap results
			while #autocompleteResults > 12 do
				table.remove(autocompleteResults)
			end

			if #autocompleteResults > 0 then
				local list = PluginUI.createItemList({Visible = true})
				local group = ItemGroup.create(function(v) v:Destroy() end, {list})

				local buttons = {}
				for _, result in autocompleteResults do
					local button = PluginUI.createButton(nil, result.label, function()
						result.insert()
						if autocompleteGroup then
							autocompleteGroup:free()
						end
						task.defer(function()
							list:Destroy()
						end)
					end)
					table.insert(buttons, button.Instance)
				end
				list:AddBulkItem(buttons)

				local frameSize = list.Backdrop.AbsoluteSize
				list:SetAnchor(
					Vector2.new(0, 0),
					UDim2.fromOffset(
						getClampedXY(
							frameSize,
							queryInput.AbsolutePosition + Vector2.new(0, queryInput.AbsoluteSize.Y),
							Vector2.zero,
							jexplorerUi.AbsolutePosition,
							jexplorerUi.AbsoluteSize
						)
					)
				)

				local currentSelection = 1

				group:extend(cleanup.disconnect, {
					Manager.connectInputBegan(function(input)
						if input.KeyCode == Enum.KeyCode.Up then
							local lastButton = buttons[currentSelection]
							currentSelection = math.clamp(currentSelection - 1, 1, #autocompleteResults)
							local button = buttons[currentSelection]

							lastButton:RemoveTag("JEXP_SelectedColor");
							(lastButton:FindFirstChildOfClass("TextLabel") :: any):RemoveTag("JEXP_SelectedColor")
							button:AddTag("JEXP_SelectedColor");
							(button:FindFirstChildOfClass("TextLabel") :: any):AddTag("JEXP_SelectedColor")
						elseif input.KeyCode == Enum.KeyCode.Down then
							local lastButton = buttons[currentSelection]
							currentSelection = math.clamp(currentSelection + 1, 1, #autocompleteResults)
							local button = buttons[currentSelection]

							lastButton:RemoveTag("JEXP_SelectedColor");
							(lastButton:FindFirstChildOfClass("TextLabel") :: any):RemoveTag("JEXP_SelectedColor")
							button:AddTag("JEXP_SelectedColor");
							(button:FindFirstChildOfClass("TextLabel") :: any):AddTag("JEXP_SelectedColor")
						elseif input.KeyCode == Enum.KeyCode.Return then
							autocompleteResults[currentSelection].insert()
						elseif input.KeyCode == Enum.KeyCode.Escape and autocompleteGroup then
							autocompleteGroup:free()
						end
					end)
				})
				local button = buttons[currentSelection]
				button:AddTag("JEXP_SelectedColor");
				(button:FindFirstChildOfClass("TextLabel") :: any):AddTag("JEXP_SelectedColor")

				autocompleteGroup = group

				list.Backdrop.Parent = jexplorerUi
			end
		end),
		-- Search bar functionality
		queryInput.FocusLost:Connect(function(enterPressed)
			if not enterPressed then return end
			if autocompleteGroup then
				autocompleteGroup:free()
			end
			
			local queryText = queryInput.Text
			
			local function playsound(id: string)
				local sound = Instance.new("Sound")
				sound.SoundId = id
				sound.Volume = 5
				
				sound.Parent = jexplorerWidget
				
				sound.Ended:Connect(function()
					sound:Destroy()
				end)
				sound.Playing = true
			end
			if queryText == "hello everybody my name is welcome" then
				playsound("rbxassetid://7298563407")
				return
			elseif queryText == "was that the bite of 87???" then
				playsound("rbxassetid://86389960852671")
				return
			elseif queryText == "the first night is never usually that bad" then
				playsound("rbxassetid://7398226850")
				return
			elseif queryText == "WHAT THE HELL IS THAT" then
				playsound("rbxassetid://107433594687751")
				return
			end
			
			profilebegin("Jexplorer::query")
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
				topbar.QueryInputFrame.QueryCount.Text = "0"
				for _, entity in state.Entities do
					world:remove(entity, components.QueryInvisible)
					HierarchyState.invalidateEntityStateCache(entity)
					world:remove(entity, components.IsQueried)
				end
				state.TreeScroller.CanvasSize = UDim2.fromScale(0, 0)
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
				local queryResult = JQL.executeQuery(world, queryWorld, components, Manager.QueryCtMap, Manager.QueryTagMap, Manager.QueryAttrMap, conditions)
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
			
			local validEntities = {}
			local n = 0
			for _, v in result do
				local inst = Manager.instanceOf(v)
				if inst and Manager.isInstanceExcluded(inst) then continue end
				n += 1
				table.insert(validEntities, v)
			end
			-- Everything is invisible if no results
			if n == 0 then
				topbar.QueryInputFrame.QueryCount.Text = "0"
				return
			end

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
						if Manager.isExplorerEntityInvisible(parent) then
							world:remove(entity, components.IsQueried)
							world:add(entity, components.QueryInvisible)
							break
						end
						world:remove(parent, components.QueryInvisible)
						world:remove(parent, components.ArrowInvisible)
						world:add(parent, components.QueryExpanded)
						HierarchyState.invalidateEntityStateCache(parent)
					end

					world:add(last, components.QueryAncestor)
				end
			end
			
			local n = 0
			for _ in world:query(components.IsQueried) do
				n += 1
			end
			
			topbar.QueryInputFrame.QueryCount.Text = n

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
		state.TreeScroller:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			Manager.InstTreeAbsoluteSizeY = state.TreeScroller.AbsoluteSize.Y
		end)
	}
end

function Manager.init(connections, jexplorerWidget)
	local instances = connections:extend(cleanup.destroy)

	local jexplorerUi = UITemplates.JexplorerUi {
		Parent = jexplorerWidget
	}

	local instanceTree = jexplorerUi.InstanceTree :: GuiObject
	local treeScroller = (instanceTree :: any).TreeScroller :: ScrollingFrame
	
	local storage = findOrCreateInstance(game:GetService("ServerStorage"), "jexplorer_instance_storage", "Folder")
	Manager.Storage = {
		repoRoots = findOrCreateInstance(storage, "repo_roots", "Folder"),
		idObjects = findOrCreateInstance(storage, "jexplorer_ids", "Folder"),
		--pluginActions = findOrCreateInstance(storage, "plugin_actions", "Folder")
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
		IsDragging = false,
		
		InstanceTree = (instanceTree :: any).ScrollContainer,
		TreeScroller = treeScroller
	}
	
	local state = Manager.WidgetState
	local components = Manager.Components
	local topbar = jexplorerUi.Topbar
	
	Manager.InstTreeAbsoluteSizeY = treeScroller.AbsoluteSize.Y
	
	if getGlobalConfigValue("reset_state") == true then
		SavedState.save(SavedState.get_default(Manager))
	end

	if getGlobalConfigValue("data_version") then
		local tbl = plugin:GetSetting("Jexplorer_SavedState")
		tbl.data_version = getGlobalConfigValue("data_version")
	end
	local loaders, savedState = Manager.loadState(SavedState.load(Manager))
	local sheet = loaders.style()
	
	loaders.icon_colors()
	loaders.order()
	loaders.invisible()
	
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
	
	local settings = getGlobalConfigValue("settings")
	if settings then
		for k, v in settings do
			Manager.setSetting(k, v)
		end
	end
	
	for _, obj in Manager.Storage.idObjects:GetChildren() do
		assert(obj:IsA("ObjectValue"))
		
		local inst = obj.Value
		if not inst then
			obj:Destroy()
			continue
		end
		
		local id = obj:GetAttribute(ID_ATTR)
		
		Manager.InstanceToId[inst] = id
		Manager.IdToInstance[id] = inst
		Manager.IdToObjectValue[id] = obj
	end
	ExplorerFrame.initializeFrameCaches(Manager)
	local topbarMenuDropdown = CreateOptionsDropdown(Manager, components, topbar)

	initRegisterPluginMenusAndActions(state, components)
		
	InsertMenu.init(Manager)
	
	local tagAddedSignals, tagRemovedSignals, tagAdded, tagRemoved = initRegisterTagListeners(state, components)
	local scrollTrackerConnection, scrollTrackerThread = initStartTrackScrolling(state)

	local entities = {}
	initCreateEntities(state, components, entities)
	
	VersionControl.Versions = loaders.versions()
	loaders.repo_proxies()

	ContextMenuEditor.init(Manager)
	JextensionEditor.init(Manager)
	StateEditor.init(Manager)

	Manager.AllTab = Manager.registerTab("All", "rbxassetid://13641691796", entities, false)
	-- Wait until robloxs scrollingframe update
	task.delay(1.5, Manager.AllTab.Toggle)
	task.delay(2, loaders.tabs)

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
		StateEditor.Widget,
		PropertyEditor.Widget,
		ContextMenuEditor.Widget
	}

	instances:add_many({
		plugin,
	})

	local scriptConnections = initConnections(state, components, topbarMenuDropdown)
	connections:add_many(scriptConnections)
	connections:add_many({
		tagAdded,
		tagRemoved,
		scrollTrackerConnection,
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
		function()
			for _, v in Manager.PluginActions do
				v:Destroy()
			end
		end,
	})
	
	local function flushCycle()
		local suc1 = HierarchyState.flushOnChildAddedQueue(Manager)
		local suc2 = HierarchyState.flushOnChildRemovedQueue(Manager)
		local suc3 = HierarchyState.flushEntityCleanupQueue(Manager)
		task.defer(task.defer, function()
			ExplorerFrame.stepFlushFrameSetParentQueue(Manager)
			if not VirtualScroller.IsScrolling and not VirtualScroller.IsVirtualScrollerUpdating then
				ExplorerFrame.flushFrameReuseQueue(Manager)
			end
			ExplorerFrame.flushExplorerFrameTagAssignQueue(Manager)
		end)
		
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
	sheet:UpdateTokens()
	Manager.InstTreeAbsoluteSizeY = treeScroller.AbsoluteSize.Y
end

Manager.ChildOf = ChildOf
Manager.Script = script.Parent

Manager.createPluginAction = createPluginAction

return Manager