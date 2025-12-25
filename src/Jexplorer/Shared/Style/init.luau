--!strict
--!optimize 2

local eval = require(script.EvalASEL)
local SimpleSignal = require(script.Parent.Vendor.SimpleSignal)

export type Expression = {
	__stylevar: boolean,
	__expr: string
}

export type Cloned = {
	__clonedrule: boolean,
	__name: string
}

export type Style = {
	Sheet: StyleSheet,
	Tokens: {[string]: any},
	AppliedTokens: {[string]: any},
	TokenDependencies: {[string]: {string}},

	Links: {StyleLink},
	Rules: {Rule},
	Link: (Style, gui: Instance) -> StyleLink,

	SetToken: (Style, name: string, value: any, autoUpdate: boolean) -> (),
	GetToken: (Style, name: string) -> any,
	UpdateTokens: (Style) -> (),
	UpdateToken: (Style, name: string) -> (),
	GetDependencies: (Style, expr: string) -> {string},

	AddRules: (Style, rules: {[any]: any}) -> (),
	FindRule: (Style, selector: string) -> StyleRule?,
	GetTagged: (Style, tag: string) -> {Rule},
	GetWithoutTags: (Style, ...string) -> {Rule},
	Replace: (Style, newStyle: Style) -> (),

	RuleAdded: SimpleSignal.SimpleSignal<Rule>,
	RuleRemoved: SimpleSignal.SimpleSignal<Rule>,
	TokenChanged: SimpleSignal.SimpleSignal<string, any>,
	AppliedTokenChanged: SimpleSignal.SimpleSignal<string, any>,
}

export type Rule = {
	Rule: StyleRule,
	Sheet: Style,
	ChildRules: {Rule},
	ParentRule: Rule?,
	Tags: {[string]: boolean},
	PropertyDependencies: {[string]: {string}},

	AddTag: (Rule, string) -> (),
	HasTag: (Rule, string) -> boolean,
	RemoveTag: (Rule, string) -> (),
	GetTagged: (Rule, tag: string) -> {Rule},
	GetWithoutTags: (Rule, ...string) -> {Rule},

	RawProperties: {[string]: any},
	AppliedProperties: {[string]: any},

	AddRules: (Rule, rules: {Rule}) -> (),
	SetProperty: (Rule, k: string, value: any) -> (),
	GetProperty: (Rule, k: string) -> any,
	GetName: (Rule) -> string,
	SetName: (Rule, name: string) -> (),
	Destroy: (Rule) -> (),

	PropertyChanged: SimpleSignal.SimpleSignal<string, any>,
	AppliedPropertyChanged: SimpleSignal.SimpleSignal<string, any>,
	RuleAdded: SimpleSignal.SimpleSignal<Rule>,
	RuleRemoved: SimpleSignal.SimpleSignal<Rule>,

	init: (Rule, sheet: Style) -> (),
	__initialized: boolean
}

local RULE_NAME_FORMAT = "%s"

local Style = {
	eval = eval
}

-- Extract all $TOKEN references from an expression
local function getDependencies(expr: string): {string}
	local deps = {}
	local seen = {}

	-- Match $TOKEN pattern (alphanumeric and underscore after $)
	for token in expr:gmatch("%$([%w_]+)") do
		if not seen[token] then
			seen[token] = true
			table.insert(deps, token)
		end
	end

	return deps
end

-- Topological sort for token evaluation order
local function topologicalSort(tokens: {[string]: any}, tokenDeps: {[string]: {string}}): {string}
	local sorted = {}
	local visited = {}
	local visiting = {}

	local function visit(name: string)
		if visited[name] then return end
		if visiting[name] then
			error(`Circular dependency detected involving token '${name}'`)
		end

		visiting[name] = true
		local deps = tokenDeps[name]
		if deps then
			for _, dep in deps do
				if tokens[dep] ~= nil then
					visit(dep)
				end
			end
		end
		visiting[name] = nil
		visited[name] = true
		table.insert(sorted, name)
	end

	for name in tokens do
		if type(name) == "string" and not visited[name] then
			visit(name)
		end
	end

	return sorted
