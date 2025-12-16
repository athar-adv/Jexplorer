local Types = require("../../Types")
local UDF = require("../UDF")
local default_style = require("../Defaults/DefaultStyle")
local default_settings = require("../Defaults/DefaultSettings")
local default_invisible_classes = require("../Defaults/DefaultInvisibleClasses")

local function noop() end

local function reset_styles(self, state, manager)
	local defaultTokens, defaultRules = default_style(manager)
	local rules: {Types.SerializedStyleRule} = {}
	local tokens = {}

	self._serialize_rules(defaultRules, rules)
	for k, v in defaultTokens do
		tokens[k] = UDF.to(v)
	end
	state.style.rules = rules
	state.style.tokens = tokens
end

local function reset_invisible_classes(self, state, manager)
	local dict = {}
	for _, v in default_invisible_classes do
		dict[v] = true
	end
	state.invisible = dict
end

local function reset_internal_behavior_settings(self, state, manager)
	local default = table.clone(state.settings)
	local configs = default_settings
	for name, v in configs.InternalBehavior do
		default[name] = UDF.to(v.Default)
	end
	state.settings = default
end

local migrations
migrations = {
	v6_to_v7 = reset_styles,
	v7_to_v8 = noop,
	v8_to_v9 = noop,
	v9_to_v10 = reset_internal_behavior_settings,
	v10_to_v11 = noop,
	v11_to_v12 = reset_styles,
	v12_to_v13 = reset_invisible_classes,
	v13_to_v14 = reset_styles
}
:: {[string]: (any, Types.SavedState, Types.Manager) -> Types.SavedState?}

return migrations