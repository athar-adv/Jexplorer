--!strict

local main = script.Parent

local shared = main.Shared
local ui = main.__legacy.UI

local PluginUI = require(shared.PluginUI)
local Style = require(shared.Style)
local GitAPI = require(shared.GitAPI)

local ItemGroup = require(shared.Vendor.ItemGroup)
local SimpleSignal = require(shared.Vendor.SimpleSignal)
local ColorPicker = require(shared.Vendor.PluginColorPicker)

local Jecs = require(main.Jecs)

type Array<T> = {T}
export type InstanceId = string
export type TempId = string
type UDFValue = string
type PlaceId = string

export type SerializedStyleRule = {
	display_name: string,
	selector: string,
	priority: number,
	props: {[string]: UDFValue},
	rules: {SerializedStyleRule}
}
export type SavedState = {
	repo_proxies: {
		[PlaceId]: Array<{
			display_name: string,
			repo_id: string,
			root_inst_id: InstanceId
		}>
	},
	tabs: {
		[PlaceId]: Array<{
			display_name: string,
			icon: string,
			icon_color: UDFValue,
			inst_ids: {InstanceId}
		}>
	},
	display_order: {
		default_order: number,
		class_order: {string}
	},
	data_version: number,
	invisible: {[string]: boolean},
	settings: {[string]: UDFValue},
	style: {
		rules: {SerializedStyleRule},
		tokens: {[string]: UDFValue}
	},
	icon_colors: {
		[PlaceId]: {[InstanceId]: UDFValue}
	},
	versions: {
		[PlaceId]: {
			[InstanceId]: {
				{
					timestamp: typeof(DateTime.now():ToUniversalTime()),
					props: {[string]: UDFValue},
				}
			}
		}
	},
}

export type ItemGroup<T=any> = ItemGroup.ItemGroup<T>
type Signal<T... = ()> = SimpleSignal.SimpleSignal<T...>
export type DragInfo_SetInstTypeProperty = {
	-- Set instance type properties
	Type: "setproperty",
	TargetInstances: {Instance},
	PropertyName: string
}
export type DragInfo_ReparentInstances = {
	-- Drag into
	Type: "reparent",
	Entities: {ExplorerEntity},
}
export type StudioIconResult = {
	Image: string,
	ImageRectOffset: Vector2,
	ImageRectSize: Vector2
}
export type ContextMenu = {
	Actions: {PluginAction},
	Menu: PluginMenu,
	SubMenus: {ContextMenu},
	UnprocessedContents: {any},
	Id: string
}
export type Tab = {
	TabFrame: GuiObject,
	Button: GuiButton,
	InsertButton: GuiButton?,
	RemoveButton: GuiButton?,
	NameBox: TextBox,
	IconLabel: ImageLabel,

	Roots: {ExplorerEntity},
	Name: string,
	Icon: string,
	IconColor: Color3,

	Toggle: () -> (),
	Remove: () -> (),
}
export type RepoProxy = {
	DisplayName: string,
	RepoId: string,
	Root: Instance,

	Remove: () -> ()
}
--export type InstanceFrame = {
--	Instance: typeof(ui.InstanceFrame),
--	Connections: Group.Group,
--	CurrentEntity: ExplorerEntity?,
--	TagsToRemove: {string},

--	Assign: (InstanceFrame, entity: ExplorerEntity?, parent: ExplorerEntity?) -> (),
--	ToggleSelection: (InstanceFrame, selected: boolean) -> (),
--	Reuse: (InstanceFrame) -> ()
--}
export type ExplorerFrame = Jecs.Id
export type PropertyItem = {
	name: string,
	type: ReflectionType,
	writable: boolean,
	readable: boolean
}

export type World = Jecs.World
export type ExplorerEntity = Jecs.Id
export type QueryEntity = Jecs.Id
export type FrameState = {
	isLMBActive: boolean,
	tagsToRemove: {string},
	hasBeenSelected: boolean,
	shouldDeselect: boolean,
	lastClickTime: number,
	packageIconConns: {RBXScriptConnection},
	pendingChangeIconConns: {RBXScriptConnection},
	lastPackageIconPos: number,
	isAssigning: boolean,
	setIconColor: Color3?,
	icon: ImageLabel,
	hasPackageLinkConn: boolean,
	hasPendingChangesConn: boolean,
	packageLinkIcon: ImageLabel,
	isVisible: boolean,
	instanceName: TextBox,
	pendingChanges: ImageLabel,
}

