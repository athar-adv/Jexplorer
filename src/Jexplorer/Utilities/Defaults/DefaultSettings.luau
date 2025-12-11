--!strict
local Types = require(script.Parent.Parent.Parent.Types)
local Style = require(script.Parent.Parent.Style)

local var = Style.var

return {
	InternalBehavior = {
		FlushCycleInterval = {
			Type = "number",
			Display = "Queue Flush Cycle Interval",
			Default = 1/30
		},
		FrameReuseCycleInterval = {
			Type = "number",
			Display = "ExplorerFrame Reuse & HierarchyCache Rebuild Cycle Interval",
			Default = 1/30
		},
		EntityCleanupCycleInterval = {
			Type = "number",
			Display = "ExplorerEntity Cleanup Cycle Interval",
			Default = 0.25
		},
		EntityCreationCycleInterval = {
			Type = "number",
			Display = "ExplorerEntity Creation Cycle Interval",
			Default = 1/30
		}
	},
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