--!optimize 2
--!strict

local plugin = script:FindFirstAncestorOfClass("Plugin")

local StudioService = game:GetService("StudioService")

local RawInst = require(script.Parent.Small.RawInst)
local index, newindex = RawInst.index, RawInst.newindex

export type ItemList = {
	Backdrop: Frame & any,
	Container: ScrollingFrame,
	CurrentParent: ItemList?,
	Items: {GuiObject},
	IsShown: boolean,
	AddItem: (self: ItemList, item: GuiObject) -> (),
	RemoveItem: (self: ItemList, item: GuiObject) -> (),
	Clear: (self: ItemList) -> (),
	SetAnchor: (self: ItemList, anchorPoint: Vector2, position: UDim2) -> (),
	Show: (self: ItemList) -> (),
	Hide: (self: ItemList) -> (),
	Destroy: (self: ItemList) -> (),
	Parent: (self: ItemList, parentList: ItemList) -> ()
}

export type ValueUIItem<T = (newValue: string, ...never) -> ()> = {
	Instance: Instance & {
		ValueBox: TextBox
	},
	Get: (self: ValueUIItem<T>) -> any,
	Set: (self: ValueUIItem<T>, value: any) -> (),
	SetText: (self: ValueUIItem<T>, new: string) -> (),
	GetName: (self: ValueUIItem<T>) -> string,
	SetName: (self: ValueUIItem<T>, new: string) -> (),
	OnChange: (self: ValueUIItem<T>, callback: T) -> RBXScriptConnection,
	Destroy: (self: ValueUIItem<T>) -> (),
	SetEditable: (self: ValueUIItem<T>, editable: boolean) -> ()
}

export type TriggerUIItem = {
	Instance: Instance & any,
	Trigger: (self: TriggerUIItem) -> (),
	OnTrigger: (self: TriggerUIItem, callback: () -> ()) -> RBXScriptConnection,
	Destroy: (self: TriggerUIItem) -> ()
}

local function remove(t: any, key: any)
	local v = t[key]
	t[key] = nil
	return v
end

local function updateLayout(container: any)
	-- Update canvas size based on content
	local totalHeight = 0
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") and child.Visible then
			totalHeight += child.AbsoluteSize.Y
		end
	end
	container.CanvasSize = UDim2.new(0, 0, 0, totalHeight + 2)
end

local function isNotTransparent(gui: GuiObject)
	if gui:IsA("Frame") then
		return gui.BackgroundTransparency < 0.98
	elseif
		gui:IsA("TextButton")
	or	gui:IsA("TextLabel")
	or	gui:IsA("TextBox")
	then
		return gui.BackgroundTransparency < 0.98 or gui.Transparency < 0.98
	else
		return true
	end
end

local function canBeSeen(gui: GuiObject)
	local isntTransparent = isNotTransparent(gui)
	
	if isntTransparent then
		return true
	else
		return gui:FindFirstChildOfClass("UIStroke") ~= nil
	end
end

local PluginUI = {}

function PluginUI.getGuiObjectsAtPosition(root: GuiObject, x: number, y: number)
	local list: {GuiObject} = {}
	local visit, iterate
	
	function visit(instance: Instance, clipStart: Vector2?, clipEnd: Vector2?)
		if instance:IsA("GuiObject") then
			if not instance.Visible then return false end
			
			local start = if clipStart then
				Vector2.new(
					math.max(instance.AbsolutePosition.X, clipStart.X),
					math.max(instance.AbsolutePosition.Y, clipStart.Y)
				)
				else
				instance.AbsolutePosition
			
			local extend = if clipEnd then
				Vector2.new(
					math.min(
						instance.AbsolutePosition.X + instance.AbsoluteSize.X,
						clipEnd.X
					),
					math.min(
						instance.AbsolutePosition.Y + instance.AbsoluteSize.Y,
						clipEnd.Y
					)
				)
				else
				instance.AbsolutePosition + instance.AbsoluteSize
			
			if instance.ClipsDescendants then
				iterate(instance, start, extend)
			else
				iterate(instance, clipStart, clipEnd)
			end
			
			local minX = math.min(start.X, extend.X)
			local maxX = math.max(minX, extend.X)
			local minY = math.min(start.Y, extend.Y)
			local maxY = math.max(minY, extend.Y)

			local isInside =
				x >= minX
			and x <= maxX
			and	y >= minY
			and	y <= maxY

			return isInside;
		end
		iterate(instance, clipStart, clipEnd)
		return false
	end
	
	function iterate(instance: Instance, clipStart: Vector2?, clipEnd: Vector2?)
		local buffered: {{Index: number, Object: GuiObject}} = {}
		local children = instance:GetChildren()
		
		for i, child in children do
			if not child:IsA("GuiObject") then continue end
			table.insert(buffered, {
				Index = i,
				Object = child
			})
		end
		
		table.sort(buffered, function(a, b)
			if a.Object.ZIndex == b.Object.ZIndex then
				return a.Index > b.Index
			else
				return a.Object.ZIndex > b.Object.ZIndex
			end
		end)
		
		for _, child in buffered do
			local isInside = visit(child.Object, clipStart, clipEnd)
			if isInside and canBeSeen(child.Object) then
				table.insert(list, child.Object)
			end
		end
	end
	
	iterate(root)
	return list
end

local function connection(tbl: {any}, item: any): RBXScriptConnection
	return {
		Connected = true,
		Disconnect = function(self)
			if not self.Connected then return end
			
			self.Connected = false
			local idx = table.find(tbl, item)
			if idx then
				table.remove(tbl, idx)
			end
		end,
	} :: any
end

function PluginUI.getId(name: string, unique: boolean?)
	if unique then
		return name .. os.clock()
	end
	return name
end

function PluginUI.createEditorWidget<T>(mainframe: T, name: string, displayName: string, guiInfo: DockWidgetPluginGuiInfo?): (DockWidgetPluginGui, T)
	assert(typeof(mainframe) == "Instance")
	
	local widget = plugin:CreateDockWidgetPluginGui(
		PluginUI.getId(name, true), guiInfo or DockWidgetPluginGuiInfo.new(
			Enum.InitialDockState.Float,
			false,
			true
		)
	)
	widget:AddTag("JEXP_Widget")
	
	widget.Name = `Jexplorer_{name}`
	widget.Title = `Jexplorer {displayName}`
	widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	widget:BindToClose(function()
		widget.Enabled = not widget.Enabled
	end)
	
	mainframe:AddTag("JEXP_Background")
	mainframe.Parent = widget
	
	mainframe.Items.Content:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local size = mainframe.Items.Content.AbsoluteSize
		mainframe.Items.Overlay.Size = UDim2.fromOffset(size.X, size.Y)
	end)
	
	return widget, mainframe
