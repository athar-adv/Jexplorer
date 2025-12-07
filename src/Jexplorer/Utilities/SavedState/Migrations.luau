local Types = require("../../Types")
local UDF = require("../UDF")
local default_style = require("../Defaults/DefaultStyle")
local default_settings = require("../Defaults/DefaultSettings")

local migrations
migrations = {
	v6_to_v7 = function(self, state, manager)
		local defaultTokens, defaultRules = default_style(manager)
		local rules: {Types.SerializedStyleRule} = {}
		local tokens = {}
		
		self._serialize_rules(defaultRules, rules)
		for k, v in defaultTokens do
			tokens[k] = UDF.to(v)
		end
		state.style.rules = rules
		state.style.tokens = tokens
	end,
	v7_to_v8 = function(...)
		migrations.v6_to_v7(...)
	end,
	v8_to_v9 = function()
		--NOOP
	end,
	v9_to_v10 = function(self, state, manager)
		local default = table.clone(state.settings)
		local configs = default_settings
		for name, v in configs.InternalBehavior do
			default[name] = UDF.to(v.Default)
		end
		state.settings = default
	end,
}
:: {[string]: (any, Types.SavedState, Types.Manager) -> Types.SavedState?}

return migrations