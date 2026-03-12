--!strict

local main = script.Parent

local shared = main.Shared

local PluginUI = require(shared.PluginUI)
local Style = require(shared.Style)
local GitAPI = require(shared.GitAPI)

local ItemGroup = require(shared.Vendor.ItemGroup)
local SimpleSignal = require(shared.Vendor.SimpleSignal)
local ColorPicker = require(shared.Vendor.PluginColorPicker)

local Jecs = require(main.Jecs)

-- UI definitions

export type UITEMPLATE_JExplorerUi = Frame & {
	InstanceTree: Frame & {
		TreeScroller: ScrollingFrame,
		ScrollContainer: Frame,

		ScrollBackgroundHorizontal: Frame,
		ScrollBackgroundVertical: Frame,
	},

	Topbar: Frame & {
		UIStroke: UIStroke,
		PathBar: Frame & {
			Segments: ScrollingFrame & {
				PathSegment: TextButton,
			}
		},
		TabBar: Frame & {
			Tabs: ScrollingFrame,
		},
		Options: ImageButton,
		QueryInputFrame: Frame & {
			Scroll: ScrollingFrame & {
				QueryInput: TextBox,
			},
			SelectQueried: TextButton,
			QueryCount: TextLabel,
		}
	}
}

type UITEMPLATE_InstanceFrame_Main = Frame & {
	Overlay: Frame & {
		Select: ImageButton,
	},
	ClassIcon: ImageLabel,
	InstanceName: TextBox,
	Arrow: ImageButton,
	Insert: ImageButton,

	PackageLinkIcon: ImageLabel,
	PendingChanges: ImageLabel,
	Reclass: ImageButton
}

export type UITEMPLATE_InstanceFrame = Frame & {
	Buffer: Frame,
	Ruler: Frame,
	Main: UITEMPLATE_InstanceFrame_Main,
}

export type UITEMPLATE_EditorFrame = Frame & {
	Items: ScrollingFrame & {
		Content: Frame & {
			UIListLayout: UIListLayout,
		},
		Overlay: Frame,
	},
	ScrollBackgroundHorizontal: Frame,
	ScrollBackgroundVertical: Frame,
}

export type UITEMPLATE_TabFrame = Frame & {
	NameBox: TextButton,
	Button: TextButton,
	Icon: ImageLabel,
}

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
	rules: {SerializedStyleRule},
	tokens: {[string]: SerializedStyleToken},
	tags: {string},
	attributes: {[string]: UDFValue}
}
export type SerializedStyleToken = {
	value: UDFValue,
	tags: {string}
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
			inst_ids: {InstanceId},
			layout_order: number
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
		tokens: {[string]: SerializedStyleToken}
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
	ruler: GuiObject,
	isLMBActive: boolean,
	tagsToRemove: {string},
	hasBeenSelected: boolean,
	shouldDeselect: boolean,
	lastClickTime: number,
	lastPackageIconPos: number,
	isAssigning: boolean,
	setIconColor: Color3?,
	icon: ImageLabel,
	packageLinkIcon: ImageLabel,
	isVisible: boolean,
	instanceName: TextBox,
	pendingChanges: ImageLabel,
	arrow: GuiButton,
	hasPackageLink: boolean,
	insertInstanceButton: GuiButton,
	reclassButton: GuiButton,
	currentFrameName: string?,
	packageLinkIconVisible: boolean,
	pendingChangesIconVisible: boolean,
	reclassIconVisible: boolean,
	currentNameBoundX: number,
	currentFrameX: number,
	lastFrameX: number,
	
	linkIconPos: UDim2?,
	pendingChangesIconPos: UDim2?,
	reclassIconPos: UDim2?
}

