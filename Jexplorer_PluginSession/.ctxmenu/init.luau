return {
	Menus = {
		Instance = {
			"OpenVersionHistory",
			"Append",
			"Commit",

			"---",
			
			"Copy",
			"PasteInto",
			"Delete",
			"Rename",

			"---",
			
			"GroupAsFolder",
			"GroupAsModel",
			
			"---",

			"SelectChildren",
			"CollapseAll",
			
			"---",
			
			"InsertSystem",
			"InsertFromFile",
			"InsertObject",

			"---",

			"SaveToFile",
			"SaveToRoblox",
		},
	},
	Actions = {
		InsertSystem = {
			Callback = function(manager, target)
				local state = manager.WidgetState
				local world = state.World

				local inst = world:get(target, manager.Components.Instance)
				if not inst then return end

				local module = Instance.new("ModuleScript")
				module.Source = "--!strict\n\nlocal ReplicatedStorage = game:GetService(\"ReplicatedStorage\")\n\nlocal shared = ReplicatedStorage.Shared\n\nlocal Jecs = require(shared.Jecs)\nlocal ct = require(shared.Components)\n\nlocal a_has = Jecs.assert_has\n\nlocal System = {}\n\nfunction System.init(world: Jecs.World, scheduler: RBXScriptSignal)\n\nend\n\nreturn System"
				module.Parent = inst
				
				local ent = manager.getOrCreateInstanceEntity(module)
				manager.setEntitiesAsSelection(world, {ent}, true)
				
				local parent = manager.InstanceToEntity[inst]
				if not world:has(parent, manager.Components.Expanded) then
					manager.toggleExpand(world, parent, true, true)
				end
			end,
			Text = "Insert System...",
			Tooltip = "Inserts an ECS system.",
			Icon = "rbxassetid://72574623675660"
		}
	}
}