--!strict

local main = script.Parent

local utilities = main.Utilities
local ui = main.__legacy.UI

local PluginUI = require(utilities.PluginUI)
local Style = require(utilities.Style)
local GitAPI = require(utilities.GitAPI)

local Group = require(utilities.Vendor.Group)
local SimpleSignal = require(utilities.Vendor.SimpleSignal)
local ColorPicker = require(utilities.Vendor.PluginColorPicker)

local Jecs = require(main.Jecs)

type Array<T> = {T}
type InstanceId = string
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
	versions: {
		[PlaceId]: {
			[string]: {
				{
					timestamp: typeof(DateTime.now():ToUniversalTime()),
					props: {[string]: UDFValue},
				}
			}
		}
	},
}

type Signal<T... = ()> = SimpleSignal.SimpleSignal<T...>
export type WidgetState = {
	World: World,
	QueryWorld: World,
	
	Connections: Group.Group,
	Entities: {InstanceEntity},
	Widget: DockWidgetPluginGui,
	CurrentSelection: {InstanceEntity},
	Favorited: {InstanceEntity},
	Tabs: {Tab},
	RepoProxies: {RepoProxy},
	HierarchyVersion: number,
	SavedState: SavedState,
	
	LastSelectedEntity: InstanceEntity?,
	ContextTarget: InstanceEntity?,
	
	CurrentlyRenaming: InstanceEntity?,
	CurrentlyInserting: {Instance}?,
	CurrentDrag: {
		Connections: Group.Group,
		Frame: typeof(ui.DragFrame),
		Entities: {InstanceEntity}
	}?,
	
	JExplorerUI: typeof(ui.JExplorerUi),
	DefaultInstanceActionsArray: {any},
	InstanceContextMenus: {[string]: {Menu: ContextMenu, Condition: (manager: Manager, target: InstanceEntity, instance: Instance) -> boolean, Priority: number}},
	MiscContextMenus: {[string]: ContextMenu}
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
	Id: string
}
export type Tab = {
	TabFrame: GuiObject,
	Button: GuiButton,
	InsertButton: GuiButton,
	RemoveButton: GuiButton?,
	NameBox: TextBox,
	
	Roots: {InstanceEntity},
	Name: string,
	
	Toggle: () -> (),
	Remove: () -> (),
}
export type RepoProxy = {
	DisplayName: string,
	RepoId: string,
	Root: Instance,
	
	Remove: () -> ()
}
export type InstanceFrame = {
	Instance: typeof(ui.InstanceFrame),
	Connections: Group.Group,
	CurrentEntity: InstanceEntity?,
	TagsToRemove: {string},
	
	Assign: (InstanceFrame, entity: InstanceEntity?, parent: InstanceEntity?) -> (),
	ToggleSelection: (InstanceFrame, selected: boolean) -> (),
	Reuse: (InstanceFrame) -> ()
}
export type PropertyItem = {
	name: string,
	type: string,
	writable: boolean,
	readable: boolean
}

export type World = Jecs.World
export type InstanceEntity = Jecs.Id
export type QueryEntity = Jecs.Id

type Components = {
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
	
	Instance: Jecs.Id<Instance>,
	Frame: Jecs.Id<InstanceFrame>,
	Connections: Jecs.Id<Group.Group>,
	FavoriteProxy: Jecs.Id<InstanceEntity>,
	FavoriteProxySource: Jecs.Id<InstanceEntity>,
	ScriptErrors: Jecs.Id<{string}>,
	ScriptWarns: Jecs.Id<{string}>,
	QueryLinkedEntities: Jecs.Id<{InstanceEntity}>,
	LinkedQueryEntity: Jecs.Id<QueryEntity>,
	ParentTabs: Jecs.Id<{[Tab]: boolean}>,
}

