--!strict
--!optimize 2

local plugin = script:FindFirstAncestorOfClass("Plugin")

local main = script.Parent.Parent

local utilities = main.Utilities
local ui = main.UI

local PluginUI = require(utilities.PluginUI)
local InstanceUtility = require(utilities.InstanceUtility)

local Types = require(main.Types)

local rawindex = InstanceUtility.rawindex

local init = false

local ContextMenuEditor = {} :: Types.ContextMenuEditor

type ContextMenuConfigs = {
	Menus: {
		[string]: {string}
	},
	Actions: {
		[string]: {
			Callback: (manager: Types.Manager, target: Types.InstanceEntity) -> (),
			Text: string,
			Tooltip: string,
			Icon: string?
		}
	}
}

local currentlyUsedModule: Instance?

function ContextMenuEditor.init(Manager)
	init = true
	local state = Manager.WidgetState
	local components = Manager.Components
	
	local jexplorerUi = state.JExplorerUI
	local topbar = jexplorerUi.Topbar

	local connections = state.Connections
	local instances = connections:Extend("Destroy")

	local widget, mainframe = PluginUI.createEditorWidget(ui.EditorFrame, "ContextMenuEditor", "Context Menu Editor")
	ContextMenuEditor.Widget = widget
	Manager.Style:Link(widget)
	
	local list = PluginUI.createItemListFromExisting(mainframe, mainframe.Items)
	
	local modulepath = plugin:GetSetting("ContextMenuConfigsModulePath") or ""
	local pathBox = PluginUI.createAttributeBox(list, "Module Path", modulepath, function(v)
		plugin:SetSetting("ContextMenuConfigsModulePath", v)
	end)
	
	local defaultCtxMenus = table.clone(Manager.ContextMenus)
	local defaultActions = table.clone(Manager.PluginActions)
	
	local function refresh()
		local path: string = pathBox:Get()
		if path == "" then
			Manager.ContextMenus = defaultCtxMenus
			Manager.PluginActions = defaultActions
			return
		end
		local segments = string.split(path, "/")

		local current = game
		for _, v in segments do
			current = rawindex(current, v)
		end
		
		assert(current:IsA("ModuleScript"), "context menu configs path must lead to a ModuleScript")
		
		if currentlyUsedModule then
			currentlyUsedModule:Destroy()
		end
		local clone = current:Clone()
		currentlyUsedModule = clone
		
		clone.Source = current.Source
		clone.Parent = plugin
		
		local configs: ContextMenuConfigs = (require::any)(clone)

		for name, info in configs.Actions do
			local action = plugin:CreatePluginAction(
				tostring(os.clock()), info.Text, info.Tooltip, info.Icon
			)
			action.Triggered:Connect(function()
				local target = Manager.WidgetState.ContextTarget
				if not target then return end
				info.Callback(Manager, target)
			end)
			Manager.PluginActions[name] = action
		end
		for name, actionNames in configs.Menus do
			--local menu = Manager.ContextMenus[name]
			--assert(menu, `ContextMenu '{name}' doesn't exist.`)

			local newMenu = Manager.createContextMenu(tostring(os.clock()), actionNames)
			Manager.ContextMenus[name] = newMenu
		end
	end
	
	if modulepath ~= "" then
		-- If it errors wont affect this thread
		task.spawn(refresh)
	end
	PluginUI.createButton(list, "Refresh Module", refresh)
end

return ContextMenuEditor