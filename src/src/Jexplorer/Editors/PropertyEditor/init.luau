--!strict
--!optimize 2

local plugin = script:FindFirstAncestorOfClass("Plugin")

local main = script.Parent.Parent

local utilities = main.Utilities

local UITemplates = require(utilities.UITemplates)
local PropertyFrame = require(script.PropertyFrame)
local xyz = require(script.xyz)
local InstanceUtility = require(utilities.Small.InstanceUtility)
local VersionControl = require(script.Parent.VersionControl)
local PluginUI = require(utilities.PluginUI)

local Types = require(main.Types)

local rawindex = InstanceUtility.rawindex
local rawnewindex = InstanceUtility.rawnewindex
local getId = PluginUI.getId

local instanceConnections: {RBXScriptConnection} = {}
local instancesToClean: {Instance} = {}

local typeToPropModule = {}
for _, v in script.PropertyFrames:GetChildren() do
	local name = v.Name
	local module = (require::any)(v)
	local split = string.split(name, "|")
	for _, part in split do
		typeToPropModule[part] = module
	end
end

local function isFirstCharUpper(s: string)
	local upper = string.char(string.byte(s) + 32)
	return string.upper(upper) == string.sub(s, 1, 1)
end

local DEFAULT_PRIORITY = 2
local CATEGORY_PRIORITIES = {
	"Data",
	"Behavior",
	"Tags",
	"Attributes"
}

local init = false

local Manager: Types.Manager
local PropertyEditor = {} :: Types.PropertyEditor

local function getCommonProperties(instances: {Instance}): {[any]: any}
	if #instances == 0 then
		return {}
	end

	if #instances == 1 then
		-- Single instance, return all its properties
		local inst = instances[1]
		return Manager.APIMap[inst.ClassName] or {}
	end

	-- Multiple instances - find intersection of properties
	local commonProps = {}
	local firstInstanceProps = Manager.APIMap[instances[1].ClassName]

	if not firstInstanceProps then
		return {}
	end

	-- Start with properties from the first instance
	for propName, propData in firstInstanceProps do
		local isCommon = true

		-- Check if this property exists in all other instances
		for i = 2, #instances do
			local instanceProps = Manager.APIMap[instances[i].ClassName]
			if not instanceProps or not instanceProps[propName] then
				isCommon = false
				break
			end

			-- Also check if the property type matches
			if instanceProps[propName].Type ~= propData.Type then
				isCommon = false
				break
			end
		end

		if isCommon then
			commonProps[propName] = propData
		end
	end

	return commonProps
end