end

function PluginUI.createItemListFromExisting(backdrop: Instance, container: Instance, scrollingFrame: ScrollingFrame): ItemList
	local items = {}

	local itemList = {
		Backdrop = backdrop,
		Container = container,
		Items = items
	}

	-- Methods
	function itemList:AddItem(item: GuiObject)
		item.Parent = container
		item.Size = UDim2.new(1, 0, 0, item.Size.Y.Offset or 30)
		table.insert(self.Items, item)
		updateLayout(scrollingFrame)
	end

	function itemList:RemoveItem(item: GuiObject)
		for i, existingItem in self.Items do
			if existingItem == item then
				table.remove(self.Items, i)
				item:Destroy()
				break
			end
		end
		updateLayout(scrollingFrame)
	end

	function itemList:Clear()
		for _, item in self.Items do
			item:Destroy()
		end
		self.Items = {}
		updateLayout(scrollingFrame)
	end

	function itemList:SetAnchor(anchorPoint: Vector2, position: UDim2)
		self.Backdrop.AnchorPoint = anchorPoint
		self.Backdrop.Position = position
	end

	function itemList:Show()
		self.Backdrop.Visible = true
	end

	function itemList:Hide()
		self.Backdrop.Visible = false
	end

	function itemList:Destroy()
		self.Backdrop:Destroy()
	end
	
	function itemList:Parent(parent)
		self.CurrentParent = parent
		backdrop.Parent = parent and parent.Container or nil
	end
	
	return itemList :: any
end

function PluginUI.createItemList(frameProperties: {[string]: any}?): ItemList
	local backdrop do
		backdrop = Instance.new("Frame")
		local parent
		if frameProperties then
			parent = remove(frameProperties, "Parent")
		end

		-- Default properties for backdrop
		backdrop.Name = "ItemListBackdrop"
		backdrop:AddTag("JEXP_Background")
		backdrop:AddTag("JEXP_Border")
		
		backdrop.BorderSizePixel = 0
		backdrop.Size = UDim2.new(0, 200, 0, 300)
		backdrop.Position = UDim2.new(0, 0, 0, 0)
		backdrop.AnchorPoint = Vector2.new(0, 0)
		backdrop.ZIndex = 1000
		backdrop.Visible = false

		if frameProperties then
			-- Apply custom properties
			for k, v in frameProperties do
				newindex(backdrop, k, v)
			end
		end

		if parent then backdrop.Parent = parent end
	end

	-- Create scrolling container
	local container = Instance.new("ScrollingFrame")
	container.Name = "ItemContainer"

	container.Parent = backdrop
	container.Size = UDim2.new(1, -4, 1, -4)
	container.Position = UDim2.new(0, 2, 0, 2)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.ScrollBarThickness = 6
	container.ScrollBarImageColor3 = Color3.fromRGB(85, 85, 85)
	container.CanvasSize = UDim2.new(0, 0, 0, 0)
	container.AutomaticCanvasSize = Enum.AutomaticSize.Y

	-- Add UIListLayout for automatic positioning
	local layout = Instance.new("UIListLayout")
	layout.Parent = container
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 1)

	-- Track items
	local items = {}

	local itemList = {
		Backdrop = backdrop,
		Container = container,
		Items = items,
		IsShown = false
	}

	-- Methods
	function itemList:AddItem(item: GuiObject)
		item.Parent = container
		table.insert(self.Items, item)
		updateLayout(container)
	end

	function itemList:RemoveItem(item: GuiObject)
		for i, existingItem in self.Items do
			if existingItem == item then
				table.remove(self.Items, i)
				item:Destroy()
				break
			end
		end
		updateLayout(container)
	end

	function itemList:Clear()
		for _, item in self.Items do
			item:Destroy()
		end
		self.Items = {}
		updateLayout(container)
	end

	function itemList:SetAnchor(anchorPoint: Vector2, position: UDim2)
		self.Backdrop.AnchorPoint = anchorPoint
		self.Backdrop.Position = position
	end

	function itemList:Show()
		self.Backdrop.Visible = true
		self.IsShown = true
	end

	function itemList:Hide()
		self.Backdrop.Visible = false
		self.IsShown = false
	end

	function itemList:Destroy()
		self.Backdrop:Destroy()
	end
	
	function itemList:Parent(parent)
		self.CurrentParent = parent
		backdrop.Parent = parent and parent.Container or nil
	end

	return itemList :: any
end

