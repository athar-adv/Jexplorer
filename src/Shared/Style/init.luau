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

export type StyleToken = {
	__styletoken: boolean,
	Name: string?,
	RawValue: any,
	AppliedValue: any,
	Sheet: Style?,
	Tags: {[string]: boolean},

	AddTag: (StyleToken, string) -> (),
	HasTag: (StyleToken, string) -> boolean,
	RemoveTag: (StyleToken, string) -> (),

	init: (StyleToken, sheet: Style, name: string) -> (),
	evaluate: (StyleToken) -> (),
	__initialized: boolean,
}

export type Style = {
	Sheet: StyleSheet,
	Tokens: {[string]: StyleToken},
	AppliedTokens: {[string]: any},
	TokenDependencies: {[string]: {string}},

	Links: {StyleLink},
	Rules: {Rule},
	Link: (Style, gui: Instance) -> StyleLink,

	SetToken: (Style, name: string, value: (StyleToken | any)?, autoUpdate: boolean) -> (),
	GetToken: (Style, name: string) -> any,
	GetRawToken: (Style, name: string) -> StyleToken?,
	UpdateTokens: (Style) -> (),
	UpdateToken: (Style, name: string) -> (),
	GetDependencies: (Style, expr: string) -> {string},

	AddRules: (Style, rules: {[any]: any}) -> (),
	FindRule: (Style, selector: string) -> Rule?,
	GetTagged: (Style, tag: string) -> {Rule},
	GetWithoutTags: (Style, ...string) -> {Rule},
	Replace: (Style, newStyle: Style) -> (),

	SlctrToRule: {[string]: Rule},

	RuleAdded: SimpleSignal.SimpleSignal<Rule>,
	RuleRemoved: SimpleSignal.SimpleSignal<Rule>,
	TokenChanged: SimpleSignal.SimpleSignal<string, StyleToken>,
	AppliedTokenChanged: SimpleSignal.SimpleSignal<string, any>,
}

