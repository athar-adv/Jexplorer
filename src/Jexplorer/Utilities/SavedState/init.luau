--!strict
local plugin = script:FindFirstAncestorOfClass("Plugin")

local Style = require("./Style")
local Types = require("../Types")

local DefaultOrder = require("./Defaults/DefaultOrder")
local DefaultInvisibleClasses = require("./Defaults/DefaultInvisibleClasses")
local DefaultSettings = require("./Defaults/DefaultSettings")
local DefaultStyle = require("./Defaults/DefaultStyle")

local UDF = require("./UDF")
local Migrations = require("@self/Migrations")

export type SavedState = Types.SavedState

local SavedState = {
	data_version = 10
}

function SavedState._migrate(state: any, manager: Types.Manager): SavedState
	local current_version = state.data_version or 1
	if current_version == SavedState.data_version then
		return state
	end
	
	if current_version > SavedState.data_version then
		warn(string.format(
			"SavedState version %d is newer than supported version %d. Using defaults.",
			current_version,
			SavedState.data_version
			))
		return SavedState.get_default(manager)
	end
	
	print(string.format("Migrating SavedState from v%d to v%d", current_version, SavedState.data_version))

	for version = current_version, SavedState.data_version - 1 do
		local migration_fn = Migrations[string.format("v%d_to_v%d", version, version + 1)]
		if migration_fn then
			local success, result = pcall(migration_fn, SavedState, state, manager)
			if success then
				state = result or state
				print(string.format("  ✓ Migrated to v%d", version + 1))
			else
				warn(string.format("Migration v%d_to_v%d failed: %s", version, version + 1, tostring(result)))
				warn("Falling back to defaults")
				return SavedState.get_default(manager)
			end
		else
			warn(string.format("Missing migration function: v%d_to_v%d", version, version + 1))
		end
	end

	print(string.format("Migration complete: now at v%d", state.data_version))
	return state
end

function SavedState._serialize_rules(source: {Style.Rule}, destination: any)
	for _, rule in source do
		local subrules = {}
		if #rule.ChildRules > 0 then
			SavedState._serialize_rules(rule.ChildRules, subrules)
		end
		table.insert(destination, {
			display_name = rule:GetName(),
			selector = rule.Rule.Selector,
			priority = rule.Rule.Priority,
			props = (function()
				local props = {}
				for k, v in rule.RawProperties do
					props[k] = UDF.to(v)
				end
				return props
			end)(),
			rules = subrules
		})
	end
end

function SavedState.get_default(manager: Types.Manager): SavedState
	local rules, tokens = {}, {}
	local configs = {}
	local invis = {}

	local dtokens, drules = DefaultStyle(manager)
	for k, v in dtokens do
		tokens[k] = UDF.to(v)
	end

	SavedState._serialize_rules(drules, rules)
	for _, t in DefaultSettings do
		for k, v in t do
			configs[k] = UDF.to(v.Default)
		end
	end
	for _, v in DefaultInvisibleClasses do
		invis[v] = true
	end

	return {
		repo_proxies = {},
		tabs = {},
		display_order = {
			default_order = 999,
			class_order = DefaultOrder(manager)
		},
		invisible = invis,
		data_version = SavedState.data_version,
		settings = configs,
		style = {
			tokens = tokens,
			rules = rules
		},
		versions = {}
	}
end

function SavedState.save(state: SavedState)
	plugin:SetSetting("Jexplorer_SavedState", state)
end

function SavedState.load(manager: Types.Manager): SavedState
	local saved = plugin:GetSetting("Jexplorer_SavedState")
	
	if not saved then
		print("No saved state found, creating defaults")
		saved = SavedState.get_default(manager)
		return saved
	end
	
	if not saved.data_version or saved.data_version ~= SavedState.data_version then
		saved = SavedState._migrate(saved, manager)
		saved.data_version = SavedState.data_version
	end

	return saved
end

return SavedState