return {
	Input = {
		"ProximityPrompt",
		"ClickDetector",
		"DragDetector",
		"UIDragDetector",
		"InputAction",
		"InputBinding",
		"InputContext"
	},
	
	UI = {
		"SurfaceGui",
		"BillboardGui",
		"ScreenGui",
		"Frame",
		"TextLabel",
		"TextButton",
		"TextBox",
		"ImageLabel",
		"ImageButton",
		"ScrollingFrame",
		"CanvasGroup",
		"UICorner",
		"UIStroke",
		"UIGradient",
		"UIListLayout",
		"UIGridLayout",
		"UIPageLayout",
		"UITableLayout",
		"UIPadding",
		"UIScale",
		"UISizeConstraint",
		"UITextSizeConstraint",
		"UIAspectRatioConstraint",
		"ViewportFrame",
		"Path2D"
	},
	
	Chatting = {
		"TextChatCommand",
		"TextChannel"
	},

	Scripting = {
		"Script",
		"LocalScript",
		"ModuleScript",
		"RemoteEvent",
		"RemoteFunction",
		"BindableEvent",
		"BindableFunction",
		"Actor"
	},
	
	Value = {
		"ObjectValue",
		"StringValue",
		"IntValue",
		"NumberValue",
		"BoolValue",
		"Vector3Value",
		"CFrameValue",
		"Color3Value",
		"BrickColorValue",
		"RayValue"
	},
	
	Style = {
		"StyleSheet",
		"StyleRule",
		"StyleDerive",
		"StyleLink"
	},

	Parts = {
		"Part",
		"WedgePart",
		"CornerWedgePart",
		"TrussPart",
		"UnionOperation",
		"NegateOperation",
		"MeshPart"
	},

	Lighting = {
		"Camera",
		"PointLight",
		"SpotLight",
		"SurfaceLight",
		"Sky",
		"Atmosphere",
		"Clouds",
		"SunRaysEffect",
		"BloomEffect",
		"BlurEffect",
		"ColorCorrectionEffect",
		"DepthOfFieldEffect"
	},

	Constraints = {
		"Motor6D",
		"Weld",
		"AnimationConstraint",
		"AlignOrientation",
		"AlignPosition",
		"AngularVelocity",
		"Attachment",
		"BallSocketConstraint",
		"HingeConstraint",
		"PrismaticConstraint",
		"CylindricalConstraint",
		"RodConstraint",
		"RopeConstraint",
		"SpringConstraint",
		"WeldConstraint",
		"RigidConstraint",
		"NoCollisionConstraint",
		"UniversalConstraint"
	},
	
	Pathfinding = {
		"PathfindingLink",
		"PathfindingModifier"
	},

	Sounds = {
		"Sound",
		"SoundGroup",
		"ChorusSoundEffect",
		"CompressorSoundEffect",
		"DistortionSoundEffect",
		"EchoSoundEffect",
		"EqualizerSoundEffect",
		"FlangeSoundEffect",
		"PitchShiftSoundEffect",
		"ReverbSoundEffect",
		"TremoloSoundEffect",
	},
	
	Audio = {
		"AudioTextToSpeech",
		"AudioSpeechToText",
		"Wire",
		"AudioDeviceInput",
		"AudioDeviceOutput",
		"AudioPlayer",
		"AudioAnalyzer",
		"AudioChannelMixer",
		"AudioChannelSplitter",
		"AudioChorus",
		"AudioCompressor",
		"AudioEcho",
		"AudioDistortion",
		"AudioGate",
		"AudioLimiter",
		"AudioListener",
		"AudioEmitter",
		"AudioFilter",
		"AudioFlanger",
		"AudioReverb",
		"AudioPitchShifter",
		"AudioTremolo"
	},

	Meshes = {
		"SpecialMesh",
		"BlockMesh",
		"CylinderMesh",
		"FileMesh"
	},

	Textures = {
		"Texture",
		"Decal",
		"SurfaceAppearance",
		"MaterialVariant"
	},

	Gameplay = {
		"SpawnLocation",
		"Team",
		"Seat",
		"VehicleSeat",
		"Tool",
		"HopperBin",
		"Flag",
		"FlagStand",
		"Dialog",
		"DialogChoice"
	},

	Humanoid = {
		"Humanoid",
		"HumanoidDescription",
		"Accessory",
		"Hat",
		"Shirt",
		"Pants",
		"ShirtGraphic",
		"BodyColors",
		"BodyPartDescription",
		
		"ControllerManager",
		"ControllerPartSensor",
		"AirController",
		"ClimbController",
		"GroundController",
		"SwimController"
	},

	Animation = {
		"Animator",
		"Animation",
		"AnimationController",
		"Keyframe",
		"KeyframeSequence",
	},

	Grouping = {
		"Model",
		"Folder",
		"Configuration"
	},

	Effects = {
		"Explosion",
		"Fire",
		"Smoke",
		"Sparkles",
		"ParticleEmitter",
		"Trail",
		"Beam",
		"Highlight"
	},
	
	Adornments = {
		"SelectionBox",
		"SelectionSphere",
		"Handles",
		"ArcHandles",
		"SurfaceSelection"
	},

	Physics = {
		"LinearVelocity",
		"VectorForce",
		"LineForce",
		"WorldModel",
		"IKControl"
	},
	
	Sensors = {
		"AtmosphereSensor",
		"FluidForceSensor",
		"BuoyancySensor"
	},
	
	--Scriptable = {
	--	"TeleportOptions",
	--	"DataStoreOptions",
	--	"DataStoreGetOptions",
	--	"DataStoreSetOptions",
	--	"DataStoreIncrementOptions",
	--	"ExperienceInviteOptions",
	--	"AudioSearchParams",
	--}
} :: {[string]: {string}}