end

local function filterRules(style: Style, rules: {[string | number]: any}, tokens: {[string]: any})
	local sheet = style.Sheet

	-- First pass: collect all tokens and their dependencies
	for k, v in rules do
		if type(k) == "number" then continue end
		if type(v) == "table" and v.__stylevar then
			style.TokenDependencies[k] = getDependencies(v.__expr)
		else
			style.TokenDependencies[k] = {}
		end
		tokens[k] = v
		rules[k] = nil
	end

	-- Sort tokens in dependency order
	local sortedTokens = topologicalSort(tokens, style.TokenDependencies)

	-- Evaluate tokens in order, building up AppliedTokens progressively
	for _, tokenName in sortedTokens do
		local v = tokens[tokenName]
		if type(v) == "table" and v.__stylevar then
			-- Evaluate using the progressively built AppliedTokens
			local evaluated = eval(v.__expr, style.AppliedTokens)
			sheet:SetAttribute(tokenName, evaluated)
			style.AppliedTokens[tokenName] = evaluated
		else
			-- Store literal values directly
			pcall(sheet.SetAttribute, sheet, tokenName, v)
			style.AppliedTokens[tokenName] = v
		end
	end

	-- Now evaluate rule properties
	for _, rule in rules do
		for k, v in rule.RawProperties do
			if type(v) == "table" and v.__stylevar then
				rule.PropertyDependencies[k] = getDependencies(v.__expr)
				local evaluated = eval(v.__expr, style.AppliedTokens)
				rule.AppliedProperties[k] = evaluated
			elseif type(v) == "string" and v:sub(1, 1) == "$" then
				rule.PropertyDependencies[k] = getDependencies(v)
				local evaluated = style.AppliedTokens[k]
				rule.AppliedProperties[k] = evaluated
			else
				rule.PropertyDependencies[k] = {}
				rule.AppliedProperties[k] = v
			end
		end
	end

	for k, rule: Rule in rules do
		if rule.__initialized then continue end
		rule:init(style)

		for _, v in rule.AppliedProperties do
			if type(v) ~= "string" then continue end
			if v:sub(1, 1) ~= "$" then continue end
			local tokenName = v:sub(2)
			if sheet:GetAttribute(tokenName) == nil then
				error(`token '${tokenName}' not found (selector '{rule.Rule.Selector}')`)
			end
		end
	end
end

local StyleMethods = {} :: Style
(StyleMethods::any).__index = StyleMethods

function StyleMethods:Link(gui)
	local sheet = self.Sheet
	local link = Instance.new("StyleLink")
	link.StyleSheet = sheet
	link.Parent = gui
	table.insert(self.Links, link)
	return link
end

function StyleMethods:GetToken(name: string)
	return self.AppliedTokens[name]
end

function StyleMethods:GetDependencies(expr: string): {string}
	return getDependencies(expr)
end

-- Build reverse dependency map (which tokens are affected by a change)
local function buildReverseDeps(tokenDeps: {[string]: {string}}): {[string]: {string}}
	local reverseDeps: {[string]: {string}} = {}

	for tokenName, deps in tokenDeps do
		for _, depToken in deps do
			if not reverseDeps[depToken] then
				reverseDeps[depToken] = {}
			end
			table.insert(reverseDeps[depToken], tokenName)
		end
	end

	return reverseDeps
end

