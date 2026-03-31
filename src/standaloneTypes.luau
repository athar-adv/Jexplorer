--!strict

-- Jecs Definitions

type i53 = number
type i24 = number

type Ty = { Entity }
type ArchetypeId = number

type Column = { any }

type Map<K, V> = { [K]: V }

export type Archetype = {
	id: number,
	types: Ty,
	type: string,
	entities: { Entity },
	columns: { Column },
	columns_map: { [Component]: Column }
}

export type QueryInner = {
	compatible_archetypes: { Archetype },
	archetypes_map: { [number]: number },
	ids: { Component },
	filter_with: { Component },
	filter_without: { Component },
	next: () -> (Entity, ...any),
	-- world: World,
}

export type Entity<T = any> ={ __T: T }
export type Component<T = any> ={ __T: T }
export type Id<T = any> = { __T: T }
export type Pair<P, O> = Id<P>
type ecs_id_t<T = unknown> = Id<T> | Entity<T> | Pair<T, "Tag"> | Pair<"Tag", T>
type ecs_entity_t<T = unknown> = Id<T> | Entity<T> | Pair<T, "Tag"> | Pair<"Tag", T>
export type Item<T...> = (self: Query<T...>) -> (Entity, T...)
export type Iter<T...> = (query: Query<T...>) -> () -> (Entity, T...)

export type Cached_Query_Iter<T...> = (query: Cached_Query<T...>) -> () -> (Entity, T...)

type TypePack<T...> = (T...) -> never

export type Cached_Query<T...> = typeof(setmetatable(
	{} :: {
		iter: Cached_Query_Iter<T...>,
		archetypes: (Cached_Query<T...>, override: boolean?) -> { Archetype },
		has: (Cached_Query<T...>, Entity) -> boolean,
		fini: (Cached_Query<T...>) -> (),

		ids: { Id<any> },
		filter_with: { Id<any> }?,
		filter_without: { Id<any> }?,
		archetypes_map: { [number]: number },
		-- world: World
	},
	{} :: {
		__iter: Cached_Query_Iter<T...>,
	})
)

export type Query<T...> = typeof(setmetatable(
	{} :: {
		iter: Iter<T...>,
		with: ((Query<T...>, ...Component) -> Query<T...>),
		without: ((Query<T...>, ...Component) -> Query<T...>),
		archetypes: (Query<T...>) -> { Archetype },
		cached: (Query<T...>) -> Cached_Query<T...>,
		has: (Query<T...>, Entity) -> boolean,
		ids: { Id<any> },
		filter_with: { Id<any> }?,
		filter_without: { Id<any> }?,
		-- world: World
	},
	{} :: {
		__iter: Iter<T...>,
	}
	))

type QueryArm<T...> = () -> ()

export type Observer = {
	callback: (archetype: Archetype) -> (),
	query: QueryInner,
}