function PropertyEditor.updateProperties(instances)
	if not init then return end
	debug.profilebegin("PropertyEditor::updateProperties")
	local widget = PropertyEditor.Widget
	local list = PropertyEditor.PropertyList
	for _, v in instanceConnections do
		v:Disconnect()
	end
	for _, v in instancesToClean do
		v:Destroy()
	end

	list:Clear()

	local n = #instances
	if n == 0 then
		widget.Title = "JProperties"
		return
	end
	if n > 1 then
		widget.Title = `JProperties - {n} items`
	else
		local inst = instances[1]
		assert(inst)

		widget.Title = `JProperties - {inst.ClassName} "{inst.Name}"`
	end
	
	local props = getCommonProperties(instances)
	local categories = {}
	for k, v in props do
		local item = {name = k, type = v.Type, writable = v.Writable, readable = v.Readable}
		if not categories[v.Category] then
			categories[v.Category] = {}
		end
		table.insert(categories[v.Category], item)
	end
	
	local categoriesSorted = {}
	for category, list in categories do
		table.insert(categoriesSorted, {category = category, list = list})
	end
	table.sort(categoriesSorted, function(a, b)
		local pa = table.find(CATEGORY_PRIORITIES, a.category) or DEFAULT_PRIORITY
		local pb = table.find(CATEGORY_PRIORITIES, b.category) or DEFAULT_PRIORITY

		return pa < pb
	end)
	
	local function getFormattedValue(t: string, value: any)
		if t == "float" or t == "double" then
			value = string.format("%.3f", value)
		elseif t == "int8" or t == "int16" or t == "int32" or t == "int64" or t == "int" then
			value = tostring(math.round(value))
		elseif t == "Vector3" then
			value = `{string.format("%.3f", value.X)}, {string.format("%.3f", value.Y)}, {string.format("%.3f", value.Z)}`
		elseif t == "Color3" then
			value = `{math.round(value.R)}, {math.round(value.G)}, {math.round(value.B)}`
		elseif t:match("Enum") then
			value = value.Name
		end
		return value
	end
	
	local function onchange(propFrame: PluginUI.ValueUIItem, propItem: Types.PropertyItem, newValue: any)
		local actualValue: any
		local t = propItem.type
		local enumName = t:match("Enum%.(%w+)")
		if t == "double" or t == "float" then
			actualValue = string.format("%.3f", newValue)
		elseif t == "int8" or t == "int16" or t == "int32" or t == "int" or t == "int64" then
			actualValue = tostring(math.round(newValue))
		elseif t == "bool" or t == "string" or t == "ContentId" or t == "Instance" then
			actualValue = newValue
		elseif enumName then
			actualValue = (Enum[enumName] :: any):FromName(newValue)
		elseif t == "Vector3" then
			local x, y, z = xyz(newValue)
			actualValue = Vector3.new(
				tonumber(x),
				tonumber(y),
				tonumber(z)
			)
		elseif t == "Color3" then
			local r, g, b = xyz(newValue)
			actualValue = Color3.fromRGB(
				tonumber(r),
				tonumber(g),
				tonumber(b)
			)
		end
		for _, inst in instances do
			local success = pcall(rawnewindex, inst, propItem.name, actualValue)
			if not success then
				propFrame:Set(getFormattedValue(t, rawindex(inst, propItem.name)))
				break
			end
			VersionControl.addPendingChange(inst, propItem.name, actualValue)
		end
	end
	
	local items: {[string]: PluginUI.ValueUIItem} = {}
	for _, inst in instances do
		table.insert(instanceConnections, inst.Changed:Connect(function(prop)
			local item = items[prop]
			if not item then return end

			local property = props[prop]
			if not property then return end
			if not property.Readable then return end
			
			local firstValue = rawindex(instances[1], prop)
			local allSame = true

			for i = 2, #instances do
				if rawindex(instances[i], prop) ~= firstValue then
					allSame = false
					break
				end
			end

			local t = property.Type
			local value = firstValue

			if not allSame then
				item:Set("--")
				return
			end

			if value == nil then
				item:Set("")
				return
			end
			value = getFormattedValue(t, value)
			
			item:Set(typeof(value) ~= "string" and tostring(value) or value)
		end))
	end
	
	local dropdowns = {}
	for i, v in categoriesSorted do
		local category, propItems = v.category, v.list :: {Types.PropertyItem}

		local dropdown = PluginUI.createDropDownItemList({Visible = true, Name = category}, category, false)
		dropdown.Backdrop.LayoutOrder = i
		dropdown.Container.AutomaticCanvasSize = Enum.AutomaticSize.Y
		
		local n = 0
		for _, propItem in propItems do
			if not isFirstCharUpper(propItem.name) then continue end
			if not propItem.readable then continue end

			local propType = propItem.type
			if propItem.type:sub(1, 4) == "Enum" then
				propType = "Enum"
			end

			local create = typeToPropModule[propType]
			if not create then continue end
			
			local propFrame = create({
				PropertyEditor = PropertyEditor,
				Manager = Manager,
				InstanceCleanup = instancesToClean
			}, dropdown, instances[1], propItem)
			if not propFrame then continue end

			n += 1

			if not propItem.writable then
				propFrame:SetEditable(false)
				continue
			end

			propFrame:OnChange(function(newValue: any)
				onchange(propFrame, propItem, newValue)
			end)

			items[propItem.name] = propFrame
			
			local firstValue = rawindex(instances[1], propItem.name)
			local allSame = true

			for j = 2, #instances do
				if rawindex(instances[j], propItem.name) ~= firstValue then
					allSame = false
					break
				end
			end

			if not allSame then
				propFrame:Set("--")
			end
		end
		if n == 0 then
			dropdown:Destroy()
			continue
		end
		table.insert(dropdowns, dropdown)
		dropdown:Show()
	end
	
	local allHaveTags = true
	for _, inst in instances do
		if not inst.GetTags then
			allHaveTags = false
			break
		end
	end
	
	if allHaveTags then
		local dropdown = PluginUI.createDropDownItemList({Visible = true, Name = "Tags"}, "Tags", false)
		table.insert(dropdowns, dropdown)
		dropdown.Backdrop.LayoutOrder = 10000
		dropdown.Container.AutomaticCanvasSize = Enum.AutomaticSize.Y
		
		local tagToFrame = {}
		local function createTagFrame(tag: string)
			local frame = PluginUI.createButtonWithIcon(dropdown, tag, "rbxassetid://92768859826736", Vector2.zero, Vector2.zero)
			PluginUI.createDeleteButton(frame.Instance, function()
				frame:Destroy()
				for _, inst in instances do
					inst:RemoveTag(tag)
				end
				tagToFrame[tag] = nil
			end)
			tagToFrame[tag] = frame
		end

		local insert = PluginUI.createInsertButton(dropdown.Backdrop.DropDownHeader, function()
			for _, inst in instances do
				inst:AddTag("TEST")
			end
		end)
		
		local commonTags = {}
		if #instances > 0 then
			local firstInstanceTags = instances[1]:GetTags()
			for _, tag in firstInstanceTags do
				local isCommon = true
				for i = 2, #instances do
					if not table.find(instances[i]:GetTags(), tag) then
						isCommon = false
						break
					end
				end
				if isCommon then
					table.insert(commonTags, tag)
				end
			end
		end

		for _, tag in commonTags do
			createTagFrame(tag)
		end
		
		for _, inst in instances do
			table.insert(instanceConnections, Manager.onTagAdded(inst, function(tag)
				local isCommon = true
				for _, otherInst in instances do
					if not table.find(otherInst:GetTags(), tag) then
						isCommon = false
						break
					end
				end
				if isCommon and not tagToFrame[tag] then
					createTagFrame(tag)
				end
			end))
			table.insert(instanceConnections, Manager.onTagRemoved(inst, function(tag)
				local frame = tagToFrame[tag]
				if frame then
					frame:Destroy()
					tagToFrame[tag] = nil
				end
			end))
		end

		dropdown:Show()
	end
	
	for _, v in dropdowns do
		list:AddItem(v.Backdrop)
	end
	debug.profileend()