function PluginUI.createDropDownItemList(frameProperties: {[string]: any}?, headerText: string?, headerLabelIsBox: boolean?, headerHeight: number?): ItemList
	local HEADER_HEIGHT = headerHeight or 20
	local INDENT_WIDTH = 16

	local backdrop do
		backdrop = Instance.new("Frame")
		local parent
		if frameProperties then
			parent = remove(frameProperties, "Parent")
		end

		-- Default properties for backdrop
		backdrop.Name = "DropDownItemListBackdrop"
		backdrop:AddTag("JEXP_Background")
		--backdrop:AddTag("JEXP_Border")

		backdrop.BorderSizePixel = 0
		backdrop.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
		backdrop.Position = UDim2.new(0, 0, 0, 0)
		backdrop.AnchorPoint = Vector2.new(0, 0)
		backdrop.ZIndex = 1000
		backdrop.AutomaticSize = Enum.AutomaticSize.Y
		backdrop.Visible = false

		if frameProperties then
			for k, v in frameProperties do
				newindex(backdrop, k, v)
			end
		end

		if parent then backdrop.Parent = parent end
	end

	-- Create header
	local header = Instance.new("Frame")
	header.Name = "DropDownHeader"
	header:AddTag("JEXP_LightBackground")
	header:AddTag("JEXP_Hover")

	header.BorderSizePixel = 0
	header.Size = UDim2.new(1, -2, 0, HEADER_HEIGHT - 2)
	header.Position = UDim2.new(0, 1, 0, 1)
	header.Parent = backdrop
	
	-- Arrow icon
	local arrow = Instance.new("ImageLabel")
	arrow.Name = "Arrow"
	arrow:AddTag("JEXP_Arrow")
	
	arrow.Size = UDim2.new(0, 12, 0, 12)
	arrow.Position = UDim2.new(0, 10, 0.5, 0)
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.BackgroundTransparency = 1
	arrow.Rotation = -90
	arrow.Parent = header
	
	local headerLabel: any
	if headerLabelIsBox then
		headerLabel = Instance.new("TextBox")
		headerLabel.ClearTextOnFocus = false
	else
		headerLabel = Instance.new("TextLabel")
	end
	headerLabel.Name = "HeaderLabel"
	headerLabel:AddTag("JEXP_Text")
	
	headerLabel.ZIndex = 3
	headerLabel.TextTruncate = Enum.TextTruncate.AtEnd
	headerLabel.BorderSizePixel = 0
	headerLabel.AnchorPoint = Vector2.new(0, 0.5)
	headerLabel.Size = UDim2.new(0.5, 0, 1, 0)
	headerLabel.Position = UDim2.new(0, 24, 0.5, 0)
	headerLabel.BackgroundTransparency = 1
	headerLabel.Text = headerText or "Dropdown"
	headerLabel.TextXAlignment = Enum.TextXAlignment.Left
	headerLabel.Font = Enum.Font.SourceSans
	headerLabel.TextSize = math.max(10, HEADER_HEIGHT * 0.65)
	headerLabel.Parent = header
	
	-- Create scrolling container
	local container = Instance.new("ScrollingFrame")
	container.Name = "DropDownContainer"
	
	container.VerticalScrollBarInset = Enum.ScrollBarInset.Always
	container.HorizontalScrollBarInset = Enum.ScrollBarInset.Always
	container.BorderSizePixel = 0
	container.Size = UDim2.new(1, -INDENT_WIDTH, 0, 0)
	container.Position = UDim2.new(0, INDENT_WIDTH, 0, HEADER_HEIGHT)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.ScrollBarThickness = 6
	container.ScrollBarImageColor3 = Color3.fromRGB(85, 85, 85)
	container.CanvasSize = UDim2.new(0, 0, 0, 0)
	container.AutomaticCanvasSize = Enum.AutomaticSize.None
	container.AutomaticSize = Enum.AutomaticSize.Y
	container.Visible = false -- Start collapsed
	container.Parent = backdrop
	
	local layout = Instance.new("UIListLayout")
	layout.Parent = container
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 1)
	
	local items = {}
	local itemList = {
		Backdrop = backdrop,
		Container = container,
		Items = items,
		IsShown = false
	} :: ItemList
	
	function itemList:AddItem(item: GuiObject)
		item.Parent = container
		item.Size = UDim2.new(1, 0, 0, item.Size.Y.Offset)
		table.insert(self.Items, item)
		updateLayout(container)
	end

	function itemList:RemoveItem(item: GuiObject)
		for i, existingItem in self.Items do
			if existingItem == item then
				table.remove(self.Items, i)
				item:Destroy()
				break
			end
		end
		updateLayout(container)
	end
	
	function itemList:Clear()
		for _, item in self.Items do
			item:Destroy()
		end
		self.Items = {}
		updateLayout(container)
	end

	function itemList:SetAnchor(anchorPoint: Vector2, position: UDim2)
		self.Backdrop.AnchorPoint = anchorPoint
		self.Backdrop.Position = position
	end
	
	local lastContentHeight = 0
	-- Show = Expand
	function itemList:Show()
		self.Backdrop.Visible = true
		if self.IsShown then return end
		
		self.IsShown = true
		container.Visible = true
		
		self.Container.AutomaticCanvasSize = Enum.AutomaticSize.Y
		
		arrow.Rotation = 0
	end

	-- Hide = Collapse
	function itemList:Hide()
		if not self.IsShown then 
			self.Backdrop.Visible = false
			return 
		end

		self.IsShown = false
		
		self.Container.AutomaticCanvasSize = Enum.AutomaticSize.None
		
		arrow.Rotation = -90
		container.Visible = false
	end

	function itemList:Destroy()
		self.Backdrop:Destroy()
	end

	function itemList:Parent(parent)
		self.CurrentParent = parent
		backdrop.Parent = parent and parent.Container or nil
	end
	local headerButton = Instance.new("TextButton")
	headerButton.Parent = header
	headerButton.Size = UDim2.new(1, 0, 1, 0)
	headerButton.BackgroundTransparency = 1
	headerButton.Text = ""

	headerButton.MouseButton1Click:Connect(function()
		if itemList.IsShown then
			itemList:Hide()
		else
			itemList:Show()
		end
	end)

	return itemList :: any
end

