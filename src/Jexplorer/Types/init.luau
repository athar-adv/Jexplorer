--!strict

local main = script.Parent

local utilities = main.Utilities
local ui = main.UI

local PluginUI = require(utilities.PluginUI)
local Style = require(utilities.Style)
local Group = require(utilities.Group)
local SimpleSignal = require(utilities.SimpleSignal)
local GitAPI = require(utilities.GitAPI)
local APIMap = require(utilities.APIMap)
local ColorPicker = require(utilities.PluginColorPicker)
local Jecs = require(main.Jecs)

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
	HierarchyVersion: number,

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
	WidgetState: WidgetState,
	Components: Components,
	Toolbar: PluginToolbar,
	
	ContextMenus: {[string]: ContextMenu},
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
	
	APIMap: typeof(APIMap()),
	
	SelectionChanged: Signal<{InstanceEntity}>,
	
	connectInputBegan: (fn: (input: InputObject) -> ()) -> (),
	connectInputEnded: (fn: (input: InputObject) -> ()) -> (),
	isKeyDown: (key: Enum.KeyCode) -> (boolean),
	isInputActive: (input: Enum.UserInputType) -> (boolean),
	getInstanceFrame: () -> InstanceFrame,
	getOrCreateInstanceEntity: (instance: Instance, parent: InstanceEntity?, dontSetInInstanceToEntity: boolean?) -> InstanceEntity?,
	registerTab: (name: string, roots: {InstanceEntity}, createDeleteButton: boolean, registerIntoTabsArray: boolean) -> Tab,
	toggleExpand: (world: World, entity: InstanceEntity, expanded: boolean, update: boolean) -> (),
	
	getPropertyTag: (world: World, propName: string) -> Jecs.Id,
	
	createVirtualEntity: (options: {ClassName: string, Name: string, ChildAmount: number, ClassIcon: StudioIconResult, PropTags: {Jecs.Id}, Parent: InstanceEntity?}, extra: {[string]: any}) -> InstanceEntity,
	createInstanceEntity: (instance: Instance, parent: InstanceEntity?, dontSetInInstanceToEntity: boolean?) -> InstanceEntity?,
	
	createContextMenu: (id: string, actions: {string}, title: string?, icon: string?) -> ContextMenu,
	replaceContextMenu: (name: string, newActions: {string}) -> (),
	
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
	
	init: (onClose: () -> (), pluginVersion: string, connections: Group.Group) -> ()
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

return nil