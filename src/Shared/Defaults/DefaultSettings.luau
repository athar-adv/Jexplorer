--!strict
local Types = require(script.Parent.Parent.Parent.Types)
local Style = require(script.Parent.Parent.Style)

local var = Style.var

return {
	Internal = {
		EntityDeletionFlushStep = {
			Type = "number",
			Display = "Entity Deletion Flush Step",
			Default = 30
		}
	},
	Query = {
		QueryAutocompleteEnabled = {
			Type = "boolean",
			Display = "Query Autocomplete Enabled",
			Default = true
		}
	},
	Duplicate = {
		IncrementNamesWithNoNumberSuffix = {
			Type = "boolean",
			Display = "Increment Names With No Number Suffix",
			Default = false,
		},
		NormalDuplicateIncrementsName = {
			Type = "boolean",
			Display = "Normal Duplicate Increments Name",
			Default = true
		},
	},
	Keybinds = {
		KeybindEscapeTarget = {
			Type = "string",
			Display = "Escape Target",
			Default = "Escape | (Shift & Backspace)"
		},
		KeybindDeleteTarget = {
			Type = "string",
			Display = "Delete Target",
			Default = "Delete | Backspace"
		},
		KeybindDuplicateTarget = {
			Type = "string",
			Display = "Duplicate Target",
			Default = "Control & D"
		},
		KeybindDuplicateTargetWithIncrementName = {
			Type = "string",
			Display = "Duplicate Target With Increment Name",
			Default = "Control & D & E"
		},
		KeybindCopy = {
			Type = "string",
			Display = "Copy",
			Default = "Control & C"
		},
		KeybindPaste = {
			Type = "string",
			Display = "Paste",
			Default = "Control & V"
		},
		KeybindUndo = {
			Type = "string",
			Display = "Undo",
			Default = "Control & Z"
		},
		KeybindRedo = {
			Type = "string",
			Display = "Redo",
			Default = "Control & Y"
		},
	},
	Expand = {
		AutoExpandOnSelect = {
			Type = "boolean",
			Display = "Auto-expand Ancestors on Select Unexpanded Instance",
			Default = true,
		},
		StickyStacksEnabled = {
			Type = "boolean",
			Display = "Sticky Stack Breadcrumb when Ancestors Are Expanded",
			Default = true
		}
	},
	Selection = {
		JumpToSelection = {
			Type = "boolean",
			Display = "Jump to Middle of Selection",
			Default = true,
		},
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
	Saving = {
		AutosaveInstChanged = {
			Type = "boolean",
			Display = "Autosave Instance Changes",
			Default = true
		},
		SaveOnClose = {
			Type = "boolean",
			Display = "Save On Close",
			Default = true
		}
	},
	Language = {
		DocumentationLanguage = {
			Type = "string",
			Display = "Documentation Language (Roblox | System | locale-id)",
			Default = "Roblox"
		}
	},
	Scrolling = {
		--SmoothScrollEnabled = {
		--	Type = "boolean",
		--	Display = "Smooth Scroll Enabled",
		--	Default = false,
		--	OnChange = function(Manager, newValue)
		--		local jexplorerUi = Manager.WidgetState.JExplorerUI
		--		jexplorerUi.InstanceTree.ScrollingEnabled = newValue
		--	end
		--},
		ScrollStep = {
			Type = "number",
			Display = "Scrolling Step (offsets)",
			Default = 20,
		},
		--ScrollThreshold = {
		--	Type = "number",
		--	Display = "Non-smooth Scroll Threshold",
		--	Default = 1,
		--},
		VirtualScrollFrameBuffer = {
			Type = "number",
			Display = "Virtual Scrolling Instance Frame Buffer",
			Default = 10,
		},
		VirtualScrollSettleTime = {
			Type = "number",
			Display = "Virtual Scrolling Scroll Settle Time",
			Default = var "1/20",
		},
		--VirtualReuseCooldown = {
		--	Type = "number",
		--	Display = "Virtual Frame Reuse Cooldown",
		--	Default = 0,
		--},
	},
	ExplorerFrame = {
		IndentWidth = {
			Type = "number",
			Display = "ExplorerFrame Children Indent Width",
			Default = 20,
			OnChange = function(Manager)
				Manager.VirtualScroller.rebuildAndUpdate(Manager, false)
			end,
		},
		FrameHeight = {
			Type = "number",
			Display = "ExplorerFrame Frame Height",
			Default = 20,
			OnChange = function(Manager)
				Manager.VirtualScroller.rebuildAndUpdate(Manager, false)
			end,
		}
	}
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