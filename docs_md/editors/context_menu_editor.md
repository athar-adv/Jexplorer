# The Context Menu Editor

The context menu editor is the editor you use to customize/add context menus inside Jexplorer.

The way this works is by using a custom ModuleScript that returns `ContextMenuConfigs`, whose structure is this:

```luau
type ModuleReturn = ((Plugin, Manager) -> ContextMenuConfigs) | ContextMenuConfigs

type ContextMenuConfigs = {
	Menus: {
		{
			Id: string,
			Priority: number,
			Condition: (manager: Types.Manager, target: Types.ExplorerEntity) -> boolean,
			Contents: {any} | (createInterface: () -> ContextMenuInterface) -> {any},
            DefaultActionsName: string?,
		}
	},
	Actions: {
		[string]: {
			Callback: (manager: Types.Manager, target: Types.ExplorerEntity) -> (),
			Text: string,
			Tooltip: string,
			Icon: string?
		}
	}
}

type ContextMenuInterface = {
	GetMenuContents: () -> {any},
	GetSubMenu: (name: string) -> ContextMenuInterface,
	
	Remove: (idx: number) -> (),
	Insert: (idx: number, v: any) -> (),
	
	FindAction: (name: string) -> number,
	FindSubMenu: (name: string) -> number
}
```

A few things need to be clarified:

The contents of the array `ContextMenuConfigs::Menus::value_type::Contents` are as follows:

- Any string for the name of a registered PluginAction, created within `ContextMenuConfigs::Actions`
- The string "---", specifying a seperator
- The mixed table `{Id: string, Title: string, Icon: string?, [1]: typeof(ContextMenuConfigs::Menus::value_type::Contents)}` specifies a submenu

Heres an example value for Contents:

```luau
{
    "MyAction1",
    "MyAction2",

    "---"
    {
        Id = "Menu.More",
        Title = "More",
        {
            "Cool1",
            "Cool2",

            "---",

            "Cool3"
        }
    },

    "---",
    "LastAction"
}
```

Now, you may be wondering how to edit default context menus without completely overwriting them, and that's by specifying `ContextMenuConfigs::Menus::value_type::Contents` as a function that accepts a `createInterface` function that can be called to get a `ContextMenuInterface`.

This `ContextMenuInterface` will contain the default context menu you specified in the `DefaultActionsName` field.

Everything else should be clear enough for you to understand.
If it isn't, heres an example of an extensive ContextMenuConfigs module i made for my game:

