local INSERT_SUGGESTED_CLASSES: {[string]: {string}} = {
	Workspace = {
		"Part",
		"MeshPart",
		"Model",
		"Folder",
		"Pointer",
	},
	Players = {
		"Pointer"
	},
	CoreGui = {
		"ScreenGui",
		"Pointer"
	},
	Lighting = {
		"Sky",
		"Atmosphere",
		"SunRaysEffect",
		"ColorCorrectionEffect",
		"BlurEffect",
		"BloomEffect",
		"DepthOfFieldEffect",
		"Pointer"
	},
	MaterialService = {
		"MaterialVariant",
		"Folder",
		"Pointer"
	},
	NetworkClient = {},
	PluginGuiService = {},
	ReplicatedFirst = {
		"LocalScript",
		"Folder",
		"Pointer"
	},
	ReplicatedStorage = {
		"Folder",
		"ModuleScript",
		"RemoteEvent",
		"RemoteFunction",
		"BindableEvent",
		"BindableFunction",
		"Pointer"
	},
	ServerScriptService = {
		"Script",
		"ModuleScript",
		"Folder",
		"Pointer",
	},
	ServerStorage = {
		"Script",
		"ModuleScript",
		"Folder",
		"Pointer"
	},
	SoundService = {
		"Sound",
		"SoundGroup",
		"Folder",
		"Pointer"
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
		"SurfaceGui",
		"Pointer"
	},
	StarterPack = {
		"Tool",
		"LocalScript",
		"Pointer"
	},
	StarterPlayer = {
		"LocalScript",
		"Folder",
		"BindableFunction",
		"BindableEvent",
		"Pointer"
	},
	Teams = {
		"Team",
		"Pointer"
	},
	TextChatService = {
		"TextChatCommand",
		"TextChannel",
		"Pointer"
	},
	StylingService = {
		"StyleSheet",
		"StyleRule",
		"StyleDerive",
		"Pointer"
	}
}
return INSERT_SUGGESTED_CLASSES