export type World = {
	archetype_edges: Map<number, Map<Entity, Archetype>>,
	archetype_index: { [string]: Archetype },
	ROOT_ARCHETYPE: Archetype,

	max_component_id: number,
	max_archetype_id: number,

	observable: Map<Component, Map<Component, { Observer }>>,

	added: <T>(World, Component<T>, (e: Entity, id: Id<T>, value: T, oldarchetype: Archetype) -> ()) -> () -> (),
	removed: <T>(World, Component<T>, (e: Entity, id: Id<T>, delete: boolean?) -> ()) -> () -> (),
	changed: <T>(World, Component<T>, (e: Entity, id: Id<T>, value: T, oldarchetype: Archetype) -> ()) -> () -> (),

	--- Enforce a check on entities to be created within desired range
	range: (self: World, range_begin: number, range_end: number?) -> (),

	--- Creates a new entity
	entity:
		& ((self: World) -> Entity<nil>)
	& ((self: World, id: Entity) -> Entity)
	& ((self: World, id: number) -> Entity)
	& (<T>(self: World, id: Component<T>) -> Component<T>),
	--- Creates a new entity located in the first 256 ids.
	--- These should be used for static components for fast access.
	component: <T>(self: World) -> Entity<T>,

	--- Gets the target of an relationship. For example, when a user calls
	--- `world:target(id, ChildOf(parent), 0)`, you will obtain the parent entity.
	target: <T, a>(
		self: World,
		id: Entity<T> | number,
		relation: Component,
		index: number?
	) -> Entity<unknown>?,

	--- Deletes an entity and all it's related components and relationships.
	delete: <T>(self: World, id: Entity<T>) -> (),

	--- Adds a component to the entity with no value
	add: <a>(
		self: World,
		id: Entity<any>,
		component: Component<a>
	) -> (),

	--- Assigns a value to a component on the given entity
	set: <T, a>(self: World, id: Entity<T>, component: Component<a>, data: a) -> (),

	cleanup: (self: World) -> (),

	-- Removes all components from the entity
	clear: (self: World, entity: Entity) -> (),
	--- Removes a component from the given entity
	remove: <T, a>(self: World, id: Entity<T>, component: Component<a>) -> (),
	--- Retrieves the value of up to 4 components. These values may be nil.
	get: & (<T, a>(World, Entity<T> | number, Component<a>) -> a?)
	& (<T, a, b>(World, Entity<T> | number, Component<a>, Component<b>) -> (a?, b?))
	& (<T, a, b, c>(World, Entity<T> | number, Component<a>, Component<b>, Component<c>) -> (a?, b?, c?))
	& (<T, a, b, c, d>(World, Entity<T> | number, Component<a>, Component<b>, Component<c>, Component<d>) -> (a?, b?, c?, d?)),

	--- Returns whether the entity has the ID.
	has: (<T, a>(World, Entity<T>, Component<a>) -> boolean)
	& (<T, a, b>(World, Entity<T>, Component<a>, Component<a>) -> boolean)
	& (<T, a, b, c>(World, Entity<T>, Component<a>, Component<b>, Component<c>) -> boolean)
	& <T, a, b, c, d>(World, Entity<T>, Component<a>, Component<b>, Component<c>, Component<d>) -> boolean,

	--- Get parent (target of ChildOf relationship) for entity. If there is no ChildOf relationship pair, it will return nil.
	parent: <T>(self: World, entity: Entity<T>) -> Entity?,

	--- Checks if the world contains the given entity
	contains: <T>(self: World, entity: Entity<T>) -> boolean,

	--- Checks if the entity exists
	exists: <T>(self: World, entity: Entity<T>) -> boolean,

	each: <T>(self: World, id: Id<T>) -> () -> Entity,

	children: <T>(self: World, id: Id<T>) -> () -> Entity,

	--- Searches the world for entities that match a given query
	query: ((World) -> Query<nil>)
	& (<A>(World, Component<A>) -> Query<A>)
	& (<A, B>(World, Component<A>, Component<B>) -> Query<A, B>)
	& (<A, B, C>(World, Component<A>, Component<B>, Component<C>) -> Query<A, B, C>)
	& (<A, B, C, D>(World, Component<A>, Component<B>, Component<C>, Component<D>) -> Query<A, B, C, D>)
	& (<A, B, C, D, E>(World, Component<A>, Component<B>, Component<C>, Component<D>, Component<E>) -> Query<A, B, C, D, E>)
	& (<A, B, C, D, E, F>(World, Component<A>, Component<B>, Component<C>, Component<D>, Component<E>, Component<F>) -> Query<A, B, C, D, E, F>)
	& (<A, B, C, D, E, F, G>(
		World,
		Component<A>,
		Component<B>,
		Component<C>,
		Component<D>,
		Component<E>,
		Component<F>,
		Component<G>
		) -> Query<A, B, C, D, E, F, G>)
	& (<A, B, C, D, E, F, G, H>(
		World,
		Component<A>,
		Component<B>,
		Component<C>,
		Component<D>,
		Component<E>,
		Component<F>,
		Component<G>,
		Component<H>,
		...Component<any>
		) -> Query<A, B, C, D, E, F, G, H>),
}


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