```luau
local function apply_surface_type(manager, type)
	local state = manager.WidgetState
	local components = manager.Components
	local world = state.World

	for _, ent in state.CurrentSelection do
		local inst = world:get(ent, components.Instance)
		if not inst then continue end
		if not inst:IsA("BasePart") then continue end

		for _, v in Enum.NormalId:GetEnumItems() do
			local prop = `{v.Name}Surface`
			inst[prop] = type
		end
	end
end

local function insert_contents(createInterface, actionName)
	local interface = createInterface()

	if actionName then
		interface.Insert(
			interface.FindAction("InsertFromFile"),
			actionName
		)
	end
	return interface.GetMenuContents()
end

local function insert_system(manager, target, src)
	local state = manager.WidgetState
	local world = state.World

	local inst = world:get(target, manager.Components.Instance)
	if not inst then return end

	local module = Instance.new("ModuleScript")
	module.Name = "(System) "
	module.Source = src
	module.Parent = inst

	local ent = manager.getOrCreateInstanceEntity(module, target)
	manager.setEntitiesAsSelection(world, {ent}, true)
	
	if not world:has(target, manager.Components.Expanded) then
		--manager.toggleExpand(world, parent, true, true)
		world:add(target, manager.Components.Expanded)
		manager.updateExpandedVisuals(false)
	end
	
	state.HierarchyVersion += 1
	manager.updateVirtualScroller()

	game:GetService("ScriptEditorService"):OpenScriptDocumentAsync(module)
end

return {
	Menus = {
		{
			Id = "InstanceMenu_Client",
			Priority = 0.5, -- Above instance but not above service
			Condition = function(_, _, inst)
				return (inst.Parent == game.ReplicatedStorage.Client and inst.Name == "Systems") or inst:IsDescendantOf(game.ReplicatedStorage.Client.Systems)
			end,
			Contents = function(createInterface)
				return insert_contents(createInterface, "InsertSystem_Client")
			end,
		},
		{
			Id = "InstanceMenu_Shared",
			Priority = 0.5,
			Condition = function(_, _, inst)
				return (inst.Parent == game.ReplicatedStorage.Shared and inst.Name == "Systems") or inst:IsDescendantOf(game.ReplicatedStorage.Shared.Systems)
			end,
			Contents = function(createInterface)
				return insert_contents(createInterface, "InsertSystem_Shared")
			end,
		},
		{
			Id = "InstanceMenu_Server",
			Priority = 0.5,
			Condition = function(_, _, inst)
				return (inst.Parent == game.ServerStorage.Server and inst.Name == "Systems") or inst:IsDescendantOf(game.ServerStorage.Server.Systems)
			end,
			Contents = function(createInterface)
				return insert_contents(createInterface, "InsertSystem_Server")
			end,
		},
		{
			Id = "BasePartMenu",
			Priority = 2, -- Above service and default
			Condition = function(_, _, inst)
				return inst:IsA("BasePart")
			end,
			Contents = function(createInterface)
				local interface = createInterface()
				interface.Insert(
					interface.FindSubMenu("Menu.ConvertInto") + 1,
					{
						Id = "SurfaceTypes",
						Title = "Surface Types",
						{
							"Studs",
							"Inlets",
							"StudsAndInlets"
						}
					}
				)
				return interface.GetMenuContents()
			end,
		}
	},
	Actions = {
		Studs = {
			Text = "Studs",
			Tooltip = "Turns all selected parts into stud surfaces.",
			Callback = function(manager)
				apply_surface_type(manager, Enum.SurfaceType.Studs)
			end,
		},
		Inlets = {
			Text = "Inlets",
			Tooltip = "Turns all selected parts into inlet surfaces.",
			Callback = function(manager)
				apply_surface_type(manager, Enum.SurfaceType.Inlet)
			end,
		},
		StudsAndInlets = {
			Text = "Studs and Inlets",
			Tooltip = "Turns all selected parts into universal surfaces.",
			Callback = function(manager)
				apply_surface_type(manager, Enum.SurfaceType.Universal)
			end,
		},
		InsertSystem_Client = {
			Text = "Insert System...",
			Tooltip = "Inserts an ECS system.",
			Icon = "rbxassetid://72574623675660",
			Callback = function(manager, target)
				insert_system(manager, target, "--!strict\n\nlocal ReplicatedStorage = game:GetService(\"ReplicatedStorage\")\n\nlocal shared = ReplicatedStorage.Shared\nlocal client = ReplicatedStorage.Client\n\nlocal jecs = require(shared.Jecs)\nlocal components = require(shared.Components)\nlocal types = require(shared.Types)\nlocal shared_constants = require(shared.Constants)\nlocal client_constants = require(client.Constants)\n\nreturn function(world: jecs.World, scheduler: types.Scheduler)\n\nend")
			end,
		},
		InsertSystem_Server = {
			Text = "Insert System...",
			Tooltip = "Inserts an ECS system.",
			Icon = "rbxassetid://72574623675660",
			Callback = function(manager, target)
				insert_system(manager, target, "--!strict\n\nlocal ReplicatedStorage = game:GetService(\"ReplicatedStorage\")\nlocal ServerStorage = game:GetService(\"ServerStorage\")\n\nlocal shared = ReplicatedStorage.Shared\nlocal server = ServerStorage.Server\n\nlocal jecs = require(shared.Jecs)\nlocal components = require(shared.Components)\nlocal types = require(shared.Types)\nlocal shared_constants = require(shared.Constants)\nlocal server_constants = require(server.Constants)\n\nreturn function(world: jecs.World, scheduler: types.Scheduler)\n\nend")
			end,
		},
		InsertSystem_Shared = {
			Text = "Insert System...",
			Tooltip = "Inserts an ECS system.",
			Icon = "rbxassetid://72574623675660",
			Callback = function(manager, target)
				insert_system(manager, target, "--!strict\n\nlocal ReplicatedStorage = game:GetService(\"ReplicatedStorage\")\n\nlocal shared = ReplicatedStorage.Shared\n\nlocal jecs = require(shared.Jecs)\nlocal components = require(shared.Components)\nlocal types = require(shared.Types)\nlocal shared_constants = require(shared.Constants)\n\nreturn function(world: jecs.World, scheduler: types.Scheduler)\n\nend")
			end,
		}
	}
}
```

## The Context Menu Editor Widget

Now that you have a config file specifying your custom context menus, you need to specify how Jexplorer should access it.

Open the context menu editor widget in the jexplorer dropdown menu and you'll see 2 fields, "Module Name" and "Source Changed Refresh Delay".

"Module Name" is what the name of your ModuleScript returning the `ContextMenuConfigs` is. SO if your module is named "ContextMenu", you should set "Module Name" to "ContextMenu".

This value supports non-alphanumeric characters so you can also do stuff like ".contextmenu"

"Source Changed Refresh Delay" is how often the internal context menus should be refreshed anytime you change the source of your module that contains the `ContextMenuConfigs`, since it's updated automatically.