export type Components = {
	Selected: Jecs.Id,
	Expanded: Jecs.Id,
	AncestryLocked: Jecs.Id,
	ArrowInvisible: Jecs.Id,
	QueryAncestor: Jecs.Id,
	QueryExpanded: Jecs.Id,
	QueryInvisible: Jecs.Id,
	Invisible: Jecs.Id,
	IsQueried: Jecs.Id,
	PendingChanges: Jecs.Id,
	Deleted: Jecs.Id,
	DisplayTopLevel: Jecs.Id,
	
	CleanupTicket: Jecs.Id<{}>,
	DeletionTicket: Jecs.Id<{}>,
	ChildAddedTicket: Jecs.Id<{children: {Instance}}>,
	ChildMovedTicket: Jecs.Id<{children: {Instance}}>,
	CreationTicket: Jecs.Id<{children: {Instance}}>,
	PropAssignTicket: Jecs.Id<{ty: "virtual" | "instance"}>,
	
	FrameReuseTicket: Jecs.Id<{frame: ExplorerFrame}>,
	FrameTagAssignTicket: Jecs.Id<{frame: ExplorerFrame}>,
	
	FRAMEWORLD_FrameSetParentTicket: Jecs.Id<{newParent: Instance?}>,
	FRAMEWORLD_Main: typeof(main.__legacy.UI.InstanceFrame.Main),
	QUERYWORLD_ComponentHash: Jecs.Id<string>,
	
	Instance: Jecs.Id<Instance>,
	Frame: Jecs.Id<ExplorerFrame>,
	Entity: Jecs.Id<ExplorerEntity>,
	FrameState: Jecs.Id<FrameState>,
	FrameIconColor: Jecs.Id<Color3>,

	Connections: Jecs.Id<ItemGroup<RBXScriptConnection>>,
	ScriptErrors: Jecs.Id<{string}>,
	ScriptWarns: Jecs.Id<{string}>,
	QueryLinkedEntities: Jecs.Id<{ExplorerEntity}>,
	LinkedQueryEntity: Jecs.Id<QueryEntity>,
	ParentTabs: Jecs.Id<{[Tab]: boolean}>,
}

export type WidgetState = {
	World: World,
	QueryWorld: World,
	FrameWorld: World,
	InstanceTree: GuiObject,
	TreeScroller: ScrollingFrame,

	Connections: ItemGroup<RBXScriptConnection>,
	Entities: {ExplorerEntity},
	Widget: DockWidgetPluginGui,
	CurrentSelection: {ExplorerEntity},
	Favorited: {ExplorerEntity},
	Tabs: {Tab},
	RepoProxies: {RepoProxy},
	SavedState: SavedState,

	LastSelectedEntity: ExplorerEntity?,
	ContextTarget: ExplorerEntity?,

	CurrentlyRenaming: ExplorerEntity?,
	CurrentlyInserting: {Instance}?,
	IsDragging: boolean,

	JExplorerUI: typeof(ui.JExplorerUi),
	DefaultInstanceActionsArray: {any},
	InstanceContextMenus: {[string]: {Menu: ContextMenu, Condition: (manager: Manager, target: ExplorerEntity, instance: Instance) -> boolean, Priority: number}},
	MiscContextMenus: {[string]: ContextMenu},
	OverridePathBarText: string?
}

