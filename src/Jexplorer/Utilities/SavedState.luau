--!strict

local plugin = script:FindFirstAncestorOfClass("Plugin")

local Style = require("./Style")

local Types = require("../Types")
local DefaultOrder = require("./Defaults/DefaultOrder")
local DefaultInvisibleClasses = require("./Defaults/DefaultInvisibleClasses")
local DefaultSettings = require("./Defaults/DefaultSettings")
local DefaultStyle = require("./Defaults/DefaultStyle")
local UDF = require("./UDF")

export type SavedState = Types.SavedState

local SavedState = {
	data_version = 6
}

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
	if not saved or saved.data_version ~= SavedState.data_version then
		saved = SavedState.get_default(manager)
	end
	
	return saved
end

return SavedState