export type VisibleViewportInfo = {
	visibleArray: Array<{
		entity: ExplorerEntity,
		yoffset: number,
		indentoffset: number
	}>,
	entityToIndex: {[ExplorerEntity]: number},
	entityToVisibleIndex: {[ExplorerEntity]: number},
	explorerFrameHeight: number,
	expandedHeightIndex: {[ExplorerEntity]: number},
	flatCount: number,
	visibleExpandedAncestors: Array<{
		stickyY: number?,
		rulerHeight: number
	}>,
	stickyStackDepth: number,
	viewportTop: number,
	visibleSet: {[ExplorerEntity]: boolean}
}
export type ItemGroup<T=any> = any
type Signal<T... = ()> = any
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

------------------------------------ Context Menu
export type MenuDef = {
	Id: string,
	Priority: number,
	Condition: (manager: Manager, target: ExplorerEntity) -> boolean,
	Contents: ((utils: ContextMenuUtils) -> {any}) | {any},
}
export type ActionDef = {
	Id: string?,
	Callback: (manager: Manager, target: ExplorerEntity) -> (),
	Text: string,
	Desc: string?,
	Icon: (() -> string)?
}

export type ContextMenuConfigModuleReturnValue =
|	ContextMenuConfigs 
|	(Plugin, Manager, ContextMenuUtils, {any}) -> ContextMenuConfigs

export type ContextMenuConfigs = {
	Menus: {MenuDef},
	Actions: {[string]: ActionDef}
}

export type ContextMenuUtils = {
	createInterface: (defaultName: string) -> ContextMenuInterface,
	getMenuIds: () -> {string},
	createModifiedMenu: (menuId: string, newContents: (ContextMenuInterface) -> {any}) -> MenuDef,

	createSubMenu: (id: string, title: string, icon: any?, content: {any}) -> any,
	createSection: (sectionName: string) -> any,
}
export type ContextMenuInterface = {
	getMenuContents: () -> {any},
	getSubMenu: (name: string) -> ContextMenuInterface,

	remove: (idx: number) -> (),
	insert: (idx: number, v: any) -> (),
	inline: (idx: number, arr: {any}) -> (),

	findAction: (name: string) -> number,
	findSubMenu: (name: string) -> number,

	relocate: (name: string, newIndex: number) -> (),
	flipOrder: () -> (),

	getSection: (sectionName: string) -> (number, number),
	addSection: (idx: number, sectionName: string, content: {any}) -> (),
}
export type ContextMenu = {
	Menu: PluginMenu,
	SubMenus: {ContextMenu},
	Contents: {any},
	Id: string,
	Actions: {PluginAction},
	
	ShowAsync: (self: ContextMenu, targetOverride: any?) -> (),
	Instantiate: (self: ContextMenu) -> ()
}

------------------------------------ end Context Menu
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
	QueryDescendants: (selector: string) -> {Instance}
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
export type ExplorerFrame = Id
export type PropertyItem = {
	name: string,
	type: ReflectionType,
	writable: boolean,
	readable: boolean
}

export type ExplorerEntity = Id
export type QueryEntity = Id
export type FrameState = {
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
	overlayFrame: Frame,
	isSticky: boolean,
	
	linkIconPos: UDim2?,
	pendingChangesIconPos: UDim2?,
	reclassIconPos: UDim2?
}