export type HierarchyState = {
	StateCache: {[ExplorerEntity]: {invisible: boolean, expanded: boolean, isTopLevel: boolean}},
	ChildrenMap: {[ExplorerEntity]: {ExplorerEntity}},

	cleanupEntities: (Manager) -> boolean,
	cleanupEntity: (Manager, ExplorerEntity) -> (),
	rebuildHierarchyCache: (Manager) -> ({[ExplorerEntity]: {ExplorerEntity}}, {ExplorerEntity}),
	getFlattenedVisibleEntities: (Manager, invisible: {ExplorerEntity}, isScroller: boolean) -> ({ExplorerEntity}, {[ExplorerEntity]: number}, {number}),

	invalidateEntityStateCache: (ExplorerEntity) -> (),

	flushEntityCreationQueue: (Manager) -> boolean,
	queueForEntityCreation: (Manager, parent: ExplorerEntity, children: {Instance}) -> (),

	flushEntityCleanupQueue: (Manager) -> boolean,
	queueForEntityCleanup: (Manager, entity: ExplorerEntity) -> (),

	flushOnChildAddedQueue: (Manager) -> boolean,
	queueForOnChildAdded: (Manager, new_parent: ExplorerEntity, child: Instance) -> (),

	flushOnChildRemovedQueue: (Manager) -> boolean,
	queueForOnChildRemoved: (Manager, old_parent: ExplorerEntity, child: Instance) -> (),

	stepFlushEntityDeletionQueue: (Manager) -> boolean,
	queueForEntityDeletion: (Manager, entity: ExplorerEntity) -> (),

	getEntitiesBetween: (Manager, e1: ExplorerEntity, e2: ExplorerEntity) -> {ExplorerEntity},

	flushEntityPropAssignQueue: (Manager) -> (),

	getOrCreateInstanceEntity: (Manager, instance: Instance, parent: ExplorerEntity?, dontSetInInstanceToEntity: boolean?) -> ExplorerEntity,
	createVirtualEntity: (Manager, options: {
		ClassName: string,
		Name: string,
		ChildAmount: number,
		ClassIcon: StudioIconResult,
		PropTags: {Jecs.Id},
		Parent: ExplorerEntity?
	}, extra: {[string]: any}) -> ExplorerEntity,
	createInstanceEntity: (Manager, instance: Instance, parent: ExplorerEntity?, dontSetInInstanceToEntity: boolean?) -> ExplorerEntity,

	deregisterFromQueryWorld: (Manager, entity: ExplorerEntity) -> (),
	registerIntoQueryWorld: (Manager, entity: ExplorerEntity, className: string, tags: {Jecs.Id}, attributes: {Jecs.Id}) -> (),

	updateEntityOrder: (Manager, entity: ExplorerEntity) -> (),
	getChildren: (ExplorerEntity) -> {ExplorerEntity},
}

export type ExplorerFrameLib = {
	fillGlobalPoolToLimit: (Manager) -> (),
	--fillLocalPoolToLimit: (Manager) -> (),
	initializeFrameCaches: (Manager) -> (),

	getExplorerFrame: (Manager) -> ExplorerFrame,
	assignExplorerFrame: (Manager, ExplorerFrame, assignee: ExplorerEntity?, parent: ExplorerEntity?, parentIsGame: boolean) -> (),
	flushExplorerFrameTagAssignQueue: (Manager) -> boolean,

	queueForExplorerFrameReuse: (Manager, ExplorerFrame) -> (),
	flushFrameReuseQueue: (Manager) -> boolean,
	stepFlushFrameSetParentQueue: (Manager) -> boolean,
	
	updateSelectionVisuals: (Manager, updateSelection: boolean) -> (),
	updateExpandedVisuals: (Manager) -> (),
	updateCollapsedVisuals: (Manager) -> (),
	
	setExplorerFrameIconColor: (Manager, frame: ExplorerFrame, iconColor: Color3?) -> (),
}

export type VirtualScroller = {
	clearHeightCache: (Manager) -> (),
	invalidateEntityHeightCache: (Manager, ExplorerEntity) -> (),

	update: (Manager, isScroller: boolean) -> (),
	rebuildAndUpdate: (Manager, isScroller: boolean) -> (),
	trackScrolling: (Manager) -> (RBXScriptConnection, thread),
	
	IsScrolling: boolean,
	IsVirtualScrollerUpdating: boolean
}

export type InsertMenu = {
	init: (Manager) -> (),
	show: (Manager, buttonAbsolutePos: Vector2, buttonAbsoluteSize: Vector2) -> (),
}

export type DeferredTaskScheduler = {
	HierarchyChildrenMapNeedsUpdate: boolean,
}