function PluginUI.createButtonWithIcon(list: ItemList, text: string, icon: string, imageRectOffset: Vector2, imageRectSize: Vector2, callback: (() -> ())?): TriggerUIItem
	local button = Instance.new("Frame")
	button:AddTag("JEXP_Background")
	button:AddTag("JEXP_Hover")
	
	button.Name = "ButtonWithIconItem"
	button.Size = UDim2.new(1, 0, 0, 24)
	button.BorderSizePixel = 0
	
	local iconLabel = Instance.new("ImageLabel")
	iconLabel.Name = "Icon"
	iconLabel.Size = UDim2.new(0, 16, 0, 16)
	iconLabel.Position = UDim2.new(0, 8, 0.5, -8)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Image = icon
	iconLabel.ImageRectSize = imageRectSize
	iconLabel.ImageRectOffset = imageRectOffset
	iconLabel.Parent = button
	
	-- Label
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label:AddTag("JEXP_Text")
	
	label.Size = UDim2.new(1, -32, 1, 0)
	label.Position = UDim2.new(0, 32, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = text or "Button"
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.SourceSans
	label.TextSize = 14
	label.Parent = button
	
	-- Click handling
	local clickButton = Instance.new("TextButton")
	clickButton.Name = "Click"
	clickButton.Size = UDim2.new(1, 0, 1, 0)
	clickButton.BackgroundTransparency = 1
	clickButton.Text = ""
	clickButton.Parent = button
	
	list:AddItem(button)
	
	local callbacks: {any} = {callback}
	local item: TriggerUIItem = {
		Instance = button,
		Trigger = function(self)
			for _, v in callbacks do
				v()
			end
		end,
		OnTrigger = function(self, fn)
			table.insert(callbacks, fn)
			return connection(callbacks, fn)
		end,
		Destroy = function(self)
			table.clear(callbacks)
			table.clear(self)
			button:Destroy()
		end,
	}
	
	clickButton.Activated:Connect(function()
		for _, v in callbacks do
			v()
		end
	end)
	
	return item
end

function PluginUI.createCheckBox(list: ItemList?, text: string?, checked: boolean?, callback: ((boolean) -> ())?): ValueUIItem
	local checkBox = Instance.new("Frame")
	checkBox.Name = "CheckBoxItem"
	checkBox.BackgroundTransparency = 1
	
	checkBox.Size = UDim2.new(1, 0, 0, 20)
	checkBox.BorderSizePixel = 0
	
	local checkBoxVisual = Instance.new("Frame")
	checkBoxVisual.Name = "CheckBox"
	checkBoxVisual:AddTag("JEXP_LightBackground")
	checkBoxVisual:AddTag("JEXP_Border")
	
	checkBoxVisual.Parent = checkBox
	checkBoxVisual.Size = UDim2.new(0, 16, 0, 16)
	checkBoxVisual.Position = UDim2.new(0.55, 0, 0.5, -8)
	checkBoxVisual.BorderSizePixel = 0
	
	local checkMark = Instance.new("TextLabel")
	checkMark.Name = "CheckMark"
	checkMark:AddTag("JEXP_Text")
	
	checkMark.Parent = checkBoxVisual
	checkMark.Size = UDim2.new(1, 0, 1, 0)
	checkMark.BackgroundTransparency = 1
	checkMark.Text = "✓"
	checkMark.TextScaled = true
	checkMark.Font = Enum.Font.SourceSansBold
	checkMark.Visible = checked or false
	
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label:AddTag("JEXP_Text")
	
	label.Parent = checkBox
	label.Size = UDim2.new(1, -32, 1, 0)
	label.Position = UDim2.new(0.05, 0, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = text or "Checkbox"
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.SourceSans
	label.TextSize = 12
	
	local isChecked = checked or false
	local button = Instance.new("TextButton")
	button.Parent = checkBox
	button.Size = UDim2.new(1, 0, 1, 0)
	button.BackgroundTransparency = 1
	button.Text = ""
	
	if list then
		list:AddItem(checkBox)
	end
	
	local callbacks: {any} = {callback}
	
	local item: ValueUIItem = {
		Instance = checkBox :: any,
		Get = function(self)
			return isChecked
		end,
		Set = function(self, v)
			isChecked = v
			checkMark.Visible = v
		end,
		SetText = function(self, new)
			local is = new == "true"
			checkMark.Visible = is
			isChecked = is
		end,
		OnChange = function(self, fn)
			table.insert(callbacks, fn)
			return connection(callbacks, fn)
		end,
		Destroy = function(self)
			table.clear(callbacks)
			table.clear(self)
			checkBox:Destroy()
		end,
		SetEditable = function(self, editable)
			if not editable then
				label:RemoveTag("JEXP_Text")
				label:AddTag("JEXP_FadedText")
				checkBoxVisual:RemoveTag("JEXP_LightBackground")
				checkBoxVisual:AddTag("JEXP_DarkBackground")
				checkMark:RemoveTag("JEXP_Text")
				checkMark:AddTag("JEXP_FadedText")
				button.Interactable = false
				button.Active = false
				return
			end
			label:AddTag("JEXP_Text")
			label:RemoveTag("JEXP_FadedText")
			checkBoxVisual:AddTag("JEXP_LightBackground")
			checkBoxVisual:RemoveTag("JEXP_DarkBackground")
			checkMark:AddTag("JEXP_Text")
			checkMark:RemoveTag("JEXP_FadedText")
			button.Interactable = true
			button.Active = true
		end,
		GetName = function(self)
			return label.Text
		end,
		SetName = function(self, new)
			label.Text = new
		end,
	}

	button.MouseButton1Click:Connect(function()
		isChecked = not isChecked
		checkMark.Visible = isChecked
		
		for _, v in callbacks do
			v(isChecked)
		end
	end)
	
	return item
end

function PluginUI.createButton(list: ItemList, text: string?, callback: (() -> ())?, isimage: boolean?): TriggerUIItem
	local isimage = if isimage == nil then false else isimage
	local button = Instance.new("Frame")
	button:AddTag("JEXP_Background")
	button:AddTag("JEXP_Hover")
	
	button.BorderSizePixel = 0
	button.Name = "ButtonItem"
	button.Size = UDim2.new(1, 0, 0, 24)
	
	-- Label
	local label = Instance.new(isimage and "ImageLabel" or "TextLabel")
	label.Name = "Label"
	label:AddTag("JEXP_Text")
	
	label.BorderSizePixel = 0
	label.Size = UDim2.new(1, -16, 1, 0)
	label.Position = UDim2.new(0, 8, 0, 0)
	label.BackgroundTransparency = 1
	if isimage then
		label.Image = text or ""
	else
		label.Text = text or "Button"
	end
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.SourceSans
	label.TextSize = 14
	label.Parent = button
	
	-- Click handling
	local clickButton = Instance.new("TextButton")
	clickButton.BorderSizePixel = 0
	clickButton.Size = UDim2.new(1, 0, 1, 0)
	clickButton.BackgroundTransparency = 1
	clickButton.Text = ""
	clickButton.Parent = button
	
	if list then
		list:AddItem(button)
	end
	
	local callbacks: {any} = {callback}
	local item: TriggerUIItem = {
		Instance = button,
		Trigger = function(self)
			for _, v in callbacks do
				v()
			end
		end,
		OnTrigger = function(self, fn)
			table.insert(callbacks, fn)
			return connection(callbacks, fn)
		end,
		Destroy = function(self)
			table.clear(callbacks)
			table.clear(self)
			button:Destroy()
		end,
	}

	clickButton.Activated:Connect(function()
		for _, v in callbacks do
			v()
		end
	end)
	
	return item
end

function PluginUI.createAttributeBox(list: ItemList?, attributeName: string?, attributeValue: any?, callback: ((string) -> ())?, nameLabelIsBox: boolean?)
	local attrBox = Instance.new("Frame")
	attrBox.Name = "AttributeBoxItem"
	attrBox.BackgroundTransparency = 1
	
	attrBox.Size = UDim2.new(1, 0, 0, 20)
	attrBox.BorderSizePixel = 0
	
	-- Attribute name label
	local nameLabel = Instance.new(nameLabelIsBox and "TextBox" or "TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.BorderSizePixel = 0
	nameLabel:AddTag("JEXP_Text")
	
	nameLabel.Size = UDim2.new(0.5 - 0.1, 0, 1 - 0.1, 0)
	nameLabel.AnchorPoint = Vector2.new(0, 0.5)
	nameLabel.Position = UDim2.new(0 + 0.05, 0, 0.5, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = attributeName or "Attribute Name"
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Font = Enum.Font.SourceSans
	nameLabel.TextSize = 12
	nameLabel.ZIndex = 4
	nameLabel.Parent = attrBox
	
	--borderFrame(UDim2.fromScale(0, 0), UDim2.fromScale(0.5, 1), attrBox)
	
	-- Value input box
	local valueBox = Instance.new("TextBox")
	valueBox.Name = "ValueBox"
	valueBox:AddTag("JEXP_Text")
	
	valueBox.BorderSizePixel = 0
	valueBox.TextTruncate = Enum.TextTruncate.AtEnd
	valueBox.ClearTextOnFocus = false
	valueBox.AnchorPoint = Vector2.new(1, 0.5)
	valueBox.Size = UDim2.new(0.5 - 0.1, 0, 1 - 0.1, 0)
	valueBox.Position = UDim2.new(1 - 0.05, 0, 0.5, 0)
	valueBox.Text = tostring(attributeValue or "")
	valueBox.TextXAlignment = Enum.TextXAlignment.Left
	valueBox.Font = Enum.Font.SourceSans
	valueBox.BackgroundTransparency = 1
	valueBox.TextSize = 12
	valueBox.PlaceholderText = "Enter value..."
	valueBox.PlaceholderColor3 = Color3.fromRGB(128, 128, 128)
	valueBox.ZIndex = 4
	valueBox.Parent = attrBox
	
	--borderFrame(UDim2.fromScale(0.5, 0), UDim2.fromScale(0.5, 1), valueBox)
	
	if list then
		list:AddItem(attrBox)
	end
	
	local iseditable = true
	local callbacks: {any} = { callback}
	local item: ValueUIItem<(v: string) -> ()> = {
		Instance = attrBox :: any,
		Get = function(self)
			return valueBox.Text
		end,
		Set = function(self, v)
			valueBox.Text = v
		end,
		SetText = function(self, new)
			valueBox.Text = new
		end,
		OnChange = function(self, fn)
			table.insert(callbacks, fn)
			return connection(callbacks, fn)
		end,
		Destroy = function(self)
			table.clear(callbacks)
			table.clear(self)
			attrBox:Destroy()
		end,
		SetEditable = function(self, editable)
			iseditable = editable
			if not editable then
				nameLabel:RemoveTag("JEXP_Text")
				nameLabel:AddTag("JEXP_FadedText")
				valueBox:RemoveTag("JEXP_Text")
				valueBox:AddTag("JEXP_FadedText")
				valueBox.TextEditable = false
				return
			end
			nameLabel:AddTag("JEXP_Text")
			nameLabel:RemoveTag("JEXP_FadedText")
			valueBox:AddTag("JEXP_Text")
			valueBox:RemoveTag("JEXP_FadedText")
			valueBox.TextEditable = true
		end,
		GetName = function(self)
			return nameLabel.Text
		end,
		SetName = function(self, new)
			nameLabel.Text = new
		end,
	}
	
	local lastValue = attributeValue
	valueBox.Focused:Connect(function()
		lastValue = valueBox.Text
	end)
	valueBox.FocusLost:Connect(function(enterPressed)
		--if not enterPressed then
		--	if lastValue then
		--		valueBox.Text = lastValue
		--	end
		--	return
		--end
		if not iseditable then return end
		for _, v in callbacks do
			v(valueBox.Text)
		end
	end)
	
	return item
end

function PluginUI.createSeparator(list: ItemList): Frame
	local separator = Instance.new("Frame")
	separator.Name = "Separator"
	separator:AddTag("JEXP_LightBackground")
	
	separator.Size = UDim2.new(1, 0, 0, 1)
	separator.BorderSizePixel = 0

	list:AddItem(separator)
	return separator
end

function PluginUI.createHeader(list: ItemList?, text: string?): Frame
	local header = Instance.new("Frame")
	header.Name = "HeaderItem"
	header:AddTag("JEXP_DarkBackground")
	
	header.Size = UDim2.new(1, 0, 0, 25)
	header.BorderSizePixel = 0

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label:AddTag("JEXP_Text")
	
	label.Size = UDim2.new(1, -16, 1, 0)
	label.Position = UDim2.new(0, 8, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = text or "Header"
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Font = Enum.Font.SourceSansBold
	label.TextSize = 12
	label.Parent = header

	if list then
		list:AddItem(header)
	end
	return header
end

local visibleEnumLists: {EnumBox} = {}
type EnumBox = {
	ReconstructEnumList: (self: any, enumType: Enum, selectedValue: EnumItem?) -> (),
	IsOpen: boolean,
	List: ItemList
} & ValueUIItem

function PluginUI.clearOpenEnumLists()
	for _, v in visibleEnumLists do
		v.IsOpen = false
		v.List:Hide()
	end
	table.clear(visibleEnumLists)
end

function PluginUI.createEnumBox(
	list: ItemList?,
	attributeName: string?,
	enumType: Enum?,
	selectedValue: any?,
	callback: ((EnumItem) -> ())?, 
	listParent: Instance?,
	onList: ((list: Instance) -> ())?,
	onAnchor: ((pos: Vector2, size: Vector2) -> (Vector2, UDim2))?
)
	: (EnumBox, ItemList)
	local enumBox = Instance.new("Frame")
	enumBox.Name = "EnumBoxItem"
	enumBox.BackgroundTransparency = 1

	enumBox.Size = UDim2.new(1, 0, 0, 20)
	enumBox.BorderSizePixel = 0
	
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.BorderSizePixel = 0
	nameLabel:AddTag("JEXP_Text")

	nameLabel.Size = UDim2.new(0.5 - 0.1, 0, 1 - 0.1, 0)
	nameLabel.AnchorPoint = Vector2.new(0, 0.5)
	nameLabel.Position = UDim2.new(0 + 0.05, 0, 0.5, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = attributeName or "Enum Property"
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Font = Enum.Font.SourceSans
	nameLabel.TextSize = 12
	nameLabel.ZIndex = 4
	nameLabel.Parent = enumBox
	
	local valueButton = Instance.new("TextButton")
	valueButton.Name = "ValueButton"
	valueButton:AddTag("JEXP_LightBackground")
	valueButton:AddTag("JEXP_Text")
	valueButton:AddTag("JEXP_Hover")

	valueButton.BorderSizePixel = 0
	valueButton.TextTruncate = Enum.TextTruncate.AtEnd
	valueButton.AnchorPoint = Vector2.new(1, 0.5)
	valueButton.Size = UDim2.new(0.5 - 0.1, 0, 1 - 0.1, 0)
	valueButton.Position = UDim2.new(1 - 0.05, 0, 0.5, 0)
	valueButton.Text = selectedValue and selectedValue.Name or ""
	valueButton.TextXAlignment = Enum.TextXAlignment.Left
	valueButton.Font = Enum.Font.SourceSans
	valueButton.TextSize = 12
	valueButton.ZIndex = 4
	valueButton.Parent = enumBox
	
	local arrow = Instance.new("ImageLabel")
	arrow.Name = "Arrow"
	arrow:AddTag("JEXP_Arrow")
	arrow.Size = UDim2.new(0, 12, 0, 12)
	arrow.Position = UDim2.new(1, -16, 0.5, -6)
	arrow.BackgroundTransparency = 1
	arrow.Parent = valueButton
	
	local dropdownList = PluginUI.createItemList({
		Size = UDim2.new(0.5 - 0.1, 0, 0, 150),
		ZIndex = 2000,
		Parent = enumBox
	})
	
	if onList then
		onList(dropdownList.Backdrop)
	end
	
	local currentValue = selectedValue
	local callbacks: {any} = {callback}
	
	local enumButtons: {TriggerUIItem} = {}

	local item: EnumBox = {
		List = dropdownList,
		IsOpen = false,
		Instance = enumBox :: any,
		Get = function(self)
			return currentValue
		end,
		Set = function(self, v)
			currentValue = v
			valueButton.Text = tostring(v)
		end,
		SetText = function(self, v)
			valueButton.Text = v
		end,
		OnChange = function(self, fn)
			table.insert(callbacks, fn)
			return connection(callbacks, fn)
		end,
		Destroy = function(self: any)
			table.clear(callbacks)
			table.clear(self)
			dropdownList:Destroy()
			enumBox:Destroy()
		end,
		SetEditable = function(self, editable)
			if not editable then
				nameLabel:RemoveTag("JEXP_Text")
				nameLabel:AddTag("JEXP_FadedText")
				valueButton:RemoveTag("JEXP_Text")
				valueButton:AddTag("JEXP_FadedText")
				valueButton:RemoveTag("JEXP_LightBackground")
				valueButton:AddTag("JEXP_DarkBackground")
				valueButton.Interactable = false
				valueButton.Active = false
				return
			end
			nameLabel:AddTag("JEXP_Text")
			nameLabel:RemoveTag("JEXP_FadedText")
			valueButton:AddTag("JEXP_Text")
			valueButton:RemoveTag("JEXP_FadedText")
			valueButton:AddTag("JEXP_LightBackground")
			valueButton:RemoveTag("JEXP_DarkBackground")
			valueButton.Interactable = true
			valueButton.Active = true
		end,
		GetName = function(self)
			return nameLabel.Text
		end,
		SetName = function(self, new)
			nameLabel.Text = new
		end,
		ReconstructEnumList = function(self: EnumBox, enumType: Enum, selectedValue: EnumItem?)
			local enumValues = {}
			for _, v in enumButtons do
				v:Destroy()
			end
			table.clear(enumButtons)
			if selectedValue then
				valueButton.Text = selectedValue.Name
			end
			for _, item in enumType:GetEnumItems() do
				table.insert(enumValues, item)
			end

			table.sort(enumValues, function(a, b) return a.Name < b.Name end)
			for _, enum: EnumItem in enumValues do
				local enumName = enum.Name
				local enumButton = PluginUI.createButton(dropdownList, enumName, function()
					valueButton.Text = enumName
					currentValue = enumName
					dropdownList:Hide()
					self.IsOpen = false

					for _, fn in callbacks do
						fn(enum)
					end
				end)
				table.insert(enumButtons, enumButton)
			end
		end,
	}
	
	if enumType then
		local enumValues = {}
		for _, item in enumType:GetEnumItems() do
			table.insert(enumValues, item)
		end

		table.sort(enumValues, function(a, b) return a.Name < b.Name end)
		for _, enum: EnumItem in enumValues do
			local enumName = enum.Name
			local enumButton = PluginUI.createButton(dropdownList, enumName, function()
				valueButton.Text = enumName
				currentValue = enumName
				dropdownList:Hide()
				item.IsOpen = false

				for _, fn in callbacks do
					fn(enum)
				end
			end)
			table.insert(enumButtons, enumButton)
		end
	end

	if list then
		list:AddItem(enumBox)
	end

	valueButton.Activated:Connect(function()
		if item.IsOpen then
			dropdownList:Hide()
			item.IsOpen = false
		else
			PluginUI.clearOpenEnumLists()
			
			local absolutePos = valueButton.AbsolutePosition
			local absoluteSize = valueButton.AbsoluteSize
			
			if onAnchor then
				dropdownList:SetAnchor(onAnchor(absolutePos, absoluteSize))
			else
				dropdownList:SetAnchor(Vector2.new(1, 0), UDim2.fromOffset(absolutePos.X, absolutePos.Y))
			end
			dropdownList:Show()
			table.insert(visibleEnumLists, item)
			
			item.IsOpen = true
		end
	end)
	
	return item::any, dropdownList
end

function PluginUI.createDropdownBox(list: ItemList?, attributeName: string?, attributeValue: any?, callback: ((string) -> ())?, dropdownItems: {(parentItem: ValueUIItem) -> ValueUIItem}?): (ValueUIItem, {ValueUIItem})
	local dropdownBox = Instance.new("Frame")
	dropdownBox.Name = "DropdownBoxItem"
	dropdownBox.BackgroundTransparency = 1
	
	dropdownBox.Size = UDim2.new(1, 0, 0, 20)
	--dropdownBox.ClipsDescendants = false
	dropdownBox.AutomaticSize = Enum.AutomaticSize.Y
	dropdownBox.BorderSizePixel = 0
	
	local absSize = dropdownBox.AbsoluteSize
	
	local expandArrow = Instance.new("ImageButton")
	expandArrow.Name = "ExpandArrow"
	expandArrow:AddTag("JEXP_Arrow")
	
	expandArrow.Size = UDim2.new(0, 12, 0, 12)
	expandArrow.Position = UDim2.new(0, 8, 0, (0.5 * absSize.Y) - 6)
	expandArrow.BackgroundTransparency = 1
	expandArrow.Rotation = -90
	expandArrow.Parent = dropdownBox
	
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.BorderSizePixel = 0
	nameLabel:AddTag("JEXP_Text")
	nameLabel:AddTag("JEXP_Hover")
	
	nameLabel.Size = UDim2.new(0.5 - 0.1, -20, 0, (1 - 0.1) * absSize.Y)
	nameLabel.AnchorPoint = Vector2.new(0, 0.5)
	nameLabel.Position = UDim2.new(0 + 0.05, 20, 0, 0.5 * absSize.Y)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = attributeName or "Dropdown Property"
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Font = Enum.Font.SourceSans
	nameLabel.TextSize = 12
	nameLabel.ZIndex = 4
	nameLabel.Parent = dropdownBox
	
	local valueBox = Instance.new("TextBox")
	valueBox.Name = "ValueBox"
	valueBox:AddTag("JEXP_Text")
	
	valueBox.BorderSizePixel = 0
	valueBox.TextTruncate = Enum.TextTruncate.AtEnd
	valueBox.ClearTextOnFocus = false
	valueBox.AnchorPoint = Vector2.new(1, 0.5)
	valueBox.Size = UDim2.new(0.5 - 0.1, 0, 0, (1 - 0.1) * absSize.Y)
	valueBox.Position = UDim2.new(1 - 0.05, 0, 0, 0.5 * absSize.Y)
	valueBox.Text = attributeValue or ""
	valueBox.TextXAlignment = Enum.TextXAlignment.Left
	valueBox.Font = Enum.Font.SourceSans
	valueBox.BackgroundTransparency = 1
	valueBox.TextSize = 12
	valueBox.PlaceholderText = "Enter value..."
	valueBox.PlaceholderColor3 = Color3.fromRGB(128, 128, 128)
	valueBox.ZIndex = 4
	valueBox.Parent = dropdownBox
	
	local dropdownList = PluginUI.createItemList({
		AutomaticSize = Enum.AutomaticSize.XY,
		Position = UDim2.new(0, 0, 0, absSize.Y + 2),
		ZIndex = 2000,
		BackgroundTransparency = 0,
		--Visible = true,
		Parent = dropdownBox
	})
	dropdownList.Backdrop:RemoveTag("JEXP_Border")
	dropdownList.Backdrop.AutomaticSize = Enum.AutomaticSize.Y
	dropdownList.Backdrop.Size = UDim2.new(1, 0, 0, 0)
	dropdownList.Container.Size = UDim2.new(1, 0, 0, 0)
	dropdownList.Container.AutomaticSize = Enum.AutomaticSize.Y
	dropdownList.Container.AutomaticCanvasSize = Enum.AutomaticSize.Y
	dropdownList.Container.Position = UDim2.new(0, 20, 0, 0)
	if dropdownItems then
		dropdownList.Container.CanvasSize = UDim2.new(1, 0, 0, (#dropdownItems + 0) * absSize.Y)
	end
	
	local callbacks: {any} = {callback}
	local items: {ValueUIItem} = {}
	local isExpanded = false
	
	if list then
		list:AddItem(dropdownBox)
	end
	
	local iseditable = false

	local item: ValueUIItem<(v: string) -> ()> = {
		Instance = dropdownBox :: any,
		Get = function(self)
			return valueBox.Text
		end,
		Set = function(self, v)
			valueBox.Text = v
		end,
		SetText = function(self, new)
			valueBox.Text = new
		end,
		OnChange = function(self, fn)
			table.insert(callbacks, fn)
			return connection(callbacks, fn)
		end,
		Destroy = function(self)
			table.clear(callbacks)
			table.clear(self)
			dropdownList:Destroy()
			dropdownBox:Destroy()
		end,
		SetEditable = function(self, editable)
			iseditable = editable
			for _, v in items do
				v:SetEditable(editable)
			end
			
			if not editable then
				nameLabel:RemoveTag("JEXP_Text")
				nameLabel:AddTag("JEXP_FadedText")
				valueBox:RemoveTag("JEXP_Text")
				valueBox:AddTag("JEXP_FadedText")
				valueBox.TextEditable = false
				nameLabel.Interactable = false
				nameLabel.Active = false
				return
			end
			nameLabel:AddTag("JEXP_Text")
			nameLabel:RemoveTag("JEXP_FadedText")
			valueBox:AddTag("JEXP_Text")
			valueBox:RemoveTag("JEXP_FadedText")
			valueBox.TextEditable = true
			nameLabel.Interactable = true
			nameLabel.Active = true
		end,
		GetName = function(self)
			return nameLabel.Text
		end,
		SetName = function(self, new)
			nameLabel.Text = new
		end,
	}
	
	if dropdownItems then
		for _, createChildItem in dropdownItems do
			local childItem = createChildItem(item)
			dropdownList:AddItem(childItem.Instance)
			table.insert(items, childItem)
		end
	end
	
	local function toggleDropdown()
		if isExpanded then
			dropdownList:Hide()
			expandArrow.Rotation = -90
			isExpanded = false
		else
			dropdownList:Show()
			expandArrow.Rotation = 0
			isExpanded = true
		end
	end

	expandArrow.Activated:Connect(toggleDropdown)
	local lastValue = attributeValue
	valueBox.Focused:Connect(function()
		lastValue = valueBox.Text
	end)
	valueBox.FocusLost:Connect(function(enterPressed)
		--if not enterPressed then
		--	if lastValue then
		--		valueBox.Text = lastValue
		--	end
		--	return
		--end
		if not iseditable then return end
		for _, v in callbacks do
			v(valueBox.Text)
		end
	end)

	return item, items
end

function PluginUI.createInsertButton(parent: Instance?, fn: () -> ())
	local insertButton = Instance.new("TextButton")
	insertButton:AddTag("JEXP_Text")
	insertButton:AddTag("JEXP_LightBackground")

	insertButton.BorderSizePixel = 0
	insertButton.AnchorPoint = Vector2.new(1, 0.5)
	insertButton.Position = UDim2.fromScale(0.9, 0.5)
	insertButton.Size = UDim2.fromOffset(20, 20)
	insertButton.TextScaled = true
	insertButton.Text = "+"
	insertButton.BackgroundTransparency = 1
	insertButton.Activated:Connect(fn)
	
	insertButton.Parent = parent
	return insertButton
end

function PluginUI.createInsertButtonWithImage(parent: Instance?, image: string, fn: () -> ())
	local insertButton = Instance.new("ImageButton")
	insertButton:AddTag("JEXP_LightBackground")
	
	insertButton.BorderSizePixel = 0
	insertButton.AnchorPoint = Vector2.new(1, 0.5)
	insertButton.Position = UDim2.fromScale(0.9, 0.5)
	insertButton.Size = UDim2.fromOffset(20, 20)
	insertButton.Image = image
	insertButton.BackgroundTransparency = 1
	insertButton.Activated:Connect(fn)

	insertButton.Parent = parent
	return insertButton
end

function PluginUI.createDeleteButton(parent: Instance?, fn: () -> ())
	local deleteButton = Instance.new("TextButton")
	deleteButton:AddTag("JEXP_Text")
	deleteButton:AddTag("JEXP_LightBackground")

	deleteButton.BorderSizePixel = 0
	deleteButton.AnchorPoint = Vector2.new(1, 0.5)
	deleteButton.Position = UDim2.fromScale(0.85, 0.5)
	deleteButton.Size = UDim2.fromOffset(20, 20)
	deleteButton.TextScaled = true
	deleteButton.Text = "-"
	deleteButton.BackgroundTransparency = 1
	deleteButton.Activated:Connect(fn)
	
	deleteButton.Parent = parent
	return deleteButton
end

function PluginUI.createSideButtonImage(image: string, imageRectOffset: Vector2, imageRectSize: Vector2, container: GuiObject, bindex: number?)
	local bindex = bindex or 0
	local sideButton = Instance.new("ImageButton")
	sideButton:AddTag("JEXP_LightBackground")
	
	sideButton.BorderSizePixel = 0
	sideButton.AnchorPoint = Vector2.new(1, 0.5)
	sideButton.Position = UDim2.new(0, -(6 + (12 * bindex)), 0.5, 0)
	sideButton.Size = UDim2.fromOffset(12, 12)
	sideButton.Image = image
	sideButton.ImageRectOffset = imageRectOffset
	sideButton.ImageRectSize = imageRectSize
	
	local size = container.Size
	container.Size = UDim2.new(
		size.X.Scale,
		-(sideButton.Size.X.Offset + (6 + (12 * bindex))),
		size.Y.Scale,
		size.Y.Offset
	)
	sideButton.Parent = container
	
	return sideButton
end

function PluginUI.createSideButtonText(text: string, container: GuiObject, bindex: number?)
	local bindex = bindex or 0
	local sideButton = Instance.new("TextButton")
	sideButton:AddTag("JEXP_LightBackground")

	sideButton.BorderSizePixel = 0
	sideButton.AnchorPoint = Vector2.new(1, 0.5)
	sideButton.Position = UDim2.new(0, -(6 + (12 * bindex)), 0.5, 0)
	sideButton.Size = UDim2.fromOffset(12, 12)
	sideButton.Text = text
	
	local size = container.Size
	container.Size = UDim2.new(
		size.X.Scale,
		-(sideButton.Size.X.Offset + (6 + (12 * bindex))),
		size.Y.Scale,
		size.Y.Offset
	)
	sideButton.Parent = container

	return sideButton
end

local point = Path2DControlPoint.new
local ZERO = UDim2.fromScale(0, 0)
function PluginUI.createLine(parent: Instance?, p1: UDim2, p2: UDim2, xoffset1: number, radius1: number, xoffset2: number, radius2: number, color: Color3)
	local path = Instance.new("Path2D")
	path:SetControlPoints {
		point(p1, ZERO, ZERO),
		point(
			UDim2.new(0, p1.X.Offset + xoffset1, 0, p1.Y.Offset + radius1),
			UDim2.new(0, 0, 0, -radius1),
			UDim2.new(0, 0, 0, radius1)
		),
		point(
			UDim2.new(0, p2.X.Offset + xoffset2, 0, p2.Y.Offset - radius2),
			UDim2.new(0, 0, 0, -radius2),
			UDim2.new(0, 0, 0, radius2)
		),
		point(p2, ZERO, ZERO)
	}
	
	path.Parent = parent
	path.Color3 = color
	return path
end

function PluginUI.createCancelCreateButtons()
	local container = Instance.new("Frame")
	container.Name = "CreateConfirmContainer"
	container.BackgroundTransparency = 1

	container.Size = UDim2.new(1, 0, 0, 20)
	container.BorderSizePixel = 0
	
	local cancelButton: TriggerUIItem do
		local button = Instance.new("TextButton")
		button.Name = "button"
		button:AddTag("JEXP_LightBackground")
		button:AddTag("JEXP_Text")
		button:AddTag("JEXP_Hover")

		button.BorderSizePixel = 0
		button.TextTruncate = Enum.TextTruncate.AtEnd
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Size = UDim2.new(0.5 - 0.1, 0, 1 - 0.1, 0)
		button.Position = UDim2.new(1 - 0.05, 0, 0.5, 0)
		button.Text = "Cancel"
		button.TextXAlignment = Enum.TextXAlignment.Center
		button.Font = Enum.Font.SourceSans
		button.TextSize = 12
		button.ZIndex = 4
		button.Parent = container
		
		local callbacks = {}
		cancelButton = {
			Instance = button,
			OnTrigger = function(self, callback)
				table.insert(callbacks, callback)
				return connection(callbacks, callback)
			end,
			Trigger = function(self)
				for _, v in callbacks do
					v()
				end
			end,
			Destroy = function(self)
				button:Destroy()
			end,
		}
		button.Activated:Connect(function()
			for _, v in callbacks do
				v()
			end
		end)
	end
	
	local confirmButton: TriggerUIItem do
		local button = Instance.new("TextButton")
		button.Name = "button"
		button:AddTag("JEXP_SelectedColor")
		
		button.BorderSizePixel = 0
		button.TextTruncate = Enum.TextTruncate.AtEnd
		button.AnchorPoint = Vector2.new(0, 0.5)
		button.Size = UDim2.new(0.5 - 0.1, 0, 1 - 0.1, 0)
		button.Position = UDim2.new(0.05, 0, 0.5, 0)
		button.Text = "Confirm"
		button.TextXAlignment = Enum.TextXAlignment.Center
		button.Font = Enum.Font.SourceSans
		button.TextSize = 12
		button.ZIndex = 4
		button.Parent = container

		local callbacks = {}
		confirmButton = {
			Instance = button,
			OnTrigger = function(self, callback)
				table.insert(callbacks, callback)
				return connection(callbacks, callback)
			end,
			Trigger = function(self)
				for _, v in callbacks do
					v()
				end
			end,
			Destroy = function(self)
				button:Destroy()
			end,
		}
		button.Activated:Connect(function()
			for _, v in callbacks do
				v()
			end
		end)
	end
	
	return container, cancelButton, confirmButton
end

function PluginUI.createCreatorWidget(title: string, items: {ValueUIItem})
	local widget = plugin:CreateDockWidgetPluginGuiAsync(
		PluginUI.getId("Creator", true), DockWidgetPluginGuiInfo.new(
			Enum.InitialDockState.Float,
			true,
			true,
			200,
			100
		)
	)
	widget:AddTag("JEXP_Widget")
	local UITemplates = require("./UITemplates")
	local editorFrame = UITemplates.EditorFrame()
	editorFrame.Parent = widget
	
	widget.Name = "CREATORWIDGET"
	widget.Title = title
	widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	widget:BindToClose(function()
		widget.Enabled = not widget.Enabled
	end)

	editorFrame:AddTag("JEXP_Background")
	editorFrame.Parent = widget

	editorFrame.Items.Content:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local size = editorFrame.Items.Content.AbsoluteSize
		editorFrame.Items.Overlay.Size = UDim2.fromOffset(size.X, size.Y)
	end)
	
	local list = PluginUI.createItemListFromExisting(editorFrame, editorFrame.Items.Content, editorFrame.Items)
	for _, v in items do
		list:AddItem(v.Instance)
	end
	
	local container, cancel, confirm = PluginUI.createCancelCreateButtons()
	list:AddItem(container)
	widget:BindToClose(function()
		widget.Enabled = false
		widget:Destroy()
	end)
	
	return widget, cancel, confirm, function()
		widget.Enabled = false
		task.wait(0.1)
		widget:Destroy()
	end
end

return PluginUI