export type Components = {
	Selected: Component,
	Expanded: Component,
	AncestryLocked: Component,
	ArrowInvisible: Component,
	QueryAncestor: Component,
	QueryExpanded: Component,
	QueryInvisible: Component,
	Invisible: Component,
	IsQueried: Component,
	PendingChanges: Component,
	Deleted: Component,
	DisplayTopLevel: Component,
	HasPackageLink: Component,
	HasSideIcons: Component,

	CleanupTicket: Component<{}>,
	DeletionTicket: Component<{}>,
	ChildAddedTicket: Component<{children: {Instance}}>,
	ChildMovedTicket: Component<{children: {Instance}}>,
	CreationTicket: Component<{children: {Instance}}>,
	PropAssignTicket: Component<{ty: "virtual" | "instance"}>,

	FrameReuseTicket: Component<{frame: ExplorerFrame}>,
	FrameTagAssignTicket: Component<{frame: ExplorerFrame}>,

	FRAMEWORLD_FrameSetParentTicket: Component<{newParent: Instance?}>,
	FRAMEWORLD_Main: Component<UITEMPLATE_InstanceFrame_Main>,
	FRAMEWORLD_CurrentParent: Component<Instance>,
	FRAMEWORLD_Ruler: Component<GuiObject>,
	FRAMEWORLD_IsSticky: Component,
	QUERYWORLD_ComponentHash: Component<string>,

	Instance: Component<Instance>,
	Frame: Component<ExplorerFrame>,
	Entity: Component<ExplorerEntity>,
	FrameState: Component<FrameState>,
	FrameIconColor: Component<Color3>,

	Connections: Component<ItemGroup<RBXScriptConnection>>,
	ScriptErrors: Component<{string}>,
	ScriptWarns: Component<{string}>,
	QueryLinkedEntities: Component<{ExplorerEntity}>,
	LinkedQueryEntity: Component<QueryEntity>,
	ParentTabs: Component<{[Tab]: boolean}>,
}

export type ContextMenuInfo = {
	Menu: ContextMenu,
	Condition: (manager: Manager, target: ExplorerEntity, instance: Instance) -> boolean,
	Priority: number
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
	InstanceContextMenus: {[string]: ContextMenuInfo},
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
		PropTags: {Id},
		Parent: ExplorerEntity?
	}, extra: {[string]: any}) -> ExplorerEntity,
	createInstanceEntity: (Manager, instance: Instance, parent: ExplorerEntity?, dontSetInInstanceToEntity: boolean?) -> ExplorerEntity,

	deregisterFromQueryWorld: (Manager, entity: ExplorerEntity) -> (),
	registerIntoQueryWorld: (Manager, entity: ExplorerEntity, className: string, tags: {Id}, attributes: {Id}) -> (),

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
	
	getVisibleViewportInfo: (Manager, top: number, isScroller: boolean) -> VisibleViewportInfo,
	getLastVisibleViewportInfo: (Manager) -> VisibleViewportInfo?,
	update: (Manager, isScroller: boolean, forceUpdateIcons: boolean?) -> VisibleViewportInfo?,
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
	classSelectList: any,
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

export type SharedTabState = {
	currentlyPickingTabRoots: Tab?,
	tabInsertListener: RBXScriptConnection?,
	currentlyOpenTab: Tab?,
	contextTargetTab: Tab?
}

export type ActionInfos = {[string]: {
	Id: string,
	Text: string,
	Desc: string?,
	Icon: (() -> string)?,
	Triggered: ((target: any) -> ())?
}}