-- Update only the specified token and its dependents
function StyleMethods:UpdateToken(name: string)
	local sheet = self.Sheet

	-- Build reverse dependency map
	local reverseDeps = buildReverseDeps(self.TokenDependencies)

	-- Determine which tokens need updating (BFS for transitive dependencies)
	local toUpdate = {[name] = true}
	local queue = {name}
	local queueIdx = 1

	while queueIdx <= #queue do
		local current = queue[queueIdx]
		queueIdx = queueIdx + 1

		local dependents = reverseDeps[current]
		if dependents then
			for _, dependent in dependents do
				if not toUpdate[dependent] then
					toUpdate[dependent] = true
					table.insert(queue, dependent)
				end
			end
		end
	end

	-- Build subset of tokens to update
	local tokensToUpdate = {}
	for tokenName in toUpdate do
		tokensToUpdate[tokenName] = self.Tokens[tokenName]
	end

	-- Sort them in dependency order
	local sortedTokens = topologicalSort(tokensToUpdate, self.TokenDependencies)

	-- Update tokens in dependency order
	for _, tokenName in sortedTokens do
		local v = self.Tokens[tokenName]
		if type(v) == "table" and v.__stylevar then
			local evaluated = eval(v.__expr, self.AppliedTokens)
			sheet:SetAttribute(tokenName, evaluated)
			self.AppliedTokens[tokenName] = evaluated
			self.AppliedTokenChanged:Fire(tokenName, evaluated)
		else
			pcall(sheet.SetAttribute, sheet, tokenName, v)
			self.AppliedTokens[tokenName] = v
			self.AppliedTokenChanged:Fire(tokenName, v)
		end
	end

	-- Update rules that depend on these tokens
	local function updateRulesRecursive(rules: {Rule})
		for _, ruleTbl in rules do
			for propName, deps in ruleTbl.PropertyDependencies do
				-- Check if this property depends on any updated token
				local needsUpdate = false
				for _, dep in deps do
					if toUpdate[dep] then
						needsUpdate = true
						break
					end
				end

				if needsUpdate then
					local v = ruleTbl.RawProperties[propName]
					if type(v) == "table" and v.__stylevar then
						local evaluated = eval(v.__expr, self.AppliedTokens)
						ruleTbl.Rule:SetProperty(propName, evaluated)
						ruleTbl.AppliedProperties[propName] = evaluated
						ruleTbl.AppliedPropertyChanged:Fire(propName, evaluated)
					else
						ruleTbl.Rule:SetProperty(propName, v)
						ruleTbl.AppliedProperties[propName] = v
						ruleTbl.AppliedPropertyChanged:Fire(propName, v)
					end
				end
			end

			if #ruleTbl.ChildRules > 0 then
				updateRulesRecursive(ruleTbl.ChildRules)
			end
		end
	end

	updateRulesRecursive(self.Rules)
end

function StyleMethods:SetToken(name: string, value: any, autoUpdate: boolean)
	local sheet = self.Sheet

	self.Tokens[name] = value
	if type(value) == "table" and value.__stylevar then
		self.TokenDependencies[name] = getDependencies(value.__expr)
		local evaluated = eval(value.__expr, self.AppliedTokens)
		sheet:SetAttribute(name, evaluated)
		self.AppliedTokens[name] = evaluated
	else
		self.TokenDependencies[name] = {}
		pcall(sheet.SetAttribute, sheet, name, value)
		self.AppliedTokens[name] = value
	end

	self.TokenChanged:Fire(name, value)

	if autoUpdate then
		self:UpdateToken(name)
	end
end

function StyleMethods:UpdateTokens()
	local sheet = self.Sheet

	-- Sort tokens in dependency order
	local sortedTokens = topologicalSort(self.Tokens, self.TokenDependencies)

	-- Update tokens in order
	for _, tokenName in sortedTokens do
		local v = self.Tokens[tokenName]
		if type(v) == "table" and v.__stylevar then
			local evaluated = eval(v.__expr, self.AppliedTokens)
			sheet:SetAttribute(tokenName, evaluated)
			self.AppliedTokens[tokenName] = evaluated
			self.AppliedTokenChanged:Fire(tokenName, evaluated)
		else
			pcall(sheet.SetAttribute, sheet, tokenName, v)
			self.AppliedTokens[tokenName] = v
			self.AppliedTokenChanged:Fire(tokenName, v)
		end
	end

	local function updateRulesRecursive(rules: {Rule})
		for _, ruleTbl in rules do
			for k, v in ruleTbl.RawProperties do
				if type(v) == "table" and v.__stylevar then
					local evaluated = eval(v.__expr, self.AppliedTokens)
					ruleTbl.Rule:SetProperty(k, evaluated)
					ruleTbl.AppliedProperties[k] = evaluated

					ruleTbl.AppliedPropertyChanged:Fire(k, evaluated)
				else
					ruleTbl.Rule:SetProperty(k, v)
					ruleTbl.AppliedProperties[k] = v

					ruleTbl.AppliedPropertyChanged:Fire(k, v)
				end
			end
			if #ruleTbl.ChildRules > 0 then
				updateRulesRecursive(ruleTbl.ChildRules)
			end
		end
	end
	updateRulesRecursive(self.Rules)