end

function PropertyEditor.init(_m)
	init = true
	Manager = _m

	local state = Manager.WidgetState
	local components = Manager.Components

	local jexplorerUi = state.JExplorerUI
	local topbar = jexplorerUi.Topbar
	
	local connections = state.Connections
	local instances = connections:Extend("Destroy")

	local toggleButton = Manager.Toolbar:CreateButton(
		getId("ToggleProperties"), "Toggle the properties widget visibility",
		"rbxassetid://106850260964317", "Properties"
	)
	toggleButton.ClickableWhenViewportHidden = true

	local widget, mainframe = PluginUI.createEditorWidget(
		UITemplates.EditorFrame(), "PropertyEditor", "",
		DockWidgetPluginGuiInfo.new(
			Enum.InitialDockState.Right,
			false,
			false
		)
	)
	
	widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	widget.Title = "JProperties"

	PropertyEditor.Widget = widget
	Manager.Style:Link(widget)
	
	toggleButton.Click:Connect(function()
		widget.Enabled = not widget.Enabled
	end)

	local list = PluginUI.createItemListFromExisting(mainframe, mainframe.Items)
	PropertyEditor.PropertyList = list

	local setNilMenu = plugin:CreatePluginMenu(
		getId("Jexplorer_PropertyEditor_ContextMenu_SetNil", true)
	)
	local action = setNilMenu:AddNewAction(
		getId("Jexplorer_PropertyEditor_ContextMenu_SetNilAction", true), "Set to Nil"
	) :: PluginAction
	action.Triggered:Connect(function()
		local currentTarget = PropertyEditor.CurrentSetNilTarget
		if not currentTarget then return end
		
		for _, v in currentTarget do
			InstanceUtility.rawnewindex(v.inst, v.name, nil)
		end
	end)
	
	PropertyEditor.SetNilMenu = setNilMenu

	connections:Insert {
		function()
			for _, v in instanceConnections do
				v:Disconnect()
			end
		end,
	}
end 

return PropertyEditor