export type Manager = {
	CleanupFns: typeof(ItemGroup.cleanup),
	WidgetState: WidgetState,
	Components: Components,
	Toolbar: PluginToolbar,
	Storage: {
		repoRoots: Instance,
		idObjects: Instance,
		--pluginActions: Instance
	},

	InstTreeAbsoluteSizeY: number,
	
	QueryTagMap: {[string]: Jecs.Id},
	QueryCtMap: {[string]: Jecs.Id},
	QueryAttrMap: {[string]: Jecs.Id},
	AttributeUsageAmounts: {[string]: number},
	
	Script: Instance,

	ExplorerFrame: ExplorerFrameLib,
	HierarchyState: HierarchyState,
	VirtualScroller: VirtualScroller,
	InsertMenu: InsertMenu,
	DeferredTaskScheduler: DeferredTaskScheduler,

	PluginActions: {[string]: PluginAction},

	ItemLists: {
		InsertInstance: PluginUI.ItemList
	},
	Style: Style.Style,
	AllTab: Tab,

	InstanceToEntity: {[Instance]: ExplorerEntity},
	FrameToInstanceFrame: {[Instance]: ExplorerFrame},
	IconColorMap: {[InstanceId]: Color3},

	ChildAmountCache: {[ExplorerEntity]: number},
	ClassNameCache: {[ExplorerEntity]: string},
	NameCache: {[ExplorerEntity]: string},
	
	IdToInstance: {[InstanceId]: Instance},
	InstanceToId: {[Instance]: InstanceId},
	IdToObjectValue: {[InstanceId]: ObjectValue},
	
	TempIdToInstance: {[TempId]: Instance},
	InstanceToTempId: {[Instance]: TempId},
	
	TabFrameToTab: {[Instance]: Tab},
	
	createPluginAction: (actionId: string, text: string, statusTip: string, iconId: string) -> PluginAction,

	connectInputBegan: (fn: (input: InputObject) -> ()) -> RBXScriptConnection,
	connectInputEnded: (fn: (input: InputObject) -> ()) -> RBXScriptConnection,
	isKeyDown: (key: Enum.KeyCode) -> (boolean),
	isInputActive: (input: Enum.UserInputType) -> (boolean),

	registerTab: (name: string, icon: string, roots: {ExplorerEntity}, registerIntoTabsArray: boolean) -> Tab,

	getPropertyTag: (world: World, propName: string) -> Jecs.Id,

	triggerDuplicateTarget: () -> (),
	triggerDuplicateTargetWithIncrementName: () -> (),
	triggerDeleteTarget: () -> (),
	triggerEscapeTarget: () -> (),

	createContextMenu: (id: string, contents: {any}, title: string?, icon: string?) -> ContextMenu,
	registerRightClickContextMenu: (menu: ContextMenu, condition: (manager: Manager, target: ExplorerEntity) -> boolean, priority: number) -> (),

	getEntityAt: (x: number, y: number, filteredParent: Instance?) -> (Instance?, ExplorerEntity?, Tab?),

	onTagAdded: (inst: Instance, callback: (tag: string) -> ()) -> RBXScriptConnection,
	onTagRemoved: (inst: Instance, callback: (tag: string) -> ()) -> RBXScriptConnection,

	getOrCreateInstId: (instance: Instance) -> string,
	getInstId: (instance: Instance) -> string?,
	getInstFromId: (id: string) -> Instance?,
	
	getTempId: (instance: Instance) -> string,
	getInstFromTempId: (id: string) -> Instance,

	getSetting: (name: string) -> any,
	setSetting: (name: string, value: any) -> (),

	isExplorerEntityInvisible: (entity: ExplorerEntity) -> boolean,
	isExplorerEntityDeleted: (entity: ExplorerEntity) -> boolean,
	isExplorerEntityExpanded: (entity: ExplorerEntity) -> boolean,

	getPropertyComponentsForClass: (World, class: string) -> {Jecs.Id},
	
	isInstanceExcluded: (inst: Instance) -> boolean,

	getSetPropertyDragInfo: (instances: {Instance}, propName: string) -> any,
	getDragEntitiesDragInfo: (entities: {ExplorerEntity}) -> any,
	unpackDragInfo: (dragInfo: any) -> DragInfo_ReparentInstances | DragInfo_SetInstTypeProperty,

	addExplorerEntitiesToSelection: (entities: {ExplorerEntity}, updateSelection: boolean) -> (),
	setExplorerEntitiesAsSelection: (entities: {ExplorerEntity}, updateSelection: boolean) -> (),
	
	refreshQueryTags: (entity: ExplorerEntity, tagEnt: Jecs.Id?) -> (),
	refreshQueryAttributes: (entity: ExplorerEntity, attrEnt: Jecs.Id?) -> (),

	startDraggingSelected: () -> (),

	ChildOf: (ent: ExplorerEntity) -> Jecs.Pair<Jecs.Id, ExplorerEntity>,

	init: (connections: ItemGroup<RBXScriptConnection>, widget: DockWidgetPluginGui) -> (),

	frameOf: (frame: ExplorerFrame) -> typeof(main.__legacy.UI.InstanceFrame)?,
	parentOf: (entity: ExplorerEntity) -> ExplorerEntity?,
	instanceOf: (entity: ExplorerEntity) -> Instance?,
	updateParent: (entity: ExplorerEntity, newParent: ExplorerEntity?) -> (),
	
	saveState: () -> {
		save: () -> (),
		all: () -> (),
		icon_colors: () -> (),
		style: () -> (),
		versions: () -> (),
		tabs: () -> (),
		repo_proxies: () -> (),
		settings: () -> (),
		order: () -> (),
		invisible: () -> (),
	},
	loadState: (state: SavedState) -> ({
		icon_colors: () -> (),
		style: () -> Style.Style,
		versions: () -> {
			[Instance]: {
				{
					timestamp: DateTime,
					props: {[string]: any},
				}
			}
		},
		tabs: () -> (),
		repo_proxies: () -> (),
		settings: () -> (),
		order: () -> (),
		invisible: () -> (),
	}, SavedState)
}

