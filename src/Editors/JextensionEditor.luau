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

local Types = require(main.Types)

local rawindex = RawInst.rawindex

local init = false

local JextensionEditor = {} :: Types.JextensionEditor

local currentlyUsedModule: Instance?
function JextensionEditor.init(Manager)
	init = true
	local state = Manager.WidgetState
	local components = Manager.Components
	
	local jexplorerUi = state.JExplorerUI
	local topbar = jexplorerUi.Topbar

	local connections = state.Connections
	local instances = connections:extend(cleanup.destroy)

	local widget, mainframe = PluginUI.createEditorWidget(UITemplates.EditorFrame(), "JextensionEditor", "Jextension Editor")
	JextensionEditor.Widget = widget
	Manager.Style:Link(widget)
	
	local list = PluginUI.createItemListFromExisting(mainframe, mainframe.Items.Content, mainframe.Items)
	
	local moduleName = plugin:GetSetting("JextensionModuleName") or ""
	local nameBox = PluginUI.createAttributeBox(list, "Module Name", moduleName, function(v)
		plugin:SetSetting("JextensionModuleName", v)
	end)
	local delayBox = PluginUI.createAttributeBox(list, "Source Changed Refresh Delay", plugin:GetSetting("JextensionRefreshDelay") or "0.5", function(v)
		assert(tonumber(v), `'{v}' could not be converted into number`)
		plugin:SetSetting("JextensionRefreshDelay", v)
	end)
	
	local defaultInstanceCtxMenus = table.clone(state.InstanceContextMenus)
	local defaultActions = table.clone(Manager.PluginActions)
	
	local refreshDebounceThread: thread? = nil
	local sourceChangedConn: RBXScriptConnection?
	local function refresh(module: Instance)
		if not module:IsA("ModuleScript") then return end
		
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

		local fn = (require::any)(clone)
		assert(type(fn) == "function", "Jextension must return a function")
		
		fn(plugin, Manager)
	end
	local function findConfigs(moduleName: string)
		local result = game:QueryDescendants(`[Name = "{moduleName}"]`)
		if #result > 1 then warn(`More than 1 Instance named '{moduleName}'`) return end
		local inst = result[1]
		if not inst then warn(`Jextension module with name '{moduleName}' not found`) return end
		-- If it errors wont affect this thread
		task.spawn(refresh, inst)
	end
	if moduleName ~= "" then
		findConfigs(moduleName)
	end
	nameBox:OnChange(findConfigs)
	game.DescendantAdded:Connect(function(inst)
		local expectedName = nameBox:Get()
		if expectedName == "" then return end
		if inst.Name == nameBox:Get() then
			refresh(inst)
		end
	end)
end

return JextensionEditor