end

function StyleMethods:Replace(new: Style)
	local sheet = self.Sheet
	new.Sheet.Parent = sheet.Parent

	for _, v in self.Links do
		v.StyleSheet = new.Sheet
	end
	sheet:Destroy()

	self.Sheet = new.Sheet
	table.clear(self.Rules)
	for _, v in new.Rules do
		table.insert(self.Rules, v)
		self.RuleAdded:Fire(v)
	end
	table.clear(self.Tokens)
	for k, v in new.Tokens do
		self.Tokens[k] = v
		self.TokenChanged:Fire(k, v)
	end
	table.clear(self.AppliedTokens)
	for k, v in new.AppliedTokens do
		self.AppliedTokens[k] = v
	end
	table.clear(self.TokenDependencies)
	for k, v in new.TokenDependencies do
		self.TokenDependencies[k] = v
	end
end

function StyleMethods:AddRules(newRules)
	filterRules(self, newRules, self.Tokens)
	for _, v in newRules do
		self.Sheet:InsertStyleRule(v.Rule)
		table.insert(self.Rules, v)
		self.RuleAdded:Fire(v)
	end
end

function StyleMethods:FindRule(selector)
	local rule = self.Sheet:FindFirstChild(RULE_NAME_FORMAT:format(selector))
	return rule :: StyleRule
end

function StyleMethods:GetTagged(tag: string): {Rule}
	local tagged = {}
	for _, rule in self.Rules do
		if rule:HasTag(tag) then
			table.insert(tagged, rule)
		end
	end
	return tagged
end

function StyleMethods:GetWithoutTags(...: string): {Rule}
	local excludeTags = {...}
	local result = {}
	for _, rule in self.Rules do
		local hasExcludedTag = false
		for _, tag in excludeTags do
			if rule:HasTag(tag) then
				hasExcludedTag = true
				break
			end
		end
		if not hasExcludedTag then
			table.insert(result, rule)
		end
	end
	return result
end

local RuleMethods = {} :: Rule
(RuleMethods::any).__index = RuleMethods

function RuleMethods:AddTag(tag)
	self.Tags[tag] = true
end

function RuleMethods:HasTag(tag)
	return self.Tags[tag] == true
end

function RuleMethods:RemoveTag(tag)
	self.Tags[tag] = nil
end

function RuleMethods:GetTagged(tag: string): {Rule}
	local tagged = {}
	for _, rule in self.ChildRules do
		if rule:HasTag(tag) then
			table.insert(tagged, rule)
		end
	end
	return tagged
end

function RuleMethods:GetWithoutTags(...: string): {Rule}
	local excludeTags = {...}
	local result = {}
	for _, rule in self.ChildRules do
		local hasExcludedTag = false
		for _, tag in excludeTags do
			if rule:HasTag(tag) then
				hasExcludedTag = true
				break
			end
		end
		if not hasExcludedTag then
			table.insert(result, rule)
		end
	end
	return result
end

function RuleMethods:SetProperty(k, v)
	local realProps = self.AppliedProperties
	local props = self.RawProperties
	local style = self.Sheet

	if type(v) == "table" and v.__stylevar then
		self.PropertyDependencies[k] = getDependencies(v.__expr)
		local evaluated = eval(v.__expr, style.AppliedTokens)
		realProps[k] = evaluated
	elseif type(v) == "string" and v:sub(1, 1) == "$" then
		self.PropertyDependencies[k] = getDependencies(v)
		local evaluated = style.AppliedTokens[k]
		realProps[k] = evaluated
	else
		self.PropertyDependencies[k] = {}
		realProps[k] = v
	end
	self.Rule:SetProperty(k, realProps[k])
	props[k] = v
	self.PropertyChanged:Fire(k, v)
