--!strict
--!optimize 2

local plugin = script:FindFirstAncestorOfClass("Plugin")

local ReflectionService = game:GetService("ReflectionService")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

local main = script.Parent.Parent

local shared = main.Shared

local UITemplates = require(shared.UITemplates)
local PropertyFrame = require(script.PropertyFrame)
local xyz = require(shared.Small.xyz)
local RawInst = require(shared.Small.RawInst)
local VersionControl = require(script.Parent.VersionControl)
local PluginUI = require(shared.PluginUI)
local ItemGroup = require(shared.Vendor.ItemGroup)
local cleanup = ItemGroup.cleanup

local Types = require(main.Types)

local rawindex = RawInst.rawindex
local rawnewindex = RawInst.rawnewindex
local getId = PluginUI.getId

local instanceConnections: {RBXScriptConnection} = {}
local instancesToClean: {Instance} = {}

-- Frame pooling system
local framePool: {[string]: {{frame: PluginUI.ValueUIItem & any, data: {[string]: any}}}} = {}
local frameMetadata: {[any]: {type: string, data: {[string]: any}, connections: {RBXScriptConnection}}} = {}

local function cleanupFrameConnections(frame: any)
	local metadata = frameMetadata[frame]
	if metadata and metadata.connections then
		for _, conn in metadata.connections do
			if typeof(conn) == "RBXScriptConnection" then
				conn:Disconnect()
			elseif typeof(conn) == "function" then
				conn()
			end
		end
		table.clear(metadata.connections)
	end
end

local function getPooledFrame(propType: string, createFn: any, ...): (PluginUI.ValueUIItem & any, {[string]: any})
	if not framePool[propType] then
		framePool[propType] = {}
	end

	local pool = framePool[propType]
	if #pool > 0 then
		local frame = table.remove(pool)
		assert(frame)
		
		cleanupFrameConnections(frame)
		return frame.frame, frame.data
	end
	local frame, data = createFn(...)
	if frame then
		frameMetadata[frame] = {
			type = propType,
			data = data,
			connections = {}
		}
	end
	return frame, data
end

local function clearActiveFrames()
	for frame, metadata in frameMetadata do
		if metadata.connections then
			for _, conn in metadata.connections do
				if typeof(conn) == "RBXScriptConnection" then
					conn:Disconnect()
				elseif typeof(conn) == "function" then
					conn()
				end
			end
			table.clear(metadata.connections)
		end
		if frame.Instance then
			frame.Instance.Parent = nil
		end
	end
end

local function poolFramesByType()
	-- Organize all frames back into pools
	for frame, metadata in frameMetadata do
		local propType = metadata.type
		if propType then
			if not framePool[propType] then
				framePool[propType] = {}
			end
			local pooled = {
				frame = frame,
				data = metadata.data
			}
			local found = false
			for _, v in framePool[propType] do
				if v.frame == frame then
					found = true
					break
				end
			end
			if not found then
				table.insert(framePool[propType], pooled)
			end
		end
	end
end

local typeToPropModule = {}
for _, v in script.PropertyFrames:GetChildren() do
	local name = v.Name
	local module: PropertyFrame.PropertyFrame = (require::any)(v)
	local split = string.split(name, "_")
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

local function gettypestr(type: ReflectionType)
	if type.InstanceType == "Instance" then
		return "Instance"
	else
		return type.EngineType
	end
end

local function getCommonProperties(instances: {Instance}): ReflectedProperties
	if #instances == 0 then
		return {}
	end

	if #instances == 1 then
		-- Single instance, return all its properties
		local inst = instances[1]
		return ReflectionService:GetPropertiesOfClass(inst.ClassName)
	end
	local commonProps = {}
	local firstInstanceProps = ReflectionService:GetPropertiesOfClass(instances[1].ClassName)

	if not firstInstanceProps then
		return {}
	end

	-- Start with properties from the first instance
	for _, propData in firstInstanceProps do
		local propName = propData.Name
		local isCommon = true

		-- Check if this property exists in all other instances
		for i = 2, #instances do
			local instanceProps = ReflectionService:GetPropertiesOfClass(instances[i].ClassName)
			local instancePropsSet = {}
			for _, v in instanceProps do
				instancePropsSet[v.Name] = v
			end
			if not instancePropsSet[propName] then
				isCommon = false
				break
			end

			-- Also check if the property type matches
			if gettypestr(instancePropsSet[propName].Type) ~= gettypestr(propData.Type) then
				isCommon = false
				break
			end
		end

		if isCommon then
			table.insert(commonProps, propData)
		end
	end

	return commonProps