export type Rule = {
	Rule: StyleRule,
	Sheet: Style,
	ChildRules: {Rule},
	ParentRule: Rule?,
	GetTokens: (Rule) -> {[string]: any},
	Tags: {[string]: boolean},
	PropertyDependencies: {[string]: {string}},
	
	GetChild: (Rule, childName: string) -> Rule,

	Tokens: {[string]: StyleToken},
	AppliedTokens: {[string]: any},
	TokenDependencies: {[string]: {string}},
	TokenChanged: SimpleSignal.SimpleSignal<string, StyleToken>,
	AppliedTokenChanged: SimpleSignal.SimpleSignal<string, any>,
	SetToken: (Rule, name: string, value: (StyleToken | any)?, autoUpdate: boolean) -> (),
	GetToken: (Rule, name: string) -> any,
	GetRawToken: (Rule, name: string) -> StyleToken?,
	UpdateTokens: (Rule) -> (),
	UpdateToken: (Rule, name: string) -> (),

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

local function unwrapValue(v: any): any
	if type(v) == "table" and v.__styletoken then
		return (v :: StyleToken).RawValue
	end
	return v
end

local function getDependencies(expr: string): {string}
	local deps = {}
	local seen = {}
	for token in expr:gmatch("%$([%w_]+)") do
		if not seen[token] then
			seen[token] = true
			table.insert(deps, token)
		end
	end
	return deps
end

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

local function buildRuleTokenContext(rule: Rule): {[string]: any}
	local chain: {Rule} = {}
	local cursor: Rule? = rule
	while cursor do
		table.insert(chain, 1, cursor)
		cursor = cursor.ParentRule
	end
	local resolved: {[string]: any} = {}
	if rule.Sheet then
		for k, v in rule.Sheet.AppliedTokens do
			resolved[k] = v
		end
	end
	for _, r in chain do
		for k, v in r.AppliedTokens do
			resolved[k] = v
		end
	end
	return resolved
end

local function evalProperty(inner: any, ctx: {[string]: any}): any
	if type(inner) == "table" and inner.__stylevar then
		return eval(inner.__expr, ctx)
	elseif type(inner) == "string" and inner:sub(1, 1) == "$" then
		return ctx[inner:sub(2)]
	else
		return inner
	end
end

local function updateRulesRecursive(rules: {Rule})
	for _, ruleTbl in rules do
		local ctx = buildRuleTokenContext(ruleTbl)
		for k, v in ruleTbl.RawProperties do
			local inner = unwrapValue(v)
			local evaluated = evalProperty(inner, ctx)
			ruleTbl.Rule:SetProperty(k, evaluated)
			ruleTbl.AppliedProperties[k] = evaluated
			ruleTbl.AppliedPropertyChanged:Fire(k, evaluated)
		end
		if #ruleTbl.ChildRules > 0 then
			updateRulesRecursive(ruleTbl.ChildRules)
		end
	end
end

-- StyleToken metatable -------------------------------------------------------

local TokenMethods = {} :: StyleToken;
(TokenMethods :: any).__index = TokenMethods;
(TokenMethods :: any).__tostring = function(self: StyleToken)
	return `StyleToken({tostring(self.RawValue)})`
end

function TokenMethods:AddTag(tag: string)
	self.Tags[tag] = true
end

function TokenMethods:HasTag(tag: string): boolean
	return self.Tags[tag] == true
end

function TokenMethods:RemoveTag(tag: string)
	self.Tags[tag] = nil
end

function TokenMethods:evaluate()
	local sheet = self.Sheet
	assert(sheet, "StyleToken must be initialized before calling evaluate()")
	local name = self.Name :: string
	local raw = self.RawValue

	local applied: any
	if type(raw) == "table" and raw.__stylevar then
		applied = eval(raw.__expr, sheet.AppliedTokens)
	else
		applied = raw
	end

	self.AppliedValue = applied
	sheet.AppliedTokens[name] = applied
	pcall(sheet.Sheet.SetAttribute, sheet.Sheet, name, applied)
end

function TokenMethods:init(sheet: Style, name: string)
	assert(not self.__initialized, `StyleToken '${name}' has already been initialized.`)
	self.__initialized = true
	self.Sheet = sheet
	self.Name = name

	local raw = self.RawValue
	if type(raw) == "table" and raw.__stylevar then
		sheet.TokenDependencies[name] = getDependencies(raw.__expr)
	else
		sheet.TokenDependencies[name] = {}
	end

	self:evaluate()
end

------------------------------------------------------------------------------

local function filterRules(style: Style, rules: {[string | number]: any}, tokens: {[string]: StyleToken})
	for k, v in rules do
		if type(k) == "number" then continue end
		local tok: StyleToken
		if type(v) == "table" and v.__styletoken then
			tok = v :: StyleToken
		else
			tok = Style.token(v)
		end
		tokens[k] = tok
		rules[k] = nil
	end

	for name, tok in tokens do
		local raw = tok.RawValue
		if type(raw) == "table" and raw.__stylevar then
			style.TokenDependencies[name] = getDependencies(raw.__expr)
		else
			style.TokenDependencies[name] = {}
		end
	end

	local sortedTokens = topologicalSort(tokens, style.TokenDependencies)
	for _, tokenName in sortedTokens do
		local tok = tokens[tokenName]
		if not tok.__initialized then
			tok:init(style, tokenName)
		end
	end

	for _, rule: Rule in rules do
		if rule.__initialized then continue end
		rule:init(style)
	end
end

local StyleMethods = {} :: Style
(StyleMethods :: any).__index = StyleMethods

function StyleMethods:Link(gui)
	local sheet = self.Sheet
	local link = Instance.new("StyleLink")
	link.StyleSheet = sheet
	link.Parent = gui
	table.insert(self.Links, link)
	return link
end

function StyleMethods:GetToken(name: string): any
	return self.AppliedTokens[name]
end

function StyleMethods:GetRawToken(name: string): StyleToken?
	return self.Tokens[name]
end

function StyleMethods:GetDependencies(expr: string): {string}
	return getDependencies(expr)
end

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

function StyleMethods:UpdateToken(name: string)
	local reverseDeps = buildReverseDeps(self.TokenDependencies)

	local toUpdate = {[name] = true}
	local queue = {name}
	local queueIdx = 1
	while queueIdx <= #queue do
		local current = queue[queueIdx]
		queueIdx += 1
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

	local tokensToUpdate = {}
	for tokenName in toUpdate do
		tokensToUpdate[tokenName] = self.Tokens[tokenName]
	end
	for _, tokenName in topologicalSort(tokensToUpdate, self.TokenDependencies) do
		local tok = self.Tokens[tokenName]
		tok:evaluate()
		self.AppliedTokenChanged:Fire(tokenName, tok.AppliedValue)
	end

	updateRulesRecursive(self.Rules)
end

function StyleMethods:SetToken(name: string, value: (StyleToken | any)?, autoUpdate: boolean)
	if not value then
		local tok: StyleToken = self.Tokens[name]
		if not tok then return end

		self.Tokens[name] = nil
		self.AppliedTokens[name] = nil
		self.TokenDependencies[name] = nil

		pcall(self.Sheet.SetAttribute, self.Sheet, name, nil)

		tok.Sheet = nil
		tok.Name = nil
		tok.__initialized = false
		self.TokenChanged:Fire(name, nil)

		return
	end

	local tok: StyleToken
	if type(value) == "table" and (value :: any).__styletoken then
		tok = value
	else
		tok = Style.token(value :: any)
	end

	tok.__initialized = false
	tok:init(self, name)
	self.Tokens[name] = tok
	self.TokenChanged:Fire(name, tok)

	if autoUpdate then
		self:UpdateToken(name)
	end
end

function StyleMethods:UpdateTokens()
	for _, tokenName in topologicalSort(self.Tokens, self.TokenDependencies) do
		local tok = self.Tokens[tokenName]
		tok:evaluate()
		self.AppliedTokenChanged:Fire(tokenName, tok.AppliedValue)
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
	return self.SlctrToRule[selector]
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

-- Rule metatable -------------------------------------------------------------

local RuleMethods = {} :: Rule
(RuleMethods :: any).__index = RuleMethods

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

function RuleMethods:GetTokens(): {[string]: any}
	return buildRuleTokenContext(self)
end

function RuleMethods:GetToken(name: string): any
	return self.AppliedTokens[name]
end

function RuleMethods:GetRawToken(name: string): StyleToken?
	return self.Tokens[name]
end

function RuleMethods:SetToken(name: string, value: (StyleToken | any)?, autoUpdate: boolean)
	if not value then
		local tok: StyleToken = self.Tokens[name]
		if not tok then return end
		self.Tokens[name] = nil
		self.AppliedTokens[name] = nil
		self.TokenDependencies[name] = nil
		tok.Sheet = nil
		tok.Name = nil
		tok.__initialized = false
		self.TokenChanged:Fire(name, nil)
		return
	end

	local tok: StyleToken
	if type(value) == "table" and (value :: any).__styletoken then
		tok = value
	else
		tok = Style.token(value :: any)
	end
	
	self.AppliedTokens = buildRuleTokenContext(self)
	local fakeSheet = {
		AppliedTokens = self.AppliedTokens,
		TokenDependencies = self.TokenDependencies,
		Sheet = { SetAttribute = function() end },
	}
	
	tok.__initialized = false
	tok:init(fakeSheet :: any, name)
	self.Tokens[name] = tok
	self.TokenChanged:Fire(name, tok)

	if autoUpdate then
		self:UpdateToken(name)
	end
end

function RuleMethods:UpdateToken(name: string)
	local reverseDeps = buildReverseDeps(self.TokenDependencies)
	local toUpdate = {[name] = true}
	local queue = {name}
	local queueIdx = 1
	while queueIdx <= #queue do
		local current = queue[queueIdx]
		queueIdx += 1
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
	
	self.AppliedTokens = buildRuleTokenContext(self)
	local fakeSheet = {
		AppliedTokens = self.AppliedTokens,
		TokenDependencies = self.TokenDependencies,
		Sheet = { SetAttribute = function() end },
	}
	local tokensToUpdate = {}
	for tokenName in toUpdate do
		tokensToUpdate[tokenName] = self.Tokens[tokenName]
	end
	for _, tokenName in topologicalSort(tokensToUpdate, self.TokenDependencies) do
		local tok = self.Tokens[tokenName]
		tok.Sheet = fakeSheet :: any
		tok:evaluate()
		self.AppliedTokenChanged:Fire(tokenName, tok.AppliedValue)
	end

	updateRulesRecursive({self})
end

function RuleMethods:UpdateTokens()
	local fakeSheet = {
		AppliedTokens = self.AppliedTokens,
		TokenDependencies = self.TokenDependencies,
		Sheet = { SetAttribute = function() end },
	}
	for _, tokenName in topologicalSort(self.Tokens, self.TokenDependencies) do
		local tok = self.Tokens[tokenName]
		tok.Sheet = fakeSheet :: any
		tok:evaluate()
		self.AppliedTokenChanged:Fire(tokenName, tok.AppliedValue)
	end

	updateRulesRecursive({self})
end

function RuleMethods:SetProperty(k, v)
	local ctx = buildRuleTokenContext(self)
	local inner = unwrapValue(v)
	local evaluated = evalProperty(inner, ctx)

	if type(inner) == "table" and inner.__stylevar then
		self.PropertyDependencies[k] = getDependencies(inner.__expr)
	elseif type(inner) == "string" and inner:sub(1, 1) == "$" then
		self.PropertyDependencies[k] = {inner:sub(2)}
	else
		self.PropertyDependencies[k] = {}
	end

	self.Rule:SetProperty(k, evaluated)
	self.RawProperties[k] = v
	self.AppliedProperties[k] = evaluated
	self.PropertyChanged:Fire(k, v)
end

function RuleMethods:AddRules(rules)
	local sheet = self.Sheet
	for _, rule in rules do
		rule:init(sheet)
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

function RuleMethods:GetChild(name)
	for _, v in self.ChildRules do
		if v:GetName() == name then return v end
	end
	error(`Couldnt find child Rule '{name}' of Rule '{self:GetName()}'`)
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
	self.Sheet.SlctrToRule[self.Rule.Selector] = nil
	table.clear(self.RawProperties)
	table.clear(self.AppliedProperties)

	self.PropertyChanged:Destroy()
	self.AppliedPropertyChanged:Destroy()
	self.RuleAdded:Destroy()
	self.RuleRemoved:Destroy()
	self.TokenChanged:Destroy()
	self.AppliedTokenChanged:Destroy()
end

function RuleMethods:init(sheet)
	assert(not self.__initialized, `rule '{self:GetName()}' has already been initialized.`)
	self.__initialized = true
	self.Sheet = sheet

	sheet.SlctrToRule[self.Rule.Selector] = self

	local rule = self.Rule

	if not self.ParentRule then
		rule.Parent = sheet.Sheet
	else
		rule.Parent = self.ParentRule.Rule
	end

	local ctx = buildRuleTokenContext(self)
	local realProps = self.AppliedProperties
	local props = self.RawProperties
	for k, v in props do
		local inner = unwrapValue(v)
		local evaluated = evalProperty(inner, ctx)
		realProps[k] = evaluated
		if type(inner) == "table" and inner.__stylevar then
			self.PropertyDependencies[k] = getDependencies(inner.__expr)
		elseif type(inner) == "string" and inner:sub(1, 1) == "$" then
			self.PropertyDependencies[k] = {inner:sub(2)}
		else
			self.PropertyDependencies[k] = {}
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

	for _, childRule in rulesToInit do
		childRule:init(sheet)
	end
end

-- Style constructors ---------------------------------------------------------

function Style.var(expr: string): Expression
	return {
		__stylevar = true,
		__expr = expr
	}
end

function Style.token(value: any): StyleToken
	return setmetatable({
		__styletoken = true,
		__initialized = false,
		RawValue = value,
		AppliedValue = nil,
		Name = nil,
		Sheet = nil,
		Tags = {},
	} :: any, TokenMethods) :: StyleToken
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
	for i, v in ipairs(props :: any) do
		table.insert(arrayPart, i)
		table.insert(childrenRules, v)
	end
	for _, i in arrayPart do
		props[i] = nil
	end

	local realProps = {}
	local ruleTbl: Rule = setmetatable({
		Rule = rule,
		RawProperties = props,
		AppliedProperties = realProps,
		ChildRules = childrenRules,
		Tags = {},
		PropertyDependencies = {},

		Tokens = {},
		AppliedTokens = {},
		TokenDependencies = {},
		TokenChanged = SimpleSignal.new(),
		AppliedTokenChanged = SimpleSignal.new(),
		AppliedPropertyChanged = SimpleSignal.new(),
		PropertyChanged = SimpleSignal.new(),
		RuleAdded = SimpleSignal.new(),
		RuleRemoved = SimpleSignal.new()
	} :: Rule, RuleMethods) :: any

	local currentSlctr = rule.Selector
	rule:GetPropertyChangedSignal("Selector"):Connect(function()
		if ruleTbl.Sheet then
			ruleTbl.Sheet.SlctrToRule[currentSlctr] = nil
			ruleTbl.Sheet.SlctrToRule[rule.Selector] = ruleTbl
			currentSlctr = rule.Selector
		end
		rule.Name = RULE_NAME_FORMAT:format(rule.Selector)
	end)

	return ruleTbl
end

function Style.create(rules: {[any]: any}): Style
	local sheet = Instance.new("StyleSheet")

	local tokens = {}
	local style = setmetatable({
		Sheet = sheet,
		Tokens = tokens,
		Links = {},
		AppliedTokens = {},
		TokenDependencies = {},
		Rules = rules,

		RuleAdded = SimpleSignal.new(),
		RuleRemoved = SimpleSignal.new(),
		TokenChanged = SimpleSignal.new(),
		AppliedTokenChanged = SimpleSignal.new(),
		SlctrToRule = {}
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