export type Manager = {
	CleanupFns: {[string]: any},
	WidgetState: WidgetState,
	TabState: SharedTabState,
	Components: Components,
	Toolbar: PluginToolbar,
	Storage: {
		repoRoots: Instance,
		idObjects: Instance,
		publicTypedef: ModuleScript,
		self: Instance
	},
	
	CurrentTheme: string,
	
	TabChanged: Signal<Tab, Tab?>,
	SelectionChanged: Signal<{ExplorerEntity}>,

	InstTreeAbsoluteSizeY: number,
	InstTreeAbsoluteSizeX: number,

	QueryTagMap: {[string]: Id},
	QueryCtMap: {[string]: Id},
	QueryAttrMap: {[string]: Id},
	AttributeUsageAmounts: {[string]: number},

	Script: Instance,

	ExplorerFrame: ExplorerFrameLib,
	HierarchyState: HierarchyState,
	VirtualScroller: VirtualScroller,
	ClassSelectionMenu: ClassSelectionMenu,
	DeferredTaskScheduler: DeferredTaskScheduler,

	ActionInfos: ActionInfos,
	BindableActions: {[string]: PluginAction},
	
	ItemLists: {
		InsertInstance: any
	},
	Style: any,
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

	createPluginAction: (actionId: string, text: string, statusTip: string, iconId: string?) -> PluginAction,
	takeContextTarget: () -> ExplorerEntity,

	connectInputBegan: (fn: (input: InputObject) -> ()) -> RBXScriptConnection,
	connectInputEnded: (fn: (input: InputObject) -> ()) -> RBXScriptConnection,
	isKeyDown: (key: Enum.KeyCode) -> (boolean),
	isInputActive: (input: Enum.UserInputType) -> (boolean),

	registerTab: (name: string, icon: string, roots: {ExplorerEntity}, registerIntoTabsArray: boolean) -> Tab,

	getPropertyTag: (world: World, propName: string) -> Id,

	triggerDuplicateTarget: () -> (),
	triggerDuplicateTargetWithIncrementName: () -> (),
	triggerDeleteTarget: () -> (),
	triggerEscapeTarget: () -> (),

	createContextMenu: (id: string, contents: {any}, title: string?, icon: (() -> string)?) -> ContextMenu,
	registerRightClickContextMenu: (menuId: string, menu: ContextMenu, condition: (manager: Manager, target: ExplorerEntity) -> boolean, priority: number) -> (),

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

	getPropertyComponentsForClass: (World, class: string) -> {Id},

	isInstanceExcluded: (inst: Instance) -> boolean,

	getSetPropertyDragInfo: (instances: {Instance}, propName: string) -> any,
	getDragEntitiesDragInfo: (entities: {ExplorerEntity}) -> any,
	unpackDragInfo: (dragInfo: any) -> DragInfo_ReparentInstances | DragInfo_SetInstTypeProperty,

	addExplorerEntitiesToSelection: (entities: {ExplorerEntity}, updateSelection: boolean) -> (),
	setExplorerEntitiesAsSelection: (entities: {ExplorerEntity}, updateSelection: boolean) -> (),

	refreshQueryTags: (entity: ExplorerEntity, tagEnt: Id?) -> (),
	refreshQueryAttributes: (entity: ExplorerEntity, attrEnt: Id?) -> (),

	startDraggingSelected: () -> (),

	ChildOf: (ent: ExplorerEntity) -> Pair<Id, ExplorerEntity>,

	init: (connections: ItemGroup<RBXScriptConnection>, widget: DockWidgetPluginGui) -> (),

	frameOf: (frame: ExplorerFrame) -> UITEMPLATE_InstanceFrame?,
	parentOf: (entity: ExplorerEntity) -> ExplorerEntity?,
	instanceOf: (entity: ExplorerEntity) -> Instance?,
	updateParent: (entity: ExplorerEntity, newParent: ExplorerEntity?) -> (),

	convertEntitiesInto: (entities: {ExplorerEntity}, class: string) -> {ExplorerEntity},
	insertClassInto: (entity: ExplorerEntity, class: string) -> Instance?,
	
	jumpCanvasTo: (x: number?, y: number?, epsilon: number?) -> (),
	
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
		style: () -> any,
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
	createSetting: (list: any, settingName: string, displayName: string, valueType: string, defaultValue: any, onChange: ((newValue: any) -> ())?) -> (),
}

export type OrderEditor = Editor & {
	ClassPriorities: {string},
	DefaultPriority: number,
	PriorityVersion: number
}

export type VersionControl = Editor & {
	InstanceHistoryWidget: DockWidgetPluginGui,
	InstanceHistoryUIList: any,

	VersionViewerWidget: DockWidgetPluginGui,
	VersionViewerUIList: any,

	SourceViewerWidget: DockWidgetPluginGui,
	SourceViewerMainframe: UITEMPLATE_EditorFrame,

	Token: any?,
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
	PropertyList: any,

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