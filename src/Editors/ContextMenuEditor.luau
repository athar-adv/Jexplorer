--!strict
--!optimize 2

local plugin = script:FindFirstAncestorOfClass("Plugin")

local main = script.Parent.Parent

local shared = main.Shared

local PluginUI = require(shared.PluginUI)
local RawInst = require(shared.Small.RawInst)
local UITemplates = require(shared.UITemplates)
local ItemGroup = require(shared.Vendor.ItemGroup)
local cleanup = ItemGroup.cleanup
local Constants = require(main.Constants)
local gt = require(shared.Vendor.greentea)

local Types = require(main.Types)

local rawindex = RawInst.rawindex

local init = false

local ContextMenuEditor = {} :: Types.ContextMenuEditor

local function createCtxMenuInterface(actions: any)
	local self: Types.ContextMenuInterface; self = {
		getMenuContents = function() return actions end,
		getSubMenu = function(name)
			local subMenus = {}
			for _, v in actions do
				if type(v) ~= "table" then continue end
				if v.Id ~= name then continue end
				return createCtxMenuInterface(v[1])
			end
			error(`SubMenu '{name}' not found`)
		end,
		relocate = function(name, newIndex)
			local idx = table.find(actions, name)
			if idx then
				table.remove(actions, idx)
			end
			table.insert(actions, newIndex, name)
		end,
		flipOrder = function()
			local reversed = {}
			for i = #actions, 1, -1 do
				table.insert(reversed, actions[i])
			end
			actions = reversed
		end,
		
		remove = function(idx)
			table.remove(actions, idx)
		end,
		insert = function(idx, v)
			table.insert(actions, idx, v)
		end,
		
		findAction = function(name)
			return assert(table.find(actions, name), `Action {name} not found`)
		end,
		findSubMenu = function(name)
			for i, v in actions do
				if type(v) ~= "table" then continue end
				if v.Id ~= name then continue end
				return i
			end
			error(`SubMenu '{name}' not found`)
		end,
		
		inline = function(idx, arr)
			for _, v in arr do
				table.insert(actions, idx, v)
				idx += 1
			end
		end,
		
		addSection = function(idx, sectionName, content)
			self.insert(idx, {SectionName = sectionName})
			self.inline(idx + 1, content)
		end,
		getSection = function(sectionName)
			local x: number?, y: number?
			local sectionFound = false
			
			for i, v in actions do
				if type(v) ~= "table" then continue end
				if not v.SectionName then continue end
				if sectionFound then
					y = i - 1
					break
				end
				local name = v.SectionName
				if name == sectionName then
					x = i
					sectionFound = true
					continue
				end
			end
			
			assert(x, `Section '{sectionName}' doesn't exist.`)
			if not y then
				y = #actions
			end
			
			return x::any, y::any
		end,
	}
	return self
end

local contextMenuConfigType: Types.ContextMenuConfigs = gt.struct {
	Menus = gt.array(gt.struct {
		Id = gt.string(),
		Priority = gt.number(),
		Condition = gt.anyfn(),
		Contents = gt.union(gt.anyfn(), gt.array(gt.any())),
	}),
	Actions = gt.dictionary(gt.string(), gt.struct {
		Id = gt.string(),
		Callback = gt.anyfn(),
		Text = gt.string(),
		Desc = gt.opt(gt.string()),
		Icon = gt.opt(gt.union(gt.anyfn(),gt.string()))
	})
}

local returnValTy: Types.ContextMenuConfigModuleReturnValue = gt.union(
	contextMenuConfigType,
	gt.anyfn()
)