export type Manager = {
	Jecs: typeof(Jecs),
	WidgetState: WidgetState,
	Components: Components,
	Toolbar: PluginToolbar,
	Storage: Folder,
	
	PluginActions: {[string]: PluginAction},
	
	ItemLists: {
		InsertInstance: PluginUI.ItemList
	},
	AbstractEntClasses: {
		Favorited: "JEXP_ABSTRACT_Favorited"
	},
	Style: Style.Style,
	InstanceToEntity: {[Instance]: InstanceEntity},
	FrameToInstanceFrame: {[Instance]: InstanceFrame},
	
	SelectionChanged: Signal<{InstanceEntity}>,
	
	connectInputBegan: (fn: (input: InputObject) -> ()) -> (),
	connectInputEnded: (fn: (input: InputObject) -> ()) -> (),
	isKeyDown: (key: Enum.KeyCode) -> (boolean),
	isInputActive: (input: Enum.UserInputType) -> (boolean),
	getInstanceFrame: () -> InstanceFrame,
	getOrCreateInstanceEntity: (instance: Instance, parent: InstanceEntity?, dontSetInInstanceToEntity: boolean?) -> InstanceEntity?,
	registerTab: (name: string, roots: {InstanceEntity}, createDeleteButton: boolean, registerIntoTabsArray: boolean) -> Tab,
	
	getPropertyTag: (world: World, propName: string) -> Jecs.Id,
	
	createVirtualEntity: (options: {ClassName: string, Name: string, ChildAmount: number, ClassIcon: StudioIconResult, PropTags: {Jecs.Id}, Parent: InstanceEntity?}, extra: {[string]: any}) -> InstanceEntity,
	createInstanceEntity: (instance: Instance, parent: InstanceEntity?, dontSetInInstanceToEntity: boolean?) -> InstanceEntity?,
	
	createContextMenu: (id: string, contents: {any}, title: string?, icon: string?) -> ContextMenu,
	registerRightClickContextMenu: (menu: ContextMenu, condition: (manager: Manager, target: InstanceEntity) -> boolean, priority: number) -> (),
	
	getEntityAt: (x: number, y: number, filteredParent: Instance?) -> (Instance?, InstanceEntity?, Tab?),
	
	onTagAdded: (inst: Instance, callback: (tag: string) -> ()) -> RBXScriptConnection,
	onTagRemoved: (inst: Instance, callback: (tag: string) -> ()) -> RBXScriptConnection,
	
	getInstId: (instance: Instance) -> string,
	getInstFromId: (id: string) -> Instance?,
	
	getSetting: (name: string) -> any,
	setSetting: (name: string, value: any) -> (),
	
	getDragInfo: (inst: Instance, propName: string) -> any,
	unpackDragInfo: (dragInfo: any) -> (Instance, string),
	
	setInstanceFramePoolTarget: (n: number) -> (),
	fillInstanceFramePoolToLimit: () -> (),
	addEntitiesToSelection: (world: World, entities: {InstanceEntity}, updateSelection: boolean) -> (),
	setEntitiesAsSelection: (world: World, entities: {InstanceEntity}, updateSelection: boolean) -> (),
	updateVirtualScroller: () -> (),
	updateSelectionVisuals: (updateSelection: boolean) -> (),
	updateExpandedVisuals: (update: boolean, expandedCt: Jecs.Id?) -> (),
	updateCollapsedVisuals: (update: boolean, expandedCt: Jecs.Id?) -> (),
	
	ChildOf: (ent: InstanceEntity) -> Jecs.Pair<Jecs.Id, InstanceEntity>,	
	init: (onClose: () -> (), pluginVersion: string, connections: Group.Group) -> (),
	
	saveState: () -> SavedState,
	loadState: (state: SavedState) -> ({
		style: () -> Style.Style,
		versions: () -> {
			[string]: {
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
		[string]: {
			{
				timestamp: DateTime,
				props: {[string]: any},
			}
		}
	},
	PendingChanges: {
		[string]: {
			[string]: any
		}
	},
	
	openSourceViewer: (src: string) -> (),
	showInstanceHistoryWidget: (inst: Instance) -> (),
	createInstanceVersion: (inst: Instance, changedProp: string, newValue: any) -> boolean,
	appendInstanceVersion: (inst: Instance, changedProp: string, newValue: any) -> boolean,
	
	addPendingChange: (inst: Instance, changedProp: string, newValue: any) -> (),
	appendPendingChanges: (inst: Instance) -> boolean,
	createPendingChanges: (inst: Instance) -> boolean,
	
	createRepoProxy: (display_name: string, repo_id: string, root: Instance, register_into_proxies_array: boolean) -> ()
}

export type InstanceVisibilityEditor = Editor & {
	InvisibleClasses: {[string]: boolean},
	InvisibleInstances: {[Instance]: boolean},
	
	setVisible: (className: string, visible: boolean) -> (),
}

export type PropertyEditor = Editor & {
	PropertyList: PluginUI.ItemList,
	
	CurrentSetNilTarget: {{inst: Instance, name: string}}?,
	SetNilMenu: PluginMenu,
	
	updateProperties: (instances: {Instance}) -> ()
}

export type ContextMenuEditor = Editor & {
	
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