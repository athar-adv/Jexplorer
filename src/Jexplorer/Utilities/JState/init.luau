--!strict
--!optimize 2
local plugin = script:FindFirstAncestorOfClass("Plugin") :: Plugin

local main = script.Parent.Parent
local utilities = script.Parent
local editors = main.Editors

local SettingEditor = require(editors.SettingEditor)
local OrderEditor = require(editors.OrderEditor)
local InstanceVisibilityEditor = require(editors.InstanceVisibilityEditor)

local Style = require(utilities.Style)
local JDF = require(utilities.JDF)
local Selector = require(utilities.Selector)
local DefaultStyle = require(utilities.DefaultStyle)
local DefaultSettings = require(utilities.DefaultSettings)
local DefaultOrder = require(utilities.DefaultOrder)
local DefaultInvisClasses = require(utilities.DefaultInvisibleClasses)

local Types = require(main.Types)

export type JStateObject = {
	Style: Style.Style,
	Settings: {[string]: any},
	Order: {
		ClassPriorities: {string},
		DefaultPriority: number
	},
	InvisibleClasses: {[string]: boolean},
	-- user defined tabs
	Tabs: {
		{
			name: string,
			ids: {string}
		}
	},
	Version: number
}

-- Bump this when defaults change
local CURRENT_VERSION = 63

local DEFAULT_INVIS_MAP = {}
for _, v in DefaultInvisClasses do
	DEFAULT_INVIS_MAP[v] = true
end

local GAME_ID = tostring(game.PlaceId)

local JState = {
	Manager = (nil::any) :: Types.Manager,
	Initialized = false,
	DefaultTokens = {} :: {[string]: boolean},
	DefaultRules = {} :: {[Style.Rule]: boolean}
}

function JState.getDefaultStyle()
	local defaultTokens, defaultRules = DefaultStyle(JState.Manager)
	return Style.fromRulesTokens(defaultRules, defaultTokens)
end

function JState.getDefaultSettings()
	local settings = {}
	for _, list in DefaultSettings do
		for name, v in list do
			settings[name] = v.Default
		end
	end
	return settings
end

function JState.getDefaultOrder()
	return {
		ClassPriorities = DefaultOrder(JState.Manager),
		DefaultPriority = 999
	}
end

function JState.getDefaultInvisClasses()
	return table.clone(DEFAULT_INVIS_MAP)
end

function JState.getDefaultState(): JStateObject
	return {
		Style = JState.getDefaultStyle(),
		Settings = JState.getDefaultSettings(),
		Order = JState.getDefaultOrder(),
		InvisibleClasses = JState.getDefaultInvisClasses(),
		Tabs = {},
		Version = CURRENT_VERSION
	}
end

local function serializeRules(rules: {Style.Rule}, targetTable: {any})
	for _, rule in rules do
		local props = {}
		for k, v in rule.RawProperties do
			props[k] = JDF.to(v)
		end

		local ruleData = {
			name = rule:GetName(),
			priority = rule.Rule.Priority,
			selector = rule.Rule.Selector,
			children = {},
			properties = props,
			isDefault = JState.DefaultRules[rule] == true
		}
		table.insert(targetTable, ruleData)
		if #rule.ChildRules > 0 then
			serializeRules(rule.ChildRules, ruleData.children)
		end
	end
end

local function deserializeRules(serializedRules: {any}, targetTable: {Style.Rule}, nodefault: boolean)
	for _, ruleData in serializedRules do
		if nodefault and ruleData.isDefault then continue end
		local props = {}
		for k, v in ruleData.properties do
			props[k] = JDF.from(v)
		end
		if #ruleData.children > 0 then
			deserializeRules(ruleData.children, props, nodefault)
		end
		
		local rule = Style.rule(ruleData.name, ruleData.selector, ruleData.priority, props)
		table.insert(targetTable, rule)
		if ruleData.isDefault then
			JState.DefaultRules[rule] = true
		end
	end
end

local function serializeState(style: Style.Style, settings: {[string]: any}, defaultPriority: number, order: {string}, invisibleClasses: {[string]: boolean}, tabs: {Types.Tab}, globalTabs: {[string]: any})
	local styleData = {
		tokens = {},
		rules = {}
	}
	
	serializeRules(style.Rules, styleData.rules)

	for k, v in style.Tokens do
		styleData.tokens[k] = {value = JDF.to(v), isDefault = JState.DefaultTokens[k] == true}
	end

	local serializedSettings = {}
	for k, v in settings do
		serializedSettings[k] = JDF.to(v)
	end
	
	local tabArray = {}
	local getInstId = JState.Manager.getInstId
	local world = JState.Manager.WidgetState.World
	local components = JState.Manager.Components
	
	for _, tab in tabs do
		local ids = {}
		for _, ent in tab.Roots do
			local inst = world:get(ent, components.Instance)
			if not inst then continue end
			
			local id = getInstId(inst)
			table.insert(ids, id)
		end
		table.insert(tabArray, {
			name = tab.Name,
			ids = ids,
		})
	end
	globalTabs[GAME_ID] = tabArray
	
	return {
		Style = styleData,
		Settings = serializedSettings,
		Order = {
			ClassPriorities = order,
			DefaultPriority = defaultPriority
		},
		Tabs = globalTabs,
		InvisibleClasses = invisibleClasses,
		Version = CURRENT_VERSION
	}