type Editor = {
	Widget: DockWidgetPluginGui,

	init: (Manager) -> (),
}

export type StyleEditor = Editor & {

}

export type SettingEditor = Editor & {
	Configs: {[string]: any},

	getSetting: (Manager: Manager, name: string) -> any,
	setSetting: (Manager: Manager, name: string, value: any) -> (),
	createSetting: (list: PluginUI.ItemList, settingName: string, displayName: string, valueType: string, defaultValue: any, onChange: ((newValue: any) -> ())?) -> (),
}

export type OrderEditor = Editor & {
	ClassPriorities: {string},
	DefaultPriority: number,
	PriorityVersion: number
}

export type VersionControl = Editor & {
	InstanceHistoryWidget: DockWidgetPluginGui,
	InstanceHistoryUIList: PluginUI.ItemList,

	VersionViewerWidget: DockWidgetPluginGui,
	VersionViewerUIList: PluginUI.ItemList,

	SourceViewerWidget: DockWidgetPluginGui,
	SourceViewerMainframe: typeof(ui.EditorFrame),

	Token: GitAPI.LuaSecret?,
	RepoId: string,
	Versions: {
		[Instance]: {
			{
				timestamp: DateTime,
				props: {[string]: any},
			}
		}
	},
	PendingChanges: {
		[Instance]: {
			changedProps: {[string]: any},
			originalProps: {[string]: any}
		}
	},

	openSourceViewer: (src: string) -> (),
	showInstanceHistoryWidget: (inst: Instance) -> (),
	createInstanceVersion: (inst: Instance, changedProp: string, newValue: any) -> boolean,
	appendInstanceVersion: (inst: Instance, changedProp: string, newValue: any) -> boolean,

	addPendingChange: (inst: Instance, changedProp: string, newValue: any) -> (),
	appendPendingChanges: (inst: Instance) -> boolean,
	createPendingChanges: (inst: Instance) -> boolean,
	discardPendingChanges: (inst: Instance) -> boolean,

	createRepoProxy: (display_name: string, repo_id: string, root: Instance, register_into_proxies_array: boolean) -> RepoProxy
}

export type InstanceVisibilityEditor = Editor & {
	InvisibleClasses: {[string]: boolean},
	InvisibleInstances: {[Instance]: boolean},

	setInvisible: (className: string, invisible: boolean) -> boolean,
}

export type PropertyEditor = Editor & {
	PropertyList: PluginUI.ItemList,

	CurrentSetNilTarget: {instances: {Instance}, name: string}?,
	SetNilMenu: PluginMenu,

	updateProperties: (instances: {Instance}) -> (),
	clearFramePools: () -> ()
}

export type ContextMenuEditor = Editor & {

}

export type JextensionEditor = Editor & {

}

export type StateEditor = Editor & {

}

export type Jexplorer = {
	Manager: Manager,
	StyleEditor: StyleEditor,
	SettingEditor: SettingEditor,
	OrderEditor: OrderEditor,
	VersionControl: VersionControl,
	PropertyEditor: PropertyEditor,

	Dependencies: {[string]: any},

	OnLoad: RBXScriptSignal,
	OnClose: RBXScriptSignal,
	ModifyIconStep: RBXScriptSignal
}

return nil