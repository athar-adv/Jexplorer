--!strict
--!optimize 2

local eval = require(script.ExprEvaluator)
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
	
	Links: {StyleLink},
	Rules: {Rule},
	
	Link: (Style, gui: Instance) -> StyleLink,
	
	SetToken: (Style, name: string, value: any, autoUpdate: boolean) -> (),
	GetToken: (Style, name: string) -> any,
	UpdateTokens: (Style) -> (),
	
	AddRules: (Style, rules: {[any]: any}) -> (),
	FindRule: (Style, selector: string) -> StyleRule?,
	Replace: (Style, newStyle: Style) -> (),
	
	RuleAdded: SimpleSignal.SimpleSignal<Rule>,
	RuleRemoved: SimpleSignal.SimpleSignal<Rule>,
	TokenChanged: SimpleSignal.SimpleSignal<string, any>,
}

export type Rule = {
	Rule: StyleRule,
	Sheet: Style,
	ChildRules: {Rule},
	ParentRule: Rule?,
	Tags: {[string]: boolean},
	
	AddTag: (Rule, string) -> (),
	HasTag: (Rule, string) -> boolean,
	RemoveTag: (Rule, string) -> (),
	
	RawProperties: {[string]: any},
	AppliedProperties: {[string]: any},
	
	AddRules: (Rule, rules: {Rule}) -> (),
	SetProperty: (Rule, k: string, value: any) -> (),
	GetProperty: (Rule, k: string) -> any,
	GetName: (Rule) -> string,
	SetName: (Rule, name: string) -> (),
	Destroy: (Rule) -> (),
	
	PropertyChanged: SimpleSignal.SimpleSignal<string, any>,
	RuleAdded: SimpleSignal.SimpleSignal<Rule>,
	RuleRemoved: SimpleSignal.SimpleSignal<Rule>,
	
	init: (Rule, sheet: Style) -> (),
	__initialized: boolean
}

local RULE_NAME_FORMAT = "%s"

local Style = {
	eval = eval
}

local function filterRules(style: Style, rules: {[string | number]: any}, tokens: {[string]: any})
	local sheet = style.Sheet
	local queuedTokens = {}
	
	for k, v in rules do
		if type(k) == "number" then continue end
		if type(v) == "table" and v.__stylevar then
			table.insert(queuedTokens, function()
				local evaluated = eval(v.__expr, tokens)
				sheet:SetAttribute(k, evaluated)
			end)
		else
			pcall(sheet.SetAttribute, sheet, k, v)
		end
		tokens[k] = v
		rules[k] = nil
	end
	for _, f in queuedTokens do f() end
	
	local appliedTokens = sheet:GetAttributes()
	for _, rule in rules do
		for k, v in rule.RawProperties do
			if type(v) == "table" and v.__stylevar then
				local evaluated = eval(v.__expr, appliedTokens)
				rule.AppliedProperties[k] = evaluated
			else
				rule.AppliedProperties[k] = v
			end
		end
	end
	
	for k, rule in rules do
		rule:init(style)
		
		for _, v in rule.AppliedProperties do
			if type(v) ~= "string" then continue end
			if v:sub(1, 1) ~= "$" then continue end
			local tokenName = v:sub(2)
			if sheet:GetAttribute(tokenName) == nil then
				error(`token '${tokenName}' not found (selector '{rule.Selector}')`)
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

function StyleMethods:SetToken(name: string, value: any, autoUpdate: boolean)
	local sheet = self.Sheet
	local appliedTokens = sheet:GetAttributes()

	self.Tokens[name] = value
	if type(value) == "table" and value.__stylevar then
		local evaluated = eval(value.__expr, appliedTokens)
		sheet:SetAttribute(name, evaluated)
		appliedTokens[name] = evaluated
	else
		pcall(sheet.SetAttribute, sheet, name, value)
		appliedTokens[name] = value
	end

	self.AppliedTokens = appliedTokens
	if autoUpdate then
		self:UpdateTokens()
	end
	self.TokenChanged:Fire(name, value)
end

function StyleMethods:UpdateTokens()
	local sheet = self.Sheet
	local appliedTokens = sheet:GetAttributes()
	
	for k, v in self.Tokens do
		if type(v) == "table" and v.__stylevar then
			local evaluated = eval(v.__expr, appliedTokens)
			sheet:SetAttribute(k, evaluated)
			appliedTokens[k] = evaluated
		else
			pcall(sheet.SetAttribute, sheet, k, v)
			appliedTokens[k] = v
		end
	end
	
	local function updateRulesRecursive(rules: {Rule})
		for _, ruleTbl in rules do
			local changed = false
			for k, v in ruleTbl.RawProperties do
				if type(v) == "table" and v.__stylevar then
					local evaluated = eval(v.__expr, appliedTokens)
					ruleTbl.Rule:SetProperty(k, evaluated)
					ruleTbl.AppliedProperties[k] = evaluated
					changed = true
				else
					ruleTbl.Rule:SetProperty(k, v)
					ruleTbl.AppliedProperties[k] = v
					changed = true
				end
			end
			if #ruleTbl.ChildRules == 0 then continue end
			updateRulesRecursive(ruleTbl.ChildRules)
		end
	end
	updateRulesRecursive(self.Rules)
	self.AppliedTokens = appliedTokens
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

function RuleMethods:SetProperty(k, v)
	local realProps = self.AppliedProperties
	local props = self.RawProperties
	local rule = self.Rule
	
	if type(v) == "table" and v.__stylevar then
		local evaluated = eval(v.__expr, self.Sheet.Sheet:GetAttributes())
		realProps[k] = evaluated
	else
		realProps[k] = v
	end
	rule:SetProperty(k, realProps[k])
	props[k] = v
	self.PropertyChanged:Fire(k, v)
end

function RuleMethods:AddRules(rules)
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
			local evaluated = eval(v.__expr, self.Sheet.Sheet:GetAttributes())
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
	
	local appliedTokens = sheet.Sheet:GetAttributes()
	for _, rule in rulesToInit do
		for k, v in rule.RawProperties do
			if type(v) == "table" and v.__stylevar then
				local evaluated = eval(v.__expr, appliedTokens)
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
		
		PropertyChanged = SimpleSignal.new(),
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
		AppliedTokens = sheet:GetAttributes(),
		Rules = rules,

		RuleAdded = SimpleSignal.new(),
		RuleRemoved = SimpleSignal.new(),
		TokenChanged = SimpleSignal.new(),
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