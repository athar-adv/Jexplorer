--!strict
--!optimize 2

local plugin = script:FindFirstAncestorOfClass("Plugin")

local StudioService = game:GetService('StudioService')

local main = script.Parent.Parent

local shared = main.Shared

local UITemplates = require(shared.UITemplates)
local Types = require(main.Types)

local PluginUI = require(shared.PluginUI)
local Style = require(shared.Style)
local UDF = require(shared.UDF)
local Selector = require(shared.Small.Selector)
local RawInst = require(shared.Small.RawInst)
local ItemGroup = require(shared.Vendor.ItemGroup)
local xyz = require(shared.Small.xyz)
local cleanup = ItemGroup.cleanup

local getId = PluginUI.getId
local rule = Style.rule

local ColorPicker = require(shared.Vendor.PluginColorPicker)

local index = RawInst.index
local newindex = RawInst.newindex

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
	
	local function resolve(v: any): Color3
		if typeof(v) == "Color3" then
			return v
		elseif typeof(v) == "string" then
			return Style.eval(v, sheet.Tokens)
		elseif typeof(v) == "table" and v.__stylevar then
			return Style.eval(v.__expr, sheet.Tokens)
		else
			error(`'{v}' cannot be converted into Color3`)
		end
	end
	
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
	--warningHeader.Parent = mainframe.Items.Content

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
			local value = UDF.from(newValue)
			rule:SetProperty(k, value)
		end)
		
		local conn2
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
		elseif k == "BackgroundColor3" or k == "TextColor3" or k == "ImageColor3" or k == "Color" or k == "PlaceholderTextColor3" then
			local chooseColorButton = PluginUI.createSideButtonImage("", Vector2.zero, Vector2.zero, box.Instance.ValueBox)
			chooseColorButton:AddTag("JEXP_Border")
			chooseColorButton.BackgroundColor3 = resolve(defaultValue)

			local function colorChanged(newColor: Color3)
				assert(rule)
				
				rule:SetProperty(k, newColor)
				box.Instance.ValueBox.Text = UDF.to(newColor)
				chooseColorButton.BackgroundColor3 = newColor
			end
			
			local last
			chooseColorButton.Activated:Connect(function()
				assert(rule)
				if last then
					last:Close()
					last:Destroy()
				end
				local picker = ColorPicker.new(plugin, getId("StyleColorPicker", true))
				last = picker
				
				picker:Show()
				local originalColor = resolve(rule:GetProperty(k))
				picker:Set(originalColor)

				picker:BindToChange(colorChanged)
				picker:BindToCancel(function()
					colorChanged(originalColor)
					picker:Close()
					picker:Destroy()
				end)
				picker:BindToConfirm(function()
					picker:Close()
					picker:Destroy()
				end)
			end)
			
			if rule then
				conn2 = rule.AppliedPropertyChanged:Connect(function(name, v)
					if name ~= k then return end
					chooseColorButton.BackgroundColor3 = resolve(v)
				end)
			end
		end
		
		if rule then
			local conn = rule.PropertyChanged:Connect(function(name, newValue)
				if name ~= k then return end
				box.Instance.ValueBox.Text = UDF.to(newValue)
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
				if conn2 then
					conn2:Disconnect()
				end
				box:Destroy()
			end)
			button.AnchorPoint = Vector2.new(1, 0)
			button.Position = UDim2.fromScale(1, 0)
		end
		
		return box
	end
	
	local currentCreatingRule: Style.Rule?, creatingDropdown: any?
	local function showCreateStylePropertyMenu()
		local nameBox = PluginUI.createAttributeBox(nil, "Name", "")
		local defaultValueBox = PluginUI.createAttributeBox(nil, "Default Value", "")
		
		local widget, cancel, confirm, close = PluginUI.createCreatorWidget("Create Style Property", {
			nameBox,
			defaultValueBox
		})
		Manager.Style:Link(widget)
		
		cancel:OnTrigger(function()
			close()
		end)
		confirm:OnTrigger(function()
			if not currentCreatingRule then
				close()
				return
			end
			local name = nameBox:Get()
			local defaultValue = UDF.from(defaultValueBox:Get())

			if not defaultValue then return end

			currentCreatingRule:SetProperty(name, defaultValue)
			createStylePropertyBox(creatingDropdown, name, defaultValue, nil, currentCreatingRule)
			currentCreatingRule = nil
			
			close()
		end)
	end
	
	local function showCreateNestedStyleRuleMenu()
		local selectorBox = PluginUI.createAttributeBox(nil, "Selector", "")
		local priorityBox = PluginUI.createAttributeBox(nil, "Priority", "1")
		
		local widget, cancel, confirm, close = PluginUI.createCreatorWidget("Create Child Style Rule", {
			selectorBox,
			priorityBox
		})
		Manager.Style:Link(widget)
		
		cancel:OnTrigger(function()
			close()
		end)
		confirm:OnTrigger(function()
			if not currentCreatingRule or not creatingDropdown then
				close()
				return
			end

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

			close()
		end)
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
				box.Instance.ValueBox.Text = UDF.to(newSelector)
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
			showCreateStylePropertyMenu()
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
			showCreateNestedStyleRuleMenu()
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
	
	local function showCreateTopStyleRuleMenu()
		local selectorBox = PluginUI.createAttributeBox(nil, "Selector", "")
		local priorityBox = PluginUI.createAttributeBox(nil, "Priority", "1")

		local widget, cancel, confirm, close = PluginUI.createCreatorWidget("Create Style Rule", {
			selectorBox,
			priorityBox
		})
		Manager.Style:Link(widget)
		
		cancel:OnTrigger(function()
			close()
		end)
		confirm:OnTrigger(function()
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
			
			close()
		end)
	end
	
	local function createTokenAttribute(k: string, defaultValue: any, defaultStr: string)
		local box
		box = PluginUI.createAttributeBox(tokensDropdown, k, defaultStr, function(newValue)
			if newValue == defaultStr then 
				sheet:SetToken(k, defaultValue, true)
				return
			end
			local value = UDF.from(newValue)
			if not value then
				box.Instance.ValueBox.Text = defaultStr
				return
			end
			sheet:SetToken(k, value, true)
		end)
		
		local conn = sheet.TokenChanged:Connect(function(name, newValue)
			if name ~= k then return end
			box.Instance.ValueBox.Text = UDF.to(newValue)
		end)
		local conn2
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

		local button = PluginUI.createDeleteButton(box.Instance, function()
			sheet:SetToken(k, nil, true)
			conn:Disconnect()
			if conn2 then
				conn2:Disconnect()
			end
			box:Destroy()
		end)
		button.AnchorPoint = Vector2.new(1, 0)
		button.Position = UDim2.fromScale(1, 0)
		
		local function iscolor(v: any): boolean
			local success, result = pcall(resolve, v)
			return success and typeof(result) == "Color3"
		end
		if iscolor(defaultValue) then
			local chooseColorButton = PluginUI.createSideButtonImage("", Vector2.zero, Vector2.zero, box.Instance.ValueBox)
			chooseColorButton:AddTag("JEXP_Border")
			chooseColorButton.BackgroundColor3 = resolve(defaultValue)

			local function colorChanged(newColor: Color3)
				assert(rule)

				sheet:SetToken(k, newColor, true)
				box.Instance.ValueBox.Text = UDF.to(newColor)
				chooseColorButton.BackgroundColor3 = newColor
			end
			
			local last
			chooseColorButton.Activated:Connect(function()
				assert(rule)
				if last then
					last:Close()
					last:Destroy()
				end
				local picker = ColorPicker.new(plugin, getId("StyleColorPicker", true))
				last = picker
				
				picker:Show()
				local originalColor = resolve(sheet:GetToken(k))
				picker:Set(originalColor)

				picker:BindToChange(colorChanged)
				picker:BindToCancel(function()
					colorChanged(originalColor)
					picker:Close()
					picker:Destroy()
				end)
				picker:BindToConfirm(function()
					picker:Close()
					picker:Destroy()
				end)
			end)
			
			conn2 = sheet.AppliedTokenChanged:Connect(function(name, v)
				if name ~= k then return end
				chooseColorButton.BackgroundColor3 = resolve(v)
			end)
		end
	end
	
	local function showCreateTokenMenu()
		local nameBox = PluginUI.createAttributeBox(nil, "Name", "")
		local defaultValueBox = PluginUI.createAttributeBox(nil, "Default Value", "")

		local widget, cancel, confirm, close = PluginUI.createCreatorWidget("Create Token", {
			nameBox,
			defaultValueBox
		})
		Manager.Style:Link(widget)
		
		cancel:OnTrigger(function()
			close()
		end)
		confirm:OnTrigger(function()
			local name = nameBox:Get()
			local defaultStr = defaultValueBox:Get()
			local defaultValue = UDF.from(defaultStr)
			sheet:SetToken(name, defaultValue, true)

			createTokenAttribute(name, defaultValue, defaultStr)

			close()
		end)
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
		showCreateTopStyleRuleMenu()
	end)
	
	local tokensHeader = tokensDropdown.Backdrop:FindFirstChild("DropDownHeader")
	
	PluginUI.createInsertButton(tokensHeader, function()
		showCreateTokenMenu()
	end)

	rulesDropdown.Backdrop.Parent = mainframe.Items.Content
	tokensDropdown.Backdrop.Parent = mainframe.Items.Content
	
	connections:add_many({
		sheet.RuleAdded:Connect(function(newRule)
			createStyleRuleDropdown(newRule)
		end) :: any,
	})
	
	local instances = connections:extend(cleanup.destroy)
	
	instances:add(stylePropertyResetMenu)
end

return StyleEditor