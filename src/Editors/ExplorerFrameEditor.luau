--!strict
--!optimize 2

local plugin = script:FindFirstAncestorOfClass("Plugin")

local main = script.Parent.Parent

local shared = main.Shared

local PluginUI = require(shared.PluginUI)
local UITemplates = require(shared.UITemplates)
local ItemGroup = require(shared.Vendor.ItemGroup)
local Style = require(shared.Style)
local ColorPicker = require(shared.Vendor.PluginColorPicker)
local UDF = require(shared.UDF)
local ToStringUtils = require(shared.Small.ToStringUtils)
local Constants = require(main.Constants)
local cleanup = ItemGroup.cleanup
local var = Style.var

local Types = require(main.Types)

local ExplorerFrameEditor = {} :: Types.ExplorerFrameEditor

local function parseSelector(input: string): string
	local input = input:match("^%s*(.-)%s*$")
	assert(input)

	-- [tag] TAG -> .JEXP_TAG_TagName
	local tag = input:match("^%[tag%]%s+(.+)$")
	if tag then
		return ".JEXP_TAG_" .. tag
	end

	-- [name] NAME -> .JEXP_TAGGED_Name_NameValue
	local name = input:match("^%[name%]%s+(.+)$")
	if name then
		return ".JEXP_TAGGED_Name_" .. name
	end

	-- [class] CLASS -> #f_ClassName
	local class = input:match("^%[class%]%s+(.+)$")
	if class then
		return "#f_" .. class
	end

	-- [script] SCRIPT_TYPE -> #s_ScriptType
	local script = input:match("^%[script%]%s+(.+)$")
	if script then
		return "#s_" .. script
	end
	return input
end

local function unparseSelector(parsed: string)
	-- .JEXP_TAG_TagName -> [tag] TagName
	local tag = parsed:match("^%.JEXP_TAG_(.+)$")
	if tag then
		return "[tag] " .. tag
	end

	-- .JEXP_TAGGED_Name_NameValue -> [name] NameValue
	local name = parsed:match("^%.JEXP_TAGGED_Name_(.+)$")
	if name then
		return "[name] " .. name
	end

	-- #f_ClassName -> [class] ClassName
	local class = parsed:match("^#f_(.+)$")
	if class then
		return "[class] " .. class
	end

	-- #s_ScriptType -> [script] ScriptType
	local script = parsed:match("^#s_(.+)$")
	if script then
		return "[script] " .. script
	end

	-- Return raw input if no pattern matches
	return parsed
end

