--!strict
local Types = require(script.Parent.Parent.Parent.Types)
local Style = require(script.Parent.Parent.Style)

local var = Style.var

return {
	ExpandBehavior = {
		AutoExpandOnSelect = {
			Type = "boolean",
			Display = "Auto-expand Ancestors on Select Unexpanded Instance",
			Default = true,
		},
	},
	SelectBehavior = {
		PropertyEditorUpdatedOnSelect = {
			Type = "boolean",
			Display = "Property Editor (JProperties) Updated on Selection Changed",
			Default = false
		},
		DoubleClickToOpenScriptTime = {
			Type = "number",
			Display = "Cooldown to Double Click to Open Script",
			Default = 0.2
		},
		DoubleClickToRenameTime = {
			Type = "number",
			Display = "Cooldown to Double Click to Rename",
			Default = 0.5
		}
	},
	SavingBehavior = {
		AutosaveInstChanged = {
			Type = "boolean",
			Display = "Autosave Instance Changes",
			Default = false
		},
		SaveOnClose = {
			Type = "boolean",
			Display = "Save On Close",
			Default = false
		}
	},
	ScrollBehavior = {
		SmoothScrollEnabled = {
			Type = "boolean",
			Display = "Smooth Scroll Enabled",
			Default = false,
			OnChange = function(Manager, newValue)
				local jexplorerUi = Manager.WidgetState.JExplorerUI
				jexplorerUi.InstanceTree.ScrollingEnabled = newValue
			end
		},
		ScrollStep = {
			Type = "number",
			Display = "Non-smooth Scroll Step",
			Default = 40,
		},
		ScrollThreshold = {
			Type = "number",
			Display = "Non-smooth Scroll Threshold",
			Default = 1,
		},
		--VirtualScrollingEnabled = {
		--	Type = "boolean",
		--	Display = "Virtual Scrolling Enabled",
		--	Default = true,
		--	OnChange = function(Manager, newValue)
		--		local state = Manager.WidgetState
		--		local components = Manager.Components
				
		--		local ui = script.Parent.Parent.UI
		--		local jexplorerUi = state.JExplorerUI
				
		--		local world = state.World

		--		if not newValue then
		--			if not jexplorerUi.InstanceTree:FindFirstChildOfClass("UIListLayout") then
		--				local list = Instance.fromExisting(ui.UIListLayout)
		--				list.Parent = jexplorerUi.InstanceTree
		--			end
		--			if not ui.InstanceFrame.Children.List:FindFirstChildOfClass("UIListLayout") then
		--				local list = Instance.fromExisting(ui.UIListLayout)
		--				list.Parent = ui.InstanceFrame.Children.List
		--			end
		--			for _, v in jexplorerUi.InstanceTree:GetDescendants() do
		--				if v.Name == "List" and not v:FindFirstChildOfClass("UIListLayout") then
		--					local list = Instance.fromExisting(ui.UIListLayout)
		--					list.Parent = v
		--				end
		--			end
		--			for _, entity in Manager.getVisibleEntities(world, {}) do
		--				local frame: Types.InstanceFrame? = world:get(entity, components.Frame)
		--				if not frame then
		--					local frame = Manager.getInstanceFrame()
		--					world:set(entity, components.Frame, frame)
		--					frame:Assign(entity, world:parent(entity))
		--					frame.Instance.Children.List.Size = UDim2.fromScale(1, 1)
		--				else
		--					frame:Assign(entity, world:parent(entity))
		--					frame.Instance.Children.List.Size = UDim2.fromScale(1, 1)
		--				end
		--			end
		--		else
		--			if jexplorerUi.InstanceTree:FindFirstChildOfClass("UIListLayout") then
		--				jexplorerUi.InstanceTree.UIListLayout:Destroy()
		--			end
		--			if ui.InstanceFrame.Children.List:FindFirstChildOfClass("UIListLayout") then
		--				ui.InstanceFrame.Children.List.UIListLayout:Destroy()
		--			end
		--			for _, v in jexplorerUi.InstanceTree:GetDescendants() do
		--				if v:IsA("UIListLayout") then 
		--					v:Destroy()
		--				end
		--			end
		--		end
		--	end
		--},
		VirtualScrollFrameBuffer = {
			Type = "number",
			Display = "Virtual Scrolling Instance Frame Buffer",
			Default = 3,
		},
		VirtualScrollSettleTime = {
			Type = "number",
			Display = "Virtual Scrolling Scroll Settle Time",
			Default = var "1/20",
		},
		VirtualReuseCooldown = {
			Type = "number",
			Display = "Virtual Frame Reuse Cooldown",
			Default = 0,
		},
	},
} :: {
	[string]: {
		[string]: {
			Type: string,
			Display: string,
			Default: any,
			OnChange: ((m: Types.Manager, newValue: any) -> ())?
		}
	}
}