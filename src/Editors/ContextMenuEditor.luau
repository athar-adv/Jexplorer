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

local Types = require(main.Types)

local rawindex = RawInst.rawindex

local init = false

local ContextMenuEditor = {} :: Types.ContextMenuEditor

type MenuDef = {
	Id: string,
	Priority: number,
	Condition: (manager: Types.Manager, target: Types.ExplorerEntity) -> boolean,
	Contents: ((utils: ContextMenuUtils) -> {any}) | {any},
}
type ContextMenuConfigs = {
	Menus: {MenuDef},
	Actions: {
		[string]: {
			Id: string?,
			Callback: (manager: Types.Manager, target: Types.ExplorerEntity) -> (),
			Text: string,
			Desc: string?,
			Icon: (() -> string)?
		}
	}
}

type ContextMenuUtils = {
	createInterface: (defaultName: string) -> ContextMenuInterface,
	getMenuIds: () -> {string},
	createModifiedMenu: (menuId: string, newContents: (ContextMenuInterface) -> {any}) -> MenuDef
}

type ContextMenuInterface = {
	GetMenuContents: () -> {any},
	GetSubMenu: (name: string) -> ContextMenuInterface,
	
	Remove: (idx: number) -> (),
	Insert: (idx: number, v: any) -> (),
	
	FindAction: (name: string) -> number,
	FindSubMenu: (name: string) -> number,
	
	Relocate: (name: string, newIndex: number) -> (),
	FlipOrder: () -> ()
}

local function createCtxMenuInterface(actions: any): ContextMenuInterface
	return {
		GetMenuContents = function() return actions end,
		GetSubMenu = function(name)
			local subMenus = {}
			for _, v in actions do
				if type(v) ~= "table" then continue end
				if v.Id ~= name then continue end
				return createCtxMenuInterface(v[1])
			end
			error(`SubMenu '{name}' not found`)
		end,
		Relocate = function(name, newIndex)
			local idx = table.find(actions, name)
			if idx then
				table.remove(actions, idx)
			end
			table.insert(actions, newIndex, name)
		end,
		FlipOrder = function()
			local reversed = {}
			for i = #actions, 1, -1 do
				table.insert(reversed, actions[i])
			end
			actions = reversed
		end,
		
		Remove = function(idx)
			table.remove(actions, idx)
		end,
		Insert = function(idx, v)
			table.insert(actions, idx, v)
		end,
		
		FindAction = function(name)
			return assert(table.find(actions, name), `Action {name} not found`)
		end,
		FindSubMenu = function(name)
			for i, v in actions do
				if type(v) ~= "table" then continue end
				if v.Id ~= name then continue end
				return i
			end
			error(`SubMenu '{name}' not found`)
		end,
	}
end

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
	
	local defaultInstanceCtxMenus = table.clone(state.InstanceContextMenus)
	local defaultActionInfos = table.clone(Manager.ActionInfos)
	local defaultActions = table.clone(Manager.BindableActions)
	
	local refreshDebounceThread: thread? = nil
	local sourceChangedConn: RBXScriptConnection?
	local currentStored = connections:extend(cleanup.destroy)
	
	local function getCtxMenuInterface(defaultActionsName: string?)
		local tbl
		if defaultActionsName and state.InstanceContextMenus[defaultActionsName] then
			tbl = table.clone(state.InstanceContextMenus[defaultActionsName].Menu.Contents)
		else
			tbl = {}
		end
		return createCtxMenuInterface(tbl)
	end
	
	local utils: ContextMenuUtils = {
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
			local menu = Manager.createContextMenu(
				PluginUI.getId(menuId, true), contents
			)
			
			return {
				Id = menuId,
				Priority = menuInfo.Priority,
				Condition = function(manager, target)
					return menuInfo.Condition(manager, target, assert(Manager.instanceOf(target)))
				end,
				Contents = contents
			}
		end,
	}
	
	local function refresh(module: Instance)
		if not module:IsA("ModuleScript") then return end
		state.InstanceContextMenus = defaultInstanceCtxMenus
		Manager.ActionInfos = defaultActionInfos
		Manager.BindableActions = defaultActions
		
		currentStored:free()
		currentStored = connections:extend(cleanup.destroy)
		
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
				refresh(module)
				refreshDebounceThread = nil
			end)
		end)
		
		local returnval: ContextMenuConfigs | (Plugin, Types.Manager, ContextMenuUtils, {any}) -> ContextMenuConfigs = (require::any)(clone)
		local configs: ContextMenuConfigs
		if type(returnval) == "function" then
			configs = returnval(plugin, Manager, utils, table.clone(state.DefaultInstanceActionsArray))
		elseif type(returnval) == "table" then
			configs = returnval
		else
			error("ContextMenu module must return (Plugin, Manager) -> ContextMenuConfigs or ContextMenuConfigs.")
		end
		
		for name, info in configs.Actions do
			local id = info.Id or `JexplorerCustomAction({tostring(os.clock())})`
			
			local action = Manager.createPluginAction(
				id, info.Text, info.Desc or "", if info.Icon then info.Icon() else nil
			)
			currentStored:add(action)
			
			local function triggered()
				local target = Manager.takeContextTarget()
				info.Callback(Manager, target)
			end
			
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
			
			currentStored:add(newMenu.Menu)
			for _, v in newMenu.SubMenus do
				currentStored:add(v.Menu)
			end
			state.InstanceContextMenus[info.Id] = {
				Menu = newMenu,
				Condition = info.Condition,
				Priority = info.Priority
			}
		end
	end
	local function findConfigs(moduleName: string)
		local result = game:QueryDescendants(`[Name = "{moduleName}"]`)
		if #result > 1 then warn(`More than 1 Instance named '{moduleName}'`) return end
		local inst = result[1]
		if not inst then warn(`ContextMenuConfigs module with name '{moduleName}' not found`) return end
		-- If it errors wont affect this thread
		task.spawn(refresh, inst)
	end
	if moduleName ~= "" then
		findConfigs(moduleName)
	end
	nameBox:OnChange(findConfigs)
	game.DescendantAdded:Connect(function(inst)
		if inst.Name == nameBox:Get() then
			refresh(inst)
		end
	end)
end

return ContextMenuEditor