function ExplorerFrameEditor.init(Manager)
	local state = Manager.WidgetState
	local components = Manager.Components

	local jexplorerUi = state.JExplorerUI
	local topbar = jexplorerUi.Topbar
	
	local world = state.World
	
	local connections = state.Connections
	local instances = connections:extend(cleanup.destroy)

	local widget, mainframe = PluginUI.createEditorWidget(UITemplates.EditorFrame(), "ExplorerFrameEditor", "ExplorerFrame Editor")
	ExplorerFrameEditor.Widget = widget
	Manager.Style:Link(widget)
	
	local list = PluginUI.createItemListFromExisting(mainframe, mainframe.Items.Content, mainframe.Items)
	local editorDropdown = PluginUI.createDropDownItemList({
		Visible = true,
		Name = "EditorDropdown"
	})
	editorDropdown:Parent(list)
	editorDropdown:SetText("ExplorerFrame Configs")
	
	PluginUI.createHeader(editorDropdown, "FrameTypeSelector: [tag] TAG STRING or [name] NAME STRING or [class] CLASS STRING")
	
	local function createExplorerFrameConfig(rule: Style.Rule)
		local explorerFrameConfigHeader = PluginUI.createDropDownItemList({
			Visible = true,
		}, nil, true)
		explorerFrameConfigHeader:Parent(editorDropdown)
		explorerFrameConfigHeader:SetText(rule:GetName())
		
		local headerLabel = explorerFrameConfigHeader.Backdrop.DropDownHeader.HeaderLabel
		headerLabel.FocusLost:Connect(function(enterPressed)
			if not enterPressed then return end
			rule:SetName(headerLabel.Text)
		end)
		
		PluginUI.createDeleteButton(explorerFrameConfigHeader.Backdrop:WaitForChild("DropDownHeader"), function()
			explorerFrameConfigHeader:Destroy()
			rule:Destroy()
		end)

		local selectorList = PluginUI.createDropDownItemList({
			Visible = true
		}, "Selectors")
		selectorList:Parent(explorerFrameConfigHeader)

		local selectorGroups: {{selectors: {{selector: string}}}} = {}

		local function onSelectorChanged()
			local groupStrings = {}
			for _, group in selectorGroups do
				local parts = {}
				for _, s in group.selectors do
					if #s.selector > 0 then
						table.insert(parts, s.selector)
					end
				end
				if #parts > 0 then
					table.insert(groupStrings, table.concat(parts, " "))
				end
			end
			rule.Rule.Selector = table.concat(groupStrings, ",")
		end

		local function createSelectorBox(groupDropdown, group, obj, unparsed)
			local box = PluginUI.createAttributeBox(groupDropdown, "Selector", unparsed or "", function(newSelector)
				obj.selector = parseSelector(newSelector)
				onSelectorChanged()
			end)
			local del = PluginUI.createDeleteButton(box.Instance, function()
				local idx = table.find(group.selectors, obj)
				if idx then table.remove(group.selectors, idx) end
				onSelectorChanged()
			end)
			del.ZIndex = 1000
			return box
		end

		local function createSelectorGroup(existingSelectors: {{selector: string}}?)
			local group = {selectors = existingSelectors or {} :: {{selector: string}}}
			table.insert(selectorGroups, group)

			local groupDropdown = PluginUI.createDropDownItemList({
				Visible = true
			}, "SelectorGroup")
			groupDropdown:Parent(selectorList)

			local groupHeader = groupDropdown.Backdrop:WaitForChild("DropDownHeader")

			-- Insert button to add selectors within this group
			local ins = PluginUI.createInsertButton(groupHeader, function()
				local obj = {selector = ""}
				table.insert(group.selectors, obj)
				createSelectorBox(groupDropdown, group, obj, "")
				onSelectorChanged()
			end)
			ins.ZIndex = 1000

			-- Delete button to remove this entire group
			local del = PluginUI.createDeleteButton(groupHeader, function()
				local idx = table.find(selectorGroups, group)
				if idx then table.remove(selectorGroups, idx) end
				groupDropdown:Destroy()
				onSelectorChanged()
			end)
			del.ZIndex = 1000
			
			-- Populate with existing selectors
			for _, obj in group.selectors do
				createSelectorBox(groupDropdown, group, obj, unparseSelector(obj.selector))
			end

			return group, groupDropdown
		end

		-- Insert button on selectorList header to add new groups
		local header = selectorList.Backdrop:WaitForChild("DropDownHeader")
		PluginUI.createInsertButton(header, function()
			createSelectorGroup(nil)
			onSelectorChanged()
		end)

		-- Parse existing selector string into groups and selectors
		if #rule.Rule.Selector > 0 then
			local splitGroups = rule.Rule.Selector:split(",")
			for _, groupStr in splitGroups do
				local groupStr = groupStr:match("^%s*(.-)%s*$") -- trim whitespace
				if not groupStr then continue end
				local existingSelectors = {}
				for part in groupStr:gmatch("%S+") do
					table.insert(existingSelectors, {selector = part})
				end
				createSelectorGroup(existingSelectors)
			end
		end
		
		local globalRule = rule
		local function onvalue(rule: Style.Rule, PROP: string, TY: string, udfStr: string, DEFAULT_VALUE: any)
			if udfStr == "" then
				rule:SetProperty(PROP, nil)
				return
			end
			local value = UDF.from(udfStr --[[, TY]])
			globalRule:SetToken(PROP, value, true)
			rule:SetProperty(PROP, `${PROP}`)
		end
		local colorChanged1
		local color = rule:GetToken("ImageColor3") or Color3.fromRGB(255, 255, 255)
		local colorBox1 = PluginUI.createAttributeBox(
			explorerFrameConfigHeader,
			"Icon Color3",
			color and `[rgb] {ToStringUtils.toRGBString(color)}` or "",
			function(udfStr)
				local PROP, TY = "ImageColor3", "Color3"
				onvalue(rule:GetChild("IconStyle"), PROP, TY, udfStr, Color3.fromRGB(255, 255, 255))
				colorChanged1(UDF.from(udfStr, TY) or Color3.fromRGB(255, 255, 255))
			end
		)
		do
			local chooseColorButton = PluginUI.createSideButtonImage("", Vector2.zero, Vector2.zero, colorBox1.Instance.ValueBox)
			chooseColorButton:AddTag("JEXP_Border")
			chooseColorButton.BackgroundColor3 = color

			local function colorChanged(newColor: Color3)
				assert(rule)

				local PROP, TY = "ImageColor3", "Color3"
				onvalue(rule:GetChild("IconStyle"), PROP, TY, UDF.to(newColor), Color3.fromRGB(255, 255, 255))
				colorBox1:SetText(UDF.to(newColor))
				chooseColorButton.BackgroundColor3 = newColor
			end
			colorChanged1 = colorChanged

			local last
			chooseColorButton.Activated:Connect(function()
				assert(rule)
				if last then
					last:Close()
					last:Destroy()
				end
				local picker = ColorPicker.new(plugin, PluginUI.getId("StyleColorPicker", true))
				last = picker

				picker:Show()
				local originalColor = rule:GetToken("ImageColor3") or Color3.fromRGB(255, 255, 255)
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
		end
		
		local image = rule:GetToken("Image")
		PluginUI.createAttributeBox(
			explorerFrameConfigHeader,
			"Icon Image",
			image and `[str] {image}` or "",
			function(udfStr)
				local PROP, TY = "Image", "string"
				onvalue(rule:GetChild("IconStyle"), PROP, TY, udfStr, "")
			end
		)
		local bg = rule:GetToken("BackgroundColor3") or Color3.fromRGB(255, 255, 255)
		
		local colorChanged2
		local colorBox2 = PluginUI.createAttributeBox(
			explorerFrameConfigHeader,
			"Overlay Color3",
			bg and `[rgb] {ToStringUtils.toRGBString(bg)}` or "",
			function(udfStr)
				local PROP, TY = "BackgroundColor3", "Color3"
				onvalue(rule:GetChild("OverlayStyle"), PROP, TY, udfStr, Color3.fromRGB(255, 255, 255))
				colorChanged2(UDF.from(udfStr, TY) or Color3.fromRGB(255, 255, 255))
			end
		)
		do
			local chooseColorButton = PluginUI.createSideButtonImage("", Vector2.zero, Vector2.zero, colorBox2.Instance.ValueBox)
			chooseColorButton:AddTag("JEXP_Border")
			chooseColorButton.BackgroundColor3 = bg

			local function colorChanged(newColor: Color3)
				assert(rule)

				local PROP, TY = "BackgroundColor3", "Color3"
				onvalue(rule:GetChild("IconStyle"), PROP, TY, UDF.to(newColor), Color3.fromRGB(255, 255, 255))
				colorBox2:SetText(UDF.to(newColor))
				chooseColorButton.BackgroundColor3 = newColor
			end
			colorChanged2 = colorChanged

			local last
			chooseColorButton.Activated:Connect(function()
				assert(rule)
				if last then
					last:Close()
					last:Destroy()
				end
				local picker = ColorPicker.new(plugin, PluginUI.getId("StyleColorPicker", true))
				last = picker

				picker:Show()
				local originalColor = rule:GetToken("BackgroundColor3") or Color3.fromRGB(255, 255, 255)
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
		end
		
		local bt = rule:GetToken("BackgroundTransparency")
		PluginUI.createAttributeBox(
			explorerFrameConfigHeader,
			"Overlay Transparency",
			bt and `[num] {ToStringUtils.toFloatString(bt)}` or "",
			function(udfStr)
				local PROP, TY = "BackgroundTransparency", "number"
				onvalue(rule:GetChild("OverlayStyle"), PROP, TY, udfStr, 1)
			end
		)
		
		local imageRectOffset = rule:GetToken("ImageRectOffset")
		PluginUI.createAttributeBox(
			explorerFrameConfigHeader,
			"Icon ImageRectOffset",
			imageRectOffset and `[vec2] {ToStringUtils.toVec2String(imageRectOffset)}` or "",
			function(udfStr)
				local PROP, TY = "ImageRectOffset", "Vector2"
				onvalue(rule:GetChild("IconStyle"), PROP, TY, udfStr, Vector2.zero)
			end
		)

		local imageRectSize = rule:GetToken("ImageRectSize")
		PluginUI.createAttributeBox(
			explorerFrameConfigHeader,
			"Icon ImageRectSize",
			imageRectSize and `[vec2] {ToStringUtils.toVec2String(imageRectSize)}` or "",
			function(udfStr)
				local PROP, TY = "ImageRectSize", "Vector2"
				onvalue(rule:GetChild("IconStyle"), PROP, TY, udfStr, Vector2.zero)
			end
		)
		
		local contrastThreshold = rule:GetToken("ContrastThreshold")
		PluginUI.createAttributeBox(
			explorerFrameConfigHeader,
			"Contrast Threshold",
			contrastThreshold and `[num] {contrastThreshold}` or "",
			function(udfStr)
				rule:SetToken("ContrastThreshold", UDF.from(udfStr), true)
			end
		)
	end
	
	local header = editorDropdown.Backdrop:WaitForChild("DropDownHeader")
	PluginUI.createInsertButton(header, function()
		local overlayRule = Style.rule("OverlayStyle", "> #Main > #Overlay", 1, {
			BackgroundColor3 = var "$BackgroundColor3",
			BackgroundTransparency = var "$BackgroundTransparency"
		})
		local iconRule = Style.rule("IconStyle", "> #Main > #ClassIcon", 1, {
			ImageColor3 = var "$ImageColor3",
			Image = var "$Image",
			ImageRectOffset = var "$ImageRectOffset",
			ImageRectSize = var "$ImageRectSize"
		})
		local rule = Style.rule("ExplorerFrameConfig", "", 10, {
			overlayRule,
			iconRule,
			Style.rule("NameStyle", "> #Main > #InstanceName", 1, {
				TextColor3 = var "brightnessWithTransparency($BackgroundColor3, $BackgroundTransparency, $BackgroundColor) > $ContrastThreshold ? rgb(0, 0, 0) : rgb(255, 255, 255)"
			}),
			Style.rule("ArrowStyle", "> #Main > #Arrow", 1, {
				Image = var "brightnessWithTransparency($BackgroundColor3, $BackgroundTransparency, $BackgroundColor) > $ContrastThreshold ? $DarkArrowImage : $LightArrowImage",
				ImageColor3 = var "brightnessWithTransparency($BackgroundColor3, $BackgroundTransparency, $BackgroundColor) > $ContrastThreshold ? rgb(0, 0, 0) : rgb(255, 255, 255)"
			}),
			Style.rule("InsertButton", "> #Main > #Insert", 1, {
				ImageColor3 = var "brightnessWithTransparency($BackgroundColor3, $BackgroundTransparency, $BackgroundColor) > $ContrastThreshold ? rgb(0, 0, 0) : rgb(255, 255, 255)"
			}),
			Style.rule("ReclassButton", "> #Main > #Reclass", 1, {
				ImageColor3 = var "brightnessWithTransparency($BackgroundColor3, $BackgroundTransparency, $BackgroundColor) > $ContrastThreshold ? rgb(0, 0, 0) : rgb(255, 255, 255)"
			})
		})
		
		rule:AddTag("ExplorerFrameConfig")
		rule:SetToken("BackgroundColor3", Color3.fromRGB(255, 255, 255), false)
		rule:SetToken("ImageColor3", Color3.fromRGB(255, 255, 255), false)
		rule:SetToken("Image", "", false)
		rule:SetToken("BackgroundTransparency", 1, false)
		rule:SetToken("ContrastThreshold", 0.5, false)
		rule:SetName("ExplorerFrameConfig")
		
		Manager.Style:AddRules({rule})
		rule:UpdateTokens()
		
		createExplorerFrameConfig(rule)
	end)
	
	for _, rule in Manager.Style:GetTagged("ExplorerFrameConfig") do
		createExplorerFrameConfig(rule)
	end
end

return ExplorerFrameEditor