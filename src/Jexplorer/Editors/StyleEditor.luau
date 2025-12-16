--!strict
--!optimize 2

local plugin = script:FindFirstAncestorOfClass("Plugin")

local StudioService = game:GetService('StudioService')

local main = script.Parent.Parent

local utilities = main.Utilities

local UITemplates = require(utilities.UITemplates)
local Types = require(main.Types)

local PluginUI = require(utilities.PluginUI)
local Style = require(utilities.Style)
local UDF = require(utilities.UDF)
local Selector = require(utilities.Small.Selector)
local InstanceUtility = require(utilities.Small.InstanceUtility)
local ItemGroup = require(utilities.Vendor.ItemGroup)
local cleanup = ItemGroup.cleanup

local getId = PluginUI.getId
local rule = Style.rule

local index = InstanceUtility.index
local newindex = InstanceUtility.newindex

local studioSettings = settings().Studio

local init = false
local StyleEditor = {} :: Types.StyleEditor

function StyleEditor.init(Manager)
	init = true
	local sheet = Manager.Style
	local state = Manager.WidgetState
	local components = Manager.Components
	
	local jexplorerUi = state.JExplorerUI
	local topbar = jexplorerUi.Topbar
	
	local connections = state.Connections
	local widget, mainframe = PluginUI.createEditorWidget(UITemplates.EditorFrame(), "StyleEditor", "Style Editor")
	StyleEditor.Widget = widget
	sheet:Link(widget)
	
	local currentResetTarget: {
		box: TextBox,
		inst: any,
		name: string,
		defaultValue: any,
		type: "ruleProperty" | "styledProperty" | "token"
	}?
	local stylePropertyResetMenu do
		stylePropertyResetMenu = plugin:CreatePluginMenu(
			getId("Jexplorer_StylePropertyResetMenu", true)
		)

		local reset = stylePropertyResetMenu:AddNewAction(
			getId("Jexplorer_ContextMenu_StylePropertyResetToDefault", true), "Reset to Default"
		) :: PluginAction
		reset.Triggered:Connect(function()
			if not currentResetTarget then return end
			if currentResetTarget.type == "styledProperty" then
				currentResetTarget.box.Text = UDF.to(currentResetTarget.defaultValue)
				currentResetTarget.inst:SetProperty(currentResetTarget.name, currentResetTarget.defaultValue)
			elseif currentResetTarget.type == "ruleProperty" then
				currentResetTarget.box.Text = UDF.to(currentResetTarget.defaultValue)
				newindex(
					currentResetTarget.inst,
					currentResetTarget.name,
					currentResetTarget.defaultValue
				)
			elseif currentResetTarget.type == "token" then
				currentResetTarget.box.Text = UDF.to(currentResetTarget.defaultValue)
				currentResetTarget.inst:SetToken(currentResetTarget.name, currentResetTarget.defaultValue, true)
			end
			currentResetTarget = nil
		end)
	end

	--local warningHeader = PluginUI.createHeader(nil, "WARNING: Styles are currently not saved")
	--warningHeader.Parent = mainframe.Items

	local rulesDropdown = PluginUI.createDropDownItemList(nil, "StyleRules")
	local tokensDropdown = PluginUI.createDropDownItemList(nil, "Tokens")
	rulesDropdown.Backdrop.Visible = true
	tokensDropdown.Backdrop.Visible = true

	-- WARNING: YOU HAVE TO PASS A RULE IF K IS "Image" OR "Texture"
	local function createStylePropertyBox(dropdown: any, k: string, defaultValue: any, callback: ((string) -> ())?, rule: Style.Rule?)
		local defaultStr = UDF.to(defaultValue)
		local box
		box = PluginUI.createAttributeBox(dropdown, k, defaultStr, callback or function(newValue)
			assert(rule, "unexpected error: style rule not found while creating style property box")
			if newValue == defaultStr then 
				rule:SetProperty(k, defaultValue)
				return 
			end
			--if newValue == "" then
			--	rule:SetProperty(k, defaultValue)
			--	box.ValueBox.Text = defaultStr
			--	return
			--end
			local value = UDF.from(newValue)
			rule:SetProperty(k, value)
		end)
		
		if k == "Image" or k == "Texture" then
			local importFromFileButton = PluginUI.createSideButtonImage("rbxassetid://13544220123", Vector2.zero, Vector2.zero, box.Instance.ValueBox)
			importFromFileButton:AddTag("JEXP_MonochromeImage")
			importFromFileButton.BackgroundTransparency = 1
			
			importFromFileButton.Activated:Connect(function()
				local file = StudioService:PromptImportFile({"png", "jpg", "jpeg"}) :: File?
				if not file then return end
				assert(rule)
				
				box:Set(file:GetTemporaryId())
				rule:SetProperty(k, box:Get())
			end)
		end
		
		if rule then
			local conn = rule.PropertyChanged:Connect(function(name, newValue)
				if name ~= k then return end
				box:Set(UDF.to(newValue))
			end);
			(box.Instance :: GuiObject).InputBegan:Connect(function(input: InputObject)
				if input.UserInputState ~= Enum.UserInputState.Begin then return end
				if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end
				currentResetTarget = {
					box = box.Instance.ValueBox,
					inst = rule,
					name = k,
					defaultValue = defaultValue,
					type = "styledProperty"
				}
				stylePropertyResetMenu:ShowAsync()
			end)
			local button = PluginUI.createDeleteButton(box.Instance, function()
				rule:SetProperty(k, nil)
				conn:Disconnect()
				box:Destroy()
			end)
			button.AnchorPoint = Vector2.new(1, 0)
			button.Position = UDim2.fromScale(1, 0)
		end
		
		return box
	end
	
	local currentCreatingRule: Style.Rule?, creatingDropdown: any?
	local createStylePropertyItemList do
		createStylePropertyItemList = PluginUI.createItemList {
			Name = "StyleRuleItemList"
		}
		
		local nameBox = PluginUI.createAttributeBox(createStylePropertyItemList, "Name")
		local defaultValueBox = PluginUI.createAttributeBox(createStylePropertyItemList, "Default Value")
		PluginUI.createButton(createStylePropertyItemList, "Create", function()
			createStylePropertyItemList:Hide()
			if not currentCreatingRule then return end
			local name = nameBox:Get()
			local defaultValue = UDF.from(defaultValueBox:Get())
			
			if not defaultValue then return end

			currentCreatingRule:SetProperty(name, defaultValue)
			createStylePropertyBox(creatingDropdown, name, defaultValue, nil, currentCreatingRule)
			currentCreatingRule = nil
		end)

		createStylePropertyItemList.Backdrop.MouseLeave:Connect(function()
			createStylePropertyItemList:Hide()
		end)
		createStylePropertyItemList.Backdrop.Parent = topbar
	end
	
	local createNestedStyleRuleList do
		createNestedStyleRuleList = PluginUI.createItemList {
			Name = "CreateNestedStyleRuleItemList"
		}
		
		local selectorBox = PluginUI.createAttributeBox(createNestedStyleRuleList, "Selector")
		local priorityBox = PluginUI.createAttributeBox(createNestedStyleRuleList, "Priority")
		PluginUI.createButton(createNestedStyleRuleList, "Create", function()
			createNestedStyleRuleList:Hide()
			if not currentCreatingRule or not creatingDropdown then return end
			
			local selector = selectorBox:Get()
			local priority = tonumber(priorityBox:Get())
			assert(priority, "stylerule priority must be a number")

			local defaultProperties = {}
			-- Macro
			local newSelector, macroType = Selector.parseSelectorMacro(selector)
			if newSelector then selector = newSelector end
			if macroType == "icon" then
				-- WARNING: THE PRESENCE OF IMAGERECTOFFSET AND IMAGERECTSIZE IS VERY IMPORTANT TO ENSURE THIS STYLE GETS APPLIED, IDK WHY IT DOESNT WORK OTHERWISE
				defaultProperties = {
					Image = "",
					ImageRectOffset = Vector2.zero,
					ImageRectSize = Vector2.zero
				}
			end
			
			local styleRule = rule("CustomStyle", selector, priority, defaultProperties)
			
			currentCreatingRule:AddRules({styleRule})
			-- Handled in ParentRule.RuleAdded
			--dropdown:Parent(creatingDropdown)
		end)
		
		createNestedStyleRuleList.Backdrop.MouseLeave:Connect(function()
			createNestedStyleRuleList:Hide()
		end)
		createNestedStyleRuleList.Backdrop.Parent = topbar
	end
	
	local function createStyleRuleDropdown(rule: Style.Rule)
		if rule:GetName() == nil then
			rule:SetName("StyleRule")
		end
		local dropdown = PluginUI.createDropDownItemList(nil, rule:GetName(), true)
		dropdown.Backdrop.Visible = true
		dropdown.Backdrop.DropDownHeader.HeaderLabel.FocusLost:Connect(function(enterPressed)
			if not enterPressed then return end
			rule:SetName(dropdown.Backdrop.DropDownHeader.HeaderLabel.Text)
		end)

		local defaultSelector = rule.Rule.Selector
		local defaultPriority = rule.Rule.Priority
		local box
		box = createStylePropertyBox(dropdown, "StyleRule.Selector", defaultSelector, function(newValue)
			local newSelector, macroType = Selector.parseSelectorMacro(UDF.from(newValue))
			if newSelector then
				box:Set(UDF.to(newSelector))
				rule.Rule.Selector = newSelector
			else
				rule.Rule.Selector = newValue
			end
		end)
		box.Instance.ValueBox.InputBegan:Connect(function(input: InputObject)
			if input.UserInputState ~= Enum.UserInputState.Begin then return end
			if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end
			currentResetTarget = {
				box = box.Instance.ValueBox,
				inst = rule,
				name = "Selector",
				defaultValue = defaultSelector,
				type = "ruleProperty"
			}
			stylePropertyResetMenu:ShowAsync()
		end)
		local box
		box = createStylePropertyBox(dropdown, "StyleRule.Priority", defaultPriority, function(newValue)
			--if newValue == "" then
			--	rule.Priority = defaultPriority
			--	box.ValueBox.Text = UDF.to(defaultPriority)
			--	return
			--end
			local newValue = UDF.from(newValue)
			assert(type(newValue) == "number", "number expected for stylerule.priority")
			rule.Rule.Priority = newValue
		end)
		box.Instance.ValueBox.InputBegan:Connect(function(input: InputObject)
			if input.UserInputState ~= Enum.UserInputState.Begin then return end
			if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end
			currentResetTarget = {
				box = box.Instance.ValueBox,
				inst = rule,
				name = "Priority",
				defaultValue = defaultPriority,
				type = "ruleProperty"
			}
			stylePropertyResetMenu:ShowAsync()
		end)
		
		for k, v in rule.RawProperties do
			local defaultValue = v
			createStylePropertyBox(dropdown, k, defaultValue, nil, rule)
		end
		for _, childRule in rule.ChildRules do
			local childDropdown = createStyleRuleDropdown(childRule)
			childDropdown:Parent(dropdown)
		end
		rulesDropdown:AddItem(dropdown.Backdrop)
		local header = dropdown.Backdrop:FindFirstChild("DropDownHeader")
		
		PluginUI.createInsertButton(header, function()
			currentCreatingRule = rule
			creatingDropdown = dropdown
			createStylePropertyItemList:Show()
		end)
		
		local createRulePos = UDim2.fromScale(0.85, 0.5)
		if not rule:HasTag("Default") then
			PluginUI.createDeleteButton(header, function()
				rule:Destroy()
				dropdown:Destroy()
			end)
			createRulePos = UDim2.fromScale(0.8, 0.5)
		end
		local createRule = PluginUI.createInsertButtonWithImage(header, "rbxassetid://85474028895485", function()
			currentCreatingRule = rule
			creatingDropdown = dropdown
			createNestedStyleRuleList:Show()
		end)
		createRule.Position = createRulePos
		
		rule.Rule.Destroying:Connect(function()
			dropdown:Destroy()
		end)
		rule.RuleAdded:Connect(function(childRule)
			local childDropdown = createStyleRuleDropdown(childRule)
			childDropdown:Parent(dropdown)
		end)
		return dropdown
	end
	
	local createStyleRuleItemList do
		createStyleRuleItemList = PluginUI.createItemList {
			Name = "CreateStyleRuleItemList"
		}

		local selectorBox = PluginUI.createAttributeBox(createStyleRuleItemList, "Selector")
		local priorityBox = PluginUI.createAttributeBox(createStyleRuleItemList, "Priority")
		PluginUI.createButton(createStyleRuleItemList, "Create", function()
			createStyleRuleItemList:Hide()
			local selector = selectorBox:Get()
			local priority = tonumber(priorityBox:Get())
			assert(priority, "stylerule priority must be a number")

			local defaultProperties = {}
			-- Macro
			local newSelector, macroType = Selector.parseSelectorMacro(selector)
			if newSelector then selector = newSelector end
			if macroType == "icon" then
				-- WARNING: THE PRESENCE OF IMAGERECTOFFSET AND IMAGERECTSIZE IS VERY IMPORTANT TO ENSURE THIS STYLE GETS APPLIED, IDK WHY IT DOESNT WORK OTHERWISE
				defaultProperties = {
					Image = "",
					ImageRectOffset = Vector2.zero,
					ImageRectSize = Vector2.zero
				}
			end

			local styleRule = rule("CustomStyle", selector, priority, defaultProperties)
			sheet:AddRules {styleRule}
			
			-- Handled in the .RuleAdded connection
			--createStyleRuleDropdown(styleRule)
		end)
		
		createStyleRuleItemList.Backdrop.MouseLeave:Connect(function()
			createStyleRuleItemList:Hide()
		end)
		createStyleRuleItemList.Backdrop.Parent = topbar
	end

	local function createTokenAttribute(k: string, defaultValue: any, defaultStr: string)
		local box
		box = PluginUI.createAttributeBox(tokensDropdown, k, defaultStr, function(newValue)
			if newValue == defaultStr then 
				sheet:SetToken(k, defaultValue, true)
				return
			end
			--if newValue == "" then
			--	sheet:SetToken(k, defaultValue)
			--	box.ValueBox.Text = defaultStr
			--	return
			--end
			local value = UDF.from(newValue)
			if not value then
				box:Set(defaultStr)
				return
			end
			sheet:SetToken(k, value, true)
		end)
		
		local conn = sheet.TokenChanged:Connect(function(name, newValue)
			if name ~= k then return end
			box:Set(UDF.to(newValue))
		end)
		box.Instance.ValueBox.InputBegan:Connect(function(input: InputObject)
			if input.UserInputState ~= Enum.UserInputState.Begin then return end
			if input.UserInputType ~= Enum.UserInputType.MouseButton2 then return end
			currentResetTarget = {
				box = box.Instance.ValueBox,
				inst = sheet,
				name = k,
				defaultValue = defaultValue,
				type = "token"
			}
			stylePropertyResetMenu:ShowAsync()
		end)

		--if not JState.DefaultTokens[k] then
		--	local button = PluginUI.createDeleteButton(box.Instance, function()
		--		sheet:SetToken(k, nil, true)
		--		conn:Disconnect()
		--		box:Destroy()
		--	end)
		--	button.AnchorPoint = Vector2.new(1, 0)
		--	button.Position = UDim2.fromScale(1, 0)
		--end
	end

	local createTokenItemList do
		createTokenItemList = PluginUI.createItemList {
			Name = "CreateTokenItemList"
		}

		local nameBox = PluginUI.createAttributeBox(createTokenItemList, "Name")
		local defaultValueBox = PluginUI.createAttributeBox(createTokenItemList, "Default Value")
		PluginUI.createButton(createTokenItemList, "Create", function()
			createTokenItemList:Hide()
			local name = nameBox:Get()
			local defaultStr = defaultValueBox:Get()
			local defaultValue = UDF.from(defaultStr)
			sheet:SetToken(name, defaultValue, true)

			createTokenAttribute(name, defaultValue, defaultStr)
		end)
		
		createTokenItemList.Backdrop.MouseLeave:Connect(function()
			createTokenItemList:Hide()
		end)
		createTokenItemList.Backdrop.Parent = topbar
	end
	
	task.spawn(function()
		task.wait(2)
		for k, v in sheet.Tokens do
			local defaultValue = v
			local defaultStr = UDF.to(v)

			createTokenAttribute(k, defaultValue, defaultStr)
			task.wait(0.5)
		end
	end)
	
	task.spawn(function()
		task.wait(2)
		for _, rule in sheet.Rules do
			createStyleRuleDropdown(rule)
			task.wait(0.5)
		end
	end)
	
	local rulesHeader = rulesDropdown.Backdrop:FindFirstChild("DropDownHeader")

	PluginUI.createInsertButton(rulesHeader, function()
		createStyleRuleItemList:Show()
	end)
	
	local tokensHeader = tokensDropdown.Backdrop:FindFirstChild("DropDownHeader")
	
	PluginUI.createInsertButton(tokensHeader, function()
		createTokenItemList:Show()
	end)

	rulesDropdown.Backdrop.Parent = mainframe.Items
	tokensDropdown.Backdrop.Parent = mainframe.Items
	
	connections:add_many({
		sheet.RuleAdded:Connect(function(newRule)
			createStyleRuleDropdown(newRule)
		end) :: any,
	})
	
	local instances = connections:extend(cleanup.destroy)
	
	instances:add(stylePropertyResetMenu)
end

return StyleEditor