end

function RuleMethods:AddRules(rules)
	local sheet = self.Sheet
	for _, rule in rules do
		for k, v in rule.RawProperties do
			if type(v) == "table" and v.__stylevar then
				rule.PropertyDependencies[k] = getDependencies(v.__expr)
				local evaluated = eval(v.__expr, sheet.AppliedTokens)
				rule.AppliedProperties[k] = evaluated
			elseif type(v) == "string" and v:sub(1, 1) == "$" then
				rule.PropertyDependencies[k] = getDependencies(v)
				local evaluated = self.Sheet.AppliedTokens[k]
				rule.AppliedProperties[k] = evaluated
			else
				rule.PropertyDependencies[k] = {}
				rule.AppliedProperties[k] = v
			end
		end
	end

	for k, rule in rules do
		rule:init(sheet)
		for _, v in rule.AppliedProperties do
			if type(v) ~= "string" then continue end
			if v:sub(1, 1) ~= "$" then continue end
			local tokenName = v:sub(2)
			if sheet.Tokens[tokenName] == nil then
				error(`token '${tokenName}' not found (selector '{rule.Rule.Selector}')`)
			end
		end
	end
	for _, v in rules do
		v.ParentRule = self
		table.insert(self.ChildRules, v)
		v.Rule.Parent = self.Rule
		self.RuleAdded:Fire(v)
	end
end

function RuleMethods:GetProperty(k)
	return self.Rule:GetProperty(k)
end

function RuleMethods:GetName()
	return self.Rule:GetAttribute("Name")
end

function RuleMethods:SetName(new)
	self.Rule:SetAttribute("Name", new)
end

function RuleMethods:Destroy()
	self.Sheet.RuleRemoved:Fire(self)
	if self.ParentRule then
		self.ParentRule.RuleRemoved:Fire(self)
		local tbl = self.ParentRule.ChildRules
		local idx = table.find(tbl, self)
		if idx then
			local n = #tbl
			tbl[idx] = tbl[n]
			tbl[n] = nil
		end
	end
	local rule = self.Rule
	local rules = self.Sheet.Rules

	local idx = table.find(rules, self)
	if idx then
		local l = #rules
		rules[idx] = rules[l]
		rules[l] = nil
	end
	rule:Destroy()
	table.clear(self.RawProperties)
	table.clear(self.AppliedProperties)

	self.PropertyChanged:Destroy()
	self.AppliedPropertyChanged:Destroy()
	self.RuleAdded:Destroy()
	self.RuleRemoved:Destroy()
end

function RuleMethods:init(sheet)
	assert(not self.__initialized, `rule '{self:GetName()}' has already been initialized.`)
	self.__initialized = true
	self.Sheet = sheet

	local rule = self.Rule
	local realProps = self.AppliedProperties
	local props = self.RawProperties

	if not self.ParentRule then
		rule.Parent = sheet.Sheet
	else
		rule.Parent = self.ParentRule.Rule
	end

	for k, v in props do
		if type(v) == "table" and v.__stylevar then
			local evaluated = eval(v.__expr, sheet.AppliedTokens)
			realProps[k] = evaluated
		else
			realProps[k] = v
		end
	end
	rule:SetProperties(realProps)

	local nameMap = {}
	for _, v in sheet.Rules do
		nameMap[v:GetName()] = v
	end

	local rulesToInit: {Rule} = {}
	local clonesToResolve = {}

	for i, v: any in self.ChildRules do
		if typeof(v) == "table" and v.__clonedrule then
			local existing = nameMap[v.__name]
			assert(existing, `Rule '{v.__name}' does not exist. Cannot use Style.cloned() rule`)

			local cloned = Style.cloneRule(existing)
			cloned.ParentRule = self
			clonesToResolve[i] = cloned
			table.insert(rulesToInit, cloned)
		else
			v.ParentRule = self
			table.insert(rulesToInit, v)
		end
	end
	for i, cloned in clonesToResolve do
		self.ChildRules[i] = cloned
	end

	for _, rule in rulesToInit do
		for k, v in rule.RawProperties do
			if type(v) == "table" and v.__stylevar then
				local evaluated = eval(v.__expr, sheet.AppliedTokens)
				rule.AppliedProperties[k] = evaluated
			else
				rule.AppliedProperties[k] = v
			end
		end
	end

	for k, rule in rulesToInit do
		rule:init(sheet)

		for _, v in rule.AppliedProperties do
			if type(v) ~= "string" then continue end
			if v:sub(1, 1) ~= "$" then continue end
			local tokenName = v:sub(2)
			if sheet.Tokens[tokenName] == nil then
				error(`token '${tokenName}' not found (selector '{rule.Rule.Selector}')`)
			end
		end
	end