end

function JState.save()
	assert(JState.Initialized, "JState.init() must be called before functionality can be used")
	local Manager = JState.Manager
	local style = Manager.Style
	if not style then return end

	local settings = SettingEditor.Configs
	local order = OrderEditor.ClassPriorities
	local defaultPriority = OrderEditor.DefaultPriority
	
	local savedState = plugin:GetSetting("JState")
	local tabArray = savedState and (savedState.Tabs and (savedState.Tabs[GAME_ID] or {}) or {}) or {}
	
	local state = serializeState(style, settings, defaultPriority, order, InstanceVisibilityEditor.InvisibleClasses, Manager.WidgetState.Tabs, tabArray)
	plugin:SetSetting("JState", state)
end

function JState.load(): JStateObject
	assert(JState.Initialized, "JState.init() must be called before functionality can be used")

	local savedState = plugin:GetSetting("JState")
	
	-- Reset all styles if version is before the IsDefault property was added
	if not savedState or savedState.Version < 63 then
		-- Reset to default state if missing or outdated
		local defaultState = JState.getDefaultState()
		
		local tabArray = savedState.Tabs and (savedState.Tabs[game.PlaceId]) or {}
		local serialized = serializeState(
			defaultState.Style,
			defaultState.Settings,
			defaultState.Order.DefaultPriority,
			defaultState.Order.ClassPriorities,
			defaultState.InvisibleClasses,
			JState.Manager.WidgetState.Tabs,
			tabArray
		)
		for _, v in defaultState.Style.Rules do
			JState.DefaultRules[v] = true
		end
		for k in defaultState.Style.Tokens do
			JState.DefaultTokens[k] = true
		end
		plugin:SetSetting("JState", serialized)
		return defaultState
	elseif savedState.Version ~= CURRENT_VERSION then
		local defaultTokens, defaultRules = DefaultStyle(JState.Manager)
		
		local savedStyles = savedState.Style or { rules = {}, tokens = {} }
		local savedSettings = savedState.Settings or JState.getDefaultSettings()
		local savedOrder = savedState.Order or JState.getDefaultOrder()
		local savedInvisibleClasses = savedState.InvisibleClasses or JState.getDefaultInvisClasses()
		
		local userRules = {}
		if savedStyles.rules then
			deserializeRules(savedStyles.rules, userRules, true)
		end
		
		local userTokens = {}
		if savedStyles.tokens then
			for k, v in savedStyles.tokens do
				if not v.isDefault then
					userTokens[k] = JDF.from(v.value)
				end
			end
		end
		
		local combinedRules = {}
		local combinedTokens = {}
		for _, rule in defaultRules do
			table.insert(combinedRules, rule)
			JState.DefaultRules[rule] = true
		end
		for k, v in defaultTokens do
			combinedTokens[k] = v
			JState.DefaultTokens[k] = true
		end
		
		for _, rule in userRules do
			table.insert(combinedRules, rule)
		end
		for k, v in userTokens do
			combinedTokens[k] = v
		end
		
		local updatedStyle = Style.fromRulesTokens(combinedRules, combinedTokens)
		local restoredSettings = {}
		for k, v in savedSettings do
			restoredSettings[k] = JDF.from(v)
		end
		
		local tabArray = savedState.Tabs and (savedState.Tabs[GAME_ID] or {}) or {}
		
		local updatedState: JStateObject = {
			Style = updatedStyle,
			Settings = restoredSettings,
			Order = savedOrder,
			InvisibleClasses = savedInvisibleClasses,
			Tabs = tabArray,
			Version = CURRENT_VERSION
		}
		
		return updatedState
	end
	
	-- Load saved state
	local savedStyles = savedState.Style or { rules = {}, tokens = {} }

	-- Reconstruct rules
	local savedRules = {}
	deserializeRules(savedStyles.rules or {}, savedRules, false)
	
	-- Reconstruct tokens
	local savedTokens = {}
	for k, v in savedStyles.tokens or {} do
		savedTokens[k] = JDF.from(v.value)
		if v.isDefault then
			JState.DefaultTokens[k] = true
		end
	end
	
	local restoredStyle = Style.fromRulesTokens(savedRules, savedTokens)

	local restoredSettings = {}
	for k, v in savedState.Settings do
		restoredSettings[k] = JDF.from(v)
	end
	
	local getInstWithId = JState.Manager.getInstFromId
	local tabArray = savedState.Tabs and (savedState.Tabs[GAME_ID] or {}) or {}
	
	local finalState: JStateObject = {
		Style = restoredStyle,
		Settings = restoredSettings,
		Order = savedState.Order,
		InvisibleClasses = savedState.InvisibleClasses,
		Tabs = tabArray,
		Version = CURRENT_VERSION
	}

	return finalState
end

function JState.init(manager: Types.Manager)
	assert(not JState.Initialized, "JState.init() cannot be called twice")
	JState.Initialized = true
	JState.Manager = manager
end

return JState
