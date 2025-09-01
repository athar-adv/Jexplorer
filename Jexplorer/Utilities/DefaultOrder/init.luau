local Types = require("../Types")

return function(manager: Types.Manager)
	return {
		manager.AbstractEntClasses.Favorited,
		"Workspace",
		"Players",
		"CoreGui",
		"Lighting",
		"MaterialService",
		"NetworkClient",
		"PluginGuiService",
		"ReplicatedFirst",
		"ReplicatedStorage",
		"ServerScriptService",
		"ServerStorage",
		"StarterGui",
		"StarterPack",
		"StarterPlayer",
		"Teams",
		"SoundService",
		"TextChatService",

		"ChatWindowConfiguration",
		"ChatInputBarConfiguration",
		"ChannelTabsConfiguration",
		"BubbleChatConfiguration",

		"PackageLink",

		"Camera",
		"Terrain",
		"Folder",

		"Tool",

		"ScreenGui",
		"SurfaceGui",
		"BillboardGui",
		"DockWidgetPluginGui",
		"QWidgetPluginGui",

		"UIListLayout",
		"UIGridLayout",
		"UITableLayout",
		"UIPageLayout",
		"UIPadding",
		"UICorner",
		"UIGradient",
		"UIStroke",
		"UITextSizeConstraint",
		"UIAspectRatioConstraint",
		"UISizeConstraint",
		"UIScale",

		"AudioDeviceOutput",
		"AudioPlayer",
		"Wire",

		"Frame",
		"CanvasGroup",
		"ImageLabel",
		"ImageButton",
		"TextLabel",
		"TextBox",
		"TextButton",

		"StandalonePluginScripts",

		"BindableEvent",
		"BindableFunction",
		"RemoteEvent",
		"UnreliableRemoteEvent",
		"RemoteFunction",

		"Actor",
		"Script",
		"LocalScript",
		"ModuleScript",

		"Model",
		"Part",
		"MeshPart",
		"UnionOperation"
	}
end