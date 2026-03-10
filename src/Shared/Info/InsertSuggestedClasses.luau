local INSERT_SUGGESTED_CLASSES: {[string]: {string}} = {
	Workspace = {
		"Part",
		"MeshPart",
		"Model",
		"Folder"
	},
	Players = {},
	CoreGui = {
		"ScreenGui",
	},
	Lighting = {
		"Sky",
		"Atmosphere",
		"SunRaysEffect",
		"ColorCorrectionEffect",
		"BlurEffect",
		"BloomEffect",
		"DepthOfFieldEffect"
	},
	MaterialService = {
		"MaterialVariant",
		"Folder"
	},
	NetworkClient = {},
	PluginGuiService = {},
	ReplicatedFirst = {
		"LocalScript",
		"Folder"
	},
	ReplicatedStorage = {
		"Folder",
		"ModuleScript",
		"RemoteEvent",
		"RemoteFunction"
	},
	ServerScriptService = {
		"Script",
		"ModuleScript",
		"Folder"
	},
	ServerStorage = {
		"Script",
		"ModuleScript",
		"Folder"
	},
	SoundService = {
		"Sound",
		"SoundGroup",
		"Folder"
	},
	StarterGui = {
		"Frame",
		"TextButton",
		"TextLabel",
		"TextBox",
		"ImageButton",
		"ImageLabel",
		"ScreenGui",
		"BillboardGui",
		"SurfaceGui"
	},
	StarterPack = {
		"Tool",
		"LocalScript"
	},
	StarterPlayer = {
		"LocalScript",
		"Folder",
		"BindableFunction",
		"BindableEvent"
	},
	Teams = {
		"Team"
	},
	TextChatService = {
		"TextChatCommand",
		"TextChannel"
	},
	StylingService = {
		"StyleSheet",
		"StyleRule",
		"StyleDerive"
	}
}
return INSERT_SUGGESTED_CLASSES