export type Components = {
	Selected: Jecs.Component,
	Expanded: Jecs.Component,
	AncestryLocked: Jecs.Component,
	ArrowInvisible: Jecs.Component,
	QueryAncestor: Jecs.Component,
	QueryExpanded: Jecs.Component,
	QueryInvisible: Jecs.Component,
	Invisible: Jecs.Component,
	IsQueried: Jecs.Component,
	PendingChanges: Jecs.Component,
	Deleted: Jecs.Component,
	DisplayTopLevel: Jecs.Component,
	HasPackageLink: Jecs.Component,
	HasSideIcons: Jecs.Component,

	CleanupTicket: Jecs.Component<{}>,
	DeletionTicket: Jecs.Component<{}>,
	ChildAddedTicket: Jecs.Component<{children: {Instance}}>,
	ChildMovedTicket: Jecs.Component<{children: {Instance}}>,
	CreationTicket: Jecs.Component<{children: {Instance}}>,
	PropAssignTicket: Jecs.Component<{ty: "virtual" | "instance"}>,

	FrameReuseTicket: Jecs.Component<{frame: ExplorerFrame}>,
	FrameTagAssignTicket: Jecs.Component<{frame: ExplorerFrame}>,

	FRAMEWORLD_FrameSetParentTicket: Jecs.Component<{newParent: Instance?}>,
	FRAMEWORLD_Main: Jecs.Component<UITEMPLATE_InstanceFrame_Main>,
	FRAMEWORLD_CurrentParent: Jecs.Component<Instance>,
	QUERYWORLD_ComponentHash: Jecs.Component<string>,

	Instance: Jecs.Component<Instance>,
	Frame: Jecs.Component<ExplorerFrame>,
	Entity: Jecs.Component<ExplorerEntity>,
	FrameState: Jecs.Component<FrameState>,
	FrameIconColor: Jecs.Component<Color3>,

	Connections: Jecs.Component<ItemGroup<RBXScriptConnection>>,
	ScriptErrors: Jecs.Component<{string}>,
	ScriptWarns: Jecs.Component<{string}>,
	QueryLinkedEntities: Jecs.Component<{ExplorerEntity}>,
	LinkedQueryEntity: Jecs.Component<QueryEntity>,
	ParentTabs: Jecs.Component<{[Tab]: boolean}>,
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

	JExplorerUI: UITEMPLATE_JExplorerUi,
	DefaultInstanceActionsArray: {any},
	InstanceContextMenus: {[string]: {Menu: ContextMenu, Condition: (manager: Manager, target: ExplorerEntity, instance: Instance) -> boolean, Priority: number}},
	MiscContextMenus: {[string]: ContextMenu},
	OverridePathBarText: string?,
	Enabled: boolean
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
	assignExplorerFrame: (Manager, ExplorerFrame, assignee: ExplorerEntity?, parent: ExplorerEntity?, parentIsGame: boolean, assignSetParentTicket: boolean) -> boolean?,
	flushExplorerFrameTagAssignQueue: (Manager) -> boolean,

	queueForExplorerFrameReuse: (Manager, ExplorerFrame, ExplorerEntity?) -> (),
	flushFrameReuseQueue: (Manager) -> boolean,
	flushFrameSetParentQueue: (Manager) -> boolean,

	updateSelectionVisuals: (Manager, updateSelection: boolean) -> (),
	updateExpandedVisuals: (Manager) -> (),
	updateCollapsedVisuals: (Manager) -> (),

	updateRightEdgeIcons: (Manager, frame: ExplorerFrame, containerWidth: number?, frameX: number?, entity: ExplorerEntity?, frameState: FrameState?) -> (),
	setExplorerFrameIconColor: (Manager, frame: ExplorerFrame, iconColor: Color3?) -> (),
}

export type VirtualScroller = {
	clearHeightCache: (Manager) -> (),
	invalidateEntityHeightCache: (Manager, ExplorerEntity) -> (),

	update: (Manager, isScroller: boolean, forceUpdateIcons: boolean?) -> (),
	rebuildAndUpdate: (Manager, isScroller: boolean) -> (),
	trackScrolling: (Manager) -> (RBXScriptConnection, thread),

	IsScrolling: boolean,
	IsVirtualScrollerUpdating: boolean
}

export type buttonItem = {
	button: Frame,
	className: string,
	category: string
}
export type ClassSelectionMenuInfo = {
	currentOnSelectCallback: ((class: string) -> ())?,
	currentInsertTarget: number,
	classSelectList: PluginUI.ItemList,
	currentVisibleButtons: {buttonItem},
	searchbar: TextBox,
	highlightFrame: Frame,
	setScope: (scope: string) -> (),
	setScopeInfo: (scope: string, frequentClasses: {string}) -> ()
}
export type ClassSelectionMenu = {
	init: (Manager) -> (),
	show: (Manager, buttonAbsolutePos: Vector2, buttonAbsoluteSize: Vector2, onSelectClass: (class: string) -> ()) -> (),
	menuInfo: ClassSelectionMenuInfo
}

export type DeferredTaskScheduler = {
	ChildGraphDirty: boolean,

	FrameReuseQueuePending: boolean,
	FrameTagAssignQueuePending: boolean,
	EntityCleanupQueuePending: boolean,
	EntityCreationQueuePending: boolean,
	EntityChildAddedQueuePending: boolean,
	EntityChildRemovedQueuePending: boolean,
	EntityPropAssignQueuePending: boolean,
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
	InstTreeAbsoluteSizeX: number,

	QueryTagMap: {[string]: Jecs.Id},
	QueryCtMap: {[string]: Jecs.Id},
	QueryAttrMap: {[string]: Jecs.Id},
	AttributeUsageAmounts: {[string]: number},

	Script: Instance,

	ExplorerFrame: ExplorerFrameLib,
	HierarchyState: HierarchyState,
	VirtualScroller: VirtualScroller,
	ClassSelectionMenu: ClassSelectionMenu,
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
	takeContextTarget: () -> ExplorerEntity,

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

	frameOf: (frame: ExplorerFrame) -> UITEMPLATE_InstanceFrame?,
	parentOf: (entity: ExplorerEntity) -> ExplorerEntity?,
	instanceOf: (entity: ExplorerEntity) -> Instance?,
	updateParent: (entity: ExplorerEntity, newParent: ExplorerEntity?) -> (),

	convertEntitiesInto: (entities: {ExplorerEntity}, class: string) -> {ExplorerEntity},
	insertClassInto: (entity: ExplorerEntity, class: string) -> Instance?,

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
	SourceViewerMainframe: UITEMPLATE_EditorFrame,

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

export type ExplorerFrameEditor = Editor & {

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