local currentlyUsedModule: Instance?
function ContextMenuEditor.init(Manager)
	init = true
	local state = Manager.WidgetState
	local components = Manager.Components
	
	local jexplorerUi = state.JExplorerUI
	local topbar = jexplorerUi.Topbar

	local connections = state.Connections
	local instances = connections:extend(cleanup.destroy)

	local widget, mainframe = PluginUI.createEditorWidget(UITemplates.EditorFrame(), "ContextMenuEditor", "Context Menu Editor")
	ContextMenuEditor.Widget = widget
	Manager.Style:Link(widget)
	
	local list = PluginUI.createItemListFromExisting(mainframe, mainframe.Items.Content, mainframe.Items)
	
	local moduleName = plugin:GetSetting("ContextMenuConfigsModuleName") or ""
	local nameBox = PluginUI.createAttributeBox(list, "Module Name", moduleName, function(v)
		plugin:SetSetting("ContextMenuConfigsModuleName", v)
	end)
	local delayBox = PluginUI.createAttributeBox(list, "Source Changed Refresh Delay", plugin:GetSetting("ContextMenuConfigsRefreshDelay") or "0.5", function(v)
		assert(tonumber(v), `'{v}' could not be converted into number`)
		plugin:SetSetting("ContextMenuConfigsRefreshDelay", v)
	end)
	PluginUI.createButton(list, "Insert Config Template", function()
		local name = nameBox:Get()
		local clone = Instance.new("ModuleScript")
		clone.Source = [[
--!strict
local Types = require("@game/ServerStorage/tag.jexplorer_instance_storage/Types")

return function(plugin: Plugin, manager: Types.Manager, utils: Types.ContextMenuUtils): Types.ContextMenuConfigs
	-- Modify this to your desire!
	return {
		Actions = {},
		Menus = {}
	}
end]]
		clone.Name = name
		clone.Parent = workspace
		
		task.delay(0.1, function()
			game.Selection:Set({clone})
		end)
	end)
	
	local function deepCopy(tbl)
		local r = {}

		for i, v in tbl do
			if type(v) == "table" then
				r[i] = deepCopy(v)
				continue
			end
			r[i] = v
		end

		return r
	end
	
	local defaultInstanceCtxMenus = deepCopy(state.InstanceContextMenus)
	local defaultActionInfos = deepCopy(Manager.ActionInfos)
	local defaultActions =	deepCopy(Manager.BindableActions)
	
	local refreshDebounceThread: thread? = nil
	local sourceChangedConn: RBXScriptConnection?
	local stored: {Instance} = {}
	
	local function getCtxMenuInterface(defaultActionsName: string?)
		local tbl
		if defaultActionsName and state.InstanceContextMenus[defaultActionsName] then
			tbl = table.clone(state.InstanceContextMenus[defaultActionsName].Menu.Contents)
		else
			tbl = {}
		end
		return createCtxMenuInterface(tbl)
	end
	
	local utils: Types.ContextMenuUtils = table.freeze {
		createInterface = function(defaultActionsName: string?)
			local tbl
			if defaultActionsName and state.InstanceContextMenus[defaultActionsName] then
				tbl = table.clone(state.InstanceContextMenus[defaultActionsName].Menu.Contents)
			else
				tbl = {}
			end
			return createCtxMenuInterface(tbl)
		end,
		getMenuIds = function()
			local ids = {}
			for name in state.InstanceContextMenus do
				table.insert(ids, name)
			end
			return ids
		end,
		createModifiedMenu = function(menuId, newContents)
			local menuInfo = assert(state.InstanceContextMenus[menuId], `{menuId} is not an existing menu, cant create modified one.`)
			local contents = newContents(createCtxMenuInterface(menuInfo.Menu.Contents))
			
			return {
				Id = menuId,
				Priority = menuInfo.Priority,
				Condition = function(manager, target)
					return menuInfo.Condition(manager, target, assert(Manager.instanceOf(target)))
				end,
				Contents = contents
			}
		end,
		createSubMenu = function(id, title, icon, content)
			return {
				Id = id,
				Title = title,
				Icon = icon,
				content
			}
		end,
		createSection = function(name)
			return {SectionName = name}
		end,
	}
	
	local refreshThread
	local currentRefreshThread: thread?
	local function refresh(module: Instance)
		if not module:IsA("ModuleScript") then return end
		state.InstanceContextMenus = deepCopy(defaultInstanceCtxMenus)
		Manager.ActionInfos = deepCopy(defaultActionInfos)
		Manager.BindableActions = deepCopy(defaultActions)
		
		for _, v in stored do
			v:Destroy()
		end
		table.clear(stored)
		
		if currentlyUsedModule then
			currentlyUsedModule:Destroy()
		end
		if sourceChangedConn then
			sourceChangedConn:Disconnect()
		end
		local clone = module:Clone()
		currentlyUsedModule = clone
		clone.Parent = plugin
		sourceChangedConn = module:GetPropertyChangedSignal("Source"):Connect(function()
			if refreshDebounceThread then
				task.cancel(refreshDebounceThread)
			end
			refreshDebounceThread = task.delay(tonumber(delayBox:Get()), function()
				refreshThread(module)
				refreshDebounceThread = nil
			end)
		end)

		local returnval: Types.ContextMenuConfigModuleReturnValue = (require::any)(clone)
		gt.build(returnValTy)
			:assert(returnval)

		local configs: Types.ContextMenuConfigs
		if type(returnval) == "function" then
			configs = returnval(plugin, Manager, utils, table.clone(state.DefaultInstanceActionsArray))
		elseif type(returnval) == "table" then
			configs = returnval
		else
			error("ContextMenu module must return (Plugin, Manager) -> ContextMenuConfigs or ContextMenuConfigs.")
		end
		gt.build(contextMenuConfigType)
			:assert(configs)

		for name, info in configs.Actions do
			local id = info.Id or `JexplorerCustomAction({tostring(os.clock())})`

			local action = Manager.createPluginAction(
				id, info.Text, info.Desc or "", if info.Icon then info.Icon() else nil
			)
			table.insert(stored, action)

			local function triggered()
				local target = Manager.takeContextTarget()
				info.Callback(Manager, target)
			end
			
			action.Triggered:Connect(triggered)
			
			Manager.BindableActions[name] = action
			Manager.ActionInfos[name] = {
				Id = id,
				Text = info.Text,
				Desc = info.Desc or "",
				Icon = info.Icon,
				Triggered = triggered
			}
		end
		for name, info in configs.Menus do
			local contents
			if typeof(info.Contents) == "function" then
				contents = info.Contents(utils)
			else
				contents = info.Contents
			end
			local newMenu = Manager.createContextMenu(PluginUI.getId(info.Id, true), contents)

			table.insert(stored, newMenu.Menu)
			for _, v in newMenu.SubMenus do
				table.insert(stored, v.Menu)
			end
			state.InstanceContextMenus[info.Id] = {
				Menu = newMenu,
				Condition = info.Condition,
				Priority = info.Priority
			}
		end
	end
	local function killRefreshThread()
		if currentRefreshThread then
			if coroutine.status(currentRefreshThread) == "dead" then
				currentRefreshThread = nil
			else
				repeat
					task.cancel(currentRefreshThread)
				until coroutine.status(currentRefreshThread) == "dead"
				currentRefreshThread = nil
			end
		end
	end
	function refreshThread(inst: Instance)
		killRefreshThread()
		currentRefreshThread = task.spawn(refresh, inst)
	end
	
	local function findConfigs(moduleName: string)
		local result = game:QueryDescendants(`[Name = "{moduleName}"]`)
		if #result > 1 then warn(`More than 1 Instance named '{moduleName}'`) return end
		local inst = result[1]
		if not inst then warn(`ContextMenuConfigs module with name '{moduleName}' not found`) return end
		-- If it errors wont affect this thread
		refreshThread(inst)
		
	end
	if moduleName ~= "" then
		findConfigs(moduleName)
	end
	nameBox:OnChange(findConfigs)
	game.DescendantAdded:Connect(function(inst)
		if inst ~= currentlyUsedModule and inst.Name == nameBox:Get() then
			refreshThread(inst)
		end
	end)
end

return ContextMenuEditor