end

function Style.var(expr: string): Expression
	return {
		__stylevar = true,
		__expr = expr
	}
end

function Style.cloned(ruleName: string): Cloned
	return {
		__clonedrule = true,
		__name = ruleName
	}
end

function Style.cloneRule(rule: Rule)
	local cloned = Style.rule(rule:GetName(), rule.Rule.Selector, rule.Rule.Priority, rule.RawProperties)
	local clonedChildren = {}
	for _, v in rule.ChildRules do
		table.insert(clonedChildren, Style.cloneRule(v))
	end
	cloned:AddRules(clonedChildren)

	return cloned
end

function Style.rule(name: string, selector: string, priority: number, props: {[any]: any}): Rule
	local rule = Instance.new("StyleRule")
	rule.Selector = selector
	if rule.SelectorError ~= "" then
		error(rule.SelectorError)
	end
	rule.Priority = priority
	rule.Name = RULE_NAME_FORMAT:format(selector)
	rule:SetAttribute("Name", name)

	local arrayPart = {}
	local childrenRules = {}
	for i, v in ipairs(props::any) do
		table.insert(arrayPart, i)
		table.insert(childrenRules, v)
	end

	for _, i in arrayPart do
		props[i] = nil
	end

	rule:GetPropertyChangedSignal("Selector"):Connect(function()
		rule.Name = RULE_NAME_FORMAT:format(rule.Selector)
	end)

	local realProps = {}
	local ruleTbl = setmetatable({
		Rule = rule,
		RawProperties = props,
		AppliedProperties = realProps,
		ChildRules = childrenRules,
		Tags = {},
		PropertyDependencies = {},

		PropertyChanged = SimpleSignal.new(),
		AppliedPropertyChanged = SimpleSignal.new(),
		RuleAdded = SimpleSignal.new(),
		RuleRemoved = SimpleSignal.new()
	} :: Rule, RuleMethods) :: any

	return ruleTbl
end

function Style.create(rules: {[any]: any}): Style
	local sheet = Instance.new("StyleSheet")

	local tokens = {}
	local style = setmetatable({
		Sheet = sheet,
		Tokens = tokens,
		Links = {},
		AppliedTokens = {}, -- Start with empty table, not GetAttributes()
		TokenDependencies = {},
		Rules = rules,

		RuleAdded = SimpleSignal.new(),
		RuleRemoved = SimpleSignal.new(),
		TokenChanged = SimpleSignal.new(),
		AppliedTokenChanged = SimpleSignal.new()
	} :: Style, StyleMethods) :: any

	filterRules(style, rules, tokens)

	for _, v in rules do
		sheet:InsertStyleRule(v.Rule)
	end

	return style
end

function Style.fromRulesTokens(rules: {Rule}, tokens: {[string]: any}): Style
	local tbl = {}
	for k, v in tokens do
		tbl[k] = v
	end
	for i, v in rules do
		tbl[i :: any] = v
	end
	local sheet = Style.create(tbl)
	sheet:UpdateTokens()

	return sheet
end

return Style