end

function PropertyEditor.updateProperties(instances)
	if not init then return end
	debug.profilebegin("PropertyEditor::updateProperties")
	local widget = PropertyEditor.Widget
	local list = PropertyEditor.PropertyList

	-- Disconnect connections
	for _, v in instanceConnections do
		v:Disconnect()
	end
	table.clear(instanceConnections)

	-- Clean up temporary instances
	for _, v in instancesToClean do
		v:Destroy()
	end
	table.clear(instancesToClean)

	-- Clear active frames and pool them for reuse
	clearActiveFrames()
	poolFramesByType()

	list:Clear()

	local n = #instances
	if n == 0 then
		widget.Title = "JProperties"
		debug.profileend()
		return
	end
	if n > 1 then
		widget.Title = `JProperties - {n} items`
	else
		local inst = instances[1]
		assert(inst)

		widget.Title = `JProperties - {inst.ClassName} "{inst.Name}"`
	end

	local props = getCommonProperties(instances) or {}
	local categories = {}
	for _, v in props::ReflectedProperties do
		local display = v.Display
		if display and display.DeprecationMessage then
			continue
		end
		local category
		if display then
			category = display.Category
		else
			category = "Data"
		end
		if not categories[category] then
			categories[category] = {}
		end
		
		local item = {
			name = v.Name,
			type = v.Type,
			writable = if v.Permits.Write ~= nil then SecurityCapabilities.fromCurrent():Contains(v.Permits.Write) else false,
			readable = if v.Permits.Read ~= nil then SecurityCapabilities.fromCurrent():Contains(v.Permits.Read) else false,
		}
		table.insert(categories[category], item)
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
	
	PluginUI.clearOpenEnumLists()
	
	local datas: {[string]: {changed: (any) -> (), frame: PluginUI.ValueUIItem, item: Types.PropertyItem}} = {}
	
	local defaultValues = {
		["Color3"] = Color3.fromRGB(0, 0, 0),
		["string"] = "",
		["Instance"] = nil,
		["int8"] = 0,
		["int16"] = 0,
		["int64"] = 0,
		["int32"] = 0,
		["int"] = 0,
		["Vector3"] = Vector3.zero,
		["ContentId"] = "",
		["bool"] = false,
		["double"] = 0,
		["float"] = 0
	}
	
	local defaultEnumValues = require(script.defaultEnumValues)
	
	local dropdowns = {}
	for i, v in categoriesSorted do
		local category, propItems = v.category, v.list

		local dropdown = PluginUI.createDropDownItemList({Visible = true, Name = category}, category, false)
		dropdown.Backdrop.LayoutOrder = i
		dropdown.Container.AutomaticCanvasSize = Enum.AutomaticSize.Y

		local n = 0
		for _, propItem in propItems do
			if not isFirstCharUpper(propItem.name) then continue end
			if not propItem.readable then continue end

			local propType = propItem.type
			local typeStr = gettypestr(propType)
			
			local module = typeToPropModule[typeStr]
			if not module then continue end
			
			local allSame, firstValue = PropertyFrame.isAllValuesSame(instances, propItem.name)
			
			local initValue
			if allSame then
				initValue = firstValue
			else
				if typeStr == "Enum" and propType.EnumType then
					initValue = defaultEnumValues[propType.EnumType]
				else
					initValue = defaultValues[typeStr]
				end
			end
			
			local info = {
				PropertyEditor = PropertyEditor,
				Manager = Manager,
				InstanceCleanup = instancesToClean,
				Plugin = plugin,
				VersionControl = VersionControl,
				Instances = instances
			}
			local propFrame, data = getPooledFrame(typeStr, module.createUI, info, dropdown, propItem, initValue)
			if not propFrame then continue end
			
			propFrame:SetName(propItem.name)
			
			-- Re-parent the frame to the current dropdown
			if propFrame.Instance then
				propFrame.Instance.Parent = dropdown.Container
			end

			n += 1
			
			local cleanup, changedFn = module.applyBehavior(info, propItem, initValue, data)
			datas[propItem.name] = {
				changed = changedFn,
				frame = propFrame,
				item = propItem
			}
			if not allSame then
				if propFrame.SetText then
					propFrame:SetText("--")
				else
					propFrame:Set("--")
				end
			end
			
			propFrame:SetEditable(propItem.writable)
			-- Store the connection in metadata
			local metadata = frameMetadata[propFrame]
			if metadata then
				table.insert(metadata.connections, cleanup :: any)
			end
		end
		if n == 0 then
			dropdown:Destroy()
			continue
		end
		table.insert(dropdowns, dropdown)
		dropdown:Show()
	end
	for _, inst in instances do
		table.insert(instanceConnections, inst.Changed:Connect(function(prop)
			local data = datas[prop]
			if not data then return end
			
			if not data.item.writable then return end
			
			local allSame, firstValue = PropertyFrame.isAllValuesSame(instances, prop)
			if allSame then
				data.changed(firstValue)
			else
				data.changed(defaultValues[prop])
				data.frame:Set("--")
			end
		end))
	end

	local allHaveTags = true
	for _, inst in instances do
		if not inst.GetTags then
			allHaveTags = false
			break
		end
	end

	if allHaveTags then
		local dropdown = PluginUI.createDropDownItemList({Visible = true, Name = "Tags", LayoutOrder = 1000}, "Tags", false)
		table.insert(dropdowns, dropdown)
		dropdown.Container.AutomaticCanvasSize = Enum.AutomaticSize.Y

		local tagToFrame = {}
		local function createTagFrame(tag: string)
			local frame = PluginUI.createButtonWithIcon(dropdown, tag, "rbxassetid://92768859826736", Vector2.zero, Vector2.zero)
			frame.Instance.Icon:AddTag("JEXP_MonochromeImage")
			
			PluginUI.createDeleteButton(frame.Instance, function()
				frame:Destroy()
				for _, inst in instances do
					inst:RemoveTag(tag)
				end
				tagToFrame[tag] = nil
			end)
			tagToFrame[tag] = frame
		end
		
		local currentWidget
		local insert = PluginUI.createInsertButton(dropdown.Backdrop.DropDownHeader, function()
			if currentWidget then
				currentWidget:Destroy()
			end
			local tagBox = PluginUI.createAttributeBox(nil, "Tag", "")
			local widget, cancel, confirm, close = PluginUI.createCreatorWidget("Add Tag", {
				tagBox
			})
			currentWidget = widget
			Manager.Style:Link(widget)
			
			cancel:OnTrigger(function()
				close()
			end)
			confirm:OnTrigger(function()
				local tag = tagBox:Get()
				for _, inst in instances do
					inst:AddTag(tag)
				end
				close()
			end)
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
	local instances = connections:extend(cleanup.destroy)

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

	local list = PluginUI.createItemListFromExisting(mainframe, mainframe.Items.Content, mainframe.Items)
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

		for _, inst in currentTarget.instances do
			rawnewindex(inst, currentTarget.name, nil)
		end
	end)

	PropertyEditor.SetNilMenu = setNilMenu

	connections:add_many(instanceConnections)
	connections:add(mainframe.InputBegan:Connect(function()
		PluginUI.clearOpenEnumLists()
	end))
end 

function PropertyEditor.clearFramePools()
	for frame, metadata in frameMetadata do
		if metadata.connections then
			for _, conn in metadata.connections do
				conn:Disconnect()
			end
		end
	end
	for propType, pool in framePool do
		for _, frame in pool do
			if frame.frame.Instance then
				frame.frame.Instance:Destroy()
			end
		end
	end

	table.clear(framePool)
	table.clear(frameMetadata)
end

return PropertyEditor